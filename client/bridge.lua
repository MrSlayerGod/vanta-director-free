-- NUI callback validation and history boundaries.
DirectorClient.modules.bridge = function(ctx)
    local editorState = ctx.state
    ctx.bridge = {}

    function ctx.bridge.editorCallback(name, handler)
        RegisterNUICallback(name, function(data, callback)
            if type(data) ~= "table" then
                callback({ ok = false, message = "Invalid editor request." })
                return
            end
            if not editorState.directorOpen and name ~= "close" and name ~= "getPreferences" then
                callback({ ok = false, message = "Director is closed." })
                return
            end
            if
                editorState.routeCommands[name]
                and data.routeToken ~= nil
                and (not editorState.routeDraft or data.routeToken ~= editorState.routeDraft.token)
            then
                callback({ ok = false, message = "This route request is obsolete." })
                return
            end
            if
                editorState.editBusy
                and (
                    name == "addRoutePoint"
                    or name == "moveRoutePoint"
                    or name == "beginRoutePoint"
                    or name == "deleteRoutePoint"
                )
            then
                callback({ ok = false, message = "Wait for route inspection to finish." })
                return
            end
            if editorState.historyBusy and name ~= "setKeys" and name ~= "mouseLook" and name ~= "close" then
                callback({ ok = false, message = "Restoring the scene." })
                return
            end
            if
                (editorState.historyBusy or editorState.editBusy)
                and (
                    editorState.historyEdits[name]
                    or name == "beginActorDrag"
                    or name == "undo"
                    or name == "redo"
                    or name == "manageProject"
                )
            then
                callback({ ok = false, message = "An edit is still being applied." })
                return
            end
            if
                editorState.routeDraft
                and (
                    name == "preview"
                    or name == "capture"
                    or name == "saveProject"
                    or name == "previewCameraPreset"
                    or name == "applyCameraPreset"
                )
            then
                callback({ ok = false, message = "Apply or cancel the route first." })
                return
            end
            if editorState.motionRecording then
                callback({ ok = false, message = "Stop or cancel movement recording first." })
                return
            end
            if editorState.shotPreview and name ~= "setKeys" and name ~= "mouseLook" then
                ctx.camera.stopShotPreview()
            end
            if
                editorState.collaboration
                and editorState.collaboration.role == "viewer"
                and (
                    editorState.historyEdits[name]
                    or name == "beginActorDrag"
                    or name == "undo"
                    or name == "redo"
                    or name == "saveProject"
                    or name == "manageProject"
                    or name == "importProject"
                    or name == "startMotionRecording"
                    or name == "commitRoute"
                )
            then
                callback({ ok = false, message = "The session host controls scene edits." })
                return
            end
            local before = editorState.historyEdits[name] and DirectorHistory.copy(ctx.projects.projectPayload()) or nil
            if name == "beginActorDrag" then
                editorState.dragBefore = DirectorHistory.copy(ctx.projects.projectPayload())
            end
            if before then
                editorState.editBusy = true
            end
            local responded = false
            local function respond(result)
                if responded then
                    return
                end
                result = type(result) == "table" and result or { ok = false, message = "Invalid editor response." }
                if before then
                    editorState.editBusy = false
                    if result.ok then
                        local grouped = name == "setFov"
                            or name == "setSceneLook"
                            or name == "setProjectName"
                            or name == "setKeyframeFov"
                        DirectorHistory.commit(
                            editorState.history,
                            before,
                            ctx.projects.projectPayload(),
                            grouped and (name .. ":" .. tostring(data.index or "")) or nil,
                            GetGameTimer()
                        )
                    end
                    ctx.history.sendHistory()
                elseif name == "endActorDrag" then
                    if result.ok and editorState.dragBefore then
                        DirectorHistory.commit(
                            editorState.history,
                            editorState.dragBefore,
                            ctx.projects.projectPayload()
                        )
                    end
                    editorState.dragBefore = nil
                    ctx.history.sendHistory()
                end
                responded = true
                callback(result)
            end
            local ok, err = xpcall(function()
                handler(data, respond)
            end, debug.traceback)
            if not ok then
                editorState.editBusy = false
                editorState.historyBusy = false
                editorState.dragBefore = nil
                editorState.routeDraft = nil
                editorState.pressedKeys = {}
                pcall(SendNUIMessage, { action = "routeClosed" })
                pcall(ctx.history.sendHistory)
                pcall(ctx.projects.sendProject)
                if before then
                    pcall(SendNUIMessage, { action = "saveState", saved = false })
                end
                print(("[VANTA DIRECTOR] Callback %s failed: %s"):format(name, tostring(err):sub(1, 1500)))
                if not responded then
                    responded = true
                    callback({
                        ok = false,
                        message = "This edit could not be applied. Close or reload the scene if needed.",
                    })
                end
            end
        end)
    end

    return function() end
end
