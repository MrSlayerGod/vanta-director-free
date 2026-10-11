window.DirectorEditor.modules.collaboration = function defineModule(ctx) {
  ctx.collaboration = {};

  return function bindEvents() {
    document.getElementById("projectExport").addEventListener("click", async () => {
      if (ctx.state.libraryBusy) return;
      const button = document.getElementById("projectExport");
      button.disabled = true;
      const result = await ctx.transport.post("exportProject");
      button.disabled = false;
      if (result.ok) {
        document.getElementById("projectJson").value = result.json;
        ctx.status.showStatus(result.message || "Project exported. Copy the JSON to share it.");
      } else ctx.status.showStatus(result.message || "Export failed.");
    });

    document.getElementById("projectImport").addEventListener("click", () => {
      if (ctx.state.libraryBusy) return;
      const json = document.getElementById("projectJson").value.trim();
      if (!json) {
        ctx.status.showStatus("Paste a project JSON before importing.");
        return;
      }
      if (
        new TextEncoder().encode(json).length >
        (window.VantaRuntimeConfig?.projectFileLimit || 1048576)
      ) {
        ctx.status.showStatus("This project is too large to import.");
        return;
      }
      try {
        JSON.parse(json);
      } catch {
        ctx.status.showStatus("Invalid JSON. Paste a complete exported project.");
        return;
      }
      const run = async () => {
        ctx.elements.libraryConfirm.classList.add("is-hidden");
        ctx.state.pendingLibraryConfirm = null;
        ctx.library.setLibraryBusy(true);
        const result = await ctx.transport.post("importProject", { json });
        if (!result.ok) {
          ctx.library.setLibraryBusy(false);
          ctx.status.showStatus(result.message || "Import failed.");
        }
      };
      if (ctx.state.saveDirty || ctx.state.savePending)
        ctx.library.confirmLibraryAction(
          "Import a project?",
          "Save your current project first, or continue and discard its unsaved changes.",
          run,
        );
      else run();
    });

    for (const [id, operation] of [
      ["sessionCreate", "create"],
      ["sessionInviteButton", "invite"],
      ["sessionPublish", "publish"],
      ["sessionPlay", "play"],
      ["sessionStop", "stop"],
      ["sessionLeave", "leave"],
    ])
      document.getElementById(id).addEventListener("click", () =>
        ctx.transport.post("collaboration", {
          operation,
          target: Number(document.getElementById("sessionTarget").value),
        }),
      );

    for (const [id, operation] of [
      ["sessionAccept", "accept"],
      ["sessionDecline", "decline"],
    ])
      document.getElementById(id).addEventListener("click", () => {
        if (ctx.state.sessionInvitation)
          ctx.transport.post("collaboration", { operation, id: ctx.state.sessionInvitation });
        document.getElementById("sessionInviteOverlay").classList.add("is-hidden");
        ctx.state.sessionInvitation = null;
      });
  };
};
