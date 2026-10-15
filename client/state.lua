DirectorClient = { modules = {} }

-- One editor session; model entities and projects keep their existing lifetimes.
function DirectorClient.newState()
    local editorState = {}
    editorState.camera = nil
    editorState.directorOpen = false
    editorState.nuiReady, editorState.nuiOpenSerial = false, 0
    editorState.routeRequestSerial = 0
    editorState.previewing = false
    editorState.captureMode = false
    editorState.captureToken = 0
    editorState.motionRecording = nil
    editorState.pressedKeys = {}
    editorState.preferences = DirectorPreferences.load()
    editorState.preferencesWrittenAt = -1000
    editorState.cameraSpeed = editorState.preferences.speed
    editorState.duration = Config.DefaultDuration
    editorState.playhead = 0.0
    editorState.keyframes = {}
    editorState.cameraShots = {}
    editorState.bookmarks = {}
    editorState.selectedShotId = nil
    editorState.projectName = "Untitled Project"
    editorState.currentProjectId = nil
    editorState.pendingSaveSnapshot = nil
    editorState.saveRequestSerial = 0
    editorState.pendingSaveRequest = nil
    editorState.lastUiUpdate = 0
    editorState.lastActorScreenUpdate = 0
    editorState.lastCameraPacket, editorState.lastActorPacket, editorState.lastTransportPacket = nil, nil, nil
    editorState.previewStartedAt = 0
    editorState.previewOffset = 0.0
    editorState.playbackRange = nil
    editorState.timelineClipboard = nil
    editorState.collaboration = nil
    editorState.collaborationBackup = nil
    editorState.sessionPendingPlayback = nil
    editorState.focusOwned = false
    editorState.lastStreamingFocusUpdate = 0
    editorState.sessionPlayer = nil
    editorState.movementVelocity = { x = 0.0, y = 0.0, z = 0.0 }
    editorState.turnVelocity = { pitch = 0.0, yaw = 0.0 }
    editorState.lastInputSequence = -1
    editorState.lastSeekSequence = -1
    editorState.lastInputAt = 0
    editorState.mouseLookX, editorState.mouseLookY = 0.0, 0.0
    editorState.sceneActors = {}
    editorState.sceneEntities = {}
    editorState.lastFocusUpdate = 0
    editorState.cameraRig = { mode = "manual" }
    editorState.shotPreview = nil
    editorState.selectedActorId = nil
    editorState.outlinedHandle = nil
    editorState.dragSession = nil
    editorState.routeDraft = nil
    editorState.history = DirectorHistory.new(40)
    editorState.historyBusy, editorState.editBusy = false, false
    editorState.dragBefore = nil
    editorState.lastDragSequence = -1
    editorState.sceneLook =
        { weather = "SERVER", hour = -1, minute = 0, dof = false, near = 2.0, far = 30.0, strength = 0.5 }
    editorState.weatherTypes = {
        SERVER = true,
        EXTRASUNNY = true,
        CLEAR = true,
        CLOUDS = true,
        OVERCAST = true,
        RAIN = true,
        THUNDER = true,
        FOGGY = true,
        SMOG = true,
        CLEARING = true,
    }
    editorState.lastLookUpdate = 0
    editorState.weatherOwned, editorState.clockOwned = false, false
    editorState.projectDialogBlur = false
    editorState.sceneGeneration = 0
    editorState.nextActorId = 1
    editorState.nextActionId = 1
    editorState.animationPreviewActor = nil
    editorState.animationPreviewToken = 0
    editorState.historyEdits = {
        addRecordedGesture = true,
        pasteTimeline = true,
        saveLocation = true,
        deleteLocation = true,
        duplicateActors = true,
        setActorGroup = true,
        trimRecording = true,
        createCameraShot = true,
        updateCameraShot = true,
        deleteCameraShot = true,
        duplicateCameraShot = true,
        applyCameraPreset = true,
        addAccessory = true,
        setAttachment = true,
        setActorAppearance = true,
        addKeyframe = true,
        deleteKeyframe = true,
        moveKeyframe = true,
        setDuration = true,
        setFov = true,
        setKeyframeFov = true,
        setKeyframeName = true,
        setProjectName = true,
        setSceneLook = true,
        setCameraRig = true,
        placeBrowserModel = true,
        addActor = true,
        deleteActor = true,
        setActorTransform = true,
        addAction = true,
        deleteAction = true,
        moveAction = true,
        editActionTiming = true,
        chainActions = true,
        applyPreset = true,
        commitRoute = true,
    }
    editorState.routeCommands = {
        addRoutePoint = true,
        beginRoutePoint = true,
        moveRoutePoint = true,
        endRoutePoint = true,
        deleteRoutePoint = true,
        cancelRoute = true,
        commitRoute = true,
    }
    editorState.recordModelCache = {}
    return editorState
end
