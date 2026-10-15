window.DirectorEditor.initializeState = function initializeState(ctx) {
  ctx.state.resource =
    typeof GetParentResourceName === "function" ? GetParentResourceName() : "vanta_director_free";
  ctx.elements.root = document.getElementById("director");
  ctx.elements.keyframeList = document.getElementById("keyframeList");
  ctx.elements.markers = document.getElementById("markers");
  ctx.elements.trackLane = document.getElementById("trackLane");
  ctx.elements.actorTracks = document.getElementById("actorTracks");
  ctx.elements.scrubber = document.getElementById("timelineScrubber");
  ctx.elements.durationInput = document.getElementById("duration");
  ctx.elements.projectNameInput = document.getElementById("projectName");
  ctx.elements.statusMessage = document.getElementById("statusMessage");
  ctx.elements.toast = document.getElementById("toast");
  ctx.elements.exitOverlay = document.getElementById("exitOverlay");
  ctx.state.project = {
    name: "Untitled Project",
    duration: 20,
    playhead: 0,
    keyframes: [],
    actors: [],
    look: {},
  };
  ctx.state.camera = null;
  ctx.state.keyState = {};
  ctx.state.toastTimeout = null;
  ctx.state.nameTimeout = null;
  ctx.state.keySequence = 0;
  ctx.state.previewPlaying = false;
  ctx.state.playheadAnchorTime = 0;
  ctx.state.playheadAnchorClock = 0;
  ctx.state.animationScheduled = false;
  ctx.state.scrubbing = false;
  ctx.state.looking = false;
  ctx.state.lookDeltaX = 0;
  ctx.state.lookDeltaY = 0;
  ctx.state.lookScheduled = false;
  ctx.state.lastMouseX = null;
  ctx.state.lastMouseY = null;
  ctx.state.seekSequence = 0;
  ctx.state.timelineDrag = null;
  ctx.state.lastDragSeekAt = 0;
  ctx.state.bridgeReady = false;
  ctx.state.leftHeld = false;
  ctx.state.actorDragging = false;
  ctx.state.actorDragScheduled = false;
  ctx.state.actorDragSequence = 0;
  ctx.state.actorDragPointer = null;
  ctx.state.selectedActorId = null;
  ctx.state.selectedFrameTime = null;
  ctx.state.sceneTabActive = false;
  ctx.state.lookTabActive = false;
  ctx.state.saveDirty = false;
  ctx.state.savePending = false;
  ctx.state.savePendingTimeout = null;
  ctx.state.libraryState = { activeId: null, projects: [], limit: Infinity };
  ctx.state.libraryBusy = false;
  ctx.state.libraryWaitTimer = null;
  ctx.state.pendingLibraryConfirm = null;
  ctx.state.actorPinElements = new Map();
  ctx.state.mutatingCalls = new Set([
    "addRecordedGesture",
    "pasteTimeline",
    "saveLocation",
    "deleteLocation",
    "duplicateActors",
    "setActorGroup",
    "trimRecording",
    "createCameraShot",
    "updateCameraShot",
    "deleteCameraShot",
    "duplicateCameraShot",
    "applyCameraPreset",
    "addKeyframe",
    "deleteKeyframe",
    "moveKeyframe",
    "setDuration",
    "setProjectName",
    "addActor",
    "placeBrowserModel",
    "deleteActor",
    "setActorTransform",
    "endActorDrag",
    "addAction",
    "deleteAction",
    "moveAction",
    "editActionTiming",
    "applyPreset",
    "chainActions",
    "setKeyframeFov",
    "setKeyframeName",
    "setSceneLook",
    "setCameraRig",
    "commitRoute",
    "undo",
    "redo",
  ]);
  ctx.state.animationCatalog = window.VantaAnimations;
  ctx.state.animationActorId = null;
  ctx.state.animationSelectedId = ctx.state.animationCatalog[0].id;
  ctx.state.animationCategory = "All";
  ctx.state.animationPreviewActive = false;
  ctx.state.animationPreviewSequence = 0;
  ctx.state.animationAddPending = false;
  ctx.state.animationStorageKey = ctx.state.resource + ":animation-library:v1";
  ctx.state.animationIds = new Set(ctx.state.animationCatalog.map((item) => item.id));
  ctx.state.animationCategories = [
    "All",
    "Favorites",
    "Recent",
    ...new Set(ctx.state.animationCatalog.map((item) => item.category)),
  ];
  ctx.state.animationCategoryNames = {
    All: "Tout",
    Favorites: "Favoris",
    Recent: "Récents",
  };
  ctx.state.animationMemory = ctx.animations.readAnimationMemory();
  ctx.state.animationSearchIndex = new Map(
    ctx.state.animationCatalog.map((item) => [
      item.id,
      ctx.animations.animationSearchText(
        [
          item.name,
          item.english,
          item.category,
          item.description,
          item.tags,
          item.dict,
          item.clip,
          item.placement,
          ...item.props,
        ].join(" "),
      ),
    ]),
  );
  ctx.state.physicalKeys = {
    KeyW: "w",
    KeyA: "a",
    KeyS: "s",
    KeyD: "d",
    KeyQ: "q",
    KeyE: "e",
    ArrowLeft: "arrowleft",
    ArrowRight: "arrowright",
    ArrowUp: "arrowup",
    ArrowDown: "arrowdown",
    KeyK: "k",
    Escape: "escape",
  };
  ctx.state.hintIds = {
    KeyW: "forwardKeyLabel",
    KeyA: "leftKeyLabel",
    KeyQ: "lowerKeyLabel",
  };
  ctx.elements.libraryOverlay = document.getElementById("libraryOverlay");
  ctx.state.libraryPanel = ctx.elements.libraryOverlay.querySelector(".library-panel");
  ctx.elements.libraryList = document.getElementById("libraryList");
  ctx.elements.libraryConfirm = document.getElementById("libraryConfirm");
  ctx.elements.animationOverlay = document.getElementById("animationOverlay");
  ctx.elements.animationPreviewBar = document.getElementById("animationPreviewBar");
  ctx.elements.animationSearch = document.getElementById("animationSearch");
  ctx.elements.shotKind = document.getElementById("shotPreset");
  ctx.state.sessionInvitation = null;
  ctx.state.copiedSequence = null;
  ctx.state.timelineCopied = false;
  ctx.state.sessionRole = "none";
  ctx.state.timelineSelection = new Map();
  ctx.state.selectionKey = (item) =>
    item.kind + ":" + (item.id || item.index || item.actorId + ":" + item.actionId);
  ctx.state.inspectorSections = new Map();
  ctx.state.sceneModelNames = new Map();
  ctx.state.pendingAccessorySelection = null;
  ctx.state.actorRenderCache = new Map();
  ctx.state.inspectorSignature = "";
  ctx.state.trackRenderCache = new Map();
  ctx.elements.lookHour = document.getElementById("lookHour");
  ctx.elements.modelOverlay = document.getElementById("modelOverlay");
  ctx.state.modelCatalog = [];
  ctx.state.modelsLoaded = false;
  ctx.state.modelKind = "ped";
  ctx.state.modelPage = 0;
  ctx.state.modelSelection = null;
  ctx.state.modelSequence = 0;
  ctx.state.modelReady = false;
  ctx.state.modelPageSize = 60;
  ctx.state.modelFilterKey = null;
  ctx.state.modelMatches = [];
  ctx.state.modelPlacing = false;
  ctx.state.modelDrag = null;
  ctx.state.modelElevation = 12;
  ctx.state.modelViewScheduled = false;
  ctx.elements.modelViewport = document.getElementById("modelViewport");
  ctx.state.modelViewportObserver =
    typeof ResizeObserver === "function"
      ? new ResizeObserver(() => ctx.models.sendModelView())
      : null;
  ctx.elements.lookSurface = document.getElementById("lookSurface");
  ctx.state.recordingSourceFields = () => {
    const car = document.getElementById("motionRecordKind").value === "vehicle";
    document
      .getElementById("motionRecordOccupants")
      .closest("label")
      ?.classList.toggle("is-hidden", !car);
    document.getElementById("motionRecordAim").closest("label")?.classList.toggle("is-hidden", car);
  };
};
