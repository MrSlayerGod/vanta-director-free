-- Actor duplication and group membership.
DirectorClient.modules.groups = function(ctx)
    local editorState = ctx.state
    ctx.groups = {}

    return function()
        ctx.bridge.editorCallback("setActorGroup", function(data, callback)
            if type(data.ids) ~= "table" or #data.ids > Config.MaximumActors then
                callback({ ok = false, message = "Invalid selection." })
                return
            end
            local selected = {}
            for _, id in ipairs(data.ids) do
                local n = DirectorShots.number(id, 1, 1000000)
                if not n or n % 1 ~= 0 then
                    callback({ ok = false, message = "Invalid selection." })
                    return
                end
                selected[n] = true
            end
            for _, a in ipairs(editorState.sceneActors) do
                if selected[a.id] then
                    a.group = tostring(data.name or ""):gsub("[\r\n]", " "):sub(1, 32)
                end
            end
            ctx.scene.sceneSend()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("duplicateActors", function(data, callback)
            if
                editorState.previewing
                or editorState.captureMode
                or editorState.routeDraft
                or editorState.dragSession
            then
                callback({ ok = false, message = "Stop the current preview or edit." })
                return
            end
            local candidate, map = DirectorStaging.duplicate(
                editorState.sceneActors,
                data.ids,
                { x = tonumber(data.x) or 0, y = tonumber(data.y) or 0, z = tonumber(data.z) or 0 }
            )
            if not candidate then
                callback({ ok = false, message = map })
                return
            end
            local valid, message = DirectorSeats.validate(candidate, editorState.duration)
            if not valid then
                callback({ ok = false, message = message })
                return
            end
            local original = DirectorHistory.copy(editorState.sceneActors)
            local rig = DirectorHistory.copy(editorState.cameraRig)
            if ctx.scene.sceneLoad(candidate, true, true) == false then
                ctx.scene.sceneLoad(original, true, true)
                editorState.cameraRig = rig
                callback({ ok = false, message = "Could not clone the selected models." })
                return
            end
            editorState.cameraRig = rig
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)
    end
end
