-- Evaluate actor routes, animations and attachments at the playhead.
DirectorClient.modules.playback = function(ctx)
    local editorState = ctx.state
    ctx.playback = {}

    function ctx.playback.routeRootOffset(actor)
        if actor.kind ~= "ped" then
            local found, z = GetGroundZFor_3dCoord(actor.x + 0.0, actor.y + 0.0, (actor.z + 1.5) + 0.0, false)
            if found and type(z) == "number" and z == z and math.abs(actor.z - z) < 4 then
                return actor.z - z
            end
            local minimum = GetModelDimensions(GetHashKey(actor.model))
            return -minimum.z
        end
        if actor._routeRootOffset == nil then
            local minimum = GetModelDimensions(GetHashKey(actor.model))
            actor._routeRootOffset = minimum and ctx.maths.clamp(-minimum.z, 0.1, 1.5) or 1.0
        end
        return actor._routeRootOffset
    end

    function ctx.playback.normalizeRoute(actor, action)
        if not action.points or action.coordinateSpace == "entity" then
            return
        end
        local offset = ctx.playback.routeRootOffset(actor)
        for _, point in ipairs(action.points) do
            point.z = point.z + offset
        end
        local last = action.points[#action.points]
        if last then
            action.x, action.y, action.z = last.x, last.y, last.z
        end
        action.coordinateSpace = "entity"
        action._route, action._routeStart = nil, nil
    end

    function ctx.playback.sampleMove(action, start, progress)
        local eased = progress * progress * (3 - 2 * progress)
        if action.points then
            local signature = ("%.5f:%.5f:%.5f"):format(start.x, start.y, start.z)
            if not action._route or action._routeStart ~= signature then
                action._route = DirectorRoutes.compile(start, action.points)
                action._routeStart = signature
            end
            local point, heading = DirectorRoutes.sample(action._route, progress)
            return point, heading, action._route.length * progress
        end
        local dx, dy, dz = action.x - start.x, action.y - start.y, action.z - start.z
        return { x = start.x + dx * eased, y = start.y + dy * eased, z = start.z + dz * eased },
            (dx * dx + dy * dy > 0.01 and (math.deg(math.atan(-dx, dy)) + 360) % 360 or nil),
            math.sqrt(dx * dx + dy * dy + dz * dz) * eased
    end

    ctx.playback.sceneApply = function(time, forceSync)
        local now = GetGameTimer()
        DirectorPedCues.groundFrame(now)
        for _, actor in ipairs(editorState.sceneActors) do
            local handle = editorState.sceneEntities[actor.id]
            if handle and DoesEntityExist(handle) then
                local recorded = actor.actions and actor.actions[1]
                if recorded and recorded.type == "recording" then
                    DirectorRecording.apply(actor, handle, recorded, time, editorState.previewing, forceSync)
                    goto nextActor
                end
                local x, y, z, heading = actor.x, actor.y, actor.z, actor.heading
                local fromX, fromY, fromZ = actor.x, actor.y, actor.z
                local fromHeading = actor.heading
                local wheelTravel = 0.0
                local moveAction, animationAction, finishedExit
                local visible = not actor.attachment or actor.attachment.visible
                for _, step in ipairs(actor.actions or {}) do
                    if step.type == "move" then
                        ctx.playback.normalizeRoute(actor, step)
                    end
                    if step.type == "move" and step.time <= time then
                        if moveAction then
                            local previous = ctx.maths.clamp(
                                (step.time - moveAction.time) / math.max(moveAction.duration, 0.1),
                                0,
                                1
                            )
                            local point, targetHeading, travelled =
                                ctx.playback.sampleMove(moveAction, { x = fromX, y = fromY, z = fromZ }, previous)
                            fromHeading = (
                                fromHeading
                                + ctx.maths.wrapAngle((targetHeading or fromHeading) - fromHeading)
                                    * ctx.maths.clamp(previous / 0.2, 0, 1)
                            ) % 360
                            wheelTravel = wheelTravel + travelled
                            fromX, fromY, fromZ = point.x, point.y, point.z
                        end
                        moveAction = step
                    elseif step.type == "exitVehicle" and step.time + step.duration <= time then
                        finishedExit = step
                        local p = editorState.previewing
                                and not forceSync
                                and actor._seatExitPosition
                                and actor._seatExitPosition.id == step.id
                                and actor._seatExitPosition
                            or step
                        fromX, fromY, fromZ = p.x, p.y, p.z
                        x, y, z = p.x, p.y, p.z
                        moveAction = nil
                    elseif step.type == "animation" and step.time <= time then
                        animationAction = (not step.duration or time < step.time + step.duration) and step or nil
                    elseif step.type == "visibility" and step.time <= time then
                        visible = step.visible
                    end
                end
                local vehicleState = actor.kind == "ped" and DirectorSeats.state(actor.actions, time)
                actor._seatDesired = vehicleState
                if vehicleState then
                    if vehicleState.phase == "entering" then
                        local p = { x = fromX, y = fromY, z = fromZ }
                        if moveAction then
                            p = ctx.playback.sampleMove(
                                moveAction,
                                p,
                                ctx.maths.clamp(
                                    (vehicleState.action.time - moveAction.time) / moveAction.duration,
                                    0,
                                    1
                                )
                            )
                        end
                        actor._seatEntryPosition = p
                    end
                    goto nextActor
                end
                if actor._seatCue or actor._seatAttached then
                    if
                        IsPedInAnyVehicle(handle, false)
                        and actor._seatVehicle
                        and DoesEntityExist(actor._seatVehicle)
                    then
                        TaskLeaveVehicle(handle, actor._seatVehicle, 16)
                    end
                    ClearPedTasksImmediately(handle)
                    actor._playing = nil
                    actor._seatCue = nil
                    actor._seatAttached = nil
                    actor._lastApplied = nil
                    SetEntityCollision(handle, false, false)
                end
                local moving = moveAction and time < moveAction.time + moveAction.duration
                local progress = 0.0
                if moveAction then
                    progress = ctx.maths.clamp((time - moveAction.time) / math.max(moveAction.duration, 0.1), 0.0, 1.0)
                    local point, targetHeading =
                        ctx.playback.sampleMove(moveAction, { x = fromX, y = fromY, z = fromZ }, progress)
                    x, y, z = point.x, point.y, point.z
                    heading = (
                        fromHeading
                        + ctx.maths.wrapAngle((targetHeading or fromHeading) - fromHeading)
                            * ctx.maths.clamp(progress / 0.2, 0, 1)
                    ) % 360
                end
                if actor.kind == "ped" then
                    if (moveAction and moveAction.points) or finishedExit then
                        if actor._contactOffset == nil and actor._frozen and not actor._playing then
                            DirectorPedCues.calibrateFeet(actor, handle)
                        end
                        z = DirectorPedCues.groundHeight(
                            actor,
                            handle,
                            x,
                            y,
                            z,
                            ctx.playback.routeRootOffset(actor),
                            now,
                            forceSync
                        )
                        if moving and moveAction then
                            heading = select(
                                2,
                                ctx.playback.sampleMove(moveAction, { x = fromX, y = fromY, z = fromZ }, progress)
                            ) or heading
                        end
                    end
                    if
                        animationAction
                        and animationAction.loop == false
                        and HasAnimDictLoaded(animationAction.dict)
                    then
                        local length = GetAnimDuration(animationAction.dict, animationAction.clip)
                        if length > 0 and time >= animationAction.time + length then
                            animationAction = nil
                        end
                    end
                    if not animationAction then
                        actor._animRequested, actor._animWarning = nil, nil
                    end
                    if animationAction and (not moving or animationAction.time >= moveAction.time) then
                        if actor._playing ~= animationAction.id or forceSync then
                            if actor._animRequested ~= animationAction.id then
                                RequestAnimDict(animationAction.dict)
                                actor._animRequested = animationAction.id
                                actor._animWarning = nil
                                local requestId, dict, token =
                                    animationAction.id, animationAction.dict, editorState.sceneGeneration
                                CreateThread(function()
                                    local deadline = GetGameTimer() + (Config.ModelLoadTimeoutMs or 5000)
                                    while
                                        not HasAnimDictLoaded(dict)
                                        and GetGameTimer() < deadline
                                        and editorState.directorOpen
                                        and editorState.sceneGeneration == token
                                        and actor._animRequested == requestId
                                    do
                                        Wait(10)
                                    end
                                    if
                                        not editorState.directorOpen
                                        or editorState.sceneGeneration ~= token
                                        or actor._animRequested ~= requestId
                                        or not DoesEntityExist(handle)
                                    then
                                        return
                                    end
                                    if HasAnimDictLoaded(dict) then
                                        if not editorState.previewing then
                                            ctx.playback.sceneApply(editorState.playhead, true)
                                        end
                                    else
                                        actor._animWarning = true
                                        SendNUIMessage({
                                            action = "status",
                                            message = "An animation could not load. Check its dictionary and clip.",
                                        })
                                    end
                                end)
                            end
                            if HasAnimDictLoaded(animationAction.dict) then
                                DirectorPedCues.stopRoute(actor, handle)
                                ClearPedTasksImmediately(handle)
                                actor._lookPlaying = nil
                                if not actor._frozen then
                                    FreezeEntityPosition(handle, true)
                                    actor._frozen = true
                                end
                                TaskPlayAnim(
                                    handle,
                                    animationAction.dict,
                                    animationAction.clip,
                                    8.0,
                                    -8.0,
                                    -1,
                                    animationAction.loop == false and 0 or 1,
                                    0.0,
                                    false,
                                    false,
                                    false
                                )
                                local animationLength = GetAnimDuration(animationAction.dict, animationAction.clip)
                                local phase = animationLength > 0.0
                                        and (animationAction.loop == false and ctx.maths.clamp(
                                            (time - animationAction.time) / animationLength,
                                            0.0,
                                            0.999
                                        ) or ((time - animationAction.time) % animationLength) / animationLength)
                                    or 0.0
                                SetEntityAnimCurrentTime(
                                    handle,
                                    animationAction.dict,
                                    animationAction.clip,
                                    phase + 0.0
                                )
                                actor._playing = animationAction.id
                            end
                        end
                    elseif moving and editorState.previewing and not forceSync then
                        local starting = actor._playing ~= moveAction.id
                        if starting then
                            ClearPedTasksImmediately(handle)
                            actor._lookPlaying = nil
                            SetEntityCoordsNoOffset(handle, x + 0.0, y + 0.0, z + 0.0, true, true, true)
                            SetEntityHeading(handle, heading + 0.0)
                            if actor._frozen then
                                FreezeEntityPosition(handle, false)
                                actor._frozen = false
                            end
                        end
                        if moveAction.points then
                            if not actor._groundCollision then
                                SetEntityCollision(handle, true, true)
                                actor._groundCollision = true
                            end
                            moveAction._rootOffset = ctx.playback.routeRootOffset(actor)
                            DirectorPedCues.playRoute(
                                actor,
                                handle,
                                moveAction,
                                progress,
                                { x = x, y = y, z = z },
                                now,
                                starting
                            )
                            actor._playing = moveAction.id
                        elseif starting then
                            local remaining = math.max(0.1, moveAction.time + moveAction.duration - time)
                            local distance =
                                math.sqrt((moveAction.x - x) ^ 2 + (moveAction.y - y) ^ 2 + (moveAction.z - z) ^ 2)
                            TaskGoStraightToCoord(
                                handle,
                                moveAction.x + 0.0,
                                moveAction.y + 0.0,
                                moveAction.z + 0.0,
                                DirectorPedCues.speed(moveAction, distance, remaining) + 0.0,
                                -1,
                                heading + 0.0,
                                0.0
                            )
                            actor._playing = moveAction.id
                        end
                        -- Native tasks control position, heading and floor contact.
                        -- Explicit pause/seek still restores the exact timeline pose.
                        goto nextActor
                    end
                    if
                        (not animationAction or (moving and animationAction.time < moveAction.time))
                        and not (moving and editorState.previewing and moveAction.points and not forceSync)
                    then
                        DirectorPedCues.stopRoute(actor, handle)
                        if actor._playing then
                            ClearPedTasksImmediately(handle)
                            actor._lookPlaying = nil
                        end
                        actor._playing = nil
                        if not actor._frozen then
                            FreezeEntityPosition(handle, true)
                            actor._frozen = true
                        end
                    end
                elseif actor.kind == "vehicle" then
                    local travelled = 0
                    if moveAction then
                        local _, _, distance =
                            ctx.playback.sampleMove(moveAction, { x = fromX, y = fromY, z = fromZ }, progress)
                        travelled = distance
                    end
                    local travel = wheelTravel + travelled
                    if
                        forceSync
                        or actor._lastWheelTravel ~= travel
                        or actor._wheelPreview ~= editorState.previewing
                    then
                        actor._wheelPreview = editorState.previewing
                        for wheel = 0, GetVehicleNumberOfWheels(handle) - 1 do
                            -- Never write travelled distance into the wheel transform (camber).
                            local wheelSpeed = 0.0
                            if moving and editorState.previewing and not forceSync and moveAction then
                                if moveAction._route then
                                    wheelSpeed = moveAction._route.length / math.max(moveAction.duration, 0.1)
                                else
                                    local length = math.sqrt(
                                        (moveAction.x - fromX) ^ 2
                                            + (moveAction.y - fromY) ^ 2
                                            + (moveAction.z - fromZ) ^ 2
                                    )
                                    wheelSpeed = length
                                        * 6
                                        * progress
                                        * (1 - progress)
                                        / math.max(moveAction.duration, 0.1)
                                end
                            end
                            SetVehicleWheelRotationSpeed(handle, wheel, wheelSpeed + 0.0)
                        end
                        actor._lastWheelTravel = travel
                    end
                    local steering = 0.0
                    if moving and moveAction and moveAction._route then
                        local route = moveAction._route
                        local _, nextHeading =
                            DirectorRoutes.sample(route, math.min(1, progress + 1 / math.max(route.length, 1)))
                        steering = ctx.maths.clamp(ctx.maths.wrapAngle((nextHeading or heading) - heading), -30.0, 30.0)
                    end
                    SetVehicleSteeringAngle(handle, steering + 0.0)
                    local cues = DirectorVehicleCues.sample(actor.actions, time)
                    if forceSync or actor._engine ~= cues.engine then
                        SetVehicleEngineOn(handle, cues.engine, true, true)
                        actor._engine = cues.engine
                    end
                    if forceSync or actor._lights ~= cues.lights then
                        SetVehicleLights(handle, cues.lights and 2 or 1)
                        actor._lights = cues.lights
                    end
                    actor._doors = actor._doors or {}
                    for door = 0, 5 do
                        local open = cues.doors[door + 1]
                        if forceSync or actor._doors[door + 1] ~= open then
                            if open then
                                SetVehicleDoorOpen(handle, door, false, forceSync)
                            else
                                SetVehicleDoorShut(handle, door, forceSync)
                            end
                            actor._doors[door + 1] = open
                        end
                    end
                end
                if actor.attachment and not editorState.sceneEntities[actor.attachment.parentId] then
                    visible = false
                end
                if actor.kind == "prop" and actor._visible ~= visible then
                    SetEntityVisible(handle, visible, false)
                    ctx.placement.selectionOutline(handle, visible and editorState.selectedActorId == actor.id)
                    actor._visible = visible
                end
                if not actor.attachment then
                    local last = actor._lastApplied
                    local groundedRoute = actor.kind == "ped" and ((moveAction and moveAction.points) or finishedExit)
                    if
                        actor._groundCollision
                        and not (groundedRoute and moving and editorState.previewing and not forceSync)
                    then
                        SetEntityCollision(handle, false, false)
                        actor._groundCollision = nil
                    end
                    -- Native locomotion/physics may move the ped between frames. The
                    -- absolute route pose wins, even when the sampled pose is unchanged.
                    if groundedRoute then
                        local position = GetEntityCoords(handle)
                        last = { x = position.x, y = position.y, z = position.z, heading = GetEntityHeading(handle) }
                    end
                    local locomotion = groundedRoute and moving and editorState.previewing and not forceSync
                    local tolerance = locomotion and 0.35 or 0.0005
                    if
                        forceSync
                        or not last
                        or math.abs(x - last.x) > tolerance
                        or math.abs(y - last.y) > tolerance
                        or math.abs(z - last.z) > (locomotion and 0.15 or 0.0005)
                    then
                        SetEntityCoordsNoOffset(
                            handle,
                            x + 0.0,
                            y + 0.0,
                            z + 0.0,
                            true,
                            true,
                            groundedRoute and true or false
                        )
                    end
                    if
                        forceSync
                        or not last
                        or math.abs(ctx.maths.wrapAngle(heading - (last.heading or GetEntityHeading(handle))))
                            > 0.02
                    then
                        SetEntityHeading(handle, heading + 0.0)
                    end
                    actor._lastApplied = { x = x, y = y, z = z, heading = heading }
                end
                ::nextActor::
            end
        end
        -- Vehicle poses are now current, regardless of actor list order.
        local vehicles = {}
        local used = {}
        for _, a in ipairs(editorState.sceneActors) do
            if a.kind == "vehicle" then
                vehicles[a.id] = a
            end
        end
        for _, a in ipairs(editorState.sceneActors) do
            local state = a._seatDesired
            local target = state and vehicles[state.action.vehicleId]
            local ped = editorState.sceneEntities[a.id]
            local car = target and editorState.sceneEntities[target.id]
            if state and ped and car and DoesEntityExist(ped) and DoesEntityExist(car) then
                used[target.id] = true
                if not target._seatCollision then
                    SetEntityCollision(car, true, true)
                    target._seatCollision = true
                end
                DirectorPedCues.vehicleCue(a, ped, car, state, editorState.previewing, forceSync)
            end
        end
        for id, a in pairs(vehicles) do
            if a._seatCollision and not used[id] then
                local h = editorState.sceneEntities[id]
                if h and DoesEntityExist(h) then
                    SetEntityCollision(h, false, false)
                end
                a._seatCollision = nil
            end
        end
        for _, a in ipairs(editorState.sceneActors) do
            local h = editorState.sceneEntities[a.id]
            if a.attachment and h and DoesEntityExist(h) then
                DirectorAttachments.apply(a, h, editorState.sceneEntities[a.attachment.parentId])
            end
        end
        -- Apply gaze after all transforms, so moving subjects are already up to date.
        for _, actor in ipairs(editorState.sceneActors) do
            local handle = editorState.sceneEntities[actor.id]
            if actor.kind == "ped" and handle and DoesEntityExist(handle) then
                local cue = DirectorPedCues.lookAt(actor.actions, time)
                local target = cue and cue.targetId and editorState.sceneEntities[cue.targetId]
                if cue and cue.targetId and (not target or not DoesEntityExist(target)) then
                    cue = nil
                end
                if cue then
                    if forceSync or actor._lookPlaying ~= cue.id or actor._lookPreview ~= editorState.previewing then
                        local milliseconds = editorState.previewing
                                and math.max(1, math.ceil((cue.time + cue.duration - time) * 1000))
                            or -1
                        if target then
                            TaskLookAtEntity(handle, target, milliseconds, 2048, 3)
                        else
                            TaskLookAtCoord(handle, cue.x + 0.0, cue.y + 0.0, cue.z + 0.0, milliseconds, 2048, 3)
                        end
                        actor._lookPlaying, actor._lookPreview = cue.id, editorState.previewing
                    end
                elseif actor._lookPlaying or forceSync then
                    TaskClearLookAt(handle)
                    actor._lookPlaying, actor._lookPreview = nil, nil
                end
            end
        end
    end

    return function() end
end
