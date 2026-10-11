window.DirectorEditor.modules.lifecycle = function defineModule(ctx) {
  ctx.lifecycle = {};
  ctx.lifecycle.requestClose = function requestClose() {
    ctx.input.clearKeys();
    if (
      (ctx.state.saveDirty && window.VantaPreferences?.warning !== false) ||
      ctx.state.savePending
    )
      ctx.elements.exitOverlay.classList.remove("is-hidden");
    else ctx.transport.post("close");
  };
  return function bindEvents() {
    document
      .getElementById("exitCancelButton")
      .addEventListener("click", () => ctx.elements.exitOverlay.classList.add("is-hidden"));

    document.getElementById("exitConfirmButton").addEventListener("click", () => {
      ctx.elements.exitOverlay.classList.add("is-hidden");
      ctx.transport.post("close");
    });
  };
};
