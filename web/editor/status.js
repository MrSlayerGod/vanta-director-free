window.DirectorEditor.modules.status = function defineModule(ctx) {
  ctx.status = {};
  ctx.status.showStatus = function showStatus(message) {
    message = window.VantaI18n?.t(message) ?? message;
    if (!message) return;
    ctx.elements.statusMessage.textContent = message;
    ctx.elements.toast.textContent = message;
    ctx.elements.toast.classList.add("visible");
    clearTimeout(ctx.state.toastTimeout);
    ctx.state.toastTimeout = setTimeout(() => ctx.elements.toast.classList.remove("visible"), 2400);
  };

  ctx.status.setLookHint = function setLookHint(message) {
    if (typeof window.VantaViewHint === "function") window.VantaViewHint(message);
    else
      document.getElementById("lookHint").textContent =
        message || "RIGHT DRAG: CAMERA · LEFT DRAG: ACTORS · ALT / ↻: ROTATE · SHIFT: HEIGHT";
  };

  ctx.status.setText = function setText(element, value) {
    if (!element?.hasAttribute?.("data-i18n-user")) value = window.VantaI18n?.t(value) ?? value;
    if (element && element.textContent !== value) element.textContent = value;
  };
  return function bindEvents() {};
};
