(() => {
  const root = document.getElementById("director"),
    panel = document.getElementById("routeEditor"),
    layer = document.getElementById("routeLayer");
  let active = false,
    busy = false,
    drag = null,
    selected = null,
    sequence = 0,
    pending = null,
    scheduled = false;
  let routeLength = 0,
    suggestedSpeed = null;
  let generation = 0,
    committing = false,
    routeToken;
  const requests = new Set();
  const estimate = document.createElement("p");
  estimate.id = "routeEstimate";
  estimate.setAttribute("aria-live", "polite");
  const error = document.createElement("p");
  error.id = "routeError";
  error.setAttribute("role", "alert");
  error.hidden = true;
  panel.querySelector("p").after(estimate, error);
  const updateEstimate = () => {
    const speedMode = document.getElementById("routeTiming").value === "speed";
    const speed = Number(document.getElementById("routeSpeed").value),
      seconds = Number(document.getElementById("routeSeconds").value);
    const value = speedMode ? routeLength / speed : routeLength / seconds;
    estimate.textContent =
      routeLength > 0 && Number.isFinite(value)
        ? speedMode
          ? "Durée estimée : " + value.toFixed(1) + " s"
          : "Vitesse moyenne : " + value.toFixed(1) + " m/s"
        : "Place une destination pour estimer la durée.";
  };
  const call = async (name, data = {}) => {
    if (name !== "beginRoute" && routeToken !== undefined && data.routeToken === undefined)
      data = { ...data, routeToken };
    const controller = new AbortController();
    requests.add(controller);
    try {
      const result = await window.VantaBridge.request(name, data, { signal: controller.signal });
      if (
        result.ok &&
        window.VantaTutorialActive &&
        ["beginRoute", "commitRoute", "cancelRoute"].includes(name)
      )
        window.dispatchEvent(new CustomEvent("directorAction", { detail: { name, data, result } }));
      return result;
    } catch {
      return {
        ok: false,
        message: "Director could not receive this edit. Try again or close the editor.",
      };
    } finally {
      requests.delete(controller);
    }
  };
  const status = (text) => {
    document.getElementById("statusMessage").textContent = text;
    error.textContent = text;
    error.hidden = false;
  };
  const close = () => {
    generation++;
    requests.forEach((c) => c.abort());
    requests.clear();
    busy = committing = false;
    routeToken = undefined;
    document.getElementById("routeApply").disabled = false;
    active = false;
    drag = null;
    pending = null;
    selected = null;
    panel.classList.add("is-hidden");
    layer.classList.add("is-hidden");
    root.classList.remove("editing-route");
    window.VantaWorkflow?.render();
  };
  const modal = (target) =>
    Boolean(
      target?.closest(
        'dialog[open],.vanta-select-menu:not(.is-hidden),.library-overlay:not(.is-hidden),.model-overlay:not(.is-hidden),.animation-overlay:not(.is-hidden),.exit-overlay:not(.is-hidden),[role="dialog"]:not(.is-hidden)',
      ),
    ) ||
    Boolean(
      document.querySelector(
        "dialog[open],.vanta-select-menu:not(.is-hidden),.library-overlay:not(.is-hidden),.model-overlay:not(.is-hidden),.animation-overlay:not(.is-hidden),.exit-overlay:not(.is-hidden)",
      ),
    );
  const cancel = async () => {
    if (busy) return;
    busy = true;
    const token = generation;
    const result = await call("cancelRoute");
    if (token !== generation) return;
    busy = false;
    if (result.ok) close();
    else status(result.message || "Could not cancel route.");
  };
  const timing = () => {
    const speed = document.getElementById("routeTiming").value === "speed";
    document.getElementById("routeSecondsField").classList.toggle("is-hidden", speed);
    document.getElementById("routeSpeedField").classList.toggle("is-hidden", !speed);
    updateEstimate();
  };
  window.VantaRouteEditor = {
    open: async (actor, action) => {
      if (busy || root.classList.contains("is-hidden")) return;
      if (actor.modelAvailable === false)
        return status("This model is unavailable. Reload the project or remove this subject.");
      busy = true;
      const token = generation;
      const result = await call("beginRoute", { id: actor.id, actionId: action?.id });
      if (token !== generation) return;
      busy = false;
      if (!result.ok) return status(result.message || "Could not open route.");
      routeToken = result.routeToken;
      error.hidden = true;
      suggestedSpeed = null;
      active = true;
      selected = null;
      sequence = 0;
      root.classList.add("editing-route");
      panel.classList.remove("is-hidden");
      layer.classList.remove("is-hidden");
      document.getElementById("routeTitle").textContent =
        `${actor.kind === "vehicle" ? "Vehicle" : "Ped"} ${actor.id} / Route`;
      document.getElementById("routeSeconds").value = result.duration || 3;
      document.getElementById("routeSpeed").value = result.speed || 3;
      document.getElementById("routeGait").value = result.gait || "auto";
      document.getElementById("routeTiming").value = result.speed ? "speed" : "duration";
      if (!action && root.classList.contains("guided")) {
        document.getElementById("routeTiming").value = "speed";
        document.getElementById("routeSpeed").value = actor.kind === "ped" ? "1.4" : "8";
        if (actor.kind === "ped") {
          document.getElementById("routeGait").value = "walk";
          suggestedSpeed = 1.4;
        }
      }
      document.getElementById("routeGaitField").classList.toggle("is-hidden", actor.kind !== "ped");
      timing();
      window.dispatchEvent(new MessageEvent("message", { data: { action: "routeControls" } }));
    },
  };
  document.getElementById("routeTiming").addEventListener("change", timing);
  for (const id of ["routeSeconds", "routeSpeed"])
    document.getElementById(id).addEventListener("input", updateEstimate);
  document.getElementById("routeSpeed").addEventListener("input", () => {
    suggestedSpeed = null;
  });
  document.getElementById("routeGait").addEventListener("change", () => {
    if (suggestedSpeed === null) return;
    suggestedSpeed =
      { walk: 1.4, run: 4, sprint: 6, auto: 1.4 }[document.getElementById("routeGait").value] ||
      1.4;
    document.getElementById("routeSpeed").value = suggestedSpeed;
    updateEstimate();
  });
  document.getElementById("routeCancel").addEventListener("click", cancel);
  document.getElementById("routeApply").addEventListener("click", async () => {
    if (busy || drag) return;
    busy = committing = true;
    const token = generation;
    document.getElementById("routeApply").disabled = true;
    const result = await call("commitRoute", {
      inspectObstacles: document.getElementById("routeInspectObstacles").checked,
      duration: Number(document.getElementById("routeSeconds").value),
      gait: document.getElementById("routeGait").value,
      ...(document.getElementById("routeTiming").value === "speed"
        ? { speed: Number(document.getElementById("routeSpeed").value) }
        : {}),
    });
    if (token !== generation) return;
    busy = committing = false;
    document.getElementById("routeApply").disabled = false;
    if (result.ok) {
      close();
      window.dispatchEvent(
        new MessageEvent("message", { data: { action: "saveState", saved: false } }),
      );
    } else status(result.message || "Could not apply route.");
  });
  const pointer = (event) => ({
    x: Math.max(0, Math.min(1, event.clientX / innerWidth)),
    y: Math.max(0, Math.min(1, event.clientY / innerHeight)),
    aspect: innerWidth / innerHeight,
    heightOnly: event.shiftKey,
  });
  const sendMove = async () => {
    scheduled = false;
    if (!drag?.ready || !pending) return;
    const point = pending;
    pending = null;
    await call("moveRoutePoint", { ...point, token: drag.token, sequence: ++sequence });
  };
  document.addEventListener(
    "mousedown",
    async (event) => {
      if (!active || event.button !== 0) return;
      const node = event.target.closest(".route-node");
      if (node) {
        event.preventDefault();
        event.stopImmediatePropagation();
        selected = Number(node.dataset.index);
        const session = { ready: false, token: ++sequence, routeToken, generation };
        drag = session;
        const result = await call("beginRoutePoint", {
          index: selected,
          token: session.token,
          ...pointer(event),
        });
        if (drag !== session || generation !== session.generation) {
          if (generation === session.generation)
            await call("endRoutePoint", { token: session.token, routeToken: session.routeToken });
          return;
        }
        session.ready = result.ok;
        if (!result.ok) drag = null;
        else if (pending) sendMove();
      } else if (event.target === document.getElementById("lookSurface")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (busy) return;
        busy = true;
        const token = generation;
        const result = await call("addRoutePoint", pointer(event));
        if (token !== generation) return;
        busy = false;
        if (!result.ok) status(result.message || "Could not place point.");
      }
    },
    true,
  );
  window.addEventListener("mousemove", (event) => {
    if (!drag) return;
    pending = pointer(event);
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(sendMove);
    }
  });
  window.addEventListener("mouseup", async (event) => {
    if (event.button !== 0 || !drag) return;
    const session = drag;
    pending = pointer(event);
    await sendMove();
    if (generation !== session.generation) return;
    if (drag === session) drag = null;
    await call("endRoutePoint", { token: session.token, routeToken: session.routeToken });
  });
  document.addEventListener(
    "contextmenu",
    (event) => {
      const node = event.target.closest(".route-node");
      if (!active || !node) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      call("deleteRoutePoint", { index: Number(node.dataset.index) });
    },
    true,
  );
  document.addEventListener(
    "keydown",
    (event) => {
      if (modal(event.target)) return;
      if (active && event.key === "Escape") {
        event.preventDefault();
        event.stopImmediatePropagation();
        cancel();
        return;
      }
      if (active && event.key === "Delete" && selected && !event.target.matches("input,textarea")) {
        event.preventDefault();
        event.stopImmediatePropagation();
        call("deleteRoutePoint", { index: selected });
        selected = null;
        return;
      }
      if (
        (event.ctrlKey || event.metaKey) &&
        !event.target.matches("input,textarea,[contenteditable=true]") &&
        !root.classList.contains("is-hidden")
      ) {
        const key = event.key.toLowerCase();
        if (key === "z" || key === "y") {
          event.preventDefault();
          event.stopImmediatePropagation();
          document
            .getElementById(key === "y" || event.shiftKey ? "redoButton" : "undoButton")
            .click();
        }
      }
      if (
        !active &&
        !root.classList.contains("is-hidden") &&
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === "s"
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        document.getElementById("saveButton").click();
      }
      if (
        !active &&
        !root.classList.contains("is-hidden") &&
        event.code === "Space" &&
        !event.target.matches("input,textarea,select,button,[contenteditable=true]")
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        document
          .getElementById(
            window.DirectorEditor.state.previewPlaying ? "stopButton" : "previewButton",
          )
          ?.click();
      }
    },
    true,
  );
  for (const [id, name] of [
    ["undoButton", "undo"],
    ["redoButton", "redo"],
  ])
    document.getElementById(id).addEventListener("click", async () => {
      const result = await call(name);
      if (!result.ok) status(result.message || "History could not be restored.");
    });
  window.addEventListener("message", (event) => {
    const data = event.data || {};
    if (
      ["routeClosed", "routeScreen"].includes(data.action) &&
      data.routeToken !== undefined &&
      routeToken !== undefined &&
      data.routeToken !== routeToken
    )
      return;
    if (data.action === "historyState") {
      document.getElementById("undoButton").disabled = !data.undo || data.busy;
      document.getElementById("redoButton").disabled = !data.redo || data.busy;
    }
    if (data.action === "routeClosed" && committing)
      window.dispatchEvent(
        new MessageEvent("message", { data: { action: "saveState", saved: false } }),
      );
    if (["close", "routeClosed", "captureCountdown"].includes(data.action)) close();
    if (data.action !== "routeScreen") return;
    routeLength = Number(data.length) || 0;
    updateEstimate();
    document.getElementById("routeMeasure").textContent =
      `${data.count} points · ${Number(data.length || 0).toFixed(1)} m`;
    const lines = document.getElementById("routeLines");
    let path = lines.firstElementChild;
    if (!path) {
      path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      lines.appendChild(path);
    }
    path.setAttribute(
      "d",
      (data.lines || [])
        .map((segment) => "M" + segment.x1 + "," + segment.y1 + "L" + segment.x2 + "," + segment.y2)
        .join(" "),
    );
    const nodes = document.getElementById("routeNodes");
    const existing = new Map(
      Array.from(nodes.children).map((node) => [Number(node.dataset.index), node]),
    );
    for (const point of data.points || []) {
      let node = existing.get(point.index);
      existing.delete(point.index);
      if (!node) {
        node = document.createElement("button");
        node.type = "button";
        node.className = "route-node";
        node.dataset.index = point.index;
        node.textContent = point.index;
        node.title = "Drag to move · Shift: height · Right-click: remove";
        nodes.appendChild(node);
      }
      node.style.left = point.x * 100 + "%";
      node.style.top = point.y * 100 + "%";
      node.classList.toggle("selected", selected === point.index);
    }
    existing.forEach((node) => node.remove());
  });
})();
