window.DirectorEditor.modules.sequences = function defineModule(ctx) {
  ctx.sequences = {};
  ctx.sequences.updateContextControls = function updateContextControls() {
    const viewer = ctx.state.sessionRole === "viewer",
      host = ctx.state.sessionRole === "host",
      shot = ctx.sequences.selectedSequence();
    const actor = ctx.state.project.actors.find((a) => a.id === ctx.state.selectedActorId);
    const recorded = actor?.actions?.some((a) => a.type === "recording");
    for (const [id, disabled] of Object.entries({
      sequenceCopy: !shot || viewer,
      sequenceDelete: !shot || viewer,
      sequenceUpdate: !shot || viewer,
      sequencePaste: !ctx.state.copiedSequence || viewer,
      timelineCopy: !ctx.state.timelineSelection.size || viewer,
      timelinePaste: !ctx.state.timelineCopied || viewer,
      stagingDuplicate: !ctx.staging.stagingIds().length || viewer,
      stagingGroupApply: !ctx.staging.stagingIds().length || viewer,
      recordingTrim: !recorded || viewer,
      recordedGestureAdd: !recorded || actor?.kind !== "ped" || viewer,
      sessionCreate: ctx.state.sessionRole !== "none",
      sessionInviteButton: !host,
      sessionPublish: !host,
      sessionPlay: !host,
      sessionStop: !host,
      sessionLeave: ctx.state.sessionRole === "none",
      saveButton: ctx.state.savePending || viewer,
    }))
      document.getElementById(id).disabled = disabled;
    ctx.elements.root.classList.toggle("session-viewer", viewer);
  };

  ctx.sequences.selectedSequence = function selectedSequence() {
    return (ctx.state.project.cameraShots || []).find(
      (s) => s.id === ctx.state.project.selectedShotId,
    );
  };

  ctx.sequences.renderSequences = function renderSequences() {
    const shots = ctx.state.project.cameraShots || [],
      list = document.getElementById("sequenceList");
    list.innerHTML = "";
    document.getElementById("sequenceCount").textContent = String(shots.length).padStart(2, "0");
    for (const [index, shot] of shots.entries()) {
      const button = document.createElement("button");
      button.className =
        "sequence-row" + (shot.id === ctx.state.project.selectedShotId ? " active" : "");
      button.title = shot.name;
      button.innerHTML =
        '<span class="sequence-number"></span><span class="sequence-info"><strong></strong><small></small></span><span class="sequence-length"></span>';
      button.querySelector(".sequence-number").textContent = String(index + 1).padStart(2, "0");
      button.querySelector("strong").textContent = shot.name;
      button.querySelector("small").textContent =
        { smooth: "Smooth path", linear: "Linear", easeInOut: "Ease in / out" }[shot.ease] +
        " · " +
        (shot.frames || []).length +
        " keys";
      button.querySelector(".sequence-length").textContent = shot.duration.toFixed(1) + "s";
      button.addEventListener("click", () => {
        ctx.state.selectedFrameTime = null;
        ctx.transport.post("selectCameraShot", { id: shot.id });
      });
      list.appendChild(button);
    }
    const shot = ctx.sequences.selectedSequence();
    document.getElementById("sequenceEdit").classList.toggle("is-hidden", !shot);
    if (shot)
      if (
        ![...document.getElementById("sequenceHandheld").options].some(
          (option) => Number(option.value) === (shot.handheld || 0),
        )
      ) {
        const option = document.createElement("option");
        option.value = shot.handheld;
        option.textContent = Math.round(shot.handheld * 100) + "%";
        document.getElementById("sequenceHandheld").appendChild(option);
      }
    if (shot)
      for (const [id, value] of Object.entries({
        sequenceName: shot.name,
        sequenceTime: shot.time,
        sequenceDuration: shot.duration,
        sequenceEase: shot.ease,
        sequenceBlend: shot.blend || 0,
        sequenceHandheld: shot.handheld || 0,
      })) {
        const el = document.getElementById(id);
        if (document.activeElement !== el) el.value = value;
      }
  };

  ctx.sequences.renderSequenceMarkers = function renderSequenceMarkers() {
    for (const shot of ctx.state.project.cameraShots || []) {
      const marker = document.createElement("button");
      marker.className =
        "camera-sequence" + (shot.id === ctx.state.project.selectedShotId ? " selected" : "");
      const name = document.createElement("span");
      name.className = "clip-name";
      name.textContent = shot.name;
      const length = document.createElement("small");
      length.textContent = shot.duration.toFixed(1) + "s";
      marker.append(name, length);
      marker.title = shot.name;
      marker.style.left = (shot.time / ctx.state.project.duration) * 100 + "%";
      marker.style.width = (shot.duration / ctx.state.project.duration) * 100 + "%";
      for (const edge of ["start", "end"]) {
        const handle = document.createElement("span");
        handle.className = "clip-handle " + edge;
        handle.dataset.edge = edge;
        handle.title = "Trim " + edge;
        marker.appendChild(handle);
      }
      marker.addEventListener("mousedown", (event) =>
        ctx.timeline.beginTimelineDrag(event, marker, ctx.elements.trackLane, {
          kind: "shot",
          id: shot.id,
          time: shot.time,
          duration: shot.duration,
          maxTime: ctx.state.project.duration - shot.duration,
        }),
      );
      ctx.elements.markers.appendChild(marker);
    }
  };
  return function bindEvents() {
    document
      .getElementById("newCameraSequence")
      .addEventListener("click", () => ctx.transport.post("createCameraShot", { duration: 6 }));

    document.getElementById("legacyCameraEdit").addEventListener("click", () => {
      ctx.state.selectedFrameTime = null;
      ctx.transport.post("selectCameraShot", { id: 0 });
    });

    document.getElementById("sequenceUpdate").addEventListener("click", () => {
      const shot = ctx.sequences.selectedSequence();
      if (shot)
        ctx.transport.post("updateCameraShot", {
          id: shot.id,
          name: document.getElementById("sequenceName").value,
          time: Number(document.getElementById("sequenceTime").value),
          duration: Number(document.getElementById("sequenceDuration").value),
          ease: document.getElementById("sequenceEase").value,
          blend: Number(document.getElementById("sequenceBlend").value),
          handheld: Number(document.getElementById("sequenceHandheld").value),
        });
    });

    document.getElementById("sequenceCopy").addEventListener("click", () => {
      ctx.state.copiedSequence = ctx.sequences.selectedSequence()?.id;
      ctx.sequences.updateContextControls();
      ctx.status.showStatus("Shot copied. Move the playhead to an empty interval, then paste.");
    });

    document.getElementById("sequencePaste").addEventListener("click", () => {
      if (ctx.state.copiedSequence)
        ctx.transport.post("duplicateCameraShot", {
          id: ctx.state.copiedSequence,
          time: ctx.state.project.playhead,
        });
    });

    document.getElementById("sequenceDelete").addEventListener("click", () => {
      const shot = ctx.sequences.selectedSequence();
      if (shot) ctx.transport.post("deleteCameraShot", { id: shot.id });
    });

    document.getElementById("timelineZoom").addEventListener("input", (event) => {
      const bounds = document.getElementById("timelineViewport").getBoundingClientRect();
      ctx.timeline.zoom(Number(event.target.value), bounds.left + bounds.width / 2);
    });
  };
};
