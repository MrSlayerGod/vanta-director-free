-- Live movement recording, trimming and gesture capture.
DirectorClient.modules.recording = function(ctx)
    local editorState = ctx.state
    ctx.recording = {}

    function ctx.recording.resolveRecordModel(kind, hash, supplied)
        if
            type(supplied) == "string"
            and supplied:match("^[%w_]+$")
            and #supplied <= 48
            and GetHashKey(supplied) == hash
        then
            return supplied
        end
        if not editorState.recordModelCache[kind] then
            local map = {}
            local ok, catalog =
                pcall(json.decode, LoadResourceFile(GetCurrentResourceName(), "model_catalog.json") or "[]")
            if ok and type(catalog) == "table" then
                for _, item in ipairs(catalog) do
                    if item.kind == kind then
                        map[GetHashKey(item.model)] = item.model
                    end
                end
            end
            for _, item in ipairs(Config.CustomModels or {}) do
                if item.kind == kind then
                    map[GetHashKey(item.model)] = item.model
                end
            end
            if kind == "vehicle" and type(GetAllVehicleModels) == "function" then
                for _, name in ipairs(GetAllVehicleModels()) do
                    map[GetHashKey(name)] = name
                end
            end
            editorState.recordModelCache[kind] = map
        end
        return editorState.recordModelCache[kind][hash]
    end

    function ctx.recording.recordSample(session, seconds)
        if not DoesEntityExist(session.handle) then
            return false
        end
        local p = GetEntityCoords(session.handle)
        local r = GetEntityRotation(session.handle, 2)
        local function round(v)
            return math.floor(v * 1000 + 0.5) / 1000
        end
        local row = {
            round(seconds),
            round(p.x),
            round(p.y),
            round(p.z),
            round(r.x),
            round(r.y),
            round(r.z),
            round(math.min(150, math.max(0, GetEntitySpeed(session.handle)))),
        }
        if
            session.kind == "ped"
            and (not session._poseScan or GetGameTimer() - session._poseScan >= 250)
            and type(IsEntityPlayingAnim) == "function"
        then
            session._poseScan = GetGameTimer()
            local active = nil
            for name, gesture in pairs(DirectorRecording.gestures) do
                if IsEntityPlayingAnim(session.handle, gesture.dict, gesture.clip, 3) then
                    active = name
                    break
                end
            end
            if active ~= session._activeGesture then
                if session._activeCue then
                    session._activeCue.duration = math.max(0, seconds - session._activeCue.time)
                end
                session._activeGesture = active
                session._activeCue = nil
                if active and #session.poseCues < 30 then
                    local cue = { gesture = active, time = seconds, duration = 0 }
                    session.poseCues[#session.poseCues + 1] = cue
                    session._activeCue = cue
                end
            end
        end
        local previous = session.samples[#session.samples]
        if session.kind == "ped" and session.captureAim then
            local fired = IsPedShooting(session.handle)
            if session._activeAim then
                session._activeAim.fired = session._activeAim.fired or fired
                session._activeAim.duration = math.min(0.5, seconds - session._activeAim.time)
            end
            if not session._aimScan or seconds - session._aimScan >= 0.2 then
                session._aimScan = seconds
                session._activeAim = nil
                if IsPlayerFreeAiming(PlayerId()) and #session.aimCues < Config.MaximumAimCues then
                    local selected = GetSelectedPedWeapon(session.handle)
                    local weapon
                    for _, name in ipairs(DirectorRecording.weapons) do
                        if GetHashKey(name) == selected then
                            weapon = name
                            break
                        end
                    end
                    if weapon then
                        local cameraPosition = GetGameplayCamCoord()
                        local rotation = GetGameplayCamRot(2)
                        local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
                        local cue = {
                            weapon = weapon,
                            time = seconds,
                            duration = 0,
                            fired = fired == true,
                            x = round(cameraPosition.x - math.sin(yaw) * math.cos(pitch) * 100),
                            y = round(cameraPosition.y + math.cos(yaw) * math.cos(pitch) * 100),
                            z = round(cameraPosition.z + math.sin(pitch) * 100),
                        }
                        session.aimCues[#session.aimCues + 1] = cue
                        session._activeAim = cue
                    end
                end
            end
        end
        if not previous or row[1] > previous[1] then
            session.samples[#session.samples + 1] = row
        end
        return true
    end

    ctx.recording.finishMotionRecording = function(cancelled)
        local session = editorState.motionRecording
        if not session then
            return
        end
        editorState.motionRecording = nil
        local elapsed = math.min(session.limit, (GetGameTimer() - session.started) / 1000)
        if not cancelled then
            ctx.recording.recordSample(session, elapsed)
        end
        if session._activeCue then
            session._activeCue.duration = math.max(0, elapsed - session._activeCue.time)
        end
        session.poseCues = DirectorRecording.trimCues(session.poseCues, 0, elapsed)
        if session._activeAim then
            session._activeAim.duration = math.min(0.5, elapsed - session._activeAim.time)
        end
        session.aimCues = DirectorRecording.trimAimCues(session.aimCues, 0, elapsed)
        local ok, samples = DirectorRecording.validate(session.samples)
        local message = cancelled and "Movement recording cancelled." or "Record for at least 0.1 seconds."
        if not cancelled and ok then
            local before = DirectorHistory.copy(ctx.projects.projectPayload())
            local first = samples[1]
            local a = {
                id = editorState.nextActorId,
                kind = session.kind,
                model = session.model,
                x = first[2],
                y = first[3],
                z = first[4],
                heading = first[7],
                appearance = session.appearance,
                actions = {
                    {
                        id = editorState.nextActionId,
                        type = "recording",
                        time = session.time,
                        duration = samples[#samples][1],
                        samples = samples,
                        poseCues = session.poseCues,
                        aimCues = session.aimCues,
                    },
                },
            }
            local candidate = DirectorHistory.copy(before)
            candidate.actors[#candidate.actors + 1] = a
            candidate.duration = math.max(editorState.duration, session.time + a.actions[1].duration)
            local batch = { a }
            for i, occupant in ipairs(session.occupants or {}) do
                local child = {
                    id = editorState.nextActorId + i,
                    kind = "ped",
                    model = occupant.model,
                    name = occupant.seat == -1 and "Recorded driver" or "Recorded passenger",
                    x = first[2],
                    y = first[3],
                    z = first[4],
                    heading = first[7],
                    appearance = occupant.appearance,
                    group = "Take " .. editorState.nextActorId,
                    actions = {
                        {
                            id = editorState.nextActionId + i,
                            type = "enterVehicle",
                            vehicleId = a.id,
                            seat = occupant.seat,
                            time = session.time,
                            duration = 0.1,
                            instant = true,
                        },
                    },
                }
                batch[#batch + 1] = child
                candidate.actors[#candidate.actors + 1] = child
            end
            if #batch > 1 then
                a.group = "Take " .. editorState.nextActorId
            end
            local encoded = json.encode(candidate)
            if
                encoded
                and #encoded <= Config.ProjectFileLimit
                and #editorState.sceneActors + #batch <= Config.MaximumActors
            then
                editorState.editBusy = true
                local spawned, errorMessage = true, nil
                for _, item in ipairs(batch) do
                    local ok, reason = ctx.scene.sceneSpawn(item)
                    if not ok then
                        spawned = false
                        errorMessage = reason
                        break
                    end
                end
                if spawned then
                    for _, item in ipairs(batch) do
                        editorState.sceneActors[#editorState.sceneActors + 1] = item
                    end
                    editorState.nextActorId = editorState.nextActorId + #batch
                    editorState.nextActionId = editorState.nextActionId + #batch
                    editorState.duration = candidate.duration
                    editorState.playhead = session.time
                    editorState.selectedActorId = a.id
                    DirectorHistory.commit(editorState.history, before, ctx.projects.projectPayload())
                    message = "Movement take added. Drag its RECORD clip to change the start time."
                    SendNUIMessage({ action = "saveState", saved = false })
                else
                    for _, item in ipairs(batch) do
                        local h = editorState.sceneEntities[item.id]
                        if h and DoesEntityExist(h) then
                            DeleteEntity(h)
                        end
                        editorState.sceneEntities[item.id] = nil
                    end
                    message = errorMessage or "Could not spawn recorded actors. The take was rolled back."
                end
                editorState.editBusy = false
            else
                message = "Project size or actor limit reached. The recording was not added."
            end
        end
        if editorState.directorOpen and editorState.camera and DoesCamExist(editorState.camera) then
            RenderScriptCams(true, true, 250, true, true)
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            ctx.projects.sendProject()
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.history.sendHistory()
            SendNUIMessage({ action = "motionRecordFinished", message = message })
        end
    end

    return function()
        RegisterCommand("director_free_status", function()
            local keys = ctx.camera.frameCount()
            local actions, entities, recordings = 0, 0, 0
            for _, actor in ipairs(editorState.sceneActors) do
                local h = editorState.sceneEntities[actor.id]
                if h and DoesEntityExist(h) then
                    entities = entities + 1
                end
                for _, action in ipairs(actor.actions or {}) do
                    actions = actions + 1
                    if action.type == "recording" then
                        recordings = recordings + 1
                    end
                end
            end
            local encoded = json.encode(ctx.projects.projectPayload())
            print(
                ("[VANTA DIRECTOR] version=0.1.0-beta open=%s actors=%d entities=%d keys=%d actions=%d takes=%d bytes=%d playback=%s capture=%s session=%s"):format(
                    tostring(editorState.directorOpen),
                    #editorState.sceneActors,
                    entities,
                    keys,
                    actions,
                    recordings,
                    encoded and #encoded or 0,
                    tostring(editorState.previewing),
                    tostring(editorState.captureMode ~= nil and editorState.captureMode ~= false),
                    editorState.collaboration and editorState.collaboration.role or "solo"
                )
            )
            print(
                ctx.lifecycle.localeText(
                    "[VANTA DIRECTOR] Performance measurements: use resmon 1 and profiler record 500 in F8. This report does not measure resource CPU time."
                )
            )
        end, false)

        CreateThread(function()
            while true do
                local session = editorState.motionRecording
                if session then
                    local elapsed = (GetGameTimer() - session.started) / 1000
                    local sourceChanged = PlayerPedId() ~= session.ped
                        or not DoesEntityExist(session.handle)
                        or IsEntityDead(session.ped)
                    if session.kind == "ped" and IsPedInAnyVehicle(session.ped, false) then
                        sourceChanged = true
                    end
                    if
                        session.kind == "vehicle"
                        and (
                            GetVehiclePedIsIn(session.ped, false) ~= session.handle
                            or GetPedInVehicleSeat(session.handle, -1) ~= session.ped
                        )
                    then
                        sourceChanged = true
                    end
                    if not sourceChanged and session.occupants then
                        for seat = -1, math.min(15, GetVehicleModelNumberOfSeats(GetEntityModel(session.handle)) - 2) do
                            local expected = 0
                            for _, occupant in ipairs(session.occupants) do
                                if occupant.seat == seat then
                                    expected = occupant.handle
                                    break
                                end
                            end
                            if GetPedInVehicleSeat(session.handle, seat) ~= expected then
                                sourceChanged = true
                                break
                            end
                        end
                    end
                    if sourceChanged then
                        ctx.recording.finishMotionRecording(true)
                    elseif elapsed >= session.limit then
                        ctx.recording.finishMotionRecording(false)
                    else
                        ctx.recording.recordSample(session, elapsed)
                        SendNUIMessage({ action = "motionRecordProgress", time = elapsed, limit = session.limit })
                    end
                    Wait(50)
                else
                    Wait(250)
                end
            end
        end)

        ctx.bridge.editorCallback("addRecordedGesture", function(data, callback)
            local actor
            for _, a in ipairs(editorState.sceneActors) do
                if a.id == tonumber(data.id) then
                    actor = a
                    break
                end
            end
            local clip = actor and actor.actions[1]
            local seconds = tonumber(data.duration)
            if not actor or actor.kind ~= "ped" or not clip or clip.type ~= "recording" or not seconds then
                callback({ ok = false, message = "Choose a recorded ped take." })
                return
            end
            local cues = DirectorShots.copy(clip.poseCues or {})
            cues[#cues + 1] = { gesture = data.gesture, time = editorState.playhead - clip.time, duration = seconds }
            local clean, message = DirectorRecording.validateCues(cues, clip.duration)
            if not clean then
                callback({ ok = false, message = message })
                return
            end
            clip.poseCues = clean
            actor._recordCue = nil
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.scene.sceneSend()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("trimRecording", function(data, callback)
            local actor
            for _, a in ipairs(editorState.sceneActors) do
                if a.id == tonumber(data.id) then
                    actor = a
                    break
                end
            end
            local clip = actor and actor.actions[1]
            if not clip or clip.type ~= "recording" then
                callback({ ok = false, message = "Choose a recorded take." })
                return
            end
            local samples, message = DirectorRecording.trim(clip.samples, tonumber(data.first), tonumber(data.last))
            if not samples then
                callback({ ok = false, message = message })
                return
            end
            clip.poseCues = DirectorRecording.trimCues(clip.poseCues, tonumber(data.first), tonumber(data.last))
            clip.aimCues = DirectorRecording.trimAimCues(clip.aimCues, tonumber(data.first), tonumber(data.last))
            clip.samples = samples
            clip.duration = samples[#samples][1]
            clip._travel = nil
            actor._recordTaskAt = nil
            actor.x, actor.y, actor.z, actor.heading = samples[1][2], samples[1][3], samples[1][4], samples[1][7]
            ctx.playback.sceneApply(editorState.playhead, true)
            ctx.scene.sceneSend()
            callback({ ok = true })
        end)

        ctx.bridge.editorCallback("startMotionRecording", function(data, callback)
            if editorState.collaboration then
                callback({ ok = false, message = "Leave shared filming before recording live gameplay." })
                return
            end
            if
                not editorState.directorOpen
                or editorState.previewing
                or editorState.captureMode
                or editorState.dragSession
                or editorState.routeDraft
                or editorState.editBusy
                or editorState.historyBusy
                or DirectorModelBrowser.active
            then
                callback({ ok = false, message = "Stop playback and finish the current edit first." })
                return
            end
            if #editorState.sceneActors >= Config.MaximumActors then
                callback({ ok = false, message = "Actor limit reached." })
                return
            end
            local ped = PlayerPedId()
            local kind = data.kind
            local h = ped
            if kind == "vehicle" then
                h = GetVehiclePedIsIn(ped, false)
                if h == 0 or not DoesEntityExist(h) or GetPedInVehicleSeat(h, -1) ~= ped then
                    callback({ ok = false, message = "Sit in the driver seat before opening Director." })
                    return
                end
            elseif kind ~= "ped" then
                callback({ ok = false, message = "Choose player or vehicle." })
                return
            elseif IsPedInAnyVehicle(ped, false) then
                callback({ ok = false, message = "Leave the vehicle to record your character." })
                return
            end
            local model = ctx.recording.resolveRecordModel(kind, GetEntityModel(h), data.model)
            if not model then
                callback({ ok = false, message = "Add this custom model to Config.CustomModels or enter its name." })
                return
            end
            local seconds = tonumber(data.seconds)
            if not seconds or seconds ~= seconds or seconds < 1 or seconds > Config.RecordingMaximumSeconds then
                callback({
                    ok = false,
                    message = ("Choose a recording limit between 1 and %d seconds."):format(
                        Config.RecordingMaximumSeconds
                    ),
                })
                return
            end
            seconds = math.min(seconds, Config.MaximumDuration - editorState.playhead)
            if seconds < 0.1 then
                callback({ ok = false, message = "Move the playhead earlier." })
                return
            end
            local appearanceOk, appearance = DirectorAppearance.validate(kind, DirectorAppearance.read(kind, h))
            if not appearanceOk then
                callback({ ok = false, message = appearance })
                return
            end
            local session = {
                handle = h,
                ped = ped,
                kind = kind,
                model = model,
                appearance = appearance,
                started = GetGameTimer(),
                limit = seconds,
                time = editorState.playhead,
                samples = {},
                poseCues = {},
                aimCues = {},
                captureAim = data.captureAim == true,
            }
            if kind == "vehicle" and data.occupants == true then
                session.occupants = {}
                for seat = -1, math.min(15, GetVehicleModelNumberOfSeats(GetEntityModel(h)) - 2) do
                    local occupant = GetPedInVehicleSeat(h, seat)
                    if occupant ~= 0 and DoesEntityExist(occupant) then
                        local occupantModel = ctx.recording.resolveRecordModel("ped", GetEntityModel(occupant))
                        if not occupantModel then
                            callback({
                                ok = false,
                                message = "Register every occupant model in Config.CustomModels before capturing the seats.",
                            })
                            return
                        end
                        local ok, look = DirectorAppearance.validate("ped", DirectorAppearance.read("ped", occupant))
                        if not ok then
                            callback({ ok = false, message = look })
                            return
                        end
                        session.occupants[#session.occupants + 1] =
                            { handle = occupant, seat = seat, model = occupantModel, appearance = look }
                    end
                end
                if #editorState.sceneActors + 1 + #session.occupants > Config.MaximumActors then
                    callback({ ok = false, message = "Not enough actor slots for the vehicle and its occupants." })
                    return
                end
            end
            if not ctx.recording.recordSample(session, 0) then
                callback({ ok = false, message = "Recording source is unavailable." })
                return
            end
            editorState.motionRecording = session
            editorState.pressedKeys = {}
            ctx.camera.resetMotion()
            RenderScriptCams(false, true, 250, true, true)
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            DisplayHud(true)
            DisplayRadar(true)
            SendNUIMessage({ action = "motionRecordStarted", limit = seconds })
            callback({ ok = true })
        end)

        RegisterCommand("director_free_record_stop", function()
            ctx.recording.finishMotionRecording(false)
        end, false)

        RegisterCommand("director_free_record_cancel", function()
            ctx.recording.finishMotionRecording(true)
        end, false)

        RegisterKeyMapping(
            "director_free_record_stop",
            "VANTA DIRECTOR: finish movement recording",
            "keyboard",
            Config.StopRecordingKey
        )

        RegisterKeyMapping(
            "director_free_record_cancel",
            "VANTA DIRECTOR: cancel movement recording",
            "keyboard",
            Config.CancelRecordingKey
        )
    end
end
