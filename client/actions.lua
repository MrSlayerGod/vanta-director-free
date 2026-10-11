-- Animation previews and actor action editing.
DirectorClient.modules.actions = function(ctx)
    local editorState = ctx.state
    ctx.actions = {}

    ctx.actions.stopAnimationPreview = function(restore)
        editorState.animationPreviewToken = editorState.animationPreviewToken + 1
        local id = editorState.animationPreviewActor
        editorState.animationPreviewActor = nil
        if not id then
            return
        end
        local handle = editorState.sceneEntities[id]
        if handle and DoesEntityExist(handle) then
            ClearPedTasksImmediately(handle)
        end
        for _, actor in ipairs(editorState.sceneActors) do
            if actor.id == id then
                actor._playing = nil
                break
            end
        end
        SendNUIMessage({ action = "animationPreviewStopped" })
        if restore and editorState.directorOpen and ctx.playback.sceneApply then
            ctx.playback.sceneApply(editorState.playhead, true)
        end
    end

    ctx.actions.sceneAddAction = function(id, actionType, data)
        for _, actor in ipairs(editorState.sceneActors) do
            if actor.id == id then
                if #actor.actions >= Config.MaximumActionsPerActor then
                    return false, "Action limit reached."
                end
                if actor.actions[1] and actor.actions[1].type == "recording" then
                    return false, "Recorded takes use a dedicated movement track."
                end
                if actor.attachment and actionType ~= "visibility" then
                    return false, "Attached accessories only support wear/remove cues."
                end
                local action = {
                    id = editorState.nextActionId,
                    time = math.floor(editorState.playhead * 10 + 0.5) / 10,
                    type = actionType,
                }
                if actionType == "move" then
                    if action.time >= editorState.duration - 0.1 then
                        return false, "Move the playhead earlier to add movement."
                    end
                    action.x, action.y, action.z = ctx.scene.scenePlace()
                    if not action.x then
                        return false, "Camera is not ready."
                    end
                    if actor.kind ~= "ped" then
                        action.z = action.z + ctx.playback.routeRootOffset(actor)
                    end
                    local seconds = ctx.maths.finiteNumber(data.duration or 3.0, Config.MaximumDuration)
                    if not seconds or seconds <= 0 then
                        return false, "Enter a valid movement duration."
                    end
                    action.duration = math.max(0.1, math.min(seconds, editorState.duration - action.time))
                    if actor.kind == "ped" then
                        action.gait = tostring(data.gait or "auto")
                        if action.gait ~= "auto" and not DirectorPedCues.gaits[action.gait] then
                            return false, "Choose a valid movement style."
                        end
                        if data.autoDuration == true and DirectorPedCues.gaits[action.gait] then
                            local position = GetEntityCoords(editorState.sceneEntities[id])
                            local distance = math.sqrt(
                                (action.x - position.x) ^ 2 + (action.y - position.y) ^ 2 + (action.z - position.z) ^ 2
                            )
                            local seconds = math.max(0.1, distance / DirectorPedCues.gaits[action.gait])
                            if seconds > editorState.duration - action.time then
                                return false, "Extend the timeline or choose a closer destination."
                            end
                            action.duration = math.ceil(seconds * 10) / 10
                            action.duration = math.min(action.duration, editorState.duration - action.time)
                        end
                    end
                elseif (actionType == "enterVehicle" or actionType == "exitVehicle") and actor.kind == "ped" then
                    local target
                    for _, item in ipairs(editorState.sceneActors) do
                        if item.id == tonumber(data.vehicleId) and item.kind == "vehicle" then
                            target = item
                        end
                    end
                    local seat = tonumber(data.seat)
                    local seconds = ctx.maths.finiteNumber(data.duration or 5, 30)
                    if
                        not target
                        or not seat
                        or seat % 1 ~= 0
                        or seat < -1
                        or seat >= GetVehicleModelNumberOfSeats(GetHashKey(target.model)) - 1
                    then
                        return false, "Choose a valid vehicle and seat."
                    end
                    if not seconds or seconds < 0.1 or action.time + seconds > editorState.duration + 0.001 then
                        return false, "Extend the timeline or shorten the interaction."
                    end
                    action.vehicleId, action.seat, action.duration = target.id, seat, seconds
                    if actionType == "exitVehicle" then
                        local p = { x = target.x, y = target.y, z = target.z }
                        local heading = target.heading
                        local endTime = action.time + action.duration
                        for _, step in ipairs(target.actions) do
                            if step.type == "move" and step.time <= endTime then
                                local point, rotation = ctx.playback.sampleMove(
                                    step,
                                    p,
                                    ctx.maths.clamp((endTime - step.time) / step.duration, 0, 1)
                                )
                                p = point
                                heading = rotation or heading
                            end
                        end
                        local minimum, maximum = GetModelDimensions(GetHashKey(target.model))
                        local side = math.max(0.8, (maximum.x - minimum.x) * 0.5 + 0.6)
                            * ((seat == -1 or seat % 2 == 1) and -1 or 1)
                        local angle = math.rad(heading)
                        action.x, action.y, action.z =
                            p.x + math.cos(angle) * side,
                            p.y + math.sin(angle) * side,
                            p.z + ctx.playback.routeRootOffset(actor)
                    end
                elseif actionType == "lookAt" and actor.kind == "ped" then
                    if action.time >= editorState.duration - 0.1 then
                        return false, "Move the playhead earlier to add a gaze."
                    end
                    local seconds = ctx.maths.finiteNumber(data.duration, Config.MaximumDuration)
                    if not seconds or seconds <= 0 then
                        return false, "Enter a valid gaze duration."
                    end
                    action.duration = math.max(0.1, math.min(seconds, editorState.duration - action.time))
                    local targetId = tonumber(data.targetId)
                    if targetId then
                        if targetId == id or not editorState.sceneEntities[targetId] then
                            return false, "Choose another staged subject."
                        end
                        action.targetId = targetId
                    else
                        action.x, action.y, action.z = ctx.scene.scenePlace()
                        if not action.x then
                            return false, "Camera is not ready."
                        end
                    end
                elseif actionType == "animation" and actor.kind == "ped" then
                    local dict, clip = tostring(data.dict or ""), tostring(data.clip or "")
                    if not dict:match("^[%w_@%-]+$") or not clip:match("^[%w_%-]+$") or #dict > 80 or #clip > 80 then
                        return false, "Invalid animation."
                    end
                    if data.loop ~= nil and type(data.loop) ~= "boolean" then
                        return false, "Invalid animation playback mode."
                    end
                    local handle = editorState.sceneEntities[id]
                    local generation = editorState.sceneGeneration
                    if not handle or not DoesEntityExist(handle) or not DoesAnimDictExist(dict) then
                        return false, "Animation dictionary or ped unavailable."
                    end
                    RequestAnimDict(dict)
                    local deadline = GetGameTimer() + 2000
                    while
                        not HasAnimDictLoaded(dict)
                        and GetGameTimer() < deadline
                        and editorState.directorOpen
                        and editorState.sceneGeneration == generation
                    do
                        Wait(25)
                    end
                    if
                        not editorState.directorOpen
                        or editorState.sceneGeneration ~= generation
                        or editorState.sceneEntities[id] ~= handle
                        or not DoesEntityExist(handle)
                    then
                        return false, "Animation loading cancelled."
                    end
                    if not HasAnimDictLoaded(dict) then
                        return false, "Animation did not load."
                    end
                    local length = GetAnimDuration(dict, clip)
                    if type(length) ~= "number" or length ~= length or length <= 0 then
                        return false, "Animation clip unavailable on this game build."
                    end
                    action.dict, action.clip, action.loop = dict, clip, data.loop
                    if data.loop == false and data.duration == nil then
                        if action.time >= editorState.duration - 0.01 then
                            return false, "Move the playhead earlier to add this animation."
                        end
                        action.duration = math.min(length, editorState.duration - action.time)
                    end
                    if data.duration ~= nil then
                        local seconds = ctx.maths.finiteNumber(data.duration, editorState.duration)
                        if not seconds or seconds <= 0 or action.time + seconds > editorState.duration + 0.001 then
                            return false, "Animation duration must fit the timeline."
                        end
                        action.duration = data.loop == false and math.min(seconds, length) or seconds
                    end
                elseif actionType == "visibility" and actor.kind == "prop" and type(data.visible) == "boolean" then
                    action.visible = data.visible
                elseif
                    (actionType == "engine" or actionType == "lights")
                    and actor.kind == "vehicle"
                    and type(data.enabled) == "boolean"
                then
                    action.enabled = data.enabled
                elseif actionType == "door" and actor.kind == "vehicle" and type(data.enabled) == "boolean" then
                    local door = tonumber(data.door)
                    if not door or door % 1 ~= 0 or door < 0 or door > 5 then
                        return false, "Choose a valid vehicle door."
                    end
                    action.door, action.enabled = door, data.enabled
                else
                    return false, "Action does not fit this actor."
                end
                actor.actions[#actor.actions + 1] = action
                local valid, message = DirectorSeats.validate(editorState.sceneActors, editorState.duration)
                if not valid then
                    table.remove(actor.actions)
                    return false, message
                end
                editorState.nextActionId = editorState.nextActionId + 1
                table.sort(actor.actions, function(a, b)
                    if a.time == b.time then
                        return a.id < b.id
                    end
                    return a.time < b.time
                end)
                ctx.playback.sceneApply(editorState.playhead)
                ctx.scene.sceneSend()
                return true
            end
        end
        return false, "Actor not found."
    end

    ctx.actions.sceneDeleteAction = function(id, index)
        for _, actor in ipairs(editorState.sceneActors) do
            if actor.id == id and actor.actions[index] then
                local beforeActions = DirectorHistory.copy(actor.actions)
                local removed = table.remove(actor.actions, index)
                if removed.type == "enterVehicle" then
                    for i = 1, #actor.actions do
                        local a = actor.actions[i]
                        if a.type == "exitVehicle" and a.vehicleId == removed.vehicleId and a.time >= removed.time then
                            table.remove(actor.actions, i)
                            break
                        end
                    end
                end
                local valid, message = DirectorSeats.validate(editorState.sceneActors, editorState.duration)
                if not valid then
                    actor.actions = beforeActions
                    return false, message
                end
                local handle = editorState.sceneEntities[id]
                if actor.kind == "ped" and handle and DoesEntityExist(handle) then
                    ClearPedTasksImmediately(handle)
                end
                actor._playing = nil
                actor._lookPlaying = nil
                ctx.playback.sceneApply(editorState.playhead)
                ctx.scene.sceneSend()
                return true
            end
        end
        return false
    end

    return function()
        ctx.bridge.editorCallback("addAction", function(data, callback)
            if data.type == "animation" then
                ctx.actions.stopAnimationPreview(true)
            end
            local ok, message = ctx.actions.sceneAddAction(tonumber(data.id), data.type, data)
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("previewAnimation", function(data, callback)
            local id, dict, clip = tonumber(data.id), tostring(data.dict or ""), tostring(data.clip or "")
            if not editorState.directorOpen or editorState.captureMode or editorState.previewing then
                callback({ ok = false, message = "Stop playback before previewing an animation." })
                return
            end
            local actor
            for _, item in ipairs(editorState.sceneActors) do
                if item.id == id and item.kind == "ped" then
                    actor = item
                    break
                end
            end
            local handle = actor and editorState.sceneEntities[id]
            if not handle or not DoesEntityExist(handle) then
                callback({ ok = false, message = "Select a staged ped first." })
                return
            end
            if
                not dict:match("^[%w_@%-]+$")
                or not clip:match("^[%w_%-]+$")
                or #dict > 80
                or #clip > 80
                or not DoesAnimDictExist(dict)
            then
                callback({ ok = false, message = "This animation dictionary is unavailable." })
                return
            end
            if data.loop ~= nil and type(data.loop) ~= "boolean" then
                callback({ ok = false, message = "Invalid animation playback mode." })
                return
            end
            ctx.actions.stopAnimationPreview(true)
            local token = editorState.animationPreviewToken
            RequestAnimDict(dict)
            local deadline = GetGameTimer() + 2000
            while
                not HasAnimDictLoaded(dict)
                and GetGameTimer() < deadline
                and token == editorState.animationPreviewToken
                and editorState.directorOpen
            do
                Wait(25)
            end
            if
                token ~= editorState.animationPreviewToken
                or not editorState.directorOpen
                or not DoesEntityExist(handle)
            then
                callback({ ok = false, message = "Animation preview cancelled." })
                return
            end
            if not HasAnimDictLoaded(dict) then
                callback({ ok = false, message = "Animation did not load." })
                return
            end
            local length = GetAnimDuration(dict, clip)
            if type(length) ~= "number" or length ~= length or length <= 0 then
                callback({ ok = false, message = "Animation clip unavailable on this game build." })
                return
            end
            ClearPedTasksImmediately(handle)
            if not actor._frozen then
                FreezeEntityPosition(handle, true)
                actor._frozen = true
            end
            TaskPlayAnim(handle, dict, clip, 8.0, -8.0, -1, data.loop == false and 0 or 1, 0.0, false, false, false)
            actor._playing = "preview"
            editorState.animationPreviewActor = id
            Wait(math.max(0, math.min(120, math.floor(length * 250))))
            if token ~= editorState.animationPreviewToken or not DoesEntityExist(handle) then
                callback({ ok = false, message = "Animation preview cancelled." })
                return
            end
            if not IsEntityPlayingAnim(handle, dict, clip, 3) then
                ctx.actions.stopAnimationPreview(true)
                callback({ ok = false, message = "This animation does not play on the selected ped." })
                return
            end
            callback({ ok = true, nativeDuration = length, loop = data.loop ~= false })
        end)

        ctx.bridge.editorCallback("stopAnimationPreview", function(_, callback)
            ctx.actions.stopAnimationPreview(true)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("deleteAction", function(data, callback)
            local ok, message = ctx.actions.sceneDeleteAction(tonumber(data.id), tonumber(data.index))
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("moveAction", function(data, callback)
            local actorId, actionId, atTime = tonumber(data.actorId), tonumber(data.actionId), tonumber(data.time)
            if not atTime or atTime ~= atTime then
                callback({ ok = false, message = "Invalid action time." })
                return
            end
            for _, actor in ipairs(editorState.sceneActors) do
                if actor.id == actorId then
                    for _, action in ipairs(actor.actions) do
                        if action.id == actionId then
                            local latest = (
                                action.type == "move"
                                or action.type == "lookAt"
                                or action.type == "enterVehicle"
                                or action.type == "exitVehicle"
                                or action.type == "recording"
                                or (action.type == "animation" and action.duration)
                            )
                                    and math.max(0.0, editorState.duration - action.duration)
                                or editorState.duration
                            local oldTime = action.time
                            action.time = ctx.maths.clamp(atTime, 0.0, latest)
                            local valid, message = DirectorSeats.validate(editorState.sceneActors, editorState.duration)
                            if not valid then
                                action.time = oldTime
                                callback({ ok = false, message = message })
                                return
                            end
                            table.sort(actor.actions, function(a, b)
                                if a.time == b.time then
                                    return a.id < b.id
                                end
                                return a.time < b.time
                            end)
                            ctx.camera.setPlayhead(action.time)
                            ctx.scene.sceneSend()
                            callback({ ok = true })
                            return
                        end
                    end
                end
            end
            callback({ ok = false, message = "Action not found." })
        end)
    end
end
