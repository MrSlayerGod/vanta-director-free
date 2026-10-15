window.DirectorEditor.modules.presets = function defineModule(ctx) {
  ctx.presets = {};
  let dialog,
    select,
    references,
    entries = [],
    serial = 0;
  const q = (id) => document.getElementById(id);
  const refresh = async () => {
    const token = ++serial;
    const result = await ctx.transport.post("getPresets");
    if (token !== serial || !dialog.open) return;
    entries = result.ok && Array.isArray(result.entries) ? result.entries : [];
    select.replaceChildren();
    for (const entry of entries) {
      const option = document.createElement("option");
      option.value = entry.id;
      option.textContent = entry.name;
      option.dataset.i18nUser = "true";
      option.disabled = entry.available === false;
      select.appendChild(option);
    }
    q("personalPresetEmpty").hidden = entries.length > 0;
    renderReferences();
  };
  function renderReferences() {
    references.replaceChildren();
    const entry = entries.find((entry) => entry.id === Number(select.value));
    q("personalPresetApply").disabled =
      !entry || entry.available === false || ctx.state.sessionRole === "viewer";
    q("personalPresetDelete").disabled = !entry;
    for (const reference of entry?.references || []) {
      const label = document.createElement("label");
      const name = document.createElement("span");
      name.textContent = reference.name;
      name.dataset.i18nUser = "true";
      const input = document.createElement("select");
      input.dataset.referenceId = reference.id;
      const empty = document.createElement("option");
      empty.value = "";
      empty.textContent = "Choose a scene subject";
      input.appendChild(empty);
      for (const actor of ctx.state.project.actors.filter(
        (actor) => actor.kind === reference.kind,
      )) {
        const option = document.createElement("option");
        option.value = actor.id;
        option.textContent = actor.name || actor.model;
        option.dataset.i18nUser = "true";
        input.appendChild(option);
      }
      label.append(name, input);
      references.appendChild(label);
    }
  }
  ctx.presets.open = function open(kind = "camera") {
    ctx.input.clearKeys();
    q("personalPresetKind").value = kind;
    if (!dialog.open) dialog.showModal();
    refresh();
  };
  return function bindEvents() {
    dialog = document.createElement("dialog");
    dialog.id = "personalPresetDialog";
    dialog.className = "preset-dialog";
    dialog.setAttribute("aria-labelledby", "personalPresetTitle");
    dialog.innerHTML = `
      <header>
        <h2 id="personalPresetTitle">Personal presets</h2>
        <button type="button" id="personalPresetClose" aria-label="Close personal presets">×</button>
      </header>
      <p>Saved on this computer. Apply at the playhead; paths are placed relative to your current camera or subject.</p>
      <section>
        <h3>Save a reusable sequence</h3>
        <label>Preset name<input id="personalPresetName" maxlength="48" /></label>
        <label>Preset type
          <select id="personalPresetKind">
            <option value="camera">Current camera shot or path</option>
            <option value="actions">Selected subject’s actions</option>
          </select>
        </label>
        <button id="personalPresetSave" type="button">Save preset</button>
      </section>
      <section>
        <h3>Use a saved preset</h3>
        <p id="personalPresetEmpty">No saved presets yet.</p>
        <label>Saved presets<select id="personalPresetSelect"></select></label>
        <div id="personalPresetReferences"></div>
        <button id="personalPresetApply" type="button">Apply at playhead</button>
        <button id="personalPresetDelete" type="button">Delete preset</button>
        <p id="personalPresetStatus" role="status"></p>
      </section>`;
    ctx.elements.root.appendChild(dialog);
    select = q("personalPresetSelect");
    references = q("personalPresetReferences");
    q("personalPresetClose").onclick = () => dialog.close();
    dialog.addEventListener("close", () => {
      serial++;
    });
    select.onchange = renderReferences;
    document.addEventListener(
      "keydown",
      (event) => {
        if (!dialog.open) return;
        event.stopImmediatePropagation();
        if (event.key === "Escape") {
          event.preventDefault();
          dialog.close();
        }
      },
      true,
    );
    window.addEventListener("message", ({ data }) => {
      if (
        data?.action === "close" ||
        data?.action === "captureCountdown" ||
        data?.action === "motionRecordStarted"
      )
        dialog.close();
      if (data?.action === "sessionState" && data.role === "viewer") dialog.close();
    });
    q("personalPresetSave").onclick = async () => {
      const result = await ctx.transport.post("savePreset", {
        name: q("personalPresetName").value,
        kind: q("personalPresetKind").value,
        actorId: ctx.state.selectedActorId,
      });
      q("personalPresetStatus").textContent = result.message || "";
      if (result.ok) await refresh();
    };
    q("personalPresetApply").onclick = async () => {
      const mappings = Object.fromEntries(
        [...references.querySelectorAll("select")].map((input) => [
          input.dataset.referenceId,
          Number(input.value),
        ]),
      );
      const result = await ctx.transport.post("applyPreset", {
        id: Number(select.value),
        actorId: ctx.state.selectedActorId,
        mappings,
      });
      q("personalPresetStatus").textContent = result.message || "";
      if (result.ok) dialog.close();
    };
    q("personalPresetDelete").onclick = async () => {
      const button = q("personalPresetDelete");
      if (button.dataset.confirm !== select.value) {
        button.dataset.confirm = select.value;
        button.textContent = "Confirm delete";
        return;
      }
      const result = await ctx.transport.post("deletePreset", { id: Number(select.value) });
      button.dataset.confirm = "";
      button.textContent = "Delete preset";
      if (result.ok) await refresh();
    };
    const tools = document.createElement("div");
    tools.className = "starter-tools";
    const library = document.createElement("button");
    library.type = "button";
    library.id = "personalPresetOpen";
    library.textContent = "Personal presets";
    library.onclick = () => {
      ctx.library.closeLibrary();
      ctx.presets.open();
    };
    const video = document.createElement("button");
    video.type = "button";
    video.textContent = "Watch the quickstart tutorial";
    video.onclick = () => {
      const url = "https://youtu.be/WRm5OxSCESE";
      if (typeof window.invokeNative === "function") window.invokeNative("openUrl", url);
      else window.open(url, "_blank", "noopener,noreferrer");
    };
    tools.append(library, video);
    q("libraryBrowse").appendChild(tools);
    const starters = document.createElement("details");
    starters.className = "starter-scenes";
    starters.innerHTML =
      "<summary>Starter scenes</summary><p>Aim at an open, flat area. Each example creates a new editable project.</p>";
    for (const [kind, label] of [
      ["reveal", "Slow camera reveal"],
      ["dialogue", "Two-person conversation"],
      ["vehicle", "Vehicle follow"],
    ]) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.dataset.templateKind = kind;
      button.onclick = () =>
        ctx.library.confirmLibraryAction(
          "Create a starter scene?",
          "Save your current changes before continuing. The example will become a new project.",
          async () => {
            q("libraryConfirm").classList.add("is-hidden");
            ctx.library.setLibraryBusy(true);
            const result = await ctx.transport.post("createTemplate", { kind });
            if (!result.ok) ctx.library.setLibraryBusy(false);
          },
        );
      starters.appendChild(button);
    }
    q("libraryBrowse").appendChild(starters);
    const cameraSave = document.createElement("button");
    cameraSave.type = "button";
    cameraSave.textContent = "Save camera as preset";
    cameraSave.onclick = () => ctx.presets.open("camera");
    q("cameraSequencePanel").appendChild(cameraSave);
  };
};
