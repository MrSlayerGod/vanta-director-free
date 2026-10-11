DirectorGeometry = {}

local function basis(camera)
    local yaw = math.rad(camera.rz)
    local pitch = math.rad(camera.rx)
    local forward = { x = -math.sin(yaw) * math.cos(pitch), y = math.cos(yaw) * math.cos(pitch), z = math.sin(pitch) }
    local right = { x = math.cos(yaw), y = math.sin(yaw), z = 0.0 }
    local up = { x = math.sin(yaw) * math.sin(pitch), y = -math.cos(yaw) * math.sin(pitch), z = math.cos(pitch) }
    return forward, right, up
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

function DirectorGeometry.project(camera, aspect, point)
    local forward, right, up = basis(camera)
    local relative = { x = point.x - camera.x, y = point.y - camera.y, z = point.z - camera.z }
    local depth = dot(relative, forward)
    if depth <= 0.1 then return nil end
    local spread = math.tan(math.rad(camera.fov) * 0.5) * depth
    if spread <= 0.0 then return nil end
    return 0.5 + dot(relative, right) / (2.0 * spread * aspect),
        0.5 - dot(relative, up) / (2.0 * spread), depth
end

local function ray(camera, aspect, screenX, screenY)
    local forward, right, up = basis(camera)
    local spread = math.tan(math.rad(camera.fov) * 0.5)
    local horizontal = (screenX * 2.0 - 1.0) * spread * aspect
    local vertical = (1.0 - screenY * 2.0) * spread
    return {
        x = forward.x + right.x * horizontal + up.x * vertical,
        y = forward.y + right.y * horizontal + up.y * vertical,
        z = forward.z + right.z * horizontal + up.z * vertical
    }
end

local function onPlane(camera, direction, z)
    if math.abs(direction.z) < 0.02 then return nil end
    local distance = (z - camera.z) / direction.z
    if distance < 0.1 or distance > 1000.0 then return nil end
    return { x = camera.x + direction.x * distance, y = camera.y + direction.y * distance }
end

function DirectorGeometry.dragDelta(camera, aspect, startX, startY, endX, endY, baseZ, depth, heightOnly)
    local spread = math.tan(math.rad(camera.fov) * 0.5)
    if heightOnly then
        return { x = 0.0, y = 0.0, z = (startY - endY) * 2.0 * spread * depth }
    end

    local startHit = onPlane(camera, ray(camera, aspect, startX, startY), baseZ)
    local endHit = onPlane(camera, ray(camera, aspect, endX, endY), baseZ)
    if startHit and endHit then
        return { x = endHit.x - startHit.x, y = endHit.y - startHit.y, z = 0.0 }
    end

    local forward, right = basis(camera)
    local horizontal = (endX - startX) * 2.0 * spread * depth * aspect
    local distance = (startY - endY) * 2.0 * spread * depth
    local length = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    if length < 0.01 then length = 1.0 end
    return {
        x = right.x * horizontal + forward.x / length * distance,
        y = right.y * horizontal + forward.y / length * distance,
        z = 0.0
    }
end

DirectorGeometry.ray = ray
