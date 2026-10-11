window.DirectorEditor.modules.production = function defineModule(ctx) {
  ctx.production = {};
  ctx.production.updateFraming = function updateFraming() {
    const surface = document.getElementById("lookSurface"),
      overlay = document.getElementById("framingOverlay");
    const bounds = surface.getBoundingClientRect();
    overlay.style.left = bounds.left + "px";
    overlay.style.top = bounds.top + "px";
    overlay.style.width = bounds.width + "px";
    overlay.style.height = bounds.height + "px";
    overlay.style.right = "auto";
    overlay.style.bottom = "auto";
    const ratio = document.getElementById("framingGuide").value === "portrait" ? 9 / 16 : 2.39;
    const width = Math.min(bounds.width, bounds.height * ratio),
      height = width / ratio;
    overlay.style.setProperty?.("--guide-left", (bounds.width - width) / 2 + "px");
    overlay.style.setProperty?.("--guide-top", (bounds.height - height) / 2 + "px");
  };

  ctx.production.renderProductionSelectors = function renderProductionSelectors() {
    for (const [id, items, value] of [
      [
        "lookFocusSubject",
        [
          [0, "Manual focus distance"],
          ...ctx.state.project.actors.map((a) => [a.id, a.name || a.model]),
        ],
        String(ctx.state.project.look?.focusId || 0),
      ],
      [
        "stagingSelection",
        [
          ["", "Selected actor"],
          ...[...new Set(ctx.state.project.actors.map((a) => a.group).filter(Boolean))].map((g) => [
            g,
            g,
          ]),
        ],
        document.getElementById("stagingSelection").value,
      ],
    ]) {
      const select = document.getElementById(id),
        signature = JSON.stringify(items);
      if (select.vantaOptionsSignature !== signature) {
        select.innerHTML = "";
        for (const [key, label] of items) {
          const option = document.createElement("option");
          option.value = String(key);
          option.textContent = label;
          select.appendChild(option);
        }
        select.vantaOptionsSignature = signature;
      }
      select.value = items.some((item) => String(item[0]) === value) ? value : String(items[0][0]);
    }
  };

  ctx.production.renderProduction = function renderProduction() {
    ctx.production.updateFraming();
    ctx.production.renderProductionSelectors();
    const locations = document.getElementById("locationList");
    locations.innerHTML = "";
    (ctx.state.project.bookmarks || []).forEach((location, index) => {
      const row = document.createElement("div");
      row.className = "location-row";
      const go = document.createElement("button");
      go.textContent = location.name;
      go.dataset.i18nUser = "true";
      go.addEventListener("click", () => ctx.transport.post("goLocation", { index: index + 1 }));
      row.appendChild(go);
      const remove = document.createElement("button");
      remove.textContent = "×";
      remove.setAttribute("aria-label", "Delete " + location.name);
      remove.addEventListener("click", () =>
        ctx.transport.post("deleteLocation", { index: index + 1 }),
      );
      row.appendChild(remove);
      locations.appendChild(row);
    });
    document.getElementById("playbackFirst").max = ctx.state.project.duration;
    document.getElementById("playbackLast").max = ctx.state.project.duration;
    if (document.activeElement !== document.getElementById("playbackFirst"))
      document.getElementById("playbackFirst").value = ctx.state.project.playback?.first ?? 0;
    if (document.activeElement !== document.getElementById("playbackLast"))
      document.getElementById("playbackLast").value =
        ctx.state.project.playback?.last ?? ctx.state.project.duration;
    document.getElementById("playbackLoop").checked = ctx.state.project.playback?.loop === true;
  };
  return function bindEvents() {
    window.addEventListener("resize", ctx.production.updateFraming);

    document
      .getElementById("framingGuide")
      .addEventListener("change", ctx.production.updateFraming);
  };
};
