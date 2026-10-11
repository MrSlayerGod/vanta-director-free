dofile("config.lua")
dofile("config_validation.lua")
dofile("payload.lua")
local valid = { name = "Scene", actors = {}, duration = 600 }
assert(DirectorPayload.bounded(valid))
local cycle = {}
cycle.self = cycle
assert(not DirectorPayload.bounded(cycle))
assert(not DirectorPayload.bounded({ value = 0 / 0 }))
assert(not DirectorPayload.bounded({ value = math.huge }))
local deep = {}
local cursor = deep
for _ = 1, 30 do
    cursor.child = {}
    cursor = cursor.child
end
assert(not DirectorPayload.bounded(deep))
Config.ProjectFileLimit = 8
assert(not DirectorPayload.bounded({ value = "too many bytes" }))
assert(DirectorPayload.denseList({ 1, 2 }, 2))
assert(not DirectorPayload.denseList({ [1] = 1, [3] = 3 }, 10))
assert(not DirectorPayload.denseList({ 1, 2, extra = true }, 10))
assert(not DirectorPayload.denseList({ 1, 2, 3 }, 2))
print("Payload boundaries passed")
