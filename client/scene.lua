-- Actor entity creation, replacement and cleanup.
DirectorClient.modules.scene = function(ctx)
    local editorState = ctx.state
    ctx.scene = {}

    ctx.scene.sceneClear = function()
        if editorState.outlinedHandle then
            ctx.placement.selectionOutline(editorState.outlinedHandle, false)
        end
        if ctx.camera.stopShotPreview then
            ctx.camera.stopShotPreview()
        end
        DirectorPedCues.resetGround()
        editorState.sceneGeneration = editorState.sceneGeneration + 1
        editorState.lastActorPacket = nil
        if ctx.actions.stopAnimationPreview then
            ctx.actions.stopAnimationPreview(false)
        end
        editorState.dragSession = nil
        editorState.selectedActorId = nil
        for _, handle in pairs(editorState.sceneEntities) do
            if DoesEntityExist(handle) then
                DeleteEntity(handle)
            end
        end
        editorState.sceneEntities = {}
        for _, gesture in pairs(DirectorRecording.gestures) do
            RemoveAnimDict(gesture.dict)
        end
    end

    function ctx.scene.sceneModel(model, token)
        if type(model) ~= "string" or not model:match("^[%w_]+$") or #model > 48 then
            return nil
        end
        local hash = GetHashKey(model)
        if not IsModelInCdimage(hash) or not IsModelValid(hash) then
            return nil
        end
        RequestModel(hash)
        local deadline = GetGameTimer() + (Config.ModelLoadTimeoutMs or 5000)
        while
            not HasModelLoaded(hash)
            and GetGameTimer() < deadline
            and editorState.directorOpen
            and token == editorState.sceneGeneration
        do
            Wait(25)
        end
        if not editorState.directorOpen or token ~= editorState.sceneGeneration or not HasModelLoaded(hash) then
            SetModelAsNoLongerNeeded(hash)
            return nil
        end
        return hash
    end

    function ctx.scene.scenePlace()
        local state = ctx.camera.getCameraState()
        if not state then
            return nil
        end
        local pitch, yaw = math.rad(state.rx), math.rad(state.rz)
        local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
        local origin = vector3(state.x, state.y, state.z)
        local target = origin + direction * (Config.PlacementDistance or 150.0)
        local ray = StartShapeTestRay(
            origin.x + 0.0,
            origin.y + 0.0,
            origin.z + 0.0,
            target.x + 0.0,
            target.y + 0.0,
            target.z + 0.0,
            1 + 16,
            PlayerPedId(),
            7
        )
        local pending, hit, point = GetShapeTestResult(ray)
        local deadline = GetGameTimer() + 1000
        while pending == 1 and GetGameTimer() < deadline do
            Wait(0)
            pending, hit, point = GetShapeTestResult(ray)
        end
        if pending == 1 then
            return nil
        end
        if hit == 1 then
            return point.x, point.y, point.z, true
        end
        return target.x, target.y, target.z
    end

    function ctx.scene.sceneSpawn(actor)
        -- Runtime probes/tasks belong to this entity handle, never to a saved actor.
        actor._recordTaskAt = nil
        actor._recordCue = nil
        actor._cueRequested = nil
        actor._aimWeapon = nil
        actor._aimCue = nil
        actor._attachmentSignature = nil
        actor._ground, actor._groundCollision, actor._lastApplied = nil, nil, nil
        actor._placementGround, actor._placementSignature, actor._groundClearance = nil, nil, nil
        actor._routeTaskAt, actor._playing, actor._contactOffset = nil, nil, nil
        actor._nativeRoute = nil
        actor._seatCue, actor._seatFailed, actor._seatVehicle = nil, nil, nil
        actor._seatAttached, actor._seatDesired, actor._seatCollision, actor._seatExitPosition = nil, nil, nil, nil
        local token = editorState.sceneGeneration
        local hash = ctx.scene.sceneModel(actor.model, token)
        if not hash then
            return false, "Invalid or unavailable model."
        end
        if token ~= editorState.sceneGeneration or not editorState.directorOpen then
            SetModelAsNoLongerNeeded(hash)
            return false, "Scene closed or changed while loading."
        end
        local handle
        if actor.kind == "ped" and IsModelAPed(hash) then
            handle = CreatePed(4, hash, actor.x + 0.0, actor.y + 0.0, actor.z + 0.0, actor.heading + 0.0, false, false)
            if handle and handle ~= 0 then
                SetBlockingOfNonTemporaryEvents(handle, true)
            end
        elseif actor.kind == "vehicle" and IsModelAVehicle(hash) then
            handle = CreateVehicle(hash, actor.x + 0.0, actor.y + 0.0, actor.z + 0.0, actor.heading + 0.0, false, false)
        elseif actor.kind == "prop" and not IsModelAPed(hash) and not IsModelAVehicle(hash) then
            handle = CreateObjectNoOffset(hash, actor.x + 0.0, actor.y + 0.0, actor.z + 0.0, false, false, false)
        end
        SetModelAsNoLongerNeeded(hash)
        if not handle or handle == 0 or not DoesEntityExist(handle) then
            return false, "Could not spawn this model."
        end
        SetEntityAsMissionEntity(handle, true, true)
        SetEntityInvincible(handle, true)
        SetEntityCollision(handle, false, false)
        FreezeEntityPosition(handle, true)
        actor._frozen = true
        editorState.sceneEntities[actor.id] = handle
        local appearanceOk, appearance = DirectorAppearance.validate(actor.kind, actor.appearance)
        if appearanceOk then
            actor.appearance = appearance
            DirectorAppearance.apply(actor.kind, handle, appearance)
        end
        if actor.kind == "ped" then
            -- New peds are frozen and have no movement/animation task here.
            -- Give their skeleton a bounded opportunity to initialize.
            for _ = 1, 4 do
                if DirectorPedCues.calibrateFeet(actor, handle) ~= nil then
                    break
                end
                Wait(0)
                if
                    token ~= editorState.sceneGeneration
                    or not editorState.directorOpen
                    or not DoesEntityExist(handle)
                then
                    return false, "Scene changed while calibrating ped feet."
                end
            end
        end
        return true
    end

    ctx.scene.sceneSend = function()
        SendNUIMessage({ action = "actors", actors = ctx.projects.publicActors() })
    end

    ctx.scene.sceneLoad = function(actors, preserveIds, reuse)
        preserveIds = preserveIds ~= false
        editorState.sceneGeneration = editorState.sceneGeneration + 1
        editorState.cameraRig = { mode = "manual" }
        local retained = {}
        if reuse then
            for _, old in ipairs(editorState.sceneActors) do
                local handle = editorState.sceneEntities[old.id]
                for _, incoming in ipairs(actors or {}) do
                    if
                        incoming.id == old.id
                        and not old._missing
                        and handle
                        and DoesEntityExist(handle)
                        and DirectorHistory.same(old, incoming)
                    then
                        retained[old.id] = old
                        break
                    end
                end
            end
            if editorState.outlinedHandle then
                ctx.placement.selectionOutline(editorState.outlinedHandle, false)
            end
            if ctx.camera.stopShotPreview then
                ctx.camera.stopShotPreview()
            end
            if ctx.actions.stopAnimationPreview then
                ctx.actions.stopAnimationPreview(false)
            end
            DirectorPedCues.resetGround()
            editorState.sceneGeneration = editorState.sceneGeneration + 1
            editorState.lastActorPacket = nil
            editorState.dragSession = nil
            editorState.selectedActorId = nil
            for id, handle in pairs(editorState.sceneEntities) do
                if not retained[id] then
                    if DoesEntityExist(handle) then
                        DeleteEntity(handle)
                    end
                    editorState.sceneEntities[id] = nil
                end
            end
        else
            ctx.scene.sceneClear()
        end
        editorState.sceneActors = {}
        editorState.nextActorId = 1
        editorState.nextActionId = 1
        local token = editorState.sceneGeneration
        for _, actor in ipairs(actors or {}) do
            if token ~= editorState.sceneGeneration or not editorState.directorOpen then
                return false
            end
            if #editorState.sceneActors >= Config.MaximumActors then
                break
            end
            if
                type(actor) == "table"
                and (actor.kind == "ped" or actor.kind == "vehicle" or actor.kind == "prop")
                and type(actor.model) == "string"
            then
                actor.actions = type(actor.actions) == "table" and actor.actions or {}
                for _, action in ipairs(actor.actions) do
                    action.id = preserveIds and action.id or editorState.nextActionId
                    editorState.nextActionId = math.max(editorState.nextActionId, action.id + 1)
                end
                table.sort(actor.actions, function(a, b)
                    if a.time == b.time then
                        return a.id < b.id
                    end
                    return a.time < b.time
                end)
                actor.id = preserveIds and actor.id or editorState.nextActorId
                editorState.nextActorId = math.max(editorState.nextActorId, actor.id + 1)
                local old = retained[actor.id]
                if old then
                    actor = old
                    actor._attachmentSignature = nil
                end
                local spawned, reason
                if old then
                    spawned = true
                else
                    spawned, reason = ctx.scene.sceneSpawn(actor)
                end
                actor._missing = not spawned or nil
                editorState.sceneActors[#editorState.sceneActors + 1] = actor
                if not spawned then
                    SendNUIMessage({
                        action = "status",
                        message = "Model unavailable: "
                            .. actor.model
                            .. ". Its project data has been preserved. "
                            .. tostring(reason or ""),
                    })
                end
                if token ~= editorState.sceneGeneration or not editorState.directorOpen then
                    return false
                end
            end
        end
        ctx.playback.sceneApply(editorState.playhead)
        ctx.scene.sceneSend()
        return true
    end

    ctx.scene.sceneAdd = function(kind, model)
        if kind ~= "ped" and kind ~= "vehicle" and kind ~= "prop" then
            return false, "Choose a ped, vehicle or prop."
        end
        if #editorState.sceneActors >= Config.MaximumActors then
            return false, "Actor limit reached."
        end
        local x, y, z, surface = ctx.scene.scenePlace()
        if not x then
            return false, "Camera is not ready."
        end
        local heading = ctx.camera.getCameraState().rz
        local actor = {
            id = editorState.nextActorId,
            kind = kind,
            model = model,
            x = x,
            y = y,
            z = z,
            heading = heading,
            actions = {},
        }
        local ok, errorMessage = ctx.scene.sceneSpawn(actor)
        if not ok then
            return false, errorMessage
        end
        ctx.placement.placementRoot(actor, x, y, z, surface)
        editorState.sceneActors[#editorState.sceneActors + 1] = actor
        editorState.nextActorId = editorState.nextActorId + 1
        ctx.scene.sceneSend()
        return true
    end

    ctx.scene.sceneDelete = function(id)
        for index, actor in ipairs(editorState.sceneActors) do
            if actor.id == id then
                if editorState.selectedActorId == id then
                    editorState.selectedActorId = nil
                    editorState.dragSession = nil
                end
                local handle = editorState.sceneEntities[id]
                if actor._placementGround then
                    actor._placementGround.cancelled = true
                end
                if actor._ground then
                    actor._ground.cancelled = true
                end
                if handle and DoesEntityExist(handle) then
                    DeleteEntity(handle)
                end
                if editorState.outlinedHandle == handle then
                    editorState.outlinedHandle = nil
                end
                editorState.sceneEntities[id] = nil
                local removed = { [id] = true }
                table.remove(editorState.sceneActors, index)
                for childIndex = #editorState.sceneActors, 1, -1 do
                    local child = editorState.sceneActors[childIndex]
                    if child.attachment and child.attachment.parentId == id then
                        local object = editorState.sceneEntities[child.id]
                        if object and DoesEntityExist(object) then
                            DeleteEntity(object)
                        end
                        removed[child.id] = true
                        editorState.sceneEntities[child.id] = nil
                        table.remove(editorState.sceneActors, childIndex)
                        if editorState.selectedActorId == child.id then
                            editorState.selectedActorId = nil
                        end
                    end
                end
                for _, other in ipairs(editorState.sceneActors) do
                    for actionIndex = #other.actions, 1, -1 do
                        local action = other.actions[actionIndex]
                        if (action.type == "lookAt" and removed[action.targetId]) or removed[action.vehicleId] then
                            table.remove(other.actions, actionIndex)
                        end
                    end
                end
                ctx.playback.sceneApply(editorState.playhead, true)
                if removed[editorState.sceneLook.focusId] then
                    editorState.sceneLook.focusId = nil
                end
                for _, shot in ipairs(editorState.cameraShots) do
                    if removed[shot.rig.targetId] then
                        local anchor = shot.rig.anchor
                        shot.rig = { mode = "manual" }
                        if #shot.frames == 0 and anchor then
                            local frame = DirectorShots.copy(anchor)
                            frame.time = shot.time
                            shot.frames = { frame }
                        end
                    end
                end
                if removed[editorState.cameraRig.targetId] then
                    editorState.cameraRig = { mode = "manual" }
                    ctx.projects.sendProject()
                end
                ctx.scene.sceneSend()
                return true
            end
        end
        return false
    end

    return function() end
end
