// UI composition only; existing Lua callbacks remain authoritative.
(() => {
  const q = (id) => document.getElementById(id);
  const icon = (path) =>
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' +
    path +
    '"/></svg>';
  const right = document.querySelector(".right-panel"),
    cameraPane = q("cameraInspector");
  right.append(q("lookPane"));
  const transform = document.createElement("details");
  transform.className = "camera-transform";
  transform.innerHTML = "<summary>Camera transform</summary>";
  const first = cameraPane.querySelector(".readout-section");
  let node = first;
  const moved = [];
  while (node && !node.classList.contains("control-block")) {
    moved.push(node);
    node = node.nextElementSibling;
  }
  moved.forEach((el) => transform.append(el));
  cameraPane.append(transform);
  const speedBlock = q("speed").closest(".control-block");
  cameraPane.insertBefore(speedBlock, q("automaticCamera"));
  q("advancedCamera").classList.add("is-hidden");
  const sequence = document.createElement("details");
  sequence.id = "sequenceInspector";
  sequence.className = "rig-panel";
  sequence.open = true;
  sequence.innerHTML = "<summary>Shot timing & motion</summary>";
  sequence.append(q("sequenceEdit"));
  cameraPane.insertBefore(sequence, cameraPane.firstChild);
  q("cameraSequencePanel").open = true;
  right.insertAdjacentHTML(
    "beforeend",
    '<div class="inspector-footer"><button id="primaryEdit" class="primary-button" type="button">Capture keyframe</button><button id="secondaryEdit" class="aim-button" type="button">Update from view</button></div>',
  );
  root.insertAdjacentHTML(
    "beforeend",
    '<div class="viewport-tools"><button id="foldLeft" title="Toggle scene browser" aria-label="Toggle scene browser">' +
      icon("M3 4h18v16H3zM8 4v16") +
      '</button><button id="foldRight" title="Toggle inspector" aria-label="Toggle inspector">' +
      icon("M3 4h18v16H3zM16 4v16") +
      '</button><button id="foldBoth" title="Expand game view" aria-label="Expand game view">' +
      icon("M8 3H3v5m13-5h5v5M3 16v5h5m8 0h5v-5") +
      "</button></div>",
  );
  const controls = [];
  for (const [id, unit, initial] of [
    ["fov", "°", 50],
    ["speed", "m/s", 8],
    ["lookNear", "m", 2],
    ["lookFar", "m", 30],
    ["lookStrength", "", 0.5],
  ]) {
    const range = q(id),
      label =
        range.closest(".control-block")?.querySelector(".control-label") ||
        range.closest("label");
    const factor = id === "lookStrength" ? 100 : 1;
    const box = document.createElement("input");
    box.type = "number";
    box.className = "precision-input";
    box.min = Number(range.min) * factor;
    box.max = Number(range.max) * factor;
    box.step = Number(range.step) * factor;
    box.value = Number(range.value) * factor;
    box.setAttribute("aria-label", id + " exact value");
    const suffix = document.createElement("span");
    suffix.className = "precision-unit";
    suffix.textContent = id === "lookStrength" ? "%" : unit;
    const reset = document.createElement("button");
    reset.className = "precision-reset";
    reset.type = "button";
    reset.title = "Reset " + id;
    reset.setAttribute("aria-label", "Reset " + id);
    reset.innerHTML = icon("m8 4-5 5 5 5M3 9h11a6 6 0 0 1 0 12");
    const output = label.querySelector("output") || label.querySelector("span");
    if (output) output.classList.add("is-hidden");
    if (label === range.closest("label")) {
      const wrapper = document.createElement("div");
      wrapper.className = "precision-row";
      label.insertBefore(wrapper, range);
      wrapper.append(box, suffix, reset);
    } else label.append(box, suffix, reset);
    const commit = () => {
      if (box.value.trim() === "" || !Number.isFinite(Number(box.value))) {
        box.value = Number(range.value) * factor;
        return;
      }
      range.value = Math.max(
        Number(range.min),
        Math.min(Number(range.max), Number(box.value) / factor),
      );
      box.value = Number(range.value) * factor;
      range.dispatchEvent(new Event("input", { bubbles: true }));
      range.dispatchEvent(new Event("change", { bubbles: true }));
    };
    box.addEventListener("change", commit);
    box.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        box.blur();
      }
    });
    reset.onclick = () => {
      box.value = initial * factor;
      commit();
    };
    range.addEventListener(
      "input",
      () => (box.value = Number(range.value) * factor),
    );
    controls.push({ range, box, factor });
  }
  function refresh() {
    const primary = q("primaryEdit"),
      secondary = q("secondaryEdit"),
      actor = project.actors.find((a) => a.id === selectedActorId);
    primary.textContent = lookTabActive
      ? "Reset look"
      : sceneTabActive
        ? "Add action"
        : "Capture keyframe";
    primary.disabled =
      sessionRole === "viewer" || (sceneTabActive && !actor) || savePending;
    secondary.classList.toggle(
      "is-hidden",
      lookTabActive || (!sceneTabActive && !selectedFrame()),
    );
    secondary.textContent = sceneTabActive
      ? "Place at aim"
      : "Update from view";
    secondary.disabled =
      sessionRole === "viewer" ||
      (sceneTabActive &&
        (!actor ||
          actor.attachment ||
          actor.actions?.some((a) => a.type === "recording")));
    if (lookTabActive) {
      q("inspectorTitle").textContent = "Scene look";
      q("liveTag").classList.add("is-hidden");
    }
    controls.forEach(({ range, box, factor }) => {
      const value = String(Number(range.value) * factor);
      if (document.activeElement !== box && box.value !== value)
        box.value = value;
      range.style.setProperty(
        "--range-fill",
        ((range.value - range.min) / (range.max - range.min)) * 100 + "%",
      );
    });
    q("sequenceInspector").classList.toggle("is-hidden", !selectedSequence());
    const prefs = window.VantaPreferences || {};
    document
      .querySelectorAll("#actorInspector .actor-transform input[type=number]")
      .forEach(
        (el) =>
          (el.step = el
            .closest("label")
            .matches(".actor-transform label:last-child")
            ? prefs.rotation || 1
            : prefs.move || 0.05),
      );
    updateFraming();
  }
  q("primaryEdit").onclick = async () => {
    if (lookTabActive) {
      for (const [field, value] of [
        ["weather", "SERVER"],
        ["hour", -1],
        ["dof", false],
      ]) {
        const r = await post("setSceneLook", { field, value });
        if (!r.ok) break;
      }
    } else if (sceneTabActive) {
      const section = [...q("actorInspector").querySelectorAll("details")].find(
        (el) =>
          el.dataset.sectionKey === "Actions" ||
          el.dataset.sectionKey?.startsWith("Scheduled actions"),
      );
      if (section) {
        section.open = true;
        section.scrollIntoView({ block: "nearest", behavior: "auto" });
      } else showStatus("Select a scene element with editable actions.");
    } else q("addKeyframeButton").click();
  };
  q("secondaryEdit").onclick = () => {
    if (sceneTabActive) {
      const button = q("actorInspector").querySelector(
        ".inspector-placement .aim-button",
      );
      button?.click();
    } else q("updateFrameButton").click();
  };
  function folded() {
    updateFraming();
    if (window.VantaPreferences?.workspace && bridgeReady) {
      clearTimeout(folded.timer);
      folded.timer = setTimeout(async () => {
        const p = {
          ...window.VantaPreferences,
          leftCollapsed: root.classList.contains("collapsed-left"),
          rightCollapsed: root.classList.contains("collapsed-right"),
        };
        const r = await post("setPreferences", { preferences: p });
        if (r.ok) {
          window.VantaPreferences = r.preferences;
          window.dispatchEvent(
            new CustomEvent("preferencesUpdated", { detail: r.preferences }),
          );
        }
      }, 650);
    }
  }
  q("foldLeft").onclick = () => {
    root.classList.toggle("collapsed-left");
    folded();
  };
  q("foldRight").onclick = () => {
    root.classList.toggle("collapsed-right");
    folded();
  };
  q("foldBoth").onclick = () => {
    const on =
      !root.classList.contains("collapsed-left") ||
      !root.classList.contains("collapsed-right");
    root.classList.toggle("collapsed-left", on);
    root.classList.toggle("collapsed-right", on);
    folded();
  };
  const grip = document.createElement("div");
  grip.className = "timeline-grip";
  grip.tabIndex = 0;
  grip.setAttribute("role", "separator");
  grip.setAttribute("aria-label", "Resize timeline");
  grip.setAttribute("aria-orientation", "horizontal");
  document.querySelector(".timeline").append(grip);
  let resize = null;
  grip.onpointerdown = (e) => {
    resize = {
      y: e.clientY,
      height: document.querySelector(".timeline").offsetHeight,
    };
    grip.setPointerCapture(e.pointerId);
  };
  grip.onpointermove = (e) => {
    if (resize) {
      root.style.setProperty(
        "--editor-bottom",
        Math.max(
          210,
          Math.min(innerHeight * 0.55, resize.height + resize.y - e.clientY),
        ) + "px",
      );
      updateFraming();
    }
  };
  grip.onpointerup = grip.onpointercancel = () => (resize = null);
  grip.onkeydown = (e) => {
    if (e.key === "ArrowUp" || e.key === "ArrowDown") {
      e.preventDefault();
      root.style.setProperty(
        "--editor-bottom",
        Math.max(
          210,
          Math.min(
            innerHeight * 0.55,
            document.querySelector(".timeline").offsetHeight +
              (e.key === "ArrowUp" ? 20 : -20),
          ),
        ) + "px",
      );
      updateFraming();
    }
  };
  q("keyframeLane").onmousedown = (e) => {
    if (e.target === q("keyframeLane")) beginSeekDrag(e, q("keyframeLane"));
  };
  window.VantaPolish = { render: refresh };
  window.addEventListener("directorPreferences", (e) => {
    const p = e.detail;
    root.classList.toggle("collapsed-left", p.workspace && p.leftCollapsed);
    root.classList.toggle("collapsed-right", p.workspace && p.rightCollapsed);
    q("forwardKeyLabel").textContent = p.layout === "qwerty" ? "W" : "Z";
    q("leftKeyLabel").textContent = p.layout === "qwerty" ? "A" : "Q";
    q("lowerKeyLabel").textContent = p.layout === "qwerty" ? "Q" : "A";
    refresh();
  });
  window.addEventListener("message", (e) => {
    const d = e.data || {};
    if (["project", "actors", "tab", "sessionState"].includes(d.action))
      refresh();
    if (d.action === "camera")
      controls.slice(0, 1).forEach(({ range, box }) => {
        if (document.activeElement !== box && box.value !== range.value)
          box.value = range.value;
      });
    if (d.action === "close") {
      clearTimeout(folded.timer);
      resize = null;
    }
  });
  refresh();
})();
