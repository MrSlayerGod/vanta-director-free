-- Keyframes, playhead ranges and timeline clipboard.
DirectorClient.modules.timeline = function(ctx)
    local editorState = ctx.state
    ctx.timeline = {}

    return function()
        ctx.bridge.editorCallback("addKeyframe", function(data, callback)
            local ok, message = ctx.camera.addKeyframe(data.time)
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("deleteKeyframe", function(data, callback)
            local keyframes = ctx.camera.editingFrames()
            local index = tonumber(data.index)
            if index and keyframes[index] then
                if ctx.camera.editingShot() and #keyframes == 1 and ctx.camera.editingShot().rig.mode == "manual" then
                    callback({ ok = false, message = "Keep one key or delete the entire shot." })
                    return
                end
                table.remove(keyframes, index)
                ctx.projects.sendProject()
                callback({ ok = true })
                return
            end
            callback({ ok = false, message = "Keyframe not found." })
        end)

        ctx.bridge.editorCallback("moveKeyframe", function(data, callback)
            local keyframes = ctx.camera.editingFrames()
            local index, atTime = tonumber(data.index), tonumber(data.time)
            if not index or not keyframes[index] or not atTime or atTime ~= atTime then
                callback({ ok = false, message = "Invalid camera keyframe." })
                return
            end
            local time = ctx.maths.clamp(atTime, 0.0, editorState.duration)
            for otherIndex, frame in ipairs(keyframes) do
                if otherIndex ~= index and math.abs(frame.time - time) < 0.05 then
                    callback({ ok = false, message = "There is already a camera keyframe here." })
                    return
                end
            end
            local shot = ctx.camera.editingShot()
            if shot and (time < shot.time or time > shot.time + shot.duration) then
                callback({ ok = false, message = "Keep the key inside its shot." })
                return
            end
            keyframes[index].time = time
            table.sort(keyframes, function(a, b)
                return a.time < b.time
            end)
            ctx.camera.setPlayhead(time)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setPlayhead", function(data, callback)
            local at = ctx.maths.finiteNumber(data.time, Config.MaximumDuration)
            if not at then
                callback({ ok = false, message = "Invalid timeline position." })
                return
            end
            local sequence = ctx.maths.finiteNumber(data.sequence, 9007199254740991)
            if data.sequence ~= nil and (not sequence or sequence % 1 ~= 0) then
                callback({ ok = false, message = "Invalid timeline sequence." })
                return
            end
            if sequence and sequence <= editorState.lastSeekSequence then
                callback({ ok = true })
                return
            end
            if sequence then
                editorState.lastSeekSequence = sequence
            end
            editorState.previewing = false
            ctx.camera.setPlayhead(data.time)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setDuration", function(data, callback)
            local requested = DirectorShots.number(data.duration, Config.MinimumDuration, Config.MaximumDuration)
            if not requested then
                callback({ ok = false, message = "Invalid project duration." })
                return
            end
            for _, shot in ipairs(editorState.cameraShots) do
                if shot.time + shot.duration > requested + 0.001 then
                    callback({ ok = false, message = "Keep every camera shot inside the project." })
                    return
                end
            end
            local valid, message = DirectorSeats.validate(editorState.sceneActors, requested)
            if not valid then
                callback({ ok = false, message = message })
                return
            end
            for _, a in ipairs(editorState.sceneActors) do
                for _, clip in ipairs(a.actions) do
                    if clip.type == "recording" and clip.time + clip.duration > requested + 0.001 then
                        callback({ ok = false, message = "Keep the full recorded take inside the timeline." })
                        return
                    end
                end
            end
            for _, frame in ipairs(editorState.keyframes) do
                if frame.time > requested + 0.001 then
                    callback({ ok = false, message = "Move or delete camera keys beyond the new duration first." })
                    return
                end
            end
            for _, actor in ipairs(editorState.sceneActors) do
                for _, action in ipairs(actor.actions) do
                    if action.time + (action.duration or 0) > requested + 0.001 then
                        callback({ ok = false, message = "Move or shorten actions beyond the new duration first." })
                        return
                    end
                end
            end
            editorState.duration = requested
            editorState.playbackRange = nil
            editorState.playhead = ctx.maths.clamp(editorState.playhead, 0.0, editorState.duration)
            for _, frame in ipairs(editorState.keyframes) do
                frame.time = ctx.maths.clamp(frame.time, 0.0, editorState.duration)
            end
            for _, actor in ipairs(editorState.sceneActors) do
                for _, action in ipairs(actor.actions) do
                    action.time = ctx.maths.clamp(action.time, 0.0, editorState.duration)
                    if action.type == "move" or action.type == "lookAt" then
                        action.time = math.min(action.time, math.max(0.0, editorState.duration - 0.1))
                        action.duration =
                            math.max(0.1, math.min(action.duration, math.max(0.1, editorState.duration - action.time)))
                    end
                end
            end
            table.sort(editorState.keyframes, function(a, b)
                return a.time < b.time
            end)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setPlaybackRange", function(data, callback)
            local first = DirectorShots.number(data.first, 0, editorState.duration)
            local last = DirectorShots.number(data.last, 0, editorState.duration)
            if not first or not last or last - first < 0.1 then
                callback({ ok = false, message = "Choose a valid playback range." })
                return
            end
            editorState.previewing = false
            editorState.playbackRange = { first = first, last = last, loop = data.loop == true }
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("copyTimeline", function(data, callback)
            if type(data.items) ~= "table" or #data.items == 0 or #data.items > Config.MaximumTimelineSelection then
                callback({ ok = false, message = "Ctrl-click timeline items to select them." })
                return
            end
            local list, start = {}, math.huge
            for _, item in ipairs(data.items) do
                if type(item) ~= "table" then
                    callback({ ok = false, message = "Invalid selection." })
                    return
                end
                local value
                if item.kind == "camera" then
                    value = ctx.camera.editingFrames()[tonumber(item.index)]
                elseif item.kind == "shot" then
                    value = DirectorShots.find(editorState.cameraShots, item.id)
                elseif item.kind == "action" then
                    for _, a in ipairs(editorState.sceneActors) do
                        if a.id == tonumber(item.actorId) then
                            for _, clip in ipairs(a.actions) do
                                if clip.id == tonumber(item.actionId) then
                                    value = clip
                                end
                            end
                        end
                    end
                end
                if not value then
                    callback({ ok = false, message = "The selection changed. Select the items again." })
                    return
                end
                list[#list + 1] =
                    { kind = item.kind, actorId = tonumber(item.actorId), data = DirectorShots.copy(value) }
                start = math.min(start, value.time)
            end
            editorState.timelineClipboard = { items = list, start = start }
            callback({ ok = true, message = "Timeline selection copied." })
        end)

        ctx.bridge.editorCallback("pasteTimeline", function(_, callback)
            if not editorState.timelineClipboard then
                callback({ ok = false, message = "Copy timeline items first." })
                return
            end
            if
                editorState.previewing
                or editorState.captureMode
                or editorState.routeDraft
                or editorState.dragSession
            then
                callback({ ok = false, message = "Stop playback or editing first." })
                return
            end
            local actors = DirectorShots.copy(editorState.sceneActors)
            local shots = DirectorShots.copy(editorState.cameraShots)
            local frames = DirectorShots.copy(ctx.camera.editingFrames())
            local offset = editorState.playhead - editorState.timelineClipboard.start
            local actionId = editorState.nextActionId
            local shotId = 1
            for _, shot in ipairs(shots) do
                shotId = math.max(shotId, shot.id + 1)
            end
            for _, item in ipairs(editorState.timelineClipboard.items) do
                local copy = DirectorShots.copy(item.data)
                copy.time = copy.time + offset
                if copy.time < 0 or copy.time + (copy.duration or 0) > editorState.duration + 0.001 then
                    callback({ ok = false, message = "Extend the project or paste earlier." })
                    return
                end
                if item.kind == "camera" then
                    frames[#frames + 1] = copy
                elseif item.kind == "shot" then
                    copy = DirectorShots.retime(item.data, copy.time, copy.duration)
                    copy.id = shotId
                    shotId = shotId + 1
                    shots[#shots + 1] = copy
                elseif item.kind == "action" then
                    local actor
                    for _, a in ipairs(actors) do
                        if a.id == item.actorId then
                            actor = a
                        end
                    end
                    if not actor or #actor.actions >= Config.MaximumActionsPerActor then
                        callback({ ok = false, message = "Actor missing or action limit reached." })
                        return
                    end
                    if copy.type == "recording" then
                        callback({ ok = false, message = "Duplicate the recorded actor in Staging to copy its take." })
                        return
                    end
                    copy.id = actionId
                    actionId = actionId + 1
                    actor.actions[#actor.actions + 1] = copy
                end
            end
            local shot = ctx.camera.editingShot()
            local clean, message = DirectorShots.frames(
                frames,
                shot and shot.time or 0,
                shot and shot.time + shot.duration or editorState.duration
            )
            if not clean then
                callback({ ok = false, message = message })
                return
            end
            if shot then
                for _, v in ipairs(shots) do
                    if v.id == shot.id then
                        v.frames = clean
                    end
                end
            end
            local valid, message = DirectorShots.validate(
                shots,
                editorState.duration,
                actors,
                shot and #editorState.keyframes or #clean,
                true
            )
            if not valid then
                callback({ ok = false, message = message })
                return
            end
            local validActors, message = DirectorSeats.validate(actors, editorState.duration)
            if not validActors then
                callback({ ok = false, message = message })
                return
            end
            local old = DirectorHistory.copy(editorState.sceneActors)
            local rig = DirectorShots.copy(editorState.cameraRig)
            if not ctx.scene.sceneLoad(actors, true, true) then
                ctx.scene.sceneLoad(old, true, true)
                editorState.cameraRig = rig
                callback({ ok = false, message = "Could not restore the copied scene." })
                return
            end
            editorState.cameraRig = rig
            editorState.cameraShots = valid
            if not shot then
                editorState.keyframes = clean
            end
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.camera.setPlayhead(editorState.playhead)
            ctx.projects.sendProject()
            callback({ ok = true, message = "Selection pasted." })
        end)

        ctx.bridge.editorCallback("saveLocation", function(data, callback)
            if #editorState.bookmarks >= Config.MaximumSavedLocations then
                callback({ ok = false, message = "Location limit reached." })
                return
            end
            local state = ctx.camera.getCameraState()
            if not state then
                callback({ ok = false, message = "Camera unavailable." })
                return
            end
            state.time = 0
            editorState.bookmarks[#editorState.bookmarks + 1] =
                { name = tostring(data.name or "Location"):sub(1, 48), camera = state }
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("deleteLocation", function(data, callback)
            local i = tonumber(data.index)
            if not i or not editorState.bookmarks[i] then
                callback({ ok = false, message = "Location missing." })
                return
            end
            table.remove(editorState.bookmarks, i)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("goLocation", function(data, callback)
            local location = editorState.bookmarks[tonumber(data.index)]
            if not location then
                callback({ ok = false, message = "Location missing." })
                return
            end
            if select(1, ctx.camera.rigAtTime(editorState.playhead)).mode ~= "manual" then
                callback({ ok = false, message = "Switch the current camera mode to Manual first." })
                return
            end
            editorState.previewing = false
            ctx.camera.resetMotion()
            ctx.camera.applyState(location.camera)
            ctx.camera.sendCameraState()
            callback({ ok = true })
        end)
    end
end
