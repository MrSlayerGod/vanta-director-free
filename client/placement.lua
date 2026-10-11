-- Actor selection and mouse placement.
DirectorClient.modules.placement = function(ctx)
    local editorState = ctx.state
    ctx.placement = {}

    function ctx.placement.selectionOutline(handle, enabled)
        enabled = enabled
            and Config.SelectionOutline ~= false
            and not editorState.captureMode
            and editorState.directorOpen
        if enabled then
            for _, actor in ipairs(editorState.sceneActors) do
                -- Skinned actors keep the existing selected pin/inspector highlight.
                -- The SDK outline renderer is avoided on peds; only one rigid model
                -- can own a silhouette, outside capture and while visible.
                if
                    editorState.sceneEntities[actor.id] == handle and (actor._visible == false or actor.kind == "ped")
                then
                    enabled = false
                    break
                end
            end
        end
        if not enabled then
            if editorState.outlinedHandle == handle then
                if DoesEntityExist(handle) then
                    SetEntityDrawOutline(handle, false)
                end
                editorState.outlinedHandle = nil
            end
            return
        end
        if editorState.outlinedHandle == handle then
            return
        end
        if editorState.outlinedHandle and DoesEntityExist(editorState.outlinedHandle) then
            SetEntityDrawOutline(editorState.outlinedHandle, false)
        end
        SetEntityDrawOutlineShader(1) -- Firm silhouette; no Gaussian glow.
        SetEntityDrawOutlineColor(table.unpack(Config.SelectionColor or { 74, 195, 225, 185 }))
        SetEntityDrawOutline(handle, true)
        editorState.outlinedHandle = handle
    end

    function ctx.placement.placementRoot(actor, x, y, z, surface)
        local handle = editorState.sceneEntities[actor.id]
        local minimum = GetModelDimensions(GetHashKey(actor.model))
        local support = actor.kind == "ped" and DirectorPedCues.contactOffset(actor, 1.0) or -minimum.z
        if surface then
            SetEntityCoordsNoOffset(handle, x + 0.0, y + 0.0, (z + support) + 0.0, false, false, true)
            if actor.kind == "vehicle" then
                SetVehicleOnGroundProperly(handle)
            elseif actor.kind == "prop" then
                PlaceObjectOnGroundProperly(handle)
            end
        end
        local root = GetEntityCoords(handle)
        actor.x, actor.y, actor.z = root.x, root.y, root.z
        actor._lastApplied = nil
    end

    function ctx.placement.sceneSetTransform(id, data)
        local x = ctx.maths.finiteNumber(data.x, 100000.0)
        local y = ctx.maths.finiteNumber(data.y, 100000.0)
        local z = ctx.maths.finiteNumber(data.z, 100000.0)
        local heading = ctx.maths.finiteNumber(data.heading, 360000.0)
        local surface
        if data.aim == true then
            x, y, z, surface = ctx.scene.scenePlace()
        end
        if not x or not y or not z or not heading then
            return false, "Invalid coordinates."
        end
        for _, actor in ipairs(editorState.sceneActors) do
            if actor.id == id then
                if actor.actions[1] and actor.actions[1].type == "recording" then
                    return false, "Recorded positions are fixed. Move the clip in the timeline instead."
                end
                if actor.attachment then
                    return false, "Use the accessory position controls."
                end
                actor.x, actor.y, actor.z = x, y, z
                if data.aim == true then
                    SetEntityCoordsNoOffset(
                        editorState.sceneEntities[id],
                        x + 0.0,
                        y + 0.0,
                        z + 0.0,
                        false,
                        false,
                        true
                    )
                    ctx.placement.placementRoot(actor, x, y, z, surface)
                end
                actor.heading = heading % 360.0
                ctx.playback.sceneApply(editorState.playhead)
                ctx.scene.sceneSend()
                return true
            end
        end
        return false, "Actor not found."
    end

    function ctx.placement.sceneDragBegin(data)
        if not editorState.directorOpen or not editorState.camera or not DoesCamExist(editorState.camera) then
            return nil
        end
        local screenX = ctx.maths.finiteNumber(data.x, 1.0)
        local screenY = ctx.maths.finiteNumber(data.y, 1.0)
        local aspect = ctx.maths.finiteNumber(data.aspect, 4.0)
        if not screenX or not screenY or not aspect or screenX < 0 or screenY < 0 or aspect < 0.5 then
            return nil
        end
        local cameraState = ctx.camera.getCameraState()
        local chosen, bestDistance = nil, math.huge
        local requestedId = tonumber(data.id)
        if requestedId then
            for _, actor in ipairs(editorState.sceneActors) do
                if
                    actor.id == requestedId
                    and editorState.sceneEntities[actor.id]
                    and DoesEntityExist(editorState.sceneEntities[actor.id])
                then
                    chosen = actor
                    break
                end
            end
        end
        if not chosen then
            for _, actor in ipairs(editorState.sceneActors) do
                local handle = editorState.sceneEntities[actor.id]
                if handle and DoesEntityExist(handle) and actor._visible ~= false then
                    local position = GetEntityCoords(handle)
                    for _, height in ipairs({ 0.35, 0.9, 1.45 }) do
                        local px, py = DirectorGeometry.project(cameraState, aspect, {
                            x = position.x,
                            y = position.y,
                            z = position.z + height,
                        })
                        if px and py then
                            local dx, dy = (px - screenX) * aspect, py - screenY
                            local distance = dx * dx + dy * dy
                            local radius = actor.kind == "vehicle" and 0.12 or actor.kind == "prop" and 0.08 or 0.065
                            if distance < radius * radius and distance < bestDistance then
                                chosen, bestDistance = actor, distance
                            end
                        end
                    end
                end
            end
        end
        if not chosen or chosen.attachment or (chosen.actions[1] and chosen.actions[1].type == "recording") then
            return nil
        end

        if
            editorState.selectedActorId
            and editorState.sceneEntities[editorState.selectedActorId]
            and DoesEntityExist(editorState.sceneEntities[editorState.selectedActorId])
        then
            ctx.placement.selectionOutline(editorState.sceneEntities[editorState.selectedActorId], false)
        end
        editorState.selectedActorId = chosen.id
        ctx.placement.selectionOutline(editorState.sceneEntities[chosen.id], true)
        editorState.previewing = false
        editorState.pressedKeys = {}
        ctx.camera.resetMotion()
        local current = GetEntityCoords(editorState.sceneEntities[chosen.id])
        local _, _, depth = DirectorGeometry.project(cameraState, aspect, {
            x = current.x,
            y = current.y,
            z = current.z + 0.9,
        })
        local targets = {}
        for _, action in ipairs(chosen.actions) do
            if action.type == "move" then
                targets[action.id] =
                    { x = action.x, y = action.y, z = action.z, points = DirectorHistory.copy(action.points) }
            end
        end
        editorState.dragSession = {
            actor = chosen,
            camera = cameraState,
            aspect = aspect,
            startX = screenX,
            startY = screenY,
            depth = depth or 5.0,
            base = { x = chosen.x, y = chosen.y, z = chosen.z },
            heading = chosen.heading,
            mode = data.mode == "rotate" and "rotate" or "move",
            target = { x = chosen.x, y = chosen.y, z = chosen.z, heading = chosen.heading },
            targets = targets,
        }
        local minimum = GetModelDimensions(GetHashKey(chosen.model))
        local support = chosen.kind == "ped"
                and DirectorPedCues.contactOffset(chosen, ctx.playback.routeRootOffset(chosen))
            or -minimum.z
        editorState.dragSession.ground =
            DirectorDragGround.begin(editorState.sceneEntities[chosen.id], editorState.dragSession.base, support)
        editorState.lastDragSequence = -1
        return chosen.id
    end

    function ctx.placement.sceneDragMove(data)
        if not editorState.dragSession or not editorState.directorOpen then
            return false
        end
        local screenX = ctx.maths.finiteNumber(data.x, 1.0)
        local screenY = ctx.maths.finiteNumber(data.y, 1.0)
        local sequence = tonumber(data.sequence)
        if
            not screenX
            or not screenY
            or screenX < 0
            or screenY < 0
            or not sequence
            or sequence <= editorState.lastDragSequence
        then
            return false
        end
        editorState.lastDragSequence = sequence
        local session = editorState.dragSession
        if session.mode == "rotate" then
            session.target.heading = (session.heading + (screenX - session.startX) * 360.0) % 360.0
        else
            local offset = DirectorGeometry.dragDelta(
                session.camera,
                session.aspect,
                session.startX,
                session.startY,
                screenX,
                screenY,
                session.base.z,
                session.depth,
                data.heightOnly == true
            )
            if math.abs(offset.x) > 1000 or math.abs(offset.y) > 1000 or math.abs(offset.z) > 1000 then
                return false
            end
            session.target.x = session.base.x + offset.x
            session.target.y = session.base.y + offset.y
            session.target.z = session.base.z + offset.z
            session.heightOnly = data.heightOnly == true
        end
        return true
    end

    function ctx.placement.sceneDragUpdate(deltaSeconds)
        local session = editorState.dragSession
        if not session then
            return
        end
        local actor = session.actor
        local response = math.max(0.005, Config.ActorDragResponse)
        local amount = 1.0 - math.exp(-deltaSeconds / response)
        actor.x = ctx.maths.lerp(actor.x, session.target.x, amount)
        actor.y = ctx.maths.lerp(actor.y, session.target.y, amount)
        local targetZ = session.target.z
        local groundedZ
        if session.mode == "move" and not session.heightOnly then
            groundedZ = DirectorDragGround.height(session.ground, actor.x, actor.y, GetGameTimer())
        end
        -- XY is already eased. Easing Z a second time makes wheels lag below ramps.
        actor.z = groundedZ or ctx.maths.lerp(actor.z, targetZ, amount)
        actor.heading = (actor.heading + ctx.maths.wrapAngle(session.target.heading - actor.heading) * amount) % 360.0
        local offsetX, offsetY, offsetZ = actor.x - session.base.x, actor.y - session.base.y, actor.z - session.base.z
        local previous = session.appliedOffset
        if
            not previous
            or math.abs(previous.x - offsetX) + math.abs(previous.y - offsetY) + math.abs(previous.z - offsetZ)
                > 0.000001
        then
            session.appliedOffset = previous or {}
            session.appliedOffset.x, session.appliedOffset.y, session.appliedOffset.z = offsetX, offsetY, offsetZ
            for _, action in ipairs(actor.actions) do
                local original = session.targets[action.id]
                if original then
                    action.x, action.y, action.z = original.x + offsetX, original.y + offsetY, original.z + offsetZ
                    if original.points then
                        for index, point in ipairs(original.points) do
                            local target = action.points[index]
                            target.x, target.y, target.z = point.x + offsetX, point.y + offsetY, point.z + offsetZ
                        end
                        action._route = nil
                    end
                end
            end
        end
        ctx.playback.sceneApply(editorState.playhead)
    end

    function ctx.placement.sceneDragEnd()
        if not editorState.dragSession then
            return false
        end
        ctx.placement.sceneDragUpdate(1.0)
        editorState.dragSession = nil
        ctx.scene.sceneSend()
        return true
    end

    function ctx.placement.sceneSendScreenPositions()
        if #editorState.sceneActors == 0 then
            if editorState.lastActorPacket ~= "empty" then
                editorState.lastActorPacket = "empty"
                SendNUIMessage({ action = "actorScreen", positions = {}, selectedId = editorState.selectedActorId })
            end
            return
        end
        local cameraState = ctx.camera.getCameraState()
        if not cameraState then
            return
        end
        local width, height = GetActiveScreenResolution()
        local aspect = width > 0 and height > 0 and width / height or 16 / 9
        local positions = {}
        for _, actor in ipairs(editorState.sceneActors) do
            local handle = editorState.sceneEntities[actor.id]
            if handle and DoesEntityExist(handle) and actor._visible ~= false then
                local position = GetEntityCoords(handle)
                local x, y = DirectorGeometry.project(cameraState, aspect, {
                    x = position.x,
                    y = position.y,
                    z = position.z + 0.9,
                })
                if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                    positions[#positions + 1] = { id = actor.id, x = x, y = y, kind = actor.kind }
                end
            end
        end
        local parts = { tostring(editorState.selectedActorId) }
        for _, position in ipairs(positions) do
            parts[#parts + 1] = ("%s:%s:%.4f:%.4f"):format(position.id, position.kind, position.x, position.y)
        end
        local signature = table.concat(parts, "|")
        if signature ~= editorState.lastActorPacket then
            editorState.lastActorPacket = signature
            SendNUIMessage({ action = "actorScreen", positions = positions, selectedId = editorState.selectedActorId })
        end
    end

    return function()
        ctx.bridge.editorCallback("addActor", function(data, callback)
            local ok, message = ctx.scene.sceneAdd(data.kind, data.model)
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("deleteActor", function(data, callback)
            callback({ ok = ctx.scene.sceneDelete(tonumber(data.id)) })
        end)

        ctx.bridge.editorCallback("selectActor", function(data, callback)
            local id = tonumber(data.id)
            local handle = id and editorState.sceneEntities[id]
            if not handle or not DoesEntityExist(handle) then
                callback({ ok = false })
                return
            end
            if
                editorState.selectedActorId
                and editorState.sceneEntities[editorState.selectedActorId]
                and DoesEntityExist(editorState.sceneEntities[editorState.selectedActorId])
            then
                ctx.placement.selectionOutline(editorState.sceneEntities[editorState.selectedActorId], false)
            end
            editorState.selectedActorId = id
            local visible = true
            for _, actor in ipairs(editorState.sceneActors) do
                if actor.id == id then
                    visible = actor._visible ~= false
                    break
                end
            end
            ctx.placement.selectionOutline(handle, visible)
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("setActorTransform", function(data, callback)
            local ok, message = ctx.placement.sceneSetTransform(tonumber(data.id), data)
            callback({ ok = ok, message = message })
        end)

        ctx.bridge.editorCallback("beginActorDrag", function(data, callback)
            local id = ctx.placement.sceneDragBegin(data)
            callback({ ok = id ~= nil, id = id })
        end)

        ctx.bridge.editorCallback("dragActor", function(data, callback)
            callback({ ok = ctx.placement.sceneDragMove(data) })
        end)

        ctx.bridge.editorCallback("endActorDrag", function(_, callback)
            callback({ ok = ctx.placement.sceneDragEnd() })
        end)
    end
end
