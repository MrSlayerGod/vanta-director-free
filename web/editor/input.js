window.DirectorEditor.modules.input = function defineModule(ctx) {
  ctx.input = {};
  ctx.input.startActorDrag = function startActorDrag(event, id, mode) {
    if (event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    ctx.state.leftHeld = true;
    ctx.state.actorDragPointer = {
      x: event.clientX / window.innerWidth,
      y: event.clientY / window.innerHeight,
      heightOnly: event.shiftKey,
    };
    ctx.transport
      .post("beginActorDrag", {
        ...ctx.state.actorDragPointer,
        id,
        mode,
        aspect: window.innerWidth / window.innerHeight,
      })
      .then(async (result) => {
        if (!result.ok) return;
        ctx.state.selectedActorId = result.id;
        if (!ctx.state.leftHeld) {
          await ctx.transport.post("endActorDrag");
          return;
        }
        ctx.status.setLookHint(
          mode === "rotate"
            ? "DRAG LEFT / RIGHT TO ROTATE"
            : "DRAG TO MOVE · HOLD SHIFT FOR HEIGHT",
        );
        ctx.state.actorDragging = true;
        ctx.elements.lookSurface.classList.add("dragging-actor");
        ctx.input.queueActorDrag();
      });
  };

  ctx.input.queueActorDrag = function queueActorDrag() {
    if (ctx.state.actorDragScheduled || !ctx.state.actorDragging) return;
    ctx.state.actorDragScheduled = true;
    requestAnimationFrame(() => {
      ctx.state.actorDragScheduled = false;
      if (ctx.state.actorDragging && ctx.state.actorDragPointer)
        ctx.transport.post("dragActor", {
          ...ctx.state.actorDragPointer,
          sequence: ++ctx.state.actorDragSequence,
        });
    });
  };

  ctx.input.isTyping = function isTyping() {
    const target = document.activeElement;
    return (
      target &&
      (target.tagName === "TEXTAREA" ||
        target.isContentEditable ||
        (target.tagName === "INPUT" && !["range", "button", "checkbox"].includes(target.type)))
    );
  };

  ctx.input.normalizedKey = function normalizedKey(event) {
    const layout = window.VantaPreferences?.layout;
    if (layout && /^[a-z]$/i.test(event.key || "") && event.key.toLowerCase() !== "k") {
      const letters =
        layout === "qwerty"
          ? { w: "w", a: "a", s: "s", d: "d", q: "q", e: "e" }
          : { z: "w", q: "a", s: "s", d: "d", a: "q", e: "e" };
      return letters[event.key.toLowerCase()] || null;
    }
    if (event.code) return ctx.state.physicalKeys[event.code] || null;
    // Legacy fallback for AZERTY; CEF normally provides the physical code.
    return (
      {
        z: "w",
        q: "a",
        s: "s",
        d: "d",
        a: "q",
        e: "e",
        k: "k",
        Escape: "escape",
        ArrowLeft: "arrowleft",
        ArrowRight: "arrowright",
        ArrowUp: "arrowup",
        ArrowDown: "arrowdown",
      }[event.key] || null
    );
  };

  ctx.input.sendKeys = function sendKeys() {
    if (!ctx.state.bridgeReady || ctx.elements.root.classList.contains("is-hidden")) return;
    ctx.transport.post("setKeys", {
      keys: { ...ctx.state.keyState },
      sequence: ++ctx.state.keySequence,
    });
  };

  ctx.input.clearKeys = function clearKeys(notifyGame = true) {
    ctx.state.keyState = {};
    if (notifyGame) ctx.input.sendKeys();
  };

  ctx.input.updateKeyState = function updateKeyState(key, pressed) {
    if (
      !key ||
      !Object.values(ctx.state.physicalKeys).includes(key) ||
      key === "escape" ||
      key === "k"
    )
      return;
    if (ctx.state.keyState[key] === pressed) return;
    ctx.state.keyState[key] = pressed;
    ctx.input.sendKeys();
  };
  return function bindEvents() {
    ctx.elements.lookSurface.addEventListener("contextmenu", (event) => event.preventDefault());

    ctx.elements.lookSurface.addEventListener("mousedown", (event) => {
      if (event.button === 2) {
        event.preventDefault();
        ctx.state.looking = true;
        ctx.state.lastMouseX = Number.isFinite(event.clientX) ? event.clientX : null;
        ctx.state.lastMouseY = Number.isFinite(event.clientY) ? event.clientY : null;
        ctx.elements.lookSurface.classList.add("looking");
      } else if (event.button === 0) {
        ctx.input.startActorDrag(event, null, event.altKey ? "rotate" : "move");
      }
    });

    window.addEventListener("mouseup", (event) => {
      if (event.button === 2) {
        ctx.state.looking = false;
        ctx.state.lastMouseX = ctx.state.lastMouseY = null;
        ctx.elements.lookSurface.classList.remove("looking");
      }
      if (event.button === 0 && ctx.state.leftHeld) {
        ctx.state.leftHeld = false;
        const pointer = ctx.state.actorDragPointer;
        const wasDragging = ctx.state.actorDragging;
        ctx.state.actorDragging = false;
        ctx.elements.lookSurface.classList.remove("dragging-actor");
        ctx.status.setLookHint(null);
        if (wasDragging) {
          (async () => {
            if (pointer)
              await ctx.transport.post("dragActor", {
                ...pointer,
                sequence: ++ctx.state.actorDragSequence,
              });
            await ctx.transport.post("endActorDrag");
          })();
        }
      }
    });

    window.addEventListener("mousemove", (event) => {
      if (!ctx.state.leftHeld) return;
      ctx.state.actorDragPointer = {
        x: event.clientX / window.innerWidth,
        y: event.clientY / window.innerHeight,
        heightOnly: event.shiftKey,
      };
      ctx.input.queueActorDrag();
    });

    window.addEventListener("mousemove", (event) => {
      if (!ctx.state.looking || !(event.buttons & 2)) return;
      const fallbackX = ctx.state.lastMouseX === null ? 0 : event.clientX - ctx.state.lastMouseX;
      const fallbackY = ctx.state.lastMouseY === null ? 0 : event.clientY - ctx.state.lastMouseY;
      ctx.state.lookDeltaX += Number.isFinite(event.movementX) ? event.movementX : fallbackX;
      ctx.state.lookDeltaY += Number.isFinite(event.movementY) ? event.movementY : fallbackY;
      ctx.state.lastMouseX = Number.isFinite(event.clientX) ? event.clientX : null;
      ctx.state.lastMouseY = Number.isFinite(event.clientY) ? event.clientY : null;
      if (!ctx.state.lookScheduled) {
        ctx.state.lookScheduled = true;
        requestAnimationFrame(() => {
          ctx.state.lookScheduled = false;
          const x = ctx.state.lookDeltaX,
            y = ctx.state.lookDeltaY;
          ctx.state.lookDeltaX = ctx.state.lookDeltaY = 0;
          if (x || y) ctx.transport.post("mouseLook", { x, y });
        });
      }
    });

    document.addEventListener("keydown", (event) => {
      if (!ctx.elements.modelOverlay.classList.contains("is-hidden")) {
        if (event.key === "Escape") {
          event.preventDefault();
          ctx.models.closeModels();
        }
        return;
      }
      if (ctx.elements.root.classList.contains("is-hidden")) return;
      const key = ctx.input.normalizedKey(event);
      if (!ctx.elements.exitOverlay.classList.contains("is-hidden")) {
        if (key === "escape") {
          event.preventDefault();
          ctx.elements.exitOverlay.classList.add("is-hidden");
        }
        return;
      }
      if (!ctx.elements.libraryOverlay.classList.contains("is-hidden")) {
        if (key === "escape") {
          event.preventDefault();
          if (!ctx.elements.libraryConfirm.classList.contains("is-hidden")) {
            ctx.elements.libraryConfirm.classList.add("is-hidden");
            ctx.state.pendingLibraryConfirm = null;
          } else ctx.library.closeLibrary();
        }
        return;
      }
      if (!ctx.elements.animationOverlay.classList.contains("is-hidden")) {
        if (key === "escape") {
          event.preventDefault();
          ctx.animations.closeAnimationCatalog();
        }
        return;
      }
      if (!ctx.elements.animationPreviewBar.classList.contains("is-hidden")) {
        if (key === "escape") {
          event.preventDefault();
          document.getElementById("animationBarBackButton").click();
        }
        return;
      }
      if (key === "escape") {
        event.preventDefault();
        ctx.lifecycle.requestClose();
        return;
      }
      if (ctx.input.isTyping()) return;
      if (!window.VantaPreferences && ctx.state.hintIds[event.code] && event.key.length === 1) {
        document.getElementById(ctx.state.hintIds[event.code]).textContent =
          event.key.toUpperCase();
      }
      if (
        ["w", "a", "s", "d", "q", "e", "arrowleft", "arrowright", "arrowup", "arrowdown"].includes(
          key,
        )
      ) {
        event.preventDefault();
        ctx.input.updateKeyState(key, true);
      }
      if (key === "k" && !event.repeat)
        ctx.transport
          .post("addKeyframe", { time: ctx.state.project.playhead })
          .then((result) => result.message && ctx.status.showStatus(result.message));
    });

    document.addEventListener("keyup", (event) =>
      ctx.input.updateKeyState(ctx.input.normalizedKey(event), false),
    );

    window.addEventListener("blur", () => {
      if (ctx.state.actorDragging) ctx.transport.post("endActorDrag");
      ctx.input.clearKeys(false);
      ctx.state.looking = false;
      ctx.state.lastMouseX = ctx.state.lastMouseY = null;
      ctx.elements.lookSurface.classList.remove("looking");
      ctx.state.actorDragging = ctx.state.leftHeld = false;
      ctx.status.setLookHint(null);
      ctx.elements.lookSurface.classList.remove("dragging-actor");
    });

    setInterval(() => {
      if (
        ctx.state.bridgeReady &&
        !ctx.elements.root.classList.contains("is-hidden") &&
        Object.values(ctx.state.keyState).some(Boolean)
      )
        ctx.input.sendKeys();
    }, 250);

    window.addEventListener("beforeunload", () => {
      ctx.state.bridgeReady = false;
      ctx.state.keyState = {};
    });
  };
};
