local function getOwnerKey(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == 'license:' then
            return identifier:gsub('[^%w_-]', '')
        end
    end

    return nil
end

local function projectPath(source)
    local owner = getOwnerKey(source)
    if not owner or owner == '' then
        return nil
    end

    return ('data/%s.json'):format(owner)
end

local function libraryPath(source)
    local owner = getOwnerKey(source)
    if not owner or owner == '' then return nil end
    return ('data/%s.library.json'):format(owner)
end

-- Reject oversized/deep structures before normalization, including ignored fields.
-- Network deserialization has already happened; this bounds subsequent Lua work.
local function boundedPayload(value)
    local nodes,bytes,seen=0,0,{}
    local function visit(v,depth)
        nodes=nodes+1
        if nodes>Config.PayloadNodeLimit or depth>24 then return false end
        local kind=type(v)
        if kind=='string' then bytes=bytes+#v;return bytes<=Config.ProjectFileLimit end
        if kind=='number' then return v==v and v~=math.huge and v~=-math.huge end
        if kind=='nil' or kind=='boolean' then return true end
        if kind~='table' or seen[v] then return false end
        seen[v]=true
        for k,item in pairs(v) do
            if (type(k)~='string' and type(k)~='number') or not visit(k,depth+1) or not visit(item,depth+1) then return false end
        end
        return true
    end
    return visit(value,0)
end
local function denseList(value,maximum)
    if type(value)~='table' or #value>maximum then return false end
    local count=0
    for key in pairs(value) do
        if type(key)~='number' or key%1~=0 or key<1 or key>#value then return false end
        count=count+1
        if count>maximum then return false end
    end
    return count==#value
end

local function validateProject(project)
    if not boundedPayload(project) then return false, 'Project payload is too large or malformed.' end
    local editionAllowed,editionReason=DirectorFree.project(project)
    if not editionAllowed then return false,editionReason end
    if type(project)=='table' and project.version~=nil and (type(project.version)~='number' or project.version%1~=0 or project.version<1 or project.version>4) then return false,'Unsupported project version. Keep the original export and use a compatible Director version.' end
    if type(project) ~= 'table' or not denseList(project.keyframes, Config.MaximumKeyframes) then
        return false, 'Invalid project data.'
    end

    if #project.keyframes > Config.MaximumKeyframes then
        return false, 'This project has too many keyframes.'
    end

    local duration = tonumber(project.duration)
    if not duration or duration~=duration or duration < Config.MinimumDuration or duration > Config.MaximumDuration then
        return false, 'Project duration is out of range.'
    end

    for _, frame in ipairs(project.keyframes) do
        if type(frame) ~= 'table' then
            return false, 'Invalid keyframe data.'
        end
        for _, field in ipairs({ 'time', 'x', 'y', 'z', 'rx', 'ry', 'rz', 'fov' }) do
            local value = tonumber(frame[field])
            if not value or value ~= value or value == math.huge or value == -math.huge then
                return false, ('Invalid keyframe value: %s'):format(field)
            end
            if field ~= 'time' and field ~= 'fov' and math.abs(value) > 100000 then
                return false, ('Keyframe value out of range: %s'):format(field)
            end
        end
    end

    local name = tostring(project.name or 'Untitled Project'):sub(1, 64)
    local cleanFrames = {}
    for _, frame in ipairs(project.keyframes) do
        cleanFrames[#cleanFrames + 1] = {
            time = math.max(0.0, math.min(duration, tonumber(frame.time))),
            name = tostring(frame.name or ''):gsub('[\r\n]', ' '):sub(1, 48),
            x = tonumber(frame.x),
            y = tonumber(frame.y),
            z = tonumber(frame.z),
            rx = tonumber(frame.rx),
            ry = tonumber(frame.ry),
            rz = tonumber(frame.rz),
            fov = math.max(20.0, math.min(100.0, tonumber(frame.fov)))
        }
    end

    local sourceLook = project.look or {}
    if type(sourceLook) ~= 'table' then return false, 'Invalid scene look.' end
    local allowedWeather = { SERVER = true, EXTRASUNNY = true, CLEAR = true, CLOUDS = true, OVERCAST = true, RAIN = true, THUNDER = true, FOGGY = true, SMOG = true, CLEARING = true }
    local weather = sourceLook.weather or 'SERVER'
    if type(weather) ~= 'string' or not allowedWeather[weather] then return false, 'Invalid weather.' end
    local function lookNumber(field, fallback, minimum, maximum, integer)
        local value = sourceLook[field] == nil and fallback or tonumber(sourceLook[field])
        if not value or value ~= value or value < minimum or value > maximum or (integer and value % 1 ~= 0) then return nil end
        return value
    end
    local hour = lookNumber('hour', -1, -1, 23, true)
    local minute = lookNumber('minute', 0, 0, 59, true)
    local near = lookNumber('near', 2.0, 0.1, 100.0, false)
    local far = lookNumber('far', 30.0, 0.2, 500.0, false)
    local strength = lookNumber('strength', 0.5, 0.0, 1.0, false)
    if not hour or not minute or not near or not far or not strength or far <= near or
        (sourceLook.dof ~= nil and type(sourceLook.dof) ~= 'boolean') then return false, 'Invalid scene look.' end

    local safeProject = {
        version = 4,
        name = name,
        duration = duration,
        keyframes = cleanFrames,
        actors = {},
        look = { weather = weather, hour = hour, minute = minute, dof = sourceLook.dof == true, near = near, far = far, strength = strength }
    }

    local actors = project.actors or {}
    if not denseList(actors, Config.MaximumActors) then return false, 'Invalid actor list.' end
    local seenActorIds={}
    for actorIndex, actor in ipairs(actors) do
        local actorId=type(actor)=='table' and (actor.id or actorIndex)
        if type(actorId)~='number' or actorId%1~=0 or actorId<1 or actorId>1000000 or seenActorIds[actorId] then return false,'Invalid or duplicate actor ID.' end
        seenActorIds[actorId]=true
        if type(actor) ~= 'table' or (actor.kind ~= 'ped' and actor.kind ~= 'vehicle' and actor.kind ~= 'prop') or
            type(actor.model) ~= 'string' or not actor.model:match('^[%w_]+$') or #actor.model > 48 then
            return false, 'Invalid actor.'
        end
        local clean = { kind = actor.kind, model = actor.model, actions = {} }
        local appearanceOk,appearance=DirectorAppearance.validate(actor.kind,actor.appearance)
        if not appearanceOk then return false,appearance end
        clean.name=tostring(actor.name or ''):gsub('[\r\n]',' '):sub(1,48)
        clean.group=tostring(actor.group or ''):gsub('[\r\n]',' '):sub(1,32)
        clean.appearance=appearance
        local attachOk,attachment=DirectorAttachments.validate(actor.kind,actor.attachment)
        if not attachOk then return false,attachment end
        clean.attachment=attachment
        for _, field in ipairs({ 'x', 'y', 'z', 'heading' }) do
            local value = tonumber(actor[field])
            if not value or value ~= value or math.abs(value) > 100000 then return false, 'Invalid actor position.' end
            clean[field] = value
        end
        local actions = actor.actions or {}
        if not denseList(actions, Config.MaximumActionsPerActor) then return false, 'Invalid action list.' end
        for _, action in ipairs(actions) do
            if type(action) ~= 'table' or type(action.time) ~= 'number' or action.time~=action.time or action.time < 0 or action.time > duration then
                return false, 'Invalid action time.'
            end
            local entry = { type = action.type, time = action.time, id = #clean.actions + 1 }
            if action.type=='recording' and (actor.kind=='ped' or actor.kind=='vehicle') then
                local ok,samples=DirectorRecording.validate(action.samples)
                if not ok then return false,samples end
                entry.samples=samples;entry.duration=samples[#samples][1]
                local cues,message=DirectorRecording.validateCues(action.poseCues,entry.duration)
                if not cues or (actor.kind~='ped' and #cues>0) then return false,message or 'Only ped takes support gestures.' end
                entry.poseCues=cues
                local aimCues,aimMessage=DirectorRecording.validateAimCues(action.aimCues,entry.duration)
                if not aimCues or actor.kind~='ped' and #aimCues>0 then return false,aimMessage or 'Only ped takes support aim cues.' end
                entry.aimCues=aimCues
                if entry.time+entry.duration>duration+.001 or #actions~=1 then return false,'Recorded takes must fit the timeline and use a dedicated actor.' end
            elseif action.type == 'move' then
                for _, field in ipairs({ 'x', 'y', 'z', 'duration' }) do
                    local value = tonumber(action[field])
                    if not value or value ~= value or math.abs(value) > 100000 then return false, 'Invalid move action.' end
                    entry[field] = value
                end
                if entry.duration <= 0 or entry.duration > duration or action.time+entry.duration>duration+.001 then return false, 'Invalid move duration.' end
                if action.points ~= nil then
                    if actor.kind~='ped' and actor.kind~='vehicle' then return false, 'Routes require a ped or vehicle.' end
                    local points,message=DirectorRoutes.validate(action.points)
                    if not points then return false,message end
                    entry.points=points
                    if action.coordinateSpace ~= nil and action.coordinateSpace ~= 'entity' then return false, 'Invalid route coordinate space.' end
                    entry.coordinateSpace=action.coordinateSpace
                    local last=points[#points]; entry.x,entry.y,entry.z=last.x,last.y,last.z
                    if action.speed~=nil then local speed=tonumber(action.speed); if not speed or speed~=speed or speed<.1 or speed>100 then return false,'Invalid route speed.' end; entry.speed=speed end
                end
                if actor.kind == 'ped' then
                    local gait = action.gait or 'auto'
                    if gait ~= 'auto' and gait ~= 'walk' and gait ~= 'run' and gait ~= 'sprint' then return false, 'Invalid ped movement style.' end
                    entry.gait = gait
                end
            elseif (action.type=='enterVehicle' or action.type=='exitVehicle') and actor.kind=='ped' then
                local target,seat,seconds=tonumber(action.vehicleId),tonumber(action.seat),tonumber(action.duration)
                if not target or target%1~=0 or not seat or seat%1~=0 or seat< -1 or seat>15 or not seconds or seconds~=seconds or seconds<.1 or seconds>30 or action.time+seconds>duration+.001 then return false,'Invalid vehicle interaction.' end
                entry.vehicleId,entry.seat,entry.duration=target,seat,seconds
                if action.instant~=nil then
                    if action.type~='enterVehicle' or type(action.instant)~='boolean' then return false,'Invalid captured seat cue.' end
                    entry.instant=action.instant
                end
                if action.type=='exitVehicle' then for _,field in ipairs({'x','y','z'}) do
                    local value=tonumber(action[field]);if not value or value~=value or math.abs(value)>100000 then return false,'Invalid vehicle exit position.' end;entry[field]=value
                end end
            elseif action.type == 'lookAt' and actor.kind == 'ped' then
                local seconds = tonumber(action.duration)
                if not seconds or seconds ~= seconds or seconds <= 0 or seconds > duration then return false, 'Invalid gaze duration.' end
                entry.duration = math.min(seconds, duration-action.time)
                if entry.duration <= 0 then return false, 'Gaze is outside the timeline.' end
                if action.targetId ~= nil then
                    local targetId = tonumber(action.targetId)
                    if not targetId or targetId % 1 ~= 0 then return false, 'Invalid gaze target.' end
                    entry.targetId = targetId
                else
                    for _, field in ipairs({ 'x', 'y', 'z' }) do
                        local value = tonumber(action[field])
                        if not value or value ~= value or math.abs(value) > 100000 then return false, 'Invalid gaze point.' end
                        entry[field] = value
                    end
                end
            elseif action.type == 'animation' and actor.kind == 'ped' then
                if type(action.dict) ~= 'string' or type(action.clip) ~= 'string' or
                    not action.dict:match('^[%w_@%-]+$') or not action.clip:match('^[%w_%-]+$') or
                    #action.dict > 80 or #action.clip > 80 then return false, 'Invalid animation.' end
                if action.loop~=nil and type(action.loop)~='boolean' then return false,'Invalid animation playback mode.' end
                entry.dict, entry.clip, entry.loop = action.dict, action.clip, action.loop
                if action.duration~=nil then
                    local seconds=tonumber(action.duration)
                    if not seconds or seconds~=seconds or seconds<=0 or seconds>duration or action.time+seconds>duration+.001 then return false,'Animation duration must fit the timeline.' end
                    entry.duration=seconds
                end
            elseif action.type == 'visibility' and actor.kind == 'prop' then
                if type(action.visible) ~= 'boolean' then return false, 'Invalid visibility action.' end
                entry.visible = action.visible
            elseif (action.type == 'engine' or action.type == 'lights') and actor.kind == 'vehicle' then
                if type(action.enabled) ~= 'boolean' then return false, 'Invalid vehicle action.' end
                entry.enabled = action.enabled
            elseif action.type == 'door' and actor.kind == 'vehicle' then
                local door = tonumber(action.door)
                if type(action.enabled) ~= 'boolean' or not door or door % 1 ~= 0 or door < 0 or door > 5 then
                    return false, 'Invalid vehicle door action.'
                end
                entry.door, entry.enabled = door, action.enabled
            else return false, 'Invalid action type.' end
            clean.actions[#clean.actions + 1] = entry
        end
        safeProject.actors[#safeProject.actors + 1] = clean
    end

    local actorIndices = {}
    for index, actor in ipairs(actors) do actorIndices[actor.id or index] = index end
    for index, actor in ipairs(safeProject.actors) do
        if actor.attachment then
            local target=actorIndices[actor.attachment.parentId]
            if not target or safeProject.actors[target].kind~='ped' then return false,'Accessory ped is missing.' end
            actor.attachment.parentId=target
            for _,step in ipairs(actor.actions) do if step.type~='visibility' then return false,'Attached accessories only support visibility cues.' end end
        end
        for _, action in ipairs(actor.actions) do
            if action.vehicleId then
                local target=actorIndices[action.vehicleId]
                if not target or safeProject.actors[target].kind~='vehicle' then return false,'Interaction vehicle is missing.' end
                action.vehicleId=target
            end
            if action.type == 'lookAt' and action.targetId then
                local target = actorIndices[action.targetId]
                if not target or target == index then return false, 'Gaze subject is missing or is the ped itself.' end
                action.targetId = target
            end
        end
    end

    local seatsOk,seatsMessage=DirectorSeats.validate(safeProject.actors,duration)
    if not seatsOk then return false,seatsMessage end

    if sourceLook.focusId~=nil then
        local id=tonumber(sourceLook.focusId);local target=actorIndices[id]
        if not target then return false,'Focus subject is missing.' end
        safeProject.look.focusId=target
    end
    local rig,message=DirectorShots.rig(project.cameraRig,actors)
    if not rig then return false,message end
    safeProject.cameraRig=rig
    local shots,message=DirectorShots.validate(project.cameraShots,duration,actors,#cleanFrames)
    if not shots then return false,message end
    safeProject.cameraShots=shots
    local bookmarks,message=DirectorStaging.bookmarks(project.bookmarks)
    if not bookmarks then return false,message end
    safeProject.bookmarks=bookmarks

    local encoded = json.encode(safeProject)
    if not encoded or #encoded > Config.ProjectFileLimit then
        return false, 'Project file is too large.'
    end

    return true, safeProject, encoded
end

local function defaultProject()
    return {
        version = 4, name = 'Untitled Project', duration = Config.DefaultDuration,
        keyframes = {}, actors = {},
        look = { weather = 'SERVER', hour = -1, minute = 0, dof = false, near = 2.0, far = 30.0, strength = 0.5 }
    }
end

local function writeLibrary(path, library)
    local generation=(library.generation or 0)+1
    local stored={version=2,generation=generation,nextId=library.nextId,activeId=library.activeId,projects={}}
    for _,entry in ipairs(library.projects) do stored.projects[#stored.projects+1]={id=entry.id,updatedAt=entry.updatedAt,data=entry.data} end
    local encoded = json.encode(stored)
    if not encoded or #encoded > Config.ProjectFileLimit * Config.MaximumProjects + 8192 then
        return false, 'Project library is too large.'
    end
    local previous = LoadResourceFile(GetCurrentResourceName(), path)
    if previous then
        SaveResourceFile(GetCurrentResourceName(), path..'.bak', previous, -1)
        if LoadResourceFile(GetCurrentResourceName(), path..'.bak')~=previous then return false,'Could not preserve the previous project library. Nothing was overwritten.' end
    end
    SaveResourceFile(GetCurrentResourceName(), path..'.pending', encoded, -1)
    if LoadResourceFile(GetCurrentResourceName(), path..'.pending')~=encoded then return false,'Could not verify the staged project library.' end
    SaveResourceFile(GetCurrentResourceName(), path, encoded, -1)
    if LoadResourceFile(GetCurrentResourceName(), path) ~= encoded then
        -- Preserve the last readable library if a write is incomplete.
        if previous then SaveResourceFile(GetCurrentResourceName(), path, previous, -1) end
        SaveResourceFile(GetCurrentResourceName(),path..'.pending','',-1)
        return false, 'The server could not save the project library.'
    end
    library.version=2;library.generation=generation
    return true
end

local function readLibraryAttempt(source, override)
    local path = libraryPath(source)
    if not path then return nil, nil, 'Could not identify your account.' end
    local contents = override or LoadResourceFile(GetCurrentResourceName(), path)
    if contents then
        if #contents>Config.ProjectFileLimit*Config.MaximumProjects+8192 then return nil,nil,'The project library is too large.' end
        local ok, library = pcall(json.decode, contents)
        if ok and type(library)=='table' and library.version~=nil and (type(library.version)~='number' or library.version%1~=0 or library.version<1 or library.version>2) then return nil,nil,'Unsupported library version. No files were overwritten.' end
        if not ok or type(library) ~= 'table' or type(library.projects) ~= 'table' or
            #library.projects < 1 or #library.projects > Config.MaximumProjects then
            return nil, nil, 'The project library is damaged.'
        end
        local ids,maxId,active={},0,false
        if library.version~=nil and (type(library.version)~='number' or library.version%1~=0 or library.version<1 or library.version>2) then return nil,nil,'Unsupported library version. No files were overwritten.' end
        if library.generation~=nil and (type(library.generation)~='number' or library.generation%1~=0 or library.generation<0 or library.generation>9007199254740990) then return nil,nil,'The library generation is invalid.' end
        for _,entry in ipairs(library.projects) do
            local id=type(entry)=='table' and entry.id
            local serial=type(id)=='string' and tonumber(id:match('^p(%d+)$'))
            local p=type(entry)=='table' and entry.data
            if not serial or serial<1 or serial>1000000000 or ids[id] or type(p)~='table' then
                return nil,nil,'The project library is damaged.'
            end
            if entry.updatedAt~=nil and (type(entry.updatedAt)~='number' or entry.updatedAt~=entry.updatedAt or math.abs(entry.updatedAt)>1e12) then return nil,nil,'The project library is damaged.' end
            ids[id]=true;maxId=math.max(maxId,serial);active=active or id==library.activeId
        end
        if not active then return nil,nil,'The active project is missing.' end
        -- Recover an old/missing counter without reusing an existing project ID.
        local nextId=tonumber(library.nextId)
        library.nextId=nextId and nextId==nextId and nextId%1==0 and nextId>maxId and nextId<=1000000000 and nextId or maxId+1
        return library, path
    end

    local project = defaultProject()
    local legacy = LoadResourceFile(GetCurrentResourceName(), projectPath(source))
    if legacy and #legacy <= Config.ProjectFileLimit then
        local ok, decoded = pcall(json.decode, legacy)
        if #legacy <= Config.ProjectFileLimit and ok and type(decoded) == 'table' then
            local valid, normalized = validateProject(decoded)
            if valid then project = normalized end
        end
    end
    local library = { version = 1, nextId = 2, activeId = 'p1', projects = {
        { id = 'p1', updatedAt = os.time(), data = project }
    } }
    local saved, errorMessage = writeLibrary(path, library)
    if not saved then return nil, nil, errorMessage end
    return library, path
end

local function readLibrary(source)
    local path=libraryPath(source)
    if not path then return nil,nil,'Could not identify your account.' end
    local original=LoadResourceFile(GetCurrentResourceName(),path)
    local backup=LoadResourceFile(GetCurrentResourceName(),path..'.bak')
    local pending=LoadResourceFile(GetCurrentResourceName(),path..'.pending')
    local library,libraryFile,message
    if original or (not backup and not pending) then library,libraryFile,message=readLibraryAttempt(source) end
    if message and message:find('Unsupported library version',1,true) then return nil,nil,message end
    if library then
        for _,entry in ipairs(library.projects) do
            local version=entry.data.version
            if version~=nil and (type(version)~='number' or version%1~=0 or version<1 or version>4) then return nil,nil,'Unsupported project version in this library. No files were overwritten.' end
        end
        local activeValid,firstValid=false,nil
        for _,entry in ipairs(library.projects) do
            local valid,reason=validateProject(entry.data)
            entry._invalid=not valid;entry._error=not valid and tostring(reason) or nil
            if valid then firstValid=firstValid or entry.id;if entry.id==library.activeId then activeValid=true end end
        end
        if activeValid then return library,libraryFile end
        if firstValid then
            library.activeId=firstValid
            TriggerClientEvent('vanta_director_free:collaborationStatus',source,'The active project is damaged. A valid project was opened; the damaged entry and files were preserved.')
            return library,libraryFile
        end
        message='The active project is invalid.'
    end
    local recovered,recoveryContents,recoveryGeneration=nil,nil,-1
    for _,contents in ipairs({backup or '',pending or ''}) do
        if contents~='' then
            local candidate=readLibraryAttempt(source,contents)
            local valid,firstValid=false,nil
            if candidate then
                local supported=true
                for _,entry in ipairs(candidate.projects) do
                    local version=entry.data.version
                    if version~=nil and (type(version)~='number' or version%1~=0 or version<1 or version>4) then supported=false end
                    local good,reason=validateProject(entry.data)
                    entry._invalid=not good;entry._error=not good and tostring(reason) or nil
                    if good then firstValid=firstValid or entry.id;if entry.id==candidate.activeId then valid=true end end
                end
                if not valid and firstValid then candidate.activeId=firstValid;valid=true end
                valid=valid and supported
            end
            local generation=candidate and (candidate.generation or 0) or -1
            -- Legacy .pending has no ordering proof; do not promote it over a backup.
            if valid and (contents==backup or generation>0) and generation>recoveryGeneration then
                recovered,recoveryContents,recoveryGeneration=candidate,contents,generation
            end
        end
    end
    if not recovered then return nil,nil,message or 'The project library and recovery copies are unreadable. No files were overwritten.' end
    if original then
        SaveResourceFile(GetCurrentResourceName(),path..'.damaged',original,-1)
        if LoadResourceFile(GetCurrentResourceName(),path..'.damaged')~=original then return nil,nil,'Could not preserve the damaged library.' end
    end
    SaveResourceFile(GetCurrentResourceName(),path,recoveryContents,-1)
    if LoadResourceFile(GetCurrentResourceName(),path)~=recoveryContents then return nil,nil,'Backup recovery write failed.' end
    TriggerClientEvent('vanta_director_free:collaborationStatus',source,'Recovered the newest valid project library recovery copy. Check your recent changes.')
    return recovered,path
end

local function findProject(library, id)
    if type(id) ~= 'string' then return nil end
    for index, entry in ipairs(library.projects) do
        if entry.id == id then return entry, index end
    end
    return nil
end

local function summaries(library)
    local list = {}
    for _, entry in ipairs(library.projects) do
        local data = entry.data or {}
        list[#list + 1] = {
            id = entry.id, name = type(data.name)=='string' and data.name:sub(1,64) or 'Damaged project', updatedAt = entry.updatedAt or 0,
            duration = type(data.duration)=='number' and data.duration==data.duration and data.duration>=0 and data.duration<=Config.MaximumDuration and data.duration or Config.DefaultDuration,
            shots = (type(data.keyframes) == 'table' and #data.keyframes or 0)+(type(data.cameraShots)=='table' and #data.cameraShots or 0),
            actors = type(data.actors) == 'table' and #data.actors or 0,
            available=not entry._invalid,error=entry._error
        }
    end
    table.sort(list, function(a, b)
        if a.id == b.id then return false end
        if a.id == library.activeId then return true end
        if b.id == library.activeId then return false end
        if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
        return (tonumber(a.id:sub(2)) or 0) > (tonumber(b.id:sub(2)) or 0)
    end)
    return list
end

local function sendLibrary(source, library, message)
    local active = findProject(library, library.activeId) or library.projects[1]
    local valid,project=validateProject(active.data)
    if not valid then TriggerClientEvent('vanta_director_free:libraryError',source,'The saved project is invalid: '..tostring(project));return end
    TriggerClientEvent('vanta_director_free:projectLibrary', source, project, active.id, summaries(library), message)
end

local function libraryError(source, message)
    TriggerClientEvent('vanta_director_free:libraryError', source, message)
end

RegisterNetEvent('vanta_director_free:requestProject', function()
    local source = source
    local allowed,message=DirectorAccess.check(source,'load',250)
    if not allowed then TriggerClientEvent('vanta_director_free:accessDenied',source,message);return end
    local library, _, errorMessage = readLibrary(source)
    if not library then libraryError(source, errorMessage) return end
    sendLibrary(source, library, 'Project library loaded.')
end)

RegisterNetEvent('vanta_director_free:saveProject', function(project, requestId)
    if requestId~=nil and (type(requestId)~='number' or requestId%1~=0 or requestId<1 or requestId>9007199254740991) then return end
    local source = source
    local allowed,message=DirectorAccess.check(source,'save',250)
    if not allowed then TriggerClientEvent('vanta_director_free:saveResult',source,false,message,nil,requestId);return end
    local library, path, errorMessage = readLibrary(source)
    if not library then TriggerClientEvent('vanta_director_free:saveResult', source, false, errorMessage, nil, requestId) return end
    local entry = type(project) == 'table' and findProject(library, project.id)
    if not entry or entry.id ~= library.activeId then
        TriggerClientEvent('vanta_director_free:saveResult', source, false, 'Open the project before saving it.', nil, requestId)
        return
    end
    local valid, normalized = validateProject(project)
    if not valid then TriggerClientEvent('vanta_director_free:saveResult', source, false, normalized, nil, requestId) return end
    entry.data = normalized
    entry.updatedAt = os.time()
    local saved, writeError = writeLibrary(path, library)
    if not saved then TriggerClientEvent('vanta_director_free:saveResult', source, false, writeError, nil, requestId) return end
    TriggerClientEvent('vanta_director_free:saveResult', source, true, 'Project saved on this server.', normalized, requestId)
    TriggerClientEvent('vanta_director_free:projectList', source, library.activeId, summaries(library))
end)

RegisterNetEvent('vanta_director_free:manageProject', function(operation, id, name)
    local source = source
    local allowed,message=DirectorAccess.check(source,'manage',250)
    if not allowed then libraryError(source,message);return end
    local library, path, errorMessage = readLibrary(source)
    if not library then libraryError(source, errorMessage) return end
    local entry, index = findProject(library, id)
    local previousActive=library.activeId
    if operation == 'create' or operation == 'duplicate' then
        if #library.projects >= Config.MaximumProjects then libraryError(source, 'Project limit reached.') return end
        if operation == 'duplicate' and not entry then libraryError(source, 'Project not found.') return end
        if operation=='duplicate' then local valid,reason=validateProject(entry.data);if not valid then libraryError(source,'This project is damaged and cannot be duplicated: '..tostring(reason));return end end
        local data = operation == 'duplicate' and json.decode(json.encode(entry.data)) or defaultProject()
        if operation == 'duplicate' then data.name = ('%s copy'):format(data.name):sub(1, 64) end
        local newId = 'p' .. tostring(library.nextId or (#library.projects + 1))
        library.nextId = (library.nextId or (#library.projects + 1)) + 1
        library.projects[#library.projects + 1] = { id = newId, updatedAt = os.time(), data = data }
        library.activeId = newId
    elseif operation == 'open' then
        if not entry then libraryError(source, 'Project not found.') return end
        local valid,reason=validateProject(entry.data)
        if not valid then libraryError(source,'This project is damaged and was preserved: '..tostring(reason));return end
        library.activeId = entry.id
    elseif operation == 'rename' then
        if not entry or type(name) ~= 'string' then libraryError(source, 'Project not found.') return end
        local cleanName = name:gsub('[\r\n]', ' '):match('^%s*(.-)%s*$'):sub(1, 64)
        if cleanName == '' then libraryError(source, 'Enter a project name.') return end
        entry.data.name = cleanName
        entry.updatedAt = os.time()
    elseif operation == 'delete' then
        if not entry then libraryError(source, 'Project not found.') return end
        if #library.projects == 1 then libraryError(source, 'Keep at least one project.') return end
        if library.activeId==id then
            local nextActive
            for _,candidate in ipairs(library.projects) do if candidate.id~=id and not candidate._invalid then nextActive=candidate.id;break end end
            if not nextActive then libraryError(source,'Keep at least one valid project. Create a new project before deleting this one.');return end
            library.activeId=nextActive
        end
        table.remove(library.projects,index)
    else libraryError(source, 'Invalid project action.') return end

    local saved, writeError = writeLibrary(path, library)
    if not saved then libraryError(source, writeError) return end
    if operation=='rename' or (operation=='delete' and id~=previousActive) then
        TriggerClientEvent('vanta_director_free:projectMetadata',source,library.activeId,summaries(library),operation=='rename' and id or nil,operation=='rename' and entry.data.name or nil)
        return
    end
    sendLibrary(source, library, operation == 'create' and 'New project created.' or
        operation == 'duplicate' and 'Project duplicated.' or
        operation == 'delete' and 'Project deleted.' or
        operation == 'rename' and 'Project renamed.' or 'Project opened.')
end)

RegisterNetEvent('vanta_director_free:importProject',function(encoded)
    local player=source
    local allowed,message=DirectorAccess.check(player,'import',1000)
    if not allowed then libraryError(player,message);return end
    if type(encoded)~='string' or #encoded>Config.ProjectFileLimit then libraryError(player,'Project JSON exceeds the file limit.');return end
    local ok,raw=pcall(json.decode,encoded)
    if not ok then libraryError(player,'Invalid JSON.');return end
    local valid,project=validateProject(raw)
    if not valid then libraryError(player,project);return end
    local library,path,errorMessage=readLibrary(player)
    if not library then libraryError(player,errorMessage);return end
    if #library.projects>=Config.MaximumProjects then libraryError(player,'Project limit reached.');return end
    local id='p'..tostring(library.nextId);library.nextId=library.nextId+1
    project.name=(project.name..' imported'):sub(1,64)
    library.projects[#library.projects+1]={id=id,updatedAt=os.time(),data=project};library.activeId=id
    local saved,message=writeLibrary(path,library)
    if not saved then libraryError(player,message);return end
    sendLibrary(player,library,'Project imported into your own library.')
end)

