DirectorPayload = {}

-- Reject oversized/deep structures before normalization, including ignored fields.
-- Network deserialization has already happened; this bounds subsequent Lua work.
function DirectorPayload.bounded(value)
    local nodes, bytes, seen = 0, 0, {}
    local function visit(v, depth)
        nodes = nodes + 1
        if nodes > Config.PayloadNodeLimit or depth > 24 then
            return false
        end
        local kind = type(v)
        if kind == "string" then
            bytes = bytes + #v
            return bytes <= Config.ProjectFileLimit
        end
        if kind == "number" then
            return v == v and v ~= math.huge and v ~= -math.huge
        end
        if kind == "nil" or kind == "boolean" then
            return true
        end
        if kind ~= "table" or seen[v] then
            return false
        end
        seen[v] = true
        for k, item in pairs(v) do
            if
                (type(k) ~= "string" and type(k) ~= "number")
                or not visit(k, depth + 1)
                or not visit(item, depth + 1)
            then
                return false
            end
        end
        return true
    end
    return visit(value, 0)
end
function DirectorPayload.denseList(value, maximum)
    if type(value) ~= "table" or #value > maximum then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then
            return false
        end
        count = count + 1
        if count > maximum then
            return false
        end
    end
    return count == #value
end
