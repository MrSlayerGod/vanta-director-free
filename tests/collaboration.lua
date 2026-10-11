dofile("config.lua")
dofile("config_validation.lua")
dofile("shots.lua")
local events, dropped, sent = {}, nil, {}
RegisterNetEvent = function(name, fn)
    events[name] = fn
end
AddEventHandler = function(name, fn)
    if name == "playerDropped" then
        dropped = fn
    end
end
GetPlayerName = function(player)
    return player <= 3 and "Player" .. player or nil
end
DirectorAccess = {
    allowed = function(player)
        return player == 1 or player == 2
    end,
    check = function(player)
        return player == 1 or player == 2, "denied"
    end,
}
TriggerClientEvent = function(name, target, ...)
    sent[#sent + 1] = { name = name, target = target, args = { ... } }
end
dofile("collaboration_server.lua")
DirectorCollaboration.register(function(project)
    if type(project) ~= "table" or project.duration ~= 20 then
        return false, "invalid project"
    end
    return true, project
end)
local function fire(player, action, data)
    source = player
    sent = {}
    events["vanta_director_free:sessionAction"](action, data or {})
end
local function has(suffix)
    for _, event in ipairs(sent) do
        if event.name == "vanta_director_free:" .. suffix then
            return event
        end
    end
end
fire(3, "create", { project = { duration = 20 } })
assert(not has("sessionState"))
fire(1, "create", { project = { duration = 0 } })
assert(not has("sessionState"))
fire(1, "create", { project = { duration = 20 } })
local id = assert(has("sessionState")).args[1]
fire(2, "accept", { id = id })
assert(not has("sessionState"))
fire(1, "invite", { id = id, target = 3 })
assert(not has("sessionInvite"))
fire(1, "invite", { id = id, target = 2 })
assert(has("sessionInvite"))
fire(2, "accept", { id = id })
assert(has("sessionState"))
fire(2, "publish", { id = id, project = { duration = 20 } })
assert(not has("sessionState"))
fire(2, "stop", { id = id })
assert(not has("sessionStop"))
fire(1, "play", { id = id, start = 0, finish = 10, clock = 1000 })
assert(not has("sessionPlay"))
fire(1, "ready", { id = id, revision = 1 })
fire(2, "ready", { id = id, revision = 1 })
fire(1, "play", { id = id, start = 0, finish = 10, clock = 1000 })
assert(has("sessionPlay"))
fire(1, "publish", { id = id, project = { duration = 20 } })
assert(has("sessionState"))
fire(1, "play", { id = id, start = 0, finish = 10, clock = 1000 })
assert(not has("sessionPlay"))
source = 1
sent = {}
dropped()
assert(has("sessionEnded"))
fire(2, "ready", { id = id, revision = 2 })
assert(not has("sessionState"))
print("Collaboration: ACL, invitation, host authority, readiness and disconnect cleanup passed")
