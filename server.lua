local function getOwnerKey(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == "license:" then
            return identifier:gsub("[^%w_-]", "")
        end
    end

    return nil
end

local function projectPath(source)
    local owner = getOwnerKey(source)
    if not owner or owner == "" then
        return nil
    end

    return ("data/%s.json"):format(owner)
end

local function libraryPath(source)
    local owner = getOwnerKey(source)
    if not owner or owner == "" then
        return nil
    end
    return ("data/%s.library.json"):format(owner)
end

local validateProject = DirectorProject.validate

local function defaultProject()
    return {
        version = 4,
        name = "Untitled Project",
        duration = Config.DefaultDuration,
        keyframes = {},
        actors = {},
        look = { weather = "SERVER", hour = -1, minute = 0, dof = false, near = 2.0, far = 30.0, strength = 0.5 },
    }
end

local function writeLibrary(path, library)
    local generation = (library.generation or 0) + 1
    local stored = {
        version = 2,
        generation = generation,
        nextId = library.nextId,
        activeId = library.activeId,
        projects = {},
        recovery = library.recovery,
    }
    for _, entry in ipairs(library.projects) do
        stored.projects[#stored.projects + 1] = { id = entry.id, updatedAt = entry.updatedAt, data = entry.data }
    end
    local encoded = json.encode(stored)
    if not encoded or #encoded > Config.ProjectFileLimit * (Config.MaximumProjects + 1) + 8192 then
        return false, "Project library is too large."
    end
    local previous = LoadResourceFile(GetCurrentResourceName(), path)
    if previous then
        SaveResourceFile(GetCurrentResourceName(), path .. ".bak", previous, -1)
        if LoadResourceFile(GetCurrentResourceName(), path .. ".bak") ~= previous then
            return false, "Could not preserve the previous project library. Nothing was overwritten."
        end
    end
    SaveResourceFile(GetCurrentResourceName(), path .. ".pending", encoded, -1)
    if LoadResourceFile(GetCurrentResourceName(), path .. ".pending") ~= encoded then
        return false, "Could not verify the staged project library."
    end
    SaveResourceFile(GetCurrentResourceName(), path, encoded, -1)
    if LoadResourceFile(GetCurrentResourceName(), path) ~= encoded then
        -- Preserve the last readable library if a write is incomplete.
        if previous then
            SaveResourceFile(GetCurrentResourceName(), path, previous, -1)
        end
        SaveResourceFile(GetCurrentResourceName(), path .. ".pending", "", -1)
        return false, "The server could not save the project library."
    end
    library.version = 2
    library.generation = generation
    return true
end

local function readLibraryAttempt(source, override)
    local path = libraryPath(source)
    if not path then
        return nil, nil, "Could not identify your account."
    end
    local contents = override or LoadResourceFile(GetCurrentResourceName(), path)
    if contents then
        if #contents > Config.ProjectFileLimit * (Config.MaximumProjects + 1) + 8192 then
            return nil, nil, "The project library is too large."
        end
        local ok, library = pcall(json.decode, contents)
        if
            ok
            and type(library) == "table"
            and library.version ~= nil
            and (
                type(library.version) ~= "number"
                or library.version % 1 ~= 0
                or library.version < 1
                or library.version > 2
            )
        then
            return nil, nil, "Unsupported library version. No files were overwritten."
        end
        if
            not ok
            or type(library) ~= "table"
            or type(library.projects) ~= "table"
            or #library.projects < 1
            or #library.projects > Config.MaximumProjects
        then
            return nil, nil, "The project library is damaged."
        end
        local ids, maxId, active = {}, 0, false
        if
            library.version ~= nil
            and (
                type(library.version) ~= "number"
                or library.version % 1 ~= 0
                or library.version < 1
                or library.version > 2
            )
        then
            return nil, nil, "Unsupported library version. No files were overwritten."
        end
        if
            library.generation ~= nil
            and (
                type(library.generation) ~= "number"
                or library.generation % 1 ~= 0
                or library.generation < 0
                or library.generation > 9007199254740990
            )
        then
            return nil, nil, "The library generation is invalid."
        end
        for _, entry in ipairs(library.projects) do
            local id = type(entry) == "table" and entry.id
            local serial = type(id) == "string" and tonumber(id:match("^p(%d+)$"))
            local p = type(entry) == "table" and entry.data
            if not serial or serial < 1 or serial > 1000000000 or ids[id] or type(p) ~= "table" then
                return nil, nil, "The project library is damaged."
            end
            if
                entry.updatedAt ~= nil
                and (
                    type(entry.updatedAt) ~= "number"
                    or entry.updatedAt ~= entry.updatedAt
                    or math.abs(entry.updatedAt) > 1e12
                )
            then
                return nil, nil, "The project library is damaged."
            end
            ids[id] = true
            maxId = math.max(maxId, serial)
            active = active or id == library.activeId
        end
        if not active then
            return nil, nil, "The active project is missing."
        end
        -- Recover an old/missing counter without reusing an existing project ID.
        local nextId = tonumber(library.nextId)
        library.nextId = nextId
                and nextId == nextId
                and nextId % 1 == 0
                and nextId > maxId
                and nextId <= 1000000000
                and nextId
            or maxId + 1
        return library, path
    end

    local project = defaultProject()
    local legacy = LoadResourceFile(GetCurrentResourceName(), projectPath(source))
    if legacy and #legacy <= Config.ProjectFileLimit then
        local ok, decoded = pcall(json.decode, legacy)
        if #legacy <= Config.ProjectFileLimit and ok and type(decoded) == "table" then
            local valid, normalized = validateProject(decoded)
            if valid then
                project = normalized
            end
        end
    end
    local library = {
        version = 1,
        nextId = 2,
        activeId = "p1",
        projects = {
            { id = "p1", updatedAt = os.time(), data = project },
        },
    }
    local saved, errorMessage = writeLibrary(path, library)
    if not saved then
        return nil, nil, errorMessage
    end
    return library, path
end

local function readLibrary(source)
    local path = libraryPath(source)
    if not path then
        return nil, nil, "Could not identify your account."
    end
    local original = LoadResourceFile(GetCurrentResourceName(), path)
    local backup = LoadResourceFile(GetCurrentResourceName(), path .. ".bak")
    local pending = LoadResourceFile(GetCurrentResourceName(), path .. ".pending")
    local library, libraryFile, message
    if original or (not backup and not pending) then
        library, libraryFile, message = readLibraryAttempt(source)
    end
    if message and message:find("Unsupported library version", 1, true) then
        return nil, nil, message
    end
    if library then
        for _, entry in ipairs(library.projects) do
            local version = entry.data.version
            if version ~= nil and (type(version) ~= "number" or version % 1 ~= 0 or version < 1 or version > 4) then
                return nil, nil, "Unsupported project version in this library. No files were overwritten."
            end
        end
        local activeValid, firstValid = false, nil
        for _, entry in ipairs(library.projects) do
            local valid, reason = validateProject(entry.data)
            entry._invalid = not valid
            entry._error = not valid and tostring(reason) or nil
            if valid then
                firstValid = firstValid or entry.id
                if entry.id == library.activeId then
                    activeValid = true
                end
            end
        end
        if activeValid then
            return library, libraryFile
        end
        if firstValid then
            library.activeId = firstValid
            TriggerClientEvent(
                "vanta_director_free:collaborationStatus",
                source,
                "The active project is damaged. A valid project was opened; the damaged entry and files were preserved."
            )
            return library, libraryFile
        end
        message = "The active project is invalid."
    end
    local recovered, recoveryContents, recoveryGeneration = nil, nil, -1
    for _, contents in ipairs({ backup or "", pending or "" }) do
        if contents ~= "" then
            local candidate = readLibraryAttempt(source, contents)
            local valid, firstValid = false, nil
            if candidate then
                local supported = true
                for _, entry in ipairs(candidate.projects) do
                    local version = entry.data.version
                    if
                        version ~= nil and (type(version) ~= "number" or version % 1 ~= 0 or version < 1 or version > 4)
                    then
                        supported = false
                    end
                    local good, reason = validateProject(entry.data)
                    entry._invalid = not good
                    entry._error = not good and tostring(reason) or nil
                    if good then
                        firstValid = firstValid or entry.id
                        if entry.id == candidate.activeId then
                            valid = true
                        end
                    end
                end
                if not valid and firstValid then
                    candidate.activeId = firstValid
                    valid = true
                end
                valid = valid and supported
            end
            local generation = candidate and (candidate.generation or 0) or -1
            -- Legacy .pending has no ordering proof; do not promote it over a backup.
            if valid and (contents == backup or generation > 0) and generation > recoveryGeneration then
                recovered, recoveryContents, recoveryGeneration = candidate, contents, generation
            end
        end
    end
    if not recovered then
        return nil, nil, message or "The project library and recovery copies are unreadable. No files were overwritten."
    end
    if original then
        SaveResourceFile(GetCurrentResourceName(), path .. ".damaged", original, -1)
        if LoadResourceFile(GetCurrentResourceName(), path .. ".damaged") ~= original then
            return nil, nil, "Could not preserve the damaged library."
        end
    end
    SaveResourceFile(GetCurrentResourceName(), path, recoveryContents, -1)
    if LoadResourceFile(GetCurrentResourceName(), path) ~= recoveryContents then
        return nil, nil, "Backup recovery write failed."
    end
    TriggerClientEvent(
        "vanta_director_free:collaborationStatus",
        source,
        "Recovered the newest valid project library recovery copy. Check your recent changes."
    )
    return recovered, path
end

local function findProject(library, id)
    if type(id) ~= "string" then
        return nil
    end
    for index, entry in ipairs(library.projects) do
        if entry.id == id then
            return entry, index
        end
    end
    return nil
end

local function summaries(library)
    local list = {}
    for _, entry in ipairs(library.projects) do
        local data = entry.data or {}
        list[#list + 1] = {
            id = entry.id,
            name = type(data.name) == "string" and data.name:sub(1, 64) or "Damaged project",
            updatedAt = entry.updatedAt or 0,
            duration = type(data.duration) == "number"
                    and data.duration == data.duration
                    and data.duration >= 0
                    and data.duration <= Config.MaximumDuration
                    and data.duration
                or Config.DefaultDuration,
            shots = (type(data.keyframes) == "table" and #data.keyframes or 0)
                + (type(data.cameraShots) == "table" and #data.cameraShots or 0),
            actors = type(data.actors) == "table" and #data.actors or 0,
            available = not entry._invalid,
            error = entry._error,
        }
    end
    table.sort(list, function(a, b)
        if a.id == b.id then
            return false
        end
        if a.id == library.activeId then
            return true
        end
        if b.id == library.activeId then
            return false
        end
        if a.updatedAt ~= b.updatedAt then
            return a.updatedAt > b.updatedAt
        end
        return (tonumber(a.id:sub(2)) or 0) > (tonumber(b.id:sub(2)) or 0)
    end)
    return list
end

local function sendRecovery(source, library)
    local draft = library.recovery
    local valid = Config.RecoveryEnabled ~= false
        and type(draft) == "table"
        and type(draft.revision) == "number"
        and draft.revision % 1 == 0
        and draft.revision > 0
        and type(draft.savedAt) == "number"
        and validateProject(draft.data)
    TriggerClientEvent("vanta_director_free:recoveryState", source, valid and {
        revision = draft.revision,
        savedAt = draft.savedAt,
        name = draft.data.name,
        projectId = draft.projectId,
    } or false)
end

local function sendLibrary(source, library, message)
    local active = findProject(library, library.activeId) or library.projects[1]
    local valid, project = validateProject(active.data)
    if not valid then
        TriggerClientEvent(
            "vanta_director_free:libraryError",
            source,
            "The saved project is invalid: " .. tostring(project)
        )
        return
    end
    TriggerClientEvent("vanta_director_free:projectLibrary", source, project, active.id, summaries(library), message)
    sendRecovery(source, library)
end

local function libraryError(source, message)
    TriggerClientEvent("vanta_director_free:libraryError", source, message)
end

RegisterNetEvent("vanta_director_free:requestProject", function()
    local source = source
    local allowed, message = DirectorAccess.check(source, "load", 250)
    if not allowed then
        TriggerClientEvent("vanta_director_free:accessDenied", source, message)
        return
    end
    local library, _, errorMessage = readLibrary(source)
    if not library then
        libraryError(source, errorMessage)
        return
    end
    sendLibrary(source, library, "Project library loaded.")
end)

-- A recovery draft is a separate slot, never an overwrite of a saved project.
-- It shares the library's verified pending/backup writes and the owner's ACL.
RegisterNetEvent("vanta_director_free:saveDraft", function(project, requestId)
    local player = source
    if type(requestId) ~= "number" or requestId % 1 ~= 0 or requestId < 1 or requestId > 9007199254740991 then
        return
    end
    local function result(ok, message, revision)
        TriggerClientEvent("vanta_director_free:draftResult", player, requestId, ok, message, revision)
    end
    local allowed, message = DirectorAccess.check(player, "draft", 5000)
    if not allowed or Config.RecoveryEnabled == false then
        result(false, message or "Recovery drafts are disabled on this server.")
        return
    end
    local library, path, reason = readLibrary(player)
    if not library then
        result(false, reason)
        return
    end
    local entry = type(project) == "table" and findProject(library, project.id)
    if not entry or entry.id ~= library.activeId then
        result(false, "Open the project before saving its recovery draft.")
        return
    end
    local valid, clean = validateProject(project)
    if not valid then
        result(false, clean)
        return
    end
    local revision = (library.generation or 0) + 1
    library.recovery = { projectId = entry.id, revision = revision, savedAt = os.time(), data = clean }
    local ok, writeError = writeLibrary(path, library)
    result(ok, writeError, ok and revision or nil)
end)

RegisterNetEvent("vanta_director_free:manageRecovery", function(operation, revision)
    local player = source
    local allowed, message = DirectorAccess.check(player, "recovery", 500)
    if not allowed then
        TriggerClientEvent("vanta_director_free:libraryError", player, message)
        return
    end
    if operation ~= "restore" and operation ~= "discard" then
        return
    end
    local library, path, reason = readLibrary(player)
    if not library then
        TriggerClientEvent("vanta_director_free:libraryError", player, reason)
        return
    end
    local draft = library.recovery
    if type(draft) ~= "table" or type(revision) ~= "number" or draft.revision ~= revision then
        TriggerClientEvent(
            "vanta_director_free:libraryError",
            player,
            "The recovery draft changed. Reopen Director before trying again."
        )
        return
    end
    if operation == "restore" then
        local valid, clean = validateProject(draft.data)
        if not valid then
            TriggerClientEvent("vanta_director_free:libraryError", player, clean)
            return
        end
        if #library.projects >= Config.MaximumProjects then
            TriggerClientEvent(
                "vanta_director_free:libraryError",
                player,
                "Free a project slot before recovering this draft."
            )
            return
        end
        local id = "p" .. tostring(library.nextId)
        library.nextId = library.nextId + 1
        clean.name = (clean.name .. " recovered"):sub(1, 64)
        library.projects[#library.projects + 1] = { id = id, updatedAt = os.time(), data = clean }
        library.activeId = id
    end
    library.recovery = nil
    local ok, writeError = writeLibrary(path, library)
    if not ok then
        TriggerClientEvent("vanta_director_free:libraryError", player, writeError)
        return
    end
    if operation == "restore" then
        sendLibrary(player, library, "Recovery draft restored as a new project.")
    else
        sendRecovery(player, library)
    end
end)

RegisterNetEvent("vanta_director_free:saveProject", function(project, requestId)
    if
        requestId ~= nil
        and (type(requestId) ~= "number" or requestId % 1 ~= 0 or requestId < 1 or requestId > 9007199254740991)
    then
        return
    end
    local source = source
    local allowed, message = DirectorAccess.check(source, "save", 250)
    if not allowed then
        TriggerClientEvent("vanta_director_free:saveResult", source, false, message, nil, requestId)
        return
    end
    local library, path, errorMessage = readLibrary(source)
    if not library then
        TriggerClientEvent("vanta_director_free:saveResult", source, false, errorMessage, nil, requestId)
        return
    end
    local entry = type(project) == "table" and findProject(library, project.id)
    if not entry or entry.id ~= library.activeId then
        TriggerClientEvent(
            "vanta_director_free:saveResult",
            source,
            false,
            "Open the project before saving it.",
            nil,
            requestId
        )
        return
    end
    local valid, normalized = validateProject(project)
    if not valid then
        TriggerClientEvent("vanta_director_free:saveResult", source, false, normalized, nil, requestId)
        return
    end
    entry.data = normalized
    entry.updatedAt = os.time()
    local saved, writeError = writeLibrary(path, library)
    if not saved then
        TriggerClientEvent("vanta_director_free:saveResult", source, false, writeError, nil, requestId)
        return
    end
    TriggerClientEvent(
        "vanta_director_free:saveResult",
        source,
        true,
        "Project saved on this server.",
        normalized,
        requestId
    )
    TriggerClientEvent("vanta_director_free:projectList", source, library.activeId, summaries(library))
end)

RegisterNetEvent("vanta_director_free:manageProject", function(operation, id, name)
    local source = source
    local allowed, message = DirectorAccess.check(source, "manage", 250)
    if not allowed then
        libraryError(source, message)
        return
    end
    local library, path, errorMessage = readLibrary(source)
    if not library then
        libraryError(source, errorMessage)
        return
    end
    local entry, index = findProject(library, id)
    local previousActive = library.activeId
    if operation == "create" or operation == "duplicate" then
        if #library.projects >= Config.MaximumProjects then
            libraryError(source, "Project limit reached.")
            return
        end
        if operation == "duplicate" and not entry then
            libraryError(source, "Project not found.")
            return
        end
        if operation == "duplicate" then
            local valid, reason = validateProject(entry.data)
            if not valid then
                libraryError(source, "This project is damaged and cannot be duplicated: " .. tostring(reason))
                return
            end
        end
        local data = operation == "duplicate" and json.decode(json.encode(entry.data)) or defaultProject()
        if operation == "duplicate" then
            data.name = ("%s copy"):format(data.name):sub(1, 64)
        end
        local newId = "p" .. tostring(library.nextId or (#library.projects + 1))
        library.nextId = (library.nextId or (#library.projects + 1)) + 1
        library.projects[#library.projects + 1] = { id = newId, updatedAt = os.time(), data = data }
        library.activeId = newId
    elseif operation == "open" then
        if not entry then
            libraryError(source, "Project not found.")
            return
        end
        local valid, reason = validateProject(entry.data)
        if not valid then
            libraryError(source, "This project is damaged and was preserved: " .. tostring(reason))
            return
        end
        library.activeId = entry.id
    elseif operation == "rename" then
        if not entry or type(name) ~= "string" then
            libraryError(source, "Project not found.")
            return
        end
        local cleanName = name:gsub("[\r\n]", " "):match("^%s*(.-)%s*$"):sub(1, 64)
        if cleanName == "" then
            libraryError(source, "Enter a project name.")
            return
        end
        entry.data.name = cleanName
        entry.updatedAt = os.time()
    elseif operation == "delete" then
        if not entry then
            libraryError(source, "Project not found.")
            return
        end
        if #library.projects == 1 then
            libraryError(source, "Keep at least one project.")
            return
        end
        if library.activeId == id then
            local nextActive
            for _, candidate in ipairs(library.projects) do
                if candidate.id ~= id and not candidate._invalid then
                    nextActive = candidate.id
                    break
                end
            end
            if not nextActive then
                libraryError(source, "Keep at least one valid project. Create a new project before deleting this one.")
                return
            end
            library.activeId = nextActive
        end
        table.remove(library.projects, index)
    else
        libraryError(source, "Invalid project action.")
        return
    end

    local saved, writeError = writeLibrary(path, library)
    if not saved then
        libraryError(source, writeError)
        return
    end
    if operation == "rename" or (operation == "delete" and id ~= previousActive) then
        TriggerClientEvent(
            "vanta_director_free:projectMetadata",
            source,
            library.activeId,
            summaries(library),
            operation == "rename" and id or nil,
            operation == "rename" and entry.data.name or nil
        )
        return
    end
    sendLibrary(
        source,
        library,
        operation == "create" and "New project created."
            or operation == "duplicate" and "Project duplicated."
            or operation == "delete" and "Project deleted."
            or operation == "rename" and "Project renamed."
            or "Project opened."
    )
end)

RegisterNetEvent("vanta_director_free:importProject", function(encoded)
    local player = source
    local allowed, message = DirectorAccess.check(player, "import", 1000)
    if not allowed then
        libraryError(player, message)
        return
    end
    if type(encoded) ~= "string" or #encoded > Config.ProjectFileLimit then
        libraryError(player, "Project JSON exceeds the file limit.")
        return
    end
    local ok, raw = pcall(json.decode, encoded)
    if not ok then
        libraryError(player, "Invalid JSON.")
        return
    end
    local valid, project = validateProject(raw)
    if not valid then
        libraryError(player, project)
        return
    end
    local library, path, errorMessage = readLibrary(player)
    if not library then
        libraryError(player, errorMessage)
        return
    end
    if #library.projects >= Config.MaximumProjects then
        libraryError(player, "Project limit reached.")
        return
    end
    local id = "p" .. tostring(library.nextId)
    library.nextId = library.nextId + 1
    project.name = (project.name .. " imported"):sub(1, 64)
    library.projects[#library.projects + 1] = { id = id, updatedAt = os.time(), data = project }
    library.activeId = id
    local saved, message = writeLibrary(path, library)
    if not saved then
        libraryError(player, message)
        return
    end
    sendLibrary(player, library, "Project imported into your own library.")
end)

DirectorCollaboration.register(validateProject)
