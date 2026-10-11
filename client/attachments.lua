-- Vehicle seats and prop attachment editing.
DirectorClient.modules.attachments = function(ctx)
    local editorState = ctx.state
    ctx.attachments = {}

    return function()
        ctx.bridge.editorCallback("vehicleSeats", function(data, callback)
            for _, a in ipairs(editorState.sceneActors) do
                if a.kind == "vehicle" and a.id == tonumber(data.id) then
                    callback({ ok = true, count = GetVehicleModelNumberOfSeats(GetHashKey(a.model)) })
                    return
                end
            end
            callback({ ok = false, message = "Place a vehicle first." })
        end)

        ctx.bridge.editorCallback("addAccessory", function(data, callback)
            if
                not editorState.directorOpen
                or editorState.previewing
                or editorState.captureMode
                or editorState.dragSession
                or editorState.routeDraft
            then
                callback({ ok = false, message = "Stop playback and finish editing before adding an accessory." })
                return
            end
            local parent = DirectorAttachments.target(editorState.sceneActors, tonumber(data.parentId))
            local ok, v = DirectorAttachments.validate("prop", data.attachment)
            if not parent or not ok or v.parentId ~= parent.id or not editorState.sceneEntities[parent.id] then
                callback({ ok = false, message = "Choose a staged ped and valid attachment." })
                return
            end
            if GetPedBoneIndex(editorState.sceneEntities[parent.id], DirectorAttachments.bones[v.bone]) < 0 then
                callback({ ok = false, message = "Attachment point is unavailable on this ped." })
                return
            end
            if #editorState.sceneActors >= Config.MaximumActors then
                callback({ ok = false, message = "Actor limit reached." })
                return
            end
            local a = {
                id = editorState.nextActorId,
                kind = "prop",
                model = data.model,
                x = parent.x,
                y = parent.y,
                z = parent.z,
                heading = parent.heading,
                attachment = v,
                actions = {
                    { id = editorState.nextActionId, type = "visibility", time = editorState.playhead, visible = true },
                },
            }
            a.attachment.visible = false
            local success, message = ctx.scene.sceneSpawn(a)
            if not success then
                callback({ ok = false, message = message })
                return
            end
            -- Loading a model may yield: reject a deleted/replaced parent.
            if DirectorAttachments.target(editorState.sceneActors, parent.id) ~= parent then
                local h = editorState.sceneEntities[a.id]
                if h and DoesEntityExist(h) then
                    DeleteEntity(h)
                end
                editorState.sceneEntities[a.id] = nil
                callback({ ok = false, message = "The parent ped changed while loading." })
                return
            end
            editorState.sceneActors[#editorState.sceneActors + 1] = a
            editorState.nextActorId = editorState.nextActorId + 1
            editorState.nextActionId = editorState.nextActionId + 1
            if editorState.selectedActorId and editorState.sceneEntities[editorState.selectedActorId] then
                ctx.placement.selectionOutline(editorState.sceneEntities[editorState.selectedActorId], false)
            end
            editorState.selectedActorId = a.id
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.scene.sceneSend()
            callback({ ok = true, id = a.id })
        end)

        ctx.bridge.editorCallback("setAttachment", function(data, callback)
            if editorState.previewing or editorState.captureMode or editorState.dragSession then
                callback({ ok = false, message = "Stop playback before adjusting an accessory." })
                return
            end
            for _, a in ipairs(editorState.sceneActors) do
                if a.id == tonumber(data.id) and a.attachment then
                    local ok, v = DirectorAttachments.validate(a.kind, data.attachment)
                    if not ok or not DirectorAttachments.target(editorState.sceneActors, v.parentId) then
                        callback({ ok = false, message = "Invalid attachment or missing ped." })
                        return
                    end
                    local h = editorState.sceneEntities[a.id]
                    local parent = editorState.sceneEntities[v.parentId]
                    if
                        not h
                        or not parent
                        or not DoesEntityExist(h)
                        or not DoesEntityExist(parent)
                        or GetPedBoneIndex(parent, DirectorAttachments.bones[v.bone]) < 0
                    then
                        callback({ ok = false, message = "Attachment point is unavailable on this ped." })
                        return
                    end
                    a.attachment = v
                    DirectorAttachments.apply(a, h, parent)
                    SendNUIMessage({ action = "saveState", saved = false })
                    callback({ ok = true, attachment = DirectorHistory.copy(v) })
                    return
                end
            end
            callback({ ok = false, message = "Select an attached accessory." })
        end)
    end
end
