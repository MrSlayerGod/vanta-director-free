window.DirectorEditor.modules.accessories = function defineModule(ctx) {
  ctx.accessories = {};
  ctx.accessories.accessoryPanel = function accessoryPanel(actor) {
    const attached = !!actor.attachment;
    const panel = ctx.inspector.inspectorGroup(
      actor,
      attached ? "Attachment" : "Accessories",
      attached,
    );
    panel.classList.add("accessory-panel");
    const body = document.createElement("div");
    body.className = "appearance-body";
    panel.appendChild(body);
    const field = (title, input) => {
      const label = document.createElement("label");
      label.className = "scene-label";
      label.textContent = title;
      label.appendChild(input);
      body.appendChild(label);
    };
    const dropdown = (items, value) => {
      const el = document.createElement("select");
      for (const [id, label] of items) {
        const o = document.createElement("option");
        o.value = String(id);
        o.textContent = label;
        el.appendChild(o);
      }
      el.value = String(value);
      return el;
    };
    const bones = [
      ["rightHand", "Right hand"],
      ["leftHand", "Left hand"],
      ["back", "Back"],
      ["head", "Head"],
      ["pelvis", "Waist"],
    ];
    if (!attached) {
      const presets = [
        ["prop_phone_ing", "Phone", "rightHand", 0.1, 0, 0, 0, 0, 0],
        ["prop_pap_camera_01", "Camera", "rightHand", 0.1, 0, 0, 0, 0, 0],
        ["p_ld_heist_bag_s", "Bag", "back", 0, -0.15, 0, 0, 90, 0],
        ["w_pi_pistol", "Pistol (visual prop)", "rightHand", 0.1, 0, 0, 0, 0, 0],
      ];
      const choice = dropdown(
        [...presets.map((p) => [p[0], p[1]]), ["custom", "Custom object"]],
        presets[0][0],
      );
      field("ACCESSORY", choice);
      const custom = document.createElement("input");
      custom.type = "text";
      custom.placeholder = "Object model name";
      custom.classList.add("is-hidden");
      body.appendChild(custom);
      const bone = dropdown(bones, "rightHand");
      field("ATTACH TO", bone);
      choice.addEventListener("change", () => {
        custom.classList.toggle("is-hidden", choice.value !== "custom");
        const p = presets.find((p) => p[0] === choice.value);
        if (p) bone.value = p[2];
      });
      const add = document.createElement("button");
      add.className = "aim-button";
      add.textContent = "Add accessory at playhead";
      add.addEventListener("click", async () => {
        const preset = presets.find((p) => p[0] === choice.value);
        const coords = preset?.slice(3) || [0, 0, 0, 0, 0, 0];
        add.disabled = true;
        try {
          const attachment = {
            parentId: actor.id,
            bone: bone.value,
            visible: false,
          };
          ["x", "y", "z", "rx", "ry", "rz"].forEach((key, i) => (attachment[key] = coords[i]));
          const result = await ctx.transport.post("addAccessory", {
            parentId: actor.id,
            model: preset?.[0] || custom.value.trim(),
            attachment,
          });
          if (!result.ok)
            return ctx.status.showStatus(result.message || "Could not add accessory.");
          if (ctx.state.project.actors.some((a) => a.id === result.id)) {
            ctx.state.selectedActorId = result.id;
            ctx.actors.renderActors();
          } else ctx.state.pendingAccessorySelection = result.id;
        } finally {
          add.disabled = false;
        }
      });
      body.appendChild(add);
    } else {
      let busy = false;
      const update = async (changes) => {
        if (busy) return;
        busy = true;
        body.classList.add("is-applying");
        try {
          const result = await ctx.transport.post("setAttachment", {
            id: actor.id,
            attachment: { ...actor.attachment, ...changes },
          });
          if (!result.ok) {
            ctx.status.showStatus(result.message || "Could not adjust accessory.");
            return;
          }
          actor.attachment = result.attachment;
          paint();
        } finally {
          busy = false;
          body.classList.remove("is-applying");
        }
      };
      const paint = () => {
        body.innerHTML = "";
        const parent = dropdown(
          ctx.state.project.actors
            .filter((p) => p.kind === "ped")
            .map((p) => [p.id, ctx.inspector.sceneElementName(p)]),
          actor.attachment.parentId,
        );
        field("ACTOR", parent);
        parent.addEventListener("change", () => update({ parentId: Number(parent.value) }));
        const bone = dropdown(bones, actor.attachment.bone);
        field("ATTACH TO", bone);
        bone.addEventListener("change", () => update({ bone: bone.value }));
        for (const [key, label, step] of [
          ["x", "Left / right", 0.01],
          ["y", "Back / forward", 0.01],
          ["z", "Down / up", 0.01],
          ["rx", "Tilt", 5],
          ["ry", "Roll", 5],
          ["rz", "Turn", 5],
        ]) {
          const row = document.createElement("div");
          row.className = "appearance-stepper";
          const number = document.createElement("input");
          number.type = "number";
          number.step = String(step);
          number.min = key.startsWith("r") ? "-360" : "-2";
          number.max = key.startsWith("r") ? "360" : "2";
          number.value = actor.attachment[key].toFixed(key.startsWith("r") ? 0 : 2);
          number.setAttribute("aria-label", label + " accessory");
          for (const delta of [-1, 1]) {
            const b = document.createElement("button");
            b.innerHTML =
              '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10' +
              (delta > 0 ? "M8 3v10" : "") +
              '"/></svg>';
            b.setAttribute("aria-label", label + (delta < 0 ? " decrease" : " increase"));
            b.addEventListener("click", () =>
              update({
                [key]: Number((actor.attachment[key] + delta * step).toFixed(3)),
              }),
            );
            row.appendChild(b);
            if (delta < 0) row.appendChild(number);
          }
          number.addEventListener("change", () => update({ [key]: Number(number.value) }));
          field(label.toUpperCase() + (key.startsWith("r") ? " (DEG)" : " (M)"), row);
        }
        const zero = document.createElement("button");
        zero.className = "aim-button";
        zero.textContent = "Reset offsets";
        zero.addEventListener("click", () => update({ x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 }));
        body.appendChild(zero);
      };
      paint();
    }
    const hint = document.createElement("p");
    hint.className = "scene-hint";
    hint.textContent = attached
      ? "Watch the object in the scene while adjusting. Show/hide cues below control when it is worn."
      : "Creates a visual object, not a usable item or weapon. Choose a matching ped animation separately.";
    panel.appendChild(hint);
    return panel;
  };
  return function bindEvents() {};
};
