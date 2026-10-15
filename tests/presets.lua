dofile("config.lua")
dofile("config_validation.lua")
dofile("shots.lua")
dofile("staging.lua")
dofile("routes.lua")
dofile("appearance.lua")
dofile("attachments.lua")
dofile("recording.lua")
dofile("payload.lua")
dofile("project_validation.lua")
dofile("presets.lua")
dofile("templates.lua")
dofile("camera_rig.lua")
json = {
    encode = function()
        return "project"
    end,
}
local camera = { x = 0, y = -10, z = 4, rx = -15, ry = 0, rz = 0, fov = 50 }
for _, kind in ipairs({ "reveal", "dialogue", "vehicle" }) do
    local template = assert(DirectorTemplates.create(kind, { x = 0, y = 0, z = 0 }, camera))
    local ok, reason = DirectorProject.validate(template)
    assert(ok, tostring(reason))
end
assert(not DirectorTemplates.create("unknown", {}, camera))
local translated = DirectorPresets.point(
    { x = 2, y = 0, z = 1 },
    { x = 0, y = 0, z = 0, heading = 0 },
    { x = 10, y = 20, z = 3, heading = 90 }
)
assert(math.abs(translated.x - 10) < 0.001 and math.abs(translated.y - 22) < 0.001 and translated.z == 4)
local project = {
    keyframes = {
        { time = 2, x = 0, y = 0, z = 2, rx = 0, ry = 0, rz = 0, fov = 50 },
        { time = 6, x = 0, y = 4, z = 2, rx = 0, ry = 0, rz = 0, fov = 50 },
    },
    duration = 8,
    actors = {},
    cameraRig = { mode = "manual" },
}
local shot = assert(
    DirectorPresets.cameraShot(project, nil, { x = 10, y = 20, z = 4, rx = 0, ry = 0, rz = 90, fov = 50 }, 3, {})
)
assert(shot.time == 3 and shot.duration == 4 and shot.frames[1].time == 3 and shot.frames[2].time == 7)
assert(math.abs(shot.frames[2].x - 6) < 0.001 and math.abs(shot.frames[2].y - 20) < 0.001)
assert(
    project.keyframes[1].x == 0 and project.keyframes[2].y == 4,
    "Applying a camera preset must not mutate its saved origin"
)
local source = {
    x = 0,
    y = 0,
    z = 0,
    heading = 0,
    actions = {
        { id = 1, type = "move", time = 3, duration = 2, x = 2, y = 0, z = 0 },
        { id = 2, type = "lookAt", time = 5, duration = 1, targetId = 7 },
    },
}
local target = { x = 10, y = 20, z = 0, heading = 90, actions = {} }
assert(not DirectorPresets.actionChain(source, target, 8, {}, 10))
local chain, nextId = DirectorPresets.actionChain(source, target, 8, { ["7"] = 20 }, 10)
assert(#chain == 2 and nextId == 12 and chain[1].time == 8 and chain[2].time == 10 and chain[2].targetId == 20)
assert(math.abs(chain[1].x - 10) < 0.001 and math.abs(chain[1].y - 22) < 0.001)
assert(source.actions[1].time == 3 and #target.actions == 0)
print(
    "Presets: three validated starter scenes, rotated camera/action placement, reference mapping and immutable sources passed."
)
