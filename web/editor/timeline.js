window.DirectorEditor.modules.timeline = function defineModule(ctx) {
  ctx.timeline = {};
  ctx.timeline.renderRuler = function renderRuler() {
    const max = Number(ctx.state.project.duration) || 20;
    const interval = max <= 30 ? 5 : max <= 90 ? 15 : max <= 300 ? 30 : max <= 1200 ? 120 : 600;
    const ticks = [];
    for (let value = 0; value <= max; value += interval) {
      ticks.push(
        `<span style="left:${(value / max) * 100}%">${ctx.formatting.formatTime(value).slice(0, 5)}</span>`,
      );
    }
    if (max % interval !== 0)
      ticks.push(`<span style="left:100%">${ctx.formatting.formatTime(max).slice(0, 5)}</span>`);
    document.getElementById("ruler").innerHTML = ticks.join("");
  };

  ctx.timeline.updateTimelineSelection = function updateTimelineSelection() {
    document.getElementById("timelineSelectionCount").textContent =
      ctx.state.timelineSelection.size + " SELECTED";
    ctx.sequences.updateContextControls();
  };

  ctx.timeline.renderTimelineTracks = function renderTimelineTracks() {
    const present = new Set(ctx.state.project.actors.map((a) => a.id));
    for (const [id, cached] of ctx.state.trackRenderCache)
      if (!present.has(id)) {
        cached.node.remove();
        ctx.state.trackRenderCache.delete(id);
      }
    let denseTimeline = false;
    ctx.state.project.actors.forEach((actor, actorIndex) => {
      const signature = JSON.stringify([
        actor.id,
        actor.kind,
        actor.model,
        actor.actions,
        ctx.state.project.duration,
      ]);
      const cached = ctx.state.trackRenderCache.get(actor.id);
      if (cached?.signature === signature) {
        ctx.actors.placeCached(ctx.elements.actorTracks, cached.node, actorIndex);
        denseTimeline ||= cached.dense;
        for (const [marker, key] of cached.markers)
          marker.classList.toggle("selected", ctx.state.timelineSelection.has(key));
        return;
      }
      if (cached) cached.node.remove();
      const track = document.createElement("div");
      track.className = "track-area";
      const label = document.createElement("div");
      label.className = "track-name";
      label.textContent = `${ctx.formatting.actorLabel(actor.kind, true)} ${actor.id}`;
      label.title = actor.model;
      const lane = document.createElement("div");
      lane.className = "track-lane";
      lane.addEventListener("mousedown", (event) => {
        if (event.target === lane) ctx.timeline.beginSeekDrag(event, lane);
      });
      const markerEntries = [];
      const cueStacks = new Map();
      let deepestStack = 1;
      (actor.actions || []).forEach((action) => {
        const marker = document.createElement("button");
        marker.className = `timeline-action ${action.type}${action.type === "visibility" ? (action.visible ? " show" : " hide") : ""}`;
        marker.classList.toggle(
          "selected",
          ctx.state.timelineSelection.has(
            ctx.state.selectionKey({
              kind: "action",
              actorId: actor.id,
              actionId: action.id,
            }),
          ),
        );
        marker.style.left = `${(action.time / ctx.state.project.duration) * 100}%`;
        const stackKey = Number(action.time).toFixed(1);
        const stack = cueStacks.get(stackKey) || 0;
        cueStacks.set(stackKey, stack + 1);
        deepestStack = Math.max(deepestStack, stack + 1);
        if (stack) marker.style.top = `${5 + stack * 20}px`;
        marker.title = `${ctx.formatting.actionLabel(action)} · ${ctx.formatting.formatTime(action.time)} · drag to retime`;
        if (
          action.type === "move" ||
          action.type === "lookAt" ||
          action.type === "enterVehicle" ||
          action.type === "exitVehicle" ||
          action.type === "recording" ||
          (action.type === "animation" && action.duration)
        ) {
          marker.style.width = `${Math.max(1, (action.duration / ctx.state.project.duration) * 100)}%`;
          marker.textContent =
            action.type === "animation"
              ? "ANIM"
              : action.type === "recording"
                ? "RECORD"
                : action.type === "enterVehicle"
                  ? "ENTER"
                  : action.type === "exitVehicle"
                    ? "EXIT"
                    : action.type === "lookAt"
                      ? "LOOK"
                      : action.points
                        ? "ROUTE"
                        : action.gait && action.gait !== "auto"
                          ? action.gait.toUpperCase()
                          : "MOVE";
        } else if (action.type === "visibility") {
          marker.textContent = action.visible ? "SHOW" : "HIDE";
        } else if (action.type === "engine" || action.type === "lights" || action.type === "door") {
          marker.textContent =
            action.type === "engine" ? "ENGINE" : action.type === "lights" ? "LIGHTS" : "DOOR";
        }
        marker.addEventListener("mousedown", (event) =>
          ctx.timeline.beginTimelineDrag(event, marker, lane, {
            kind: "action",
            actorId: actor.id,
            actionId: action.id,
            time: action.time,
            maxTime:
              action.type === "move" ||
              action.type === "lookAt" ||
              action.type === "recording" ||
              (action.type === "animation" && action.duration)
                ? Math.max(0, ctx.state.project.duration - action.duration)
                : ctx.state.project.duration,
          }),
        );
        markerEntries.push([
          marker,
          ctx.state.selectionKey({
            kind: "action",
            actorId: actor.id,
            actionId: action.id,
          }),
        ]);
        lane.appendChild(marker);
      });
      if (deepestStack > 1) {
        lane.style.height = `${10 + deepestStack * 20}px`;
        track.style.height = `${26 + deepestStack * 20}px`;
      }
      if (deepestStack > 2) denseTimeline = true;
      track.appendChild(label);
      track.appendChild(lane);
      ctx.state.trackRenderCache.set(actor.id, {
        node: track,
        signature,
        dense: deepestStack > 2,
        markers: markerEntries,
      });
      ctx.actors.placeCached(ctx.elements.actorTracks, track, actorIndex);
    });
    ctx.elements.root.classList.toggle("dense-timeline", denseTimeline);
  };

  ctx.timeline.timeFromPointer = function timeFromPointer(
    clientX,
    lane,
    maximum = ctx.state.project.duration,
  ) {
    const bounds = lane.getBoundingClientRect();
    const value = Math.max(
      0,
      Math.min(maximum, ((clientX - bounds.left) / bounds.width) * ctx.state.project.duration),
    );
    const step =
      window.VantaPreferences?.snap === false ? 0.01 : window.VantaPreferences?.interval || 0.1;
    return Math.min(maximum, Math.round(value / step) * step);
  };

  ctx.timeline.beginTimelineDrag = function beginTimelineDrag(event, marker, lane, item) {
    if (event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.ctrlKey || event.metaKey) {
      const key = ctx.state.selectionKey(item);
      if (ctx.state.timelineSelection.has(key)) ctx.state.timelineSelection.delete(key);
      else ctx.state.timelineSelection.set(key, item);
      marker.classList.toggle("selected", ctx.state.timelineSelection.has(key));
      ctx.timeline.updateTimelineSelection();
      return;
    }
    ctx.state.timelineDrag = {
      marker,
      lane,
      item,
      startX: event.clientX,
      time: item.time,
      moved: false,
      edge: event.target.closest("[data-edge]")?.dataset.edge,
    };
    if (ctx.state.timelineDrag.edge)
      ctx.state.timelineDrag.original = { time: item.time, duration: item.duration };
    marker.classList.add("selected");
  };

  ctx.timeline.beginSeekDrag = function beginSeekDrag(event, lane) {
    if (event.button !== 0) return;
    event.preventDefault();
    ctx.state.timelineDrag = {
      lane,
      seek: true,
      time: ctx.timeline.timeFromPointer(event.clientX, lane),
    };
    ctx.timeline.seek(ctx.state.timelineDrag.time);
  };

  ctx.timeline.renderPlayhead = function renderPlayhead(time) {
    const value = Math.max(0, Math.min(Number(ctx.state.project.duration), time));
    ctx.status.setText(document.getElementById("timeReadout"), ctx.formatting.formatTime(value));
    if (!ctx.state.scrubbing) ctx.elements.scrubber.value = value;
    document.getElementById("playheadLine").style.left =
      `calc(var(--track-label, 108px) + (100% - var(--track-label, 108px)) * ${value / ctx.state.project.duration})`;
  };

  ctx.timeline.animatePlayhead = function animatePlayhead(now) {
    ctx.state.animationScheduled = false;
    if (!ctx.state.previewPlaying || ctx.elements.root.classList.contains("is-hidden")) return;
    if (!ctx.state.scrubbing)
      ctx.timeline.renderPlayhead(
        ctx.state.playheadAnchorTime + (now - ctx.state.playheadAnchorClock) / 1000,
      );
    ctx.state.animationScheduled = true;
    requestAnimationFrame(ctx.timeline.animatePlayhead);
  };

  ctx.timeline.seek = async function seek(time) {
    const clamped = Math.max(0, Math.min(Number(ctx.state.project.duration), Number(time) || 0));
    if (
      ctx.state.selectedFrameTime !== null &&
      Math.abs(clamped - ctx.state.selectedFrameTime) > 0.05
    ) {
      ctx.state.selectedFrameTime = null;
      for (const row of ctx.elements.keyframeList.children) row.classList.remove("selected");
      ctx.camera.renderCamera();
    }
    ctx.state.project.playhead = clamped;
    ctx.timeline.renderPlayhead(clamped);
    await ctx.transport.post("setPlayhead", { time: clamped, sequence: ++ctx.state.seekSequence });
  };
  return function bindEvents() {
    document.getElementById("timelineCopy").addEventListener("click", async () => {
      const result = await ctx.transport.post("copyTimeline", {
        items: [...ctx.state.timelineSelection.values()],
      });
      if (result.ok) {
        ctx.state.timelineCopied = true;
        ctx.sequences.updateContextControls();
        ctx.status.showStatus(result.message || "Selection copied.");
      }
    });

    document
      .getElementById("timelinePaste")
      .addEventListener("click", () => ctx.transport.post("pasteTimeline"));

    document
      .getElementById("stagingSelection")
      .addEventListener("change", ctx.sequences.updateContextControls);

    window.addEventListener("mousemove", (event) => {
      if (!ctx.state.timelineDrag) return;
      if (!(event.buttons & 1)) return;
      const drag = ctx.state.timelineDrag;
      const maximum = drag.item
        ? (drag.item.maxTime ?? ctx.state.project.duration)
        : ctx.state.project.duration;
      drag.time = ctx.timeline.timeFromPointer(event.clientX, drag.lane, maximum);
      if (drag.seek) {
        const now = performance.now();
        if (now - ctx.state.lastDragSeekAt >= 40) {
          ctx.state.lastDragSeekAt = now;
          ctx.timeline.seek(drag.time);
        }
      } else {
        drag.moved ||= Math.abs(event.clientX - drag.startX) > 3;
        if (drag.edge) {
          const end = drag.original.time + drag.original.duration;
          if (drag.edge === "start") {
            drag.time = Math.min(end - 0.1, drag.time);
            drag.item.duration = end - drag.time;
          } else {
            drag.item.duration = Math.max(
              0.1,
              ctx.timeline.timeFromPointer(event.clientX, drag.lane) - drag.original.time,
            );
            drag.time = drag.original.time;
          }
          drag.marker.style.width = (drag.item.duration / ctx.state.project.duration) * 100 + "%";
        }
        drag.marker.style.left = `${(drag.time / ctx.state.project.duration) * 100}%`;
        ctx.timeline.renderPlayhead(drag.time);
      }
    });

    window.addEventListener("mouseup", async (event) => {
      if (!ctx.state.timelineDrag || event.button !== 0) return;
      const drag = ctx.state.timelineDrag;
      ctx.state.timelineDrag = null;
      if (drag.seek) return ctx.timeline.seek(drag.time);
      drag.marker.classList.remove("selected");
      if (!drag.moved) {
        if (drag.item.kind === "shot")
          return ctx.transport.post("selectCameraShot", { id: drag.item.id });
        if (drag.item.kind === "camera") return ctx.camera.selectCameraFrame(drag.item.index - 1);
        ctx.state.selectedActorId = drag.item.actorId;
        ctx.transport.post("selectActor", { id: ctx.state.selectedActorId });
        ctx.tabs.selectSceneTab(true);
        return ctx.timeline.seek(drag.item.time);
      }
      const result =
        drag.item.kind === "shot"
          ? await ctx.transport.post("updateCameraShot", {
              id: drag.item.id,
              time: drag.time,
              duration: drag.item.duration,
            })
          : drag.item.kind === "camera"
            ? await ctx.transport.post("moveKeyframe", {
                index: drag.item.index,
                time: drag.time,
              })
            : await ctx.transport.post("moveAction", {
                actorId: drag.item.actorId,
                actionId: drag.item.actionId,
                time: drag.time,
              });
      if (!result.ok) {
        ctx.status.showStatus(result.message || "Could not move timeline item.");
        ctx.projectView.renderProject();
      } else {
        if (drag.item.kind === "camera") {
          ctx.state.selectedFrameTime = drag.time;
          ctx.projectView.renderProject();
        }
        ctx.timeline.seek(drag.time);
      }
    });

    ctx.elements.scrubber.addEventListener("input", () => {
      ctx.state.scrubbing = true;
      ctx.state.project.playhead = Number(ctx.elements.scrubber.value);
      ctx.timeline.renderPlayhead(ctx.state.project.playhead);
    });

    ctx.elements.scrubber.addEventListener("change", () => {
      ctx.state.scrubbing = false;
      ctx.timeline.seek(ctx.elements.scrubber.value);
    });

    ctx.elements.durationInput.addEventListener("change", async () => {
      const value = Math.max(
        Number(ctx.elements.durationInput.min) || 1,
        Math.min(
          Number(ctx.elements.durationInput.max) || 300,
          Number(ctx.elements.durationInput.value) ||
            window.VantaRuntimeConfig?.defaultDuration ||
            20,
        ),
      );
      const result = await ctx.transport.post("setDuration", { duration: value });
      if (result.ok) ctx.state.project.duration = value;
      ctx.projectView.renderProject();
    });

    ctx.elements.trackLane.addEventListener("mousedown", (event) => {
      if (event.target === ctx.elements.trackLane)
        ctx.timeline.beginSeekDrag(event, ctx.elements.trackLane);
    });
  };
};
