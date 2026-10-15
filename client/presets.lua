DirectorClient.modules.presets = function(ctx)
    local state = ctx.state
    local storageKey = "director_free:presets:v1"
    local maximumBytes = Config.PresetFileLimit or 4194304
    local maximumEntries = Config.MaximumPresets or 100
    ctx.presets = {}

    local function read()
        local raw = GetResourceKvpString(storageKey)
        if not raw then
            return { version = 1, nextId = 1, entries = {} }
        end
        if #raw > maximumBytes then
            return nil, "The personal preset library is too large."
        end
        local ok, data = pcall(json.decode, raw)
        if
            not ok
            or type(data) ~= "table"
            or data.version ~= 1
            or not DirectorPayload.denseList(data.entries, maximumEntries)
        then
            return nil, "The personal preset library is damaged or uses a newer version. Nothing was overwritten."
        end
        local highest, seen = 0, {}
        for _, entry in ipairs(data.entries) do
            if
                type(entry) ~= "table"
                or not DirectorShots.number(entry.id, 1, 1000000000)
                or entry.id % 1 ~= 0
                or seen[entry.id]
            then
                return nil, "The personal preset library is damaged. Nothing was overwritten."
            end
            seen[entry.id] = true
            highest = math.max(highest, entry.id)
        end
        local counter = DirectorShots.number(data.nextId, 1, 1000000000)
        data.nextId = counter and counter % 1 == 0 and math.max(counter, highest + 1) or highest + 1
        return data
    end

    local function write(library)
        local encoded = json.encode(library)
        if #encoded > maximumBytes then
            return false, "The personal preset library is too large."
        end
        local previous = GetResourceKvpString(storageKey)
        if previous then
            SetResourceKvp(storageKey .. ":backup", previous)
        end
        SetResourceKvp(storageKey, encoded)
        if GetResourceKvpString(storageKey) ~= encoded then
            return false, "Could not save the personal preset library."
        end
        return true
    end

    local function cleanRecord(entry)
        if entry.kind ~= "camera" and entry.kind ~= "actions" then
            return nil
        end
        local valid, project = DirectorProject.validate(entry.project)
        if not valid then
            return nil
        end
        if
            entry.kind == "actions"
            and (not project.actors[entry.actorIndex] or #project.actors[entry.actorIndex].actions == 0)
        then
            return nil
        end
        return {
            id = entry.id,
            name = tostring(entry.name or "Preset"):sub(1, 48),
            kind = entry.kind,
            project = project,
            actorIndex = entry.actorIndex,
            shotId = entry.shotId,
        }
    end

    return function()
        ctx.bridge.editorCallback("createTemplate", function(data, callback)
            if state.previewing or state.captureMode or state.routeDraft or state.dragSession then
                callback({ ok = false, message = "Stop playback or editing before creating a starter scene." })
                return
            end
            local camera = ctx.camera.getCameraState()
            local x, y, z = ctx.scene.scenePlace()
            if not camera or not x then
                callback({ ok = false, message = "Aim at clear ground before creating a starter scene." })
                return
            end
            local project = DirectorTemplates.create(data.kind, { x = x, y = y, z = z }, camera)
            if not project then
                callback({ ok = false, message = "Unknown starter scene." })
                return
            end
            local valid, clean = DirectorProject.validate(project)
            if not valid then
                callback({ ok = false, message = clean })
                return
            end
            TriggerServerEvent("vanta_director_free:importProject", json.encode(clean))
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("getPresets", function(_, callback)
            local library, reason = read()
            if not library then
                callback({ ok = false, message = reason })
                return
            end
            local entries = {}
            for _, entry in ipairs(library.entries) do
                local clean = cleanRecord(entry)
                entries[#entries + 1] = {
                    id = entry.id,
                    name = tostring(entry.name or "Preset"):sub(1, 48),
                    kind = entry.kind,
                    available = clean ~= nil,
                    actorKind = clean and clean.kind == "actions" and clean.project.actors[clean.actorIndex].kind
                        or nil,
                    references = clean and DirectorPresets.references(clean) or {},
                }
            end
            callback({ ok = true, entries = entries })
        end)

        ctx.bridge.editorCallback("savePreset", function(data, callback)
            local library, reason = read()
            if not library then
                callback({ ok = false, message = reason })
                return
            end
            if #library.entries >= maximumEntries then
                callback({ ok = false, message = "The personal preset library is full." })
                return
            end
            local name = type(data.name) == "string" and data.name:gsub("[%c]", " "):match("^%s*(.-)%s*$"):sub(1, 48)
            if not name or name == "" or (data.kind ~= "actions" and data.kind ~= "camera") then
                callback({ ok = false, message = "Enter a preset name and type." })
                return
            end
            local payload = ctx.projects.projectPayload()
            local actorIndex
            for index, actor in ipairs(state.sceneActors) do
                if actor.id == tonumber(data.actorId) then
                    actorIndex = index
                end
            end
            local valid, project = DirectorProject.validate(payload)
            if not valid then
                callback({ ok = false, message = project })
                return
            end
            local record = {
                id = library.nextId,
                name = name,
                kind = data.kind,
                project = project,
                actorIndex = actorIndex,
                shotId = state.selectedShotId,
            }
            if not cleanRecord(record) then
                callback({ ok = false, message = "Select a subject with actions or a camera path first." })
                return
            end
            if data.kind == "actions" then
                for _, action in ipairs(project.actors[actorIndex].actions) do
                    if action.type == "recording" then
                        callback({ ok = false, message = "Use a project export to reuse recorded takes." })
                        return
                    end
                end
            end
            if
                data.kind == "camera"
                and not DirectorPresets.cameraShot(project, state.selectedShotId, ctx.camera.getCameraState(), 0, {})
            then
                local rig = ctx.camera.editingShot() and ctx.camera.editingShot().rig or state.cameraRig
                if rig.mode == "manual" then
                    callback({ ok = false, message = "Add a camera position first." })
                    return
                end
            end
            library.entries[#library.entries + 1] = record
            library.nextId = library.nextId + 1
            local ok, message = write(library)
            callback({ ok = ok, message = message or "Preset saved on this computer." })
        end)

        ctx.bridge.editorCallback("deletePreset", function(data, callback)
            local library, reason = read()
            if not library then
                callback({ ok = false, message = reason })
                return
            end
            for index, entry in ipairs(library.entries) do
                if entry.id == tonumber(data.id) then
                    table.remove(library.entries, index)
                    local ok, message = write(library)
                    callback({ ok = ok, message = message })
                    return
                end
            end
            callback({ ok = false, message = "Preset not found." })
        end)

        ctx.bridge.editorCallback("applyPreset", function(data, callback)
            if state.previewing or state.captureMode or state.routeDraft or state.dragSession then
                callback({ ok = false, message = "Stop playback or editing before applying a preset." })
                return
            end
            local library, reason = read()
            if not library then
                callback({ ok = false, message = reason })
                return
            end
            local record
            for _, entry in ipairs(library.entries) do
                if entry.id == tonumber(data.id) then
                    record = cleanRecord(entry)
                    break
                end
            end
            if not record then
                callback({ ok = false, message = "Preset not found or damaged." })
                return
            end
            local mappings = type(data.mappings) == "table" and data.mappings or {}
            for _, ref in ipairs(DirectorPresets.references(record)) do
                local found
                for _, actor in ipairs(state.sceneActors) do
                    if actor.id == tonumber(mappings[tostring(ref.id)]) and actor.kind == ref.kind then
                        found = actor.id
                    end
                end
                if not found then
                    callback({ ok = false, message = "Choose a scene subject for every preset reference." })
                    return
                end
                mappings[tostring(ref.id)] = found
            end
            if record.kind == "camera" then
                local shot, message = DirectorPresets.cameraShot(
                    record.project,
                    record.shotId,
                    ctx.camera.getCameraState(),
                    state.playhead,
                    mappings
                )
                if not shot then
                    callback({ ok = false, message = message })
                    return
                end
                local ok, message =
                    ctx.shots.appendShot(shot.frames, shot.rig, shot.duration, record.name, state.playhead, shot)
                callback({ ok = ok, message = message })
                return
            end
            local sourceActor = record.project.actors[record.actorIndex]
            local candidate = ctx.projects.projectPayload()
            local actorIndex
            for index, actor in ipairs(candidate.actors) do
                if actor.id == tonumber(data.actorId) and actor.kind == sourceActor.kind then
                    actorIndex = index
                end
            end
            local target = actorIndex and candidate.actors[actorIndex]
            if not target then
                callback({ ok = false, message = "Select a subject of the same type as this preset." })
                return
            end
            local actions, nextId =
                DirectorPresets.actionChain(sourceActor, target, state.playhead, mappings, state.nextActionId)
            if not actions then
                callback({ ok = false, message = nextId })
                return
            end
            target.actions = actions
            local valid, clean = DirectorProject.validate(candidate)
            if not valid then
                callback({ ok = false, message = clean })
                return
            end
            local normalized = clean.actors[actorIndex].actions
            for index, action in ipairs(normalized) do
                action.id = actions[index].id
                for _, field in ipairs({ "vehicleId", "targetId" }) do
                    if action[field] then
                        action[field] = candidate.actors[action[field]].id
                    end
                end
            end
            local fits, message = DirectorTiming.movementFits(target, normalized)
            if not fits then
                callback({ ok = false, message = message })
                return
            end
            state.sceneActors[actorIndex].actions = normalized
            state.sceneActors[actorIndex]._playing = nil
            state.nextActionId = nextId
            ctx.camera.setPlayhead(state.playhead)
            ctx.scene.sceneSend()
            callback({ ok = true, message = "Action preset added at the playhead." })
        end)
    end
end
