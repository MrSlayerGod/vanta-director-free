-- Camera shot and preset editing.
DirectorClient.modules.shots = function(ctx)
    local editorState = ctx.state
    ctx.shots = {}

    function ctx.shots.buildCameraPreset(data)
        if
            not editorState.directorOpen
            or editorState.previewing
            or editorState.captureMode
            or editorState.dragSession
            or editorState.routeDraft
            or DirectorModelBrowser.active
        then
            return nil, "Stop the current preview or edit first."
        end
        local token = editorState.sceneGeneration
        local base = ctx.camera.getCameraState()
        if not base then
            return nil, "Camera is not ready."
        end
        local target
        local id = tonumber(data.targetId)
        if id and id ~= 0 then
            local handle = editorState.sceneEntities[id]
            if not handle or not DoesEntityExist(handle) then
                return nil, "Choose an available scene subject."
            end
            local point = GetEntityCoords(handle)
            target = { id = id, x = point.x, y = point.y, z = point.z, aimHeight = 0 }
        else
            if data.kind == "follow" then
                return nil, "Follow needs a scene subject."
            end
            local x, y, z = ctx.scene.scenePlace()
            if not x then
                return nil, "Could not resolve the camera aim."
            end
            target = { x = x, y = y, z = z, aimHeight = 0 }
        end
        if not editorState.directorOpen or token ~= editorState.sceneGeneration then
            return nil, "Scene changed while preparing the shot."
        end
        local draft = DirectorCameraRig.preset(
            data.kind,
            target,
            base,
            tonumber(data.seconds),
            tonumber(data.distance),
            tonumber(data.height),
            tonumber(data.travel)
        )
        if not draft then
            return nil, "Check the shot settings."
        end
        if editorState.playhead + draft.seconds > Config.MaximumDuration then
            return nil, "The shot exceeds the maximum project duration."
        end
        draft.start = editorState.playhead
        draft.camera = base
        return draft
    end

    function ctx.shots.commitShots(candidate)
        local limit = editorState.duration
        for _, shot in ipairs(candidate) do
            limit = math.max(limit, shot.time + shot.duration)
        end
        if limit > Config.MaximumDuration then
            return false, "Maximum project duration exceeded."
        end
        local clean, message =
            DirectorShots.validate(candidate, limit, editorState.sceneActors, #editorState.keyframes, true)
        if not clean then
            return false, message
        end
        editorState.cameraShots = clean
        editorState.duration = limit
        return true
    end

    function ctx.shots.appendShot(frames, rig, seconds, name, start)
        local id = 1
        for _, shot in ipairs(editorState.cameraShots) do
            id = math.max(id, shot.id + 1)
        end
        local candidate = DirectorShots.copy(editorState.cameraShots)
        candidate[#candidate + 1] = {
            id = id,
            name = name,
            time = start,
            duration = seconds,
            frames = frames,
            rig = rig or { mode = "manual" },
            ease = "smooth",
        }
        local ok, message = ctx.shots.commitShots(candidate)
        if not ok then
            return false, message
        end
        editorState.selectedShotId = id
        ctx.camera.setPlayhead(start)
        ctx.projects.sendProject()
        return true
    end

    return function()
        ctx.bridge.editorCallback("previewCameraPreset", function(data, callback)
            local draft, message = ctx.shots.buildCameraPreset(data)
            if not draft then
                callback({ ok = false, message = message })
                return
            end
            ctx.actions.stopAnimationPreview(true)
            editorState.shotPreview =
                { draft = draft, time = editorState.playhead, camera = draft.camera, clock = GetGameTimer() }
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            callback({ ok = true, message = "Temporary preview. Your project is unchanged." })
        end)

        ctx.bridge.editorCallback("cancelCameraPreset", function(_, callback)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("applyCameraPreset", function(data, callback)
            local draft, message = ctx.shots.buildCameraPreset(data)
            if not draft then
                callback({ ok = false, message = message })
                return
            end
            local frames = draft.frames or {}
            for _, frame in ipairs(frames) do
                frame.time = frame.time + draft.start
            end
            local ok, message = ctx.shots.appendShot(frames, draft.rig, draft.seconds, draft.name, draft.start)
            callback({
                ok = ok,
                message = message or "Independent shot added. Its camera mode only applies inside this clip.",
            })
        end)

        ctx.bridge.editorCallback("createCameraShot", function(data, callback)
            local seconds = DirectorShots.number(data.duration or 6, 0.1, Config.MaximumDuration)
            local state = ctx.camera.getCameraState()
            if not seconds or not state then
                callback({ ok = false, message = "Invalid shot settings." })
                return
            end
            state.time = editorState.playhead
            local ok, message = ctx.shots.appendShot(
                { state },
                { mode = "manual" },
                seconds,
                "New shot",
                editorState.playhead
            )
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("selectCameraShot", function(data, callback)
            local shot = DirectorShots.find(editorState.cameraShots, data.id)
            editorState.selectedShotId = shot and shot.id or nil
            if shot then
                editorState.previewing = false
                ctx.camera.setPlayhead(shot.time)
            end
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("updateCameraShot", function(data, callback)
            local shot = DirectorShots.find(editorState.cameraShots, data.id)
            local time = DirectorShots.number(data.time, 0, Config.MaximumDuration)
            local seconds = DirectorShots.number(data.duration, 0.1, Config.MaximumDuration)
            if not shot or not time or not seconds then
                callback({ ok = false, message = "Invalid shot." })
                return
            end
            local candidate = DirectorShots.copy(editorState.cameraShots)
            for i, item in ipairs(candidate) do
                if item.id == shot.id then
                    candidate[i] = DirectorShots.retime(shot, time, seconds)
                    candidate[i].name = tostring(data.name or shot.name):sub(1, 48)
                    candidate[i].ease = data.ease or shot.ease
                    candidate[i].blend = tonumber(data.blend) or shot.blend or 0
                end
            end
            local ok, message = ctx.shots.commitShots(candidate)
            if ok then
                editorState.selectedShotId = shot.id
                ctx.camera.setPlayhead(time)
                ctx.projects.sendProject()
            end
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("deleteCameraShot", function(data, callback)
            local shot = DirectorShots.find(editorState.cameraShots, data.id)
            if not shot then
                callback({ ok = false, message = "Shot not found." })
                return
            end
            for i, item in ipairs(editorState.cameraShots) do
                if item.id == shot.id then
                    table.remove(editorState.cameraShots, i)
                    break
                end
            end
            editorState.selectedShotId = nil
            ctx.camera.setPlayhead(editorState.playhead)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("duplicateCameraShot", function(data, callback)
            local shot = DirectorShots.find(editorState.cameraShots, data.id)
            local start = DirectorShots.number(data.time, 0, Config.MaximumDuration)
            if not shot or not start then
                callback({ ok = false, message = "Invalid shot." })
                return
            end
            local copy = DirectorShots.retime(shot, start, shot.duration)
            local ok, message = ctx.shots.appendShot(copy.frames, copy.rig, copy.duration, copy.name .. " copy", start)
            callback({ ok = ok, message = message })
        end)
    end
end
