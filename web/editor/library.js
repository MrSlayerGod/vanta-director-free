window.DirectorEditor.modules.library = function defineModule(ctx) {
  ctx.library = {};
  ctx.library.closeLibrary = function closeLibrary() {
    ctx.elements.libraryOverlay.classList.add("is-hidden");
    ctx.elements.libraryConfirm.classList.add("is-hidden");
    ctx.state.pendingLibraryConfirm = null;
  };

  ctx.library.setLibraryBusy = function setLibraryBusy(busy) {
    ctx.state.libraryBusy = busy;
    clearTimeout(ctx.state.libraryWaitTimer);
    ctx.state.libraryWaitTimer = busy
      ? setTimeout(() => {
          ctx.library.setLibraryBusy(false);
          ctx.status.showStatus("No server response. Reopen the library before retrying.");
        }, 12000)
      : null;
    ctx.state.libraryPanel.classList.toggle("busy", busy);
  };

  ctx.library.confirmLibraryAction = function confirmLibraryAction(title, message, action) {
    ctx.state.pendingLibraryConfirm = action;
    document.getElementById("libraryConfirmTitle").textContent = title;
    document.getElementById("libraryConfirmText").textContent = message;
    ctx.elements.libraryConfirm.classList.remove("is-hidden");
  };

  ctx.library.performLibraryAction = async function performLibraryAction(operation, id, name) {
    ctx.elements.libraryConfirm.classList.add("is-hidden");
    ctx.state.pendingLibraryConfirm = null;
    clearTimeout(ctx.state.nameTimeout);
    ctx.state.nameTimeout = null;
    ctx.library.setLibraryBusy(true);
    const result = await ctx.transport.post("manageProject", { operation, id, name });
    if (!result.ok) {
      ctx.library.setLibraryBusy(false);
      ctx.status.showStatus(result.message || "Project action failed.");
    }
  };

  ctx.library.requestLibraryAction = function requestLibraryAction(operation, id, name) {
    if (ctx.state.libraryBusy) return;
    if (operation === "open" && id === ctx.state.libraryState.activeId) {
      ctx.library.closeLibrary();
      return;
    }
    const item = ctx.state.libraryState.projects.find((entry) => entry.id === id);
    if (operation === "delete") {
      ctx.library.confirmLibraryAction(
        "Delete this project?",
        `“${item?.name || "Project"}” will be removed permanently.${ctx.state.saveDirty ? " Your unsaved changes will also be lost." : ""}`,
        () => ctx.library.performLibraryAction(operation, id, name),
      );
    } else if (ctx.state.saveDirty && operation !== "rename") {
      ctx.library.confirmLibraryAction(
        "Unsaved changes",
        "Save the current project first, or continue and discard your unsaved changes.",
        () => ctx.library.performLibraryAction(operation, id, name),
      );
    } else ctx.library.performLibraryAction(operation, id, name);
  };

  ctx.library.libraryButton = function libraryButton(label, action, className = "") {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.dataset.actionLabel = label;
    button.className = className;
    button.addEventListener("click", action);
    return button;
  };

  ctx.library.renderLibrary = function renderLibrary() {
    const allItems = ctx.state.libraryState.projects;
    const query = (document.getElementById("librarySearch").value || "").trim().toLowerCase();
    const items = allItems.filter((item) => item.name.toLowerCase().includes(query));
    document.getElementById("libraryCount").textContent = Number.isFinite(
      ctx.state.libraryState.limit,
    )
      ? `${allItems.length} / ${ctx.state.libraryState.limit}`
      : `${allItems.length}`;
    document.getElementById("newProjectButton").disabled =
      allItems.length >= ctx.state.libraryState.limit || allItems.length === 0;
    ctx.elements.libraryList.innerHTML = "";
    if (!items.length) {
      const empty = document.createElement("p");
      empty.className = "library-empty";
      empty.textContent = allItems.length
        ? "No matching projects. Try another name."
        : "Loading projects…";
      ctx.elements.libraryList.appendChild(empty);
      return;
    }
    items.forEach((item) => {
      const row = document.createElement("div");
      row.className = `library-row${item.id === ctx.state.libraryState.activeId ? " active" : ""}`;
      const info = document.createElement("div");
      const title = document.createElement("strong");
      title.textContent = item.name;
      title.dataset.i18nUser = "true";
      info.appendChild(title);
      if (item.id === ctx.state.libraryState.activeId) {
        const badge = document.createElement("span");
        badge.className = "active-label";
        badge.textContent = "CURRENT";
        info.appendChild(badge);
      }
      const detail = document.createElement("small");
      detail.textContent = `${item.shots} shots · ${item.actors} actors · ${Math.round(Number(item.duration) || 20)} sec`;
      info.appendChild(detail);
      const actions = document.createElement("div");
      actions.className = "library-actions";
      if (item.id !== ctx.state.libraryState.activeId) {
        const open = ctx.library.libraryButton(
          "Open",
          () => ctx.library.requestLibraryAction("open", item.id),
          "library-open",
        );
        open.disabled = item.available === false;
        open.title = item.error || "";
        actions.appendChild(open);
      }
      if (item.available === false) {
        detail.textContent += " · Damaged project (preserved)";
        row.title = item.error || "Damaged project";
      }
      const duplicateButton = ctx.library.libraryButton("Duplicate", () =>
        ctx.library.requestLibraryAction("duplicate", item.id),
      );
      duplicateButton.disabled = item.available === false;
      actions.appendChild(duplicateButton);
      actions.appendChild(
        ctx.library.libraryButton("Rename", () => {
          info.innerHTML = "";
          actions.innerHTML = "";
          const input = document.createElement("input");
          input.type = "text";
          input.maxLength = 64;
          input.value = item.name;
          info.appendChild(input);
          const renameActions = document.createElement("div");
          renameActions.className = "library-rename-actions";
          renameActions.appendChild(
            ctx.library.libraryButton("Save name", () =>
              ctx.library.requestLibraryAction("rename", item.id, input.value.trim()),
            ),
          );
          renameActions.appendChild(ctx.library.libraryButton("Cancel", ctx.library.renderLibrary));
          info.appendChild(renameActions);
        }),
      );
      const deleteButton = ctx.library.libraryButton("Delete", () =>
        ctx.library.requestLibraryAction("delete", item.id),
      );
      deleteButton.disabled = allItems.length === 1;
      actions.appendChild(deleteButton);
      row.appendChild(info);
      row.appendChild(actions);
      ctx.elements.libraryList.appendChild(row);
    });
  };
  return function bindEvents() {
    document.getElementById("projectLibraryButton").addEventListener("click", () => {
      ctx.input.clearKeys();
      ctx.library.renderLibrary();
      ctx.elements.libraryOverlay.classList.remove("is-hidden");
    });

    document
      .getElementById("libraryCloseButton")
      .addEventListener("click", ctx.library.closeLibrary);

    document
      .getElementById("newProjectButton")
      .addEventListener("click", () => ctx.library.requestLibraryAction("create"));

    document.getElementById("libraryCancelButton").addEventListener("click", () => {
      ctx.elements.libraryConfirm.classList.add("is-hidden");
      ctx.state.pendingLibraryConfirm = null;
    });

    document.getElementById("libraryContinueButton").addEventListener("click", () => {
      if (ctx.state.pendingLibraryConfirm) ctx.state.pendingLibraryConfirm();
    });
  };
};
