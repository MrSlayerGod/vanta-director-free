local events, files, emitted, values = {}, {}, {}, {}
local serial = 0
local license = "license:test"

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[copy(key)] = copy(item)
    end
    return result
end

json = {
    encode = function(value)
        serial = serial + 1
        local token = "encoded:" .. serial
        values[token] = copy(value)
        return token
    end,
    decode = function(token)
        if not values[token] then
            error("Invalid JSON")
        end
        return copy(values[token])
    end,
}
GetPlayerIdentifiers = function()
    return { license }
end
GetCurrentResourceName = function()
    return "vanta_director_free"
end
LoadResourceFile = function(_, path)
    return files[path]
end
SaveResourceFile = function(_, path, content)
    files[path] = content
    return true
end
RegisterNetEvent = function(name, handler)
    events[name] = handler
end
TriggerClientEvent = function(name, target, ...)
    assert(target == 1)
    emitted[#emitted + 1] = { name = name, args = { ... } }
end

dofile("config.lua")
dofile("config_validation.lua")
dofile("community.lua")
Config.RequireAce = false -- This suite explicitly toggles ACL for negative cases.
dofile("shots.lua")
dofile("staging.lua")
dofile("routes.lua")
dofile("appearance.lua")
dofile("attachments.lua")
dofile("recording.lua")
AddEventHandler = function() end
dofile("access.lua")

dofile("payload.lua")
dofile("collaboration_server.lua")
dofile("server.lua")

local function fire(name, ...)
    source = 1
    emitted = {}
    assert(events[name], "Missing server event: " .. name)(...)
    return emitted
end
local function named(name)
    for _, event in ipairs(emitted) do
        if event.name == "vanta_director_free:" .. name then
            return table.unpack(event.args)
        end
    end
    error("Expected event: " .. name)
end
local function validProject(id, name)
    return {
        id = id,
        name = name,
        duration = 20,
        keyframes = {},
        actors = {},
        look = { weather = "SERVER", hour = -1, minute = 0, dof = false, near = 2, far = 30, strength = 0.5 },
    }
end

local libraryPath = "data/licensetest.library.json"
local invalid = validProject("p2", "Damaged")
invalid.keyframes = { { time = 0, x = 1e20, y = 0, z = 0, rx = 0, ry = 0, rz = 0, fov = 50 } }
files[libraryPath] = json.encode({
    version = 1,
    nextId = 3,
    activeId = "p1",
    projects = { { id = "p1", data = validProject("p1", "Valid") }, { id = "p2", data = invalid } },
})
local original = files[libraryPath]
fire("vanta_director_free:requestProject")
local project, id, list = named("projectLibrary")
assert(project.name == "Valid" and list[2].available == false)
fire("vanta_director_free:manageProject", "open", "p2")
assert(named("libraryError") and files[libraryPath] == original)
fire("vanta_director_free:manageProject", "duplicate", "p2")
assert(named("libraryError") and files[libraryPath] == original)
local activeBroken = json.decode(original)
activeBroken.activeId = "p2"
files[libraryPath] = json.encode(activeBroken)
original = files[libraryPath]
fire("vanta_director_free:requestProject")
assert(named("projectLibrary").name == "Valid" and files[libraryPath] == original)
fire("vanta_director_free:manageProject", "delete", "p1")
assert(named("libraryError") and files[libraryPath] == original, "Do not delete the only valid project")
fire("vanta_director_free:manageProject", "create")
local _, created = named("projectLibrary")
assert(created == "p3")
fire("vanta_director_free:manageProject", "open", "p1")
named("projectLibrary")
fire("vanta_director_free:manageProject", "delete", "p1")
local _, remaining = named("projectLibrary")
assert(remaining == "p3", "Skip damaged entries when selecting a replacement active project")
local mixed = json.decode(files[libraryPath])
mixed.projects[1].data.actors = "malformed"
mixed.projects[1].data.cameraShots = 42
mixed.projects[1].data.name = {}
files[libraryPath] = json.encode(mixed)
fire("vanta_director_free:requestProject")
assert(
    named("projectLibrary").name == "Untitled Project",
    "Malformed secondary data must not lock the valid active project"
)
files[libraryPath .. ".bak"] = files[libraryPath]
files[libraryPath] = "partial mixed"
fire("vanta_director_free:requestProject")
assert(
    named("projectLibrary").name == "Untitled Project",
    "Recovery can preserve damaged entries alongside a valid project"
)
local older = {
    version = 2,
    generation = 2,
    nextId = 2,
    activeId = "p1",
    projects = {
        { id = "p1", data = validProject("p1", "Older") },
    },
}
local newer = copy(older)
newer.generation = 3
newer.projects[1].data.name = "Newer"
files[libraryPath] = "partial"
files[libraryPath .. ".bak"] = json.encode(older)
files[libraryPath .. ".pending"] = json.encode(newer)
fire("vanta_director_free:requestProject")
assert(named("projectLibrary").name == "Newer" and files[libraryPath .. ".damaged"] == "partial")
files[libraryPath] = "partial again"
files[libraryPath .. ".bak"] = json.encode(newer)
files[libraryPath .. ".pending"] = json.encode(older)
fire("vanta_director_free:requestProject")
assert(named("projectLibrary").name == "Newer", "Stale pending must not replace a newer backup")
local supported = files[libraryPath]
local futureLibrary = copy(newer)
futureLibrary.version = 99
files[libraryPath] = json.encode(futureLibrary)
local futureContents = files[libraryPath]
fire("vanta_director_free:requestProject")
assert(
    named("libraryError") and files[libraryPath] == futureContents,
    "Never overwrite a future library with an older recovery copy"
)
futureLibrary.version = 2
futureLibrary.projects[1].data.version = 99
files[libraryPath] = json.encode(futureLibrary)
futureContents = files[libraryPath]
fire("vanta_director_free:requestProject")
assert(
    named("libraryError") and files[libraryPath] == futureContents,
    "Never overwrite a future project using recovery"
)
files[libraryPath] = supported
local future = validProject("p1", "Future")
future.version = 99
fire("vanta_director_free:saveProject", future)
assert(named("saveResult") == false)
local anim = validProject("p1", "Finite animation")
anim.actors = {
    {
        kind = "ped",
        model = "a_m_y_business_01",
        x = 0,
        y = 0,
        z = 1,
        heading = 0,
        actions = { { type = "animation", time = 2, duration = 3, dict = "anim@test", clip = "idle" } },
    },
}
fire("vanta_director_free:saveProject", anim)
local saved, _, normalized = named("saveResult")
assert(saved and normalized.actors[1].actions[1].duration == 3)
anim.actors[1].actions[1].duration = 30
fire("vanta_director_free:saveProject", anim)
assert(named("saveResult") == false)
print(
    "Library stability: corrupt entry isolation, no invalid switch/duplication, ordered recovery, future versions and animation durations passed."
)
