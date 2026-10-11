// Personal preferences: persisted through the validated FiveM bridge.
(() => {
  const q = (s) => document.querySelector(s),
    qa = (s) => [...document.querySelectorAll(s)];
  const paths = {
    chevron: '<path d="m6 9 6 6 6-6"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    undo: '<path d="m8 4-5 5 5 5M3 9h11a6 6 0 0 1 0 12"/>',
    camera:
      '<rect x="3" y="6" width="18" height="15" rx="2"/><circle cx="12" cy="13" r="4"/>',
    grid: '<rect x="3" y="3" width="18" height="18"/><path d="M9 3v18M15 3v18M3 9h18M3 15h18"/>',
    film: '<rect x="3" y="3" width="18" height="18"/><path d="M7 3v18M17 3v18M3 8h4m-4 8h4m10-8h4m-4 8h4"/>',
    save: '<path d="M4 3h13l3 3v15H4zM8 3v6h8V3M8 21v-7h8v7"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7v1"/>',
  };
  const icon = (name) =>
    '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">' +
    paths[name] +
    "</svg>";
  const gear =
    '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 3-1 3-3 1-2 3 2 2v3l3 2 1 4h6l1-4 3-2v-3l2-2-2-3-3-1-1-3z"/><circle cx="12" cy="12" r="3"/></svg>';
  q(".top-actions").insertAdjacentHTML(
    "afterbegin",
    '<button class="btn square subtle settings-trigger" id="open-settings" aria-label="Open settings" aria-haspopup="dialog" aria-expanded="false" title="Settings">' +
      gear +
      "</button>",
  );
  const dropdown = (id, options) =>
    '<div class="setting-control"><details class="dropdown" id="pref-' +
    id +
    '"><summary><span>' +
    options[0] +
    "</span>" +
    icon("chevron") +
    '</summary><div class="menu">' +
    options
      .map(
        (v, i) =>
          '<button type="button" class="' +
          (i === 0 ? "chosen" : "") +
          '">' +
          v +
          "</button>",
      )
      .join("") +
    "</div></details></div>";
  const slider = (id, value, min, max, step, unit) =>
    '<div class="setting-control"><div class="metric"><input type="number" id="pref-' +
    id +
    '-number" aria-label="' +
    id +
    ' exact value" value="' +
    value +
    '" min="' +
    min +
    '" max="' +
    max +
    '" step="' +
    step +
    '"><span>' +
    unit +
    '</span></div><input class="range" id="pref-' +
    id +
    '" aria-label="' +
    id +
    '" type="range" value="' +
    value +
    '" min="' +
    min +
    '" max="' +
    max +
    '" step="' +
    step +
    '" data-unit="' +
    unit +
    '"></div>';
  const toggle = (id, on, label) =>
    '<button class="switch" id="pref-' +
    id +
    '" type="button" role="switch" aria-label="' +
    label +
    '" aria-checked="' +
    on +
    '"></button>';
  const row = (title, subtitle, control) =>
    '<div class="setting-row"><div class="setting-label"><strong>' +
    title +
    "</strong><small>" +
    subtitle +
    "</small></div>" +
    control +
    "</div>";
  const note = (text) =>
    '<div class="setting-note">' +
    icon("info") +
    "<span>" +
    text +
    "</span></div>";
  const tabs = [
    ["controls", "Controls", "camera"],
    ["interface", "Interface", "grid"],
    ["editing", "Editing", "film"],
    ["saving", "Saving", "save"],
    ["general", "General", "info"],
  ];
  root.insertAdjacentHTML(
    "beforeend",
    '<dialog id="settings-dialog" class="settings-dialog" aria-labelledby="settings-heading"><div class="settings-shell"><header class="settings-header"><div class="settings-title"><span class="settings-emblem">' +
      gear +
      '</span><div><h2 id="settings-heading">Settings</h2><p>Make Director feel right for you.</p></div></div><button class="btn square subtle" id="close-settings" aria-label="Close settings">' +
      icon("close") +
      '</button></header><div class="settings-main"><nav class="settings-nav" role="tablist" aria-label="Settings categories" aria-orientation="vertical"><span class="eyebrow">Your workspace</span>' +
      tabs
        .map(
          ([id, name, ic], i) =>
            '<button class="settings-tab" id="settings-tab-' +
            id +
            '" role="tab" aria-controls="settings-' +
            id +
            '" aria-selected="' +
            (i === 0) +
            '" tabindex="' +
            (i === 0 ? 0 : -1) +
            '" data-settings-tab="' +
            id +
            '">' +
            icon(ic) +
            name +
            "</button>",
        )
        .join("") +
      '<p class="nav-note">Personal preferences.<br>Your scene stays unchanged.</p></nav><div class="settings-content">' +
      '<section id="settings-controls" role="tabpanel" aria-labelledby="settings-tab-controls"><h3>Controls</h3><p class="settings-intro">Move naturally. Keep your shortcuts close.</p>' +
      row(
        "Keyboard layout",
        "Choose the movement keys you use.",
        dropdown("layout", ["AZERTY", "QWERTY"]),
      ) +
      row(
        "Mouse sensitivity",
        "Fine control when framing your shot.",
        slider("sensitivity", 1, 0.2, 3, 0.1, "×"),
      ) +
      row(
        "Camera speed",
        "Starting speed for the free camera.",
        slider("speed", 8, 0.5, 30, 0.1, " m/s"),
      ) +
      row(
        "Invert vertical look",
        "Reverse the mouse pitch direction.",
        toggle("invert", false, "Invert vertical look"),
      ) +
      '<details class="keymap"><summary><span>Movement & camera shortcuts</span>' +
      icon("chevron") +
      '</summary><div class="keymap-body"><div class="keymap-row"><span>Move</span><span id="movement-keys"><kbd>Z</kbd><kbd>Q</kbd><kbd>S</kbd><kbd>D</kbd></span></div><div class="keymap-row"><span>Height</span><span><kbd>A</kbd><kbd>E</kbd></span></div><div class="keymap-row"><span>Capture keyframe</span><span><kbd>K</kbd></span></div><div class="keymap-row"><span>Look around</span><span><kbd>Right mouse</kbd></span></div></div></details></section>' +
      '<section id="settings-interface" role="tabpanel" aria-labelledby="settings-tab-interface" hidden><h3>Interface</h3><p class="settings-intro">A comfortable workspace with less distraction.</p>' +
      row(
        "UI scale",
        "Choose the size of panels and controls.",
        dropdown("scale", [
          "100% · Default",
          "110% · Comfortable",
          "125% · Large",
        ]),
      ) +
      row(
        "Text size",
        "Improve readability without enlarging everything.",
        dropdown("text", ["Default", "Larger"]),
      ) +
      row(
        "Reduced motion",
        "Use immediate transitions for panels and controls.",
        toggle("motion", false, "Reduced motion"),
      ) +
      row(
        "Contextual tips",
        "Show mouse controls over the game view.",
        toggle("tips", true, "Contextual tips"),
      ) +
      row(
        "Hover help",
        "Explain icons and unfamiliar actions.",
        toggle("help", true, "Hover help"),
      ) +
      note("These preferences affect your workspace only.") +
      "</section>" +
      '<section id="settings-editing" role="tabpanel" aria-labelledby="settings-tab-editing" hidden><h3>Editing</h3><p class="settings-intro">Set the precision that suits your workflow.</p>' +
      row(
        "Timeline snapping",
        "Align clips and keys while dragging.",
        toggle("snap", true, "Timeline snapping"),
      ) +
      row(
        "Snap interval",
        "The smallest step for timeline edits.",
        dropdown("interval", [
          "0.1 second",
          "0.25 second",
          "0.5 second",
          "1 second",
        ]),
      ) +
      row(
        "Move increment",
        "Precision when adjusting actor placement.",
        dropdown("move", ["0.05 m", "0.10 m", "0.25 m", "0.50 m"]),
      ) +
      row(
        "Rotation increment",
        "Precision when orienting scene elements.",
        dropdown("rotation", ["1°", "5°", "15°", "45°"]),
      ) +
      note(
        "Movement and rotation increments apply to numeric controls. Mouse dragging remains smooth.",
      ) +
      "</section>" +
      '<section id="settings-saving" role="tabpanel" aria-labelledby="settings-tab-saving" hidden><h3>Saving</h3><p class="settings-intro">Protect your work while you focus on the shot.</p>' +
      row(
        "Autosave",
        "Save the active project at regular intervals.",
        toggle("autosave", true, "Autosave"),
      ) +
      row(
        "Save interval",
        "How often Director should save your changes.",
        dropdown("save-interval", [
          "Every 2 minutes",
          "Every minute",
          "Every 5 minutes",
        ]),
      ) +
      row(
        "Unsaved changes warning",
        "Ask before closing an unsaved project.",
        toggle("warning", true, "Unsaved changes warning"),
      ) +
      note(
        "Autosave runs while editing a changed project. Playback, capture, routes and shared viewer sessions pause autosave.",
      ) +
      "</section>" +
      '<section id="settings-general" role="tabpanel" aria-labelledby="settings-tab-general" hidden><h3>General</h3><p class="settings-intro">Your personal Director preferences.</p>' +
      row(
        "Language",
        "Language for the entire interface, tutorial and messages.",
        dropdown("language", ["English", "Français"]),
      ) +
      row(
        "Remember workspace",
        "Restore your panel layout when reopening.",
        toggle("workspace", true, "Remember workspace"),
      ) +
      note(
        "Personal preferences are stored locally. Project data remains saved on the server.",
      ) +
      "</section>" +
      '</div></div><footer class="settings-footer"><button class="btn reset" id="reset-settings">' +
      icon("undo") +
      'Reset tab</button><span class="status" id="settings-status" role="status">Personal settings · Saved on this device</span><button class="btn primary" id="apply-settings">Save settings</button></footer></div></dialog>',
  );
  const dialog = q("#settings-dialog"),
    trigger = q("#open-settings");
  let current = "controls";
  trigger.onclick = () => {
    paint(prefs);
    dialog.showModal();
    trigger.setAttribute("aria-expanded", "true");
    const wasDragging = actorDragging || leftHeld;
    clearKeys();
    looking = false;
    actorDragging = leftHeld = false;
    setLookHint(null);
    lookSurface.classList.remove("looking", "dragging-actor");
    if (bridgeReady && wasDragging) post("endActorDrag");
    q("#close-settings").focus();
  };
  q("#close-settings").onclick = () => dialog.close();
  dialog.addEventListener("close", () => {
    trigger.setAttribute("aria-expanded", "false");
    trigger.focus();
  });
  document.addEventListener(
    "keydown",
    (e) => {
      if (dialog.open && e.key === "Escape") {
        e.preventDefault();
        dialog.close();
        e.stopImmediatePropagation();
      }
    },
    true,
  );
  dialog.addEventListener("keydown", (e) => e.stopPropagation());
  dialog.addEventListener("keyup", (e) => e.stopPropagation());
  dialog.addEventListener("click", (e) => {
    if (e.target === dialog) {
      const b = dialog.getBoundingClientRect();
      if (
        e.clientX < b.left ||
        e.clientX > b.right ||
        e.clientY < b.top ||
        e.clientY > b.bottom
      )
        dialog.close();
    }
  });
  function tab(id) {
    current = id;
    qa("[data-settings-tab]").forEach((b) => {
      const active = b.dataset.settingsTab === id;
      b.setAttribute("aria-selected", String(active));
      b.tabIndex = active ? 0 : -1;
    });
    tabs.forEach(([key]) => (q("#settings-" + key).hidden = key !== id));
    q(".settings-content").scrollTop = 0;
    q("#settings-status").textContent =
      "Personal settings · Saved on this device";
  }
  qa("[data-settings-tab]").forEach((b, i) => {
    b.onclick = () => tab(b.dataset.settingsTab);
    b.onkeydown = (e) => {
      if (["ArrowDown", "ArrowUp", "Home", "End"].includes(e.key)) {
        e.preventDefault();
        let next =
          e.key === "Home"
            ? 0
            : e.key === "End"
              ? tabs.length - 1
              : (i + (e.key === "ArrowDown" ? 1 : -1) + tabs.length) %
                tabs.length;
        tab(tabs[next][0]);
        q("#settings-tab-" + tabs[next][0]).focus();
      }
    };
  });
  qa(".settings-dialog .switch").forEach((b) => {
    b.dataset.initial = b.getAttribute("aria-checked");
    b.onclick = () => {
      b.setAttribute(
        "aria-checked",
        String(b.getAttribute("aria-checked") !== "true"),
      );
      if (b.id === "pref-autosave") {
        q("#pref-save-interval").classList.toggle(
          "inactive",
          b.getAttribute("aria-checked") === "false",
        );
        q("#pref-save-interval").open = false;
      }
    };
  });
  qa(".settings-dialog .range").forEach((el) => {
    const update = () => {
      el.style.setProperty(
        "--fill",
        ((el.value - el.min) / (el.max - el.min)) * 100 + "%",
      );
      q("#" + el.id + "-number").value = el.value;
    };
    el.oninput = update;
    const number = q("#" + el.id + "-number");
    number.onchange = () => {
      if (
        number.value.trim() === "" ||
        !Number.isFinite(Number(number.value))
      ) {
        update();
        return;
      }
      el.value = Math.max(
        Number(el.min),
        Math.min(Number(el.max), Number(number.value)),
      );
      update();
    };
    number.onkeydown = (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        number.blur();
      }
    };
    update();
  });
  qa(".settings-dialog .menu button").forEach(
    (b) =>
      (b.onclick = () => {
        const menu = b.closest(".dropdown");
        menu.querySelector("summary span").textContent = b.textContent;
        menu
          .querySelectorAll("button")
          .forEach((el) => el.classList.toggle("chosen", el === b));
        menu.open = false;
        if (menu.id === "pref-layout") {
          q(".keymap-row:nth-child(2) kbd").textContent =
            b.textContent === "AZERTY" ? "A" : "Q";
          q("#movement-keys").innerHTML = (
            b.textContent === "AZERTY"
              ? ["Z", "Q", "S", "D"]
              : ["W", "A", "S", "D"]
          )
            .map((v) => "<kbd>" + v + "</kbd>")
            .join("");
        }
      }),
  );
  qa(".settings-dialog details.dropdown").forEach((d) =>
    d.addEventListener("toggle", () => {
      if (d.open)
        qa(".settings-dialog details.dropdown")
          .filter((other) => other !== d)
          .forEach((other) => (other.open = false));
    }),
  );
  q("#reset-settings").onclick = () => {
    const keys = {
      controls: ["layout", "sensitivity", "speed", "invert"],
      interface: ["scale", "text", "motion", "tips", "help"],
      editing: ["snap", "interval", "move", "rotation"],
      saving: ["autosave", "saveInterval", "warning"],
      general: ["language", "workspace"],
    }[current];
    const draft = read();
    for (const key of keys) draft[key] = defaults[key];
    paint(draft);
    q("#settings-status").textContent = "Tab defaults restored";
  };

  const defaults = {
    layout: "azerty",
    sensitivity: 1,
    speed: 8,
    invert: false,
    scale: 1,
    text: "default",
    motion: false,
    tips: true,
    help: true,
    snap: true,
    interval: 0.1,
    move: 0.05,
    rotation: 1,
    autosave: false,
    saveInterval: 120,
    warning: true,
    language: "fr",
    workspace: true,
    leftCollapsed: false,
    rightCollapsed: false,
  };
  let prefs = { ...defaults },
    timer = null;
  function choice(id, index) {
    const item = q(
      "#pref-" + id + " .menu button:nth-child(" + (index + 1) + ")",
    );
    if (item) item.click();
  }
  function paint(value) {
    prefs = { ...defaults, ...value };
    for (const id of ["sensitivity", "speed"]) {
      q("#pref-" + id).value = prefs[id];
      q("#pref-" + id).dispatchEvent(new Event("input"));
    }
    for (const id of [
      "invert",
      "motion",
      "tips",
      "help",
      "snap",
      "autosave",
      "warning",
      "workspace",
    ])
      q("#pref-" + id).setAttribute("aria-checked", String(prefs[id]));
    choice("layout", prefs.layout === "qwerty" ? 1 : 0);
    choice("scale", [1, 1.1, 1.25].indexOf(prefs.scale));
    choice("text", prefs.text === "larger" ? 1 : 0);
    choice("interval", [0.1, 0.25, 0.5, 1].indexOf(prefs.interval));
    choice("move", [0.05, 0.1, 0.25, 0.5].indexOf(prefs.move));
    choice("rotation", [1, 5, 15, 45].indexOf(prefs.rotation));
    choice("save-interval", [120, 60, 300].indexOf(prefs.saveInterval));
    choice("language", prefs.language === "fr" ? 1 : 0);
    q("#pref-save-interval").classList.toggle("inactive", !prefs.autosave);
  }
  function index(id) {
    return [...q("#pref-" + id + " .menu").children].findIndex((el) =>
      el.classList.contains("chosen"),
    );
  }
  function read() {
    const out = { ...prefs };
    for (const id of ["sensitivity", "speed"])
      out[id] = Number(q("#pref-" + id).value);
    for (const id of [
      "invert",
      "motion",
      "tips",
      "help",
      "snap",
      "autosave",
      "warning",
      "workspace",
    ])
      out[id] = q("#pref-" + id).getAttribute("aria-checked") === "true";
    out.layout = index("layout") === 1 ? "qwerty" : "azerty";
    out.scale = [1, 1.1, 1.25][index("scale")] || 1;
    out.text = index("text") === 1 ? "larger" : "default";
    out.interval = [0.1, 0.25, 0.5, 1][index("interval")] || 0.1;
    out.move = [0.05, 0.1, 0.25, 0.5][index("move")] || 0.05;
    out.rotation = [1, 5, 15, 45][index("rotation")] || 1;
    out.saveInterval = [120, 60, 300][index("save-interval")] || 120;
    out.language = index("language") === 1 ? "fr" : "en";
    return out;
  }
  function apply() {
    root.classList.toggle("reduce-motion", prefs.motion);
    root.classList.toggle("large-text", prefs.text === "larger");
    root.classList.toggle("hide-help", !prefs.help);
    q("#lookHint").classList.toggle("is-hidden", !prefs.tips);
    root.style.setProperty("--ui-scale", prefs.scale);
    document.getElementById("speed").value = prefs.speed;
    document.getElementById("speedValue").textContent = prefs.speed.toFixed(1);
    window.VantaPreferences = prefs;
    window.dispatchEvent(
      new CustomEvent("directorPreferences", { detail: prefs }),
    );
    scheduleAutosave();
  }
  function scheduleAutosave() {
    clearTimeout(timer);
    if (!bridgeReady || !prefs.autosave) return;
    timer = setTimeout(() => {
      if (
        saveDirty &&
        !savePending &&
        sessionRole !== "viewer" &&
        !previewPlaying &&
        !looking &&
        !actorDragging &&
        !timelineDrag &&
        !Object.values(keyState).some(Boolean) &&
        !dialog.open &&
        !isTyping() &&
        !root.classList.contains("is-hidden") &&
        q("#routeEditor").classList.contains("is-hidden") &&
        qa(
          ".library-overlay,.model-overlay,.animation-overlay,.exit-overlay",
        ).every((el) => el.classList.contains("is-hidden"))
      )
        q("#saveButton").click();
      scheduleAutosave();
    }, prefs.saveInterval * 1000);
  }
  q("#apply-settings").onclick = async () => {
    const button = q("#apply-settings");
    if (button.disabled) return;
    button.disabled = true;
    try {
      const result = await post("setPreferences", { preferences: read() });
      if (result.ok) {
        paint(result.preferences);
        apply();
        q("#settings-status").textContent = "Settings saved on this device";
      } else
        q("#settings-status").textContent =
          result.message || "Could not save settings";
    } finally {
      button.disabled = false;
    }
  };
  window.addEventListener("message", (e) => {
    const d = e.data || {};
    if (d.action === "preferences") {
      if (d.defaults)
        for (const key of Object.keys(defaults))
          if (Object.prototype.hasOwnProperty.call(d.defaults, key))
            defaults[key] = d.defaults[key];
      paint(d.preferences);
      apply();
    }
    if (
      d.action === "close" ||
      d.action === "motionRecordStarted" ||
      d.action === "captureCountdown"
    ) {
      if (dialog.open) dialog.close();
      clearTimeout(timer);
    }
    if (
      d.action === "open" ||
      d.action === "captureEnd" ||
      d.action === "motionRecordFinished"
    )
      scheduleAutosave();
  });
  window.addEventListener(
    "preferencesUpdated",
    (e) => (prefs = { ...prefs, ...e.detail }),
  );
  window.addEventListener("beforeunload", () => clearTimeout(timer));
  window.VantaPreferences = { ...defaults };
})();
