window.DirectorEditor.modules.camera = function defineModule(ctx) {
  ctx.camera = {};
  ctx.camera.selectedFrame = function selectedFrame() {
    return ctx.state.selectedFrameTime === null
      ? null
      : ctx.state.project.keyframes.find(
          (frame) => Math.abs(frame.time - ctx.state.selectedFrameTime) < 0.05,
        ) || null;
  };

  ctx.camera.selectCameraFrame = function selectCameraFrame(index) {
    const frame = ctx.state.project.keyframes[index];
    if (!frame) return;
    ctx.state.selectedFrameTime = frame.time;
    ctx.tabs.selectSceneTab(false);
    ctx.projectView.renderProject();
    ctx.timeline.seek(frame.time);
  };

  ctx.camera.updateRigFields = function updateRigFields() {
    const mode = document.getElementById("rigMode").value;
    document.getElementById("rigSubjectFields").classList.toggle("is-hidden", mode === "manual");
    document.getElementById("rigFollowFields").classList.toggle("is-hidden", mode !== "follow");
    document.getElementById("rigOrbitFields").classList.toggle("is-hidden", mode !== "orbit");
    const hints = {
      manual: "Move the camera freely or create a keyframe path.",
      target: "Keep the subject framed while moving freely or playing your keyframe path.",
      follow:
        "Apply from your current view to capture the distance and angle. Switch to Manual to reframe.",
      orbit:
        "Orbit uses the timeline time. Negative speed reverses direction. Switch to Manual to move freely.",
    };
    document.getElementById("rigHint").textContent = hints[mode] || hints.manual;
  };

  ctx.camera.renderCameraRig = function renderCameraRig() {
    const rig = ctx.state.project.cameraRig || { mode: "manual" };
    document.getElementById("rigMode").value = rig.mode;
    document.getElementById("rigBadge").textContent = rig.mode.toUpperCase();
    const target = document.getElementById("rigTarget");
    const previous = target.value;
    target.innerHTML = "";
    ctx.state.project.actors.forEach((actor) => {
      const option = document.createElement("option");
      option.value = actor.id;
      option.textContent = `${actor.kind.toUpperCase()} ${actor.id} · ${actor.model}`;
      target.appendChild(option);
    });
    target.value = String(rig.targetId || previous || ctx.state.project.actors[0]?.id || "");
    document.getElementById("rigHeight").value = rig.targetHeight ?? 1;
    document.getElementById("rigRadius").value = rig.radius ?? 8;
    document.getElementById("rigElevation").value = rig.elevation ?? 2;
    document.getElementById("rigSpeed").value = rig.speed ?? 15;
    document.getElementById("rigRelative").checked = rig.relative ?? true;
    document.getElementById("rigAvoidObstacles").checked = rig.avoidObstacles === true;
    ctx.camera.updateRigFields();
  };

  ctx.camera.renderShotSubjects = function renderShotSubjects() {
    const select = document.getElementById("shotSubject"),
      previous = select.value;
    select.innerHTML = "";
    const aim = document.createElement("option");
    aim.value = "0";
    aim.textContent = "Point at camera aim";
    select.appendChild(aim);
    ctx.state.project.actors.forEach((actor) => {
      const option = document.createElement("option");
      option.value = String(actor.id);
      option.textContent = actor.name || actor.model;
      option.dataset.i18nUser = "true";
      select.appendChild(option);
    });
    select.value = ctx.state.project.actors.some((actor) => String(actor.id) === previous)
      ? previous
      : "0";
  };

  ctx.camera.renderCamera = function renderCamera() {
    const frame = ctx.camera.selectedFrame();
    const display = frame || ctx.state.camera;
    const index = frame ? ctx.state.project.keyframes.indexOf(frame) : -1;
    if (!ctx.state.sceneTabActive) {
      ctx.status.setText(document.getElementById("inspectorEyebrow"), "INSPECTOR");
      document
        .getElementById("inspectorTitle")
        .toggleAttribute("data-i18n-user", Boolean(frame?.name));
      ctx.status.setText(
        document.getElementById("inspectorTitle"),
        frame ? frame.name || `Shot ${String(index + 1).padStart(2, "0")}` : "Live camera",
      );
    }
    document.getElementById("selectedCameraCard").classList[frame ? "remove" : "add"]("is-hidden");
    document.getElementById("shotNameField").classList[frame ? "remove" : "add"]("is-hidden");
    document
      .getElementById("selectedCameraActions")
      .classList[frame ? "remove" : "add"]("is-hidden");
    document
      .getElementById("liveTag")
      .classList[frame || ctx.state.sceneTabActive ? "add" : "remove"]("is-hidden");
    if (frame) {
      document.getElementById("selectedCameraName").textContent =
        frame.name || `Shot ${String(index + 1).padStart(2, "0")}`;
      document
        .getElementById("selectedCameraName")
        .toggleAttribute("data-i18n-user", Boolean(frame.name));
      document.getElementById("selectedCameraTime").textContent =
        `Keyframe at ${ctx.formatting.formatTime(frame.time)}`;
      if (document.activeElement !== document.getElementById("shotNameInput"))
        document.getElementById("shotNameInput").value = frame.name || "";
    }
    if (!display) return;
    for (const [id, value] of Object.entries({
      posX: display.x,
      posY: display.y,
      posZ: display.z,
      rotX: display.rx,
      rotY: display.ry,
      rotZ: display.rz,
    })) {
      ctx.status.setText(
        document.getElementById(id),
        Number.isFinite(Number(value)) ? Number(value).toFixed(2) : "—",
      );
    }
    const fov = Number.isFinite(Number(display.fov)) ? Math.round(display.fov) : 50;
    if (document.activeElement !== document.getElementById("fov")) {
      document.getElementById("fov").value = fov;
      ctx.status.setText(document.getElementById("fovValue"), `${fov}°`);
    }
  };
  return function bindEvents() {
    document.getElementById("rigMode").addEventListener("change", ctx.camera.updateRigFields);

    document.getElementById("rigApply").addEventListener("click", async () => {
      const mode = document.getElementById("rigMode").value;
      const targetId = Number(document.getElementById("rigTarget").value);
      if (mode !== "manual" && !ctx.state.project.actors.some((actor) => actor.id === targetId)) {
        ctx.status.showStatus("Place a subject in the scene first.");
        return;
      }
      const button = document.getElementById("rigApply");
      button.disabled = true;
      try {
        const result = await ctx.transport.post("setCameraRig", {
          mode,
          targetId,
          targetHeight: Number(document.getElementById("rigHeight").value),
          radius: Number(document.getElementById("rigRadius").value),
          elevation: Number(document.getElementById("rigElevation").value),
          speed: Number(document.getElementById("rigSpeed").value),
          relative: document.getElementById("rigRelative").checked,
          avoidObstacles: document.getElementById("rigAvoidObstacles").checked,
        });
        if (result.ok)
          ctx.status.showStatus(
            mode === "manual"
              ? "Manual camera restored."
              : "Automatic camera applied. Preview the timeline to see the shot.",
          );
      } finally {
        button.disabled = false;
      }
    });

    ctx.elements.shotKind.addEventListener("change", () => {
      document
        .getElementById("shotTravelField")
        .classList.toggle("is-hidden", ["orbit", "follow"].includes(ctx.elements.shotKind.value));
      document.getElementById("shotHint").textContent =
        ctx.elements.shotKind.value === "follow"
          ? "Tracks a moving scene actor inside this independent shot."
          : "Frames the subject’s current position. Check clearance in the preview; adjust the resulting keyframes freely.";
      document.getElementById("shotAdd").textContent =
        ctx.elements.shotKind.value === "follow" ? "Add Follow shot" : "Add at playhead";
    });

    for (const [id, call] of [
      ["shotPreview", "previewCameraPreset"],
      ["shotAdd", "applyCameraPreset"],
    ]) {
      document.getElementById(id).addEventListener("click", async () => {
        const button = document.getElementById(id);
        button.disabled = true;
        try {
          const result = await ctx.transport.post(call, {
            kind: ctx.elements.shotKind.value,
            targetId: Number(document.getElementById("shotSubject").value),
            seconds: Number(document.getElementById("shotSeconds").value),
            distance: Number(document.getElementById("shotDistance").value),
            height: Number(document.getElementById("shotHeight").value),
            travel: Number(document.getElementById("shotTravel").value),
          });
          if (result.ok) ctx.status.showStatus(result.message);
        } finally {
          button.disabled = false;
        }
      });
    }

    document
      .getElementById("shotCancel")
      .addEventListener("click", () => ctx.transport.post("cancelCameraPreset"));

    document.getElementById("locationSave").addEventListener("click", () =>
      ctx.transport.post("saveLocation", {
        name: document.getElementById("locationName").value || "Location",
      }),
    );

    document.getElementById("playbackRangeApply").addEventListener("click", () =>
      ctx.transport.post("setPlaybackRange", {
        first: Number(document.getElementById("playbackFirst").value),
        last: Number(document.getElementById("playbackLast").value),
        loop: document.getElementById("playbackLoop").checked,
      }),
    );

    document
      .getElementById("framingGuide")
      .addEventListener(
        "change",
        (event) =>
          (document.getElementById("framingOverlay").className =
            "framing-overlay " + event.target.value),
      );

    document.getElementById("lookFocusSubject").addEventListener("change", (event) =>
      ctx.transport.post("setSceneLook", {
        field: "focusId",
        value: Number(event.target.value),
      }),
    );

    document.getElementById("fov").addEventListener("input", (event) => {
      const value = Number(event.target.value);
      document.getElementById("fovValue").textContent = `${value}°`;
      ctx.transport.post("setFov", { fov: value });
    });

    document.getElementById("fov").addEventListener("change", async (event) => {
      const frame = ctx.camera.selectedFrame();
      if (!frame) return;
      const index = ctx.state.project.keyframes.indexOf(frame);
      const result = await ctx.transport.post("setKeyframeFov", {
        index: index + 1,
        fov: Number(event.target.value),
      });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not update field of view.");
    });

    document.getElementById("speed").addEventListener("input", (event) => {
      const value = Number(event.target.value);
      document.getElementById("speedValue").textContent = value.toFixed(1);
      ctx.transport.post("setSpeed", { speed: value });
    });
  };
};
