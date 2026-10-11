/* One short, contextual action at a time. No scene edits are performed by the guide. */
(() => {
  const q = (id) => document.getElementById(id);
  window.DirectorEditor.elements.root.insertAdjacentHTML(
    "beforeend",
    '<div id="tutorialFocus" class="tutorial-focus is-hidden" aria-hidden="true"></div><aside id="tutorialCoach" class="tutorial-coach is-hidden" role="region" aria-label="Director guided tutorial"><div class="tutorial-heading"><span>VANTA / QUICK START</span><button id="tutorialSkip" type="button">Skip tutorial</button></div><div class="tutorial-progress"><span id="tutorialProgress"></span></div><small id="tutorialCount"></small><h2 id="tutorialTitle"></h2><p id="tutorialText" aria-live="polite"></p><small id="tutorialHint"></small><footer><button id="tutorialBack" type="button">Back</button><button id="tutorialNext" class="tutorial-primary" type="button">Skip step →</button></footer></aside>',
  );
  const coach = q("tutorialCoach"),
    focus = q("tutorialFocus");
  coach.querySelector(".tutorial-heading>span").textContent = "VANTA / PREMIER FILM";
  coach.setAttribute("aria-label", "Tutoriel interactif de Director");
  q("tutorialSkip").textContent = "Passer le tutoriel";
  q("tutorialBack").textContent = "Retour";
  q("tutorialHint").insertAdjacentHTML(
    "afterend",
    '<button id="tutorialReturn" type="button" hidden>Revenir à cette étape</button>',
  );
  let active = false,
    index = -1,
    seen = false,
    baseline = null,
    lastCamera = null,
    firstTime = null,
    actorBaseline = [],
    timer = null,
    persisting = false,
    resizeTimer = null,
    pendingAdvance = false,
    generation = 0,
    projectId = null,
    pendingAutoStart = false;
  const steps = [
    {
      title: "Trouve ton premier cadrage",
      target: "#lookSurface",
      phase: "camera",
      goal: "compose",
      text: () =>
        `Déplace la caméra avec ${window.VantaPreferences?.layout === "qwerty" ? "W A S D" : "Z Q S D"}. Maintiens le clic droit dans la vue pour regarder autour de toi.`,
      hint: "Bouge ou tourne un peu la caméra pour continuer.",
    },
    {
      title: "Enregistre la position de départ",
      target: "#workflowPrimary",
      phase: "camera",
      goal: "firstKey",
      text: () =>
        "Clique sur « Ajouter cette position », ou appuie sur K. Le cadrage est mémorisé au temps actuel.",
      hint: "Director doit accepter la position pour valider cette étape.",
    },
    {
      title: "Choisis le temps d’arrivée",
      target: "#timelineContent",
      goal: "time",
      text: () =>
        "Clique plus loin sur la timeline, par exemple cinq secondes après le départ. La distance entre les deux temps donne la durée du mouvement.",
      hint: "Choisis un temps après la première position.",
    },
    {
      title: "Cadre la fin du mouvement",
      target: "#lookSurface",
      goal: "compose",
      text: () =>
        "Déplace ou tourne doucement la caméra pour choisir son cadrage d’arrivée. Essaie un petit mouvement latéral ou une approche.",
      hint: "Change réellement le cadrage avant d’ajouter la seconde position.",
    },
    {
      title: "Enregistre la position d’arrivée",
      target: "#workflowPrimary",
      phase: "camera",
      goal: "secondKey",
      text: () =>
        "Clique de nouveau sur « Ajouter cette position », ou appuie sur K. Les deux positions forment ton mouvement de caméra.",
      hint: "La seconde position doit être après le temps de départ.",
    },
    {
      title: "Ajoute un sujet",
      target: "#workflowPrimary",
      phase: "subject",
      goal: "library",
      text: () =>
        "Clique sur « Choisir un modèle ». Pour apprendre les actions, choisis un personnage ou un véhicule.",
      hint: "Facultatif : passe cette partie pour filmer un paysage sans sujet.",
    },
    {
      title: "Choisis ton modèle",
      target: "#modelResults",
      goal: "model",
      model: true,
      text: () =>
        "Clique sur un personnage ou un véhicule dans la liste. Vérifie son aperçu au centre avant de le placer.",
      hint: "Le jeu doit accepter la sélection pour continuer.",
    },
    {
      title: "Place-le dans la scène",
      target: "#modelPlace",
      goal: "place",
      model: true,
      text: () =>
        "Clique sur « Placer au point visé ». Le sujet est ajouté au point visé par la caméra avant l’ouverture de la bibliothèque.",
      hint: "Le bouton devient disponible quand le modèle est prêt.",
    },
    {
      title: "Ajoute un déplacement",
      target: ".free-move-action",
      phase: "route",
      goal: "simpleMove",
      text: () =>
        "Sélectionne ton sujet, vise sa destination avec la caméra, choisis la durée puis clique sur « Déplacer vers le point visé ». Tu peux garder un sujet immobile et passer cette étape.",
      hint: "Le déplacement doit être accepté par Director.",
    },
    {
      title: "Regarde le résultat",
      target: "#workflowPrimary",
      phase: "check",
      goal: "preview",
      text: () =>
        "Clique sur « Lire la scène ». Observe le cadrage, les virages et le contact des pieds ou des roues avec le sol.",
      hint: "Le tutoriel détecte la lecture ; tu vérifies le rendu en jeu.",
    },
    {
      title: "Reviens à l’édition",
      target: "#stopButton",
      goal: "stop",
      text: () =>
        "Clique sur le carré Arrêter dans la timeline. Tu pourras ajuster le plan avant de filmer.",
      hint: "Arrête la lecture pour continuer.",
    },
    {
      title: "Sauvegarde ton travail",
      target: "#saveButton",
      goal: "save",
      text: () =>
        "Clique sur « Enregistrer ». Attends la confirmation du serveur : un clic sur le bouton ne suffit pas.",
      hint: "L’étape reste ouverte si la sauvegarde échoue ou si la scène a changé entre-temps.",
    },
    {
      title: "Lance ta première prise",
      target: "#workflowPrimary",
      phase: "film",
      goal: "capture",
      text: () =>
        "Démarre OBS, puis clique sur « Lancer la prise propre ». Les panneaux disparaissent ; " +
        (window.VantaRuntimeConfig?.stopTakeKey || "F9") +
        " arrête la prise de Director. Termine ensuite l’enregistrement OBS.",
      hint: "Director ne crée pas de MP4 et ne détecte pas OBS. Tu peux terminer le tutoriel sans filmer.",
    },
  ];
  function blocked() {
    return (
      window.DirectorEditor.elements.root.classList.contains("is-hidden") ||
      ["libraryOverlay", "animationOverlay", "exitOverlay", "sessionInviteOverlay"].some(
        (id) => q(id) && !q(id).classList.contains("is-hidden"),
      ) ||
      (!["library", "model", "place"].includes(steps[index]?.goal) &&
        q("modelOverlay") &&
        !q("modelOverlay").classList.contains("is-hidden")) ||
      q("settings-dialog")?.open
    );
  }
  function targetElement() {
    const step = steps[index];
    if (!step) return null;
    if (
      step.target === "#workflowPrimary" &&
      window.DirectorEditor.elements.root.dataset.workflowStep !== step.phase
    )
      return null;
    const target = document.querySelector(step.target);
    return target?.getClientRects().length ? target : null;
  }
  function place() {
    const paused = !active || blocked();
    coach.classList.toggle("is-hidden", paused);
    focus.classList.add("is-hidden");
    if (paused) return;
    const width = Math.min(310, window.innerWidth - 32);
    coach.style.width = width + "px";
    const target = targetElement(),
      rect = target?.getClientRects().length ? target.getBoundingClientRect() : null;
    const height = coach.offsetHeight,
      margin = 16,
      top = steps[index]?.model ? 0 : q("workflowMode")?.getBoundingClientRect().bottom || 112;
    const clamp = (n, min, max) => Math.max(min, Math.min(max, n));
    let areaBottom = steps[index]?.model
      ? window.innerHeight
      : document.querySelector(".look-surface")?.getBoundingClientRect().bottom ||
        window.innerHeight;
    if (areaBottom - top < height + 30) areaBottom = window.innerHeight;
    let x = (document.querySelector(".left-panel")?.getBoundingClientRect().right || 250) + 18,
      y = top + 18,
      side = "none";
    if (rect) {
      const options = [
        {
          x: rect.right + 18,
          y: clamp(rect.top, top + 10, areaBottom - height - margin),
          side: "left",
        },
        {
          x: rect.left - width - 18,
          y: clamp(rect.top, top + 10, areaBottom - height - margin),
          side: "right",
        },
        { x: rect.left, y: rect.top - height - 18, side: "bottom" },
        { x: rect.left, y: rect.bottom + 18, side: "top" },
      ];
      const valid = options.find(
        (p) =>
          p.x >= margin &&
          p.x + width <= window.innerWidth - margin &&
          p.y >= top + 10 &&
          p.y + height <= areaBottom - margin,
      );
      if (valid) ({ x, y, side } = valid);
      focus.style.left = Math.max(0, rect.left - 4) + "px";
      focus.style.top = Math.max(top, rect.top - 4) + "px";
      focus.style.width = Math.min(window.innerWidth, rect.width + 8) + "px";
      focus.style.height =
        Math.max(0, Math.min(window.innerHeight, rect.bottom + 4) - Math.max(top, rect.top - 4)) +
        "px";
      focus.classList.remove("is-hidden");
    }
    coach.style.left = clamp(x, margin, window.innerWidth - width - margin) + "px";
    coach.style.top = clamp(y, top + 10, window.innerHeight - height - margin) + "px";
    coach.dataset.side = side;
    q("tutorialReturn").hidden =
      index < 0 ||
      Boolean(rect) ||
      window.DirectorEditor.elements.root.classList.contains("editing-route");
    q("tutorialBack").disabled =
      persisting ||
      index < 0 ||
      window.DirectorEditor.elements.root.classList.contains("editing-route");
    if (pendingAdvance) {
      pendingAdvance = false;
      accomplished();
    }
  }
  function paint() {
    clearTimeout(timer);
    timer = null;
    pendingAdvance = false;
    coach.classList.remove("tutorial-done");
    baseline = lastCamera ? { ...lastCamera } : null;
    actorBaseline = (window.DirectorEditor.state.project.actors || []).map((a) => ({
      id: a.id,
      x: a.x,
      y: a.y,
      z: a.z,
      heading: a.heading,
    }));
    coach.classList.remove("is-hidden");
    if (index < 0) {
      q("tutorialTitle").textContent = "Ton premier film, étape par étape";
      q("tutorialText").textContent =
        "Suis la commande mise en évidence. Le tutoriel attend tes actions dans le projet actuel : il ne crée pas de scène et ne réinitialise rien.";
      q("tutorialHint").textContent = "Facultatif · Passer à tout moment · Relancer depuis Aide";
      q("tutorialCount").textContent = "CAMÉRA → SUJET → ACTIONS → VÉRIFIER → FILMER";
      q("tutorialNext").textContent = "Commencer";
      q("tutorialBack").disabled = true;
      q("tutorialProgress").style.width = "0%";
    } else {
      const step = steps[index];
      if (step.phase) window.VantaWorkflow?.guide(step.phase);
      targetElement()?.scrollIntoView({ block: "nearest" });
      q("tutorialTitle").textContent = step.title;
      q("tutorialText").textContent = step.text();
      q("tutorialHint").textContent = step.hint;
      q("tutorialCount").textContent = `${index + 1} / ${steps.length}`;
      q("tutorialNext").textContent =
        index === steps.length - 1
          ? "Terminer sans filmer"
          : step.goal === "library"
            ? "Paysage sans sujet →"
            : "Passer cette étape →";
      q("tutorialBack").disabled = false;
      q("tutorialProgress").style.width = ((index + 1) / steps.length) * 100 + "%";
    }
    place();
  }
  function start() {
    if (!window.DirectorEditor.state.bridgeReady) return;
    if (window.DirectorEditor.state.sessionRole === "viewer")
      return window.DirectorEditor.status.showStatus(
        "L’hôte pilote la scène. Relance le tutoriel dans un projet personnel.",
      );
    if (
      window.DirectorEditor.elements.root.classList.contains("editing-route") ||
      window.DirectorEditor.state.previewPlaying
    )
      return window.DirectorEditor.status.showStatus(
        "Arrête la lecture et termine le trajet avant de lancer le tutoriel.",
      );
    generation++;
    persisting = false;
    q("tutorialSkip").disabled = q("tutorialNext").disabled = false;
    window.DirectorEditor.input.clearKeys();
    active = true;
    projectId = window.DirectorEditor.state.project.id ?? null;
    window.DirectorEditor.elements.root.classList.add("tutorial-active");
    window.VantaTutorialActive = true;
    window.VantaWorkflow?.guide("camera");
    index = -1;
    firstTime = null;
    paint();
  }
  function stop() {
    generation++;
    active = false;
    persisting = false;
    pendingAutoStart = false;
    window.VantaTutorialActive = false;
    window.DirectorEditor.elements.root.classList.remove("tutorial-active");
    clearTimeout(timer);
    timer = null;
    clearTimeout(resizeTimer);
    resizeTimer = null;
    pendingAdvance = false;
    place();
  }
  async function finish(status) {
    if (persisting || !active) return;
    clearTimeout(timer);
    timer = null;
    pendingAdvance = false;
    persisting = true;
    const token = generation;
    q("tutorialNext").disabled = q("tutorialSkip").disabled = q("tutorialBack").disabled = true;
    const result = await window.DirectorEditor.transport.post("tutorialStatus", { status });
    if (token !== generation) return;
    persisting = false;
    q("tutorialNext").disabled = q("tutorialSkip").disabled = false;
    q("tutorialBack").disabled = index < 0;
    if (result.ok) {
      seen = true;
      stop();
      window.DirectorEditor.status.showStatus(
        status === "completed"
          ? "Tutoriel terminé. Tu peux le relancer depuis Aide."
          : "Tutoriel passé. Tu peux le relancer depuis Aide.",
      );
    } else {
      q("tutorialHint").textContent =
        result.message || "Ton choix n’a pas pu être mémorisé. Réessaie.";
      place();
    }
  }
  function next(skip = false) {
    if (!active || persisting) return;
    if (index === steps.length - 1) {
      finish("completed");
      return;
    }
    if (skip && ["library", "simpleMove"].includes(steps[index]?.goal))
      index = steps.findIndex((s) => s.goal === "preview");
    else index++;
    paint();
  }
  function accomplished() {
    if (timer || !active || persisting || pendingAdvance) return;
    q("tutorialHint").textContent = "✓ Action validée";
    coach.classList.add("tutorial-done");
    timer = setTimeout(() => {
      timer = null;
      coach.classList.remove("tutorial-done");
      if (blocked()) {
        pendingAdvance = true;
        return;
      }
      next();
    }, 450);
  }
  q("tutorialSkip").onclick = () => finish("skipped");
  q("tutorialNext").onclick = async () => {
    if (
      window.DirectorEditor.elements.root.classList.contains("editing-route") &&
      steps[index]?.goal === "routeCommit"
    ) {
      if (q("routeApply").disabled) return;
      q("tutorialNext").disabled = true;
      const token = generation;
      const result = await window.DirectorEditor.transport.post("cancelRoute");
      if (token !== generation) return;
      q("tutorialNext").disabled = false;
      if (!result.ok) {
        q("tutorialHint").textContent = result.message || "Le trajet n’a pas pu être annulé.";
        return;
      }
    }
    next(true);
  };
  q("tutorialBack").onclick = () => {
    if (!persisting && !window.DirectorEditor.elements.root.classList.contains("editing-route")) {
      index = Math.max(-1, index - 1);
      paint();
    }
  };
  q("tutorialReturn").onclick = () => {
    window.VantaWorkflow?.guide(steps[index]?.phase || "camera");
    targetElement()?.scrollIntoView({ block: "nearest" });
    place();
  };
  window.addEventListener("directorAction", (event) => {
    if (!active || index < 0 || persisting) return;
    const { name, data = {}, result } = event.detail || {};
    if (!result?.ok) return;
    const goal = steps[index].goal;
    if (goal === "firstKey" && name === "addKeyframe") {
      firstTime = Number(data.time ?? window.DirectorEditor.state.project.playhead);
      accomplished();
    } else if (
      goal === "time" &&
      name === "setPlayhead" &&
      Number(data.time) > (firstTime ?? 0) + 0.05
    )
      accomplished();
    else if (goal === "secondKey" && name === "addKeyframe") {
      if (
        firstTime === null ||
        Number(data.time ?? window.DirectorEditor.state.project.playhead) > firstTime + 0.05
      )
        accomplished();
      else q("tutorialHint").textContent = "Choose a later timeline time, then capture again.";
    } else if (goal === "preview" && name === "preview") accomplished();
    else if (goal === "library" && name === "openModelBrowser") accomplished();
    else if (goal === "model" && name === "previewModel") accomplished();
    else if (goal === "place" && ["addActor", "placeBrowserModel"].includes(name)) accomplished();
    else if (goal === "simpleMove" && name === "addAction" && data.type === "move") accomplished();
    else if (goal === "stop" && name === "stopPreview") accomplished();
    else if (goal === "capture" && name === "capture") finish("completed");
  });
  window.addEventListener("message", (event) => {
    const data = event.data || {};
    if (data.action === "tutorialStatus") {
      seen = Boolean(data.seen);
      pendingAutoStart = !seen && !active;
    }
    if (data.action === "project" && data.project && pendingAutoStart) {
      pendingAutoStart = false;
      start();
    }
    if (data.action === "close") {
      stop();
      return;
    }
    if (active && data.action === "library" && (data.activeId ?? null) !== projectId) {
      stop();
      window.DirectorEditor.status.showStatus("Projet changé. Relance le tutoriel depuis Aide.");
    }
    if (active && data.action === "sessionState" && data.role === "viewer") stop();
    if (data.action === "camera" && data.camera) {
      const c = data.camera;
      lastCamera = { ...c };
      if (
        active &&
        steps[index]?.goal === "compose" &&
        !window.DirectorEditor.state.previewPlaying
      ) {
        if (!baseline) baseline = { ...c };
        else {
          const moved =
              Math.abs(c.x - baseline.x) + Math.abs(c.y - baseline.y) + Math.abs(c.z - baseline.z) >
              0.15,
            turn = (k) => {
              const d = Math.abs(c[k] - baseline[k]) % 360;
              return Math.min(d, 360 - d);
            };
          if (moved || turn("rx") + turn("rz") > 2) accomplished();
        }
      }
    }
    if (data.action === "saveResult" && active && steps[index]?.goal === "save") {
      if (data.ok && !data.stale) accomplished();
      else
        q("tutorialHint").textContent = data.stale
          ? "La scène a changé. Enregistre de nouveau."
          : "Sauvegarde non confirmée. Corrige le problème puis réessaie.";
    }
    if (
      ["project", "actors", "routeControls", "routeClosed", "captureEnd"].includes(data.action) &&
      active
    )
      schedulePlace();
  });
  function schedulePlace() {
    if (!active || resizeTimer) return;
    resizeTimer = setTimeout(() => {
      resizeTimer = null;
      place();
    }, 80);
  }
  window.addEventListener("directorPreferences", () => {
    if (active && index >= 0) {
      q("tutorialText").textContent = steps[index].text();
      place();
    }
  });
  for (const id of [
    "director",
    "libraryOverlay",
    "modelOverlay",
    "animationOverlay",
    "exitOverlay",
    "sessionInviteOverlay",
    "settings-dialog",
  ]) {
    const element = q(id);
    if (element)
      new MutationObserver(place).observe(element, {
        attributes: true,
        attributeFilter: ["class", "open"],
      });
  }
  window.addEventListener("resize", schedulePlace);
  window.DirectorEditor.elements.root.addEventListener("scroll", schedulePlace, true);
  // Add Help to the existing settings navigation without changing preference storage.
  const dialog = q("settings-dialog"),
    nav = dialog.querySelector(".settings-nav"),
    content = dialog.querySelector(".settings-content");
  const button = document.createElement("button");
  button.type = "button";
  button.id = "settings-tab-help";
  button.className = "settings-tab";
  button.setAttribute("role", "tab");
  button.setAttribute("aria-controls", "settings-help");
  button.setAttribute("aria-selected", "false");
  button.tabIndex = -1;
  button.textContent = "Help";
  nav.insertBefore(button, nav.querySelector(".nav-note"));
  const section = document.createElement("section");
  section.id = "settings-help";
  section.hidden = true;
  section.setAttribute("role", "tabpanel");
  section.setAttribute("aria-labelledby", "settings-tab-help");
  section.innerHTML =
    '<h3>Help</h3><p class="settings-intro">Get comfortable with Director, one action at a time.</p><div class="setting-row"><div class="setting-label"><strong>Guided quick start</strong><small>Camera, actors, actions, saving and clean takes.</small></div><button id="tutorialReplay" class="btn" type="button">Start tutorial</button></div><p class="settings-intro">You can skip any step. Replaying the guide does not reset your projects or preferences.</p>';
  content.append(section);
  button.textContent = "Aide";
  section.querySelector("h3").textContent = "Aide";
  section.querySelector(".settings-intro").textContent =
    "Apprends à filmer dans Director, une action à la fois.";
  section.querySelector("strong").textContent = "Tutoriel interactif";
  section.querySelector("small").textContent =
    "Caméra, sujet, actions, vérification et prise propre.";
  q("tutorialReplay").textContent = "Relancer le tutoriel";
  section.querySelector(".settings-intro:last-child").textContent =
    "Le tutoriel utilise le projet ouvert. Tu peux le passer sans réinitialiser tes projets ni tes préférences.";
  button.onclick = () => {
    dialog.querySelectorAll("[role=tabpanel]").forEach((el) => (el.hidden = el !== section));
    dialog.querySelectorAll("[role=tab]").forEach((el) => {
      el.setAttribute("aria-selected", String(el === button));
      el.tabIndex = el === button ? 0 : -1;
    });
  };
  dialog.querySelectorAll("[data-settings-tab]").forEach((el) =>
    el.addEventListener("click", () => {
      section.hidden = true;
      button.setAttribute("aria-selected", "false");
      button.tabIndex = -1;
    }),
  );
  q("tutorialReplay").onclick = () => {
    dialog.close();
    start();
  };
  const help = document.createElement("button");
  help.id = "tutorialHelp";
  help.type = "button";
  help.textContent = "Aide";
  help.title = "Aide et tutoriel interactif";
  q("controlsButton").before(help);
  help.onclick = () => {
    q("open-settings").click();
    button.click();
  };
  const tabs = Array.from(dialog.querySelectorAll("[role=tab]"));
  tabs.forEach((tab, i) => {
    tab.onkeydown = (event) => {
      if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const n =
        event.key === "Home"
          ? 0
          : event.key === "End"
            ? tabs.length - 1
            : (i + (event.key === "ArrowDown" ? 1 : -1) + tabs.length) % tabs.length;
      tabs[n].click();
      tabs[n].focus();
    };
  });
})();
