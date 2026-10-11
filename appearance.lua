DirectorAppearance = {}
local A = DirectorAppearance
local function integer(v, lo, hi)
    return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end
-- Bounded, explicit persistence contract; no entity handles or runtime metadata.
function A.validate(kind, value)
    if value == nil then
        return true, nil
    end
    if type(value) ~= "table" or (kind ~= "ped" and kind ~= "vehicle") then
        return false, "Invalid appearance."
    end
    local clean = {}
    if kind == "ped" then
        for _, name in ipairs({ "components", "props" }) do
            local list = value[name] or {}
            if type(list) ~= "table" or #list > 12 then
                return false, "Invalid clothing list."
            end
            clean[name] = {}
            local seen = {}
            for _, v in ipairs(list) do
                if
                    type(v) ~= "table"
                    or not integer(v.id, 0, name == "components" and 11 or 7)
                    or seen[v.id]
                    or not integer(v.drawable, name == "props" and -1 or 0, 4095)
                    or not integer(v.texture, 0, 255)
                    or (v.palette ~= nil and not integer(v.palette, 0, 3))
                then
                    return false, "Invalid clothing variation."
                end
                seen[v.id] = true
                clean[name][#clean[name] + 1] =
                    { id = v.id, drawable = v.drawable, texture = v.texture, palette = v.palette or 0 }
            end
        end
    else
        if value.indexed ~= nil then
            if
                type(value.indexed) ~= "table"
                or #value.indexed ~= 2
                or not integer(value.indexed[1], 0, 255)
                or not integer(value.indexed[2], 0, 255)
            then
                return false, "Invalid indexed paint."
            end
            clean.indexed = { value.indexed[1], value.indexed[2] }
        end
        for _, name in ipairs({ "primary", "secondary" }) do
            if value[name] ~= nil then
                local rgb = value[name]
                if type(rgb) ~= "table" or #rgb ~= 3 then
                    return false, "Invalid paint colour."
                end
                for i = 1, 3 do
                    if not integer(rgb[i], 0, 255) then
                        return false, "Invalid paint colour."
                    end
                end
                clean[name] = { rgb[1], rgb[2], rgb[3] }
            end
        end
        for _, name in ipairs({ "livery", "modLivery" }) do
            if value[name] ~= nil then
                if not integer(value[name], -1, 1023) then
                    return false, "Invalid livery."
                end
                clean[name] = value[name]
            end
        end
        clean.extras = {}
        local seen = {}
        local extras = value.extras or {}
        if type(extras) ~= "table" or #extras > 21 then
            return false, "Invalid extras."
        end
        for _, v in ipairs(extras) do
            if type(v) ~= "table" or not integer(v.id, 0, 20) or type(v.enabled) ~= "boolean" or seen[v.id] then
                return false, "Invalid extra."
            end
            seen[v.id] = true
            clean.extras[#clean.extras + 1] = { id = v.id, enabled = v.enabled }
        end
    end
    local ok, message = A.extendedValidate(kind, value, clean)
    if not ok then
        return false, message
    end
    return true, clean
end

local componentNames = {
    "Face",
    "Mask / beard",
    "Hair",
    "Torso",
    "Legs",
    "Bag / hands",
    "Shoes",
    "Accessories",
    "Undershirt",
    "Vest",
    "Decals",
    "Top",
}
local propNames = { [0] = "Hat", [1] = "Glasses", [2] = "Ears", [6] = "Watch", [7] = "Bracelet" }
function A.read(kind, h)
    local result = { components = {}, props = {}, extras = {} }
    if kind == "ped" then
        for id = 0, 11 do
            local count = GetNumberOfPedDrawableVariations(h, id)
            if count > 0 then
                local drawable = GetPedDrawableVariation(h, id)
                result.components[#result.components + 1] = {
                    id = id,
                    name = componentNames[id + 1],
                    count = count,
                    drawable = drawable,
                    texture = GetPedTextureVariation(h, id),
                    textures = GetNumberOfPedTextureVariations(h, id, drawable),
                    palette = GetPedPaletteVariation(h, id),
                }
            end
        end
        for _, id in ipairs({ 0, 1, 2, 6, 7 }) do
            local count = GetNumberOfPedPropDrawableVariations(h, id)
            if count > 0 then
                local drawable = GetPedPropIndex(h, id)
                result.props[#result.props + 1] = {
                    id = id,
                    name = propNames[id],
                    count = count,
                    drawable = drawable,
                    texture = math.max(0, GetPedPropTextureIndex(h, id)),
                    textures = drawable >= 0 and GetNumberOfPedPropTextureVariations(h, id, drawable) or 0,
                }
            end
        end
    elseif kind == "vehicle" then
        -- Queries and property writes happen on demand, never in sceneApply.
        SetVehicleModKit(h, 0)
        local primary, secondary = GetVehicleColours(h)
        if primary ~= nil and secondary ~= nil then
            result.indexed = { primary, secondary }
        end
        if GetIsVehiclePrimaryColourCustom(h) then
            local r, g, b = GetVehicleCustomPrimaryColour(h)
            result.primary = { r, g, b }
        end
        if GetIsVehicleSecondaryColourCustom(h) then
            local r, g, b = GetVehicleCustomSecondaryColour(h)
            result.secondary = { r, g, b }
        end
        result.livery = GetVehicleLivery(h)
        result.liveries = math.max(0, GetVehicleLiveryCount(h))
        result.modLivery = GetVehicleMod(h, 48)
        result.modLiveries = GetNumVehicleMods(h, 48)
        for id = 0, 20 do
            if DoesExtraExist(h, id) then
                result.extras[#result.extras + 1] = { id = id, enabled = IsVehicleExtraTurnedOn(h, id) }
            end
        end
    end
    A.extendedRead(kind, h, result)
    return result
end

function A.supported(kind, h, value)
    if kind == "ped" then
        for _, v in ipairs(value.components or {}) do
            if
                v.drawable >= GetNumberOfPedDrawableVariations(h, v.id)
                or v.texture >= GetNumberOfPedTextureVariations(h, v.id, v.drawable)
            then
                return false, "Clothing is unavailable on this model."
            end
        end
        for _, v in ipairs(value.props or {}) do
            if
                v.drawable >= 0
                and (
                    v.drawable >= GetNumberOfPedPropDrawableVariations(h, v.id)
                    or v.texture >= GetNumberOfPedPropTextureVariations(h, v.id, v.drawable)
                )
            then
                return false, "Accessory is unavailable on this model."
            end
        end
    else
        SetVehicleModKit(h, 0)
        if value.livery ~= nil and (GetVehicleLiveryCount(h) <= 0 or value.livery >= GetVehicleLiveryCount(h)) then
            return false, "Livery is unavailable."
        end
        if
            value.modLivery ~= nil and (GetNumVehicleMods(h, 48) <= 0 or value.modLivery >= GetNumVehicleMods(h, 48))
        then
            return false, "Livery is unavailable."
        end
        for _, v in ipairs(value.extras or {}) do
            if not DoesExtraExist(h, v.id) then
                return false, "Extra is unavailable."
            end
        end
    end
    return A.extendedSupported(kind, h, value)
end

function A.apply(kind, h, value)
    if not value then
        return
    end
    if kind == "ped" then
        for _, v in ipairs(value.components or {}) do
            if
                v.drawable < GetNumberOfPedDrawableVariations(h, v.id)
                and v.texture < GetNumberOfPedTextureVariations(h, v.id, v.drawable)
            then
                SetPedComponentVariation(h, v.id, v.drawable, v.texture, v.palette or 0)
            end
        end
        for _, v in ipairs(value.props or {}) do
            if v.drawable == -1 then
                ClearPedProp(h, v.id)
            elseif
                v.drawable < GetNumberOfPedPropDrawableVariations(h, v.id)
                and v.texture < GetNumberOfPedPropTextureVariations(h, v.id, v.drawable)
            then
                SetPedPropIndex(h, v.id, v.drawable, v.texture, true)
            end
        end
    elseif kind == "vehicle" then
        SetVehicleModKit(h, 0)
        if value.indexed then
            SetVehicleColours(h, value.indexed[1], value.indexed[2])
        end
        if value.primary then
            SetVehicleCustomPrimaryColour(h, table.unpack(value.primary))
        end
        if value.secondary then
            SetVehicleCustomSecondaryColour(h, table.unpack(value.secondary))
        end
        if value.livery ~= nil and GetVehicleLiveryCount(h) > 0 and value.livery < GetVehicleLiveryCount(h) then
            SetVehicleLivery(h, value.livery)
        end
        if value.modLivery ~= nil and GetNumVehicleMods(h, 48) > 0 and value.modLivery < GetNumVehicleMods(h, 48) then
            SetVehicleMod(h, 48, value.modLivery, false)
        end
        for _, v in ipairs(value.extras or {}) do
            if DoesExtraExist(h, v.id) then
                SetVehicleExtra(h, v.id, v.enabled and 0 or 1)
            end
        end
    end
    A.extendedApply(kind, h, value)
end

function A.patch(kind, current, patch)
    local ok, change = A.validate(kind, patch)
    if not ok then
        return false, change
    end
    local valid, merged = A.validate(kind, current or {})
    if not valid then
        return false, merged
    end
    for _, name in ipairs(kind == "ped" and { "components", "props", "face" } or { "extras", "mods", "toggles" }) do
        for _, v in ipairs(change[name] or {}) do
            local found = false
            merged[name] = merged[name] or {}
            for i, old in ipairs(merged[name]) do
                if old.id == v.id then
                    merged[name][i] = v
                    found = true
                    break
                end
            end
            if not found then
                merged[name][#merged[name] + 1] = v
            end
        end
    end
    for _, name in ipairs({
        "indexed",
        "primary",
        "secondary",
        "livery",
        "modLivery",
        "wheelType",
        "tint",
        "plate",
        "hair",
        "eye",
    }) do
        if change[name] ~= nil then
            merged[name] = change[name]
        end
    end
    return true, merged
end

-- Freemode features and model-supported vehicle mods. Queried only on demand.
A.modNames = {
    [0] = "Spoiler",
    [1] = "Front bumper",
    [2] = "Rear bumper",
    [3] = "Skirts",
    [4] = "Exhaust",
    [5] = "Chassis",
    [6] = "Grille",
    [7] = "Hood",
    [8] = "Left fender",
    [9] = "Right fender",
    [10] = "Roof",
    [11] = "Engine",
    [12] = "Brakes",
    [13] = "Transmission",
    [14] = "Horn",
    [15] = "Suspension",
    [16] = "Armor",
    [23] = "Front wheels",
    [24] = "Rear wheels",
    [25] = "Plate holder",
    [26] = "Vanity plate",
    [27] = "Trim",
    [28] = "Ornaments",
    [29] = "Dashboard",
    [30] = "Dials",
    [31] = "Door speakers",
    [32] = "Seats",
    [33] = "Steering wheel",
    [34] = "Shifter",
    [35] = "Plaques",
    [36] = "Speakers",
    [37] = "Trunk",
    [38] = "Hydraulics",
    [39] = "Engine block",
    [40] = "Air filter",
    [41] = "Struts",
    [42] = "Arch cover",
    [43] = "Aerials",
    [44] = "Trim details",
    [45] = "Tank",
    [46] = "Left door",
    [47] = "Right door",
    [49] = "Lightbar",
}
A.toggleNames = { [18] = "Turbo", [20] = "Tire smoke", [22] = "Xenon lights" }
function A.freemode(h)
    if type(GetEntityModel) ~= "function" or type(GetHashKey) ~= "function" then
        return false
    end
    local hash = GetEntityModel(h)
    return hash == GetHashKey("mp_m_freemode_01") or hash == GetHashKey("mp_f_freemode_01")
end
function A.extendedValidate(kind, value, clean)
    local function list(name, max, valid)
        if value[name] == nil then
            return true
        end
        if type(value[name]) ~= "table" or #value[name] > max then
            return false
        end
        local seen = {}
        clean[name] = {}
        for _, v in ipairs(value[name]) do
            if type(v) ~= "table" or seen[v.id] or not valid(v) then
                return false
            end
            seen[v.id] = true
            local item = { id = v.id }
            if name == "mods" then
                item.index = v.index
                item.custom = v.custom == true
            elseif name == "toggles" then
                item.enabled = v.enabled
            else
                item.value = v.value
            end
            clean[name][#clean[name] + 1] = item
        end
        return true
    end
    if kind == "ped" then
        if value.eye ~= nil then
            if not integer(value.eye, 0, 31) then
                return false, "Invalid eye colour."
            end
            clean.eye = value.eye
        end
        if value.hair ~= nil then
            if
                type(value.hair) ~= "table"
                or #value.hair ~= 2
                or not integer(value.hair[1], 0, 63)
                or not integer(value.hair[2], 0, 63)
            then
                return false, "Invalid hair colour."
            end
            clean.hair = { value.hair[1], value.hair[2] }
        end
        if
            not list("face", 20, function(v)
                return integer(v.id, 0, 19)
                    and type(v.value) == "number"
                    and v.value == v.value
                    and v.value >= -1
                    and v.value <= 1
            end)
        then
            return false, "Invalid face feature."
        end
    else
        if
            not list("mods", 47, function(v)
                return integer(v.id, 0, 49)
                    and A.modNames[v.id]
                    and integer(v.index, -1, 1023)
                    and (v.custom == nil or type(v.custom) == "boolean")
            end)
        then
            return false, "Invalid vehicle mod."
        end
        if
            not list("toggles", 3, function(v)
                return integer(v.id, 0, 49) and A.toggleNames[v.id] and type(v.enabled) == "boolean"
            end)
        then
            return false, "Invalid vehicle toggle."
        end
        for _, key in ipairs({ "wheelType", "tint" }) do
            if value[key] ~= nil then
                if not integer(value[key], key == "tint" and -1 or 0, key == "tint" and 6 or 12) then
                    return false, "Invalid wheel type or tint."
                end
                clean[key] = value[key]
            end
        end
        if value.plate ~= nil then
            if
                type(value.plate) ~= "string"
                or #value.plate < 1
                or #value.plate > 8
                or not value.plate:match("^[%w ]+$")
            then
                return false, "Use 1 to 8 letters or digits on the plate."
            end
            clean.plate = value.plate:upper()
        end
    end
    return true
end
function A.extendedRead(kind, h, result)
    if kind == "ped" then
        result.freemode = A.freemode(h)
        if not result.freemode then
            return
        end
        if type(GetPedHairColor) == "function" and type(GetPedHairHighlightColor) == "function" then
            local primary, secondary = GetPedHairColor(h), GetPedHairHighlightColor(h)
            if integer(primary, 0, 63) and integer(secondary, 0, 63) then
                result.hair = { primary, secondary }
            end
        end
        if type(GetPedEyeColor) == "function" then
            local eye = GetPedEyeColor(h)
            if integer(eye, 0, 31) then
                result.eye = eye
            end
        end
        if type(GetPedFaceFeature) == "function" then
            result.face = {}
            for id = 0, 19 do
                result.face[#result.face + 1] = { id = id, value = GetPedFaceFeature(h, id) }
            end
        end
    elseif kind == "vehicle" and type(GetVehicleWheelType) == "function" then
        result.wheelType = GetVehicleWheelType(h)
        result.tint = GetVehicleWindowTint(h)
        result.plate = GetVehicleNumberPlateText(h):sub(1, 8)
        result.mods = {}
        result.toggles = {}
        for id = 0, 49 do
            if A.modNames[id] then
                local count = GetNumVehicleMods(h, id)
                if count > 0 then
                    result.mods[#result.mods + 1] = {
                        id = id,
                        name = A.modNames[id],
                        count = count,
                        index = GetVehicleMod(h, id),
                        custom = GetVehicleModVariation(h, id),
                    }
                end
            end
        end
        for _, id in ipairs({ 18, 20, 22 }) do
            result.toggles[#result.toggles + 1] = { id = id, name = A.toggleNames[id], enabled = IsToggleModOn(h, id) }
        end
    end
end
function A.extendedSupported(kind, h, value)
    if kind == "ped" then
        if (value.hair or value.eye or value.face and #value.face > 0) and not A.freemode(h) then
            return false, "Face and colour settings require a freemode ped."
        end
    else
        -- Validation never changes a vehicle. Choose the wheel family with stock
        -- wheels first; the following read exposes its actual supported variations.
        for _, v in ipairs(value.mods or {}) do
            if
                (v.id == 23 or v.id == 24)
                and v.index >= 0
                and value.wheelType ~= nil
                and value.wheelType ~= GetVehicleWheelType(h)
            then
                return false, "Choose the wheel family with stock wheels before choosing a variation."
            end
            if v.index >= GetNumVehicleMods(h, v.id) then
                return false, "This modification is unavailable on the vehicle."
            end
        end
    end
    return true
end
function A.extendedApply(kind, h, value)
    if kind == "ped" and A.freemode(h) then
        if value.hair then
            SetPedHairTint(h, value.hair[1], value.hair[2])
        end
        if value.eye then
            SetPedEyeColor(h, value.eye)
        end
        for _, v in ipairs(value.face or {}) do
            SetPedFaceFeature(h, v.id, v.value + 0.0)
        end
    elseif kind == "vehicle" then
        if value.wheelType ~= nil then
            SetVehicleWheelType(h, value.wheelType)
        end
        for _, v in ipairs(value.mods or {}) do
            if v.index < GetNumVehicleMods(h, v.id) then
                SetVehicleMod(h, v.id, v.index, v.custom)
            end
        end
        for _, v in ipairs(value.toggles or {}) do
            ToggleVehicleMod(h, v.id, v.enabled)
        end
        if value.tint ~= nil then
            SetVehicleWindowTint(h, value.tint)
        end
        if value.plate then
            SetVehicleNumberPlateText(h, value.plate)
        end
    end
end
