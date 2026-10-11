-- Undo/redo snapshots and restoration.
DirectorClient.modules.history = function(ctx)
    local editorState = ctx.state
    ctx.history = {}

    function ctx.history.sendHistory()
        SendNUIMessage({
            action = "historyState",
            undo = #editorState.history.past,
            redo = #editorState.history.future,
            busy = editorState.historyBusy or editorState.editBusy,
        })
    end

    function ctx.history.applyHistory(direction, callback)
        if not editorState.directorOpen or editorState.captureMode or editorState.dragSession then
            callback({ ok = false, message = "Stop the current manipulation first." })
            return
        end
        local source = direction == "redo" and editorState.history.future or editorState.history.past
        local entry = source[#source]
        if not entry then
            callback({ ok = false, message = "Nothing to " .. direction .. "." })
            return
        end
        local target = DirectorHistory.copy(direction == "redo" and entry.after or entry.before)
        local current = DirectorHistory.copy(ctx.projects.projectPayload())
        local selected = editorState.selectedActorId
        editorState.historyBusy = true
        ctx.history.sendHistory()
        editorState.previewing = false
        editorState.pressedKeys = {}
        ctx.actions.stopAnimationPreview(false)
        DirectorModelBrowser.close()
        editorState.duration = target.duration
        editorState.keyframes = target.keyframes
        editorState.projectName = target.name
        local expectedGeneration = editorState.sceneGeneration + 2
        local ok = ctx.scene.sceneLoad(target.actors, true, true)
        ok = ok and #editorState.sceneActors == #target.actors
        if ok then
            ctx.environment.loadSceneLook(target.look)
            editorState.bookmarks = DirectorShots.copy(target.bookmarks or {})
            editorState.cameraShots = DirectorShots.copy(target.cameraShots or {})
            editorState.selectedShotId = nil
            ctx.camera.loadCameraRig(target.cameraRig)
            editorState.playhead = ctx.maths.clamp(editorState.playhead, 0, editorState.duration)
            ctx.camera.setPlayhead(editorState.playhead)
            if selected and editorState.sceneEntities[selected] then
                editorState.selectedActorId = selected
                ctx.placement.selectionOutline(editorState.sceneEntities[selected], true)
            end
            DirectorHistory.take(editorState.history, direction)
            ctx.projects.sendProject()
            SendNUIMessage({ action = "saveState", saved = false })
            SendNUIMessage({ action = "routeClosed" })
        elseif
            editorState.directorOpen
            and editorState.sceneGeneration == expectedGeneration
            and editorState.currentProjectId == current.id
        then
            editorState.duration = current.duration
            editorState.keyframes = current.keyframes
            editorState.projectName = current.name
            ctx.scene.sceneLoad(current.actors, true, true)
            ctx.environment.loadSceneLook(current.look)
            editorState.bookmarks = DirectorShots.copy(current.bookmarks or {})
            editorState.cameraShots = DirectorShots.copy(current.cameraShots or {})
            editorState.selectedShotId = nil
            ctx.camera.loadCameraRig(current.cameraRig)
            ctx.projects.sendProject()
        end
        editorState.historyBusy = false
        ctx.history.sendHistory()
        callback({ ok = ok, message = not ok and "Could not restore the scene." or nil })
    end

    return function()
        ctx.bridge.editorCallback("undo", function(_, callback)
            ctx.history.applyHistory("undo", callback)
        end)

        ctx.bridge.editorCallback("redo", function(_, callback)
            ctx.history.applyHistory("redo", callback)
        end)
    end
end
