-- Client session membership and synchronized playback requests.
DirectorClient.modules.collaboration = function(ctx)
    local editorState = ctx.state
    ctx.collaboration = {}

    function ctx.collaboration.releaseSessionPlayer()
        if editorState.sessionPlayer and DoesEntityExist(editorState.sessionPlayer.handle) then
            FreezeEntityPosition(editorState.sessionPlayer.handle, editorState.sessionPlayer.frozen)
        end
        editorState.sessionPlayer = nil
    end

    return function()
        ctx.bridge.editorCallback("collaboration", function(data, callback)
            local action = data.operation
            if (action == "create" or action == "accept") and IsPedInAnyVehicle(PlayerPedId(), false) then
                callback({ ok = false, message = "Leave your vehicle before shared filming." })
                return
            end
            if (action == "create" or action == "accept") and not editorState.currentProjectId then
                callback({ ok = false, message = "Wait for your project library to load." })
                return
            end
            if action == "create" then
                TriggerServerEvent(
                    "vanta_director_free:sessionAction",
                    "create",
                    { project = ctx.projects.projectPayload() }
                )
            elseif action == "invite" or action == "publish" or action == "play" or action == "stop" then
                if not editorState.collaboration or editorState.collaboration.role ~= "host" then
                    callback({ ok = false, message = "Create a hosted session first." })
                    return
                end
                local payload = { id = editorState.collaboration.id, target = tonumber(data.target) }
                if action == "publish" then
                    payload.project = ctx.projects.projectPayload()
                elseif action == "play" then
                    payload.start, payload.finish = ctx.camera.playbackBounds()
                    payload.clock = (GetNetworkTimeAccurate() + (Config.PlaybackLeadMs or 1500)) % 4294967296
                end
                TriggerServerEvent("vanta_director_free:sessionAction", action, payload)
            elseif action == "accept" or action == "decline" then
                TriggerServerEvent("vanta_director_free:sessionAction", action, { id = data.id })
            elseif action == "leave" then
                TriggerServerEvent("vanta_director_free:sessionAction", "leave", {})
            else
                callback({ ok = false, message = "Unknown collaboration action." })
                return
            end
            callback({ ok = true })
        end)

        RegisterNetEvent("vanta_director_free:sessionInvite", function(id, name)
            if editorState.directorOpen then
                SendNUIMessage({ action = "sessionInvite", id = id, name = name })
            else
                print(
                    "[VANTA DIRECTOR] Invitation received. Open Director first, then ask the host to invite you again."
                )
            end
        end)

        RegisterNetEvent("vanta_director_free:sessionState", function(id, host, role, revision, project)
            if not editorState.directorOpen or type(project) ~= "table" then
                return
            end
            if editorState.motionRecording then
                ctx.recording.finishMotionRecording(true)
            end
            if editorState.shotPreview then
                ctx.camera.stopShotPreview()
            end
            if editorState.captureMode then
                editorState.captureMode = false
                SetNuiFocus(true, true)
                SendNUIMessage({ action = "captureEnd" })
            end
            if role == "viewer" and not editorState.collaborationBackup then
                editorState.collaborationBackup = DirectorShots.copy(ctx.projects.projectPayload())
            end
            if not editorState.sessionPlayer then
                local ped = PlayerPedId()
                if DoesEntityExist(ped) then
                    editorState.sessionPlayer = { handle = ped, frozen = IsEntityPositionFrozen(ped) == true }
                    FreezeEntityPosition(ped, true)
                end
            end
            editorState.collaboration = { id = id, host = host, role = role, revision = revision }
            editorState.sessionPendingPlayback = nil
            ctx.projects.loadProject(project)
            if not editorState.directorOpen then
                return
            end
            local missing = false
            for _, actor in ipairs(editorState.sceneActors) do
                if actor._missing then
                    missing = true
                end
            end
            if missing or #editorState.sceneActors ~= #(project.actors or {}) then
                SendNUIMessage({
                    action = "status",
                    message = "Some session models failed to load. Ask the host to use models available on this client.",
                })
                return
            end
            SendNUIMessage({ action = "sessionState", role = role, host = host, id = id })
            SendNUIMessage({ action = "saveState", saved = false })
            TriggerServerEvent("vanta_director_free:sessionAction", "ready", { id = id, revision = revision })
        end)

        RegisterNetEvent("vanta_director_free:sessionEnded", function(message)
            local backup = editorState.collaborationBackup
            editorState.collaboration = nil
            editorState.collaborationBackup = nil
            editorState.sessionPendingPlayback = nil
            editorState.previewing = false
            ctx.collaboration.releaseSessionPlayer()
            if editorState.focusOwned then
                ClearFocus()
                editorState.focusOwned = false
            end
            if editorState.directorOpen and backup then
                editorState.currentProjectId = backup.id
                ctx.projects.loadProject(backup)
                SendNUIMessage({ action = "saveState", saved = false })
            end
            SendNUIMessage({ action = "sessionState", role = "none" })
            SendNUIMessage({ action = "status", message = message })
        end)

        RegisterNetEvent("vanta_director_free:sessionPlay", function(id, revision, first, last, clock)
            if
                not editorState.directorOpen
                or not editorState.collaboration
                or editorState.collaboration.id ~= id
                or editorState.collaboration.revision ~= revision
            then
                return
            end
            editorState.previewing = false
            editorState.playbackRange = { first = first, last = last, loop = false }
            ctx.camera.setPlayhead(first)
            editorState.sessionPendingPlayback = { first = first, last = last, clock = clock }
        end)

        RegisterNetEvent("vanta_director_free:sessionStop", function(id)
            if editorState.collaboration and editorState.collaboration.id == id then
                editorState.sessionPendingPlayback = nil
                editorState.previewing = false
                ctx.camera.setPlayhead(editorState.playhead)
            end
        end)

        RegisterNetEvent("vanta_director_free:collaborationStatus", function(message)
            SendNUIMessage({ action = "status", message = message })
        end)
    end
end
