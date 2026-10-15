window.DirectorEditor.modules.actors = function defineModule(ctx) {
  ctx.actors = {};
  ctx.actors.placeCached = function placeCached(parent, node, index) {
    if (parent.children[index] !== node) {
      if (parent.insertBefore) parent.insertBefore(node, parent.children[index] || null);
      else parent.appendChild(node);
    }
  };

  ctx.actors.renderActors = function renderActors() {
    ctx.camera.renderShotSubjects();
    ctx.production.renderProductionSelectors();
    const list = document.getElementById("actorList");
    const inspector = document.getElementById("actorInspector");
    const targets = JSON.stringify(
      ctx.state.project.actors.map((a) => [
        a.id,
        a.kind,
        a.model,
        a.name,
        a.group,
        a.modelAvailable,
        ctx.inspector.sceneElementName(a),
      ]),
    );
    const selected =
      ctx.state.project.actors.find((a) => a.id === ctx.state.selectedActorId) ||
      ctx.state.project.actors[0];
    const nextInspectorSignature = JSON.stringify([
      selected,
      targets,
      ctx.state.project.duration,
      ctx.state.modelsLoaded,
      window.VantaPreferences?.language,
    ]);
    const rebuildInspector = nextInspectorSignature !== ctx.state.inspectorSignature;
    if (rebuildInspector) {
      inspector.innerHTML = "";
      ctx.state.inspectorSignature = nextInspectorSignature;
    }
    const present = new Set(ctx.state.project.actors.map((a) => a.id));
    for (const [id, cached] of ctx.state.actorRenderCache)
      if (!present.has(id)) {
        cached.node.remove();
        ctx.state.actorRenderCache.delete(id);
      }
    document.getElementById("actorCount").textContent = String(
      ctx.state.project.actors.length,
    ).padStart(2, "0");
    document
      .getElementById("emptyActors")
      .classList.toggle("is-hidden", ctx.state.project.actors.length > 0);
    document
      .getElementById("actorNote")
      .classList.toggle("is-hidden", ctx.state.project.actors.length === 0);
    ctx.elements.root.classList.toggle("empty-timeline", ctx.state.project.actors.length === 0);
    ctx.elements.root.classList.toggle("few-tracks", ctx.state.project.actors.length === 1);
    inspector.classList.toggle("empty-inspector", ctx.state.project.actors.length === 0);
    if (ctx.state.project.actors.length === 0) {
      document.getElementById("actorPins").innerHTML = "";
      ctx.state.actorPinElements.clear();
    }
    if (
      ctx.state.project.actors.length &&
      !ctx.state.project.actors.some((actor) => actor.id === ctx.state.selectedActorId)
    ) {
      ctx.state.selectedActorId = ctx.state.project.actors[0].id;
      if (ctx.state.bridgeReady)
        ctx.transport.post("selectActor", { id: ctx.state.selectedActorId });
    }
    ctx.state.project.actors.forEach((actor, actorIndex) => {
      const selected = actor.id === ctx.state.selectedActorId;
      const signature = JSON.stringify([
        selected,
        selected
          ? actor
          : [
              actor.id,
              actor.kind,
              actor.model,
              actor.name,
              actor.group,
              actor.modelAvailable,
              ctx.inspector.sceneElementName(actor),
            ],
        selected ? targets : null,
        selected ? ctx.state.project.duration : null,
        ctx.state.modelsLoaded,
      ]);
      const cached = ctx.state.actorRenderCache.get(actor.id);
      if (cached?.signature === signature && (!selected || !rebuildInspector)) {
        ctx.actors.placeCached(list, cached.node, actorIndex);
        return;
      }
      if (cached) cached.node.remove();
      const card = document.createElement("div");
      card.className = "actor-card";
      card.actorId = actor.id;
      if (actor.id === ctx.state.selectedActorId) card.classList.add("selected");
      const header = document.createElement("header");
      const label = document.createElement("strong");
      label.textContent = ctx.inspector.sceneElementName(actor);
      if (actor.name) label.dataset.i18nUser = "true";
      const remove = document.createElement("button");
      remove.className = "delete-frame";
      remove.textContent = "×";
      remove.title = "Remove actor";
      remove.addEventListener("click", () => ctx.transport.post("deleteActor", { id: actor.id }));
      header.appendChild(label);
      header.appendChild(remove);
      const coordinates = document.createElement("small");
      coordinates.textContent = `${ctx.formatting.actorLabel(actor.kind)} ${String(actor.id).padStart(2, "0")}`;
      card.title = actor.model;
      card.classList.add(`scene-element-${actor.kind}`);
      const icon = document.createElement("span");
      icon.className = "actor-type-icon";
      icon.setAttribute("aria-hidden", "true");
      const paths = {
        ped: '<circle cx="12" cy="7" r="3"/><path d="M6 21v-5a6 6 0 0 1 12 0v5"/>',
        vehicle: '<path d="m5 9 2-5h10l2 5M4 10h16v9H4zM7 19v2m10-2v2M7 14h2m6 0h2"/>',
        prop: '<path d="m12 3 8 4v10l-8 4-8-4V7zm0 8 8-4m-8 4L4 7m8 4v10"/>',
      };
      icon.innerHTML = '<svg viewBox="0 0 24 24">' + (paths[actor.kind] || paths.prop) + "</svg>";
      if (actor.modelAvailable === false) {
        coordinates.textContent += " · Model unavailable";
        card.title += " · Install the model and reload this project";
      }
      if (!selected) {
        card.appendChild(header);
        card.appendChild(coordinates);
        card.appendChild(icon);
        card.addEventListener("click", (event) => {
          if (event.target.closest(".delete-frame")) return;
          ctx.state.selectedActorId = actor.id;
          ctx.transport.post("selectActor", { id: actor.id });
          ctx.actors.renderActors();
        });
        ctx.state.actorRenderCache.set(actor.id, { node: card, signature });
        ctx.actors.placeCached(list, card, actorIndex);
        return;
      }
      const transform = document.createElement("div");
      transform.className = "actor-transform";
      const inputs = {};
      for (const [field, title] of [
        ["x", "X"],
        ["y", "Y"],
        ["z", "Z"],
        ["heading", "Heading"],
      ]) {
        const wrapper = document.createElement("label");
        wrapper.textContent = title;
        const input = document.createElement("input");
        input.type = "number";
        input.step = field === "heading" ? "1" : "0.05";
        input.value = Number(actor[field]).toFixed(field === "heading" ? 1 : 2);
        inputs[field] = input;
        wrapper.appendChild(input);
        transform.appendChild(wrapper);
      }
      const updateTransform = async (aim) => {
        const data = { id: actor.id, aim };
        for (const field of ["x", "y", "z", "heading"]) {
          data[field] = Number(inputs[field].value);
          if (!Number.isFinite(data[field])) return ctx.status.showStatus("Invalid coordinates.");
        }
        const result = await ctx.transport.post("setActorTransform", data);
        if (!result.ok) ctx.status.showStatus(result.message || "Could not move actor.");
      };
      for (const input of Object.values(inputs))
        input.addEventListener("change", () => updateTransform(false));
      const aimButton = document.createElement("button");
      aimButton.className = "aim-button";
      aimButton.textContent = "Place at camera aim";
      aimButton.addEventListener("click", () => updateTransform(true));
      const controls = document.createElement("div");
      controls.className = "actor-controls";
      const movementField = document.createElement("label");
      movementField.className = "scene-label";
      movementField.textContent = "MOVE DURATION (SEC)";
      const movementDuration = document.createElement("input");
      movementDuration.type = "number";
      movementDuration.min = "0.1";
      movementDuration.max = String(ctx.state.project.duration);
      movementDuration.step = "0.1";
      movementDuration.value = "3";
      movementField.appendChild(movementDuration);
      const gait = document.createElement("select");
      const automaticDuration = document.createElement("input");
      if (actor.kind === "ped") {
        const gaitField = document.createElement("label");
        gaitField.className = "scene-label ped-gait-field";
        gaitField.textContent = "MOVEMENT STYLE";
        for (const [value, name] of [
          ["auto", "Auto (duration)"],
          ["walk", "Walk"],
          ["run", "Run"],
          ["sprint", "Sprint"],
        ]) {
          const option = document.createElement("option");
          option.value = value;
          option.textContent = name;
          gait.appendChild(option);
        }
        gait.value = "auto";
        gaitField.appendChild(gait);
        controls.appendChild(gaitField);
        const automaticField = document.createElement("label");
        automaticField.className = "ped-auto-duration";
        automaticDuration.type = "checkbox";
        automaticDuration.checked = true;
        automaticField.appendChild(automaticDuration);
        const text = document.createElement("span");
        text.textContent = "Calculate duration from distance";
        automaticField.appendChild(text);
        controls.appendChild(automaticField);
        const updateDurationMode = () => {
          automaticDuration.disabled = gait.value === "auto";
          movementDuration.disabled = gait.value !== "auto" && automaticDuration.checked;
        };
        gait.addEventListener("change", updateDurationMode);
        automaticDuration.addEventListener("change", updateDurationMode);
        updateDurationMode();
      }
      const move = document.createElement("button");
      move.className = "free-move-action";
      move.textContent = "Déplacer vers le point visé";
      move.title = "At the playhead, move to the camera aim";
      move.addEventListener("click", async () => {
        const duration = Number(movementDuration.value);
        if (!Number.isFinite(duration) || duration <= 0)
          return ctx.status.showStatus("Enter a valid movement duration.");
        const result = await ctx.transport.post("addAction", {
          id: actor.id,
          type: "move",
          duration,
          ...(actor.kind === "ped"
            ? { gait: gait.value, autoDuration: automaticDuration.checked }
            : {}),
        });
        if (!result.ok) ctx.status.showStatus(result.message || "Could not add movement.");
      });
      controls.appendChild(movementField);
      controls.appendChild(move);
      if (actor.kind === "ped" || actor.kind === "vehicle") {
        const route = document.createElement("button");
        route.className = "route-open";
        route.textContent = "Create multi-point route";
        route.disabled = actor.modelAvailable === false;
        route.addEventListener("click", () => window.VantaRouteEditor?.open(actor));
        controls.appendChild(route);
      }
      const movementNodes = new Set(controls.children);
      if (actor.kind === "ped") {
        const gazePanel = document.createElement("details");
        gazePanel.className = "animation-panel ped-gaze-panel";
        const gazeSummary = document.createElement("summary");
        gazeSummary.textContent = "Look at a subject";
        gazePanel.appendChild(gazeSummary);
        const targetField = document.createElement("label");
        targetField.className = "scene-label";
        targetField.textContent = "TARGET";
        const target = document.createElement("select");
        const point = document.createElement("option");
        point.value = "";
        point.textContent = "Point at camera aim";
        target.appendChild(point);
        ctx.state.project.actors
          .filter((item) => item.id !== actor.id)
          .forEach((item) => {
            const option = document.createElement("option");
            option.value = item.id;
            option.textContent = `${ctx.formatting.actorLabel(item.kind)} ${item.id} · ${item.model}`;
            target.appendChild(option);
          });
        target.value = "";
        targetField.appendChild(target);
        gazePanel.appendChild(targetField);
        const gazeField = document.createElement("label");
        gazeField.className = "scene-label";
        gazeField.textContent = "LOOK DURATION (SEC)";
        const gazeDuration = document.createElement("input");
        gazeDuration.type = "number";
        gazeDuration.min = ".1";
        gazeDuration.max = ctx.state.project.duration;
        gazeDuration.step = ".1";
        gazeDuration.value = "3";
        gazeField.appendChild(gazeDuration);
        gazePanel.appendChild(gazeField);
        const gazeButton = document.createElement("button");
        gazeButton.textContent = "Add gaze at playhead";
        gazeButton.addEventListener("click", async () => {
          const seconds = Number(gazeDuration.value);
          if (!Number.isFinite(seconds) || seconds <= 0)
            return ctx.status.showStatus("Enter a valid gaze duration.");
          const result = await ctx.transport.post("addAction", {
            id: actor.id,
            type: "lookAt",
            duration: seconds,
            ...(target.value ? { targetId: Number(target.value) } : {}),
          });
          if (!result.ok) ctx.status.showStatus(result.message || "Could not add gaze.");
        });
        gazePanel.appendChild(gazeButton);
        controls.appendChild(gazePanel);
        const vehiclePanel = document.createElement("details");
        vehiclePanel.className = "animation-panel vehicle-interaction-panel";
        const vehicleSummary = document.createElement("summary");
        vehicleSummary.textContent = "Vehicle interaction";
        vehiclePanel.appendChild(vehicleSummary);
        const vehicles = ctx.state.project.actors.filter((item) => item.kind === "vehicle");
        const vehicleField = document.createElement("label");
        vehicleField.className = "scene-label";
        vehicleField.textContent = "STAGED VEHICLE";
        const vehicleSelect = document.createElement("select");
        for (const item of vehicles) {
          const option = document.createElement("option");
          option.value = String(item.id);
          option.textContent = item.name || item.model;
          vehicleSelect.appendChild(option);
        }
        if (!vehicles.length) {
          const option = document.createElement("option");
          option.textContent = "Place a vehicle first";
          vehicleSelect.appendChild(option);
        }
        vehicleSelect.value = vehicles.length ? String(vehicles[0].id) : "";
        vehicleField.appendChild(vehicleSelect);
        vehiclePanel.appendChild(vehicleField);
        const seatField = document.createElement("label");
        seatField.className = "scene-label";
        seatField.textContent = "SEAT";
        const seatSelect = document.createElement("select");
        // Standard seat choices are checked against the actual model by Lua.
        for (let seat = -1; seat < 16; seat++) {
          const option = document.createElement("option");
          option.value = String(seat);
          option.textContent =
            seat === -1 ? "Driver" : seat === 0 ? "Front passenger" : "Passenger " + (seat + 1);
          seatSelect.appendChild(option);
        }
        seatSelect.value = "-1";
        seatField.appendChild(seatSelect);
        vehiclePanel.appendChild(seatField);
        let seatRequest = 0;
        const updateSeats = async () => {
          const sequence = ++seatRequest;
          const id = Number(vehicleSelect.value);
          if (!id) return;
          const result = await ctx.transport.post("vehicleSeats", { id });
          if (sequence !== seatRequest || !result.ok) return;
          const count = Number.isInteger(result.count)
            ? Math.max(1, Math.min(17, result.count))
            : 4;
          const previous = seatSelect.value;
          seatSelect.innerHTML = "";
          for (let seat = -1; seat < count - 1; seat++) {
            const option = document.createElement("option");
            option.value = String(seat);
            option.textContent =
              seat === -1 ? "Driver" : seat === 0 ? "Front passenger" : "Passenger " + (seat + 1);
            seatSelect.appendChild(option);
          }
          seatSelect.value = Number(previous) < count - 1 ? previous : "-1";
        };
        vehicleSelect.addEventListener("change", updateSeats);
        updateSeats();
        const secondsField = document.createElement("label");
        secondsField.className = "scene-label";
        secondsField.textContent = "INTERACTION DURATION (SEC)";
        const seconds = document.createElement("input");
        seconds.type = "number";
        seconds.min = ".1";
        seconds.max = "30";
        seconds.step = ".1";
        seconds.value = "5";
        secondsField.appendChild(seconds);
        vehiclePanel.appendChild(secondsField);
        for (const [type, label] of [
          ["enterVehicle", "Enter at playhead"],
          ["exitVehicle", "Exit at playhead"],
        ]) {
          const button = document.createElement("button");
          button.textContent = label;
          button.disabled = !vehicles.length;
          button.addEventListener("click", async () => {
            const result = await ctx.transport.post("addAction", {
              id: actor.id,
              type,
              vehicleId: Number(vehicleSelect.value),
              seat: Number(seatSelect.value),
              duration: Number(seconds.value),
            });
            if (!result.ok)
              ctx.status.showStatus(result.message || "Could not schedule vehicle interaction.");
          });
          vehiclePanel.appendChild(button);
        }
        const hint = document.createElement("p");
        hint.className = "scene-hint";
        hint.textContent =
          "Place the ped near the door. Keep the vehicle still during entry and exit. Exit before adding another ped movement.";
        vehiclePanel.appendChild(hint);
        controls.appendChild(vehiclePanel);
        const browse = document.createElement("button");
        browse.className = "browse-animation";
        browse.type = "button";
        browse.textContent = "Browse animations";
        browse.addEventListener("click", () => ctx.animations.openAnimationCatalog(actor.id));
        controls.appendChild(browse);
        const animationPanel = document.createElement("details");
        animationPanel.className = "animation-panel";
        const summary = document.createElement("summary");
        summary.textContent = "Custom animation (advanced)";
        animationPanel.appendChild(summary);
        const dictInput = document.createElement("input");
        dictInput.type = "text";
        dictInput.placeholder = "Animation dictionary";
        dictInput.value = "amb@world_human_hang_out_street@male_b@idle_a";
        const clipInput = document.createElement("input");
        clipInput.type = "text";
        clipInput.placeholder = "Animation clip";
        clipInput.value = "idle_b";
        const animationSeconds = document.createElement("input");
        animationSeconds.type = "number";
        animationSeconds.min = "0";
        animationSeconds.max = String(ctx.state.project.duration);
        animationSeconds.step = ".1";
        animationSeconds.value = "0";
        const animationDurationField = document.createElement("label");
        animationDurationField.className = "scene-label";
        animationDurationField.textContent = "DURATION (SEC) · 0 = UNTIL REPLACED";
        animationDurationField.appendChild(animationSeconds);
        const animate = document.createElement("button");
        animate.textContent = "Add animation at playhead";
        animate.addEventListener("click", async () => {
          const result = await ctx.transport.post("addAction", {
            id: actor.id,
            type: "animation",
            dict: dictInput.value.trim(),
            clip: clipInput.value.trim(),
            duration: Number(animationSeconds.value) || undefined,
          });
          if (!result.ok)
            ctx.status.showStatus(result.message || "Impossible d’ajouter l’animation.");
        });
        animationPanel.appendChild(dictInput);
        animationPanel.appendChild(clipInput);
        animationPanel.appendChild(animationDurationField);
        animationPanel.appendChild(animate);
        controls.appendChild(animationPanel);
      } else if (actor.kind === "prop") {
        for (const [visible, label] of [
          [true, "Show at playhead"],
          [false, "Hide at playhead"],
        ]) {
          const button = document.createElement("button");
          button.className = visible ? "visibility-show" : "visibility-hide";
          button.type = "button";
          button.textContent = actor.attachment
            ? visible
              ? "Wear at playhead"
              : "Remove at playhead"
            : label;
          button.addEventListener("click", async () => {
            const result = await ctx.transport.post("addAction", {
              id: actor.id,
              type: "visibility",
              visible,
            });
            if (!result.ok)
              ctx.status.showStatus(result.message || "Could not change object visibility.");
          });
          controls.appendChild(button);
        }
      } else if (actor.kind === "vehicle") {
        const vehicleCue = (type, enabled, label, door) => {
          const button = document.createElement("button");
          button.className = enabled ? "vehicle-cue-on" : "vehicle-cue-off";
          button.type = "button";
          button.textContent = label;
          button.addEventListener("click", async () => {
            const result = await ctx.transport.post("addAction", {
              id: actor.id,
              type,
              enabled,
              ...(door === undefined ? {} : { door: Number(door.value) }),
            });
            if (!result.ok)
              ctx.status.showStatus(result.message || "Could not add vehicle action.");
          });
          controls.appendChild(button);
        };
        vehicleCue("engine", true, "Start engine");
        vehicleCue("engine", false, "Stop engine");
        vehicleCue("lights", true, "Lights on");
        vehicleCue("lights", false, "Lights off");
        const doorField = document.createElement("label");
        doorField.className = "scene-label vehicle-door-field";
        doorField.textContent = "DOOR";
        const doorSelect = document.createElement("select");
        for (const [index, name] of [
          "Driver front",
          "Driver rear",
          "Passenger front",
          "Passenger rear",
          "Hood",
          "Trunk",
        ].entries()) {
          const option = document.createElement("option");
          option.value = String(index);
          option.textContent = name;
          doorSelect.appendChild(option);
        }
        doorField.appendChild(doorSelect);
        controls.appendChild(doorField);
        vehicleCue("door", true, "Open door", doorSelect);
        vehicleCue("door", false, "Close door", doorSelect);
      }
      card.appendChild(header);
      card.appendChild(coordinates);
      if (!actor.attachment && !actor.actions?.some((clip) => clip.type === "recording")) {
        card.appendChild(transform);
        card.appendChild(aimButton);
      }
      card.appendChild(controls);
      card.appendChild(icon);
      (actor.actions || []).forEach((action, index) => {
        const row = document.createElement("details");
        row.className = "action-row action-step";
        const summary = document.createElement("summary");
        summary.textContent = `${ctx.formatting.formatTime(action.time)} · ${ctx.formatting.actionLabel(action)}`;
        row.append(summary, ctx.actionChain.controls(actor, action, index));
        const deleteAction = document.createElement("button");
        deleteAction.className = "delete-frame";
        deleteAction.textContent = "×";
        deleteAction.title = "Delete action";
        deleteAction.addEventListener("click", () =>
          ctx.transport.post("deleteAction", { id: actor.id, index: index + 1 }),
        );
        if (action.type === "move" && (actor.kind === "ped" || actor.kind === "vehicle")) {
          const edit = document.createElement("button");
          edit.textContent = "Edit route";
          edit.className = "route-edit-action";
          edit.addEventListener("click", () => window.VantaRouteEditor?.open(actor, action));
          row.appendChild(edit);
        }
        row.appendChild(deleteAction);
        card.appendChild(row);
      });
      ctx.state.actorRenderCache.set(actor.id, { node: card, signature });
      ctx.actors.placeCached(list, card, actorIndex);
      card.addEventListener("click", (event) => {
        if (event.target.closest(".delete-frame")) return;
        if (ctx.state.selectedActorId === actor.id) return;
        ctx.state.selectedActorId = actor.id;
        ctx.transport.post("selectActor", { id: actor.id });
        ctx.actors.renderActors();
      });
      if (actor.id === ctx.state.selectedActorId) {
        const position = ctx.inspector.inspectorGroup(actor, "Position", true);
        position.appendChild(transform);
        const placement = document.createElement("div");
        placement.className = "inspector-placement";
        placement.appendChild(aimButton);
        position.appendChild(placement);
        const recordedTake = actor.actions?.find((clip) => clip.type === "recording");
        if (!actor.attachment && !recordedTake) inspector.appendChild(position);

        if (actor.kind === "ped" || actor.attachment)
          inspector.appendChild(ctx.accessories.accessoryPanel(actor));

        if (actor.kind === "ped" || actor.kind === "vehicle")
          inspector.appendChild(ctx.appearance.appearancePanel(actor));
        const movement = ctx.inspector.inspectorGroup(actor, "Movement", true);
        const movementControls = document.createElement("div");
        movementControls.className = "actor-controls movement-controls";
        const actionControls = document.createElement("div");
        actionControls.className = "actor-controls action-controls";
        for (const element of [...controls.children]) {
          const isMovement = movementNodes.has(element);
          (isMovement ? movementControls : actionControls).appendChild(element);
        }
        movement.appendChild(movementControls);
        if (!actor.attachment && !recordedTake) inspector.appendChild(movement);
        if (recordedTake) {
          const take = ctx.inspector.inspectorGroup(actor, "Recorded take", true);
          const input = document.createElement("input");
          input.type = "number";
          input.min = "0";
          input.max = String(Math.max(0, ctx.state.project.duration - recordedTake.duration));
          input.step = ".1";
          input.value = String(recordedTake.time);
          const label = document.createElement("label");
          label.className = "scene-label";
          label.textContent = "START TIME (SEC)";
          label.appendChild(input);
          take.appendChild(label);
          input.addEventListener("change", async () => {
            const r = await ctx.transport.post("moveAction", {
              actorId: actor.id,
              actionId: recordedTake.id,
              time: Number(input.value),
            });
            if (!r.ok) ctx.status.showStatus(r.message || "Could not move take.");
          });
          const note = document.createElement("p");
          note.className = "scene-hint";
          note.textContent =
            Number(recordedTake.duration).toFixed(1) +
            " sec · " +
            recordedTake.samples.length +
            " captured poses. Add camera keyframes or track this actor to film another angle.";
          take.appendChild(note);
          inspector.appendChild(take);
        }
        const actions = ctx.inspector.inspectorGroup(actor, "Actions", false);
        actions.appendChild(actionControls);
        if (!recordedTake) inspector.appendChild(actions);
        const rows = [...card.children].filter((element) =>
          element.classList.contains("action-row"),
        );
        if (rows.length) {
          const scheduled = ctx.inspector.inspectorGroup(
            actor,
            "Scheduled actions (" + rows.length + ")",
            true,
          );
          scheduled.appendChild(ctx.actionChain.toolbar(actor));
          for (const row of rows) scheduled.appendChild(row);
          if (position.parentNode === inspector)
            inspector.insertBefore(scheduled, position.nextSibling);
          else inspector.appendChild(scheduled);
        }
      }
    });
    if (!ctx.state.project.actors.length)
      inspector.textContent = "Place a ped, vehicle or object to inspect it here.";
    if (ctx.state.sceneTabActive) ctx.inspector.renderInspectorMode();
    ctx.timeline.renderTimelineTracks();
    ctx.sequences.updateContextControls();
    window.VantaPolish?.render();
    window.VantaWorkflow?.render();
  };
  return function bindEvents() {
    document.getElementById("actorKind").addEventListener("change", (event) => {
      document.getElementById("actorModel").value =
        event.target.value === "vehicle"
          ? "sultan"
          : event.target.value === "prop"
            ? "prop_tool_box_04"
            : "a_m_y_business_01";
    });

    document.getElementById("addActorButton").addEventListener("click", async () => {
      const result = await ctx.transport.post("addActor", {
        kind: document.getElementById("actorKind").value,
        model: document.getElementById("actorModel").value.trim(),
      });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not place actor.");
      else document.getElementById("actorCreate").open = false;
    });
  };
};
