-- Ped and vehicle appearance editing.
DirectorClient.modules.appearance = function(ctx)
    local editorState = ctx.state
    ctx.appearance = {}

    function ctx.appearance.appearanceActor(id)
        for _, actor in ipairs(editorState.sceneActors) do
            local h = editorState.sceneEntities[actor.id]
            if
                actor.id == tonumber(id)
                and (actor.kind == "ped" or actor.kind == "vehicle")
                and h
                and DoesEntityExist(h)
            then
                return actor, h
            end
        end
    end

    return function()
        ctx.bridge.editorCallback("getActorAppearance", function(data, callback)
            local actor, h = ctx.appearance.appearanceActor(data.id)
            if not actor then
                callback({ ok = false, message = "Select a ped or vehicle." })
                return
            end
            callback({ ok = true, options = DirectorAppearance.read(actor.kind, h) })
        end)

        ctx.bridge.editorCallback("setActorAppearance", function(data, callback)
            local actor, h = ctx.appearance.appearanceActor(data.id)
            if not actor or editorState.previewing or editorState.captureMode or editorState.dragSession then
                callback({ ok = false, message = "Stop playback before styling an actor." })
                return
            end
            local ok, value = DirectorAppearance.patch(actor.kind, actor.appearance, data.appearance)
            if not ok then
                callback({ ok = false, message = value })
                return
            end
            local supported, message = DirectorAppearance.supported(actor.kind, h, value)
            if not supported then
                callback({ ok = false, message = message })
                return
            end
            DirectorAppearance.apply(actor.kind, h, value)
            actor.appearance = value
            SendNUIMessage({ action = "saveState", saved = false })
            callback({
                ok = true,
                appearance = DirectorHistory.copy(value),
                options = DirectorAppearance.read(actor.kind, h),
            })
        end)
    end
end
