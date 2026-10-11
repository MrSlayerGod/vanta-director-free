DirectorVehicleCues = {}

function DirectorVehicleCues.sample(actions, time)
    local state = { engine = false, lights = false, doors = { false, false, false, false, false, false } }
    for _, action in ipairs(actions or {}) do
        if action.time <= time then
            if action.type == 'engine' then state.engine = action.enabled
            elseif action.type == 'lights' then state.lights = action.enabled
            elseif action.type == 'door' and action.door >= 0 and action.door <= 5 then
                state.doors[action.door + 1] = action.enabled
            end
        end
    end
    return state
end
