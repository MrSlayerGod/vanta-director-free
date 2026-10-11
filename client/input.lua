-- Keyboard and mouse input updates.
DirectorClient.modules.input = function(ctx)
    local editorState = ctx.state
    ctx.input = {}

    return function()
        ctx.bridge.editorCallback("setKeys", function(data, callback)
            local sequence = ctx.maths.finiteNumber(data.sequence, 9007199254740991)
            if not sequence or sequence % 1 ~= 0 then
                callback({ ok = false, message = "Invalid input sequence." })
                return
            end
            if editorState.directorOpen and sequence and sequence > editorState.lastInputSequence then
                editorState.lastInputSequence = sequence
                editorState.lastInputAt = GetGameTimer()
                editorState.pressedKeys = {}
                if type(data.keys) == "table" then
                    for _, key in ipairs({
                        "w",
                        "a",
                        "s",
                        "d",
                        "q",
                        "e",
                        "arrowleft",
                        "arrowright",
                        "arrowup",
                        "arrowdown",
                    }) do
                        editorState.pressedKeys[key] = data.keys[key] == true
                    end
                end
            end
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("mouseLook", function(data, callback)
            if editorState.directorOpen and not editorState.previewing then
                local x, y = ctx.maths.finiteNumber(data.x, 10000), ctx.maths.finiteNumber(data.y, 10000)
                if not x or not y then
                    callback({ ok = false, message = "Invalid mouse movement." })
                    return
                end
                editorState.mouseLookX = ctx.maths.clamp(editorState.mouseLookX + x, -120.0, 120.0)
                editorState.mouseLookY = ctx.maths.clamp(editorState.mouseLookY + y, -120.0, 120.0)
            end
            callback({ ok = true })
        end)
    end
end
