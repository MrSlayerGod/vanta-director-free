window.DirectorEditor.modules.actionChain = function defineModule(ctx) {
  ctx.actionChain = {};
  const button = (text, action) => {
    const el = document.createElement("button");
    el.type = "button";
    el.textContent = text;
    el.onclick = action;
    el.disabled = ctx.state.sessionRole === "viewer";
    return el;
  };
  ctx.actionChain.controls = function controls(actor, action, index) {
    const fields = document.createElement("div");
    fields.className = "chain-fields";
    const field = (caption, value) => {
      const label = document.createElement("label");
      label.textContent = caption;
      const input = document.createElement("input");
      input.type = "number";
      input.min = "0";
      input.max = ctx.state.project.duration;
      input.step = "0.1";
      input.value = value;
      input.disabled = ctx.state.sessionRole === "viewer";
      label.appendChild(input);
      fields.appendChild(label);
      return input;
    };
    const time = field("Start (sec)", action.time);
    const duration =
      action.duration && action.type !== "recording"
        ? field("Length (sec)", action.duration)
        : null;
    if (duration) duration.min = "0.1";
    fields.appendChild(
      button("Apply timing", async () => {
        await ctx.transport.post("editActionTiming", {
          actorId: actor.id,
          actionId: action.id,
          time: Number(time.value),
          ...(duration ? { duration: Number(duration.value) } : {}),
          ripple: ctx.state.rippleActions === true,
        });
      }),
    );
    fields.appendChild(
      button("Next step at end", () =>
        ctx.timeline.seek(
          Math.min(ctx.state.project.duration, action.time + (action.duration || 0)),
        ),
      ),
    );
    const reorder = async (direction) => {
      const order = actor.actions.map((item) => item.id);
      const other = index + direction;
      if (other < 0 || other >= order.length) return;
      [order[index], order[other]] = [order[other], order[index]];
      await ctx.transport.post("chainActions", {
        actorId: actor.id,
        order,
        time: actor.actions[0].time,
      });
    };
    if (index) fields.appendChild(button("Move step earlier and join", () => reorder(-1)));
    if (index < actor.actions.length - 1)
      fields.appendChild(button("Move step later and join", () => reorder(1)));
    return fields;
  };
  ctx.actionChain.toolbar = function toolbar(actor) {
    const wrap = document.createElement("div");
    wrap.className = "chain-toolbar";
    const label = document.createElement("label");
    label.className = "chain-ripple";
    const toggle = document.createElement("input");
    toggle.type = "checkbox";
    toggle.checked = ctx.state.rippleActions === true;
    toggle.onchange = () => {
      ctx.state.rippleActions = toggle.checked;
    };
    label.append(toggle, document.createTextNode("Move following steps too"));
    wrap.appendChild(label);
    wrap.appendChild(
      button("Join steps", () =>
        ctx.transport.post("chainActions", {
          actorId: actor.id,
          order: actor.actions.map((action) => action.id),
          time: actor.actions[0].time,
        }),
      ),
    );
    wrap.appendChild(button("Save actions as preset", () => ctx.presets.open("actions")));
    return wrap;
  };
  return function bindEvents() {};
};
