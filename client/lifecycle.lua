-- Editor focus, opening, closing and resource cleanup.
DirectorClient.modules.lifecycle = function(ctx)
    local editorState = ctx.state
    ctx.lifecycle = {}

    function ctx.lifecycle.localeText(message)
        return DirectorLocale and DirectorLocale.text(message, editorState.preferences.language) or message
    end

    function ctx.lifecycle.clearProjectDialogBlur()
        if not editorState.projectDialogBlur then
            return
        end
        editorState.projectDialogBlur = false
        TriggerScreenblurFadeOut(150.0)
    end

    function ctx.lifecycle.setNuiOpen(state)
        if not state then
            ctx.lifecycle.clearProjectDialogBlur()
        end
        editorState.lastCameraPacket, editorState.lastActorPacket, editorState.lastTransportPacket = nil, nil, nil
        editorState.directorOpen = state
        editorState.nuiOpenSerial = editorState.nuiOpenSerial + 1
        SetNuiFocus(state and editorState.nuiReady, state and editorState.nuiReady)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = state and "open" or "close" })
        if state then
            SendNUIMessage({
                action = "runtimeConfig",
                config = {
                    edition = "free",
                    discordUrl = DirectorCommunity.discordUrl(),
                    minimumDuration = Config.MinimumDuration,
                    maximumDuration = Config.MaximumDuration,
                    projectFileLimit = Config.ProjectFileLimit,
                    recoveryEnabled = Config.RecoveryEnabled ~= false,
                    defaultDuration = Config.DefaultDuration,
                    recordingMaximumSeconds = Config.RecordingMaximumSeconds,
                    collaborationEnabled = Config.CollaborationEnabled,
                    stopTakeKey = Config.StopTakeKey,
                    stopRecordingKey = Config.StopRecordingKey,
                    cancelRecordingKey = Config.CancelRecordingKey,
                },
            })
            SendNUIMessage({
                action = "preferences",
                preferences = editorState.preferences,
                defaults = DirectorPreferences.defaults(),
            })
            local tutorialStatus = GetResourceKvpString("director_free:tutorial:v1")
            SendNUIMessage({
                action = "tutorialStatus",
                seen = tutorialStatus == "skipped" or tutorialStatus == "completed",
            })
        end
    end

    function ctx.lifecycle.restorePlayerView()
        ctx.lifecycle.clearProjectDialogBlur()
        editorState.motionRecording = nil
        if editorState.collaboration then
            TriggerServerEvent("vanta_director_free:sessionAction", "leave", {})
        end
        editorState.collaboration = nil
        editorState.collaborationBackup = nil
        editorState.sessionPendingPlayback = nil
        ctx.collaboration.releaseSessionPlayer()
        if editorState.focusOwned then
            ClearFocus()
            editorState.focusOwned = false
        end
        DirectorModelBrowser.close()
        if ctx.actions.stopAnimationPreview then
            ctx.actions.stopAnimationPreview(false)
        end
        editorState.pendingSaveSnapshot = nil
        ctx.environment.clearSceneLook()
        editorState.previewing = false
        editorState.captureMode = false
        editorState.dragSession = nil
        editorState.routeDraft = nil
        editorState.editBusy = false
        editorState.historyBusy = false
        editorState.dragBefore = nil
        editorState.selectedActorId = nil
        SendNUIMessage({ action = "close" })
        if ctx.scene.sceneClear then
            ctx.scene.sceneClear()
        end
        editorState.sceneActors = {}
        editorState.pressedKeys = {}
        editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
        ctx.camera.resetMotion()
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        RenderScriptCams(false, true, 250, true, true)
        if editorState.camera and DoesCamExist(editorState.camera) then
            DestroyCam(editorState.camera, false)
        end
        editorState.camera = nil
        DisplayHud(true)
        DisplayRadar(true)
        editorState.directorOpen = false
    end

    function ctx.lifecycle.toggleDirector()
        if editorState.motionRecording then
            ctx.recording.finishMotionRecording(false)
            return
        end
        if editorState.directorOpen then
            if editorState.captureMode then
                ctx.lifecycle.restorePlayerView()
            else
                SendNUIMessage({ action = "requestClose" })
            end
            return
        end

        editorState.history = DirectorHistory.new(40)
        editorState.dragBefore = nil
        local position = GetGameplayCamCoord()
        local rotation = GetGameplayCamRot(2)
        local fov = GetGameplayCamFov()

        ctx.camera.resetMotion()
        editorState.pressedKeys = {}
        editorState.currentProjectId = nil
        editorState.camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(editorState.camera, position.x + 0.0, position.y + 0.0, position.z + 0.0)
        SetCamRot(editorState.camera, rotation.x + 0.0, rotation.y + 0.0, rotation.z + 0.0, 2)
        SetCamFov(editorState.camera, fov + 0.0)
        RenderScriptCams(true, true, 250, true, true)

        DisplayHud(false)
        DisplayRadar(false)
        ctx.lifecycle.setNuiOpen(true)
        ctx.history.sendHistory()
        ctx.environment.applySceneLook(true)
        ctx.projects.sendProject()
        ctx.camera.sendCameraState()
        TriggerServerEvent("vanta_director_free:requestProject")
    end

    return function()
        RegisterNUICallback("tutorialStatus", function(data, callback)
            if type(data) ~= "table" or (data.status ~= "skipped" and data.status ~= "completed") then
                callback({ ok = false, message = "Invalid tutorial choice." })
                return
            end
            if not editorState.directorOpen then
                callback({ ok = false, message = "Director is closed." })
                return
            end
            SetResourceKvp("director_free:tutorial:v1", data.status)
            callback({ ok = true })
        end)

        RegisterNUICallback("projectDialog", function(data, callback)
            if type(data) ~= "table" or type(data.open) ~= "boolean" then
                callback({ ok = false, message = "Invalid dialog state." })
                return
            end
            local enabled = data.open and editorState.directorOpen and not editorState.captureMode
            if enabled and not editorState.projectDialogBlur then
                editorState.projectDialogBlur = true
                TriggerScreenblurFadeIn(150.0)
            elseif not enabled then
                ctx.lifecycle.clearProjectDialogBlur()
            end
            callback({ ok = true })
        end)

        RegisterNUICallback("nuiReady", function(_, callback)
            local first = not editorState.nuiReady
            editorState.nuiReady = true
            if first and editorState.directorOpen then
                ctx.lifecycle.setNuiOpen(true)
                ctx.projects.sendProject()
                TriggerServerEvent("vanta_director_free:requestProject")
            end
            callback({ ok = true })
        end)

        CreateThread(function()
            while true do
                if editorState.directorOpen and not editorState.nuiReady then
                    local serial = editorState.nuiOpenSerial
                    Wait(8000)
                    if
                        editorState.directorOpen
                        and not editorState.nuiReady
                        and serial == editorState.nuiOpenSerial
                    then
                        ctx.lifecycle.restorePlayerView()
                        ctx.lifecycle.setNuiOpen(false)
                        print(
                            ctx.lifecycle.localeText(
                                "[VANTA DIRECTOR] Interface failed to start. Focus released; check the packaged NUI files and refresh the resource."
                            )
                        )
                    end
                else
                    Wait(500)
                end
            end
        end)

        RegisterCommand(Config.Command, ctx.lifecycle.toggleDirector, false)

        RegisterCommand("director_free_ground", function()
            if not editorState.directorOpen then
                print(ctx.lifecycle.localeText("[VANTA DIRECTOR] Open the editor first."))
                return
            end
            for _, actor in ipairs(editorState.sceneActors) do
                local handle = editorState.sceneEntities[actor.id]
                if
                    actor.kind == "ped"
                    and (not editorState.selectedActorId or editorState.selectedActorId == actor.id)
                    and handle
                    and DoesEntityExist(handle)
                then
                    local root = GetEntityCoords(handle)
                    local left = GetPedBoneCoords(handle, 0x3779, 0.0, 0.0, 0.0)
                    local right = GetPedBoneCoords(handle, 0xCC4D, 0.0, 0.0, 0.0)
                    local surface = actor._ground and actor._ground.surface
                    local feet = left and right and math.min(left.z, right.z) - 0.04
                    print(
                        ("[VANTA DIRECTOR] model=%s rootZ=%.3f soleZ=%s groundZ=%s contactOffset=%s routeOffset=%.3f clearance=%.3f"):format(
                            actor.model,
                            root.z,
                            feet and ("%.3f"):format(feet) or "unavailable",
                            surface and ("%.3f"):format(surface.z) or "pending/unavailable",
                            actor._contactOffset and ("%.3f"):format(actor._contactOffset) or "uncalibrated",
                            ctx.playback.routeRootOffset(actor),
                            actor._groundClearance or 0.0
                        )
                    )
                end
            end
        end, false)

        RegisterKeyMapping(
            Config.Command,
            ctx.lifecycle.localeText("VANTA DIRECTOR: open or close camera mode"),
            "keyboard",
            Config.DefaultKey
        )

        ctx.bridge.editorCallback("getPreferences", function(_, callback)
            callback({ ok = true, preferences = editorState.preferences })
        end)

        ctx.bridge.editorCallback("setPreferences", function(data, callback)
            if not editorState.directorOpen then
                callback({ ok = false, message = "Director is closed." })
                return
            end
            local now = GetGameTimer()
            if now - editorState.preferencesWrittenAt < 500 then
                callback({ ok = false, message = "Wait a moment before saving settings again." })
                return
            end
            if type(data.preferences) ~= "table" then
                callback({ ok = false, message = "Invalid preferences." })
                return
            end
            editorState.preferencesWrittenAt = now
            editorState.preferences = DirectorPreferences.save(data.preferences)
            editorState.cameraSpeed = editorState.preferences.speed
            editorState.pressedKeys = {}
            editorState.mouseLookX, editorState.mouseLookY = 0, 0
            ctx.camera.resetMotion()
            callback({ ok = true, preferences = editorState.preferences })
        end)

        ctx.bridge.editorCallback("close", function(_, callback)
            ctx.lifecycle.restorePlayerView()
            callback({ ok = true })
        end)

        RegisterNetEvent("vanta_director_free:accessDenied", function(message)
            if editorState.directorOpen then
                ctx.lifecycle.restorePlayerView()
                ctx.lifecycle.setNuiOpen(false)
            end
            print("[VANTA DIRECTOR] " .. tostring(ctx.lifecycle.localeText(message)))
        end)

        AddEventHandler("onResourceStop", function(resourceName)
            if resourceName == GetCurrentResourceName() then
                ctx.lifecycle.restorePlayerView()
            end
        end)
    end
end
