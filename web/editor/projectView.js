window.DirectorEditor.modules.projectView = function defineModule(ctx) {
  ctx.projectView = {};
  ctx.projectView.renderProject = function renderProject() {
    ctx.production.renderProduction();
    ctx.sequences.renderSequences();
    ctx.camera.renderShotSubjects();
    ctx.camera.renderCameraRig();
    if (document.activeElement !== ctx.elements.projectNameInput)
      ctx.elements.projectNameInput.value = ctx.state.project.name || "Untitled Project";
    if (document.activeElement !== ctx.elements.durationInput)
      ctx.elements.durationInput.value = Number(ctx.state.project.duration).toFixed(0);
    document.getElementById("durationReadout").textContent = ctx.formatting.formatTime(
      ctx.state.project.duration,
    );
    document.getElementById("frameCount").textContent = String(
      ctx.state.project.keyframes.length,
    ).padStart(2, "0");
    document
      .getElementById("emptyCamera")
      .classList.toggle("is-hidden", ctx.state.project.keyframes.length > 0);
    document
      .getElementById("cameraNote")
      .classList.toggle("is-hidden", ctx.state.project.keyframes.length === 0);
    ctx.elements.scrubber.max = ctx.state.project.duration;
    ctx.elements.scrubber.value = Math.min(ctx.state.project.playhead, ctx.state.project.duration);
    document.getElementById("timeReadout").textContent = ctx.formatting.formatTime(
      ctx.state.project.playhead,
    );
    ctx.timeline.renderRuler();

    ctx.elements.keyframeList.innerHTML = "";
    ctx.elements.markers.innerHTML = "";
    document.getElementById("keyMarkers").innerHTML = "";
    ctx.state.project.keyframes.forEach((frame, index) => {
      const row = document.createElement("div");
      row.className = "keyframe-row";
      if (
        ctx.state.selectedFrameTime !== null &&
        Math.abs(frame.time - ctx.state.selectedFrameTime) < 0.05
      )
        row.classList.add("selected");
      row.innerHTML = `<span class="frame-index">${String(index + 1).padStart(2, "0")}</span><span class="frame-meta"><strong></strong><small>FOV ${Number(frame.fov).toFixed(0)}°</small></span><span class="frame-time">${ctx.formatting.formatTime(frame.time)}</span><button class="delete-frame" title="Delete keyframe" aria-label="Delete keyframe">×</button>`;
      row.querySelector("strong").textContent =
        frame.name || `Shot ${String(index + 1).padStart(2, "0")}`;
      if (frame.name) row.querySelector("strong").dataset.i18nUser = "true";
      row.addEventListener("click", (event) => {
        if (event.target.closest(".delete-frame")) return;
        ctx.camera.selectCameraFrame(index);
      });
      row.querySelector(".delete-frame").addEventListener("click", () => {
        if (
          ctx.state.selectedFrameTime !== null &&
          Math.abs(frame.time - ctx.state.selectedFrameTime) < 0.05
        )
          ctx.state.selectedFrameTime = null;
        ctx.transport.post("deleteKeyframe", { index: index + 1 });
      });
      ctx.elements.keyframeList.appendChild(row);

      const marker = document.createElement("button");
      marker.className = "timeline-marker";
      marker.classList.toggle(
        "selected",
        ctx.state.timelineSelection.has(
          ctx.state.selectionKey({ kind: "camera", index: index + 1 }),
        ),
      );
      marker.style.left = `${(frame.time / ctx.state.project.duration) * 100}%`;
      marker.title = `Keyframe ${index + 1} · ${ctx.formatting.formatTime(frame.time)}`;
      marker.addEventListener("mousedown", (event) =>
        ctx.timeline.beginTimelineDrag(event, marker, document.getElementById("keyframeLane"), {
          kind: "camera",
          index: index + 1,
          time: frame.time,
        }),
      );
      document.getElementById("keyMarkers").appendChild(marker);
    });
    ctx.sequences.renderSequenceMarkers();
    ctx.timeline.renderPlayhead(ctx.state.project.playhead);
    document.getElementById("pathBar").style.width =
      ctx.state.project.cameraRig?.mode && ctx.state.project.cameraRig.mode !== "manual"
        ? "100%"
        : `${(Math.max(...ctx.state.project.keyframes.map((frame) => frame.time), 0) / ctx.state.project.duration) * 100}%`;
    ctx.actors.renderActors();
    ctx.camera.renderCamera();
    ctx.production.updateFraming();
    window.VantaVisual?.render();
    window.VantaWorkflow?.render();
  };
  return function bindEvents() {};
};
