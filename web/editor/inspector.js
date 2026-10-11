window.DirectorEditor.modules.inspector = function defineModule(ctx) {
  ctx.inspector = {};
  ctx.inspector.sceneElementName = function sceneElementName(actor) {
    return (
      actor.name ||
      ctx.state.sceneModelNames.get(actor.model) ||
      {
        a_m_y_business_01: "Businessman",
        sultan: "Sultan",
        prop_tool_box_04: "Tool box",
      }[actor.model] ||
      actor.model
        .replace(/^(?:a_[mf]_[myo]_?|s_[mf]_[myo]_?|prop_)/, "")
        .replace(/_/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase())
    );
  };

  ctx.inspector.inspectorGroup = function inspectorGroup(actor, name, initiallyOpen) {
    const key = actor.id + ":" + name;
    const section = document.createElement("details");
    section.className = "inspector-group";
    section.dataset.sectionKey = name;
    section.open = ctx.state.inspectorSections.has(key)
      ? ctx.state.inspectorSections.get(key)
      : initiallyOpen;
    const summary = document.createElement("summary");
    summary.textContent = name;
    section.appendChild(summary);
    section.addEventListener("toggle", () => ctx.state.inspectorSections.set(key, section.open));
    return section;
  };

  ctx.inspector.renderInspectorMode = function renderInspectorMode() {
    document
      .getElementById("cameraInspector")
      .classList.toggle("is-hidden", ctx.state.sceneTabActive || ctx.state.lookTabActive);
    document
      .getElementById("actorInspector")
      .classList.toggle("is-hidden", !ctx.state.sceneTabActive);
    const actor = ctx.state.project.actors.find((item) => item.id === ctx.state.selectedActorId);
    if (ctx.state.sceneTabActive) {
      document.getElementById("inspectorEyebrow").textContent = actor
        ? `${ctx.formatting.actorLabel(actor.kind)} ${String(actor.id).padStart(2, "0")} / INSPECTOR`
        : "INSPECTOR";
      document.getElementById("inspectorTitle").textContent = actor
        ? ctx.inspector.sceneElementName(actor)
        : "Scene";
      document
        .getElementById("inspectorTitle")
        .toggleAttribute("data-i18n-user", Boolean(actor?.name));
      document.getElementById("liveTag").classList.add("is-hidden");
    }
  };
  return function bindEvents() {};
};
