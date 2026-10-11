DirectorCameraRig = {}

-- Presets use the same editable keyframe sampler as manual shots.
function DirectorCameraRig.preset(kind, target, base, seconds, distance, height, travel)
    local names =
        { orbit = "Orbit", lateral = "Travelling", approach = "Approach", pullback = "Pullback", follow = "Follow" }
    if not names[kind] then
        return nil
    end
    for _, value in ipairs({ seconds, distance, height, travel }) do
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
            return nil
        end
    end
    if
        seconds < 1
        or seconds > 60
        or distance < 1
        or distance > 200
        or math.abs(height) > 50
        or travel < 1
        or travel > 200
    then
        return nil
    end
    local dx, dy = base.x - target.x, base.y - target.y
    local angle = math.atan(dy, dx)
    local ux, uy = math.cos(angle), math.sin(angle)
    local aimHeight = target.aimHeight or 0
    local rig = {
        mode = "follow",
        targetHeight = aimHeight,
        offsetX = ux * distance,
        offsetY = uy * distance,
        offsetZ = height,
        relative = false,
        radius = distance,
        elevation = height,
        speed = 0,
        startAngle = 0,
    }
    if kind == "follow" then
        rig.anchor = base
        rig.targetId = target.id
        return { name = names[kind], rig = rig, seconds = seconds }
    end
    local count = kind == "orbit" and 12 or 1
    local frames = {}
    for index = 0, count do
        local t = index / count
        if kind == "orbit" then
            local a = angle + t * math.pi
            rig.offsetX, rig.offsetY = math.cos(a) * distance, math.sin(a) * distance
        elseif kind == "lateral" then
            local shift = (t - 0.5) * travel
            rig.offsetX, rig.offsetY = ux * distance - uy * shift, uy * distance + ux * shift
        else
            local radius = distance + (kind == "approach" and (1 - t) or t) * travel
            rig.offsetX, rig.offsetY = ux * radius, uy * radius
        end
        local state = DirectorCameraRig.sample(rig, target, base, 0)
        state.time = t * seconds
        state.name = names[kind]
        frames[#frames + 1] = state
    end
    return { name = names[kind], frames = frames, seconds = seconds }
end

function DirectorCameraRig.sample(rig, target, base, time)
    if not rig or rig.mode == "manual" or not target or not base then
        return nil
    end
    local state = { x = base.x, y = base.y, z = base.z, ry = base.ry or 0, fov = base.fov or 50 }
    local aimZ = target.z + (rig.targetHeight or 0)
    if rig.mode == "follow" then
        local x, y = rig.offsetX, rig.offsetY
        if rig.relative then
            local heading = math.rad(target.heading or 0)
            x, y = x * math.cos(heading) - y * math.sin(heading), x * math.sin(heading) + y * math.cos(heading)
        end
        state.x, state.y, state.z = target.x + x, target.y + y, aimZ + rig.offsetZ
    elseif rig.mode == "orbit" then
        local angle = math.rad(rig.startAngle + time * rig.speed)
        state.x = target.x + math.cos(angle) * rig.radius
        state.y = target.y + math.sin(angle) * rig.radius
        state.z = aimZ + rig.elevation
    end
    local dx, dy, dz = target.x - state.x, target.y - state.y, aimZ - state.z
    local horizontal = math.sqrt(dx * dx + dy * dy)
    if horizontal < 0.00001 and math.abs(dz) < 0.00001 then
        state.rx, state.rz = base.rx or 0, base.rz or 0
    else
        state.rx = math.max(-89, math.min(89, math.deg(math.atan(dz, horizontal))))
        state.rz = math.deg(math.atan(-dx, dy))
    end
    return state
end
