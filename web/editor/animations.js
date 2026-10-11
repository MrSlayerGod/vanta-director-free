window.DirectorEditor.modules.animations = function defineModule(ctx) {
  ctx.animations = {};
  ctx.animations.animationIdList = function animationIdList(value, limit) {
    return Array.isArray(value)
      ? [
          ...new Set(
            value.filter((id) => typeof id === "string" && ctx.state.animationIds.has(id)),
          ),
        ].slice(0, limit)
      : [];
  };

  ctx.animations.readAnimationMemory = function readAnimationMemory() {
    try {
      const raw = window.localStorage?.getItem(ctx.state.animationStorageKey);
      if (!raw) return { favorites: [], recent: [] };
      if (raw.length > 65536) throw Error("Invalid animation preferences");
      const data = JSON.parse(raw);
      if (!data || data.version !== 1) return { favorites: [], recent: [] };
      return {
        favorites: ctx.animations.animationIdList(
          data.favorites,
          ctx.state.animationCatalog.length,
        ),
        recent: ctx.animations.animationIdList(data.recent, 20),
      };
    } catch {
      return { favorites: [], recent: [] };
    }
  };

  ctx.animations.storeAnimationMemory = function storeAnimationMemory() {
    try {
      if (!window.localStorage) throw Error("Storage unavailable");
      window.localStorage.setItem(
        ctx.state.animationStorageKey,
        JSON.stringify({ version: 1, ...ctx.state.animationMemory }),
      );
      return true;
    } catch {
      return false;
    }
  };

  ctx.animations.recordAnimationUse = function recordAnimationUse(id) {
    if (!ctx.state.animationIds.has(id)) return;
    ctx.state.animationMemory.recent = [
      id,
      ...ctx.state.animationMemory.recent.filter((item) => item !== id),
    ].slice(0, 20);
    ctx.animations.storeAnimationMemory();
  };

  ctx.animations.animationSearchText = function animationSearchText(text) {
    return String(text)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  };

  ctx.animations.selectedAnimation = function selectedAnimation() {
    return ctx.state.animationCatalog.find((item) => item.id === ctx.state.animationSelectedId);
  };

  ctx.animations.renderAnimationCatalog = function renderAnimationCatalog() {
    const words = ctx.animations
      .animationSearchText(ctx.elements.animationSearch.value.trim())
      .split(/\s+/)
      .filter(Boolean);
    const categories = document.getElementById("animationCategories");
    categories.innerHTML = "";
    for (const category of ctx.state.animationCategories) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = ctx.state.animationCategoryNames[category] || category;
      button.className = category === ctx.state.animationCategory ? "active" : "";
      button.addEventListener("click", () => {
        ctx.state.animationCategory = category;
        ctx.animations.renderAnimationCatalog();
      });
      categories.appendChild(button);
    }
    const visible = ctx.state.animationCatalog.filter(
      (item) =>
        (ctx.state.animationCategory === "All" ||
          item.category === ctx.state.animationCategory ||
          (ctx.state.animationCategory === "Favorites" &&
            ctx.state.animationMemory.favorites.includes(item.id)) ||
          (ctx.state.animationCategory === "Recent" &&
            ctx.state.animationMemory.recent.includes(item.id))) &&
        words.every((word) => ctx.state.animationSearchIndex.get(item.id).includes(word)),
    );
    if (ctx.state.animationCategory === "Recent")
      visible.sort(
        (a, b) =>
          ctx.state.animationMemory.recent.indexOf(a.id) -
          ctx.state.animationMemory.recent.indexOf(b.id),
      );
    document.getElementById("animationCount").textContent =
      visible.length + " / " + ctx.state.animationCatalog.length + " animations";
    if (!visible.some((item) => item.id === ctx.state.animationSelectedId))
      ctx.state.animationSelectedId = visible[0]?.id || null;
    const results = document.getElementById("animationResults");
    results.innerHTML = "";
    if (!visible.length) {
      const empty = document.createElement("div");
      empty.className = "animation-empty";
      empty.textContent =
        ctx.state.animationCategory === "Favorites"
          ? "Ajoute une animation aux favoris avec le bouton étoile."
          : ctx.state.animationCategory === "Recent"
            ? "Les animations prévisualisées ou ajoutées apparaîtront ici."
            : "Aucune animation ne correspond à cette recherche.";
      results.appendChild(empty);
    }
    visible.forEach((item) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className = `animation-result${item.id === ctx.state.animationSelectedId ? " active" : ""}`;
      row.dataset.animationId = item.id;
      const label = document.createElement("span");
      const title = document.createElement("strong");
      title.textContent = item.name;
      const category = document.createElement("small");
      category.textContent =
        item.category +
        " · " +
        (item.loop ? "Boucle" : "Une fois") +
        (ctx.state.animationMemory.favorites.includes(item.id) ? " · ★" : "");
      label.appendChild(title);
      label.appendChild(category);
      const arrow = document.createElement("span");
      arrow.className = "preview-glyph";
      arrow.textContent = "›";
      row.appendChild(label);
      row.appendChild(arrow);
      row.addEventListener("click", () => {
        if (ctx.state.animationSelectedId !== item.id) ctx.animations.stopCatalogPreview();
        ctx.state.animationSelectedId = item.id;
        ctx.animations.renderAnimationCatalog();
      });
      results.appendChild(row);
    });
    const item = ctx.animations.selectedAnimation();
    document.getElementById("animationName").textContent = item?.name || "Aucune animation";
    document.getElementById("animationDescription").textContent =
      item?.description || "Choisis une autre catégorie ou une autre recherche.";
    document.getElementById("animationDict").textContent = item?.dict || "—";
    document.getElementById("animationClip").textContent = item?.clip || "—";
    document.getElementById("animationLoop").textContent = item
      ? item.loop
        ? "Boucle, jusqu’à la fin du segment"
        : "Action courte, jouée une fois"
      : "—";
    document.getElementById("animationRequirements").textContent = item
      ? [
          item.placement,
          item.props.length
            ? "Objet(s) à placer comme accessoires : " +
              item.props.join(", ") +
              ". Aucun objet n’est créé automatiquement."
            : "",
          item.caution,
        ]
          .filter(Boolean)
          .join(" ")
      : "";
    document.getElementById("animationDurationLabel").textContent =
      item && !item.loop
        ? "DURÉE MAX. (SEC) · 0 = DURÉE NATIVE"
        : "DURÉE (SEC) · 0 = JUSQU’À REMPLACEMENT";
    const favorite = document.getElementById("animationFavoriteButton");
    favorite.disabled = !item;
    favorite.setAttribute(
      "aria-pressed",
      String(Boolean(item && ctx.state.animationMemory.favorites.includes(item.id))),
    );
    favorite.textContent =
      item && ctx.state.animationMemory.favorites.includes(item.id)
        ? "★ Retirer des favoris"
        : "☆ Ajouter aux favoris";
    document.getElementById("animationPlayButton").disabled = !item;
    document.getElementById("animationAddButton").disabled = !item;
  };

  ctx.animations.openAnimationCatalog = function openAnimationCatalog(actorId) {
    const actor = ctx.state.project.actors.find(
      (item) => item.id === actorId && item.kind === "ped",
    );
    if (!actor) return ctx.status.showStatus("Select a staged ped first.");
    ctx.state.animationActorId = actorId;
    ctx.state.animationPreviewSequence++;
    ctx.state.animationCategory = "All";
    ctx.elements.animationSearch.value = "";
    ctx.state.animationSelectedId = ctx.state.animationCatalog[0].id;
    ctx.state.animationPreviewActive = false;
    document.getElementById("animationContext").textContent =
      `Personnage ${String(actorId).padStart(2, "0")} · Ajouter à ${ctx.formatting.formatTime(ctx.state.project.playhead)}`;
    document.getElementById("animationPreviewStatus").textContent =
      "Choisis une pose et regarde son aperçu sur le personnage.";
    ctx.transport.post("stopPreview");
    ctx.input.clearKeys();
    ctx.animations.renderAnimationCatalog();
    ctx.elements.animationPreviewBar.classList.add("is-hidden");
    ctx.elements.animationOverlay.classList.remove("is-hidden");
  };

  ctx.animations.stopCatalogPreview = async function stopCatalogPreview() {
    const sequence = ++ctx.state.animationPreviewSequence;
    ctx.state.animationPreviewActive = false;
    const result = await ctx.transport.post("stopAnimationPreview");
    if (sequence !== ctx.state.animationPreviewSequence) return;
    const message = result.ok
      ? "Aperçu arrêté. La scène est restaurée au curseur."
      : result.message || "Impossible d’arrêter l’aperçu.";
    document.getElementById("animationPreviewStatus").textContent = message;
    document.getElementById("animationBarStatus").textContent = message;
    return result;
  };

  ctx.animations.closeAnimationCatalog = function closeAnimationCatalog() {
    if (
      ctx.elements.animationOverlay.classList.contains("is-hidden") &&
      ctx.elements.animationPreviewBar.classList.contains("is-hidden")
    )
      return;
    ctx.elements.animationOverlay.classList.add("is-hidden");
    ctx.elements.animationPreviewBar.classList.add("is-hidden");
    ctx.state.animationPreviewSequence++;
    ctx.transport.post("stopAnimationPreview");
    ctx.state.animationPreviewActive = false;
    ctx.state.animationActorId = null;
  };

  ctx.animations.addSelectedAnimation = async function addSelectedAnimation() {
    const item = ctx.animations.selectedAnimation();
    if (!item || ctx.state.animationActorId == null || ctx.state.animationAddPending) return;
    const id = ctx.state.animationActorId;
    const seconds = Number(document.getElementById("animationDuration").value);
    if (!Number.isFinite(seconds) || seconds < 0)
      return ctx.status.showStatus("Choisis une durée positive, ou 0 pour la durée par défaut.");
    ctx.state.animationAddPending = true;
    try {
      const stopped = ctx.animations.stopCatalogPreview(),
        sequence = ctx.state.animationPreviewSequence;
      const stopResult = await stopped;
      if (sequence !== ctx.state.animationPreviewSequence || id !== ctx.state.animationActorId)
        return;
      if (!stopResult?.ok)
        return ctx.status.showStatus(stopResult?.message || "Impossible d’arrêter l’aperçu.");
      const result = await ctx.transport.post("addAction", {
        id,
        type: "animation",
        dict: item.dict,
        clip: item.clip,
        loop: item.loop,
        duration: seconds || undefined,
      });
      if (sequence !== ctx.state.animationPreviewSequence || id !== ctx.state.animationActorId)
        return;
      if (result.ok) {
        ctx.animations.recordAnimationUse(item.id);
        ctx.animations.closeAnimationCatalog();
        ctx.status.showStatus(
          `${item.name} ajouté à ${ctx.formatting.formatTime(ctx.state.project.playhead)}.`,
        );
      } else ctx.status.showStatus(result.message || "Impossible d’ajouter l’animation.");
    } finally {
      ctx.state.animationAddPending = false;
    }
  };
  return function bindEvents() {
    ctx.elements.animationSearch.addEventListener("input", ctx.animations.renderAnimationCatalog);

    document.getElementById("animationFavoriteButton").addEventListener("click", () => {
      const item = ctx.animations.selectedAnimation();
      if (!item) return;
      const ids = ctx.state.animationMemory.favorites;
      ctx.state.animationMemory.favorites = ids.includes(item.id)
        ? ids.filter((id) => id !== item.id)
        : [...ids, item.id];
      if (!ctx.animations.storeAnimationMemory())
        document.getElementById("animationPreviewStatus").textContent =
          "Favoris conservés pour cette session ; le stockage local est indisponible.";
      ctx.animations.renderAnimationCatalog();
    });

    document
      .getElementById("animationCloseButton")
      .addEventListener("click", ctx.animations.closeAnimationCatalog);

    document.getElementById("animationPlayButton").addEventListener("click", async () => {
      const item = ctx.animations.selectedAnimation();
      if (!item || ctx.state.animationActorId == null) return;
      const sequence = ++ctx.state.animationPreviewSequence;
      document.getElementById("animationPreviewStatus").textContent = "Chargement de l’animation…";
      document.getElementById("animationBarName").textContent = item.name;
      document.getElementById("animationBarStatus").textContent = "Chargement de l’animation…";
      ctx.elements.animationOverlay.classList.add("is-hidden");
      ctx.elements.animationPreviewBar.classList.remove("is-hidden");
      const result = await ctx.transport.post("previewAnimation", {
        id: ctx.state.animationActorId,
        dict: item.dict,
        clip: item.clip,
        loop: item.loop,
      });
      if (
        sequence !== ctx.state.animationPreviewSequence ||
        ctx.elements.animationPreviewBar.classList.contains("is-hidden")
      )
        return;
      ctx.state.animationPreviewActive = result.ok;
      if (result.ok) {
        ctx.animations.recordAnimationUse(item.id);
        ctx.animations.renderAnimationCatalog();
      }
      const message = result.ok
        ? "Aperçu sur le personnage. Arrête-le pour restaurer la scène."
        : result.message || "Animation indisponible.";
      document.getElementById("animationPreviewStatus").textContent = message;
      document.getElementById("animationBarStatus").textContent = message;
      if (!result.ok) {
        ctx.elements.animationPreviewBar.classList.add("is-hidden");
        ctx.elements.animationOverlay.classList.remove("is-hidden");
      }
    });

    document
      .getElementById("animationStopButton")
      .addEventListener("click", ctx.animations.stopCatalogPreview);

    document
      .getElementById("animationBarStopButton")
      .addEventListener("click", ctx.animations.stopCatalogPreview);

    document.getElementById("animationBarBackButton").addEventListener("click", async () => {
      ctx.elements.animationPreviewBar.classList.add("is-hidden");
      ctx.elements.animationOverlay.classList.remove("is-hidden");
      await ctx.animations.stopCatalogPreview();
    });

    document
      .getElementById("animationAddButton")
      .addEventListener("click", ctx.animations.addSelectedAnimation);

    document
      .getElementById("animationBarAddButton")
      .addEventListener("click", ctx.animations.addSelectedAnimation);
  };
};
