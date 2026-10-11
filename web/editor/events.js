window.DirectorEditor.modules.events = function defineModule(ctx) {
  ctx.events = {};

  return function bindEvents() {
    window.addEventListener("message", (event) => {
      const data = event.data || {};
      if (data.action === "motionRecordStarted") {
        ctx.input.clearKeys();
        ctx.elements.root.classList.add("is-hidden");
        document.getElementById("motionRecordOverlay").classList.remove("is-hidden");
        document.getElementById("motionRecordClock").textContent = "00:00";
      }
      if (data.action === "motionRecordProgress")
        document.getElementById("motionRecordClock").textContent =
          ctx.formatting.formatTime(data.time) + " / " + Number(data.limit).toFixed(0) + "s";
      if (data.action === "motionRecordFinished") {
        document.getElementById("motionRecordOverlay").classList.add("is-hidden");
        ctx.elements.root.classList.remove("is-hidden");
        ctx.status.showStatus(data.message);
      }
      if (data.action === "close") {
        ctx.state.copiedSequence = null;
        ctx.state.timelineCopied = false;
        ctx.state.sessionRole = "none";
        ctx.sequences.updateContextControls();
        document.getElementById("motionRecordOverlay").classList.add("is-hidden");
        document.getElementById("sessionInviteOverlay").classList.add("is-hidden");
        document.getElementById("sessionBadge").classList.add("is-hidden");
      }
      if (data.action === "open") {
        ctx.elements.root.classList.remove("is-hidden");
        ctx.state.bridgeReady = true;
        ctx.elements.exitOverlay.classList.add("is-hidden");
        ctx.saving.setSavePending(false);
        ctx.input.clearKeys();
        ctx.state.saveDirty = false;
        document.getElementById("saveState").textContent = "Not saved yet";
        ctx.state.libraryState = { activeId: null, projects: [], limit: Infinity };
        ctx.library.renderLibrary();
      }
      if (data.action === "captureCountdown") {
        const countdown = document.getElementById("captureCountdown");
        ctx.elements.root.classList.add("is-hidden");
        ctx.input.clearKeys(false);
        countdown.classList.remove("is-hidden");
        let seconds = Number(data.seconds) || 3;
        countdown.textContent = `TAKE STARTS IN ${seconds}`;
        const timer = setInterval(() => {
          seconds -= 1;
          if (seconds <= 0 || countdown.classList.contains("is-hidden")) {
            clearInterval(timer);
          } else {
            countdown.textContent = `TAKE STARTS IN ${seconds}`;
          }
        }, 1000);
      }
      if (data.action === "captureGo") {
        document.getElementById("captureCountdown").classList.add("is-hidden");
      }
      if (data.action === "captureEnd") {
        document.getElementById("captureCountdown").classList.add("is-hidden");
        ctx.elements.root.classList.remove("is-hidden");
        ctx.state.selectedFrameTime = null;
        ctx.projectView.renderProject();
      }
      if (data.action === "requestClose") ctx.lifecycle.requestClose();
      if (data.action === "close") {
        ctx.models.closeModels(false);
        ctx.state.bridgeReady = false;
        ctx.elements.exitOverlay.classList.add("is-hidden");
        ctx.saving.setSavePending(false);
        ctx.elements.root.classList.add("is-hidden");
        document.getElementById("captureCountdown").classList.add("is-hidden");
        document.getElementById("actorPins").innerHTML = "";
        ctx.state.actorPinElements.clear();
        ctx.state.selectedActorId = null;
        ctx.state.timelineSelection.clear();
        ctx.timeline.updateTimelineSelection();
        ctx.state.previewPlaying = false;
        ctx.state.actorRenderCache.clear();
        ctx.state.trackRenderCache.clear();
        ctx.state.inspectorSignature = "";
        document.getElementById("actorList").innerHTML = "";
        ctx.elements.actorTracks.innerHTML = "";
        ctx.state.selectedFrameTime = null;
        ctx.state.looking = false;
        ctx.state.leftHeld = ctx.state.actorDragging = false;
        ctx.status.setLookHint(null);
        ctx.state.lookDeltaX = ctx.state.lookDeltaY = 0;
        ctx.input.clearKeys(false);
        ctx.library.setLibraryBusy(false);
        ctx.library.closeLibrary();
        ctx.elements.animationOverlay.classList.add("is-hidden");
        ctx.elements.animationPreviewBar.classList.add("is-hidden");
        ctx.state.animationPreviewSequence++;
        ctx.state.animationPreviewActive = false;
        ctx.state.animationActorId = null;
      }
      if (data.action === "modelCatalog") {
        if (data.append !== true) {
          ctx.state.modelCatalog = [];
          ctx.state.sceneModelNames.clear();
        }
        const chunk = (Array.isArray(data.models) ? data.models : []).map((item) => ({
          ...item,
          search: (item.label + " " + item.model + " " + item.category).toLowerCase(),
        }));
        for (const item of chunk) {
          ctx.state.modelCatalog.push(item);
          ctx.state.sceneModelNames.set(item.model, item.label);
        }
        ctx.state.modelsLoaded = data.complete !== false;
        ctx.state.modelFilterKey = null;
        if (ctx.state.modelsLoaded) {
          ctx.models.renderModelCategories();
          ctx.models.renderModels();
          ctx.actors.renderActors();
        } else if (data.append !== true) {
          ctx.models.renderModelCategories();
          ctx.models.renderModels();
        }
      }
      if (data.action === "sessionInvite") {
        ctx.state.sessionInvitation = data.id;
        document.getElementById("sessionInviteText").textContent =
          data.name + " invites you to a filming session.";
        document.getElementById("sessionInviteOverlay").classList.remove("is-hidden");
      }
      if (data.action === "sessionState") {
        ctx.state.copiedSequence = null;
        ctx.state.timelineCopied = false;
        ctx.state.sessionRole = data.role || "none";
        ctx.sequences.updateContextControls();
        document.getElementById("sessionBadge").classList.toggle("is-hidden", data.role === "none");
        document.getElementById("sessionBadge").textContent =
          data.role === "viewer" ? "SESSION / VIEWER" : "SESSION / HOST";
        document.getElementById("sessionRole").textContent =
          data.role === "none" ? "SOLO" : data.role.toUpperCase();
        document.getElementById("sessionHint").textContent =
          data.role === "viewer"
            ? "Viewing the host’s scene. Only the host can publish edits or start shared playback."
            : data.role === "host"
              ? "Publish after editing, then play together once all participants have loaded."
              : "Host a scene and invite participants by server ID.";
      }
      if (data.action === "project" && data.project) {
        ctx.state.project = {
          ...ctx.state.project,
          ...data.project,
          keyframes: Array.isArray(data.project.keyframes) ? data.project.keyframes : [],
          actors: Array.isArray(data.project.actors) ? data.project.actors : [],
        };
        for (const [key, item] of ctx.state.timelineSelection) {
          const current =
            item.kind === "action"
              ? ctx.state.project.actors
                  .find((a) => a.id === item.actorId)
                  ?.actions.find((a) => a.id === item.actionId)
              : item.kind === "camera"
                ? ctx.state.project.keyframes[item.index - 1]
                : item.kind === "shot"
                  ? ctx.state.project.cameraShots?.find((s) => s.id === item.id)
                  : null;
          if (!current || (item.kind === "camera" && current.time !== item.time))
            ctx.state.timelineSelection.delete(key);
          else
            ctx.state.timelineSelection.set(key, {
              ...item,
              time: current.time,
              duration: current.duration,
            });
        }
        ctx.timeline.updateTimelineSelection();
        if (ctx.state.selectedFrameTime !== null && !ctx.camera.selectedFrame())
          ctx.state.selectedFrameTime = null;
        ctx.projectView.renderProject();
        ctx.environment.renderLook();
      }
      if (data.action === "library") {
        const previousId = ctx.state.libraryState.activeId;
        ctx.state.libraryState = {
          activeId: data.activeId,
          projects: Array.isArray(data.projects) ? data.projects : [],
          limit: Number(data.limit) || Infinity,
        };
        if (previousId !== data.activeId) {
          ctx.state.timelineSelection.clear();
          ctx.timeline.updateTimelineSelection();
          ctx.state.copiedSequence = null;
          ctx.state.timelineCopied = false;
          ctx.models.closeModels(false);
          ctx.saving.setSavePending(false);
          ctx.animations.closeAnimationCatalog();
          ctx.state.selectedActorId = null;
          ctx.state.selectedFrameTime = null;
          ctx.projectView.renderProject();
        }
        ctx.library.renderLibrary();
        ctx.library.setLibraryBusy(false);
        if (
          previousId !== data.activeId &&
          !ctx.elements.libraryOverlay.classList.contains("is-hidden")
        )
          ctx.library.closeLibrary();
        if (data.show) ctx.elements.libraryOverlay.classList.remove("is-hidden");
      }
      if (data.action === "libraryError") {
        ctx.library.setLibraryBusy(false);
        ctx.status.showStatus(data.message);
      }
      if (data.action === "saveState") ctx.saving.setSaveState(Boolean(data.saved));
      if (data.action === "saveResult") {
        ctx.saving.setSavePending(false);
        if (!data.ok || data.stale) ctx.saving.setSaveState(false);
      }
      if (data.action === "tab")
        ctx.tabs.selectSceneTab(data.scene === "look" ? "look" : Boolean(data.scene));
      if (data.action === "animationCatalog")
        ctx.animations.openAnimationCatalog(Number(data.actorId));
      if (data.action === "animationPreviewStopped") {
        ctx.state.animationPreviewActive = false;
        if (!ctx.elements.animationPreviewBar.classList.contains("is-hidden"))
          document.getElementById("animationBarStatus").textContent =
            "Aperçu arrêté. La scène est restaurée au curseur.";
      }
      if (data.action === "actors") {
        ctx.state.project.actors = Array.isArray(data.actors) ? data.actors : [];
        if (
          ctx.state.pendingAccessorySelection &&
          ctx.state.project.actors.some((a) => a.id === ctx.state.pendingAccessorySelection)
        ) {
          ctx.state.selectedActorId = ctx.state.pendingAccessorySelection;
          ctx.state.pendingAccessorySelection = null;
        }
        ctx.camera.renderCameraRig();
        ctx.actors.renderActors();
      }
      if (data.action === "actorScreen") {
        if (data.selectedId != null && data.selectedId !== ctx.state.selectedActorId) {
          ctx.state.selectedActorId = data.selectedId;
          ctx.actors.renderActors();
        }
        ctx.pins.renderActorPins(Array.isArray(data.positions) ? data.positions : []);
      }
      if (data.action === "camera") {
        ctx.state.camera = data.camera;
        if (!ctx.camera.selectedFrame()) ctx.camera.renderCamera();
      }
      if (data.action === "playhead") {
        if (!ctx.state.timelineDrag) ctx.state.project.playhead = Number(data.time) || 0;
        ctx.state.previewPlaying = Boolean(data.playing);
        ctx.state.playheadAnchorTime = ctx.state.project.playhead;
        ctx.state.playheadAnchorClock = performance.now();
        if (!ctx.state.scrubbing && !ctx.state.timelineDrag)
          ctx.timeline.renderPlayhead(ctx.state.project.playhead);
        if (window.VantaVisual?.setPlaying) window.VantaVisual.setPlaying(ctx.state.previewPlaying);
        else
          document.getElementById("previewButton").textContent = ctx.state.previewPlaying
            ? "Ⅱ"
            : "▶";
        if (ctx.state.previewPlaying && !ctx.state.animationScheduled) {
          ctx.state.animationScheduled = true;
          requestAnimationFrame(ctx.timeline.animatePlayhead);
        }
      }
      if (data.action === "previewStarted") {
        if (window.VantaVisual?.setPlaying) window.VantaVisual.setPlaying(true);
        else document.getElementById("previewButton").textContent = "Ⅱ";
      }
      if (data.action === "status") ctx.status.showStatus(data.message);
    });
  };
};
