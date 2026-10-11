-- Clean take countdown and playback lifecycle.
DirectorClient.modules.capture = function(ctx)
    local editorState = ctx.state
    ctx.capture = {}

    function ctx.capture.endCapture()
        if not editorState.captureMode then
            return
        end
        editorState.captureMode = false
        editorState.previewing = false
        SendNUIMessage({ action = "captureEnd" })
        if
            editorState.selectedActorId
            and editorState.sceneEntities[editorState.selectedActorId]
            and DoesEntityExist(editorState.sceneEntities[editorState.selectedActorId])
        then
            ctx.placement.selectionOutline(editorState.sceneEntities[editorState.selectedActorId], true)
        end
        SetNuiFocus(true, true)
        ctx.camera.setPlayhead(select(1, ctx.camera.playbackBounds()))
    end

    return function()
        ctx.bridge.editorCallback("capture", function(_, callback)
            for _, actor in ipairs(editorState.sceneActors) do
                if actor._missing then
                    callback({
                        ok = false,
                        message = "Model unavailable: "
                            .. actor.model
                            .. ". Reload after installing it, or remove this actor before filming.",
                    })
                    return
                end
            end
            editorState.captureToken = editorState.captureToken + 1
            local token = editorState.captureToken
            if
                #editorState.keyframes == 0
                and #editorState.cameraShots == 0
                and editorState.cameraRig.mode == "manual"
            then
                callback({ ok = false, message = "Add a camera keyframe before recording." })
                return
            end
            editorState.previewing = false
            editorState.captureMode = true
            editorState.pressedKeys = {}
            if
                editorState.selectedActorId
                and editorState.sceneEntities[editorState.selectedActorId]
                and DoesEntityExist(editorState.sceneEntities[editorState.selectedActorId])
            then
                ctx.placement.selectionOutline(editorState.sceneEntities[editorState.selectedActorId], false)
            end
            SetNuiFocus(false, false)
            SendNUIMessage({ action = "captureCountdown", seconds = Config.CaptureCountdownSeconds })
            callback({ ok = true })
            CreateThread(function()
                Wait(Config.CaptureCountdownSeconds * 1000)
                if token ~= editorState.captureToken or not editorState.captureMode or not editorState.directorOpen then
                    return
                end
                editorState.playhead = select(1, ctx.camera.playbackBounds())
                ctx.camera.setPlayhead(editorState.playhead)
                local ok = ctx.camera.startPreview()
                if ok then
                    SendNUIMessage({ action = "captureGo" })
                else
                    ctx.capture.endCapture()
                end
            end)
        end)

        RegisterCommand("vanta_director_free_stop_take", function()
            if editorState.captureMode then
                ctx.capture.endCapture()
            end
        end, false)

        RegisterKeyMapping(
            "vanta_director_free_stop_take",
            ctx.lifecycle.localeText("VANTA DIRECTOR: stop clean take"),
            "keyboard",
            Config.StopTakeKey
        )

        ctx.bridge.editorCallback("stopPreview", function(_, callback)
            if editorState.captureMode then
                ctx.capture.endCapture()
            else
                editorState.previewing = false
            end
            ctx.camera.resetMotion()
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.camera.applyCameraRig(
                editorState.playhead,
                ctx.camera.stateAtTime(editorState.playhead) or editorState.cameraRig.anchor
            )
            callback({ ok = true })
        end)
    end
end
