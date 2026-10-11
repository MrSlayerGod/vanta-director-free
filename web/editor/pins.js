window.DirectorEditor.modules.pins = function defineModule(ctx) {
  ctx.pins = {};
  ctx.pins.renderActorPins = function renderActorPins(positions) {
    const container = document.getElementById("actorPins");
    const visible = new Set();
    positions.forEach((position) => {
      visible.add(position.id);
      let pin = ctx.state.actorPinElements.get(position.id);
      if (!pin) {
        pin = document.createElement("div");
        pin.className = "actor-pin";
        const label = document.createElement("span");
        label.textContent = `${position.kind === "vehicle" ? "VEHICLE" : ctx.formatting.actorLabel(position.kind, true)} ${position.id}`;
        const rotate = document.createElement("button");
        rotate.className = "rotate-grip";
        rotate.type = "button";
        rotate.textContent = "↻";
        rotate.title = "Drag to rotate";
        rotate.addEventListener("mousedown", (event) =>
          ctx.input.startActorDrag(event, position.id, "rotate"),
        );
        pin.appendChild(label);
        pin.appendChild(rotate);
        container.appendChild(pin);
        ctx.state.actorPinElements.set(position.id, pin);
      }
      pin.style.left = `${position.x * 100}%`;
      ctx.status.setText(
        pin.children[0],
        `${position.kind === "vehicle" ? "VEHICLE" : ctx.formatting.actorLabel(position.kind, true)} ${position.id}`,
      );
      pin.style.top = `${position.y * 100}%`;
      if (position.id === ctx.state.selectedActorId) pin.classList.add("selected");
      else pin.classList.remove("selected");
    });
    for (const [id, pin] of ctx.state.actorPinElements) {
      if (!visible.has(id)) {
        pin.remove();
        ctx.state.actorPinElements.delete(id);
      }
    }
    for (const card of document.getElementById("actorList").children) {
      if (card.actorId === ctx.state.selectedActorId) card.classList.add("selected");
      else card.classList.remove("selected");
    }
  };
  return function bindEvents() {};
};
