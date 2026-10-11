-- Official Cfx float input positions; integers/handles/flags remain integers.
local positions = {
    SetPedFaceFeature = { 3 },
    AttachEntityToEntity = { 4, 5, 6, 7, 8, 9 },
    SetCamNearDof = { 2 },
    SetCamFarDof = { 2 },
    SetCamDofStrength = { 2 },
    TriggerScreenblurFadeOut = { 1 },
    TriggerScreenblurFadeIn = { 1 },
    SetCamCoord = { 2, 3, 4 },
    SetCamRot = { 2, 3, 4 },
    SetCamFov = { 2 },
    StartShapeTestRay = { 1, 2, 3, 4, 5, 6 },
    CreatePed = { 3, 4, 5, 6 },
    CreateVehicle = { 2, 3, 4, 5 },
    CreateObjectNoOffset = { 2, 3, 4 },
    GetGroundZFor_3dCoord = { 1, 2, 3 },
    TaskPlayAnim = { 4, 5, 8 },
    SetEntityAnimCurrentTime = { 4 },
    SetEntityCoordsNoOffset = { 2, 3, 4 },
    SetEntityHeading = { 2 },
    TaskGoStraightToCoord = { 2, 3, 4, 5, 7, 8 },
    TaskExtendRoute = { 1, 2, 3 },
    TaskFollowPointRoute = { 2 },
    SetPedMoveRateOverride = { 2 },
    SetPedMinMoveBlendRatio = { 2 },
    SetPedMaxMoveBlendRatio = { 2 },
    TaskLookAtCoord = { 2, 3, 4 },
    GetPedBoneCoords = { 3, 4, 5 },
    SetFocusPosAndVel = { 1, 2, 3, 4, 5, 6 },
    StartShapeTestLosProbe = { 1, 2, 3, 4, 5, 6 },
    TaskEnterVehicle = { 5 },
    TaskGoToCoordWhileAimingAtCoord = { 2, 3, 4, 5, 6, 7, 8, 10, 11 },
    TaskAimGunAtCoord = { 2, 3, 4 },
    SetEntityRotation = { 2, 3, 4 },
}
function DirectorTestFloatContracts()
    for name, indices in pairs(positions) do
        local original = _G[name]
        if type(original) == "function" then
            _G[name] = function(...)
                local args = table.pack(...)
                for _, index in ipairs(indices) do
                    assert(
                        math.type(args[index]) == "float",
                        name .. " parameter " .. index .. " must be a Lua float for Legacy"
                    )
                end
                return original(table.unpack(args, 1, args.n))
            end
        end
    end
end
