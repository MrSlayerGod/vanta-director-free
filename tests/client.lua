dofile("config.lua")
dofile("config_validation.lua")
dofile("community.lua")
dofile("locale.lua")
dofile("shots.lua")
dofile("staging.lua")
dofile("history.lua")
dofile("routes.lua")
dofile("appearance.lua")
dofile("attachments.lua")
dofile("recording.lua")
dofile("motion.lua")
dofile("scene_geometry.lua")
dofile("drag_ground.lua")
dofile("ped_cues.lua")
dofile("vehicle_cues.lua")
dofile("camera_rig.lua")
dofile("obstacles.lua")
local callbacks, events, messages, commands, entities = {}, {}, {}, {}, {}
local clock, nextHandle = 1000, 10
local hitPoint = { x = 10, y = 0, z = 0 }
local cam = { x = 0, y = -10, z = 4, rx = -15, ry = 0, rz = 0, fov = 50 }
local vec = {}
vec.__index = vec
function vec.__add(a, b)
    return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vec)
end
function vec.__mul(a, b)
    return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, vec)
end
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vec)
end
function RegisterNUICallback(name, fn)
    callbacks[name] = fn
end
function RegisterNetEvent(name, fn)
    events[name] = fn
end
function RegisterCommand(name, fn)
    commands[name] = fn
end
function CreateThread() end
function SendNUIMessage(data)
    messages[#messages + 1] = DirectorHistory.copy(data)
end
function GetGameTimer()
    return clock
end
function GetGameplayCamCoord()
    return vector3(cam.x, cam.y, cam.z)
end
function GetGameplayCamRot()
    return vector3(cam.rx, cam.ry, cam.rz)
end
function GetGameplayCamFov()
    return cam.fov
end
function GetCamCoord()
    return GetGameplayCamCoord()
end
function GetCamRot()
    return GetGameplayCamRot()
end
function GetCamFov()
    return cam.fov
end
function SetCamCoord(_, x, y, z)
    cam.x, cam.y, cam.z = x, y, z
end
function SetCamRot(_, x, y, z)
    cam.rx, cam.ry, cam.rz = x, y, z
end
function SetCamFov(_, v)
    assert(math.type(v) == "float", "Camera FOV must be passed as a float on Legacy")
    cam.fov = v
end
function CreateCam()
    return 1
end
function DoesCamExist()
    return true
end
function PlayerPedId()
    return 99
end
function GetActiveScreenResolution()
    return 1920, 1080
end
function GetHashKey(model)
    return model
end
function IsModelInCdimage()
    return true
end
function IsModelValid()
    return true
end
function HasModelLoaded()
    return true
end
function IsModelAPed(model)
    return model:sub(1, 2) == "a_" or model == "s_m_m_paramedic_01"
end
function IsModelAVehicle(model)
    return model == "sultan"
end
local function spawn(x, y, z, heading)
    nextHandle = nextHandle + 1
    entities[nextHandle] = { x = x, y = y, z = z, heading = heading }
    return nextHandle
end
function CreatePed(_, _, x, y, z, heading)
    return spawn(x, y, z, heading)
end
function CreateVehicle(_, x, y, z, heading)
    return spawn(x, y, z, heading)
end
function DoesEntityExist(handle)
    return entities[handle] ~= nil
end
function DeleteEntity(handle)
    entities[handle] = nil
end
function GetEntityCoords(handle)
    return entities[handle]
end
local boneOffset = 0.96
function GetPedBoneCoords(handle, bone)
    assert(bone == 0x3779 or bone == 0xCC4D)
    local root = entities[handle]
    return { x = root.x + (bone == 0x3779 and -0.12 or 0.12), y = root.y, z = root.z - boneOffset }
end
function GetEntityHeading(handle)
    return entities[handle].heading
end
function GetModelDimensions(model)
    return { x = -0.3, y = -0.3, z = model == "a_f_m_eastsa_01" and -1.3 or -1 }, { x = 0.3, y = 0.3, z = 0.9 }
end
local taskStarts = 0
local nativePoints = {}
function TaskFlushRoute()
    nativePoints = {}
end
function TaskExtendRoute(x, y, z)
    assert(#nativePoints < 8)
    nativePoints[#nativePoints + 1] = { x = x, y = y, z = z }
end
function TaskFollowPointRoute(handle, speed, mode)
    assert(mode == 0 and #nativePoints > 0)
    local target = nativePoints[#nativePoints]
    entities[handle].task = { x = target.x, y = target.y, z = target.z, speed = speed }
    taskStarts = taskStarts + 1
end
function SetPedMoveRateOverride(handle, rate)
    assert(rate >= 0.85 and rate <= 1.15)
    entities[handle].moveRate = rate
end
function ClearPedTasksImmediately(handle)
    entities[handle].task = nil
end
function TaskGoStraightToCoord(handle, x, y, z, speed)
    entities[handle].task = { x = x, y = y, z = z, speed = speed }
    taskStarts = taskStarts + 1
end
function SetEntityCoordsNoOffset(handle, x, y, z, keepTasks, keepIK, doWarp)
    local entity = entities[handle]
    if not keepTasks then
        entity.task = nil
    end
    entity.x, entity.y, entity.z = x, y, z
    entity.keepIK = keepIK
    entity.doWarp = doWarp
end
function SetEntityHeading(handle, heading)
    entities[handle].heading = heading
end
function GetVehicleNumberOfWheels()
    return 4
end
local terrainSlope, terrainBase = 0, 0
local groundRays, nextRay = {}, 100
function GetGroundZFor_3dCoord(x, y, z)
    return true, terrainBase + terrainSlope * x
end
function StartShapeTestRay(x, y, z, tx, ty, tz)
    if x == tx and y == ty then
        nextRay = nextRay + 1
        groundRays[nextRay] = { x = x, y = y, z = terrainBase + terrainSlope * x }
        return nextRay
    end
    return 1
end
function GetShapeTestResult(ray)
    if groundRays[ray] then
        return 2, 1, groundRays[ray], { x = -terrainSlope, y = 0, z = 1 }
    end
    return 2, 1, hitPoint
end
function SetEntityCollision(handle, enabled)
    entities[handle].collision = enabled
end
DirectorModelBrowser = { close = function() end, active = false }
json = {
    encode = function()
        return "{}"
    end,
}
-- Explicitly ignored rendering natives. This suite exercises real callback/state logic,
-- not game engine visuals, physics, native tasks or resource performance.
setmetatable(_G, {
    __index = function(_, name)
        if name:match("^[A-Z]") then
            return function() end
        end
    end,
})
dofile("preferences.lua")
dofile("tests/native-float-contracts.lua")
DirectorTestFloatContracts()
dofile("client/state.lua")
dofile("client/camera.lua")
dofile("client/lifecycle.lua")
dofile("client/collaboration.lua")
dofile("client/placement.lua")
dofile("client/history.lua")
dofile("client/environment.lua")
dofile("client/maths.lua")
dofile("client/projects.lua")
dofile("client/scene.lua")
dofile("client/playback.lua")
dofile("client/actions.lua")
dofile("client/routes.lua")
dofile("client/bridge.lua")
dofile("client/input.lua")
dofile("client/timeline.lua")
dofile("client/shots.lua")
dofile("client/capture.lua")
dofile("client/models.lua")
dofile("client/appearance.lua")
dofile("client/recording.lua")
dofile("client/groups.lua")
dofile("client/attachments.lua")
dofile("client/frame.lua")
dofile("client.lua")
local function call(name, data)
    local result
    callbacks[name](data or {}, function(value)
        result = value
    end)
    assert(result, "Callback did not respond: " .. name)
    return result
end
local function latest(action)
    for i = #messages, 1, -1 do
        if messages[i].action == action then
            return messages[i]
        end
    end
end

local focus = false
function SetNuiFocus(value)
    focus = value
end
commands[Config.Command]()
assert(not focus, "No mouse capture until the full NUI is ready")
assert(call("nuiReady").ok and focus)

assert(commands.director_free_status and commands.director_free_ground and commands.vanta_director_free_stop_take)
assert(not commands.director_status and not commands.vanta_director_stop_take and not commands.director_record_stop)
assert(
    callbacks.beginRoute and callbacks.startMotionRecording and callbacks.addAccessory and callbacks.applyCameraPreset
)
assert(callbacks.collaboration and callbacks.vehicleSeats and callbacks.setActorGroup)
assert(commands.director_free_record_stop and commands.director_free_record_cancel)
events["vanta_director_free:projectLibrary"]({
    name = "Free",
    duration = 20,
    keyframes = {},
    actors = { { id = 1, kind = "ped", model = "a_m_y_business_01", x = 0, y = 0, z = 1, heading = 0, actions = {} } },
}, "free", {})
assert(call("setProjectName", { name = "Edited" }).ok and call("undo").ok)
assert(call("setDuration", { duration = 61 }).ok)
assert(call("setDuration", { duration = 20 }).ok)
-- Invalid incomplete rig/action data is still rejected after the edition gate is gone.

assert(not call("addAction", { id = 1, type = "recording" }).ok)
assert(call("addKeyframe", { time = 0 }).ok)
assert(call("setPlayhead", { time = 3 }).ok)
assert(call("addKeyframe", { time = 3 }).ok)
assert(call("addAction", { id = 1, type = "move", duration = 3, gait = "walk" }).ok)
assert(#latest("actors").actors[1].actions == 1)
assert(call("deleteAction", { id = 1, index = 1 }).ok)
assert(call("undo").ok and call("redo").ok)
assert(call("beginRoute", { id = 1 }).ok)
assert(call("addRoutePoint", { x = 0.5, y = 0.5, aspect = 16 / 9 }).ok)
assert(call("cancelRoute").ok)
assert(call("setActorGroup", { ids = { 1 }, name = "Actors" }).ok)
assert(call("collaboration", { operation = "create" }).ok)
assert(call("close").ok and not focus)
assert(not call("addKeyframe", { time = 0 }).ok)
print(
    "Client: focus, callback registration, configurable duration, move/undo/redo, routes, grouping and session request passed."
)
