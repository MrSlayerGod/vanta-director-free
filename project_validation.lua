-- One scene schema for imports, recovery drafts and reusable presets. The server always validates again.
DirectorProject = {}
local boundedPayload = DirectorPayload.bounded
local denseList = DirectorPayload.denseList

function DirectorProject.validate(project)
    if not boundedPayload(project) then
        return false, "Project payload is too large or malformed."
    end
    if
        type(project) == "table"
        and project.version ~= nil
        and (
            type(project.version) ~= "number"
            or project.version % 1 ~= 0
            or project.version < 1
            or project.version > 4
        )
    then
        return false, "Unsupported project version. Keep the original export and use a compatible Director version."
    end
    if type(project) ~= "table" or not denseList(project.keyframes, Config.MaximumKeyframes) then
        return false, "Invalid project data."
    end

    if #project.keyframes > Config.MaximumKeyframes then
        return false, "This project has too many keyframes."
    end

    local duration = tonumber(project.duration)
    if
        not duration
        or duration ~= duration
        or duration < Config.MinimumDuration
        or duration > Config.MaximumDuration
    then
        return false, "Project duration is out of range."
    end

    for _, frame in ipairs(project.keyframes) do
        if type(frame) ~= "table" then
            return false, "Invalid keyframe data."
        end
        for _, field in ipairs({ "time", "x", "y", "z", "rx", "ry", "rz", "fov" }) do
            local value = tonumber(frame[field])
            if not value or value ~= value or value == math.huge or value == -math.huge then
                return false, ("Invalid keyframe value: %s"):format(field)
            end
            if field ~= "time" and field ~= "fov" and math.abs(value) > 100000 then
                return false, ("Keyframe value out of range: %s"):format(field)
            end
        end
    end

    local name = tostring(project.name or "Untitled Project"):sub(1, 64)
    local cleanFrames = {}
    for _, frame in ipairs(project.keyframes) do
        cleanFrames[#cleanFrames + 1] = {
            time = math.max(0.0, math.min(duration, tonumber(frame.time))),
            name = tostring(frame.name or ""):gsub("[\r\n]", " "):sub(1, 48),
            x = tonumber(frame.x),
            y = tonumber(frame.y),
            z = tonumber(frame.z),
            rx = tonumber(frame.rx),
            ry = tonumber(frame.ry),
            rz = tonumber(frame.rz),
            fov = math.max(20.0, math.min(100.0, tonumber(frame.fov))),
        }
    end

    local sourceLook = project.look or {}
    if type(sourceLook) ~= "table" then
        return false, "Invalid scene look."
    end
    local allowedWeather = {
        SERVER = true,
        EXTRASUNNY = true,
        CLEAR = true,
        CLOUDS = true,
        OVERCAST = true,
        RAIN = true,
        THUNDER = true,
        FOGGY = true,
        SMOG = true,
        CLEARING = true,
    }
    local weather = sourceLook.weather or "SERVER"
    if type(weather) ~= "string" or not allowedWeather[weather] then
        return false, "Invalid weather."
    end
    local function lookNumber(field, fallback, minimum, maximum, integer)
        local value = sourceLook[field] == nil and fallback or tonumber(sourceLook[field])
        if not value or value ~= value or value < minimum or value > maximum or (integer and value % 1 ~= 0) then
            return nil
        end
        return value
    end
    local hour = lookNumber("hour", -1, -1, 23, true)
    local minute = lookNumber("minute", 0, 0, 59, true)
    local near = lookNumber("near", 2.0, 0.1, 100.0, false)
    local far = lookNumber("far", 30.0, 0.2, 500.0, false)
    local strength = lookNumber("strength", 0.5, 0.0, 1.0, false)
    if
        not hour
        or not minute
        or not near
        or not far
        or not strength
        or far <= near
        or (sourceLook.dof ~= nil and type(sourceLook.dof) ~= "boolean")
    then
        return false, "Invalid scene look."
    end

    local safeProject = {
        version = 4,
        name = name,
        duration = duration,
        keyframes = cleanFrames,
        actors = {},
        look = {
            weather = weather,
            hour = hour,
            minute = minute,
            dof = sourceLook.dof == true,
            near = near,
            far = far,
            strength = strength,
        },
    }

    local actors = project.actors or {}
    if not denseList(actors, Config.MaximumActors) then
        return false, "Invalid actor list."
    end
    local seenActorIds = {}
    for actorIndex, actor in ipairs(actors) do
        local actorId = type(actor) == "table" and (actor.id or actorIndex)
        if
            type(actorId) ~= "number"
            or actorId % 1 ~= 0
            or actorId < 1
            or actorId > 1000000
            or seenActorIds[actorId]
        then
            return false, "Invalid or duplicate actor ID."
        end
        seenActorIds[actorId] = true
        if
            type(actor) ~= "table"
            or (actor.kind ~= "ped" and actor.kind ~= "vehicle" and actor.kind ~= "prop")
            or type(actor.model) ~= "string"
            or not actor.model:match("^[%w_]+$")
            or #actor.model > 48
        then
            return false, "Invalid actor."
        end
        local clean = { kind = actor.kind, model = actor.model, actions = {} }
        local appearanceOk, appearance = DirectorAppearance.validate(actor.kind, actor.appearance)
        if not appearanceOk then
            return false, appearance
        end
        clean.name = tostring(actor.name or ""):gsub("[\r\n]", " "):sub(1, 48)
        clean.group = tostring(actor.group or ""):gsub("[\r\n]", " "):sub(1, 32)
        clean.appearance = appearance
        local attachOk, attachment = DirectorAttachments.validate(actor.kind, actor.attachment)
        if not attachOk then
            return false, attachment
        end
        clean.attachment = attachment
        for _, field in ipairs({ "x", "y", "z", "heading" }) do
            local value = tonumber(actor[field])
            if not value or value ~= value or math.abs(value) > 100000 then
                return false, "Invalid actor position."
            end
            clean[field] = value
        end
        local actions = actor.actions or {}
        if not denseList(actions, Config.MaximumActionsPerActor) then
            return false, "Invalid action list."
        end
        for _, action in ipairs(actions) do
            if
                type(action) ~= "table"
                or type(action.time) ~= "number"
                or action.time ~= action.time
                or action.time < 0
                or action.time > duration
            then
                return false, "Invalid action time."
            end
            local entry = { type = action.type, time = action.time, id = #clean.actions + 1 }
            if action.type == "recording" and (actor.kind == "ped" or actor.kind == "vehicle") then
                local ok, samples = DirectorRecording.validate(action.samples)
                if not ok then
                    return false, samples
                end
                entry.samples = samples
                entry.duration = samples[#samples][1]
                local cues, message = DirectorRecording.validateCues(action.poseCues, entry.duration)
                if not cues or (actor.kind ~= "ped" and #cues > 0) then
                    return false, message or "Only ped takes support gestures."
                end
                entry.poseCues = cues
                local aimCues, aimMessage = DirectorRecording.validateAimCues(action.aimCues, entry.duration)
                if not aimCues or actor.kind ~= "ped" and #aimCues > 0 then
                    return false, aimMessage or "Only ped takes support aim cues."
                end
                entry.aimCues = aimCues
                if entry.time + entry.duration > duration + 0.001 or #actions ~= 1 then
                    return false, "Recorded takes must fit the timeline and use a dedicated actor."
                end
            elseif action.type == "move" then
                for _, field in ipairs({ "x", "y", "z", "duration" }) do
                    local value = tonumber(action[field])
                    if not value or value ~= value or math.abs(value) > 100000 then
                        return false, "Invalid move action."
                    end
                    entry[field] = value
                end
                if
                    entry.duration <= 0
                    or entry.duration > duration
                    or action.time + entry.duration > duration + 0.001
                then
                    return false, "Invalid move duration."
                end
                if action.points ~= nil then
                    if actor.kind ~= "ped" and actor.kind ~= "vehicle" then
                        return false, "Routes require a ped or vehicle."
                    end
                    local points, message = DirectorRoutes.validate(action.points)
                    if not points then
                        return false, message
                    end
                    entry.points = points
                    if action.coordinateSpace ~= nil and action.coordinateSpace ~= "entity" then
                        return false, "Invalid route coordinate space."
                    end
                    entry.coordinateSpace = action.coordinateSpace
                    local last = points[#points]
                    entry.x, entry.y, entry.z = last.x, last.y, last.z
                    if action.speed ~= nil then
                        local speed = tonumber(action.speed)
                        if not speed or speed ~= speed or speed < 0.1 or speed > 100 then
                            return false, "Invalid route speed."
                        end
                        entry.speed = speed
                    end
                end
                if actor.kind == "ped" then
                    local gait = action.gait or "auto"
                    if gait ~= "auto" and gait ~= "walk" and gait ~= "run" and gait ~= "sprint" then
                        return false, "Invalid ped movement style."
                    end
                    entry.gait = gait
                end
            elseif (action.type == "enterVehicle" or action.type == "exitVehicle") and actor.kind == "ped" then
                local target, seat, seconds =
                    tonumber(action.vehicleId), tonumber(action.seat), tonumber(action.duration)
                if
                    not target
                    or target % 1 ~= 0
                    or not seat
                    or seat % 1 ~= 0
                    or seat < -1
                    or seat > 15
                    or not seconds
                    or seconds ~= seconds
                    or seconds < 0.1
                    or seconds > 30
                    or action.time + seconds > duration + 0.001
                then
                    return false, "Invalid vehicle interaction."
                end
                entry.vehicleId, entry.seat, entry.duration = target, seat, seconds
                if action.instant ~= nil then
                    if action.type ~= "enterVehicle" or type(action.instant) ~= "boolean" then
                        return false, "Invalid captured seat cue."
                    end
                    entry.instant = action.instant
                end
                if action.type == "exitVehicle" then
                    for _, field in ipairs({ "x", "y", "z" }) do
                        local value = tonumber(action[field])
                        if not value or value ~= value or math.abs(value) > 100000 then
                            return false, "Invalid vehicle exit position."
                        end
                        entry[field] = value
                    end
                end
            elseif action.type == "lookAt" and actor.kind == "ped" then
                local seconds = tonumber(action.duration)
                if not seconds or seconds ~= seconds or seconds <= 0 or seconds > duration then
                    return false, "Invalid gaze duration."
                end
                entry.duration = math.min(seconds, duration - action.time)
                if entry.duration <= 0 then
                    return false, "Gaze is outside the timeline."
                end
                if action.targetId ~= nil then
                    local targetId = tonumber(action.targetId)
                    if not targetId or targetId % 1 ~= 0 then
                        return false, "Invalid gaze target."
                    end
                    entry.targetId = targetId
                else
                    for _, field in ipairs({ "x", "y", "z" }) do
                        local value = tonumber(action[field])
                        if not value or value ~= value or math.abs(value) > 100000 then
                            return false, "Invalid gaze point."
                        end
                        entry[field] = value
                    end
                end
            elseif action.type == "animation" and actor.kind == "ped" then
                if
                    type(action.dict) ~= "string"
                    or type(action.clip) ~= "string"
                    or not action.dict:match("^[%w_@%-]+$")
                    or not action.clip:match("^[%w_%-]+$")
                    or #action.dict > 80
                    or #action.clip > 80
                then
                    return false, "Invalid animation."
                end
                if action.loop ~= nil and type(action.loop) ~= "boolean" then
                    return false, "Invalid animation playback mode."
                end
                entry.dict, entry.clip, entry.loop = action.dict, action.clip, action.loop
                if action.duration ~= nil then
                    local seconds = tonumber(action.duration)
                    if
                        not seconds
                        or seconds ~= seconds
                        or seconds <= 0
                        or seconds > duration
                        or action.time + seconds > duration + 0.001
                    then
                        return false, "Animation duration must fit the timeline."
                    end
                    entry.duration = seconds
                end
            elseif action.type == "visibility" and actor.kind == "prop" then
                if type(action.visible) ~= "boolean" then
                    return false, "Invalid visibility action."
                end
                entry.visible = action.visible
            elseif (action.type == "engine" or action.type == "lights") and actor.kind == "vehicle" then
                if type(action.enabled) ~= "boolean" then
                    return false, "Invalid vehicle action."
                end
                entry.enabled = action.enabled
            elseif action.type == "door" and actor.kind == "vehicle" then
                local door = tonumber(action.door)
                if type(action.enabled) ~= "boolean" or not door or door % 1 ~= 0 or door < 0 or door > 5 then
                    return false, "Invalid vehicle door action."
                end
                entry.door, entry.enabled = door, action.enabled
            else
                return false, "Invalid action type."
            end
            clean.actions[#clean.actions + 1] = entry
        end
        safeProject.actors[#safeProject.actors + 1] = clean
    end

    local actorIndices = {}
    for index, actor in ipairs(actors) do
        actorIndices[actor.id or index] = index
    end
    for index, actor in ipairs(safeProject.actors) do
        if actor.attachment then
            local target = actorIndices[actor.attachment.parentId]
            if not target or safeProject.actors[target].kind ~= "ped" then
                return false, "Accessory ped is missing."
            end
            actor.attachment.parentId = target
            for _, step in ipairs(actor.actions) do
                if step.type ~= "visibility" then
                    return false, "Attached accessories only support visibility cues."
                end
            end
        end
        for _, action in ipairs(actor.actions) do
            if action.vehicleId then
                local target = actorIndices[action.vehicleId]
                if not target or safeProject.actors[target].kind ~= "vehicle" then
                    return false, "Interaction vehicle is missing."
                end
                action.vehicleId = target
            end
            if action.type == "lookAt" and action.targetId then
                local target = actorIndices[action.targetId]
                if not target or target == index then
                    return false, "Gaze subject is missing or is the ped itself."
                end
                action.targetId = target
            end
        end
    end

    local seatsOk, seatsMessage = DirectorSeats.validate(safeProject.actors, duration)
    if not seatsOk then
        return false, seatsMessage
    end

    if sourceLook.focusId ~= nil then
        local id = tonumber(sourceLook.focusId)
        local target = actorIndices[id]
        if not target then
            return false, "Focus subject is missing."
        end
        safeProject.look.focusId = target
    end
    local rig, message = DirectorShots.rig(project.cameraRig, actors)
    if not rig then
        return false, message
    end
    safeProject.cameraRig = rig
    local shots, message = DirectorShots.validate(project.cameraShots, duration, actors, #cleanFrames)
    if not shots then
        return false, message
    end
    safeProject.cameraShots = shots
    local bookmarks, message = DirectorStaging.bookmarks(project.bookmarks)
    if not bookmarks then
        return false, message
    end
    safeProject.bookmarks = bookmarks

    local encoded = json.encode(safeProject)
    if not encoded or #encoded > Config.ProjectFileLimit then
        return false, "Project file is too large."
    end

    return true, safeProject, encoded
end
