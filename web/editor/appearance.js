window.DirectorEditor.modules.appearance = function defineModule(ctx) {
  ctx.appearance = {};
  ctx.appearance.appearancePanel = function appearancePanel(actor) {
    const panel = ctx.inspector.inspectorGroup(actor, "Appearance", false);
    panel.classList.add("appearance-panel");
    const body = document.createElement("div");
    body.className = "appearance-body";
    panel.appendChild(body);
    let loaded = false,
      busy = false,
      selectedSlot = "",
      options;
    const field = (label, input) => {
      const el = document.createElement("label");
      el.className = "scene-label";
      el.textContent = label;
      el.appendChild(input);
      body.appendChild(el);
      return el;
    };
    const select = (items, value) => {
      const el = document.createElement("select");
      for (const [id, name] of items) {
        const o = document.createElement("option");
        o.value = String(id);
        o.textContent = name;
        el.appendChild(o);
      }
      el.value = String(value);
      return el;
    };
    const apply = async (appearance) => {
      if (busy) return;
      busy = true;
      body.classList.add("is-applying");
      try {
        const result = await ctx.transport.post("setActorAppearance", {
          id: actor.id,
          appearance,
        });
        if (!result.ok) {
          ctx.status.showStatus(result.message || "Could not apply appearance.");
          return;
        }
        actor.appearance = result.appearance;
        options = result.options;
        paint();
      } finally {
        busy = false;
        body.classList.remove("is-applying");
      }
    };
    const paint = () => {
      body.innerHTML = "";
      if (!options) {
        body.textContent = "Appearance is unavailable.";
        return;
      }
      if (actor.kind === "ped") {
        const slots = [
          ...(options.components || []).map((v) => ({
            ...v,
            type: "components",
          })),
          ...(options.props || []).map((v) => ({ ...v, type: "props" })),
        ];
        if (!slots.length) {
          body.textContent = "This model has no clothing variations.";
          return;
        }
        if (!slots.some((v) => v.type + ":" + v.id === selectedSlot))
          selectedSlot = slots[0].type + ":" + slots[0].id;
        const slot = slots.find((v) => v.type + ":" + v.id === selectedSlot);
        const slotSelect = select(
          slots.map((v) => [v.type + ":" + v.id, v.name]),
          selectedSlot,
        );
        field("CLOTHING / ACCESSORY", slotSelect);
        slotSelect.addEventListener("change", () => {
          selectedSlot = slotSelect.value;
          paint();
        });
        const stepper = document.createElement("div");
        stepper.className = "appearance-stepper";
        const min = slot.type === "props" ? -1 : 0,
          max = slot.count - 1;
        const changeDrawable = (value) => {
          if (!Number.isInteger(value) || value < min || value > max)
            return ctx.status.showStatus("Choose an available variation.");
          apply({
            [slot.type]: [
              {
                id: slot.id,
                drawable: value,
                texture: 0,
                palette: slot.palette || 0,
              },
            ],
          });
        };
        const number = document.createElement("input");
        number.type = "number";
        number.min = String(min);
        number.max = String(max);
        number.step = "1";
        number.value = String(slot.drawable);
        number.setAttribute("aria-label", "Clothing variation");
        for (const [delta, label] of [
          [-1, "Previous variation"],
          [1, "Next variation"],
        ]) {
          const b = document.createElement("button");
          b.textContent = delta < 0 ? "\u2212" : "+";
          b.title = label;
          b.setAttribute("aria-label", label);
          b.disabled = slot.drawable + delta < min || slot.drawable + delta > max;
          b.addEventListener("click", () => changeDrawable(slot.drawable + delta));
          stepper.appendChild(b);
          if (delta < 0) stepper.appendChild(number);
        }
        number.addEventListener("change", () => changeDrawable(Number(number.value)));
        field("VARIATION", stepper);
        const textures = select(
          Array.from({ length: Math.max(1, slot.textures) }, (_, i) => [i, "Texture " + (i + 1)]),
          slot.texture,
        );
        textures.disabled = slot.drawable < 0;
        field("TEXTURE / COLOUR", textures);
        textures.addEventListener("change", () =>
          apply({
            [slot.type]: [
              {
                id: slot.id,
                drawable: slot.drawable,
                texture: Number(textures.value),
                palette: slot.palette || 0,
              },
            ],
          }),
        );
        const hint = document.createElement("p");
        hint.className = "scene-hint";
        hint.textContent =
          (slot.drawable < 0
            ? "Accessory removed. "
            : "Variation " + (slot.drawable + 1) + " / " + slot.count + ". ") +
          "Changes appear directly on the ped. Clothing combinations depend on the model.";
        body.appendChild(hint);
        if (options.freemode) {
          const details = document.createElement("details");
          details.className = "inspector-group";
          const summary = document.createElement("summary");
          summary.textContent = "Face & colours";
          details.appendChild(summary);
          body.appendChild(details);
          const numeric = (label, value, min, max, step, change) => {
            const row = document.createElement("label");
            row.className = "scene-label";
            row.textContent = label;
            const input = document.createElement("input");
            Object.assign(input, {
              type: "number",
              min: String(min),
              max: String(max),
              step: String(step),
              value: String(value),
            });
            input.setAttribute("aria-label", label);
            input.addEventListener("change", () => {
              const v = Number(input.value);
              if (Number.isFinite(v) && v >= min && v <= max) change(v);
              else ctx.status.showStatus("Choose an available value.");
            });
            row.appendChild(input);
            details.appendChild(row);
          };
          if (options.hair)
            for (const [index, label] of [
              [0, "HAIR COLOUR"],
              [1, "HIGHLIGHT COLOUR"],
            ])
              numeric(label, options.hair[index], 0, 63, 1, (v) => {
                const hair = [...options.hair];
                hair[index] = v;
                apply({ hair });
              });
          if (options.eye !== undefined)
            numeric("EYE COLOUR", options.eye, 0, 31, 1, (v) => apply({ eye: v }));
          const features = [
            "Nose width",
            "Nose peak",
            "Nose length",
            "Nose bone",
            "Nose tip",
            "Nose twist",
            "Brow height",
            "Brow depth",
            "Cheek height",
            "Cheek size",
            "Cheek width",
            "Eye opening",
            "Lip thickness",
            "Jaw width",
            "Jaw shape",
            "Chin height",
            "Chin length",
            "Chin shape",
            "Chin cleft",
            "Neck thickness",
          ];
          for (const feature of options.face || [])
            numeric(features[feature.id], feature.value, -1, 1, 0.05, (v) =>
              apply({ face: [{ id: feature.id, value: v }] }),
            );
        }
      } else {
        for (const name of ["primary", "secondary"]) {
          const rgb = actor.appearance?.[name] || options[name];
          const hex = rgb
            ? "#" + rgb.map((v) => Number(v).toString(16).padStart(2, "0")).join("")
            : "";
          const input = document.createElement("input");
          input.type = "text";
          input.value = hex.toUpperCase();
          input.maxLength = 7;
          input.placeholder = "Original paint - choose a custom colour";
          input.setAttribute("aria-label", name + " paint hex colour");
          const applyHex = (value) => {
            if (!/^#[0-9a-f]{6}$/i.test(value))
              return ctx.status.showStatus("Use a colour such as #28B8F4.");
            apply({
              [name]: [1, 3, 5].map((i) => parseInt(value.slice(i, i + 2), 16)),
            });
          };
          input.addEventListener("change", () => applyHex(input.value.trim()));
          field(name.toUpperCase() + " PAINT (HEX)", input);
          const swatches = document.createElement("div");
          swatches.className = "appearance-swatches";
          for (const [colour, label] of [
            ["#28B8F4", "Vanta cyan"],
            ["#1754DC", "Vanta blue"],
            ["#091526", "Navy"],
            ["#111111", "Black"],
            ["#FFFFFF", "White"],
            ["#AF1F2D", "Red"],
            ["#D4B86A", "Gold"],
            ["#647568", "Green"],
          ]) {
            const b = document.createElement("button");
            b.style.backgroundColor = colour;
            b.title = label;
            b.setAttribute("aria-label", name + " paint " + label);
            b.addEventListener("click", () => applyHex(colour));
            swatches.appendChild(b);
          }
          body.appendChild(swatches);
        }
        for (const [key, count, label] of [
          ["livery", options.liveries, "LIVERY"],
          ["modLivery", options.modLiveries, "MOD LIVERY"],
        ])
          if (count > 0) {
            const el = select(
              [
                [-1, "Standard"],
                ...Array.from({ length: count }, (_, i) => [i, "Livery " + (i + 1)]),
              ],
              options[key],
            );
            field(label, el);
            el.addEventListener("change", () => apply({ [key]: Number(el.value) }));
          }
        for (const extra of options.extras || []) {
          const row = document.createElement("label");
          row.className = "ped-auto-duration";
          const check = document.createElement("input");
          check.type = "checkbox";
          check.checked = extra.enabled;
          row.appendChild(check);
          const text = document.createElement("span");
          text.textContent = "Extra " + extra.id;
          row.appendChild(text);
          body.appendChild(row);
          check.addEventListener("change", () =>
            apply({ extras: [{ id: extra.id, enabled: check.checked }] }),
          );
        }
        if (options.mods?.length) {
          const mods = options.mods;
          if (!mods.some((v) => "mod:" + v.id === selectedSlot)) selectedSlot = "mod:" + mods[0].id;
          const mod = mods.find((v) => "mod:" + v.id === selectedSlot);
          const category = select(
            mods.map((v) => ["mod:" + v.id, v.name]),
            selectedSlot,
          );
          field("CUSTOMIZATION", category);
          category.addEventListener("change", () => {
            selectedSlot = category.value;
            paint();
          });
          const variation = select(
            [
              [-1, "Stock"],
              ...Array.from({ length: mod.count }, (_, i) => [i, "Option " + (i + 1)]),
            ],
            mod.index,
          );
          field("MODIFICATION", variation);
          variation.addEventListener("change", () =>
            apply({
              mods: [
                {
                  id: mod.id,
                  index: Number(variation.value),
                  custom: mod.custom,
                },
              ],
            }),
          );
        }
        if (options.wheelType !== undefined) {
          const wheel = select(
            [
              "Sport",
              "Muscle",
              "Lowrider",
              "SUV",
              "Off road",
              "Tuner",
              "Bike",
              "High end",
              "Benny original",
              "Benny bespoke",
              "Open wheel",
              "Street",
              "Track",
            ].map((v, i) => [i, v]),
            options.wheelType,
          );
          field("WHEEL FAMILY", wheel);
          wheel.addEventListener("change", () =>
            apply({
              wheelType: Number(wheel.value),
              mods: [
                { id: 23, index: -1 },
                { id: 24, index: -1 },
              ],
            }),
          );
        }
        if (options.tint !== undefined) {
          const tint = select(
            [
              [-1, "Original"],
              [0, "None"],
              [1, "Pure black"],
              [2, "Dark smoke"],
              [3, "Light smoke"],
              [4, "Stock"],
              [5, "Limo"],
              [6, "Green"],
            ],
            options.tint,
          );
          field("WINDOW TINT", tint);
          tint.addEventListener("change", () => apply({ tint: Number(tint.value) }));
        }
        if (options.plate !== undefined) {
          const plate = document.createElement("input");
          plate.value = options.plate;
          plate.maxLength = 8;
          plate.setAttribute("aria-label", "License plate");
          field("LICENSE PLATE", plate);
          plate.addEventListener("change", () =>
            apply({ plate: plate.value.trim().toUpperCase() }),
          );
        }
        for (const toggle of options.toggles || []) {
          const row = document.createElement("label");
          row.className = "ped-auto-duration";
          const input = document.createElement("input");
          input.type = "checkbox";
          input.checked = toggle.enabled;
          row.append(input, document.createTextNode(toggle.name));
          body.appendChild(row);
          input.addEventListener("change", () =>
            apply({ toggles: [{ id: toggle.id, enabled: input.checked }] }),
          );
        }
        const hint = document.createElement("p");
        hint.className = "scene-hint";
        hint.textContent =
          "Paint uses custom RGB colours. Liveries and extras appear only when supported by the vehicle.";
        body.appendChild(hint);
      }
    };
    const load = async () => {
      if (loaded || !panel.open) return;
      loaded = true;
      body.textContent = "Loading available options...";
      const result = await ctx.transport.post("getActorAppearance", { id: actor.id });
      if (result.ok) {
        options = result.options;
        paint();
      } else {
        loaded = false;
        body.textContent = result.message || "Could not load appearance.";
      }
    };
    panel.addEventListener("toggle", load);
    if (panel.open) load();
    return panel;
  };
  return function bindEvents() {};
};
