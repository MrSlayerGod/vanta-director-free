-- Pure timeline edits: build a candidate first, then validate it before committing.
DirectorTiming = {}
local T = DirectorTiming

function T.retime(actions, actionId, time, duration, ripple, limit)
    local result = DirectorShots.copy(actions)
    local selected
    for _, action in ipairs(result) do
        if action.id == actionId then
            selected = action
            break
        end
    end
    if not selected then
        return nil, "Action not found."
    end
    local at = DirectorShots.number(time, 0, limit)
    local length = duration == nil and selected.duration or DirectorShots.number(duration, 0.1, limit)
    if not at or (duration ~= nil and not length) then
        return nil, "Choose valid action timing."
    end
    if duration ~= nil and not selected.duration then
        return nil, "This cue has no duration."
    end
    if selected.type == "recording" and length ~= selected.duration then
        return nil, "Use Trim recording to shorten a recorded take."
    end
    if
        selected.type == "animation"
        and selected.loop == false
        and length
        and selected.duration
        and length > selected.duration
    then
        return nil, "A one-shot animation cannot be extended beyond its captured duration."
    end
    if (selected.type == "enterVehicle" or selected.type == "exitVehicle") and length > 30 then
        return nil, "Vehicle interactions must last at most 30 seconds."
    end
    local oldEnd = selected.time + (selected.duration or 0)
    local newEnd = at + (length or 0)
    local shift = newEnd - oldEnd
    if ripple then
        for _, action in ipairs(result) do
            if action.id ~= actionId and action.time >= oldEnd - 0.001 then
                action.time = action.time + shift
            end
        end
    end
    if selected.speed and length and selected.duration then
        selected.speed = selected.speed * selected.duration / length
    end
    selected.time, selected.duration = at, length
    for _, action in ipairs(result) do
        if action.time < 0 or action.time + (action.duration or 0) > limit + 0.001 then
            return nil, "Extend the project or shorten the action chain first."
        end
    end
    table.sort(result, function(a, b)
        if a.time == b.time then
            return a.id < b.id
        end
        return a.time < b.time
    end)
    return result
end

function T.movementFits(actor, actions)
    local origin = { x = actor.x, y = actor.y, z = actor.z }
    for _, action in ipairs(actions) do
        if action.type == "move" then
            local points = action.points or { { x = action.x, y = action.y, z = action.z } }
            local route = DirectorRoutes.compile(origin, points)
            if actor.kind == "ped" then
                local maximum = ({ walk = 2, run = 6, sprint = 8, auto = 8 })[action.gait or "auto"] or 8
                if route.length / action.duration > maximum + 0.01 then
                    return false, "This movement is too fast for the chosen gait. Increase its duration."
                end
            end
            origin = { x = action.x, y = action.y, z = action.z }
        elseif action.type == "exitVehicle" then
            origin = { x = action.x, y = action.y, z = action.z }
        end
    end
    return true
end

function T.chain(actions, order, start, limit)
    if not DirectorPayload.denseList(order, Config.MaximumActionsPerActor) or #order ~= #actions then
        return nil, "The action list changed. Select the steps again."
    end
    local byId, seen, result = {}, {}, {}
    for _, action in ipairs(actions) do
        byId[action.id] = action
    end
    local cursor = DirectorShots.number(start, 0, limit)
    if not cursor then
        return nil, "Choose valid action timing."
    end
    for _, id in ipairs(order) do
        local original = byId[id]
        if not original or seen[id] then
            return nil, "The action list changed. Select the steps again."
        end
        if original.type == "recording" then
            return nil, "Use Trim recording to shorten a recorded take."
        end
        if original.type == "animation" and not original.duration then
            return nil, "Give every animation a clip duration before joining steps."
        end
        local action = DirectorShots.copy(original)
        action.time = cursor
        cursor = cursor + (action.duration or 0)
        if cursor > limit + 0.001 then
            return nil, "Extend the project or shorten the action chain first."
        end
        seen[id] = true
        result[#result + 1] = action
    end
    return result
end
