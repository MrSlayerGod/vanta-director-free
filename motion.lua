DirectorMotion = {}

function DirectorMotion.alpha(deltaSeconds, responseSeconds)
    return 1.0 - math.exp(-math.max(deltaSeconds, 0.0) / math.max(responseSeconds, 0.001))
end

-- Integrate the exponential response exactly to keep travel consistent at different FPS.
function DirectorMotion.damp(current, target, deltaSeconds, responseSeconds)
    local response = math.max(responseSeconds, 0.001)
    local alpha = DirectorMotion.alpha(deltaSeconds, response)
    return current + (target - current) * alpha, target * deltaSeconds + (current - target) * response * alpha
end

local function angleDelta(first, second)
    return (second - first + 180.0) % 360.0 - 180.0
end
local cameraFields = { "x", "y", "z", "rx", "ry", "rz", "fov" }

-- Time-aware cubic tangents keep the velocity continuous through internal keys.
-- The first and last keys ease to rest; rotation follows the shortest arc.
function DirectorMotion.sample(frames, time, ease)
    if #frames == 0 then
        return nil
    end
    if #frames == 1 or time <= frames[1].time then
        return frames[1]
    end
    if time >= frames[#frames].time then
        return frames[#frames]
    end

    local low, high = 1, #frames - 1
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if frames[middle].time <= time then
            low = middle
        else
            high = middle - 1
        end
    end
    local index = low
    do
        local first, second = frames[index], frames[index + 1]
        if time >= first.time and time < second.time then
            local span = second.time - first.time
            local t = (time - first.time) / span
            if ease == "easeInOut" then
                t = t * t * (3 - 2 * t)
            end
            local t2, t3 = t * t, t * t * t
            local h00, h10 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t
            local h01, h11 = -2 * t3 + 3 * t2, t3 - t2
            local state = { time = time }
            local before, after = frames[index - 1], frames[index + 2]
            for _, field in ipairs(cameraFields) do
                local angular = field == "rx" or field == "ry" or field == "rz"
                local a = first[field]
                local b = angular and a + angleDelta(a, second[field]) or second[field]
                local startSlope, endSlope = 0.0, 0.0
                if before then
                    local previous = angular and a - angleDelta(before[field], a) or before[field]
                    startSlope = (b - previous) / math.max(second.time - before.time, 0.001)
                end
                if after then
                    local following = angular and b + angleDelta(b, after[field]) or after[field]
                    endSlope = (following - a) / math.max(after.time - first.time, 0.001)
                end
                if ease == "linear" or ease == "easeInOut" then
                    state[field] = a + (b - a) * t
                else
                    state[field] = h00 * a + h10 * span * startSlope + h01 * b + h11 * span * endSlope
                end
            end
            return state
        end
    end
    return frames[#frames]
end

-- Stop idle camera calculations while preserving damping after input release.
function DirectorMotion.cameraActive(keys, movement, turn, mouseX, mouseY)
    return keys.w
        or keys.a
        or keys.s
        or keys.d
        or keys.q
        or keys.e
        or keys.arrowleft
        or keys.arrowright
        or keys.arrowup
        or keys.arrowdown
        or movement.x ~= 0.0
        or movement.y ~= 0.0
        or movement.z ~= 0.0
        or turn.yaw ~= 0.0
        or turn.pitch ~= 0.0
        or mouseX ~= 0.0
        or mouseY ~= 0.0
end
