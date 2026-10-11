-- Per-frame camera input, preview updates and UI synchronization.
DirectorClient.modules.frame = function(ctx)
    local editorState = ctx.state
    ctx.frame = {}

    return function()
        CreateThread(function()
            while true do
                if not editorState.directorOpen or not editorState.camera or not DoesCamExist(editorState.camera) then
                    Wait(250)
                elseif editorState.motionRecording then
                    Wait(50)
                else
                    local deltaSeconds = math.min(GetFrameTime(), 0.1)
                    if GetGameTimer() - editorState.lastInputAt > 750 then
                        editorState.pressedKeys = {}
                    end
                    DisableAllControlActions(0)
                    DisplayHud(false)
                    DisplayRadar(false)
                    ctx.environment.applySceneLook(false)
                    if
                        editorState.collaboration
                        and editorState.camera
                        and DoesCamExist(editorState.camera)
                        and GetGameTimer() - editorState.lastStreamingFocusUpdate >= 100
                    then
                        editorState.lastStreamingFocusUpdate = GetGameTimer()
                        local p = GetCamCoord(editorState.camera)
                        SetFocusPosAndVel(p.x + 0.0, p.y + 0.0, p.z + 0.0, 0.0, 0.0, 0.0)
                        editorState.focusOwned = true
                    end
                    if editorState.sessionPendingPlayback then
                        local pending = editorState.sessionPendingPlayback
                        local elapsed = (
                            (GetNetworkTimeAccurate() - pending.clock + 2147483648) % 4294967296 - 2147483648
                        ) / 1000
                        if elapsed >= 0 then
                            editorState.sessionPendingPlayback = nil
                            editorState.playhead = math.min(pending.last, pending.first + elapsed)
                            if editorState.playhead < pending.last then
                                ctx.camera.startPreview()
                                SendNUIMessage({ action = "previewStarted" })
                            end
                        end
                    end

                    if DirectorModelBrowser.active then
                        editorState.pressedKeys = {}
                        editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
                        ctx.camera.resetMotion()
                    elseif editorState.shotPreview then
                        editorState.pressedKeys = {}
                        editorState.mouseLookX, editorState.mouseLookY = 0, 0
                        local draft = editorState.shotPreview.draft
                        local elapsed = math.min((GetGameTimer() - editorState.shotPreview.clock) / 1000, draft.seconds)
                        editorState.previewing = true
                        ctx.playback.sceneApply(math.min(draft.start + elapsed, editorState.duration))
                        editorState.previewing = false
                        if draft.rig then
                            local handle = editorState.sceneEntities[draft.rig.targetId]
                            if handle and DoesEntityExist(handle) then
                                local point = GetEntityCoords(handle)
                                ctx.camera.applyState(
                                    DirectorCameraRig.sample(
                                        draft.rig,
                                        { x = point.x, y = point.y, z = point.z },
                                        draft.camera,
                                        elapsed
                                    )
                                )
                            else
                                ctx.camera.stopShotPreview()
                            end
                        else
                            ctx.camera.applyState(DirectorMotion.sample(draft.frames, elapsed))
                        end
                        if elapsed >= draft.seconds then
                            ctx.camera.stopShotPreview()
                        end
                    elseif editorState.previewing then
                        editorState.playhead = editorState.previewOffset
                            + (GetGameTimer() - editorState.previewStartedAt) / 1000.0
                        local first, last = ctx.camera.playbackBounds()
                        if editorState.playhead >= last then
                            if editorState.playbackRange and editorState.playbackRange.loop then
                                editorState.playhead = first + (editorState.playhead - first) % (last - first)
                                editorState.previewOffset = editorState.playhead
                                editorState.previewStartedAt = GetGameTimer()
                                ctx.playback.sceneApply(editorState.playhead, true)
                            else
                                editorState.playhead = last
                                editorState.previewing = false
                            end
                        end
                        ctx.playback.sceneApply(editorState.playhead)
                        local base = ctx.camera.stateAtTime(editorState.playhead) or editorState.cameraRig.anchor
                        ctx.camera.applyState(base)
                        ctx.camera.applyCameraRig(editorState.playhead, base, true)
                        if editorState.captureMode and not editorState.previewing then
                            ctx.capture.endCapture()
                        end
                    elseif
                        select(1, ctx.camera.rigAtTime(editorState.playhead)).mode == "follow"
                        or select(1, ctx.camera.rigAtTime(editorState.playhead)).mode == "orbit"
                    then
                        editorState.pressedKeys = {}
                        editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
                        ctx.camera.resetMotion()
                        if editorState.dragSession then
                            ctx.placement.sceneDragUpdate(deltaSeconds)
                        end
                        ctx.camera.applyCameraRig(
                            editorState.playhead,
                            ctx.camera.stateAtTime(editorState.playhead) or editorState.cameraRig.anchor
                        )
                    else
                        if editorState.dragSession then
                            editorState.pressedKeys = {}
                            editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
                            ctx.camera.resetMotion()
                        end
                        if
                            DirectorMotion.cameraActive(
                                editorState.pressedKeys,
                                editorState.movementVelocity,
                                editorState.turnVelocity,
                                editorState.mouseLookX,
                                editorState.mouseLookY
                            )
                        then
                            local rotation = GetCamRot(editorState.camera, 2)
                            local position = GetCamCoord(editorState.camera)
                            local yaw = math.rad(rotation.z)
                            local pitch = math.rad(rotation.x)
                            local forward = vector3(
                                -math.sin(yaw) * math.cos(pitch),
                                math.cos(yaw) * math.cos(pitch),
                                math.sin(pitch)
                            )
                            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
                            local move = vector3(0.0, 0.0, 0.0)

                            if editorState.pressedKeys.w then
                                move = move + forward
                            end
                            if editorState.pressedKeys.s then
                                move = move - forward
                            end
                            if editorState.pressedKeys.d then
                                move = move + right
                            end
                            if editorState.pressedKeys.a then
                                move = move - right
                            end
                            if editorState.pressedKeys.e then
                                move = move + vector3(0.0, 0.0, 1.0)
                            end
                            if editorState.pressedKeys.q then
                                move = move - vector3(0.0, 0.0, 1.0)
                            end

                            local length = math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
                            local scale = length > 0.0 and editorState.cameraSpeed / length or 0.0
                            local distance = {}
                            for _, axis in ipairs({ "x", "y", "z" }) do
                                editorState.movementVelocity[axis], distance[axis] = DirectorMotion.damp(
                                    editorState.movementVelocity[axis],
                                    move[axis] * scale,
                                    deltaSeconds,
                                    Config.CameraMoveResponse
                                )
                                if math.abs(editorState.movementVelocity[axis]) < 0.0001 then
                                    editorState.movementVelocity[axis] = 0.0
                                end
                            end
                            if distance.x ~= 0.0 or distance.y ~= 0.0 or distance.z ~= 0.0 then
                                SetCamCoord(
                                    editorState.camera,
                                    (position.x + distance.x) + 0.0,
                                    (position.y + distance.y) + 0.0,
                                    (position.z + distance.z) + 0.0
                                )
                            end

                            local targetYaw = (
                                (editorState.pressedKeys.arrowleft and 1 or 0)
                                - (editorState.pressedKeys.arrowright and 1 or 0)
                            ) * 65.0
                            local targetPitch = (
                                (editorState.pressedKeys.arrowup and 1 or 0)
                                - (editorState.pressedKeys.arrowdown and 1 or 0)
                            ) * 65.0
                            local yawStep, pitchStep
                            editorState.turnVelocity.yaw, yawStep = DirectorMotion.damp(
                                editorState.turnVelocity.yaw,
                                targetYaw,
                                deltaSeconds,
                                Config.CameraLookResponse
                            )
                            editorState.turnVelocity.pitch, pitchStep = DirectorMotion.damp(
                                editorState.turnVelocity.pitch,
                                targetPitch,
                                deltaSeconds,
                                Config.CameraLookResponse
                            )
                            if targetYaw == 0.0 and math.abs(editorState.turnVelocity.yaw) < 0.0001 then
                                editorState.turnVelocity.yaw = 0.0
                            end
                            if targetPitch == 0.0 and math.abs(editorState.turnVelocity.pitch) < 0.0001 then
                                editorState.turnVelocity.pitch = 0.0
                            end
                            local mouseYaw = editorState.mouseLookX
                                * Config.MouseLookSensitivity
                                * editorState.preferences.sensitivity
                            local mousePitch = editorState.mouseLookY
                                * Config.MouseLookSensitivity
                                * editorState.preferences.sensitivity
                                * (editorState.preferences.invert and -1 or 1)
                            editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
                            if yawStep ~= 0.0 or pitchStep ~= 0.0 or mouseYaw ~= 0.0 or mousePitch ~= 0.0 then
                                SetCamRot(
                                    editorState.camera,
                                    (ctx.maths.clamp(rotation.x + pitchStep - mousePitch, -89.0, 89.0)) + 0.0,
                                    rotation.y + 0.0,
                                    (ctx.maths.wrapAngle(rotation.z + yawStep - mouseYaw)) + 0.0,
                                    2
                                )
                            end
                        end
                        if editorState.dragSession then
                            ctx.placement.sceneDragUpdate(deltaSeconds)
                        end
                        -- Target mode must still follow a moving subject while camera input is idle.
                        if select(1, ctx.camera.rigAtTime(editorState.playhead)).mode ~= "manual" then
                            ctx.camera.applyCameraRig(editorState.playhead, ctx.camera.getCameraState())
                        end
                    end

                    local now = GetGameTimer()
                    if
                        not editorState.captureMode
                        and not DirectorModelBrowser.active
                        and now - editorState.lastUiUpdate >= (Config.UiUpdateIntervalMs or 100)
                    then
                        editorState.lastUiUpdate = now
                        local signature = ("%.3f:%s"):format(editorState.playhead, tostring(editorState.previewing))
                        if signature ~= editorState.lastTransportPacket then
                            editorState.lastTransportPacket = signature
                            SendNUIMessage({
                                action = "playhead",
                                time = editorState.playhead,
                                playing = editorState.previewing,
                            })
                        end
                        ctx.camera.sendCameraState()
                    end
                    if
                        not editorState.captureMode
                        and not DirectorModelBrowser.active
                        and now - editorState.lastActorScreenUpdate
                            >= ((editorState.previewing or editorState.dragSession or editorState.routeDraft or next(
                                editorState.pressedKeys
                            )) and 33 or 150)
                    then
                        editorState.lastActorScreenUpdate = now
                        ctx.placement.sceneSendScreenPositions()
                        if editorState.routeDraft then
                            ctx.routes.sendRouteScreen()
                        end
                    end
                    Wait(0)
                end
            end
        end)
    end
end
