window.DirectorEditor.modules.saving = function defineModule(ctx) {
  ctx.saving = {};
  ctx.saving.setSaveState = function setSaveState(saved) {
    ctx.state.saveDirty = !saved;
    const label = document.getElementById("saveState");
    label.textContent = saved
      ? "Saved on server"
      : ctx.state.savePending
        ? "Saving on server…"
        : "Unsaved changes";
    if (saved) {
      label.classList.add("saved");
      label.classList.remove("dirty");
    } else {
      label.classList.add("dirty");
      label.classList.remove("saved");
    }
    window.VantaWorkflow?.render();
  };

  ctx.saving.setSavePending = function setSavePending(pending) {
    ctx.state.savePending = pending;
    clearTimeout(ctx.state.savePendingTimeout);
    ctx.state.savePendingTimeout = pending
      ? setTimeout(() => {
          ctx.saving.setSavePending(false);
          ctx.saving.setSaveState(false);
          ctx.status.showStatus("Save is taking too long. Check the project before trying again.");
        }, 12000)
      : null;
    const button = document.getElementById("saveButton");
    button.disabled = pending || ctx.state.sessionRole === "viewer";
    button.textContent = pending ? "Saving…" : "Save project";
    button.classList.toggle("saving", pending);
    if (pending) document.getElementById("saveState").textContent = "Saving on server…";
    window.VantaWorkflow?.render();
  };
  return function bindEvents() {
    document.getElementById("saveButton").addEventListener("click", async () => {
      if (ctx.state.savePending) return;
      clearTimeout(ctx.state.nameTimeout);
      ctx.state.nameTimeout = null;
      ctx.saving.setSavePending(true);
      const nameResult = await ctx.transport.post("setProjectName", {
        name: ctx.elements.projectNameInput.value,
      });
      if (!nameResult.ok) {
        ctx.saving.setSavePending(false);
        ctx.status.showStatus(nameResult.message || "Could not update the project name.");
        return;
      }
      const result = await ctx.transport.post("saveProject");
      if (!result.ok) {
        ctx.saving.setSavePending(false);
        ctx.saving.setSaveState(false);
        ctx.status.showStatus(result.message || "Could not save project.");
      }
    });

    ctx.elements.projectNameInput.addEventListener("input", () => {
      ctx.saving.setSaveState(false);
      clearTimeout(ctx.state.nameTimeout);
      ctx.state.nameTimeout = setTimeout(
        () => ctx.transport.post("setProjectName", { name: ctx.elements.projectNameInput.value }),
        180,
      );
    });

    document.addEventListener("focusin", (event) => {
      if (event.target.matches('input, textarea, [contenteditable="true"]')) {
        ctx.input.clearKeys();
      }
    });
  };
};
