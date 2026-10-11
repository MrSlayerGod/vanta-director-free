-- Route editing sessions and NUI requests.
DirectorClient.modules.routes = function(ctx)
    local editorState = ctx.state
    ctx.routes = {}

    function ctx.routes.routeActor(id)
        for _, actor in ipairs(editorState.sceneActors) do
            if actor.id == id then
                return actor
            end
        end
    end

    function ctx.routes.sendRouteScreen()
        if not editorState.routeDraft or not editorState.directorOpen or editorState.captureMode then
            return
        end
        local state = ctx.camera.getCameraState()
        if not state then
            return
        end
        local width, height = GetActiveScreenResolution()
        local aspect = width / math.max(1, height)
        local points, lines = {}, {}
        local curve = editorState.routeDraft._curve
            or DirectorRoutes.compile(editorState.routeDraft.start, editorState.routeDraft.points)
        editorState.routeDraft._curve = curve
        for index, point in ipairs(editorState.routeDraft.points) do
            local x, y = DirectorGeometry.project(
                state,
                aspect,
                { x = point.x, y = point.y, z = point.z - (editorState.routeDraft.rootOffset or 0.0) + 0.1 }
            )
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                points[#points + 1] = { index = index, x = x, y = y }
            end
        end
        local previous
        local stride = math.max(1, math.ceil(#curve.samples / 160))
        for index = 1, #curve.samples + stride - 1, stride do
            local point = curve.samples[math.min(index, #curve.samples)]
            local x, y = DirectorGeometry.project(
                state,
                aspect,
                { x = point.x, y = point.y, z = point.z - (editorState.routeDraft.rootOffset or 0.0) + 0.06 }
            )
            if x and previous then
                lines[#lines + 1] = { x1 = previous.x, y1 = previous.y, x2 = x, y2 = y }
            end
            previous = x and { x = x, y = y } or nil
        end
        local signature = { tostring(#editorState.routeDraft.points), ("%.2f"):format(curve.length) }
        for _, point in ipairs(points) do
            signature[#signature + 1] = ("%d:%.4f:%.4f"):format(point.index, point.x, point.y)
        end
        for _, line in ipairs(lines) do
            signature[#signature + 1] = ("%.4f:%.4f:%.4f:%.4f"):format(line.x1, line.y1, line.x2, line.y2)
        end
        signature = table.concat(signature, "|")
        if signature ~= editorState.routeDraft._screen then
            editorState.routeDraft._screen = signature
            SendNUIMessage({
                action = "routeScreen",
                routeToken = editorState.routeDraft.token,
                points = points,
                lines = lines,
                length = curve.length,
                count = #editorState.routeDraft.points,
            })
        end
    end

    function ctx.routes.routePointAt(data)
        local sx, sy, aspect =
            ctx.maths.finiteNumber(data.x, 1), ctx.maths.finiteNumber(data.y, 1), ctx.maths.finiteNumber(data.aspect, 4)
        local state = ctx.camera.getCameraState()
        if not state or not sx or not sy or sx < 0 or sy < 0 or not aspect or aspect < 0.5 then
            return nil
        end
        local direction = DirectorGeometry.ray(state, aspect, sx, sy)
        local target =
            { x = state.x + direction.x * 200, y = state.y + direction.y * 200, z = state.z + direction.z * 200 }
        local ray = StartShapeTestRay(
            state.x + 0.0,
            state.y + 0.0,
            state.z + 0.0,
            target.x + 0.0,
            target.y + 0.0,
            target.z + 0.0,
            1 + 16,
            PlayerPedId(),
            7
        )
        local pending, hit, point = GetShapeTestResult(ray)
        local deadline = GetGameTimer() + 250
        while pending == 1 and GetGameTimer() < deadline do
            Wait(0)
            pending, hit, point = GetShapeTestResult(ray)
        end
        if pending == 2 and hit == 1 then
            return { x = point.x, y = point.y, z = point.z }
        end
    end

    return function()
        ctx.bridge.editorCallback("beginRoute", function(data, callback)
            local actor = ctx.routes.routeActor(tonumber(data.id))
            if
                not actor
                or (actor.kind ~= "ped" and actor.kind ~= "vehicle")
                or editorState.captureMode
                or editorState.dragSession
            then
                callback({ ok = false, message = "Select a ped or vehicle and stop playback." })
                return
            end
            local handle = editorState.sceneEntities[actor.id]
            if actor._missing or not handle or not DoesEntityExist(handle) then
                callback({
                    ok = false,
                    message = "This model is unavailable. Reload the project after installing the model, or remove this subject.",
                })
                return
            end
            local generation = editorState.sceneGeneration
            editorState.previewing = false
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            ctx.actions.stopAnimationPreview(true)
            local existing
            for _, action in ipairs(actor.actions) do
                if action.id == tonumber(data.actionId) and action.type == "move" then
                    existing = action
                end
            end
            if data.actionId and not existing then
                callback({ ok = false, message = "Movement action no longer exists." })
                return
            end
            if existing then
                ctx.playback.normalizeRoute(actor, existing)
            end
            local at = existing and existing.time or editorState.playhead
            ctx.camera.setPlayhead(at)
            if
                not editorState.directorOpen
                or generation ~= editorState.sceneGeneration
                or editorState.sceneEntities[actor.id] ~= handle
                or not DoesEntityExist(handle)
            then
                callback({ ok = false, message = "Scene changed while preparing the route." })
                return
            end
            local position = GetEntityCoords(handle)
            editorState.routeRequestSerial = editorState.routeRequestSerial + 1
            editorState.routeDraft = {
                token = editorState.routeRequestSerial,
                actorId = actor.id,
                rootOffset = ctx.playback.routeRootOffset(actor),
                actionId = existing and existing.id,
                time = at,
                start = { x = position.x, y = position.y, z = position.z },
                points = existing
                        and DirectorHistory.copy(
                            existing.points or { { x = existing.x, y = existing.y, z = existing.z } }
                        )
                    or {},
            }
            ctx.routes.sendRouteScreen()
            callback({
                ok = true,
                routeToken = editorState.routeDraft.token,
                duration = existing and existing.duration or 3,
                gait = existing and existing.gait or "auto",
                speed = existing and existing.speed,
                points = editorState.routeDraft.points,
            })
        end)

        ctx.bridge.editorCallback("addRoutePoint", function(data, callback)
            if not editorState.routeDraft or #editorState.routeDraft.points >= Config.MaximumRoutePoints then
                callback({ ok = false, message = "Route limit reached." })
                return
            end
            local draft = editorState.routeDraft
            local point = ctx.routes.routePointAt(data)
            if editorState.routeDraft ~= draft or not point then
                callback({ ok = false, message = "Click a visible ground surface within 200 metres." })
                return
            end
            point.z = point.z + (draft.rootOffset or 0.0)
            draft.points[#draft.points + 1] = point
            draft._curve = nil
            ctx.routes.sendRouteScreen()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("beginRoutePoint", function(data, callback)
            local index = tonumber(data.index)
            local point = editorState.routeDraft and editorState.routeDraft.points[index]
            if not point then
                callback({ ok = false })
                return
            end
            local token = tonumber(data.token)
            if not token or token <= (editorState.routeDraft.lastDragToken or -1) then
                callback({ ok = false })
                return
            end
            editorState.routeDraft.lastDragToken = token
            local state = ctx.camera.getCameraState()
            local sx, sy, aspect =
                ctx.maths.finiteNumber(data.x, 1),
                ctx.maths.finiteNumber(data.y, 1),
                ctx.maths.finiteNumber(data.aspect, 4)
            if not state or not sx or not sy or not aspect or aspect < 0.5 then
                callback({ ok = false })
                return
            end
            local _, _, depth = DirectorGeometry.project(
                state,
                aspect,
                { x = point.x, y = point.y, z = point.z - (editorState.routeDraft.rootOffset or 0.0) }
            )
            editorState.routeDraft.drag = {
                token = token,
                index = index,
                base = DirectorHistory.copy(point),
                camera = state,
                x = sx,
                y = sy,
                aspect = aspect,
                depth = depth or 5,
                sequence = -1,
            }
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("moveRoutePoint", function(data, callback)
            local drag = editorState.routeDraft and editorState.routeDraft.drag
            local sx, sy, sequence =
                ctx.maths.finiteNumber(data.x, 1), ctx.maths.finiteNumber(data.y, 1), tonumber(data.sequence)
            if
                not drag
                or tonumber(data.token) ~= drag.token
                or not sx
                or not sy
                or not sequence
                or sequence <= drag.sequence
            then
                callback({ ok = false })
                return
            end
            drag.sequence = sequence
            local offset = DirectorGeometry.dragDelta(
                drag.camera,
                drag.aspect,
                drag.x,
                drag.y,
                sx,
                sy,
                drag.base.z - (editorState.routeDraft.rootOffset or 0.0),
                drag.depth,
                data.heightOnly == true
            )
            if math.abs(offset.x) > 1000 or math.abs(offset.y) > 1000 or math.abs(offset.z) > 1000 then
                callback({ ok = false })
                return
            end
            editorState.routeDraft.points[drag.index] =
                { x = drag.base.x + offset.x, y = drag.base.y + offset.y, z = drag.base.z + offset.z }
            editorState.routeDraft._curve = nil
            ctx.routes.sendRouteScreen()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("endRoutePoint", function(data, callback)
            if
                editorState.routeDraft
                and editorState.routeDraft.drag
                and tonumber(data.token) == editorState.routeDraft.drag.token
            then
                editorState.routeDraft.drag = nil
            end
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("deleteRoutePoint", function(data, callback)
            local index = tonumber(data.index)
            if not editorState.routeDraft or not index or not editorState.routeDraft.points[index] then
                callback({ ok = false })
                return
            end
            table.remove(editorState.routeDraft.points, index)
            editorState.routeDraft._curve = nil
            ctx.routes.sendRouteScreen()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("cancelRoute", function(_, callback)
            local token = editorState.routeDraft and editorState.routeDraft.token
            editorState.routeDraft = nil
            SendNUIMessage({ action = "routeClosed", routeToken = token })
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("commitRoute", function(data, callback)
            local draft = editorState.routeDraft
            local actor = draft and ctx.routes.routeActor(draft.actorId)
            if not actor then
                callback({ ok = false, message = "No route to apply." })
                return
            end
            local points, message = DirectorRoutes.validate(draft.points)
            if not points then
                callback({ ok = false, message = message })
                return
            end
            local curve = DirectorRoutes.compile(draft.start, points)
            if curve.length < 0.05 then
                callback({ ok = false, message = "Place a destination further from the start." })
                return
            end
            if data.inspectObstacles == true then
                local ok, reason = DirectorObstacles.route(
                    curve,
                    actor.kind == "ped" and (draft.rootOffset or 1) or 0,
                    editorState.sceneEntities[actor.id] or 0,
                    function()
                        return editorState.routeDraft ~= draft or not editorState.directorOpen
                    end
                )
                if not ok then
                    callback({ ok = false, message = reason })
                    return
                end
                if editorState.routeDraft ~= draft then
                    callback({ ok = false, message = "Route changed during inspection." })
                    return
                end
            end
            local seconds = ctx.maths.finiteNumber(data.duration, Config.MaximumDuration)
            local speed = data.speed and ctx.maths.finiteNumber(data.speed, 100)
            if data.speed and (not speed or speed < 0.1) then
                callback({ ok = false, message = "Choose a speed between 0.1 and 100 m/s." })
                return
            end
            if speed then
                seconds = curve.length / speed
            end
            if not seconds or seconds < 0.1 or draft.time + seconds > editorState.duration + 0.001 then
                callback({ ok = false, message = "Extend the timeline or increase route speed." })
                return
            end
            local gait = tostring(data.gait or "auto")
            if actor.kind == "ped" and gait ~= "auto" and not DirectorPedCues.gaits[gait] then
                callback({ ok = false, message = "Invalid movement style." })
                return
            end
            local maximumSpeed = ({ walk = 2.0, run = 6.0, sprint = 8.0, auto = 8.0 })[gait] or 8.0
            if actor.kind == "ped" and curve.length / seconds > maximumSpeed then
                callback({
                    ok = false,
                    message = ("Route too fast for %s. Use at least %.1f seconds or choose another gait."):format(
                        gait,
                        math.ceil(curve.length / maximumSpeed * 10) / 10
                    ),
                })
                return
            end
            local action, index
            for i, item in ipairs(actor.actions) do
                if item.id == draft.actionId then
                    action = item
                    index = i
                    break
                end
            end
            if not action and #actor.actions >= Config.MaximumActionsPerActor then
                callback({ ok = false, message = "Action limit reached." })
                return
            end
            local last = points[#points]
            local entry = {
                id = action and action.id or editorState.nextActionId,
                type = "move",
                time = draft.time,
                duration = seconds,
                x = last.x,
                y = last.y,
                z = last.z,
                points = points,
                coordinateSpace = "entity",
                gait = actor.kind == "ped" and gait or nil,
                speed = speed,
            }
            if index then
                actor.actions[index] = entry
            else
                actor.actions[#actor.actions + 1] = entry
            end
            local valid, message = DirectorSeats.validate(editorState.sceneActors, editorState.duration)
            if not valid then
                if index then
                    actor.actions[index] = action
                else
                    table.remove(actor.actions)
                end
                callback({ ok = false, message = message })
                return
            end
            if not index then
                editorState.nextActionId = editorState.nextActionId + 1
            end
            table.sort(actor.actions, function(a, b)
                if a.time == b.time then
                    return a.id < b.id
                end
                return a.time < b.time
            end)
            editorState.routeDraft = nil
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.scene.sceneSend()
            SendNUIMessage({ action = "routeClosed", routeToken = draft.token })
            callback({ ok = true })
        end)
    end
end
