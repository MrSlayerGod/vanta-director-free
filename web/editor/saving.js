window.DirectorEditor.modules.saving = function defineModule(ctx) {
  ctx.saving = {};
  let draftTimer,
    draftTimeout,
    draftPending = false;
  let editVersion = 0,
    draftVersion = -1,
    pendingVersion = -1;
  let recovery = null;
  let activeProjectId = null;

  ctx.saving.resetDraft = function resetDraft() {
    clearTimeout(draftTimer);
    clearTimeout(draftTimeout);
    draftTimer = null;
    draftPending = false;
    editVersion = 0;
    draftVersion = -1;
  };
  ctx.saving.queueDraft = function queueDraft() {
    if (
      draftTimer ||
      !ctx.state.bridgeReady ||
      window.VantaRuntimeConfig?.recoveryEnabled === false
    )
      return;
    draftTimer = setTimeout(async () => {
      draftTimer = null;
      if (!ctx.state.bridgeReady || !ctx.state.saveDirty || draftVersion === editVersion) return;
      const blocked =
        draftPending ||
        ctx.state.savePending ||
        ctx.state.previewPlaying ||
        ctx.state.sessionRole === "viewer" ||
        ctx.state.actorDragging ||
        ctx.state.timelineDrag ||
        ctx.elements.root.classList.contains("is-hidden") ||
        ctx.input.isTyping() ||
        !document.getElementById("routeEditor").classList.contains("is-hidden");
      if (!blocked) {
        pendingVersion = editVersion;
        draftPending = true;
        draftTimeout = setTimeout(() => {
          draftPending = false;
          ctx.saving.queueDraft();
        }, 12000);
        const result = await ctx.transport.post("saveDraft", {}, { silent: true });
        if (!result.ok) {
          clearTimeout(draftTimeout);
          draftPending = false;
        }
      }
      ctx.saving.queueDraft();
    }, 30000);
  };

  ctx.saving.setSaveState = function setSaveState(saved) {
    ctx.state.saveDirty = !saved;
    if (!saved) {
      editVersion += 1;
      ctx.saving.queueDraft();
    } else {
      clearTimeout(draftTimer);
      draftTimer = null;
    }
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
    const banner = document.createElement("section");
    banner.className = "recovery-banner is-hidden";
    banner.innerHTML = `
      <strong>Recovery draft available</strong>
      <span data-i18n-user="true"></span>
      <p>Restore a separate copy of your last unsaved scene.</p>
      <button type="button">Restore as new project</button>
      <button type="button">Discard draft</button>`;
    ctx.elements.libraryList.before(banner);
    const recoveryAction = async (operation) => {
      if (!recovery || ctx.state.sessionRole === "viewer") return;
      const run = async () => {
        ctx.elements.libraryConfirm.classList.add("is-hidden");
        ctx.state.pendingLibraryConfirm = null;
        ctx.library.setLibraryBusy(true);
        const result = await ctx.transport.post("manageRecovery", {
          operation,
          revision: recovery.revision,
        });
        if (!result.ok) ctx.library.setLibraryBusy(false);
      };
      ctx.library.confirmLibraryAction(
        operation === "restore" ? "Restore recovery draft?" : "Discard recovery draft?",
        operation === "restore"
          ? "A new project will be created. Save your current changes before continuing."
          : "This removes the recovery draft only. Your saved projects stay available.",
        run,
      );
    };
    banner.querySelectorAll("button")[0].onclick = () => recoveryAction("restore");
    banner.querySelectorAll("button")[1].onclick = () => recoveryAction("discard");
    window.addEventListener("message", ({ data }) => {
      if (data?.action === "open" || data?.action === "close") {
        ctx.saving.resetDraft();
        activeProjectId = null;
      }
      if (data?.action === "library" && data.activeId !== activeProjectId) {
        ctx.saving.resetDraft();
        activeProjectId = data.activeId;
      }
      if (data?.action === "recoveryState") {
        recovery = data.draft || null;
        banner.classList.toggle("is-hidden", !recovery);
        banner.querySelector("span").textContent = recovery?.name || "";
        ctx.library.setLibraryBusy(false);
      }
      if (data?.action === "draftResult" && draftPending) {
        clearTimeout(draftTimeout);
        draftPending = false;
        if (data.ok) {
          draftVersion = pendingVersion;
          document.getElementById("saveState").title =
            "A recovery draft is protected on this server. Save project to keep your final version.";
          if (ctx.state.saveDirty && draftVersion === editVersion)
            document.getElementById("saveState").textContent = "Unsaved · draft protected";
        }
      }
    });
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
