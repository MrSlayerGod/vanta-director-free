DirectorTemplates = {}
function DirectorTemplates.create(kind, anchor, camera)
    if kind ~= "reveal" and kind ~= "dialogue" and kind ~= "vehicle" then
        return nil
    end
    local project = { version = 4, name = "First reveal", duration = 8, keyframes = {}, actors = {}, look = {} }
    local yaw = math.rad(camera.rz)
    local forward = { x = -math.sin(yaw), y = math.cos(yaw) }
    local function frame(time, distance)
        local result = DirectorShots.copy(camera)
        result.time = time
        result.x = result.x + forward.x * distance
        result.y = result.y + forward.y * distance
        return result
    end
    project.keyframes = { frame(0, 0), frame(8, 3) }
    if kind == "dialogue" then
        project.name = "Two-person conversation"
        for index = 1, 2 do
            local side = index == 1 and -1 or 1
            project.actors[index] = {
                id = index,
                kind = "ped",
                model = "a_m_y_business_01",
                name = "Character " .. index,
                x = anchor.x + math.cos(yaw) * side,
                y = anchor.y + math.sin(yaw) * side,
                z = anchor.z + 1,
                heading = camera.rz + side * 90,
                actions = { { id = index, type = "lookAt", time = 0, duration = 8, targetId = 3 - index } },
            }
        end
    elseif kind == "vehicle" then
        project.name = "Vehicle follow"
        project.actors[1] = {
            id = 1,
            kind = "vehicle",
            model = "sultan",
            name = "Picture vehicle",
            x = anchor.x,
            y = anchor.y,
            z = anchor.z + 0.5,
            heading = camera.rz,
            actions = {
                {
                    id = 1,
                    type = "move",
                    time = 0,
                    duration = 8,
                    x = anchor.x + forward.x * 12,
                    y = anchor.y + forward.y * 12,
                    z = anchor.z + 0.5,
                },
            },
        }
        local preset =
            DirectorCameraRig.preset("follow", { id = 1, x = anchor.x, y = anchor.y, z = anchor.z }, camera, 8, 8, 2, 3)
        project.cameraRig = preset.rig
    end
    return project
end
