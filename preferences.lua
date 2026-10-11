-- Personal settings only. No permissions or project state belongs in this store.
DirectorPreferences = {}
local defaults = {
    layout = "azerty",
    sensitivity = 1,
    speed = 8,
    invert = false,
    scale = 1,
    text = "default",
    motion = false,
    tips = true,
    help = true,
    snap = true,
    interval = 0.1,
    move = 0.05,
    rotation = 1,
    autosave = false,
    saveInterval = 120,
    warning = true,
    language = "en",
    workspace = true,
    leftCollapsed = false,
    rightCollapsed = false,
}
-- Server defaults apply only where a personal preference is absent.
if Config and type(Config.DefaultPreferences) == "table" then
    for key, value in pairs(Config.DefaultPreferences) do
        if defaults[key] ~= nil then
            defaults[key] = value
        end
    end
end
defaults.speed = Config and Config.DefaultCameraSpeed or defaults.speed
function DirectorPreferences.defaults()
    local copy = {}
    for key, value in pairs(defaults) do
        copy[key] = value
    end
    return copy
end
local enums = {
    layout = { azerty = true, qwerty = true },
    text = { default = true, larger = true },
    language = {
        en = true,
        fr = true,
    },
}
local numbers = {
    sensitivity = { 0.2, 3 },
    speed = { 0.5, 30 },
    scale = { 1, 1.25 },
    interval = { 0.01, 1 },
    move = { 0.01, 0.5 },
    rotation = { 1, 45 },
    saveInterval = { 60, 300 },
}
function DirectorPreferences.normalize(value)
    value = type(value) == "table" and value or {}
    local out = {}
    for key, fallback in pairs(defaults) do
        local candidate = value[key]
        if enums[key] then
            out[key] = enums[key][candidate] and candidate or fallback
        elseif numbers[key] then
            out[key] = type(candidate) == "number"
                    and candidate == candidate
                    and candidate ~= math.huge
                    and candidate ~= -math.huge
                    and math.max(numbers[key][1], math.min(numbers[key][2], candidate))
                or fallback
        elseif type(fallback) == "boolean" then
            if type(candidate) == "boolean" then
                out[key] = candidate
            else
                out[key] = fallback
            end
        else
            out[key] = fallback
        end
    end
    return out
end
function DirectorPreferences.load()
    local raw = GetResourceKvpString("director_free:preferences:v1")
    if not raw or #raw > 2048 then
        return DirectorPreferences.normalize()
    end
    local ok, value = pcall(json.decode, raw)
    return DirectorPreferences.normalize(ok and value or nil)
end
function DirectorPreferences.save(value)
    local clean = DirectorPreferences.normalize(value)
    SetResourceKvp("director_free:preferences:v1", json.encode(clean))
    return clean
end
