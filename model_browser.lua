DirectorModelBrowser = { active = false }
local browser = DirectorModelBrowser
local entity, previewCamera, returnCamera, origin, center, sphereRadius
local viewport = { left = 0, top = 0, width = 1, height = 1 }
local previewFov = 45.0 -- Legacy native expects a Lua float, not an integer.
local generation, catalogLoading = 0, false
local catalog, catalogSource
local catalogGeneration, catalogSent = 0, false

local function clearPreview()
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    if previewCamera and DoesCamExist(previewCamera) then
        DestroyCam(previewCamera, false)
    end
    if returnCamera and DoesCamExist(returnCamera) then
        SetCamActive(returnCamera, true)
    end
    entity, previewCamera, center, sphereRadius = nil, nil, nil, nil
end

function browser.close()
    generation = generation + 1
    browser.active = false
    catalogGeneration = catalogGeneration + 1
    catalogLoading = false
    clearPreview()
    returnCamera, origin = nil, nil
    viewport = { left = 0, top = 0, width = 1, height = 1 }
end

function browser.resetPreview()
    generation = generation + 1
    clearPreview()
end

-- Build once per resource lifetime. Bound native work and NUI serialization per frame.
function browser.sendCatalog()
    if not browser.active or catalogSent or catalogLoading then
        return
    end
    catalogLoading = true
    local token = catalogGeneration
    CreateThread(function()
        local function current()
            return browser.active and token == catalogGeneration
        end
        if not current() then
            return
        end
        if not catalog then
            if not catalogSource then
                -- Keep JSON decode separate from the opening callback and native validation.
                Wait(0)
                if not current() then
                    return
                end
                local ok, value =
                    pcall(json.decode, LoadResourceFile(GetCurrentResourceName(), "catalog/index.json") or "[]")
                if not ok or type(value) ~= "table" then
                    catalogLoading = false
                    SendNUIMessage({
                        action = "status",
                        message = "Model catalog could not be read. Check the catalog folder.",
                    })
                    return
                end
                catalogSource = value
                Wait(0)
                if not current() then
                    return
                end
            end
            local seen, available, sortKeys = {}, {}, {}
            local checked, started = 0, GetGameTimer()
            local function checkpoint()
                checked = checked + 1
                if checked >= 64 or (checked % 8 == 0 and GetGameTimer() - started >= 1) then
                    Wait(0)
                    if not current() then
                        return false
                    end
                    checked, started = 0, GetGameTimer()
                end
                return current()
            end
            local function include(item)
                if
                    type(item) ~= "table"
                    or type(item.model) ~= "string"
                    or not item.model:match("^[%w_]+$")
                    or #item.model > 48
                then
                    return
                end
                local kind, name = item.kind, item.model:lower()
                if kind ~= "ped" and kind ~= "vehicle" and kind ~= "prop" then
                    return
                end
                local key = kind .. ":" .. name
                if seen[key] then
                    return
                end
                seen[key] = true
                local hash = GetHashKey(name)
                if not IsModelInCdimage(hash) or not IsModelValid(hash) then
                    return
                end
                if
                    (kind == "ped" and not IsModelAPed(hash))
                    or (kind == "vehicle" and not IsModelAVehicle(hash))
                    or (kind == "prop" and (IsModelAPed(hash) or IsModelAVehicle(hash)))
                then
                    return
                end
                local label = tostring(item.label or name)
                local entry =
                    { kind = kind, model = name, label = label, category = tostring(item.category or "Custom") }
                available[#available + 1] = entry
                sortKeys[entry] = kind .. "\0" .. label:lower()
            end
            if catalogSource.chunks then
                if type(catalogSource.chunks) ~= "table" or #catalogSource.chunks > 128 then
                    catalogLoading = false
                    catalogSource = nil
                    SendNUIMessage({ action = "status", message = "Invalid model catalog index." })
                    return
                end
                for _, path in ipairs(catalogSource.chunks) do
                    Wait(0)
                    if not current() then
                        return
                    end
                    if type(path) ~= "string" or not path:match("^catalog/chunk%-%d%d%d%.json$") then
                        catalogLoading = false
                        catalogSource = nil
                        SendNUIMessage({ action = "status", message = "Invalid model catalog chunk." })
                        return
                    end
                    local raw = LoadResourceFile(GetCurrentResourceName(), path)
                    local ok, entries = false, nil
                    if raw and #raw <= 262144 then
                        ok, entries = pcall(json.decode, raw)
                    end
                    if not ok or type(entries) ~= "table" or #entries > 512 then
                        catalogLoading = false
                        SendNUIMessage({ action = "status", message = "Model catalog chunk could not be read." })
                        return
                    end
                    Wait(0)
                    if not current() then
                        return
                    end
                    for _, item in ipairs(entries) do
                        include(item)
                        if not checkpoint() then
                            return
                        end
                    end
                end
            else
                -- Supports existing small catalog fixtures without a chunk index.
                for _, item in ipairs(catalogSource) do
                    include(item)
                    if not checkpoint() then
                        return
                    end
                end
            end
            if type(GetAllVehicleModels) == "function" then
                for _, name in ipairs(GetAllVehicleModels()) do
                    if type(name) == "string" and not seen["vehicle:" .. name:lower()] then
                        local label = GetLabelText(GetDisplayNameFromVehicleModel(GetHashKey(name)))
                        include({
                            kind = "vehicle",
                            model = name,
                            label = label ~= "NULL" and label or name,
                            category = "Server / Add-on",
                        })
                    end
                    if not checkpoint() then
                        return
                    end
                end
            end
            for _, item in ipairs(Config.CustomModels or {}) do
                include(item)
                if not checkpoint() then
                    return
                end
            end
            Wait(0)
            if not current() then
                return
            end
            table.sort(available, function(a, b)
                return sortKeys[a] < sortKeys[b]
            end)
            catalog = available
            catalogSource = nil
            Wait(0)
            if not current() then
                return
            end
        end
        -- The NUI retains this catalogue on close. Cancelled transfers restart cleanly.
        if #catalog == 0 then
            SendNUIMessage({ action = "modelCatalog", models = {}, append = false, complete = true })
        else
            for first = 1, #catalog, 256 do
                if not current() then
                    return
                end
                local chunk, last = {}, math.min(first + 255, #catalog)
                for index = first, last do
                    chunk[#chunk + 1] = catalog[index]
                end
                SendNUIMessage({ action = "modelCatalog", models = chunk, append = first > 1, complete = last
                    == #catalog })
                if last < #catalog then
                    Wait(0)
                end
            end
        end
        if current() then
            catalogLoading, catalogSent = false, true
        end
    end)
end

function browser.open(camera, state)
    browser.close()
    browser.active, returnCamera, origin = true, camera, state
    browser.sendCatalog()
end

-- NUI rectangle is normalized to the full game surface, not physical pixels.
-- Reject malformed rectangles rather than allowing an unbounded camera distance.
local function updateViewport(value)
    if type(value) ~= "table" then
        return
    end
    for _, key in ipairs({ "left", "top", "width", "height" }) do
        local n = value[key]
        if type(n) ~= "number" or n ~= n or n < 0 or n > 1 then
            return
        end
    end
    if
        value.width < 0.1
        or value.height < 0.1
        or value.left + value.width > 1.001
        or value.top + value.height > 1.001
    then
        return
    end
    viewport = { left = value.left, top = value.top, width = value.width, height = value.height }
end
function browser.view(angle, zoom, elevation, visibleViewport)
    if not browser.active or not center or not previewCamera then
        return
    end
    local function number(value, fallback)
        local n = tonumber(value)
        return n and n == n and math.abs(n) < 100000 and n or fallback
    end
    updateViewport(visibleViewport)
    angle = math.rad(number(angle, 135))
    zoom = math.max(0.6, math.min(2.5, number(zoom, 1)))
    elevation = math.rad(math.max(-15, math.min(75, number(elevation, 12))))
    local aspect = type(GetAspectRatio) == "function" and GetAspectRatio(false) or 16 / 9
    aspect = math.max(0.5, math.min(4, number(aspect, 16 / 9)))
    local tangent = math.tan(math.rad(previewFov * 0.5))
    local offsetX = (2 * (viewport.left + viewport.width * 0.5) - 1) * tangent * aspect
    local offsetY = (1 - 2 * (viewport.top + viewport.height * 0.5)) * tangent
    local opening = math.min(viewport.width * tangent * aspect, viewport.height * tangent) * 0.88
    -- Perspective sphere bound, including the off-axis center and 12% breathing room.
    local fit = sphereRadius + sphereRadius * math.sqrt(1 + offsetX * offsetX + offsetY * offsetY) / opening
    local distance = math.max(0.75, fit) * zoom
    local horizontal = distance * math.cos(elevation)
    local x, y, z =
        center.x + math.cos(angle) * horizontal,
        center.y + math.sin(angle) * horizontal,
        center.z + distance * math.sin(elevation)
    -- Translate along the camera's local right/up axes without changing orientation.
    -- The model therefore appears at the center of the unobstructed NUI viewport.
    local shiftX, shiftY = -offsetX * distance, -offsetY * distance
    x = x - math.sin(angle) * shiftX - math.cos(angle) * math.sin(elevation) * shiftY
    y = y + math.cos(angle) * shiftX - math.sin(angle) * math.sin(elevation) * shiftY
    z = z + math.cos(elevation) * shiftY
    SetCamCoord(previewCamera, x + 0.0, y + 0.0, z + 0.0)
    local dx, dy, dz = -math.cos(angle) * horizontal, -math.sin(angle) * horizontal, -distance * math.sin(elevation)
    SetCamRot(
        previewCamera,
        (math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))) + 0.0,
        0.0,
        (math.deg(math.atan(-dx, dy))) + 0.0,
        2
    )
end

function browser.preview(kind, model, visibleViewport)
    if not browser.active or not origin then
        return false, "Open the model browser first."
    end
    generation = generation + 1
    local token = generation
    clearPreview()
    if type(model) ~= "string" or not model:match("^[%w_]+$") or #model > 48 then
        return false, "Invalid model."
    end
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then
        return false, "Model unavailable on this game build."
    end
    if
        (kind == "ped" and not IsModelAPed(hash))
        or (kind == "vehicle" and not IsModelAVehicle(hash))
        or (kind == "prop" and (IsModelAPed(hash) or IsModelAVehicle(hash)))
        or (kind ~= "ped" and kind ~= "vehicle" and kind ~= "prop")
    then
        return false, "Model type does not match."
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + (Config.ModelLoadTimeoutMs or 5000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline and token == generation and browser.active do
        Wait(25)
    end
    if token ~= generation or not browser.active then
        SetModelAsNoLongerNeeded(hash)
        return false, "Preview cancelled."
    end
    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return false, "Model could not load."
    end
    local minimum, maximum = GetModelDimensions(hash)
    local size = math.sqrt((maximum.x - minimum.x) ^ 2 + (maximum.y - minimum.y) ^ 2 + (maximum.z - minimum.z) ^ 2)
    if size ~= size or size < 0.01 or size > 150 then
        SetModelAsNoLongerNeeded(hash)
        return false, "This world model is too large for the preview."
    end
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
    entity = nil
    local x, y, z = origin.x, origin.y, origin.z
    if kind == "ped" then
        entity = CreatePed(4, hash, x + 0.0, y + 0.0, z + 0.0, 0.0, false, false)
    elseif kind == "vehicle" then
        entity = CreateVehicle(hash, x + 0.0, y + 0.0, z + 0.0, 0.0, false, false)
    else
        entity = CreateObjectNoOffset(hash, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    end
    SetModelAsNoLongerNeeded(hash)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        entity = nil
        return false, "Could not preview this model."
    end
    SetEntityAsMissionEntity(entity, true, true)
    SetEntityInvincible(entity, true)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    if kind == "ped" then
        SetBlockingOfNonTemporaryEvents(entity, true)
    end
    local actual = GetEntityCoords(entity)
    center =
        { x = actual.x + (minimum.x + maximum.x) * 0.5, y = actual.y + (minimum.y + maximum.y) * 0.5, z = actual.z
            + (minimum.z + maximum.z) * 0.5 }
    sphereRadius = size * 0.5
    updateViewport(visibleViewport)
    if returnCamera and DoesCamExist(returnCamera) then
        SetCamActive(returnCamera, false)
    end
    if not previewCamera then
        previewCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
    end
    SetCamFov(previewCamera, previewFov + 0.0)
    -- Validate the engine value once, so numeric marshaling failures are visible.
    if type(GetCamFov) == "function" then
        local actualFov = GetCamFov(previewCamera)
        if type(actualFov) ~= "number" or actualFov ~= actualFov or math.abs(actualFov - previewFov) > 0.1 then
            clearPreview()
            return false, "Preview camera FOV could not be applied. Restart Director and check F8."
        end
    end
    browser.view(135, 1)
    SetCamActive(previewCamera, true)
    RenderScriptCams(true, false, 0, true, true)
    return true
end
