-- Project serialization, save requests and library responses.
DirectorClient.modules.projects = function(ctx)
    local editorState = ctx.state
    ctx.projects = {}

    function ctx.projects.publicActors()
        local actors = DirectorHistory.copy(editorState.sceneActors)
        for i, actor in ipairs(editorState.sceneActors) do
            local handle = editorState.sceneEntities[actor.id]
            actors[i].modelAvailable = not actor._missing and handle ~= nil and DoesEntityExist(handle) == true
        end
        return actors
    end

    function ctx.projects.sendProject()
        SendNUIMessage({
            action = "project",
            project = {
                name = editorState.projectName,
                id = editorState.currentProjectId,
                duration = editorState.duration,
                playhead = editorState.playhead,
                keyframes = ctx.camera.editingFrames(),
                cameraShots = editorState.cameraShots,
                bookmarks = editorState.bookmarks,
                playback = editorState.playbackRange or { first = 0, last = editorState.duration, loop = false },
                selectedShotId = editorState.selectedShotId,
                actors = ctx.projects.publicActors(),
                cameraRig = ctx.camera.editingShot() and ctx.camera.editingShot().rig or editorState.cameraRig,
                look = editorState.sceneLook,
            },
        })
    end

    function ctx.projects.withoutRuntimeState(value)
        if type(value) ~= "table" then
            return value
        end
        local result = {}
        for key, item in pairs(value) do
            if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
                result[key] = ctx.projects.withoutRuntimeState(item)
            end
        end
        return result
    end

    ctx.projects.projectPayload = function()
        return {
            id = editorState.currentProjectId,
            version = 4,
            name = editorState.projectName,
            duration = editorState.duration,
            keyframes = editorState.keyframes,
            actors = ctx.projects.withoutRuntimeState(editorState.sceneActors),
            look = editorState.sceneLook,
            cameraRig = ctx.projects.withoutRuntimeState(editorState.cameraRig),
            cameraShots = ctx.projects.withoutRuntimeState(editorState.cameraShots),
            bookmarks = editorState.bookmarks,
        }
    end

    function ctx.projects.loadProject(project, preserveIds)
        if editorState.shotPreview then
            ctx.camera.stopShotPreview()
        end
        editorState.sessionPendingPlayback = nil
        DirectorModelBrowser.close()
        if type(project) ~= "table" or type(project.keyframes) ~= "table" then
            return
        end

        editorState.playbackRange = nil
        editorState.timelineClipboard = nil
        editorState.history = DirectorHistory.new(40)
        editorState.dragBefore = nil
        ctx.history.sendHistory()
        editorState.previewing = false
        editorState.captureMode = false
        editorState.pendingSaveSnapshot = nil
        editorState.pendingDraftRequest = nil
        editorState.lastDraftRevision = nil
        editorState.playhead = 0.0
        editorState.projectName = tostring(project.name or editorState.projectName):sub(1, 64)
        editorState.duration = ctx.maths.clamp(
            tonumber(project.duration) or Config.DefaultDuration,
            Config.MinimumDuration,
            Config.MaximumDuration
        )
        editorState.keyframes = {}
        for _, frame in ipairs(project.keyframes) do
            if type(frame) == "table" then
                local values = { frame.time, frame.x, frame.y, frame.z, frame.rx, frame.ry, frame.rz, frame.fov }
                local valid = true
                for _, value in ipairs(values) do
                    if type(value) ~= "number" then
                        valid = false
                        break
                    end
                end
                if valid and #editorState.keyframes < Config.MaximumKeyframes then
                    editorState.keyframes[#editorState.keyframes + 1] = {
                        time = ctx.maths.clamp(frame.time, 0.0, editorState.duration),
                        name = tostring(frame.name or ""):gsub("[\r\n]", " "):sub(1, 48),
                        x = frame.x,
                        y = frame.y,
                        z = frame.z,
                        rx = frame.rx,
                        ry = frame.ry,
                        rz = frame.rz,
                        fov = ctx.maths.clamp(frame.fov, 20.0, 100.0),
                    }
                end
            end
        end
        table.sort(editorState.keyframes, function(a, b)
            return a.time < b.time
        end)
        -- Network-normalized projects use actor indices; local session backups keep live IDs.
        if ctx.scene.sceneLoad(project.actors, preserveIds == true) == false then
            return
        end
        ctx.environment.loadSceneLook(project.look)
        editorState.bookmarks = DirectorShots.copy(project.bookmarks or {})
        editorState.cameraShots = DirectorShots.copy(project.cameraShots or {})
        editorState.selectedShotId = nil
        ctx.camera.applyState(ctx.camera.stateAtTime(editorState.playhead))
        ctx.camera.loadCameraRig(project.cameraRig)
        ctx.projects.sendProject()
        SendNUIMessage({ action = "saveState", saved = true })
    end

    return function()
        ctx.bridge.editorCallback("saveDraft", function(_, callback)
            if not editorState.currentProjectId or Config.RecoveryEnabled == false then
                callback({ ok = false, message = "Recovery is unavailable." })
                return
            end
            editorState.draftRequestSerial = (editorState.draftRequestSerial or 0) + 1
            editorState.pendingDraftRequest = editorState.draftRequestSerial
            TriggerServerEvent(
                "vanta_director_free:saveDraft",
                ctx.projects.projectPayload(),
                editorState.pendingDraftRequest
            )
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("manageRecovery", function(data, callback)
            if data.operation ~= "restore" and data.operation ~= "discard" then
                callback({ ok = false, message = "Invalid recovery action." })
                return
            end
            TriggerServerEvent("vanta_director_free:manageRecovery", data.operation, data.revision)
            callback({ ok = true })
        end)

        RegisterNetEvent("vanta_director_free:recoveryState", function(draft)
            if editorState.directorOpen then
                if type(draft) == "table" and draft.projectId == editorState.currentProjectId then
                    editorState.lastDraftRevision = draft.revision
                end
                SendNUIMessage({ action = "recoveryState", draft = draft })
            end
        end)

        RegisterNetEvent("vanta_director_free:draftResult", function(requestId, ok, message, revision)
            if requestId ~= editorState.pendingDraftRequest then
                return
            end
            editorState.pendingDraftRequest = nil
            if ok then
                editorState.lastDraftRevision = revision
            end
            if editorState.directorOpen then
                SendNUIMessage({ action = "draftResult", ok = ok, message = message })
            end
        end)

        ctx.bridge.editorCallback("setProjectName", function(data, callback)
            editorState.projectName = tostring(data.name or "Untitled Project"):gsub("[\r\n]", " "):sub(1, 64)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("saveProject", function(_, callback)
            for _, actor in ipairs(editorState.sceneActors) do
                if actor._missing then
                    callback({
                        ok = false,
                        message = "A model is unavailable. Reload it or explicitly remove the actor before saving.",
                    })
                    return
                end
            end
            if not editorState.currentProjectId then
                callback({ ok = false, message = "Project library is still loading." })
                return
            end
            local payload = ctx.projects.projectPayload()
            editorState.pendingSaveSnapshot = DirectorHistory.copy(payload)
            editorState.saveRequestSerial = editorState.saveRequestSerial + 1
            editorState.pendingSaveRequest = editorState.saveRequestSerial
            TriggerServerEvent("vanta_director_free:saveProject", payload, editorState.pendingSaveRequest)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("manageProject", function(data, callback)
            local operation = tostring(data.operation or "")
            if
                operation ~= "create"
                and operation ~= "open"
                and operation ~= "duplicate"
                and operation ~= "rename"
                and operation ~= "delete"
            then
                callback({ ok = false, message = "Invalid project action." })
                return
            end
            TriggerServerEvent("vanta_director_free:manageProject", operation, data.id, data.name)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("exportProject", function(_, callback)
            callback({
                ok = true,
                json = json.encode(ctx.projects.projectPayload()),
                message = "Copy the JSON to share this project or keep it as a reusable scene template.",
            })
        end)

        ctx.bridge.editorCallback("importProject", function(data, callback)
            if type(data.json) ~= "string" or #data.json > Config.ProjectFileLimit then
                callback({ ok = false, message = "Project JSON is too large." })
                return
            end
            TriggerServerEvent("vanta_director_free:importProject", data.json)
            callback({ ok = true })
        end)

        RegisterNetEvent("vanta_director_free:projectLibrary", function(project, id, list, message)
            if not editorState.directorOpen then
                return
            end
            editorState.currentProjectId = id
            ctx.projects.loadProject(project)
            SendNUIMessage({ action = "library", activeId = id, projects = list, limit = Config.MaximumProjects })
            SendNUIMessage({ action = "status", message = message or "Project loaded." })
        end)

        RegisterNetEvent("vanta_director_free:projectMetadata", function(id, list, renamedId, name)
            if not editorState.directorOpen then
                return
            end
            if renamedId == editorState.currentProjectId then
                editorState.projectName = name
                ctx.projects.sendProject()
            end
            SendNUIMessage({ action = "library", activeId = id, projects = list, limit = Config.MaximumProjects })
        end)

        RegisterNetEvent("vanta_director_free:projectList", function(id, list)
            editorState.currentProjectId = id
            SendNUIMessage({ action = "library", activeId = id, projects = list, limit = Config.MaximumProjects })
        end)

        RegisterNetEvent("vanta_director_free:libraryError", function(message)
            SendNUIMessage({ action = "libraryError", message = message or "Project action failed." })
        end)

        RegisterNetEvent("vanta_director_free:saveResult", function(ok, message, project, requestId)
            if requestId ~= editorState.pendingSaveRequest then
                return
            end
            if not editorState.directorOpen then
                editorState.pendingSaveSnapshot = nil
                return
            end
            if not editorState.pendingSaveSnapshot then
                return
            end
            local unchangedSinceSave =
                DirectorHistory.same(ctx.projects.projectPayload(), editorState.pendingSaveSnapshot)
            editorState.pendingSaveSnapshot = nil
            if ok and unchangedSinceSave and editorState.lastDraftRevision then
                TriggerServerEvent("vanta_director_free:manageRecovery", "discard", editorState.lastDraftRevision)
                editorState.lastDraftRevision = nil
            end
            if ok and type(project) == "table" and unchangedSinceSave then
                SendNUIMessage({ action = "saveState", saved = true })
            elseif ok then
                SendNUIMessage({ action = "saveState", saved = false })
            end
            SendNUIMessage({ action = "saveResult", ok = ok, stale = ok and not unchangedSinceSave })
            local status = (ok and not unchangedSinceSave)
                    and "An earlier version was saved. Save again to include your latest edits."
                or message
                or (ok and "Saved." or "Save failed.")
            SendNUIMessage({ action = "status", message = status })
        end)
    end
end
