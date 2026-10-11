-- Camera transforms, rigs and shot previews.
DirectorClient.modules.camera = function(ctx)
    local editorState = ctx.state
    ctx.camera = {}

    function ctx.camera.editingShot()
        return DirectorShots.find(editorState.cameraShots, editorState.selectedShotId)
    end

    function ctx.camera.editingFrames()
        local shot = ctx.camera.editingShot()
        return shot and shot.frames or editorState.keyframes
    end

    function ctx.camera.frameCount()
        local count = #editorState.keyframes
        for _, shot in ipairs(editorState.cameraShots) do
            count = count + #shot.frames
        end
        return count
    end

    function ctx.camera.playbackBounds()
        return editorState.playbackRange and editorState.playbackRange.first or 0,
            editorState.playbackRange and math.min(editorState.duration, editorState.playbackRange.last)
                or editorState.duration
    end

    function ctx.camera.resetMotion()
        editorState.movementVelocity.x, editorState.movementVelocity.y, editorState.movementVelocity.z = 0.0, 0.0, 0.0
        editorState.turnVelocity.pitch, editorState.turnVelocity.yaw = 0.0, 0.0
    end

    function ctx.camera.getCameraState()
        if not editorState.camera or not DoesCamExist(editorState.camera) then
            return nil
        end

        local position = GetCamCoord(editorState.camera)
        local rotation = GetCamRot(editorState.camera, 2)
        return {
            x = position.x,
            y = position.y,
            z = position.z,
            rx = rotation.x,
            ry = rotation.y,
            rz = rotation.z,
            fov = GetCamFov(editorState.camera),
        }
    end

    function ctx.camera.sendCameraState()
        local state = ctx.camera.getCameraState()
        if state then
            local signature = ("%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f"):format(
                state.x,
                state.y,
                state.z,
                state.rx,
                state.ry,
                state.rz,
                state.fov
            )
            if signature == editorState.lastCameraPacket then
                return
            end
            editorState.lastCameraPacket = signature
            SendNUIMessage({ action = "camera", camera = state })
        end
    end

    function ctx.camera.addKeyframe(atTime)
        local keyframes = ctx.camera.editingFrames()
        local shot = ctx.camera.editingShot()
        local state = ctx.camera.getCameraState()
        if not state then
            return false, "Camera is not ready."
        end

        local time = ctx.maths.clamp(tonumber(atTime) or editorState.playhead, 0.0, editorState.duration)
        if shot and (time < shot.time or time > shot.time + shot.duration) then
            return false, "Move the playhead inside the selected shot."
        end
        state.time = time

        local replaced = false
        for index, frame in ipairs(keyframes) do
            if math.abs(frame.time - time) < 0.05 then
                state.name = frame.name
                keyframes[index] = state
                replaced = true
                break
            end
        end

        if not replaced then
            if ctx.camera.frameCount() >= Config.MaximumKeyframes then
                return false, "Keyframe limit reached."
            end
            keyframes[#keyframes + 1] = state
        end

        table.sort(keyframes, function(a, b)
            return a.time < b.time
        end)
        editorState.playhead = time
        ctx.projects.sendProject()
        return true
    end

    function ctx.camera.stateAtTime(time)
        local shot = DirectorShots.at(editorState.cameraShots, time)
        return DirectorMotion.sample(shot and shot.frames or editorState.keyframes, time, shot and shot.ease)
            or (shot and shot.rig.anchor)
    end

    function ctx.camera.rigAtTime(time)
        local shot = DirectorShots.at(editorState.cameraShots, time)
        return shot and shot.rig or editorState.cameraRig, shot
    end

    function ctx.camera.applyState(state)
        if not state or not editorState.camera or not DoesCamExist(editorState.camera) then
            return
        end

        SetCamCoord(editorState.camera, state.x + 0.0, state.y + 0.0, state.z + 0.0)
        SetCamRot(editorState.camera, state.rx + 0.0, state.ry + 0.0, state.rz + 0.0, 2)
        SetCamFov(editorState.camera, ctx.maths.clamp(state.fov, 20.0, 100.0) + 0.0)
    end

    function ctx.camera.setPlayhead(time)
        if ctx.actions.stopAnimationPreview then
            ctx.actions.stopAnimationPreview(false)
        end
        ctx.camera.resetMotion()
        editorState.playhead = ctx.maths.clamp(tonumber(time) or 0.0, 0.0, editorState.duration)
        if ctx.playback.sceneApply then
            ctx.playback.sceneApply(editorState.playhead, true)
        end
        local state = ctx.camera.stateAtTime(editorState.playhead)
        ctx.camera.applyState(state)
        if ctx.camera.applyCameraRig then
            ctx.camera.applyCameraRig(editorState.playhead, state or editorState.cameraRig.anchor, true)
        end
    end

    function ctx.camera.startPreview()
        if ctx.actions.stopAnimationPreview then
            ctx.actions.stopAnimationPreview(true)
        end
        if #editorState.keyframes == 0 and #editorState.cameraShots == 0 and editorState.cameraRig.mode == "manual" then
            return false, "Add at least one keyframe first."
        end

        local first, last = ctx.camera.playbackBounds()
        if editorState.playhead < first or editorState.playhead >= last then
            editorState.playhead = first
        end
        ctx.camera.resetMotion()
        editorState.pressedKeys = {}
        editorState.previewing = true
        editorState.previewOffset = editorState.playhead
        editorState.previewStartedAt = GetGameTimer()
        return true
    end

    function ctx.camera.sampleRig(rig, base, time)
        if rig.mode == "manual" then
            return base
        end
        local handle = editorState.sceneEntities[rig.targetId]
        if not handle or not DoesEntityExist(handle) then
            return base
        end
        local p = GetEntityCoords(handle)
        return DirectorCameraRig.sample(
            rig,
            { x = p.x, y = p.y, z = p.z, heading = GetEntityHeading(handle) },
            base or rig.anchor or ctx.camera.getCameraState(),
            time
        )
    end

    ctx.camera.applyCameraRig = function(time, base, forceBlend)
        local rig, shot = ctx.camera.rigAtTime(time)
        local blending = shot
            and (shot.blend or 0) > 0
            and time < shot.time + shot.blend
            and (editorState.previewing or forceBlend)
        if rig.mode == "manual" and not blending then
            return
        end
        local state = ctx.camera.sampleRig(rig, base, shot and time - shot.time or time)
        if blending and state then
            local previous
            for _, candidate in ipairs(editorState.cameraShots) do
                if candidate.time < shot.time and math.abs(candidate.time + candidate.duration - shot.time) < 0.001 then
                    previous = candidate
                end
            end
            if previous then
                local before = DirectorMotion.sample(previous.frames, previous.time + previous.duration, previous.ease)
                    or previous.rig.anchor
                before = ctx.camera.sampleRig(previous.rig, before, previous.duration)
                if before then
                    state = DirectorShots.blend(before, state, (time - shot.time) / shot.blend)
                end
            end
        end
        if state and rig.avoidObstacles and rig.mode ~= "manual" then
            local handle = editorState.sceneEntities[rig.targetId]
            if handle and DoesEntityExist(handle) then
                local p = GetEntityCoords(handle)
                state = DirectorObstacles.camera(
                    rig,
                    { x = p.x, y = p.y, z = p.z + (rig.targetHeight or 0) },
                    state,
                    handle,
                    GetGameTimer(),
                    time
                )
            end
        end
        ctx.camera.applyState(state)
    end

    function ctx.camera.loadCameraRig(value)
        editorState.cameraRig = type(value) == "table" and value or { mode = "manual" }
        if editorState.cameraRig.mode ~= "manual" and not editorState.sceneEntities[editorState.cameraRig.targetId] then
            editorState.cameraRig = { mode = "manual" }
        end
        ctx.camera.applyCameraRig(
            editorState.playhead,
            ctx.camera.stateAtTime(editorState.playhead) or editorState.cameraRig.anchor
        )
    end

    ctx.camera.stopShotPreview = function()
        if not editorState.shotPreview then
            return
        end
        local previous = editorState.shotPreview
        editorState.shotPreview = nil
        editorState.playhead = previous.time
        ctx.playback.sceneApply(editorState.playhead, true)
        ctx.camera.applyState(previous.camera)
        SendNUIMessage({ action = "shotPreviewStopped" })
    end

    return function()
        ctx.bridge.editorCallback("setFov", function(data, callback)
            local fov = ctx.maths.clamp(tonumber(data.fov) or 50.0, 20.0, 100.0)
            local rig = ctx.camera.editingShot() and ctx.camera.editingShot().rig or editorState.cameraRig
            if rig.anchor then
                rig.anchor.fov = fov
                ctx.projects.sendProject()
                SendNUIMessage({ action = "saveState", saved = false })
            end
            if editorState.camera and DoesCamExist(editorState.camera) then
                SetCamFov(editorState.camera, fov + 0.0)
            end
            ctx.camera.sendCameraState()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setKeyframeFov", function(data, callback)
            local keyframes = ctx.camera.editingFrames()
            local index, fov = tonumber(data.index), tonumber(data.fov)
            if not index or not keyframes[index] or not fov or fov ~= fov then
                callback({ ok = false, message = "Camera shot not found." })
                return
            end
            keyframes[index].fov = ctx.maths.clamp(fov, 20.0, 100.0)
            if
                math.abs(editorState.playhead - keyframes[index].time) < 0.05
                and editorState.camera
                and DoesCamExist(editorState.camera)
            then
                SetCamFov(editorState.camera, keyframes[index].fov + 0.0)
            end
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setKeyframeName", function(data, callback)
            local keyframes = ctx.camera.editingFrames()
            local index = tonumber(data.index)
            if not index or not keyframes[index] then
                callback({ ok = false, message = "Camera shot not found." })
                return
            end
            keyframes[index].name = tostring(data.name or ""):gsub("[\r\n]", " "):sub(1, 48)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setSpeed", function(data, callback)
            editorState.cameraSpeed = ctx.maths.clamp(tonumber(data.speed) or Config.DefaultCameraSpeed, 0.5, 30.0)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setCameraRig", function(data, callback)
            local shot = ctx.camera.editingShot()
            local mode = tostring(data.mode or "manual")
            if mode == "manual" then
                if shot and #shot.frames == 0 and ctx.camera.frameCount() >= Config.MaximumKeyframes then
                    callback({ ok = false, message = "Camera keyframe limit reached." })
                    return
                end
                editorState.previewing = false
                editorState.pressedKeys = {}
                ctx.camera.resetMotion()
                if shot then
                    if #shot.frames == 0 then
                        local anchor = DirectorShots.copy(shot.rig.anchor or ctx.camera.getCameraState())
                        anchor.time = shot.time
                        shot.frames = { anchor }
                    end
                    shot.rig = { mode = "manual" }
                else
                    editorState.cameraRig = { mode = "manual" }
                end
                ctx.projects.sendProject()
                callback({ ok = true })
                return
            end
            if mode ~= "target" and mode ~= "follow" and mode ~= "orbit" then
                callback({ ok = false, message = "Choose a camera mode." })
                return
            end
            local id = tonumber(data.targetId)
            local handle = id and editorState.sceneEntities[id]
            local state = ctx.camera.getCameraState()
            if not handle or not DoesEntityExist(handle) or not state then
                callback({ ok = false, message = "Choose a staged subject first." })
                return
            end
            local targetHeight = ctx.maths.finiteNumber(data.targetHeight, 20)
            local radius = ctx.maths.finiteNumber(data.radius, 1000)
            local elevation = ctx.maths.finiteNumber(data.elevation, 100)
            local speed = ctx.maths.finiteNumber(data.speed, 90)
            if not targetHeight or not radius or radius < 0.5 or not elevation or not speed then
                callback({ ok = false, message = "Check the camera settings." })
                return
            end
            local position = GetEntityCoords(handle)
            local dx, dy = state.x - position.x, state.y - position.y
            local offsetX, offsetY = dx, dy
            local relative = data.relative == true
            if relative then
                local heading = math.rad(GetEntityHeading(handle))
                offsetX, offsetY =
                    dx * math.cos(heading) + dy * math.sin(heading), -dx * math.sin(heading) + dy * math.cos(heading)
            end
            local rig = {
                mode = mode,
                targetId = id,
                targetHeight = targetHeight,
                relative = relative,
                avoidObstacles = data.avoidObstacles == true,
                offsetX = offsetX,
                offsetY = offsetY,
                offsetZ = state.z - position.z - targetHeight,
                radius = radius,
                elevation = elevation,
                speed = speed,
                startAngle = math.deg(math.atan(dy, dx))
                    - (shot and editorState.playhead - shot.time or editorState.playhead) * speed,
                anchor = state,
            }
            if shot then
                shot.rig = rig
            else
                editorState.cameraRig = rig
            end
            editorState.previewing = false
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            ctx.camera.applyCameraRig(editorState.playhead, state)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("preview", function(_, callback)
            local ok, message = ctx.camera.startPreview()
            SendNUIMessage({ action = ok and "previewStarted" or "status", message = message })
            callback({ ok = ok, message = message })
        end)
    end
end
