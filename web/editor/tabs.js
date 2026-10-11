window.DirectorEditor.modules.tabs = function defineModule(ctx) {
  ctx.tabs = {};
  ctx.tabs.selectSceneTab = function selectSceneTab(scene) {
    window.VantaWorkflow?.tab(scene);
    ctx.state.lookTabActive = scene === "look";
    ctx.state.sceneTabActive = scene === true;
    if (scene && ctx.state.selectedFrameTime !== null) {
      ctx.state.selectedFrameTime = null;
      for (const row of ctx.elements.keyframeList.children) row.classList.remove("selected");
      ctx.camera.renderCamera();
    }
    document.getElementById("actorsPane").classList.toggle("is-hidden", !ctx.state.sceneTabActive);
    document.getElementById("cameraPane").classList.toggle("is-hidden", ctx.state.sceneTabActive);
    document.getElementById("lookPane").classList.toggle("is-hidden", !ctx.state.lookTabActive);
    document.getElementById("actorsTab").classList.toggle("active", ctx.state.sceneTabActive);
    document
      .getElementById("cameraTab")
      .classList.toggle("active", !ctx.state.sceneTabActive && !ctx.state.lookTabActive);
    document.getElementById("lookTab").classList.toggle("active", ctx.state.lookTabActive);
    if (ctx.state.sceneTabActive) ctx.actors.renderActors();
    else if (ctx.state.lookTabActive) {
      ctx.environment.renderLook();
      ctx.camera.renderCamera();
    } else ctx.camera.renderCamera();
    ctx.inspector.renderInspectorMode();
    window.VantaPolish?.render();
    window.VantaWorkflow?.render();
  };
  return function bindEvents() {
    document
      .getElementById("actorsTab")
      .addEventListener("click", () => ctx.tabs.selectSceneTab(true));

    document
      .getElementById("cameraTab")
      .addEventListener("click", () => ctx.tabs.selectSceneTab(false));

    document
      .getElementById("lookTab")
      .addEventListener("click", () => ctx.tabs.selectSceneTab("look"));
  };
};
