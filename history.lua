DirectorHistory = {}
function DirectorHistory.copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 1) ~= "_" then
            result[key] = DirectorHistory.copy(item)
        end
    end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if (type(key) ~= "string" or key:sub(1, 1) ~= "_") and not equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if (type(key) ~= "string" or key:sub(1, 1) ~= "_") and a[key] == nil then
            return false
        end
    end
    return true
end
DirectorHistory.same = equal
function DirectorHistory.new(limit)
    return { past = {}, future = {}, limit = limit or 40 }
end
function DirectorHistory.commit(history, before, after, group, time)
    if equal(before, after) then
        return false
    end
    local last = history.past[#history.past]
    -- Adjacent entries share immutable snapshots; take() returns an isolated copy.
    before = last and equal(last.after, before) and last.after or DirectorHistory.copy(before)
    after = DirectorHistory.copy(after)
    if
        group
        and last
        and last.group == group
        and time
        and last.time
        and time - last.time < 500
        and #history.future == 0
    then
        last.after = after
        last.time = time
        return true
    end
    history.past[#history.past + 1] = { before = before, after = after, group = group, time = time }
    if #history.past > history.limit then
        table.remove(history.past, 1)
    end
    history.future = {}
    return true
end
function DirectorHistory.take(history, direction)
    local source = direction == "redo" and history.future or history.past
    local destination = direction == "redo" and history.past or history.future
    local item = table.remove(source)
    if not item then
        return nil
    end
    destination[#destination + 1] = item
    return DirectorHistory.copy(direction == "redo" and item.after or item.before)
end
