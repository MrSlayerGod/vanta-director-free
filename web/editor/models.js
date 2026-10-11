window.DirectorEditor.modules.models = function defineModule(ctx) {
  ctx.models = {};
  ctx.models.setModelPlacing = function setModelPlacing(value) {
    ctx.state.modelPlacing = value;
    ctx.elements.modelOverlay.classList.toggle("placing", value);
    document.getElementById("modelClose").disabled = value;
    document.getElementById("modelPlace").textContent = value
      ? "Placing model…"
      : "Place at camera aim";
  };

  ctx.models.setModelLoading = function setModelLoading(value) {
    ctx.elements.modelOverlay.classList.toggle("loading-preview", value);
    for (const id of ["modelAngle", "modelZoom", "modelFront", "modelSide", "modelFit"])
      document.getElementById(id).disabled = value || !ctx.state.modelReady;
  };

  ctx.models.modelVisibleViewport = function modelVisibleViewport() {
    const bounds = document.getElementById("modelViewport").getBoundingClientRect();
    const width = Math.max(1, window.innerWidth),
      height = Math.max(1, window.innerHeight);
    const left = Math.max(0, Math.min(width, bounds.left)),
      top = Math.max(0, Math.min(height, bounds.top));
    return {
      left: left / width,
      top: top / height,
      width: Math.max(0, Math.min(width, bounds.right) - left) / width,
      height: Math.max(0, Math.min(height, bounds.bottom) - top) / height,
    };
  };

  ctx.models.sendModelView = function sendModelView() {
    if (ctx.state.modelViewScheduled) return;
    ctx.state.modelViewScheduled = true;
    requestAnimationFrame(() => {
      ctx.state.modelViewScheduled = false;
      if (ctx.state.modelReady && !ctx.elements.modelOverlay.classList.contains("is-hidden"))
        ctx.transport.post("modelPreviewView", {
          angle: Number(document.getElementById("modelAngle").value),
          zoom: Number(document.getElementById("modelZoom").value),
          elevation: ctx.state.modelElevation,
          viewport: ctx.models.modelVisibleViewport(),
        });
    });
  };

  ctx.models.resetModelView = function resetModelView(angle = 135) {
    document.getElementById("modelAngle").value = String(angle);
    document.getElementById("modelZoom").value = "1";
    ctx.state.modelElevation = 12;
    ctx.models.sendModelView();
  };

  ctx.models.localizedModelSearch = function localizedModelSearch(item) {
    if (item.localizedSearch) return item.localizedSearch;
    const normalize = (value) =>
      String(value)
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toLowerCase();
    return (item.localizedSearch = normalize(
      item.search +
        " " +
        (window.VantaI18n?.searchText(item.category.replaceAll("_", " ")) || "") +
        " " +
        (window.VantaI18n?.searchText(item.label) || ""),
    ));
  };

  ctx.models.renderModels = function renderModels() {
    const query = document
      .getElementById("modelSearch")
      .value.trim()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
    const category = document.getElementById("modelCategory").value;
    const key = `${ctx.state.modelKind}|${category}|${query}`;
    if (ctx.state.modelFilterKey !== key) {
      ctx.state.modelMatches = ctx.state.modelCatalog.filter(
        (item) =>
          item.kind === ctx.state.modelKind &&
          (!category || item.category === category) &&
          (!query || ctx.models.localizedModelSearch(item).includes(query)),
      );
      ctx.state.modelFilterKey = key;
    }
    const matching = ctx.state.modelMatches;
    const pages = Math.max(1, Math.ceil(matching.length / ctx.state.modelPageSize));
    ctx.state.modelPage = Math.min(ctx.state.modelPage, pages - 1);
    const list = document.getElementById("modelResults");
    list.innerHTML = "";
    matching
      .slice(
        ctx.state.modelPage * ctx.state.modelPageSize,
        (ctx.state.modelPage + 1) * ctx.state.modelPageSize,
      )
      .forEach((item) => {
        const row = document.createElement("button");
        row.type = "button";
        row.className = "model-result";
        row.modelKey = `${item.kind}:${item.model}`;
        if (
          ctx.state.modelSelection?.model === item.model &&
          ctx.state.modelSelection.kind === item.kind
        )
          row.classList.add("selected");
        const title = document.createElement("strong");
        title.textContent = item.label;
        const detail = document.createElement("small");
        detail.textContent = `${item.model} · ${item.category.replaceAll("_", " ")}`;
        row.appendChild(title);
        row.appendChild(detail);
        row.addEventListener("click", () => ctx.models.selectModel(item));
        list.appendChild(row);
      });
    if (!matching.length) {
      const empty = document.createElement("p");
      empty.textContent = ctx.state.modelsLoaded
        ? "No matching models on this game build."
        : "Checking models available on your game build…";
      list.appendChild(empty);
    }
    document.getElementById("modelCount").textContent = ctx.state.modelsLoaded
      ? `${matching.length.toLocaleString()} models · ${ctx.state.modelPage + 1}/${pages}`
      : "Loading models…";
    document.getElementById("modelPrevious").disabled = ctx.state.modelPage === 0;
    document.getElementById("modelNext").disabled = ctx.state.modelPage >= pages - 1;
    for (const [id, kind] of [
      ["modelsPed", "ped"],
      ["modelsVehicle", "vehicle"],
      ["modelsProp", "prop"],
    ])
      document.getElementById(id).classList.toggle("active", kind === ctx.state.modelKind);
  };

  ctx.models.renderModelCategories = function renderModelCategories() {
    const select = document.getElementById("modelCategory");
    const previous = select.value;
    select.innerHTML = "";
    const all = document.createElement("option");
    all.value = "";
    all.textContent = "All categories";
    select.appendChild(all);
    const categories = [
      ...new Set(
        ctx.state.modelCatalog
          .filter((item) => item.kind === ctx.state.modelKind)
          .map((item) => item.category),
      ),
    ].sort();
    categories.forEach((category) => {
      const option = document.createElement("option");
      option.value = category;
      option.textContent = category.replaceAll("_", " ");
      select.appendChild(option);
    });
    select.value = categories.includes(previous) ? previous : "";
  };

  ctx.models.selectModel = async function selectModel(item) {
    if (ctx.state.modelPlacing) return;
    ctx.state.modelDrag = null;
    ctx.state.modelElevation = 12;
    ctx.state.modelSelection = item;
    ctx.state.modelReady = false;
    ctx.models.setModelLoading(true);
    const sequence = ++ctx.state.modelSequence;
    document.getElementById("modelName").textContent = item.label;
    document.getElementById("modelCode").textContent = item.model;
    document.getElementById("modelPlace").disabled = true;
    document.getElementById("modelPreviewStatus").textContent = "Loading 3D preview…";
    document.getElementById("modelAngle").value = "135";
    document.getElementById("modelZoom").value = "1";
    for (const row of document.getElementById("modelResults").children)
      row.classList.toggle("selected", row.modelKey === `${item.kind}:${item.model}`);
    const result = await ctx.transport.post("previewModel", {
      kind: item.kind,
      model: item.model,
      viewport: ctx.models.modelVisibleViewport(),
    });
    if (
      sequence !== ctx.state.modelSequence ||
      ctx.elements.modelOverlay.classList.contains("is-hidden")
    )
      return;
    ctx.state.modelReady = Boolean(result.ok);
    ctx.models.setModelLoading(false);
    document.getElementById("modelPlace").disabled = !ctx.state.modelReady;
    document.getElementById("modelPreviewStatus").textContent = result.ok
      ? "Drag the model view to rotate. Scroll to zoom. Reset view to fit the whole model."
      : result.message || "Preview unavailable.";
  };

  ctx.models.closeModels = async function closeModels(notify = true) {
    if (ctx.state.modelPlacing && notify) return;
    ctx.models.setModelPlacing(false);
    ctx.state.modelReady = false;
    ctx.models.setModelLoading(false);
    ctx.state.modelDrag = null;
    ctx.elements.modelViewport.classList.remove("rotating");
    ctx.state.modelSequence++;
    ctx.state.modelReady = false;
    ctx.elements.modelOverlay.classList.add("is-hidden");
    ctx.elements.root.classList.remove("model-browsing");
    if (notify) await ctx.transport.post("closeModelBrowser");
  };
  return function bindEvents() {
    ctx.state.modelViewportObserver?.observe(ctx.elements.modelViewport);

    window.addEventListener("resize", ctx.models.sendModelView);

    window.addEventListener("beforeunload", () => ctx.state.modelViewportObserver?.disconnect());

    ctx.elements.modelViewport.addEventListener("mousedown", (event) => {
      if (event.button !== 0 || !ctx.state.modelReady) return;
      event.preventDefault();
      ctx.state.modelDrag = { x: event.clientX, y: event.clientY };
      ctx.elements.modelViewport.classList.add("rotating");
    });

    window.addEventListener("mousemove", (event) => {
      if (!ctx.state.modelDrag || !ctx.state.modelReady) return;
      if (!(event.buttons & 1)) {
        ctx.state.modelDrag = null;
        ctx.elements.modelViewport.classList.remove("rotating");
        return;
      }
      const angle = document.getElementById("modelAngle");
      angle.value = String(
        (Number(angle.value) - (event.clientX - ctx.state.modelDrag.x) * 0.45 + 720) % 360,
      );
      ctx.state.modelElevation = Math.max(
        -15,
        Math.min(75, ctx.state.modelElevation + (event.clientY - ctx.state.modelDrag.y) * 0.3),
      );
      ctx.state.modelDrag = { x: event.clientX, y: event.clientY };
      ctx.models.sendModelView();
    });

    window.addEventListener("mouseup", () => {
      ctx.state.modelDrag = null;
      ctx.elements.modelViewport.classList.remove("rotating");
    });

    ctx.elements.modelViewport.addEventListener(
      "wheel",
      (event) => {
        event.preventDefault();
        if (!ctx.state.modelReady) return;
        const zoom = document.getElementById("modelZoom");
        zoom.value = String(
          Math.max(0.6, Math.min(2.5, Number(zoom.value) * Math.exp(event.deltaY * 0.001))),
        );
        ctx.models.sendModelView();
      },
      { passive: false },
    );

    ctx.elements.modelViewport.addEventListener("dblclick", () => ctx.models.resetModelView());

    document
      .getElementById("modelFit")
      .addEventListener("click", () => ctx.models.resetModelView());

    document
      .getElementById("modelFront")
      .addEventListener("click", () => ctx.models.resetModelView(90));

    document
      .getElementById("modelSide")
      .addEventListener("click", () => ctx.models.resetModelView(0));

    document.getElementById("browseModelsButton").addEventListener("click", async () => {
      if (!ctx.elements.modelOverlay.classList.contains("is-hidden")) return;
      ctx.state.looking = false;
      ctx.state.lookDeltaX = ctx.state.lookDeltaY = 0;
      ctx.input.clearKeys();
      ctx.state.previewPlaying = false;
      ctx.state.selectedFrameTime = null;
      ctx.elements.modelOverlay.classList.remove("is-hidden");
      ctx.elements.root.classList.add("model-browsing");
      ctx.state.modelSelection = null;
      ctx.state.modelReady = false;
      ctx.state.modelPage = 0;
      const session = ++ctx.state.modelSequence;
      ctx.models.setModelLoading(false);
      document.getElementById("modelName").textContent = "Choose a model";
      document.getElementById("modelCode").textContent = "—";
      document.getElementById("modelPlace").disabled = true;
      document.getElementById("modelPreviewStatus").textContent =
        "The preview is temporary and does not modify your project.";
      ctx.models.renderModelCategories();
      ctx.models.renderModels();
      const result = await ctx.transport.post("openModelBrowser");
      if (
        session !== ctx.state.modelSequence ||
        ctx.elements.modelOverlay.classList.contains("is-hidden")
      )
        return;
      if (!result.ok) {
        ctx.models.closeModels(false);
        ctx.status.showStatus(result.message);
      }
    });

    document.getElementById("modelClose").addEventListener("click", () => ctx.models.closeModels());

    for (const [id, kind] of [
      ["modelsPed", "ped"],
      ["modelsVehicle", "vehicle"],
      ["modelsProp", "prop"],
    ])
      document.getElementById(id).addEventListener("click", () => {
        if (ctx.state.modelPlacing || ctx.state.modelKind === kind) return;
        ctx.state.modelSequence++;
        ctx.state.modelSelection = null;
        ctx.state.modelReady = false;
        ctx.models.setModelLoading(false);
        document.getElementById("modelName").textContent = "Choose a model";
        document.getElementById("modelCode").textContent = "—";
        document.getElementById("modelPlace").disabled = true;
        document.getElementById("modelPreviewStatus").textContent =
          "Select a model to preview it in 3D.";
        ctx.transport.post("clearModelPreview");
        ctx.state.modelKind = kind;
        ctx.state.modelPage = 0;
        document.getElementById("modelCategory").value = "";
        ctx.models.renderModelCategories();
        ctx.models.renderModels();
      });

    document.getElementById("modelSearch").addEventListener("input", () => {
      ctx.state.modelPage = 0;
      ctx.models.renderModels();
    });

    document.getElementById("modelCategory").addEventListener("change", () => {
      ctx.state.modelPage = 0;
      ctx.models.renderModels();
    });

    document.getElementById("modelPrevious").addEventListener("click", () => {
      ctx.state.modelPage = Math.max(0, ctx.state.modelPage - 1);
      ctx.models.renderModels();
    });

    document.getElementById("modelNext").addEventListener("click", () => {
      ctx.state.modelPage++;
      ctx.models.renderModels();
    });

    for (const id of ["modelAngle", "modelZoom"])
      document.getElementById(id).addEventListener("input", () => {
        ctx.models.sendModelView();
      });

    document.getElementById("modelPlace").addEventListener("click", async () => {
      if (!ctx.state.modelReady || !ctx.state.modelSelection || ctx.state.modelPlacing) return;
      ctx.models.setModelPlacing(true);
      const session = ctx.state.modelSequence;
      document.getElementById("modelPlace").disabled = true;
      const result = await ctx.transport.post("placeBrowserModel", {
        kind: ctx.state.modelSelection.kind,
        model: ctx.state.modelSelection.model,
      });
      if (session !== ctx.state.modelSequence || !ctx.state.bridgeReady) return;
      await ctx.models.closeModels(false);
      if (!result.ok) ctx.status.showStatus(result.message || "Could not place model.");
      else ctx.status.showStatus("Model placed at your original camera aim.");
    });
  };
};
