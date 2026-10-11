-- Numeric helpers shared by camera and actor movement.
DirectorClient.modules.maths = function(ctx)
    local editorState = ctx.state
    ctx.maths = {}

    function ctx.maths.clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end

    function ctx.maths.wrapAngle(angle)
        return (angle + 180.0) % 360.0 - 180.0
    end

    function ctx.maths.lerp(a, b, amount)
        return a + (b - a) * amount
    end

    function ctx.maths.finiteNumber(value, limit)
        local number = tonumber(value)
        if not number or number ~= number or math.abs(number) > limit then
            return nil
        end
        return number
    end

    return function() end
end
