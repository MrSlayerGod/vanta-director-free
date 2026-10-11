/* The approved design's composition, connected to the existing editor controls. */
(() => {
  const q = (id) => document.getElementById(id);
  const paths = {
    camera:
      '<path d="M4 7h3l2-3h6l2 3h3v13H4z"/><circle cx="12" cy="13" r="4"/>',
    person:
      '<circle cx="12" cy="7" r="3"/><path d="M6 21v-5a6 6 0 0 1 12 0v5"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2"/>',
    film: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 3v18M17 3v18M3 8h4m-4 8h4m10-8h4m-4 8h4"/>',
    folder: '<path d="M3 5h7l2 3h9v12H3z"/>',
    save: '<path d="M4 3h13l3 3v15H4zM8 3v6h8V3M8 21v-7h8v7"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V4H4v12h4"/>',
    paste:
      '<path d="M8 5H4v16h16V5h-4"/><rect x="8" y="2" width="8" height="6" rx="2"/>',
    play: '<path d="m8 5 11 7-11 7z" fill="currentColor" stroke="none"/>',
    pause: '<path d="M8 5v14M16 5v14" stroke-width="4"/>',
    stop: '<rect x="7" y="7" width="10" height="10" rx="1" fill="currentColor" stroke="none"/>',
    skip: '<path d="M5 5v14m14-14L8 12l11 7z"/>',
    undo: '<path d="m8 4-5 5 5 5M3 9h11a6 6 0 0 1 0 12"/>',
    focus:
      '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m8 0h5v-5"/><circle cx="12" cy="12" r="3"/>',
    grid: '<rect x="3" y="3" width="18" height="18" rx="1"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  };
  const icon = (name) =>
    '<svg class="design-icon" viewBox="0 0 24 24" aria-hidden="true">' +
    paths[name] +
    "</svg>";
  const buttonContent = (id, name, label) => {
    q(id).innerHTML = icon(name) + (label ? "<span>" + label + "</span>" : "");
  };
  buttonContent("projectLibraryButton", "folder", "Projects");
  buttonContent("captureButton", "film", "Clean take");
  buttonContent("saveButton", "save", "Save project");
  buttonContent("closeButton", "close");
  buttonContent("cameraTab", "camera", "Camera");
  buttonContent("actorsTab", "person", "Scene");
  buttonContent("lookTab", "sun", "Atmosphere");
  buttonContent("timelineCopy", "copy", "Copy");
  buttonContent("timelinePaste", "paste", "Paste");
  buttonContent("stopButton", "stop");
  buttonContent("browseModelsButton", "plus", "Browse models");
  buttonContent("newCameraSequence", "plus", "Add camera shot");
  buttonContent("addKeyframeButton", "plus", "Add keyframe");
  q("addKeyframeButton").insertAdjacentHTML("beforeend", "<kbd>K</kbd>");
  q("cameraPane").querySelector("h1").textContent = "Camera sequences";
  q("actorsPane").querySelector("h2").textContent = "Actors & objects";
  const scene = q("actorsPane"),
    sceneListHeading = q("actorCount").closest(".list-heading");
  scene.querySelector(".panel-heading").append(q("actorCount"));
  sceneListHeading.classList.add("is-hidden");
  let sceneAnchor = q("browseModelsButton");
  for (const id of [
    "actorList",
    "emptyActors",
    "actorNote",
    "stagingTools",
    "motionRecordPanel",
    "actorCreate",
  ]) {
    sceneAnchor.after(q(id));
    sceneAnchor = q(id);
  }
  const leftTabs = document.querySelector(".scene-tabs"),
    right = document.querySelector(".right-panel");
  const tabs = document.createElement("nav");
  tabs.className = "inspector-tabs";
  tabs.setAttribute("aria-label", "Inspector views");
  tabs.innerHTML =
    '<button id="inspectorCameraTab" type="button">' +
    icon("camera") +
    "<span>Camera</span></button>";
  tabs.append(q("lookTab"));
  right.insertBefore(tabs, q("cameraInspector"));
  q("inspectorCameraTab").onclick = () => q("cameraTab").click();
  // Shot list first, then selected sequence and presets. Extra functions stay in disclosures.
  const pane = q("cameraPane"),
    heading = pane.querySelector(".panel-heading"),
    sequences = q("cameraSequencePanel");
  sequences.classList.add("sequence-browser");
  pane.insertBefore(sequences, heading.nextSibling);
  const advanced = document.createElement("details");
  advanced.className = "rig-panel keyframe-browser";
  advanced.innerHTML = "<summary>Keyframe list & original path</summary>";
  advanced.append(q("legacyCameraEdit"), q("keyframeList"));
  pane.append(advanced);
  const caption = document.createElement("div");
  caption.className = "selected-sequence-label";
  caption.innerHTML =
    '<span>Selected sequence</span><span id="selectedSequenceNumber">—</span>';
  pane.insertBefore(caption, q("addKeyframeButton"));
  const intro = pane.querySelector(".panel-intro");
  intro.textContent = "Move the camera, then capture its position.";
  pane.insertBefore(intro, q("addKeyframeButton"));
  q("shotLibrary").querySelector("summary").firstChild.textContent =
    "Shot presets ";
  // Motion/options are secondary to timing in the inspector.
  const timing = q("sequenceInspector");
  timing.className = "shot-timing-inspector";
  timing.querySelector("summary").textContent = "Shot timing";
  const edit = q("sequenceEdit"),
    name = q("sequenceName").closest("label"),
    grid = edit.querySelector(".rig-grid");
  const more = document.createElement("details");
  more.className = "rig-panel sequence-options";
  more.innerHTML = "<summary>Sequence settings</summary>";
  for (const child of [...edit.children])
    if (child !== grid && child !== q("sequenceUpdate")) more.append(child);
  edit.prepend(grid);
  more.append(q("sequenceUpdate"));
  q("shotLibrary").after(more);
  name.firstChild.textContent = "Shot name";
  edit.insertAdjacentHTML(
    "beforeend",
    '<p class="timing-note">Drag the clip or its edges to change timing.</p>',
  );
  for (const id of ["sequenceTime", "sequenceDuration"])
    q(id).addEventListener("change", () => q("sequenceUpdate").click());
  q("sequenceTime").closest("label").firstChild.textContent = "Start / seconds";
  q("sequenceDuration").closest("label").firstChild.textContent =
    "Length / seconds";
  const context = document.createElement("div");
  context.className = "shot-context";
  context.id = "shotContext";
  q("cameraInspector").prepend(context);
  const transform = q("cameraInspector").querySelector(".camera-transform");
  transform
    .querySelector("summary")
    .insertAdjacentHTML(
      "beforeend",
      '<span class="transform-meta">X · Y · Z</span>',
    );
  // Matching viewport toolbar; every action uses an existing functional control.
  const view = document.createElement("div");
  view.className = "view-caption";
  view.innerHTML =
    icon("camera") +
    '<span id="viewCaption">Live camera</span><span class="view-live">● LIVE</span>';
  root.append(view);
  const tools = document.querySelector(".viewport-tools");
  tools.insertAdjacentHTML(
    "afterbegin",
    '<button id="viewGrid" type="button" aria-label="Toggle framing guides" title="Framing guides" aria-pressed="false">' +
      icon("grid") +
      '</button><button id="viewSubject" type="button" aria-label="Keep selected subject framed" title="Keep selected subject framed">' +
      icon("focus") +
      "</button>",
  );
  buttonContent("foldLeft", "folder");
  buttonContent("foldRight", "person");
  buttonContent("foldBoth", "focus");
  q("viewGrid").onclick = () => {
    const select = q("framingGuide");
    select.value = select.value === "thirds" ? "none" : "thirds";
    select.dispatchEvent(new Event("change", { bubbles: true }));
    refresh();
  };
  q("viewSubject").onclick = () => {
    if (
      !project.actors.some((a) => a.id === selectedActorId) ||
      sessionRole === "viewer"
    )
      return;
    q("rigMode").value = "target";
    q("rigMode").dispatchEvent(new Event("change", { bubbles: true }));
    q("rigTarget").value = selectedActorId;
    q("rigApply").click();
  };
  q("lookHint").innerHTML =
    '<span data-view-hint><b>Right drag</b> Look</span><span data-view-hint><b id="viewMoveKeys">Z Q S D</b> Move</span><span data-view-hint><b>Shift + drag</b> Actor height</span><span id="viewDragHint" hidden></span>';
  const defaultHints = Array.from(
    q("lookHint").querySelectorAll("[data-view-hint]"),
  );
  const dragHint = q("viewDragHint");
  window.VantaViewHint = (message) => {
    defaultHints.forEach((el) => (el.hidden = Boolean(message)));
    dragHint.hidden = !message;
    dragHint.textContent = message || "";
  };
  // Transport icons and an actual seek-to-start control.
  const restart = document.createElement("button");
  restart.id = "timelineRestart";
  restart.type = "button";
  restart.setAttribute("aria-label", "Go to start");
  restart.title = "Go to start";
  restart.innerHTML = icon("skip");
  restart.onclick = () => seek(0);
  document.querySelector(".transport").prepend(restart);
  q("timeReadout").insertAdjacentHTML(
    "beforebegin",
    '<span class="transport-divider"></span>',
  );
  const duration = document.querySelector(".duration-control");
  duration.firstChild.textContent = "Duration ";
  duration.lastElementChild.textContent = "sec";
  document.querySelector(".timeline-zoom").firstChild.textContent = "Zoom";
  const cameraLabel = q("trackLane").previousElementSibling;
  cameraLabel.innerHTML =
    icon("camera") +
    '<span>CAMERA</span><span class="track-eye">' +
    icon("eye") +
    "</span>";
  q("keyframeLane").previousElementSibling.innerHTML =
    '<svg class="design-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 21 12 12 21 3 12z"/></svg><span>KEYFRAMES</span>';
  q("statusMessage").insertAdjacentHTML(
    "afterend",
    '<span class="timeline-legend"><span><i class="legend-clip"></i>Clip</span><span><i class="legend-key"></i>Keyframe</span><span><i class="legend-head"></i>Playhead</span></span>',
  );
  // Time of day: exact minute slider, retaining hour/minute controls and Server time.
  const hourField = q("lookHour").closest("label"),
    minuteField = q("lookMinute").closest("label");
  hourField.classList.add("time-source");
  minuteField.classList.add("time-minute");
  const timeField = document.createElement("div");
  timeField.className = "time-of-day";
  timeField.innerHTML =
    '<label for="lookTimeOfDay">Time of day <output id="lookTimeLabel">Server time</output></label><input id="lookTimeOfDay" type="range" min="0" max="1439" step="1" value="720"><div><span>00:00</span><button id="lookServerTime" type="button">Use server time</button><span>23:59</span></div>';
  hourField.after(timeField);
  q("lookTimeOfDay").oninput = () => timeDisplay();
  q("lookTimeOfDay").onchange = async () => {
    const value = Number(q("lookTimeOfDay").value);
    const response = await post("setSceneLook", {
      field: "hour",
      value: Math.floor(value / 60),
    });
    if (response.ok)
      await post("setSceneLook", { field: "minute", value: value % 60 });
  };
  q("lookServerTime").onclick = () =>
    post("setSceneLook", { field: "hour", value: -1 });
  const copy = q("lookPane").querySelector(".look-copy");
  copy.classList.add("is-hidden");
  // No telemetry observer: update only context, icons and changed values.
  function timeDisplay() {
    const range = q("lookTimeOfDay"),
      v = Number(range.value);
    setText(
      q("lookTimeLabel"),
      String(Math.floor(v / 60)).padStart(2, "0") +
        ":" +
        String(v % 60).padStart(2, "0"),
    );
    range.style.setProperty("--range-fill", (v / 1439) * 100 + "%");
  }
  let playing = null;
  function refresh() {
    const shot = selectedSequence(),
      actor = project.actors.find((a) => a.id === selectedActorId),
      prefs = window.VantaPreferences || {};
    leftTabs
      .querySelector("#cameraTab")
      .classList.toggle("active", !sceneTabActive);
    q("inspectorCameraTab").classList.toggle("active", !lookTabActive);
    q("lookTab").classList.toggle("active", lookTabActive);
    tabs.classList.toggle("is-hidden", sceneTabActive);
    setText(
      q("viewCaption"),
      shot
        ? shot.name +
            " / Camera " +
            String((project.cameraShots || []).indexOf(shot) + 1).padStart(
              2,
              "0",
            )
        : "Live camera",
    );
    setText(
      q("selectedSequenceNumber"),
      shot
        ? String((project.cameraShots || []).indexOf(shot) + 1).padStart(2, "0")
        : "—",
    );
    more.classList.toggle("is-hidden", !shot);
    setText(
      q("frameCount"),
      String((project.cameraShots || []).length).padStart(2, "0"),
    );
    setText(
      q("shotContext"),
      shot
        ? "Shot " +
            String((project.cameraShots || []).indexOf(shot) + 1).padStart(
              2,
              "0",
            ) +
            " · " +
            shot.time.toFixed(1) +
            "–" +
            (shot.time + shot.duration).toFixed(1) +
            " sec"
        : "Live camera · Capture a position to start",
    );
    if (!sceneTabActive) q("inspectorTitle").removeAttribute("data-i18n-user");
    if (!sceneTabActive)
      setText(
        q("inspectorTitle"),
        lookTabActive ? "Camera & scene look" : shot?.name || "Live camera",
      );
    setText(
      q("viewMoveKeys"),
      prefs.layout === "qwerty" ? "W A S D" : "Z Q S D",
    );
    q("viewGrid").setAttribute(
      "aria-pressed",
      String(q("framingGuide").value === "thirds"),
    );
    q("viewSubject").disabled = !actor || sessionRole === "viewer";
    for (const [id, name, label] of [
      [
        "primaryEdit",
        "plus",
        lookTabActive
          ? "Reset look"
          : sceneTabActive
            ? "Add action"
            : "Capture keyframe",
      ],
      ["secondaryEdit", sceneTabActive ? "focus" : "undo", ""],
    ]) {
      const button = q(id),
        signature = name + label;
      if (
        button.dataset.designContent !== signature ||
        !button.querySelector("svg")
      ) {
        buttonContent(id, name, label);
        button.dataset.designContent = signature;
      }
    }
    q("secondaryEdit").title = sceneTabActive
      ? "Place at camera aim"
      : "Update keyframe from view";
    q("secondaryEdit").setAttribute("aria-label", q("secondaryEdit").title);
    transport(previewPlaying);
    const hour = Number(project.look?.hour ?? -1);
    if (document.activeElement !== q("lookTimeOfDay")) {
      q("lookTimeOfDay").value =
        hour < 0 ? 720 : hour * 60 + Number(project.look?.minute || 0);
      timeDisplay();
      if (hour < 0) setText(q("lookTimeLabel"), "Server time");
    }
    q("lookTimeOfDay").disabled = q("lookServerTime").disabled =
      sessionRole === "viewer";
    // Newly built track labels get the matching type icon, once per project render.
    for (const label of q("actorTracks").querySelectorAll(
      ".track-name:not([data-styled])",
    )) {
      const text = label.textContent,
        kind = project.actors.find(
          (a) => Number(text.split(" ").at(-1)) === a.id,
        )?.kind;
      label.innerHTML =
        icon(
          kind === "vehicle" ? "film" : kind === "prop" ? "grid" : "person",
        ) +
        '<span></span><span class="track-eye">' +
        icon("eye") +
        "</span>";
      label.querySelector("span").textContent = text;
      label.dataset.styled = "true";
    }
    const transform = q("actorInspector").querySelector(".actor-transform");
    if (transform?.dataset.styled)
      transform.querySelector("input[type=range]").disabled =
        sessionRole === "viewer";
    if (transform && !transform.dataset.styled) {
      transform.dataset.styled = "true";
      const heading = transform.querySelector("label:last-child"),
        input = heading.querySelector("input");
      heading.classList.add("heading-control");
      const range = document.createElement("input");
      range.type = "range";
      range.min = 0;
      range.max = 360;
      range.step = prefs.rotation || 1;
      range.value = ((Number(input.value) % 360) + 360) % 360;
      range.setAttribute("aria-label", "Actor heading");
      const paint = () =>
        range.style.setProperty(
          "--range-fill",
          Number(range.value) / 3.6 + "%",
        );
      paint();
      range.disabled = input.disabled || sessionRole === "viewer";
      range.oninput = () => {
        input.value = Number(range.value).toFixed(1);
        paint();
      };
      range.onchange = () =>
        input.dispatchEvent(new Event("change", { bubbles: true }));
      input.addEventListener("change", () => {
        range.value = ((Number(input.value) % 360) + 360) % 360;
        paint();
      });
      heading.append(range);
    }
    root.classList.toggle("empty-scene-inspector", sceneTabActive && !actor);
  }
  function transport(on) {
    if (playing !== on || !q("previewButton").querySelector("svg")) {
      buttonContent("previewButton", on ? "pause" : "play");
      q("previewButton").setAttribute(
        "aria-label",
        on ? "Pause preview" : "Play preview",
      );
      playing = on;
    }
  }
  window.VantaVisual = { render: refresh, setPlaying: transport };
  const previous = window.VantaPolish.render;
  window.VantaPolish.render = () => {
    previous();
    refresh();
  };
  window.addEventListener("directorPreferences", refresh);
  window.addEventListener("message", (event) => {
    if (
      [
        "open",
        "project",
        "actors",
        "tab",
        "sessionState",
        "captureEnd",
      ].includes(event.data?.action)
    )
      refresh();
  });
  window.addEventListener("resize", updateFraming);
  refresh();
  updateFraming();
})();
