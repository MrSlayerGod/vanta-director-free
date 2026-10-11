-- One asynchronous collision probe for the active drag, at most ten per second.
-- Heights are absolute: never accumulate a correction from the moving entity.
DirectorDragGround = {}
local function finite(v)
    return type(v) == "number" and v == v and math.abs(v) < 100000
end
function DirectorDragGround.begin(handle, base, support)
    local found, z = GetGroundZFor_3dCoord(base.x + 0.0, base.y + 0.0, (base.z + 1.5) + 0.0, false)
    local floor = found and finite(z) and math.abs(base.z - support - z) < 4 and z or base.z - support
    local state = {
        handle = handle,
        offset = base.z - floor,
        hint = floor,
        nextProbe = 100,
        baseZ = base.z,
        request = { x = base.x, y = base.y, z = floor },
        started = GetGameTimer(),
    }
    state.nextProbe = state.started + 100
    state.ray = StartShapeTestRay(
        base.x + 0.0,
        base.y + 0.0,
        (floor + 1.5) + 0.0,
        base.x + 0.0,
        base.y + 0.0,
        (floor - 4) + 0.0,
        1 + 16,
        handle,
        7
    )
    if state.ray == 0 then
        state.ray = nil
        state.baseZ = nil
    end
    return state
end
function DirectorDragGround.height(state, x, y, now)
    if state.ray then
        local status, hit, p, n = GetShapeTestResult(state.ray)
        if status == 2 or status == 0 or now - state.started > 250 then
            local r = state.request
            if
                status == 2
                and (hit == true or hit == 1)
                and p
                and finite(p.z)
                and n
                and finite(n.x)
                and finite(n.y)
                and finite(n.z)
                and n.z > 0.35
                and p.z >= r.z - 4
                and p.z <= r.z + 1.5
                and (x - r.x) ^ 2 + (y - r.y) ^ 2 <= 4
            then
                state.surface = { x = r.x, y = r.y, z = p.z, normal = n, at = now }
                if state.baseZ then
                    state.offset = state.baseZ - p.z
                end
            end
            state.ray = nil
            state.baseZ = nil
        end
    end
    local surface = state.surface
    local floor
    if surface and now - surface.at < 1000 and (x - surface.x) ^ 2 + (y - surface.y) ^ 2 <= 16 then
        local n = surface.normal
        floor = surface.z - (n.x * (x - surface.x) + n.y * (y - surface.y)) / n.z
        state.hint = floor
    end
    if not state.ray and now >= state.nextProbe then
        local z = state.hint
        state.request = { x = x, y = y, z = z }
        state.started = now
        state.nextProbe = now + 100
        state.ray = StartShapeTestRay(
            x + 0.0,
            y + 0.0,
            (z + 1.5) + 0.0,
            x + 0.0,
            y + 0.0,
            (z - 4) + 0.0,
            1 + 16,
            state.handle,
            7
        )
        if state.ray == 0 then
            state.ray = nil
        end
    end
    return floor and floor + state.offset or nil
end
