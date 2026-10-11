local camera = nil
local directorOpen = false
local nuiReady, nuiOpenSerial = false, 0
local routeRequestSerial=0
local previewing = false
local captureMode = false
local captureToken=0
local motionRecording=nil
local finishMotionRecording
local pressedKeys = {}
local preferences = DirectorPreferences.load()
local function localeText(message)
    return DirectorLocale and DirectorLocale.text(message,preferences.language) or message
end
local preferencesWrittenAt = -1000
local cameraSpeed = preferences.speed
local duration = Config.DefaultDuration
local playhead = 0.0
local keyframes = {}
local cameraShots={}
local bookmarks={}
local selectedShotId=nil
local function editingShot() return DirectorShots.find(cameraShots,selectedShotId) end
local function editingFrames() local shot=editingShot();return shot and shot.frames or keyframes end
local function frameCount() local count=#keyframes;for _,shot in ipairs(cameraShots) do count=count+#shot.frames end;return count end
local projectName = 'Untitled Project'
local currentProjectId = nil
local pendingSaveSnapshot = nil
local saveRequestSerial = 0
local pendingSaveRequest = nil
local lastUiUpdate = 0
local lastActorScreenUpdate = 0
local lastCameraPacket, lastActorPacket, lastTransportPacket
local previewStartedAt = 0
local previewOffset = 0.0
local playbackRange=nil
local function playbackBounds() return playbackRange and playbackRange.first or 0,playbackRange and math.min(duration,playbackRange.last) or duration end
local timelineClipboard=nil
local collaboration=nil
local collaborationBackup=nil
local sessionPendingPlayback=nil
local focusOwned=false
local lastStreamingFocusUpdate=0
local sessionPlayer=nil
local function releaseSessionPlayer()
    if sessionPlayer and DoesEntityExist(sessionPlayer.handle) then FreezeEntityPosition(sessionPlayer.handle,sessionPlayer.frozen) end
    sessionPlayer=nil
end
local movementVelocity = { x = 0.0, y = 0.0, z = 0.0 }
local turnVelocity = { pitch = 0.0, yaw = 0.0 }
local lastInputSequence = -1
local lastSeekSequence = -1
local lastInputAt = 0
local mouseLookX, mouseLookY = 0.0, 0.0
local sceneClear, sceneLoad, sceneApply, sceneSend, sceneAdd, sceneDelete, sceneAddAction, sceneDeleteAction
local stopAnimationPreview
local sceneActors = {}
local sceneEntities={}
local lastFocusUpdate=0
local cameraRig = { mode = 'manual' }
local shotPreview=nil
local stopShotPreview
local applyCameraRig
local selectedActorId = nil
local outlinedHandle
local function selectionOutline(handle,enabled)
    enabled=enabled and Config.SelectionOutline~=false and not captureMode and directorOpen
    if enabled then
        for _,actor in ipairs(sceneActors) do
            -- Skinned actors keep the existing selected pin/inspector highlight.
            -- The SDK outline renderer is avoided on peds; only one rigid model
            -- can own a silhouette, outside capture and while visible.
            if sceneEntities[actor.id]==handle and (actor._visible==false or actor.kind=='ped') then enabled=false;break end
        end
    end
    if not enabled then
        if outlinedHandle==handle then
            if DoesEntityExist(handle) then SetEntityDrawOutline(handle,false) end
            outlinedHandle=nil
        end
        return
    end
    if outlinedHandle==handle then return end
    if outlinedHandle and DoesEntityExist(outlinedHandle) then SetEntityDrawOutline(outlinedHandle,false) end
    SetEntityDrawOutlineShader(1) -- Firm silhouette; no Gaussian glow.
    SetEntityDrawOutlineColor(table.unpack(Config.SelectionColor or {74,195,225,185}))
    SetEntityDrawOutline(handle,true)
    outlinedHandle=handle
end
local dragSession = nil
local routeDraft = nil
local projectPayload
local history = DirectorHistory.new(40)
local historyBusy, editBusy = false, false
local dragBefore = nil
local function sendHistory()
    SendNUIMessage({action='historyState',undo=#history.past,redo=#history.future,busy=historyBusy or editBusy})
end
local lastDragSequence = -1
local sceneLook = { weather = 'SERVER', hour = -1, minute = 0, dof = false, near = 2.0, far = 30.0, strength = 0.5 }
local weatherTypes = { SERVER = true, EXTRASUNNY = true, CLEAR = true, CLOUDS = true, OVERCAST = true, RAIN = true, THUNDER = true, FOGGY = true, SMOG = true, CLEARING = true }
local lastLookUpdate = 0
local weatherOwned, clockOwned = false, false

local function applySceneLook(force)
    if not directorOpen then return end
    local now = GetGameTimer()
    if force or now - lastLookUpdate >= 1000 then
        lastLookUpdate = now
        if sceneLook.weather ~= 'SERVER' then
            SetOverrideWeather(sceneLook.weather)
            weatherOwned = true
        end
        if sceneLook.hour >= 0 then
            NetworkOverrideClockTime(sceneLook.hour, sceneLook.minute, 0)
            clockOwned = true
        end
    end
    if camera and DoesCamExist(camera) then
        if force then SetCamUseShallowDofMode(camera, sceneLook.dof) end
        if sceneLook.dof then
            if force then
                SetCamNearDof(camera, sceneLook.near + 0.0)
                SetCamFarDof(camera, sceneLook.far + 0.0)
                SetCamDofStrength(camera, sceneLook.strength + 0.0)
            end
            if sceneLook.focusId and now-lastFocusUpdate>=100 then
                lastFocusUpdate=now
                local handle=sceneEntities[sceneLook.focusId]
                if handle and DoesEntityExist(handle) then
                    local p,c=GetEntityCoords(handle),GetCamCoord(camera)
                    local distance=math.sqrt((p.x-c.x)^2+(p.y-c.y)^2+(p.z-c.z)^2)
                    SetCamNearDof(camera,(math.max(.1,distance-1)) + 0.0);SetCamFarDof(camera,(math.max(.2,distance+1)) + 0.0)
                end
            end
            SetUseHiDof()
        end
    end
end

local function clearSceneLook()
    if weatherOwned then
        ClearOverrideWeather()
        weatherOwned = false
    end
    if clockOwned then
        NetworkClearClockTimeOverride()
        clockOwned = false
    end
    if camera and DoesCamExist(camera) then SetCamUseShallowDofMode(camera, false) end
end

local function loadSceneLook(value)
    value = type(value) == 'table' and value or {}
    local weather = tostring(value.weather or 'SERVER'):upper()
    sceneLook.weather = weatherTypes[weather] and weather or 'SERVER'
    sceneLook.hour = math.floor(math.max(-1, math.min(23, tonumber(value.hour) or -1)))
    sceneLook.minute = math.floor(math.max(0, math.min(59, tonumber(value.minute) or 0)))
    sceneLook.dof = value.dof == true
    sceneLook.focusId=tonumber(value.focusId)
    sceneLook.near = math.max(0.1, math.min(100.0, tonumber(value.near) or 2.0))
    sceneLook.far = math.max(sceneLook.near + 0.1, math.min(500.0, tonumber(value.far) or 30.0))
    sceneLook.strength = math.max(0.0, math.min(1.0, tonumber(value.strength) or 0.5))
    if directorOpen then
        clearSceneLook()
        applySceneLook(true)
    end
end

local function resetMotion()
    movementVelocity.x, movementVelocity.y, movementVelocity.z = 0.0, 0.0, 0.0
    turnVelocity.pitch, turnVelocity.yaw = 0.0, 0.0
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function wrapAngle(angle)
    return (angle + 180.0) % 360.0 - 180.0
end

local function lerp(a, b, amount)
    return a + (b - a) * amount
end

local function getCameraState()
    if not camera or not DoesCamExist(camera) then
        return nil
    end

    local position = GetCamCoord(camera)
    local rotation = GetCamRot(camera, 2)
    return {
        x = position.x,
        y = position.y,
        z = position.z,
        rx = rotation.x,
        ry = rotation.y,
        rz = rotation.z,
        fov = GetCamFov(camera)
    }
end

local function publicActors()
    local actors=DirectorHistory.copy(sceneActors)
    for i,actor in ipairs(sceneActors) do
        local handle=sceneEntities[actor.id]
        actors[i].modelAvailable=not actor._missing and handle~=nil and DoesEntityExist(handle)==true
    end
    return actors
end
local function sendProject()
    SendNUIMessage({
        action = 'project',
        project = {
            name = projectName,
            id = currentProjectId,
            duration = duration,
            playhead = playhead,
            keyframes = editingFrames(),
            cameraShots = cameraShots,
            bookmarks = bookmarks,
            playback = playbackRange or {first=0,last=duration,loop=false},
            selectedShotId = selectedShotId,
            actors = publicActors(),
            cameraRig = editingShot() and editingShot().rig or cameraRig,
            look = sceneLook
        }
    })
end

local function sendCameraState()
    local state = getCameraState()
    if state then
        local signature = ('%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f'):format(state.x,state.y,state.z,state.rx,state.ry,state.rz,state.fov)
        if signature == lastCameraPacket then return end
        lastCameraPacket = signature
        SendNUIMessage({ action = 'camera', camera = state })
    end
end

RegisterNUICallback('tutorialStatus', function(data, callback)
    if type(data) ~= 'table' or (data.status ~= 'skipped' and data.status ~= 'completed') then
        callback({ok=false,message='Invalid tutorial choice.'})
        return
    end
    if not directorOpen then callback({ok=false,message='Director is closed.'});return end
    SetResourceKvp('director_free:tutorial:v1', data.status)
    callback({ok=true})
end)
local projectDialogBlur = false
local function clearProjectDialogBlur()
    if not projectDialogBlur then return end
    projectDialogBlur = false
    TriggerScreenblurFadeOut(150.0)
end

RegisterNUICallback('projectDialog', function(data, callback)
    if type(data) ~= 'table' or type(data.open) ~= 'boolean' then
        callback({ok=false,message='Invalid dialog state.'})
        return
    end
    local enabled = data.open and directorOpen and not captureMode
    if enabled and not projectDialogBlur then
        projectDialogBlur = true
        TriggerScreenblurFadeIn(150.0)
    elseif not enabled then clearProjectDialogBlur() end
    callback({ok=true})
end)

local function setNuiOpen(state)
    if not state then clearProjectDialogBlur() end
    lastCameraPacket, lastActorPacket, lastTransportPacket = nil, nil, nil
    directorOpen = state
    nuiOpenSerial=nuiOpenSerial+1
    SetNuiFocus(state and nuiReady, state and nuiReady)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = state and 'open' or 'close' })
    if state then
        SendNUIMessage({action='runtimeConfig',config={edition='free',discordUrl=DirectorFree.discordUrl(),minimumDuration=Config.MinimumDuration,maximumDuration=Config.MaximumDuration,defaultDuration=Config.DefaultDuration,recordingMaximumSeconds=Config.RecordingMaximumSeconds,collaborationEnabled=Config.CollaborationEnabled,stopTakeKey=Config.StopTakeKey,stopRecordingKey=Config.StopRecordingKey,cancelRecordingKey=Config.CancelRecordingKey}})
        SendNUIMessage({action='preferences',preferences=preferences,defaults=DirectorPreferences.defaults()})
        local tutorialStatus = GetResourceKvpString('director_free:tutorial:v1')
        SendNUIMessage({action='tutorialStatus',seen=tutorialStatus=='skipped' or tutorialStatus=='completed'})
    end
end

RegisterNUICallback('nuiReady',function(_,callback)
    local first=not nuiReady;nuiReady=true
    if first and directorOpen then setNuiOpen(true);sendProject();TriggerServerEvent('vanta_director_free:requestProject') end
    callback({ok=true})
end)

local function restorePlayerView()
    clearProjectDialogBlur()
    motionRecording=nil
    if collaboration then TriggerServerEvent('vanta_director_free:sessionAction','leave',{}) end
    collaboration=nil;collaborationBackup=nil;sessionPendingPlayback=nil
    releaseSessionPlayer()
    if focusOwned then ClearFocus();focusOwned=false end
    DirectorModelBrowser.close()
    if stopAnimationPreview then stopAnimationPreview(false) end
    pendingSaveSnapshot = nil
    clearSceneLook()
    previewing = false
    captureMode = false
    dragSession = nil
    routeDraft = nil
    editBusy=false;historyBusy=false;dragBefore=nil
    selectedActorId = nil
    SendNUIMessage({ action = 'close' })
    if sceneClear then sceneClear() end
    sceneActors={}
    pressedKeys = {}
    mouseLookX, mouseLookY = 0.0, 0.0
    resetMotion()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    RenderScriptCams(false, true, 250, true, true)
    if camera and DoesCamExist(camera) then
        DestroyCam(camera, false)
    end
    camera = nil
    DisplayHud(true)
    DisplayRadar(true)
    directorOpen = false
end

CreateThread(function()
    while true do
        if directorOpen and not nuiReady then
            local serial=nuiOpenSerial
            Wait(8000)
            if directorOpen and not nuiReady and serial==nuiOpenSerial then
                restorePlayerView();setNuiOpen(false)
                print(localeText('[VANTA DIRECTOR] Interface failed to start. Focus released; check the packaged NUI files and refresh the resource.'))
            end
        else Wait(500) end
    end
end)

local function toggleDirector()
    if motionRecording then finishMotionRecording(false);return end
    if directorOpen then
        if captureMode then restorePlayerView() else SendNUIMessage({action='requestClose'}) end
        return
    end

    history=DirectorHistory.new(40); dragBefore=nil
    local position = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()

    resetMotion()
    pressedKeys = {}
    currentProjectId = nil
    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, position.x + 0.0, position.y + 0.0, position.z + 0.0)
    SetCamRot(camera, rotation.x + 0.0, rotation.y + 0.0, rotation.z + 0.0, 2)
    SetCamFov(camera, fov + 0.0)
    RenderScriptCams(true, true, 250, true, true)

    DisplayHud(false)
    DisplayRadar(false)
    setNuiOpen(true)
    sendHistory()
    applySceneLook(true)
    sendProject()
    sendCameraState()
    TriggerServerEvent('vanta_director_free:requestProject')
end

local function addKeyframe(atTime)
    local keyframes=editingFrames()
    local shot=editingShot()
    local state = getCameraState()
    if not state then
        return false, 'Camera is not ready.'
    end

    local time = clamp(tonumber(atTime) or playhead, 0.0, duration)
    if shot and (time<shot.time or time>shot.time+shot.duration) then return false,'Move the playhead inside the selected shot.' end
    state.time = time

    local replaced = false
    for index, frame in ipairs(keyframes) do
        if math.abs(frame.time - time) < 0.05 then
            state.name = frame.name
            keyframes[index] = state
            replaced = true
            break
        end
    end

    if not replaced then
        if frameCount() >= Config.MaximumKeyframes then
            return false, 'Keyframe limit reached.'
        end
        keyframes[#keyframes + 1] = state
    end

    table.sort(keyframes, function(a, b) return a.time < b.time end)
    playhead = time
    sendProject()
    return true
end

local function stateAtTime(time)
    local shot=DirectorShots.at(cameraShots,time)
    return DirectorMotion.sample(shot and shot.frames or keyframes,time,shot and shot.ease) or (shot and shot.rig.anchor)
end
local function rigAtTime(time)
    local shot=DirectorShots.at(cameraShots,time)
    return shot and shot.rig or cameraRig, shot
end

local function applyState(state)
    if not state or not camera or not DoesCamExist(camera) then
        return
    end

    SetCamCoord(camera, state.x + 0.0, state.y + 0.0, state.z + 0.0)
    SetCamRot(camera, state.rx + 0.0, state.ry + 0.0, state.rz + 0.0, 2)
    SetCamFov(camera, clamp(state.fov, 20.0, 100.0) + 0.0)
end

local function setPlayhead(time)
    if stopAnimationPreview then stopAnimationPreview(false) end
    resetMotion()
    playhead = clamp(tonumber(time) or 0.0, 0.0, duration)
    if sceneApply then sceneApply(playhead, true) end
    local state = stateAtTime(playhead)
    applyState(state)
    if applyCameraRig then applyCameraRig(playhead, state or cameraRig.anchor,true) end
end

local function startPreview()
    if stopAnimationPreview then stopAnimationPreview(true) end
    if #keyframes == 0 and #cameraShots==0 and cameraRig.mode == 'manual' then
        return false, 'Add at least one keyframe first.'
    end

    local first,last=playbackBounds()
    if playhead<first or playhead>=last then playhead=first end
    resetMotion()
    pressedKeys = {}
    previewing = true
    previewOffset = playhead
    previewStartedAt = GetGameTimer()
    return true
end

local sceneGeneration = 0
local nextActorId = 1
local nextActionId = 1
local animationPreviewActor = nil
local animationPreviewToken = 0

local function sampleRig(rig,base,time)
    if rig.mode=='manual' then return base end
    local handle=sceneEntities[rig.targetId]
    if not handle or not DoesEntityExist(handle) then return base end
    local p=GetEntityCoords(handle)
    return DirectorCameraRig.sample(rig,{x=p.x,y=p.y,z=p.z,heading=GetEntityHeading(handle)},base or rig.anchor or getCameraState(),time)
end
applyCameraRig = function(time,base,forceBlend)
    local rig,shot=rigAtTime(time)
    local blending=shot and (shot.blend or 0)>0 and time<shot.time+shot.blend and (previewing or forceBlend)
    if rig.mode=='manual' and not blending then return end
    local state=sampleRig(rig,base,shot and time-shot.time or time)
    if blending and state then
        local previous
        for _,candidate in ipairs(cameraShots) do if candidate.time<shot.time and math.abs(candidate.time+candidate.duration-shot.time)<.001 then previous=candidate end end
        if previous then
            local before=DirectorMotion.sample(previous.frames,previous.time+previous.duration,previous.ease) or previous.rig.anchor
            before=sampleRig(previous.rig,before,previous.duration)
            if before then state=DirectorShots.blend(before,state,(time-shot.time)/shot.blend) end
        end
    end
    if state and rig.avoidObstacles and rig.mode~='manual' then
        local handle=sceneEntities[rig.targetId]
        if handle and DoesEntityExist(handle) then
            local p=GetEntityCoords(handle)
            state=DirectorObstacles.camera(rig,{x=p.x,y=p.y,z=p.z+(rig.targetHeight or 0)},state,handle,GetGameTimer(),time)
        end
    end
    applyState(state)
end

local function loadCameraRig(value)
    cameraRig = type(value) == 'table' and value or { mode = 'manual' }
    if cameraRig.mode ~= 'manual' and not sceneEntities[cameraRig.targetId] then cameraRig = { mode = 'manual' } end
    applyCameraRig(playhead, stateAtTime(playhead) or cameraRig.anchor)
end

sceneClear = function()
    if outlinedHandle then selectionOutline(outlinedHandle,false) end
    if stopShotPreview then stopShotPreview() end
    DirectorPedCues.resetGround()
    sceneGeneration = sceneGeneration + 1
    lastActorPacket = nil
    if stopAnimationPreview then stopAnimationPreview(false) end
    dragSession = nil
    selectedActorId = nil
    for _, handle in pairs(sceneEntities) do
        if DoesEntityExist(handle) then DeleteEntity(handle) end
    end
    sceneEntities = {}
    for _,gesture in pairs(DirectorRecording.gestures) do RemoveAnimDict(gesture.dict) end
end

local function sceneModel(model, token)
    if type(model) ~= 'string' or not model:match('^[%w_]+$') or #model > 48 then return nil end
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (Config.ModelLoadTimeoutMs or 5000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline and directorOpen and token == sceneGeneration do Wait(25) end
    if not directorOpen or token ~= sceneGeneration or not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);return nil end
    return hash
end

local function scenePlace()
    local state = getCameraState()
    if not state then return nil end
    local pitch, yaw = math.rad(state.rx), math.rad(state.rz)
    local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local origin = vector3(state.x, state.y, state.z)
    local target = origin + direction * (Config.PlacementDistance or 150.0)
    local ray = StartShapeTestRay((origin.x) + 0.0, (origin.y) + 0.0, (origin.z) + 0.0, (target.x) + 0.0, (target.y) + 0.0, (target.z) + 0.0, 1 + 16, PlayerPedId(), 7)
    local pending, hit, point = GetShapeTestResult(ray)
    local deadline = GetGameTimer() + 1000
    while pending == 1 and GetGameTimer() < deadline do
        Wait(0)
        pending, hit, point = GetShapeTestResult(ray)
    end
    if pending == 1 then return nil end
    if hit == 1 then return point.x, point.y, point.z, true end
    return target.x, target.y, target.z
end

local function sceneSpawn(actor)
    -- Runtime probes/tasks belong to this entity handle, never to a saved actor.
    actor._recordTaskAt=nil;actor._recordCue=nil;actor._cueRequested=nil
    actor._aimWeapon=nil;actor._aimCue=nil
    actor._attachmentSignature=nil
    actor._ground,actor._groundCollision,actor._lastApplied=nil,nil,nil
    actor._placementGround,actor._placementSignature,actor._groundClearance=nil,nil,nil
    actor._routeTaskAt,actor._playing,actor._contactOffset=nil,nil,nil
    actor._nativeRoute=nil
    actor._seatCue,actor._seatFailed,actor._seatVehicle=nil,nil,nil
    actor._seatAttached,actor._seatDesired,actor._seatCollision,actor._seatExitPosition=nil,nil,nil,nil
    local token = sceneGeneration
    local hash = sceneModel(actor.model, token)
    if not hash then return false, 'Invalid or unavailable model.' end
    if token ~= sceneGeneration or not directorOpen then SetModelAsNoLongerNeeded(hash); return false, 'Scene closed or changed while loading.' end
    local handle
    if actor.kind == 'ped' and IsModelAPed(hash) then
        handle = CreatePed(4, hash, (actor.x) + 0.0, (actor.y) + 0.0, (actor.z) + 0.0, (actor.heading) + 0.0, false, false)
        if handle and handle ~= 0 then SetBlockingOfNonTemporaryEvents(handle, true) end
    elseif actor.kind == 'vehicle' and IsModelAVehicle(hash) then
        handle = CreateVehicle(hash, (actor.x) + 0.0, (actor.y) + 0.0, (actor.z) + 0.0, (actor.heading) + 0.0, false, false)
    elseif actor.kind == 'prop' and not IsModelAPed(hash) and not IsModelAVehicle(hash) then
        handle = CreateObjectNoOffset(hash, (actor.x) + 0.0, (actor.y) + 0.0, (actor.z) + 0.0, false, false, false)
    end
    SetModelAsNoLongerNeeded(hash)
    if not handle or handle == 0 or not DoesEntityExist(handle) then return false, 'Could not spawn this model.' end
    SetEntityAsMissionEntity(handle, true, true)
    SetEntityInvincible(handle, true)
    SetEntityCollision(handle, false, false)
    FreezeEntityPosition(handle, true)
    actor._frozen = true
    sceneEntities[actor.id] = handle
    local appearanceOk,appearance=DirectorAppearance.validate(actor.kind,actor.appearance)
    if appearanceOk then actor.appearance=appearance; DirectorAppearance.apply(actor.kind,handle,appearance) end
    if actor.kind=='ped' then
        -- New peds are frozen and have no movement/animation task here.
        -- Give their skeleton a bounded opportunity to initialize.
        for _=1,4 do
            if DirectorPedCues.calibrateFeet(actor,handle)~=nil then break end
            Wait(0)
            if token~=sceneGeneration or not directorOpen or not DoesEntityExist(handle) then return false,'Scene changed while calibrating ped feet.' end
        end
    end
    return true
end

-- Clicks hit the ground; ped coordinates describe the root above its feet.
local function routeRootOffset(actor)
    if actor.kind ~= 'ped' then
        local found,z=GetGroundZFor_3dCoord((actor.x) + 0.0,(actor.y) + 0.0,(actor.z+1.5) + 0.0,false)
        if found and type(z)=='number' and z==z and math.abs(actor.z-z)<4 then return actor.z-z end
        local minimum=GetModelDimensions(GetHashKey(actor.model))
        return -minimum.z
    end
    if actor._routeRootOffset == nil then
        local minimum = GetModelDimensions(GetHashKey(actor.model))
        actor._routeRootOffset = minimum and clamp(-minimum.z, .1, 1.5) or 1.0
    end
    return actor._routeRootOffset
end
local function normalizeRoute(actor, action)
    if not action.points or action.coordinateSpace == 'entity' then return end
    local offset = routeRootOffset(actor)
    for _, point in ipairs(action.points) do point.z = point.z + offset end
    local last = action.points[#action.points]
    if last then action.x, action.y, action.z = last.x, last.y, last.z end
    action.coordinateSpace = 'entity'
    action._route, action._routeStart = nil, nil
end

local function sampleMove(action, start, progress)
    local eased = progress*progress*(3-2*progress)
    if action.points then
        local signature = ('%.5f:%.5f:%.5f'):format(start.x,start.y,start.z)
        if not action._route or action._routeStart ~= signature then
            action._route=DirectorRoutes.compile(start,action.points); action._routeStart=signature
        end
        local point, heading=DirectorRoutes.sample(action._route,progress)
        return point,heading,action._route.length*progress
    end
    local dx,dy,dz=action.x-start.x,action.y-start.y,action.z-start.z
    return {x=start.x+dx*eased,y=start.y+dy*eased,z=start.z+dz*eased},(dx*dx+dy*dy>.01 and (math.deg(math.atan(-dx,dy))+360)%360 or nil),math.sqrt(dx*dx+dy*dy+dz*dz)*eased
end

sceneApply = function(time, forceSync)
    local now=GetGameTimer()
    DirectorPedCues.groundFrame(now)
    for _, actor in ipairs(sceneActors) do
        local handle = sceneEntities[actor.id]
        if handle and DoesEntityExist(handle) then
            local recorded=actor.actions and actor.actions[1]
            if recorded and recorded.type=='recording' then
                DirectorRecording.apply(actor,handle,recorded,time,previewing,forceSync)
                goto nextActor
            end
            local x, y, z, heading = actor.x, actor.y, actor.z, actor.heading
            local fromX, fromY, fromZ = actor.x, actor.y, actor.z
            local fromHeading = actor.heading
            local wheelTravel = 0.0
            local moveAction, animationAction, finishedExit
            local visible = not actor.attachment or actor.attachment.visible
            for _, step in ipairs(actor.actions or {}) do
                if step.type == 'move' then normalizeRoute(actor, step) end
                if step.type == 'move' and step.time <= time then
                    if moveAction then
                        local previous = clamp((step.time-moveAction.time)/math.max(moveAction.duration,.1),0,1)
                        local point, targetHeading, travelled=sampleMove(moveAction,{x=fromX,y=fromY,z=fromZ},previous)
                        fromHeading=(fromHeading+wrapAngle((targetHeading or fromHeading)-fromHeading)*clamp(previous/.2,0,1))%360
                        wheelTravel=wheelTravel+travelled
                        fromX,fromY,fromZ=point.x,point.y,point.z
                    end
                    moveAction = step
                elseif step.type=='exitVehicle' and step.time+step.duration<=time then
                    finishedExit=step
                    local p=previewing and not forceSync and actor._seatExitPosition and actor._seatExitPosition.id==step.id and actor._seatExitPosition or step
                    fromX,fromY,fromZ=p.x,p.y,p.z;x,y,z=p.x,p.y,p.z;moveAction=nil
                elseif step.type == 'animation' and step.time <= time then
                    animationAction = (not step.duration or time<step.time+step.duration) and step or nil
                elseif step.type == 'visibility' and step.time <= time then
                    visible = step.visible
                end
            end
            local vehicleState=actor.kind=='ped' and DirectorSeats.state(actor.actions,time)
            actor._seatDesired=vehicleState
            if vehicleState then
                if vehicleState.phase=='entering' then
                    local p={x=fromX,y=fromY,z=fromZ}
                    if moveAction then p=sampleMove(moveAction,p,clamp((vehicleState.action.time-moveAction.time)/moveAction.duration,0,1)) end
                    actor._seatEntryPosition=p
                end
                goto nextActor
            end
            if actor._seatCue or actor._seatAttached then
                if IsPedInAnyVehicle(handle,false) and actor._seatVehicle and DoesEntityExist(actor._seatVehicle) then TaskLeaveVehicle(handle,actor._seatVehicle,16) end
                ClearPedTasksImmediately(handle);actor._playing=nil;actor._seatCue=nil;actor._seatAttached=nil;actor._lastApplied=nil
                SetEntityCollision(handle,false,false)
            end
            local moving = moveAction and time < moveAction.time + moveAction.duration
            local progress = 0.0
            if moveAction then
                progress = clamp((time - moveAction.time) / math.max(moveAction.duration, 0.1), 0.0, 1.0)
                local point,targetHeading=sampleMove(moveAction,{x=fromX,y=fromY,z=fromZ},progress)
                x,y,z=point.x,point.y,point.z
                heading=(fromHeading+wrapAngle((targetHeading or fromHeading)-fromHeading)*clamp(progress/.2,0,1))%360
            end
            if actor.kind == 'ped' then
                if (moveAction and moveAction.points) or finishedExit then
                    if actor._contactOffset==nil and actor._frozen and not actor._playing then
                        DirectorPedCues.calibrateFeet(actor,handle)
                    end
                    z=DirectorPedCues.groundHeight(actor,handle,x,y,z,routeRootOffset(actor),now,forceSync)
                    if moving and moveAction then heading=select(2,sampleMove(moveAction,{x=fromX,y=fromY,z=fromZ},progress)) or heading end
                end
                if animationAction and animationAction.loop==false and HasAnimDictLoaded(animationAction.dict) then
                    local length=GetAnimDuration(animationAction.dict,animationAction.clip)
                    if length>0 and time>=animationAction.time+length then animationAction=nil end
                end
                if not animationAction then actor._animRequested, actor._animWarning = nil, nil end
                if animationAction and (not moving or animationAction.time >= moveAction.time) then
                    if actor._playing ~= animationAction.id or forceSync then
                        if actor._animRequested ~= animationAction.id then
                            RequestAnimDict(animationAction.dict)
                            actor._animRequested = animationAction.id
                            actor._animWarning = nil
                            local requestId, dict, token = animationAction.id, animationAction.dict, sceneGeneration
                            CreateThread(function()
                                local deadline = GetGameTimer() + (Config.ModelLoadTimeoutMs or 5000)
                                while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline and directorOpen and
                                    sceneGeneration == token and actor._animRequested == requestId do Wait(10) end
                                if not directorOpen or sceneGeneration ~= token or actor._animRequested ~= requestId or
                                    not DoesEntityExist(handle) then return end
                                if HasAnimDictLoaded(dict) then
                                    if not previewing then sceneApply(playhead, true) end
                                else
                                    actor._animWarning = true
                                    SendNUIMessage({action='status',message='An animation could not load. Check its dictionary and clip.'})
                                end
                            end)
                        end
                        if HasAnimDictLoaded(animationAction.dict) then
                            DirectorPedCues.stopRoute(actor,handle)
                            ClearPedTasksImmediately(handle)
                            actor._lookPlaying = nil
                            if not actor._frozen then FreezeEntityPosition(handle, true); actor._frozen = true end
                            TaskPlayAnim(handle, animationAction.dict, animationAction.clip, 8.0, -8.0, -1, animationAction.loop==false and 0 or 1, 0.0, false, false, false)
                            local animationLength = GetAnimDuration(animationAction.dict, animationAction.clip)
                            local phase = animationLength > 0.0 and (animationAction.loop==false and clamp((time-animationAction.time)/animationLength,0.0,.999) or ((time-animationAction.time)%animationLength)/animationLength) or 0.0
                            SetEntityAnimCurrentTime(handle, animationAction.dict, animationAction.clip, (phase) + 0.0)
                            actor._playing = animationAction.id
                        end
                    end
                elseif moving and previewing and not forceSync then
                    local starting=actor._playing~=moveAction.id
                    if starting then
                        ClearPedTasksImmediately(handle);actor._lookPlaying=nil
                        SetEntityCoordsNoOffset(handle,x+0.0,y+0.0,z+0.0,true,true,true)
                        SetEntityHeading(handle,heading+0.0)
                        if actor._frozen then FreezeEntityPosition(handle,false);actor._frozen=false end
                    end
                    if moveAction.points then
                        if not actor._groundCollision then SetEntityCollision(handle,true,true);actor._groundCollision=true end
                        moveAction._rootOffset=routeRootOffset(actor)
                        DirectorPedCues.playRoute(actor,handle,moveAction,progress,{x=x,y=y,z=z},now,starting)
                        actor._playing=moveAction.id
                    elseif starting then
                        local remaining=math.max(.1,moveAction.time+moveAction.duration-time)
                        local distance=math.sqrt((moveAction.x-x)^2+(moveAction.y-y)^2+(moveAction.z-z)^2)
                        TaskGoStraightToCoord(handle,moveAction.x+0.0,moveAction.y+0.0,moveAction.z+0.0,
                            DirectorPedCues.speed(moveAction,distance,remaining)+0.0,-1,heading+0.0,0.0)
                        actor._playing=moveAction.id
                    end
                    -- Native tasks control position, heading and floor contact.
                    -- Explicit pause/seek still restores the exact timeline pose.
                    goto nextActor
                end
                if (not animationAction or (moving and animationAction.time < moveAction.time)) and not (moving and previewing and moveAction.points and not forceSync) then
                    DirectorPedCues.stopRoute(actor,handle)
                    if actor._playing then ClearPedTasksImmediately(handle); actor._lookPlaying = nil end
                    actor._playing = nil
                    if not actor._frozen then FreezeEntityPosition(handle, true); actor._frozen = true end
                end
            elseif actor.kind == 'vehicle' then
                local travelled=0
                if moveAction then local _,_,distance=sampleMove(moveAction,{x=fromX,y=fromY,z=fromZ},progress); travelled=distance end
                local travel=wheelTravel+travelled
                if forceSync or actor._lastWheelTravel ~= travel or actor._wheelPreview ~= previewing then
                    actor._wheelPreview=previewing
                    for wheel = 0, GetVehicleNumberOfWheels(handle) - 1 do
                        -- Never write travelled distance into the wheel transform (camber).
                        local wheelSpeed=0.0
                        if moving and previewing and not forceSync and moveAction then
                            if moveAction._route then wheelSpeed=moveAction._route.length/math.max(moveAction.duration,.1)
                            else
                                local length=math.sqrt((moveAction.x-fromX)^2+(moveAction.y-fromY)^2+(moveAction.z-fromZ)^2)
                                wheelSpeed=length*6*progress*(1-progress)/math.max(moveAction.duration,.1)
                            end
                        end
                        SetVehicleWheelRotationSpeed(handle, wheel, wheelSpeed + 0.0)
                    end
                    actor._lastWheelTravel = travel
                end
                local steering=0.0
                if moving and moveAction and moveAction._route then
                    local route=moveAction._route
                    local _,nextHeading=DirectorRoutes.sample(route,math.min(1,progress+1/math.max(route.length,1)))
                    steering=clamp(wrapAngle((nextHeading or heading)-heading),-30.0,30.0)
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
                        if open then SetVehicleDoorOpen(handle, door, false, forceSync)
                        else SetVehicleDoorShut(handle, door, forceSync) end
                        actor._doors[door + 1] = open
                    end
                end
            end
            if actor.attachment and not sceneEntities[actor.attachment.parentId] then visible=false end
            if actor.kind == 'prop' and actor._visible ~= visible then
                SetEntityVisible(handle, visible, false)
                selectionOutline(handle, visible and selectedActorId == actor.id)
                actor._visible = visible
            end
            if not actor.attachment then
                local last = actor._lastApplied
                local groundedRoute=actor.kind=='ped' and ((moveAction and moveAction.points) or finishedExit)
                if actor._groundCollision and not (groundedRoute and moving and previewing and not forceSync) then
                    SetEntityCollision(handle,false,false);actor._groundCollision=nil
                end
                -- Native locomotion/physics may move the ped between frames. The
                -- absolute route pose wins, even when the sampled pose is unchanged.
                if groundedRoute then
                    local position=GetEntityCoords(handle)
                    last={x=position.x,y=position.y,z=position.z,heading=GetEntityHeading(handle)}
                end
                local locomotion=groundedRoute and moving and previewing and not forceSync
                local tolerance=locomotion and .35 or .0005
                if forceSync or not last or math.abs(x - last.x) > tolerance or math.abs(y - last.y) > tolerance or math.abs(z - last.z) > (locomotion and .15 or .0005) then
                    SetEntityCoordsNoOffset(handle, (x) + 0.0, (y) + 0.0, (z) + 0.0, true, true, groundedRoute and true or false)
                end
                if forceSync or not last or math.abs(wrapAngle(heading - (last.heading or GetEntityHeading(handle)))) > 0.02 then
                    SetEntityHeading(handle, (heading) + 0.0)
                end
                actor._lastApplied = { x = x, y = y, z = z, heading = heading }
            end
            ::nextActor::
        end
    end
    -- Vehicle poses are now current, regardless of actor list order.
    local vehicles={};local used={}
    for _,a in ipairs(sceneActors) do if a.kind=='vehicle' then vehicles[a.id]=a end end
    for _,a in ipairs(sceneActors) do
        local state=a._seatDesired
        local target=state and vehicles[state.action.vehicleId]
        local ped=sceneEntities[a.id];local car=target and sceneEntities[target.id]
        if state and ped and car and DoesEntityExist(ped) and DoesEntityExist(car) then
            used[target.id]=true
            if not target._seatCollision then SetEntityCollision(car,true,true);target._seatCollision=true end
            DirectorPedCues.vehicleCue(a,ped,car,state,previewing,forceSync)
        end
    end
    for id,a in pairs(vehicles) do if a._seatCollision and not used[id] then
        local h=sceneEntities[id];if h and DoesEntityExist(h) then SetEntityCollision(h,false,false) end;a._seatCollision=nil
    end end
    for _,a in ipairs(sceneActors) do
        local h=sceneEntities[a.id]
        if a.attachment and h and DoesEntityExist(h) then DirectorAttachments.apply(a,h,sceneEntities[a.attachment.parentId]) end
    end
    -- Apply gaze after all transforms, so moving subjects are already up to date.
    for _, actor in ipairs(sceneActors) do
        local handle = sceneEntities[actor.id]
        if actor.kind == 'ped' and handle and DoesEntityExist(handle) then
            local cue = DirectorPedCues.lookAt(actor.actions, time)
            local target = cue and cue.targetId and sceneEntities[cue.targetId]
            if cue and cue.targetId and (not target or not DoesEntityExist(target)) then cue = nil end
            if cue then
                if forceSync or actor._lookPlaying ~= cue.id or actor._lookPreview ~= previewing then
                    local milliseconds = previewing and math.max(1, math.ceil((cue.time + cue.duration - time) * 1000)) or -1
                    if target then TaskLookAtEntity(handle, target, milliseconds, 2048, 3)
                    else TaskLookAtCoord(handle, (cue.x) + 0.0, (cue.y) + 0.0, (cue.z) + 0.0, milliseconds, 2048, 3) end
                    actor._lookPlaying, actor._lookPreview = cue.id, previewing
                end
            elseif actor._lookPlaying or forceSync then
                TaskClearLookAt(handle)
                actor._lookPlaying, actor._lookPreview = nil, nil
            end
        end
    end
end

stopAnimationPreview = function(restore)
    animationPreviewToken = animationPreviewToken + 1
    local id = animationPreviewActor
    animationPreviewActor = nil
    if not id then return end
    local handle = sceneEntities[id]
    if handle and DoesEntityExist(handle) then ClearPedTasksImmediately(handle) end
    for _, actor in ipairs(sceneActors) do
        if actor.id == id then actor._playing = nil break end
    end
    SendNUIMessage({ action = 'animationPreviewStopped' })
    if restore and directorOpen and sceneApply then sceneApply(playhead, true) end
end

sceneSend = function()
    SendNUIMessage({ action = 'actors', actors = publicActors() })
end

sceneLoad = function(actors, preserveIds, reuse)
    preserveIds = preserveIds ~= false
    sceneGeneration = sceneGeneration + 1
    cameraRig = { mode = 'manual' }
    local retained={}
    if reuse then
        for _,old in ipairs(sceneActors) do
            local handle=sceneEntities[old.id]
            for _,incoming in ipairs(actors or {}) do
                if incoming.id==old.id and not old._missing and handle and DoesEntityExist(handle) and DirectorHistory.same(old,incoming) then retained[old.id]=old;break end
            end
        end
        if outlinedHandle then selectionOutline(outlinedHandle,false) end
        if stopShotPreview then stopShotPreview() end
        if stopAnimationPreview then stopAnimationPreview(false) end
        DirectorPedCues.resetGround();sceneGeneration=sceneGeneration+1;lastActorPacket=nil;dragSession=nil;selectedActorId=nil
        for id,handle in pairs(sceneEntities) do if not retained[id] then if DoesEntityExist(handle) then DeleteEntity(handle) end;sceneEntities[id]=nil end end
    else sceneClear() end
    sceneActors = {}
    nextActorId = 1
    nextActionId = 1
    local token = sceneGeneration
    for _, actor in ipairs(actors or {}) do
        if token ~= sceneGeneration or not directorOpen then return false end
        if #sceneActors >= Config.MaximumActors then break end
        if type(actor) == 'table' and (actor.kind == 'ped' or actor.kind == 'vehicle' or actor.kind == 'prop') and type(actor.model) == 'string' then
            actor.actions = type(actor.actions) == 'table' and actor.actions or {}
            for _, action in ipairs(actor.actions) do
                action.id = preserveIds and action.id or nextActionId
                nextActionId = math.max(nextActionId, action.id + 1)
            end
            table.sort(actor.actions, function(a, b)
                if a.time == b.time then return a.id < b.id end
                return a.time < b.time
            end)
            actor.id = preserveIds and actor.id or nextActorId
            nextActorId = math.max(nextActorId, actor.id + 1)
            local old=retained[actor.id]
            if old then actor=old;actor._attachmentSignature=nil end
            local spawned,reason
            if old then spawned=true else spawned,reason=sceneSpawn(actor) end
            actor._missing = not spawned or nil
            sceneActors[#sceneActors + 1] = actor
            if not spawned then SendNUIMessage({action='status',message='Model unavailable: '..actor.model..'. Its project data has been preserved. '..tostring(reason or '')}) end
            if token ~= sceneGeneration or not directorOpen then return false end
        end
    end
    sceneApply(playhead)
    sceneSend()
    return true
end

-- Only new surface placements are grounded. Saved coordinates are root positions
-- and must never receive another model offset when loading or undoing a scene.
local function placementRoot(actor,x,y,z,surface)
    local handle=sceneEntities[actor.id]
    local minimum=GetModelDimensions(GetHashKey(actor.model))
    local support=actor.kind=='ped' and DirectorPedCues.contactOffset(actor,1.0) or -minimum.z
    if surface then
        SetEntityCoordsNoOffset(handle,(x) + 0.0,(y) + 0.0,(z+support) + 0.0,false,false,true)
        if actor.kind=='vehicle' then SetVehicleOnGroundProperly(handle)
        elseif actor.kind=='prop' then PlaceObjectOnGroundProperly(handle) end
    end
    local root=GetEntityCoords(handle)
    actor.x,actor.y,actor.z=root.x,root.y,root.z
    actor._lastApplied=nil
end

sceneAdd = function(kind, model)
    if kind ~= 'ped' and kind ~= 'vehicle' and kind ~= 'prop' then return false, 'Choose a ped, vehicle or prop.' end
    if #sceneActors >= Config.MaximumActors then return false, 'Actor limit reached.' end
    local x, y, z, surface = scenePlace()
    if not x then return false, 'Camera is not ready.' end
    local heading = getCameraState().rz
    local actor = { id = nextActorId, kind = kind, model = model, x = x, y = y, z = z, heading = heading, actions = {} }
    local ok, errorMessage = sceneSpawn(actor)
    if not ok then return false, errorMessage end
    placementRoot(actor,x,y,z,surface)
    sceneActors[#sceneActors + 1] = actor
    nextActorId = nextActorId + 1
    sceneSend()
    return true
end

sceneDelete = function(id)
    for index, actor in ipairs(sceneActors) do
        if actor.id == id then
            if selectedActorId == id then selectedActorId = nil; dragSession = nil end
            local handle = sceneEntities[id]
            if actor._placementGround then actor._placementGround.cancelled=true end
            if actor._ground then actor._ground.cancelled=true end
            if handle and DoesEntityExist(handle) then DeleteEntity(handle) end
            if outlinedHandle==handle then outlinedHandle=nil end
            sceneEntities[id] = nil
            local removed={[id]=true}
            table.remove(sceneActors, index)
            for childIndex=#sceneActors,1,-1 do
                local child=sceneActors[childIndex]
                if child.attachment and child.attachment.parentId==id then
                    local object=sceneEntities[child.id];if object and DoesEntityExist(object) then DeleteEntity(object) end
                    removed[child.id]=true;sceneEntities[child.id]=nil;table.remove(sceneActors,childIndex)
                    if selectedActorId==child.id then selectedActorId=nil end
                end
            end
            for _, other in ipairs(sceneActors) do
                for actionIndex = #other.actions, 1, -1 do
                    local action = other.actions[actionIndex]
                    if (action.type == 'lookAt' and removed[action.targetId]) or removed[action.vehicleId] then table.remove(other.actions, actionIndex) end
                end
            end
            sceneApply(playhead, true)
            if removed[sceneLook.focusId] then sceneLook.focusId=nil end
            for _,shot in ipairs(cameraShots) do
                if removed[shot.rig.targetId] then
                    local anchor=shot.rig.anchor
                    shot.rig={mode='manual'}
                    if #shot.frames==0 and anchor then local frame=DirectorShots.copy(anchor);frame.time=shot.time;shot.frames={frame} end
                end
            end
            if removed[cameraRig.targetId] then
                cameraRig = { mode = 'manual' }
                sendProject()
            end
            sceneSend()
            return true
        end
    end
    return false
end

local function finiteNumber(value, limit)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) > limit then return nil end
    return number
end

local function sceneSetTransform(id, data)
    local x = finiteNumber(data.x, 100000.0)
    local y = finiteNumber(data.y, 100000.0)
    local z = finiteNumber(data.z, 100000.0)
    local heading = finiteNumber(data.heading, 360000.0)
    local surface
    if data.aim == true then
        x, y, z, surface = scenePlace()
    end
    if not x or not y or not z or not heading then return false, 'Invalid coordinates.' end
    for _, actor in ipairs(sceneActors) do
        if actor.id == id then
            if actor.actions[1] and actor.actions[1].type=='recording' then return false,'Recorded positions are fixed. Move the clip in the timeline instead.' end
            if actor.attachment then return false,'Use the accessory position controls.' end
            actor.x, actor.y, actor.z = x, y, z
            if data.aim==true then
                SetEntityCoordsNoOffset(sceneEntities[id],(x) + 0.0,(y) + 0.0,(z) + 0.0,false,false,true)
                placementRoot(actor,x,y,z,surface)
            end
            actor.heading = heading % 360.0
            sceneApply(playhead)
            sceneSend()
            return true
        end
    end
    return false, 'Actor not found.'
end

local function sceneDragBegin(data)
    if not directorOpen or not camera or not DoesCamExist(camera) then return nil end
    local screenX = finiteNumber(data.x, 1.0)
    local screenY = finiteNumber(data.y, 1.0)
    local aspect = finiteNumber(data.aspect, 4.0)
    if not screenX or not screenY or not aspect or screenX < 0 or screenY < 0 or aspect < 0.5 then return nil end
    local cameraState = getCameraState()
    local chosen, bestDistance = nil, math.huge
    local requestedId = tonumber(data.id)
    if requestedId then
        for _, actor in ipairs(sceneActors) do
            if actor.id == requestedId and sceneEntities[actor.id] and DoesEntityExist(sceneEntities[actor.id]) then
                chosen = actor
                break
            end
        end
    end
    if not chosen then for _, actor in ipairs(sceneActors) do
        local handle = sceneEntities[actor.id]
        if handle and DoesEntityExist(handle) and actor._visible ~= false then
            local position = GetEntityCoords(handle)
            for _, height in ipairs({ 0.35, 0.9, 1.45 }) do
                local px, py = DirectorGeometry.project(cameraState, aspect, {
                    x = position.x, y = position.y, z = position.z + height
                })
                if px and py then
                    local dx, dy = (px - screenX) * aspect, py - screenY
                    local distance = dx * dx + dy * dy
                    local radius = actor.kind == 'vehicle' and 0.12 or actor.kind == 'prop' and 0.08 or 0.065
                    if distance < radius * radius and distance < bestDistance then
                        chosen, bestDistance = actor, distance
                    end
                end
            end
        end
    end end
    if not chosen or chosen.attachment or (chosen.actions[1] and chosen.actions[1].type=='recording') then return nil end

    if selectedActorId and sceneEntities[selectedActorId] and DoesEntityExist(sceneEntities[selectedActorId]) then
        selectionOutline(sceneEntities[selectedActorId], false)
    end
    selectedActorId = chosen.id
    selectionOutline(sceneEntities[chosen.id], true)
    previewing = false
    pressedKeys = {}
    resetMotion()
    local current = GetEntityCoords(sceneEntities[chosen.id])
    local _, _, depth = DirectorGeometry.project(cameraState, aspect, {
        x = current.x, y = current.y, z = current.z + 0.9
    })
    local targets = {}
    for _, action in ipairs(chosen.actions) do
        if action.type == 'move' then
            targets[action.id] = { x = action.x, y = action.y, z = action.z, points=DirectorHistory.copy(action.points) }
        end
    end
    dragSession = {
        actor = chosen, camera = cameraState, aspect = aspect,
        startX = screenX, startY = screenY, depth = depth or 5.0,
        base = { x = chosen.x, y = chosen.y, z = chosen.z },
        heading = chosen.heading,
        mode = data.mode == 'rotate' and 'rotate' or 'move',
        target = { x = chosen.x, y = chosen.y, z = chosen.z, heading = chosen.heading },
        targets = targets
    }
    local minimum=GetModelDimensions(GetHashKey(chosen.model))
    local support=chosen.kind=='ped' and DirectorPedCues.contactOffset(chosen,routeRootOffset(chosen)) or -minimum.z
    dragSession.ground=DirectorDragGround.begin(sceneEntities[chosen.id],dragSession.base,support)
    lastDragSequence = -1
    return chosen.id
end

local function sceneDragMove(data)
    if not dragSession or not directorOpen then return false end
    local screenX = finiteNumber(data.x, 1.0)
    local screenY = finiteNumber(data.y, 1.0)
    local sequence = tonumber(data.sequence)
    if not screenX or not screenY or screenX < 0 or screenY < 0 or not sequence or sequence <= lastDragSequence then return false end
    lastDragSequence = sequence
    local session = dragSession
    if session.mode == 'rotate' then
        session.target.heading = (session.heading + (screenX - session.startX) * 360.0) % 360.0
    else
        local offset = DirectorGeometry.dragDelta(session.camera, session.aspect,
            session.startX, session.startY, screenX, screenY, session.base.z, session.depth, data.heightOnly == true)
        if math.abs(offset.x) > 1000 or math.abs(offset.y) > 1000 or math.abs(offset.z) > 1000 then return false end
        session.target.x = session.base.x + offset.x
        session.target.y = session.base.y + offset.y
        session.target.z = session.base.z + offset.z
        session.heightOnly=data.heightOnly==true
    end
    return true
end

local function sceneDragUpdate(deltaSeconds)
    local session = dragSession
    if not session then return end
    local actor = session.actor
    local response = math.max(0.005, Config.ActorDragResponse)
    local amount = 1.0 - math.exp(-deltaSeconds / response)
    actor.x = lerp(actor.x, session.target.x, amount)
    actor.y = lerp(actor.y, session.target.y, amount)
    local targetZ=session.target.z
    local groundedZ
    if session.mode=='move' and not session.heightOnly then
        groundedZ=DirectorDragGround.height(session.ground,actor.x,actor.y,GetGameTimer())
    end
    -- XY is already eased. Easing Z a second time makes wheels lag below ramps.
    actor.z = groundedZ or lerp(actor.z, targetZ, amount)
    actor.heading = (actor.heading + wrapAngle(session.target.heading - actor.heading) * amount) % 360.0
    local offsetX, offsetY, offsetZ = actor.x - session.base.x, actor.y - session.base.y, actor.z - session.base.z
    local previous=session.appliedOffset
    if not previous or math.abs(previous.x-offsetX)+math.abs(previous.y-offsetY)+math.abs(previous.z-offsetZ)>.000001 then
        session.appliedOffset=previous or {}
        session.appliedOffset.x,session.appliedOffset.y,session.appliedOffset.z=offsetX,offsetY,offsetZ
        for _, action in ipairs(actor.actions) do
            local original = session.targets[action.id]
            if original then
                action.x, action.y, action.z = original.x + offsetX, original.y + offsetY, original.z + offsetZ
                if original.points then
                    for index,point in ipairs(original.points) do
                        local target=action.points[index]
                        target.x,target.y,target.z=point.x+offsetX,point.y+offsetY,point.z+offsetZ
                    end
                    action._route=nil
                end
            end
        end
    end
    sceneApply(playhead)
end

local function sceneDragEnd()
    if not dragSession then return false end
    sceneDragUpdate(1.0)
    dragSession = nil
    sceneSend()
    return true
end

local function sceneSendScreenPositions()
    if #sceneActors == 0 then
        if lastActorPacket ~= 'empty' then
            lastActorPacket = 'empty'
            SendNUIMessage({action='actorScreen',positions={},selectedId=selectedActorId})
        end
        return
    end
    local cameraState = getCameraState()
    if not cameraState then return end
    local width, height = GetActiveScreenResolution()
    local aspect = width > 0 and height > 0 and width / height or 16 / 9
    local positions = {}
    for _, actor in ipairs(sceneActors) do
        local handle = sceneEntities[actor.id]
        if handle and DoesEntityExist(handle) and actor._visible ~= false then
            local position = GetEntityCoords(handle)
            local x, y = DirectorGeometry.project(cameraState, aspect, {
                x = position.x, y = position.y, z = position.z + 0.9
            })
            if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                positions[#positions + 1] = { id = actor.id, x = x, y = y, kind = actor.kind }
            end
        end
    end
    local parts = { tostring(selectedActorId) }
    for _, position in ipairs(positions) do parts[#parts+1] = ('%s:%s:%.4f:%.4f'):format(position.id,position.kind,position.x,position.y) end
    local signature = table.concat(parts,'|')
    if signature ~= lastActorPacket then
        lastActorPacket = signature
        SendNUIMessage({ action = 'actorScreen', positions = positions, selectedId = selectedActorId })
    end
end

sceneAddAction = function(id, actionType, data)
    for _, actor in ipairs(sceneActors) do
        if actor.id == id then
            if #actor.actions >= Config.MaximumActionsPerActor then return false, 'Action limit reached.' end
            if actor.actions[1] and actor.actions[1].type=='recording' then return false,'Recorded takes use a dedicated movement track.' end
            if actor.attachment and actionType~='visibility' then return false,'Attached accessories only support wear/remove cues.' end
            local action = { id = nextActionId, time = math.floor(playhead * 10 + 0.5) / 10, type = actionType }
            if actionType == 'move' then
                if action.time >= duration - 0.1 then return false, 'Move the playhead earlier to add movement.' end
                action.x, action.y, action.z = scenePlace()
                if not action.x then return false, 'Camera is not ready.' end
                if actor.kind~='ped' then action.z=action.z+routeRootOffset(actor) end
                local seconds = finiteNumber(data.duration or 3.0, Config.MaximumDuration)
                if not seconds or seconds <= 0 then return false, 'Enter a valid movement duration.' end
                action.duration = math.max(0.1, math.min(seconds, duration - action.time))
                if actor.kind == 'ped' then
                    action.gait = tostring(data.gait or 'auto')
                    if action.gait ~= 'auto' and not DirectorPedCues.gaits[action.gait] then return false, 'Choose a valid movement style.' end
                    if data.autoDuration == true and DirectorPedCues.gaits[action.gait] then
                        local position = GetEntityCoords(sceneEntities[id])
                        local distance = math.sqrt((action.x-position.x)^2 + (action.y-position.y)^2 + (action.z-position.z)^2)
                        local seconds = math.max(0.1, distance / DirectorPedCues.gaits[action.gait])
                        if seconds > duration-action.time then return false, 'Extend the timeline or choose a closer destination.' end
                        action.duration = math.ceil(seconds * 10) / 10
                        action.duration = math.min(action.duration, duration-action.time)
                    end
                end
            elseif (actionType=='enterVehicle' or actionType=='exitVehicle') and actor.kind=='ped' then
                local target
                for _,item in ipairs(sceneActors) do if item.id==tonumber(data.vehicleId) and item.kind=='vehicle' then target=item end end
                local seat=tonumber(data.seat);local seconds=finiteNumber(data.duration or 5,30)
                if not target or not seat or seat%1~=0 or seat< -1 or seat>=GetVehicleModelNumberOfSeats(GetHashKey(target.model))-1 then return false,'Choose a valid vehicle and seat.' end
                if not seconds or seconds<.1 or action.time+seconds>duration+.001 then return false,'Extend the timeline or shorten the interaction.' end
                action.vehicleId,action.seat,action.duration=target.id,seat,seconds
                if actionType=='exitVehicle' then
                    local p={x=target.x,y=target.y,z=target.z};local heading=target.heading
                    local endTime=action.time+action.duration
                    for _,step in ipairs(target.actions) do if step.type=='move' and step.time<=endTime then
                        local point,rotation=sampleMove(step,p,clamp((endTime-step.time)/step.duration,0,1));p=point;heading=rotation or heading
                    end end
                    local minimum,maximum=GetModelDimensions(GetHashKey(target.model))
                    local side=math.max(.8,(maximum.x-minimum.x)*.5+.6)*((seat==-1 or seat%2==1) and -1 or 1)
                    local angle=math.rad(heading)
                    action.x,action.y,action.z=p.x+math.cos(angle)*side,p.y+math.sin(angle)*side,p.z+routeRootOffset(actor)
                end
            elseif actionType == 'lookAt' and actor.kind == 'ped' then
                if action.time >= duration - 0.1 then return false, 'Move the playhead earlier to add a gaze.' end
                local seconds = finiteNumber(data.duration, Config.MaximumDuration)
                if not seconds or seconds <= 0 then return false, 'Enter a valid gaze duration.' end
                action.duration = math.max(0.1, math.min(seconds, duration-action.time))
                local targetId = tonumber(data.targetId)
                if targetId then
                    if targetId == id or not sceneEntities[targetId] then return false, 'Choose another staged subject.' end
                    action.targetId = targetId
                else
                    action.x, action.y, action.z = scenePlace()
                    if not action.x then return false, 'Camera is not ready.' end
                end
            elseif actionType == 'animation' and actor.kind == 'ped' then
                local dict, clip = tostring(data.dict or ''), tostring(data.clip or '')
                if not dict:match('^[%w_@%-]+$') or not clip:match('^[%w_%-]+$') or #dict > 80 or #clip > 80 then return false, 'Invalid animation.' end
                if data.loop~=nil and type(data.loop)~='boolean' then return false,'Invalid animation playback mode.' end
                local handle=sceneEntities[id];local generation=sceneGeneration
                if not handle or not DoesEntityExist(handle) or not DoesAnimDictExist(dict) then return false,'Animation dictionary or ped unavailable.' end
                RequestAnimDict(dict)
                local deadline=GetGameTimer()+2000
                while not HasAnimDictLoaded(dict) and GetGameTimer()<deadline and directorOpen and sceneGeneration==generation do Wait(25) end
                if not directorOpen or sceneGeneration~=generation or sceneEntities[id]~=handle or not DoesEntityExist(handle) then return false,'Animation loading cancelled.' end
                if not HasAnimDictLoaded(dict) then return false,'Animation did not load.' end
                local length=GetAnimDuration(dict,clip)
                if type(length)~='number' or length~=length or length<=0 then return false,'Animation clip unavailable on this game build.' end
                action.dict, action.clip, action.loop = dict, clip, data.loop
                if data.loop==false and data.duration==nil then
                    if action.time>=duration-.01 then return false,'Move the playhead earlier to add this animation.' end
                    action.duration=math.min(length,duration-action.time)
                end
                if data.duration~=nil then
                    local seconds=finiteNumber(data.duration,duration)
                    if not seconds or seconds<=0 or action.time+seconds>duration+.001 then return false,'Animation duration must fit the timeline.' end
                    action.duration=data.loop==false and math.min(seconds,length) or seconds
                end
            elseif actionType == 'visibility' and actor.kind == 'prop' and type(data.visible) == 'boolean' then
                action.visible = data.visible
            elseif (actionType == 'engine' or actionType == 'lights') and actor.kind == 'vehicle' and type(data.enabled) == 'boolean' then
                action.enabled = data.enabled
            elseif actionType == 'door' and actor.kind == 'vehicle' and type(data.enabled) == 'boolean' then
                local door = tonumber(data.door)
                if not door or door % 1 ~= 0 or door < 0 or door > 5 then return false, 'Choose a valid vehicle door.' end
                action.door, action.enabled = door, data.enabled
            else return false, 'Action does not fit this actor.' end
            actor.actions[#actor.actions + 1] = action
            local valid,message=DirectorSeats.validate(sceneActors,duration)
            if not valid then table.remove(actor.actions);return false,message end
            nextActionId = nextActionId + 1
            table.sort(actor.actions, function(a, b)
                if a.time == b.time then return a.id < b.id end
                return a.time < b.time
            end)
            sceneApply(playhead)
            sceneSend()
            return true
        end
    end
    return false, 'Actor not found.'
end

sceneDeleteAction = function(id, index)
    for _, actor in ipairs(sceneActors) do
        if actor.id == id and actor.actions[index] then
            local beforeActions=DirectorHistory.copy(actor.actions)
            local removed=table.remove(actor.actions,index)
            if removed.type=='enterVehicle' then
                for i=1,#actor.actions do local a=actor.actions[i]
                    if a.type=='exitVehicle' and a.vehicleId==removed.vehicleId and a.time>=removed.time then table.remove(actor.actions,i);break end
                end
            end
            local valid,message=DirectorSeats.validate(sceneActors,duration)
            if not valid then actor.actions=beforeActions;return false,message end
            local handle = sceneEntities[id]
            if actor.kind == 'ped' and handle and DoesEntityExist(handle) then ClearPedTasksImmediately(handle) end
            actor._playing = nil
            actor._lookPlaying = nil
            sceneApply(playhead)
            sceneSend()
            return true
        end
    end
    return false
end

RegisterCommand(Config.Command, toggleDirector, false)
-- Read-only, on-demand engine evidence when a model or mapping behaves differently.
RegisterCommand('director_free_ground',function()
    if not directorOpen then print(localeText('[VANTA DIRECTOR] Open the editor first.'));return end
    for _,actor in ipairs(sceneActors) do
        local handle=sceneEntities[actor.id]
        if actor.kind=='ped' and (not selectedActorId or selectedActorId==actor.id) and handle and DoesEntityExist(handle) then
            local root=GetEntityCoords(handle)
            local left=GetPedBoneCoords(handle,0x3779,0.0,0.0,0.0)
            local right=GetPedBoneCoords(handle,0xCC4D,0.0,0.0,0.0)
            local surface=actor._ground and actor._ground.surface
            local feet=left and right and math.min(left.z,right.z)-.04
            print(('[VANTA DIRECTOR] model=%s rootZ=%.3f soleZ=%s groundZ=%s contactOffset=%s routeOffset=%.3f clearance=%.3f'):format(
                actor.model,root.z,feet and ('%.3f'):format(feet) or 'unavailable',
                surface and ('%.3f'):format(surface.z) or 'pending/unavailable',
                actor._contactOffset and ('%.3f'):format(actor._contactOffset) or 'uncalibrated',routeRootOffset(actor),actor._groundClearance or 0.0))
        end
    end
end,false)
RegisterKeyMapping(Config.Command, localeText('VANTA DIRECTOR: open or close camera mode'), 'keyboard', Config.DefaultKey)

local function routeActor(id)
    for _,actor in ipairs(sceneActors) do if actor.id==id then return actor end end
end
local function sendRouteScreen()
    if not routeDraft or not directorOpen or captureMode then return end
    local state=getCameraState(); if not state then return end
    local width,height=GetActiveScreenResolution(); local aspect=width/math.max(1,height)
    local points,lines={},{}
    local curve=routeDraft._curve or DirectorRoutes.compile(routeDraft.start,routeDraft.points); routeDraft._curve=curve
    for index,point in ipairs(routeDraft.points) do
        local x,y=DirectorGeometry.project(state,aspect,{x=point.x,y=point.y,z=point.z-(routeDraft.rootOffset or 0.0)+.1})
        if x and x>=0 and x<=1 and y>=0 and y<=1 then points[#points+1]={index=index,x=x,y=y} end
    end
    local previous
    local stride=math.max(1,math.ceil(#curve.samples/160))
    for index=1,#curve.samples+stride-1,stride do
        local point=curve.samples[math.min(index,#curve.samples)]
        local x,y=DirectorGeometry.project(state,aspect,{x=point.x,y=point.y,z=point.z-(routeDraft.rootOffset or 0.0)+.06})
        if x and previous then lines[#lines+1]={x1=previous.x,y1=previous.y,x2=x,y2=y} end
        previous=x and {x=x,y=y} or nil
    end
    local signature={tostring(#routeDraft.points),('%.2f'):format(curve.length)}
    for _,point in ipairs(points) do signature[#signature+1]=('%d:%.4f:%.4f'):format(point.index,point.x,point.y) end
    for _,line in ipairs(lines) do signature[#signature+1]=('%.4f:%.4f:%.4f:%.4f'):format(line.x1,line.y1,line.x2,line.y2) end
    signature=table.concat(signature,'|')
    if signature~=routeDraft._screen then
        routeDraft._screen=signature
        SendNUIMessage({action='routeScreen',routeToken=routeDraft.token,points=points,lines=lines,length=curve.length,count=#routeDraft.points})
    end
end
local function routePointAt(data)
    local sx,sy,aspect=finiteNumber(data.x,1),finiteNumber(data.y,1),finiteNumber(data.aspect,4)
    local state=getCameraState()
    if not state or not sx or not sy or sx<0 or sy<0 or not aspect or aspect<.5 then return nil end
    local direction=DirectorGeometry.ray(state,aspect,sx,sy)
    local target={x=state.x+direction.x*200,y=state.y+direction.y*200,z=state.z+direction.z*200}
    local ray=StartShapeTestRay((state.x) + 0.0,(state.y) + 0.0,(state.z) + 0.0,(target.x) + 0.0,(target.y) + 0.0,(target.z) + 0.0,1+16,PlayerPedId(),7)
    local pending,hit,point=GetShapeTestResult(ray); local deadline=GetGameTimer()+250
    while pending==1 and GetGameTimer()<deadline do Wait(0); pending,hit,point=GetShapeTestResult(ray) end
    if pending==2 and hit==1 then return {x=point.x,y=point.y,z=point.z} end
end

stopShotPreview=function()
    if not shotPreview then return end
    local previous=shotPreview;shotPreview=nil
    playhead=previous.time
    sceneApply(playhead,true)
    applyState(previous.camera)
    SendNUIMessage({action='shotPreviewStopped'})
end

local historyEdits={addRecordedGesture=true,pasteTimeline=true,saveLocation=true,deleteLocation=true,duplicateActors=true,setActorGroup=true,trimRecording=true,createCameraShot=true,updateCameraShot=true,deleteCameraShot=true,duplicateCameraShot=true,applyCameraPreset=true,addAccessory=true,setAttachment=true,setActorAppearance=true,addKeyframe=true,deleteKeyframe=true,moveKeyframe=true,setDuration=true,setFov=true,setKeyframeFov=true,setKeyframeName=true,setProjectName=true,setSceneLook=true,setCameraRig=true,placeBrowserModel=true,addActor=true,deleteActor=true,setActorTransform=true,addAction=true,deleteAction=true,moveAction=true,commitRoute=true}
local routeCommands={addRoutePoint=true,beginRoutePoint=true,moveRoutePoint=true,endRoutePoint=true,deleteRoutePoint=true,cancelRoute=true,commitRoute=true}
local function editorCallback(name, handler)
    RegisterNUICallback(name,function(data,callback)
        if type(data)~='table' then callback({ok=false,message='Invalid editor request.'});return end
        local allowed,reason=DirectorFree.callback(name,data)
        if not allowed then callback({ok=false,message=reason});return end
        if not directorOpen and name~='close' and name~='getPreferences' then callback({ok=false,message='Director is closed.'});return end
        if routeCommands[name] and data.routeToken~=nil and (not routeDraft or data.routeToken~=routeDraft.token) then callback({ok=false,message='This route request is obsolete.'});return end
        if editBusy and (name=='addRoutePoint' or name=='moveRoutePoint' or name=='beginRoutePoint' or name=='deleteRoutePoint') then callback({ok=false,message='Wait for route inspection to finish.'});return end
        if historyBusy and name~='setKeys' and name~='mouseLook' and name~='close' then callback({ok=false,message='Restoring the scene.'}); return end
        if (historyBusy or editBusy) and (historyEdits[name] or name=='beginActorDrag' or name=='undo' or name=='redo' or name=='manageProject') then callback({ok=false,message='An edit is still being applied.'}); return end
        if routeDraft and (name=='preview' or name=='capture' or name=='saveProject' or name=='previewCameraPreset' or name=='applyCameraPreset') then callback({ok=false,message='Apply or cancel the route first.'}); return end
        if motionRecording then callback({ok=false,message='Stop or cancel movement recording first.'});return end
        if shotPreview and name~='setKeys' and name~='mouseLook' then stopShotPreview() end
        if collaboration and collaboration.role=='viewer' and (historyEdits[name] or name=='beginActorDrag' or name=='undo' or name=='redo' or name=='saveProject' or name=='manageProject' or name=='importProject' or name=='startMotionRecording' or name=='commitRoute') then callback({ok=false,message='The session host controls scene edits.'});return end
        local before=historyEdits[name] and DirectorHistory.copy(projectPayload()) or nil
        if name=='beginActorDrag' then dragBefore=DirectorHistory.copy(projectPayload()) end
        if before then editBusy=true end
        local responded=false
        local function respond(result)
            if responded then return end
            result=type(result)=='table' and result or {ok=false,message='Invalid editor response.'}
            if before then
                editBusy=false
                if result.ok then
                    local grouped=name=='setFov' or name=='setSceneLook' or name=='setProjectName' or name=='setKeyframeFov'
                    DirectorHistory.commit(history,before,projectPayload(),grouped and (name..':'..tostring(data.index or '')) or nil,GetGameTimer())
                end
                sendHistory()
            elseif name=='endActorDrag' then
                if result.ok and dragBefore then DirectorHistory.commit(history,dragBefore,projectPayload()) end
                dragBefore=nil; sendHistory()
            end
            responded=true;callback(result)
        end
        local ok,err=xpcall(function() handler(data,respond) end,debug.traceback)
        if not ok then
            editBusy=false;historyBusy=false;dragBefore=nil;routeDraft=nil;pressedKeys={}
            pcall(SendNUIMessage,{action='routeClosed'})
            pcall(sendHistory)
            pcall(sendProject)
            if before then pcall(SendNUIMessage,{action='saveState',saved=false}) end
            print(('[VANTA DIRECTOR] Callback %s failed: %s'):format(name,tostring(err):sub(1,1500)))
            if not responded then responded=true;callback({ok=false,message='This edit could not be applied. Close or reload the scene if needed.'}) end
        end
    end)
end

editorCallback('getPreferences',function(_,callback) callback({ok=true,preferences=preferences}) end)
editorCallback('setPreferences',function(data,callback)
    if not directorOpen then callback({ok=false,message='Director is closed.'});return end
    local now=GetGameTimer()
    if now-preferencesWrittenAt<500 then callback({ok=false,message='Wait a moment before saving settings again.'});return end
    if type(data.preferences)~='table' then callback({ok=false,message='Invalid preferences.'});return end
    preferencesWrittenAt=now
    preferences=DirectorPreferences.save(data.preferences)
    cameraSpeed=preferences.speed;pressedKeys={};mouseLookX,mouseLookY=0,0;resetMotion()
    callback({ok=true,preferences=preferences})
end)
editorCallback('close', function(_, callback)
    restorePlayerView()
    callback({ ok = true })
end)

editorCallback('setKeys', function(data, callback)
    local sequence = finiteNumber(data.sequence,9007199254740991)
    if not sequence or sequence%1~=0 then callback({ok=false,message='Invalid input sequence.'});return end
    if directorOpen and sequence and sequence > lastInputSequence then
        lastInputSequence = sequence
        lastInputAt = GetGameTimer()
        pressedKeys = {}
        if type(data.keys) == 'table' then
            for _, key in ipairs({ 'w', 'a', 's', 'd', 'q', 'e', 'arrowleft', 'arrowright', 'arrowup', 'arrowdown' }) do
                pressedKeys[key] = data.keys[key] == true
            end
        end
    end
    callback({ ok = true })
end)

editorCallback('mouseLook', function(data, callback)
    if directorOpen and not previewing then
        local x,y=finiteNumber(data.x,10000),finiteNumber(data.y,10000)
        if not x or not y then callback({ok=false,message='Invalid mouse movement.'});return end
        mouseLookX = clamp(mouseLookX + x, -120.0, 120.0)
        mouseLookY = clamp(mouseLookY + y, -120.0, 120.0)
    end
    callback({ ok = true })
end)

editorCallback('addKeyframe', function(data, callback)
    local ok, message = addKeyframe(data.time)
    callback({ ok = ok, message = message })
end)

editorCallback('deleteKeyframe', function(data, callback)
    local keyframes=editingFrames()
    local index = tonumber(data.index)
    if index and keyframes[index] then
        if editingShot() and #keyframes==1 and editingShot().rig.mode=='manual' then callback({ok=false,message='Keep one key or delete the entire shot.'});return end
        table.remove(keyframes, index)
        sendProject()
        callback({ ok = true })
        return
    end
    callback({ ok = false, message = 'Keyframe not found.' })
end)

editorCallback('moveKeyframe', function(data, callback)
    local keyframes=editingFrames()
    local index, atTime = tonumber(data.index), tonumber(data.time)
    if not index or not keyframes[index] or not atTime or atTime ~= atTime then
        callback({ ok = false, message = 'Invalid camera keyframe.' })
        return
    end
    local time = clamp(atTime, 0.0, duration)
    for otherIndex, frame in ipairs(keyframes) do
        if otherIndex ~= index and math.abs(frame.time - time) < 0.05 then
            callback({ ok = false, message = 'There is already a camera keyframe here.' })
            return
        end
    end
    local shot=editingShot()
    if shot and (time<shot.time or time>shot.time+shot.duration) then callback({ok=false,message='Keep the key inside its shot.'});return end
    keyframes[index].time = time
    table.sort(keyframes, function(a, b) return a.time < b.time end)
    setPlayhead(time)
    sendProject()
    callback({ ok = true })
end)

editorCallback('setPlayhead', function(data, callback)
    local at=finiteNumber(data.time,Config.MaximumDuration)
    if not at then callback({ok=false,message='Invalid timeline position.'});return end
    local sequence = finiteNumber(data.sequence,9007199254740991)
    if data.sequence~=nil and (not sequence or sequence%1~=0) then callback({ok=false,message='Invalid timeline sequence.'});return end
    if sequence and sequence <= lastSeekSequence then
        callback({ ok = true })
        return
    end
    if sequence then lastSeekSequence = sequence end
    previewing = false
    setPlayhead(data.time)
    callback({ ok = true })
end)

editorCallback('setDuration', function(data, callback)
    local requested=DirectorShots.number(data.duration,Config.MinimumDuration,Config.MaximumDuration)
    if not requested then callback({ok=false,message='Invalid project duration.'});return end
    for _,shot in ipairs(cameraShots) do if shot.time+shot.duration>requested+.001 then callback({ok=false,message='Keep every camera shot inside the project.'});return end end
    local valid,message=DirectorSeats.validate(sceneActors,requested)
    if not valid then callback({ok=false,message=message});return end
    for _,a in ipairs(sceneActors) do for _,clip in ipairs(a.actions) do if clip.type=='recording' and clip.time+clip.duration>requested+.001 then callback({ok=false,message='Keep the full recorded take inside the timeline.'});return end end end
    for _,frame in ipairs(keyframes) do if frame.time>requested+.001 then callback({ok=false,message='Move or delete camera keys beyond the new duration first.'});return end end
    for _,actor in ipairs(sceneActors) do for _,action in ipairs(actor.actions) do
        if action.time+(action.duration or 0)>requested+.001 then callback({ok=false,message='Move or shorten actions beyond the new duration first.'});return end
    end end
    duration=requested
    playbackRange=nil
    playhead = clamp(playhead, 0.0, duration)
    for _, frame in ipairs(keyframes) do
        frame.time = clamp(frame.time, 0.0, duration)
    end
    for _, actor in ipairs(sceneActors) do
        for _, action in ipairs(actor.actions) do
            action.time = clamp(action.time, 0.0, duration)
            if action.type == 'move' or action.type == 'lookAt' then
                action.time = math.min(action.time, math.max(0.0, duration - 0.1))
                action.duration = math.max(0.1, math.min(action.duration, math.max(0.1, duration - action.time)))
            end
        end
    end
    table.sort(keyframes, function(a, b) return a.time < b.time end)
    sendProject()
    callback({ ok = true })
end)

editorCallback('setFov', function(data, callback)
    local fov = clamp(tonumber(data.fov) or 50.0, 20.0, 100.0)
    local rig=editingShot() and editingShot().rig or cameraRig
    if rig.anchor then
        rig.anchor.fov = fov
        sendProject()
        SendNUIMessage({ action = 'saveState', saved = false })
    end
    if camera and DoesCamExist(camera) then
        SetCamFov(camera, fov + 0.0)
    end
    sendCameraState()
    callback({ ok = true })
end)

editorCallback('setKeyframeFov', function(data, callback)
    local keyframes=editingFrames()
    local index, fov = tonumber(data.index), tonumber(data.fov)
    if not index or not keyframes[index] or not fov or fov ~= fov then
        callback({ ok = false, message = 'Camera shot not found.' })
        return
    end
    keyframes[index].fov = clamp(fov, 20.0, 100.0)
    if math.abs(playhead - keyframes[index].time) < 0.05 and camera and DoesCamExist(camera) then
        SetCamFov(camera, keyframes[index].fov + 0.0)
    end
    sendProject()
    callback({ ok = true })
end)

editorCallback('setKeyframeName', function(data, callback)
    local keyframes=editingFrames()
    local index = tonumber(data.index)
    if not index or not keyframes[index] then
        callback({ ok = false, message = 'Camera shot not found.' })
        return
    end
    keyframes[index].name = tostring(data.name or ''):gsub('[\r\n]', ' '):sub(1, 48)
    sendProject()
    callback({ ok = true })
end)

editorCallback('setSpeed', function(data, callback)
    cameraSpeed = clamp(tonumber(data.speed) or Config.DefaultCameraSpeed, 0.5, 30.0)
    callback({ ok = true })
end)

editorCallback('setProjectName', function(data, callback)
    projectName = tostring(data.name or 'Untitled Project'):gsub('[\r\n]', ' '):sub(1, 64)
    callback({ ok = true })
end)

editorCallback('setSceneLook', function(data, callback)
    local field, value = tostring(data.field or ''), data.value
    if field == 'weather' then
        value = tostring(value or ''):upper()
        if not weatherTypes[value] then callback({ ok = false, message = 'Invalid weather.' }) return end
        sceneLook.weather = value
    elseif field == 'hour' then
        value = tonumber(value)
        if not value or value % 1 ~= 0 or value < -1 or value > 23 then callback({ ok = false, message = 'Invalid hour.' }) return end
        sceneLook.hour = value
    elseif field == 'minute' then
        value = tonumber(value)
        if not value or value % 1 ~= 0 or value < 0 or value > 59 then callback({ ok = false, message = 'Invalid minute.' }) return end
        sceneLook.minute = value
    elseif field=='focusId' then
        local id=tonumber(value)
        if id~=0 and not sceneEntities[id] then callback({ok=false,message='Choose a scene subject.'});return end
        sceneLook.focusId=id~=0 and id or nil
    elseif field == 'dof' then
        if type(value) ~= 'boolean' then callback({ ok = false, message = 'Invalid depth of field.' }) return end
        sceneLook.dof = value
    elseif field == 'near' or field == 'far' or field == 'strength' then
        value = tonumber(value)
        local minimum, maximum = field == 'near' and 0.1 or (field == 'far' and 0.2 or 0.0), field == 'near' and 100.0 or (field == 'far' and 500.0 or 1.0)
        if not value or value ~= value or value < minimum or value > maximum then callback({ ok = false, message = 'Invalid focus value.' }) return end
        sceneLook[field] = value
        if sceneLook.far <= sceneLook.near then sceneLook.far = math.min(500.0, sceneLook.near + 0.1) end
    else callback({ ok = false, message = 'Invalid setting.' }) return end
    clearSceneLook()
    applySceneLook(true)
    sendProject()
    callback({ ok = true })
end)

local function buildCameraPreset(data)
    if not directorOpen or previewing or captureMode or dragSession or routeDraft or DirectorModelBrowser.active then return nil,'Stop the current preview or edit first.' end
    local token=sceneGeneration
    local base=getCameraState()
    if not base then return nil,'Camera is not ready.' end
    local target
    local id=tonumber(data.targetId)
    if id and id~=0 then
        local handle=sceneEntities[id]
        if not handle or not DoesEntityExist(handle) then return nil,'Choose an available scene subject.' end
        local point=GetEntityCoords(handle)
        target={id=id,x=point.x,y=point.y,z=point.z,aimHeight=0}
    else
        if data.kind=='follow' then return nil,'Follow needs a scene subject.' end
        local x,y,z=scenePlace()
        if not x then return nil,'Could not resolve the camera aim.' end
        target={x=x,y=y,z=z,aimHeight=0}
    end
    if not directorOpen or token~=sceneGeneration then return nil,'Scene changed while preparing the shot.' end
    local draft=DirectorCameraRig.preset(data.kind,target,base,tonumber(data.seconds),tonumber(data.distance),tonumber(data.height),tonumber(data.travel))
    if not draft then return nil,'Check the shot settings.' end
    if playhead+draft.seconds>Config.MaximumDuration then return nil,'The shot exceeds the maximum project duration.' end
    draft.start=playhead;draft.camera=base
    return draft
end

local function commitShots(candidate)
    local limit=duration
    for _,shot in ipairs(candidate) do limit=math.max(limit,shot.time+shot.duration) end
    if limit>Config.MaximumDuration then return false,'Maximum project duration exceeded.' end
    local clean,message=DirectorShots.validate(candidate,limit,sceneActors,#keyframes,true)
    if not clean then return false,message end
    cameraShots=clean;duration=limit
    return true
end
local function appendShot(frames,rig,seconds,name,start)
    local id=1;for _,shot in ipairs(cameraShots) do id=math.max(id,shot.id+1) end
    local candidate=DirectorShots.copy(cameraShots)
    candidate[#candidate+1]={id=id,name=name,time=start,duration=seconds,frames=frames,rig=rig or {mode='manual'},ease='smooth'}
    local ok,message=commitShots(candidate)
    if not ok then return false,message end
    selectedShotId=id;setPlayhead(start);sendProject()
    return true
end
editorCallback('setPlaybackRange',function(data,callback)
    local first=DirectorShots.number(data.first,0,duration)
    local last=DirectorShots.number(data.last,0,duration)
    if not first or not last or last-first<.1 then callback({ok=false,message='Choose a valid playback range.'});return end
    previewing=false;playbackRange={first=first,last=last,loop=data.loop==true};sendProject();callback({ok=true})
end)
editorCallback('copyTimeline',function(data,callback)
    if type(data.items)~='table' or #data.items==0 or #data.items>Config.MaximumTimelineSelection then callback({ok=false,message='Ctrl-click timeline items to select them.'});return end
    local list,start={},math.huge
    for _,item in ipairs(data.items) do
        if type(item)~='table' then callback({ok=false,message='Invalid selection.'});return end
        local value
        if item.kind=='camera' then value=editingFrames()[tonumber(item.index)]
        elseif item.kind=='shot' then value=DirectorShots.find(cameraShots,item.id)
        elseif item.kind=='action' then for _,a in ipairs(sceneActors) do if a.id==tonumber(item.actorId) then for _,clip in ipairs(a.actions) do if clip.id==tonumber(item.actionId) then value=clip end end end end end
        if not value then callback({ok=false,message='The selection changed. Select the items again.'});return end
        list[#list+1]={kind=item.kind,actorId=tonumber(item.actorId),data=DirectorShots.copy(value)};start=math.min(start,value.time)
    end
    timelineClipboard={items=list,start=start};callback({ok=true,message='Timeline selection copied.'})
end)
editorCallback('pasteTimeline',function(_,callback)
    if not timelineClipboard then callback({ok=false,message='Copy timeline items first.'});return end
    if previewing or captureMode or routeDraft or dragSession then callback({ok=false,message='Stop playback or editing first.'});return end
    local actors=DirectorShots.copy(sceneActors);local shots=DirectorShots.copy(cameraShots);local frames=DirectorShots.copy(editingFrames())
    local offset=playhead-timelineClipboard.start;local actionId=nextActionId;local shotId=1
    for _,shot in ipairs(shots) do shotId=math.max(shotId,shot.id+1) end
    for _,item in ipairs(timelineClipboard.items) do
        local copy=DirectorShots.copy(item.data);copy.time=copy.time+offset
        if copy.time<0 or copy.time+(copy.duration or 0)>duration+.001 then callback({ok=false,message='Extend the project or paste earlier.'});return end
        if item.kind=='camera' then frames[#frames+1]=copy
        elseif item.kind=='shot' then copy=DirectorShots.retime(item.data,copy.time,copy.duration);copy.id=shotId;shotId=shotId+1;shots[#shots+1]=copy
        elseif item.kind=='action' then
            local actor;for _,a in ipairs(actors) do if a.id==item.actorId then actor=a end end
            if not actor or #actor.actions>=Config.MaximumActionsPerActor then callback({ok=false,message='Actor missing or action limit reached.'});return end
            if copy.type=='recording' then callback({ok=false,message='Duplicate the recorded actor in Staging to copy its take.'});return end
            copy.id=actionId;actionId=actionId+1;actor.actions[#actor.actions+1]=copy
        end
    end
    local shot=editingShot()
    local clean,message=DirectorShots.frames(frames,shot and shot.time or 0,shot and shot.time+shot.duration or duration)
    if not clean then callback({ok=false,message=message});return end
    if shot then for _,v in ipairs(shots) do if v.id==shot.id then v.frames=clean end end end
    local valid,message=DirectorShots.validate(shots,duration,actors,shot and #keyframes or #clean,true)
    if not valid then callback({ok=false,message=message});return end
    local validActors,message=DirectorSeats.validate(actors,duration)
    if not validActors then callback({ok=false,message=message});return end
    local old=DirectorHistory.copy(sceneActors);local rig=DirectorShots.copy(cameraRig)
    if not sceneLoad(actors,true,true) then sceneLoad(old,true,true);cameraRig=rig;callback({ok=false,message='Could not restore the copied scene.'});return end
    cameraRig=rig;cameraShots=valid;if not shot then keyframes=clean end
    sceneApply(playhead,true);setPlayhead(playhead);sendProject();callback({ok=true,message='Selection pasted.'})
end)

editorCallback('saveLocation',function(data,callback)
    if #bookmarks>=Config.MaximumSavedLocations then callback({ok=false,message='Location limit reached.'});return end
    local state=getCameraState();if not state then callback({ok=false,message='Camera unavailable.'});return end
    state.time=0;bookmarks[#bookmarks+1]={name=tostring(data.name or 'Location'):sub(1,48),camera=state}
    sendProject();callback({ok=true})
end)
editorCallback('deleteLocation',function(data,callback)
    local i=tonumber(data.index);if not i or not bookmarks[i] then callback({ok=false,message='Location missing.'});return end
    table.remove(bookmarks,i);sendProject();callback({ok=true})
end)
editorCallback('goLocation',function(data,callback)
    local location=bookmarks[tonumber(data.index)]
    if not location then callback({ok=false,message='Location missing.'});return end
    if select(1,rigAtTime(playhead)).mode~='manual' then callback({ok=false,message='Switch the current camera mode to Manual first.'});return end
    previewing=false;resetMotion();applyState(location.camera);sendCameraState();callback({ok=true})
end)
editorCallback('setCameraRig', function(data, callback)
    local shot=editingShot()
    local mode = tostring(data.mode or 'manual')
    if mode == 'manual' then
        if shot and #shot.frames==0 and frameCount()>=Config.MaximumKeyframes then
            callback({ok=false,message='Camera keyframe limit reached.'});return
        end
        previewing = false
        pressedKeys = {}
        resetMotion()
        if shot then if #shot.frames==0 then local anchor=DirectorShots.copy(shot.rig.anchor or getCameraState());anchor.time=shot.time;shot.frames={anchor} end;shot.rig={mode='manual'} else cameraRig={mode='manual'} end
        sendProject()
        callback({ ok = true })
        return
    end
    if mode ~= 'target' and mode ~= 'follow' and mode ~= 'orbit' then
        callback({ ok = false, message = 'Choose a camera mode.' }) return
    end
    local id = tonumber(data.targetId)
    local handle = id and sceneEntities[id]
    local state = getCameraState()
    if not handle or not DoesEntityExist(handle) or not state then
        callback({ ok = false, message = 'Choose a staged subject first.' }) return
    end
    local targetHeight = finiteNumber(data.targetHeight, 20)
    local radius = finiteNumber(data.radius, 1000)
    local elevation = finiteNumber(data.elevation, 100)
    local speed = finiteNumber(data.speed, 90)
    if not targetHeight or not radius or radius < 0.5 or not elevation or not speed then
        callback({ ok = false, message = 'Check the camera settings.' }) return
    end
    local position = GetEntityCoords(handle)
    local dx, dy = state.x - position.x, state.y - position.y
    local offsetX, offsetY = dx, dy
    local relative = data.relative == true
    if relative then
        local heading = math.rad(GetEntityHeading(handle))
        offsetX, offsetY = dx * math.cos(heading) + dy * math.sin(heading), -dx * math.sin(heading) + dy * math.cos(heading)
    end
    local rig = {
        mode = mode, targetId = id, targetHeight = targetHeight, relative = relative,
        avoidObstacles=data.avoidObstacles==true,
        offsetX = offsetX, offsetY = offsetY, offsetZ = state.z - position.z - targetHeight,
        radius = radius, elevation = elevation, speed = speed,
        startAngle = math.deg(math.atan(dy, dx)) - (shot and playhead-shot.time or playhead) * speed, anchor = state
    }
    if shot then shot.rig=rig else cameraRig=rig end
    previewing = false
    pressedKeys = {}
    resetMotion()
    applyCameraRig(playhead, state)
    sendProject()
    callback({ ok = true })
end)

editorCallback('preview', function(_, callback)
    local ok, message = startPreview()
    SendNUIMessage({ action = ok and 'previewStarted' or 'status', message = message })
    callback({ ok = ok, message = message })
end)

local function endCapture()
    if not captureMode then return end
    captureMode = false
    previewing = false
    SendNUIMessage({ action = 'captureEnd' })
    if selectedActorId and sceneEntities[selectedActorId] and DoesEntityExist(sceneEntities[selectedActorId]) then
        selectionOutline(sceneEntities[selectedActorId], true)
    end
    SetNuiFocus(true, true)
    setPlayhead(select(1,playbackBounds()))
end

editorCallback('capture', function(_, callback)
    for _,actor in ipairs(sceneActors) do if actor._missing then callback({ok=false,message='Model unavailable: '..actor.model..'. Reload after installing it, or remove this actor before filming.'});return end end
    captureToken=captureToken+1;local token=captureToken
    if #keyframes == 0 and #cameraShots==0 and cameraRig.mode == 'manual' then
        callback({ ok = false, message = 'Add a camera keyframe before recording.' })
        return
    end
    previewing = false
    captureMode = true
    pressedKeys = {}
    if selectedActorId and sceneEntities[selectedActorId] and DoesEntityExist(sceneEntities[selectedActorId]) then
        selectionOutline(sceneEntities[selectedActorId], false)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'captureCountdown', seconds = Config.CaptureCountdownSeconds })
    callback({ ok = true })
    CreateThread(function()
        Wait(Config.CaptureCountdownSeconds * 1000)
        if token~=captureToken or not captureMode or not directorOpen then return end
        playhead = select(1,playbackBounds())
        setPlayhead(playhead)
        local ok = startPreview()
        if ok then SendNUIMessage({ action = 'captureGo' }) else endCapture() end
    end)
end)

RegisterCommand('vanta_director_free_stop_take', function()
    if captureMode then endCapture() end
end, false)
RegisterKeyMapping('vanta_director_free_stop_take', localeText('VANTA DIRECTOR: stop clean take'), 'keyboard', Config.StopTakeKey)

editorCallback('stopPreview', function(_, callback)
    if captureMode then endCapture() else previewing = false end
    resetMotion()
    sceneApply(playhead, true)
    applyCameraRig(playhead, stateAtTime(playhead) or cameraRig.anchor)
    callback({ ok = true })
end)

editorCallback('openModelBrowser', function(_, callback)
    if not directorOpen or captureMode then callback({ok=false,message='Open Director before browsing models.'}) return end
    DirectorModelBrowser.open(camera, getCameraState())
    stopAnimationPreview(true)
    if not DirectorModelBrowser.active then callback({ok=false,message='Browser closed.'}) return end
    previewing = false
    pressedKeys = {}
    resetMotion()
    callback({ok=true})
end)

editorCallback('previewModel', function(data, callback)
    local ok, message = DirectorModelBrowser.preview(data.kind, data.model, data.viewport)
    callback({ok=ok,message=message})
end)

editorCallback('modelPreviewView', function(data, callback)
    DirectorModelBrowser.view(data.angle, data.zoom, data.elevation, data.viewport)
    callback({ok=true})
end)

editorCallback('clearModelPreview', function(_, callback)
    DirectorModelBrowser.resetPreview()
    callback({ok=true})
end)

editorCallback('closeModelBrowser', function(_, callback)
    DirectorModelBrowser.close()
    callback({ok=true})
end)

editorCallback('placeBrowserModel', function(data, callback)
    if not DirectorModelBrowser.active then callback({ok=false,message='Open the model browser first.'}) return end
    DirectorModelBrowser.close()
    local ok, message = sceneAdd(data.kind, data.model)
    callback({ok=ok,message=message})
end)

local function appearanceActor(id)
    for _,actor in ipairs(sceneActors) do
        local h=sceneEntities[actor.id]
        if actor.id==tonumber(id) and (actor.kind=='ped' or actor.kind=='vehicle') and h and DoesEntityExist(h) then return actor,h end
    end
end
editorCallback('getActorAppearance',function(data,callback)
    local actor,h=appearanceActor(data.id)
    if not actor then callback({ok=false,message='Select a ped or vehicle.'});return end
    callback({ok=true,options=DirectorAppearance.read(actor.kind,h)})
end)
editorCallback('setActorAppearance',function(data,callback)
    local actor,h=appearanceActor(data.id)
    if not actor or previewing or captureMode or dragSession then callback({ok=false,message='Stop playback before styling an actor.'});return end
    local ok,value=DirectorAppearance.patch(actor.kind,actor.appearance,data.appearance)
    if not ok then callback({ok=false,message=value});return end
    local supported,message=DirectorAppearance.supported(actor.kind,h,value)
    if not supported then callback({ok=false,message=message});return end
    DirectorAppearance.apply(actor.kind,h,value);actor.appearance=value
    SendNUIMessage({action='saveState',saved=false})
    callback({ok=true,appearance=DirectorHistory.copy(value),options=DirectorAppearance.read(actor.kind,h)})
end)
editorCallback('addActor', function(data, callback)
    local ok, message = sceneAdd(data.kind, data.model)
    callback({ ok = ok, message = message })
end)

editorCallback('deleteActor', function(data, callback)
    callback({ ok = sceneDelete(tonumber(data.id)) })
end)

editorCallback('selectActor', function(data, callback)
    local id = tonumber(data.id)
    local handle = id and sceneEntities[id]
    if not handle or not DoesEntityExist(handle) then
        callback({ ok = false })
        return
    end
    if selectedActorId and sceneEntities[selectedActorId] and DoesEntityExist(sceneEntities[selectedActorId]) then
        selectionOutline(sceneEntities[selectedActorId], false)
    end
    selectedActorId = id
    local visible = true
    for _, actor in ipairs(sceneActors) do
        if actor.id == id then visible = actor._visible ~= false break end
    end
    selectionOutline(handle, visible)
    callback({ ok = true })
end)

editorCallback('setActorTransform', function(data, callback)
    local ok, message = sceneSetTransform(tonumber(data.id), data)
    callback({ ok = ok, message = message })
end)

editorCallback('beginActorDrag', function(data, callback)
    local id = sceneDragBegin(data)
    callback({ ok = id ~= nil, id = id })
end)

editorCallback('dragActor', function(data, callback)
    callback({ ok = sceneDragMove(data) })
end)

editorCallback('endActorDrag', function(_, callback)
    callback({ ok = sceneDragEnd() })
end)

editorCallback('addAction', function(data, callback)
    if data.type == 'animation' then stopAnimationPreview(true) end
    local ok, message = sceneAddAction(tonumber(data.id), data.type, data)
    callback({ ok = ok, message = message })
end)

editorCallback('previewAnimation', function(data, callback)
    local id, dict, clip = tonumber(data.id), tostring(data.dict or ''), tostring(data.clip or '')
    if not directorOpen or captureMode or previewing then
        callback({ ok = false, message = 'Stop playback before previewing an animation.' })
        return
    end
    local actor
    for _, item in ipairs(sceneActors) do
        if item.id == id and item.kind == 'ped' then actor = item break end
    end
    local handle = actor and sceneEntities[id]
    if not handle or not DoesEntityExist(handle) then
        callback({ ok = false, message = 'Select a staged ped first.' })
        return
    end
    if not dict:match('^[%w_@%-]+$') or not clip:match('^[%w_%-]+$') or #dict > 80 or #clip > 80 or
        not DoesAnimDictExist(dict) then
        callback({ ok = false, message = 'This animation dictionary is unavailable.' })
        return
    end
    if data.loop~=nil and type(data.loop)~='boolean' then callback({ok=false,message='Invalid animation playback mode.'});return end
    stopAnimationPreview(true)
    local token = animationPreviewToken
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline and token == animationPreviewToken and directorOpen do Wait(25) end
    if token ~= animationPreviewToken or not directorOpen or not DoesEntityExist(handle) then
        callback({ ok = false, message = 'Animation preview cancelled.' })
        return
    end
    if not HasAnimDictLoaded(dict) then
        callback({ ok = false, message = 'Animation did not load.' })
        return
    end
    local length=GetAnimDuration(dict,clip)
    if type(length)~='number' or length~=length or length<=0 then callback({ok=false,message='Animation clip unavailable on this game build.'});return end
    ClearPedTasksImmediately(handle)
    if not actor._frozen then FreezeEntityPosition(handle, true); actor._frozen = true end
    TaskPlayAnim(handle, dict, clip, 8.0, -8.0, -1, data.loop==false and 0 or 1, 0.0, false, false, false)
    actor._playing = 'preview'
    animationPreviewActor = id
    Wait(math.max(0,math.min(120,math.floor(length*250))))
    if token ~= animationPreviewToken or not DoesEntityExist(handle) then
        callback({ ok = false, message = 'Animation preview cancelled.' })
        return
    end
    if not IsEntityPlayingAnim(handle, dict, clip, 3) then
        stopAnimationPreview(true)
        callback({ ok = false, message = 'This animation does not play on the selected ped.' })
        return
    end
    callback({ ok = true, nativeDuration=length, loop=data.loop~=false })
end)

editorCallback('stopAnimationPreview', function(_, callback)
    stopAnimationPreview(true)
    callback({ ok = true })
end)

editorCallback('deleteAction', function(data, callback)
    local ok,message=sceneDeleteAction(tonumber(data.id),tonumber(data.index))
    callback({ok=ok,message=message})
end)

editorCallback('moveAction', function(data, callback)
    local actorId, actionId, atTime = tonumber(data.actorId), tonumber(data.actionId), tonumber(data.time)
    if not atTime or atTime ~= atTime then
        callback({ ok = false, message = 'Invalid action time.' })
        return
    end
    for _, actor in ipairs(sceneActors) do
        if actor.id == actorId then
            for _, action in ipairs(actor.actions) do
                if action.id == actionId then
                    local latest = (action.type == 'move' or action.type == 'lookAt' or action.type=='enterVehicle' or action.type=='exitVehicle' or action.type=='recording' or (action.type=='animation' and action.duration)) and math.max(0.0, duration - action.duration) or duration
                    local oldTime=action.time
                    action.time = clamp(atTime,0.0,latest)
                    local valid,message=DirectorSeats.validate(sceneActors,duration)
                    if not valid then action.time=oldTime;callback({ok=false,message=message});return end
                    table.sort(actor.actions, function(a, b)
                        if a.time == b.time then return a.id < b.id end
                        return a.time < b.time
                    end)
                    setPlayhead(action.time)
                    sceneSend()
                    callback({ ok = true })
                    return
                end
            end
        end
    end
    callback({ ok = false, message = 'Action not found.' })
end)

local function withoutRuntimeState(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do
        if type(key) ~= 'string' or key:sub(1, 1) ~= '_' then
            result[key] = withoutRuntimeState(item)
        end
    end
    return result
end

projectPayload = function()
    return {
        id = currentProjectId,
        version = 4,
        name = projectName,
        duration = duration,
        keyframes = keyframes,
        actors = withoutRuntimeState(sceneActors),
        look = sceneLook,
        cameraRig = withoutRuntimeState(cameraRig),
        cameraShots = withoutRuntimeState(cameraShots),
        bookmarks = bookmarks
    }
end

local recordModelCache={}
RegisterCommand('director_free_status',function()
    local keys=frameCount();local actions,entities,recordings=0,0,0
    for _,actor in ipairs(sceneActors) do
        local h=sceneEntities[actor.id];if h and DoesEntityExist(h) then entities=entities+1 end
        for _,action in ipairs(actor.actions or {}) do actions=actions+1;if action.type=='recording' then recordings=recordings+1 end end
    end
    local encoded=json.encode(projectPayload())
    print(('[VANTA DIRECTOR] version=0.1.0-beta open=%s actors=%d entities=%d keys=%d actions=%d takes=%d bytes=%d playback=%s capture=%s session=%s'):format(
        tostring(directorOpen),#sceneActors,entities,keys,actions,recordings,encoded and #encoded or 0,tostring(previewing),tostring(captureMode~=nil and captureMode~=false),collaboration and collaboration.role or 'solo'))
    print(localeText('[VANTA DIRECTOR] Performance measurements: use resmon 1 and profiler record 500 in F8. This report does not measure resource CPU time.'))
end,false)
local function resolveRecordModel(kind,hash,supplied)
    if type(supplied)=='string' and supplied:match('^[%w_]+$') and #supplied<=48 and GetHashKey(supplied)==hash then return supplied end
    if not recordModelCache[kind] then
        local map={};local ok,catalog=pcall(json.decode,LoadResourceFile(GetCurrentResourceName(),'model_catalog.json') or '[]')
        if ok and type(catalog)=='table' then for _,item in ipairs(catalog) do if item.kind==kind then map[GetHashKey(item.model)]=item.model end end end
        for _,item in ipairs(Config.CustomModels or {}) do if item.kind==kind then map[GetHashKey(item.model)]=item.model end end
        if kind=='vehicle' and type(GetAllVehicleModels)=='function' then for _,name in ipairs(GetAllVehicleModels()) do map[GetHashKey(name)]=name end end
        recordModelCache[kind]=map
    end
    return recordModelCache[kind][hash]
end
local function recordSample(session,seconds)
    if not DoesEntityExist(session.handle) then return false end
    local p=GetEntityCoords(session.handle);local r=GetEntityRotation(session.handle,2)
    local function round(v)return math.floor(v*1000+.5)/1000 end
    local row={round(seconds),round(p.x),round(p.y),round(p.z),round(r.x),round(r.y),round(r.z),round(math.min(150,math.max(0,GetEntitySpeed(session.handle))))}
    if session.kind=='ped' and (not session._poseScan or GetGameTimer()-session._poseScan>=250) and type(IsEntityPlayingAnim)=='function' then
        session._poseScan=GetGameTimer();local active=nil
        for name,gesture in pairs(DirectorRecording.gestures) do if IsEntityPlayingAnim(session.handle,gesture.dict,gesture.clip,3) then active=name;break end end
        if active~=session._activeGesture then
            if session._activeCue then session._activeCue.duration=math.max(0,seconds-session._activeCue.time) end
            session._activeGesture=active;session._activeCue=nil
            if active and #session.poseCues<30 then local cue={gesture=active,time=seconds,duration=0};session.poseCues[#session.poseCues+1]=cue;session._activeCue=cue end
        end
    end
    local previous=session.samples[#session.samples]
    if session.kind=='ped' and session.captureAim then
        local fired=IsPedShooting(session.handle)
        if session._activeAim then session._activeAim.fired=session._activeAim.fired or fired;session._activeAim.duration=math.min(.5,seconds-session._activeAim.time) end
        if not session._aimScan or seconds-session._aimScan>=.2 then
            session._aimScan=seconds;session._activeAim=nil
            if IsPlayerFreeAiming(PlayerId()) and #session.aimCues<150 then
                local selected=GetSelectedPedWeapon(session.handle);local weapon
                for _,name in ipairs(DirectorRecording.weapons) do if GetHashKey(name)==selected then weapon=name;break end end
                if weapon then
                    local cameraPosition=GetGameplayCamCoord();local rotation=GetGameplayCamRot(2)
                    local pitch,yaw=math.rad(rotation.x),math.rad(rotation.z)
                    local cue={weapon=weapon,time=seconds,duration=0,fired=fired==true,
                        x=round(cameraPosition.x-math.sin(yaw)*math.cos(pitch)*100),y=round(cameraPosition.y+math.cos(yaw)*math.cos(pitch)*100),z=round(cameraPosition.z+math.sin(pitch)*100)}
                    session.aimCues[#session.aimCues+1]=cue;session._activeAim=cue
                end
            end
        end
    end
    if not previous or row[1]>previous[1] then session.samples[#session.samples+1]=row end
    return true
end
finishMotionRecording=function(cancelled)
    local session=motionRecording;if not session then return end
    motionRecording=nil
    local elapsed=math.min(session.limit,(GetGameTimer()-session.started)/1000)
    if not cancelled then recordSample(session,elapsed) end
    if session._activeCue then session._activeCue.duration=math.max(0,elapsed-session._activeCue.time) end
    session.poseCues=DirectorRecording.trimCues(session.poseCues,0,elapsed)
    if session._activeAim then session._activeAim.duration=math.min(.5,elapsed-session._activeAim.time) end
    session.aimCues=DirectorRecording.trimAimCues(session.aimCues,0,elapsed)
    local ok,samples=DirectorRecording.validate(session.samples)
    local message=cancelled and 'Movement recording cancelled.' or 'Record for at least 0.1 seconds.'
    if not cancelled and ok then
        local before=DirectorHistory.copy(projectPayload())
        local first=samples[1];local a={id=nextActorId,kind=session.kind,model=session.model,x=first[2],y=first[3],z=first[4],heading=first[7],appearance=session.appearance,
            actions={{id=nextActionId,type='recording',time=session.time,duration=samples[#samples][1],samples=samples,poseCues=session.poseCues,aimCues=session.aimCues}}}
        local candidate=DirectorHistory.copy(before);candidate.actors[#candidate.actors+1]=a;candidate.duration=math.max(duration,session.time+a.actions[1].duration)
        local batch={a}
        for i,occupant in ipairs(session.occupants or {}) do
            local child={id=nextActorId+i,kind='ped',model=occupant.model,name=occupant.seat==-1 and 'Recorded driver' or 'Recorded passenger',
                x=first[2],y=first[3],z=first[4],heading=first[7],appearance=occupant.appearance,group='Take '..nextActorId,
                actions={{id=nextActionId+i,type='enterVehicle',vehicleId=a.id,seat=occupant.seat,time=session.time,duration=.1,instant=true}}}
            batch[#batch+1]=child;candidate.actors[#candidate.actors+1]=child
        end
        if #batch>1 then a.group='Take '..nextActorId end
        local encoded=json.encode(candidate)
        if encoded and #encoded<=Config.ProjectFileLimit and #sceneActors+#batch<=Config.MaximumActors then
            editBusy=true
            local spawned,errorMessage=true,nil
            for _,item in ipairs(batch) do
                local ok,reason=sceneSpawn(item)
                if not ok then spawned=false;errorMessage=reason;break end
            end
            if spawned then
                for _,item in ipairs(batch) do sceneActors[#sceneActors+1]=item end
                nextActorId=nextActorId+#batch;nextActionId=nextActionId+#batch;duration=candidate.duration
                playhead=session.time;selectedActorId=a.id
                DirectorHistory.commit(history,before,projectPayload());message='Movement take added. Drag its RECORD clip to change the start time.'
                SendNUIMessage({action='saveState',saved=false})
            else
                for _,item in ipairs(batch) do local h=sceneEntities[item.id];if h and DoesEntityExist(h) then DeleteEntity(h) end;sceneEntities[item.id]=nil end
                message=errorMessage or 'Could not spawn recorded actors. The take was rolled back.'
            end
            editBusy=false
        else message='Project size or actor limit reached. The recording was not added.' end
    end
    if directorOpen and camera and DoesCamExist(camera) then
        RenderScriptCams(true,true,250,true,true);SetNuiFocus(true,true);SetNuiFocusKeepInput(false)
        pressedKeys={};resetMotion();sendProject();sceneApply(playhead,true);sendHistory()
        SendNUIMessage({action='motionRecordFinished',message=message})
    end
end
CreateThread(function()
    while true do
        local session=motionRecording
        if session then
            local elapsed=(GetGameTimer()-session.started)/1000
            local sourceChanged=PlayerPedId()~=session.ped or not DoesEntityExist(session.handle) or IsEntityDead(session.ped)
            if session.kind=='ped' and IsPedInAnyVehicle(session.ped,false) then sourceChanged=true end
            if session.kind=='vehicle' and (GetVehiclePedIsIn(session.ped,false)~=session.handle or GetPedInVehicleSeat(session.handle,-1)~=session.ped) then sourceChanged=true end
            if not sourceChanged and session.occupants then
                for seat=-1,math.min(15,GetVehicleModelNumberOfSeats(GetEntityModel(session.handle))-2) do
                    local expected=0;for _,occupant in ipairs(session.occupants) do if occupant.seat==seat then expected=occupant.handle;break end end
                    if GetPedInVehicleSeat(session.handle,seat)~=expected then sourceChanged=true;break end
                end
            end
            if sourceChanged then finishMotionRecording(true)
            elseif elapsed>=session.limit then finishMotionRecording(false)
            else recordSample(session,elapsed);SendNUIMessage({action='motionRecordProgress',time=elapsed,limit=session.limit}) end
            Wait(50)
        else Wait(250) end
    end
end)

local function applyHistory(direction,callback)
    if not directorOpen or captureMode or dragSession then callback({ok=false,message='Stop the current manipulation first.'}); return end
    local source=direction=='redo' and history.future or history.past
    local entry=source[#source]
    if not entry then callback({ok=false,message='Nothing to '..direction..'.'}); return end
    local target=DirectorHistory.copy(direction=='redo' and entry.after or entry.before)
    local current=DirectorHistory.copy(projectPayload()); local selected=selectedActorId
    historyBusy=true; sendHistory(); previewing=false; pressedKeys={}; stopAnimationPreview(false); DirectorModelBrowser.close()
    duration=target.duration; keyframes=target.keyframes; projectName=target.name
    local expectedGeneration=sceneGeneration+2
    local ok=sceneLoad(target.actors,true,true)
    ok=ok and #sceneActors==#target.actors
    if ok then
        loadSceneLook(target.look); bookmarks=DirectorShots.copy(target.bookmarks or {});cameraShots=DirectorShots.copy(target.cameraShots or {});selectedShotId=nil;loadCameraRig(target.cameraRig); playhead=clamp(playhead,0,duration); setPlayhead(playhead)
        if selected and sceneEntities[selected] then selectedActorId=selected; selectionOutline(sceneEntities[selected],true) end
        DirectorHistory.take(history,direction)
        sendProject(); SendNUIMessage({action='saveState',saved=false}); SendNUIMessage({action='routeClosed'})
    elseif directorOpen and sceneGeneration==expectedGeneration and currentProjectId==current.id then
        duration=current.duration; keyframes=current.keyframes; projectName=current.name
        sceneLoad(current.actors,true,true); loadSceneLook(current.look); bookmarks=DirectorShots.copy(current.bookmarks or {});cameraShots=DirectorShots.copy(current.cameraShots or {});selectedShotId=nil;loadCameraRig(current.cameraRig); sendProject()
    end
    historyBusy=false; sendHistory(); callback({ok=ok,message=not ok and 'Could not restore the scene.' or nil})
end
editorCallback('undo',function(_,callback) applyHistory('undo',callback) end)
editorCallback('redo',function(_,callback) applyHistory('redo',callback) end)
editorCallback('saveProject', function(_, callback)
    for _,actor in ipairs(sceneActors) do if actor._missing then callback({ok=false,message='A model is unavailable. Reload it or explicitly remove the actor before saving.'});return end end
    if not currentProjectId then callback({ ok = false, message = 'Project library is still loading.' }) return end
    local payload = projectPayload()
    pendingSaveSnapshot = json.encode(payload)
    saveRequestSerial=saveRequestSerial+1;pendingSaveRequest=saveRequestSerial
    TriggerServerEvent('vanta_director_free:saveProject', payload, pendingSaveRequest)
    callback({ ok = true })
end)

editorCallback('manageProject', function(data, callback)
    local operation = tostring(data.operation or '')
    if operation ~= 'create' and operation ~= 'open' and operation ~= 'duplicate' and
        operation ~= 'rename' and operation ~= 'delete' then
        callback({ ok = false, message = 'Invalid project action.' })
        return
    end
    TriggerServerEvent('vanta_director_free:manageProject', operation, data.id, data.name)
    callback({ ok = true })
end)

local function loadProject(project)
    if shotPreview then stopShotPreview() end
    sessionPendingPlayback=nil
    DirectorModelBrowser.close()
    if type(project) ~= 'table' or type(project.keyframes) ~= 'table' then
        return
    end

    playbackRange=nil;timelineClipboard=nil
    history=DirectorHistory.new(40); dragBefore=nil; sendHistory()
    previewing = false
    captureMode = false
    pendingSaveSnapshot = nil
    playhead = 0.0
    projectName = tostring(project.name or projectName):sub(1, 64)
    duration = clamp(tonumber(project.duration) or Config.DefaultDuration, Config.MinimumDuration, Config.MaximumDuration)
    keyframes = {}
    for _, frame in ipairs(project.keyframes) do
        if type(frame) == 'table' then
            local values = { frame.time, frame.x, frame.y, frame.z, frame.rx, frame.ry, frame.rz, frame.fov }
            local valid = true
            for _, value in ipairs(values) do
                if type(value) ~= 'number' then valid = false break end
            end
            if valid and #keyframes < Config.MaximumKeyframes then
                keyframes[#keyframes + 1] = {
                    time = clamp(frame.time, 0.0, duration),
                    name = tostring(frame.name or ''):gsub('[\r\n]', ' '):sub(1, 48),
                    x = frame.x, y = frame.y, z = frame.z,
                    rx = frame.rx, ry = frame.ry, rz = frame.rz,
                    fov = clamp(frame.fov, 20.0, 100.0)
                }
            end
        end
    end
    table.sort(keyframes, function(a, b) return a.time < b.time end)
    if sceneLoad(project.actors) == false then return end
    loadSceneLook(project.look)
    bookmarks=DirectorShots.copy(project.bookmarks or {});cameraShots=DirectorShots.copy(project.cameraShots or {});selectedShotId=nil;applyState(stateAtTime(playhead));loadCameraRig(project.cameraRig)
    sendProject()
    SendNUIMessage({ action = 'saveState', saved = true })
end

editorCallback('exportProject',function(_,callback)
    callback({ok=true,json=json.encode(projectPayload()),message='Copy the JSON to share this project or keep it as a reusable scene template.'})
end)
editorCallback('importProject',function(data,callback)
    if type(data.json)~='string' or #data.json>Config.ProjectFileLimit then callback({ok=false,message='Project JSON is too large.'});return end
    TriggerServerEvent('vanta_director_free:importProject',data.json);callback({ok=true})
end)
RegisterNetEvent('vanta_director_free:accessDenied',function(message)
    if directorOpen then restorePlayerView();setNuiOpen(false) end
    print('[VANTA DIRECTOR] '..tostring(localeText(message)))
end)
RegisterNetEvent('vanta_director_free:collaborationStatus',function(message)SendNUIMessage({action='status',message=message})end)
RegisterNetEvent('vanta_director_free:projectLibrary', function(project, id, list, message)
    if not directorOpen then return end
    currentProjectId = id
    loadProject(project)
    SendNUIMessage({ action = 'library', activeId = id, projects = list, limit = Config.MaximumProjects })
    SendNUIMessage({ action = 'status', message = message or 'Project loaded.' })
end)

RegisterNetEvent('vanta_director_free:projectMetadata',function(id,list,renamedId,name)
    if not directorOpen then return end
    if renamedId==currentProjectId then projectName=name;sendProject() end
    SendNUIMessage({action='library',activeId=id,projects=list,limit=Config.MaximumProjects})
end)
RegisterNetEvent('vanta_director_free:projectList', function(id, list)
    currentProjectId = id
    SendNUIMessage({ action = 'library', activeId = id, projects = list, limit = Config.MaximumProjects })
end)

RegisterNetEvent('vanta_director_free:libraryError', function(message)
    SendNUIMessage({ action = 'libraryError', message = message or 'Project action failed.' })
end)

RegisterNetEvent('vanta_director_free:saveResult', function(ok, message, project, requestId)
    if requestId ~= pendingSaveRequest then return end
    if not directorOpen then pendingSaveSnapshot = nil return end
    if not pendingSaveSnapshot then return end
    local unchangedSinceSave = json.encode(projectPayload()) == pendingSaveSnapshot
    pendingSaveSnapshot = nil
    if ok and type(project) == 'table' and unchangedSinceSave then
        SendNUIMessage({ action = 'saveState', saved = true })
    elseif ok then
        SendNUIMessage({ action = 'saveState', saved = false })
    end
    SendNUIMessage({ action = 'saveResult', ok = ok, stale = ok and not unchangedSinceSave })
    local status = (ok and not unchangedSinceSave) and 'An earlier version was saved. Save again to include your latest edits.'
        or message or (ok and 'Saved.' or 'Save failed.')
    SendNUIMessage({ action = 'status', message = status })
end)

CreateThread(function()
    while true do
        if not directorOpen or not camera or not DoesCamExist(camera) then
            Wait(250)
        elseif motionRecording then
            Wait(50)
        else
            local deltaSeconds = math.min(GetFrameTime(), 0.1)
            if GetGameTimer() - lastInputAt > 750 then pressedKeys = {} end
            DisableAllControlActions(0)
            DisplayHud(false)
            DisplayRadar(false)
            applySceneLook(false)
            if collaboration and camera and DoesCamExist(camera) and GetGameTimer()-lastStreamingFocusUpdate>=100 then
                lastStreamingFocusUpdate=GetGameTimer()
                local p=GetCamCoord(camera);SetFocusPosAndVel((p.x) + 0.0,(p.y) + 0.0,(p.z) + 0.0,0.0,0.0,0.0);focusOwned=true
            end
            if sessionPendingPlayback then
                local pending=sessionPendingPlayback
                local elapsed=((GetNetworkTimeAccurate()-pending.clock+2147483648)%4294967296-2147483648)/1000
                if elapsed>=0 then
                    sessionPendingPlayback=nil
                    playhead=math.min(pending.last,pending.first+elapsed)
                    if playhead<pending.last then startPreview();SendNUIMessage({action='previewStarted'}) end
                end
            end

            if DirectorModelBrowser.active then
                pressedKeys = {}
                mouseLookX, mouseLookY = 0.0, 0.0
                resetMotion()
            elseif shotPreview then
                pressedKeys={};mouseLookX,mouseLookY=0,0
                local draft=shotPreview.draft
                local elapsed=math.min((GetGameTimer()-shotPreview.clock)/1000,draft.seconds)
                previewing=true
                sceneApply(math.min(draft.start+elapsed,duration))
                previewing=false
                if draft.rig then
                    local handle=sceneEntities[draft.rig.targetId]
                    if handle and DoesEntityExist(handle) then
                        local point=GetEntityCoords(handle)
                        applyState(DirectorCameraRig.sample(draft.rig,{x=point.x,y=point.y,z=point.z},draft.camera,elapsed))
                    else stopShotPreview() end
                else applyState(DirectorMotion.sample(draft.frames,elapsed)) end
                if elapsed>=draft.seconds then stopShotPreview() end
            elseif previewing then
                playhead = previewOffset + (GetGameTimer() - previewStartedAt) / 1000.0
                local first,last=playbackBounds()
                if playhead>=last then
                    if playbackRange and playbackRange.loop then
                        playhead=first+(playhead-first)%(last-first)
                        previewOffset=playhead;previewStartedAt=GetGameTimer();sceneApply(playhead,true)
                    else playhead=last;previewing=false end
                end
                sceneApply(playhead)
                local base = stateAtTime(playhead) or cameraRig.anchor
                applyState(base)
                applyCameraRig(playhead, base,true)
                if captureMode and not previewing then endCapture() end
            elseif select(1,rigAtTime(playhead)).mode == 'follow' or select(1,rigAtTime(playhead)).mode == 'orbit' then
                pressedKeys = {}
                mouseLookX, mouseLookY = 0.0, 0.0
                resetMotion()
                if dragSession then sceneDragUpdate(deltaSeconds) end
                applyCameraRig(playhead, stateAtTime(playhead) or cameraRig.anchor)
            else
                if dragSession then
                    pressedKeys = {}
                    mouseLookX, mouseLookY = 0.0, 0.0
                    resetMotion()
                end
                if DirectorMotion.cameraActive(pressedKeys, movementVelocity, turnVelocity, mouseLookX, mouseLookY) then
                local rotation = GetCamRot(camera, 2)
                local position = GetCamCoord(camera)
                local yaw = math.rad(rotation.z)
                local pitch = math.rad(rotation.x)
                local forward = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
                local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
                local move = vector3(0.0, 0.0, 0.0)

                if pressedKeys.w then move = move + forward end
                if pressedKeys.s then move = move - forward end
                if pressedKeys.d then move = move + right end
                if pressedKeys.a then move = move - right end
                if pressedKeys.e then move = move + vector3(0.0, 0.0, 1.0) end
                if pressedKeys.q then move = move - vector3(0.0, 0.0, 1.0) end

                local length = math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
                local scale = length > 0.0 and cameraSpeed / length or 0.0
                local distance = {}
                for _, axis in ipairs({ 'x', 'y', 'z' }) do
                    movementVelocity[axis], distance[axis] = DirectorMotion.damp(movementVelocity[axis], move[axis] * scale, deltaSeconds, Config.CameraMoveResponse)
                    if math.abs(movementVelocity[axis]) < 0.0001 then movementVelocity[axis] = 0.0 end
                end
                if distance.x ~= 0.0 or distance.y ~= 0.0 or distance.z ~= 0.0 then
                SetCamCoord(camera, (position.x + distance.x) + 0.0, (position.y + distance.y) + 0.0, (position.z + distance.z) + 0.0)
                end

                local targetYaw = ((pressedKeys.arrowleft and 1 or 0) - (pressedKeys.arrowright and 1 or 0)) * 65.0
                local targetPitch = ((pressedKeys.arrowup and 1 or 0) - (pressedKeys.arrowdown and 1 or 0)) * 65.0
                local yawStep, pitchStep
                turnVelocity.yaw, yawStep = DirectorMotion.damp(turnVelocity.yaw, targetYaw, deltaSeconds, Config.CameraLookResponse)
                turnVelocity.pitch, pitchStep = DirectorMotion.damp(turnVelocity.pitch, targetPitch, deltaSeconds, Config.CameraLookResponse)
                if targetYaw == 0.0 and math.abs(turnVelocity.yaw) < 0.0001 then turnVelocity.yaw = 0.0 end
                if targetPitch == 0.0 and math.abs(turnVelocity.pitch) < 0.0001 then turnVelocity.pitch = 0.0 end
                local mouseYaw = mouseLookX * Config.MouseLookSensitivity * preferences.sensitivity
                local mousePitch = mouseLookY * Config.MouseLookSensitivity * preferences.sensitivity * (preferences.invert and -1 or 1)
                mouseLookX, mouseLookY = 0.0, 0.0
                if yawStep ~= 0.0 or pitchStep ~= 0.0 or mouseYaw ~= 0.0 or mousePitch ~= 0.0 then
                SetCamRot(camera, (clamp(rotation.x + pitchStep - mousePitch, -89.0, 89.0)) + 0.0, (rotation.y) + 0.0, (wrapAngle(rotation.z + yawStep - mouseYaw)) + 0.0, 2)
                end
                end
                if dragSession then sceneDragUpdate(deltaSeconds) end
                -- Target mode must still follow a moving subject while camera input is idle.
                if select(1,rigAtTime(playhead)).mode ~= 'manual' then applyCameraRig(playhead, getCameraState()) end
            end

            local now = GetGameTimer()
            if not captureMode and not DirectorModelBrowser.active and now - lastUiUpdate >= (Config.UiUpdateIntervalMs or 100) then
                lastUiUpdate = now
                local signature = ('%.3f:%s'):format(playhead,tostring(previewing))
                if signature ~= lastTransportPacket then
                    lastTransportPacket = signature
                    SendNUIMessage({ action = 'playhead', time = playhead, playing = previewing })
                end
                sendCameraState()
            end
            if not captureMode and not DirectorModelBrowser.active and now - lastActorScreenUpdate >= ((previewing or dragSession or routeDraft or next(pressedKeys)) and 33 or 150) then
                lastActorScreenUpdate = now
                sceneSendScreenPositions()
                if routeDraft then sendRouteScreen() end
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        restorePlayerView()
    end
end)

