-- Timeline editing services. Native playback changes happen only after validation.
DirectorClient.modules.workflow = function(ctx)
    local state = ctx.state
    ctx.workflow = {}

    function ctx.workflow.editTiming(data)
        if state.previewing or state.captureMode or state.dragSession or state.routeDraft then
            return false, "Stop playback or editing before changing action timing."
        end
        local actor
        for _, candidate in ipairs(state.sceneActors) do
            if candidate.id == tonumber(data.actorId) then
                actor = candidate
                break
            end
        end
        if not actor then
            return false, "Actor not found."
        end
        if data.ripple ~= nil and type(data.ripple) ~= "boolean" then
            return false, "Invalid action chain option."
        end
        local actions, message = DirectorTiming.retime(
            actor.actions,
            tonumber(data.actionId),
            data.time,
            data.duration,
            data.ripple == true,
            state.duration
        )
        if not actions then
            return false, message
        end
        local movementOk, reason = DirectorTiming.movementFits(actor, actions)
        if not movementOk then
            return false, reason
        end
        local previous = actor.actions
        actor.actions = actions
        local valid, reason = DirectorProject.validate(ctx.projects.projectPayload())
        if not valid then
            actor.actions = previous
            return false, reason
        end
        actor._playing, actor._lookPlaying = nil, nil
        ctx.camera.setPlayhead(data.time)
        ctx.scene.sceneSend()
        return true
    end

    return function()
        ctx.bridge.editorCallback("chainActions", function(data, callback)
            if state.previewing or state.captureMode or state.dragSession or state.routeDraft then
                callback({ ok = false, message = "Stop playback or editing before changing action timing." })
                return
            end
            for _, actor in ipairs(state.sceneActors) do
                if actor.id == tonumber(data.actorId) then
                    local actions, message = DirectorTiming.chain(actor.actions, data.order, data.time, state.duration)
                    if not actions then
                        callback({ ok = false, message = message })
                        return
                    end
                    local fits, message = DirectorTiming.movementFits(actor, actions)
                    if not fits then
                        callback({ ok = false, message = message })
                        return
                    end
                    local previous = actor.actions
                    actor.actions = actions
                    local valid, reason = DirectorProject.validate(ctx.projects.projectPayload())
                    if not valid then
                        actor.actions = previous
                        callback({ ok = false, message = reason })
                        return
                    end
                    actor._playing, actor._lookPlaying = nil, nil
                    ctx.camera.setPlayhead(data.time)
                    ctx.scene.sceneSend()
                    callback({ ok = true })
                    return
                end
            end
            callback({ ok = false, message = "Actor not found." })
        end)

        ctx.bridge.editorCallback("editActionTiming", function(data, callback)
            local ok, message = ctx.workflow.editTiming(data)
            callback({ ok = ok, message = message })
        end)
    end
end
