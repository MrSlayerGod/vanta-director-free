dofile("config.lua")
dofile("shots.lua")
dofile("routes.lua")
dofile("timing.lua")
dofile("payload.lua")
dofile("motion.lua")
local actions = {
    { id = 1, type = "move", time = 1, duration = 3, speed = 1, x = 3, y = 0, z = 0 },
    { id = 2, type = "animation", time = 4, duration = 2, loop = true },
    { id = 3, type = "lookAt", time = 7, duration = 1 },
}
local changed = assert(DirectorTiming.retime(actions, 1, 1, 5, true, 20))
assert(changed[1].duration == 5 and changed[2].time == 6 and changed[3].time == 9)
assert(actions[1].duration == 3 and actions[2].time == 4, "A failed candidate must never mutate the scene")
assert(math.abs(changed[1].speed - 0.6) < 0.001)
assert(not DirectorTiming.retime(actions, 1, 19, 5, true, 20))
assert(not DirectorTiming.retime(actions, 1, 0 / 0, 5, false, 20))
local take = { { id = 1, type = "recording", time = 0, duration = 5 } }
assert(not DirectorTiming.retime(take, 1, 0, 4, false, 20))
assert(DirectorTiming.retime(take, 1, 2, nil, false, 20)[1].time == 2)
local once = { { id = 1, type = "animation", time = 0, duration = 2, loop = false } }
assert(not DirectorTiming.retime(once, 1, 0, 3, false, 20))
assert(DirectorTiming.retime(once, 1, 0, 1, false, 20))
assert(DirectorTiming.movementFits({ kind = "ped", x = 0, y = 0, z = 0 }, changed))
local tooFast = { { id = 1, type = "move", time = 0, duration = 1, gait = "walk", x = 30, y = 0, z = 0 } }
assert(not DirectorTiming.movementFits({ kind = "ped", x = 0, y = 0, z = 0 }, tooFast))
local joined = assert(DirectorTiming.chain(actions, { 2, 1, 3 }, 0, 20))
assert(joined[1].id == 2 and joined[2].time == 2 and joined[3].time == 5)
assert(not DirectorTiming.chain(actions, { 1, 1, 3 }, 0, 20))
assert(not DirectorTiming.chain(actions, { 1, 2 }, 0, 20))
local camera = { x = 0, y = 0, z = 1, rx = 0, ry = 0, rz = 0, fov = 50 }
local first = DirectorMotion.handheld(camera, 2, 8, 0.7)
local second = DirectorMotion.handheld(camera, 2, 8, 0.7)
assert(first.x == second.x and first.rz == second.rz and camera.x == 0)
assert(DirectorMotion.handheld(camera, 0, 8, 0.7).x == camera.x)
assert(DirectorMotion.handheld(camera, 8, 8, 0.7).rz == camera.rz)
assert(math.abs(first.x - camera.x) < 0.03 and math.abs(first.rz - camera.rz) < 0.2)
print("Timing: ripple, rollback, finite numbers, recording protection, one-shot bounds and gait speed passed.")
