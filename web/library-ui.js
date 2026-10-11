/* Library enhancement leaves all project operations in the existing validated bridge. */
(() => {
  const overlay = document.getElementById("libraryOverlay"),
    panel = overlay.querySelector(".library-panel");
  const browse = document.getElementById("libraryBrowse"),
    transfer = document.getElementById("projectTransfer");
  const libraryTab = document.getElementById("libraryTab"),
    transferTab = document.getElementById("transferTab");
  const search = document.getElementById("librarySearch"),
    list = document.getElementById("libraryList");
  let wasOpen = false,
    returnFocus = null;
  function closeMenus() {
    panel.querySelectorAll(".library-menu").forEach((menu) => {
      menu.classList.add("is-hidden");
      menu.previousElementSibling?.setAttribute("aria-expanded", "false");
    });
  }
  function setTab(importing) {
    closeMenus();
    browse.classList.toggle("is-hidden", importing);
    transfer.classList.toggle("is-hidden", !importing);
    libraryTab.setAttribute("aria-pressed", String(!importing));
    transferTab.setAttribute("aria-pressed", String(importing));
  }
  libraryTab.addEventListener("click", () => setTab(false));
  transferTab.addEventListener("click", () => setTab(true));
  search.addEventListener("input", window.DirectorEditor.library.renderLibrary);
  function enhanceRows() {
    document.getElementById("libraryResults").textContent =
      `${list.querySelectorAll(".library-row").length} SAVED PROJECTS`;
    const active = window.DirectorEditor.state.libraryState.projects.find(
      (item) => item.id === window.DirectorEditor.state.libraryState.activeId,
    );
    document.getElementById("libraryExportName").textContent = active?.name || "Current project";
    document
      .getElementById("libraryExportName")
      .toggleAttribute("data-i18n-user", Boolean(active?.name));
    list.querySelectorAll(".library-row").forEach((row) => {
      if (row.dataset.enhanced) return;
      row.dataset.enhanced = "true";
      const info = row.firstElementChild,
        actions = row.lastElementChild;
      info.classList.add("library-info");
      const buttons = Array.from(actions.children),
        open = buttons.find((button) => button.classList.contains("library-open"));
      if (!open) {
        const continueButton = window.DirectorEditor.library.libraryButton(
          "Continue editing",
          window.DirectorEditor.library.closeLibrary,
          "library-current",
        );
        actions.prepend(continueButton);
      }
      const more = window.DirectorEditor.library.libraryButton("⋯", () => {}, "library-more");
      more.setAttribute("aria-label", "Project actions");
      more.setAttribute("aria-expanded", "false");
      const menu = document.createElement("div");
      menu.className = "library-menu is-hidden";
      buttons.filter((button) => button !== open).forEach((button) => menu.append(button));
      actions.append(more, menu);
      more.addEventListener("click", (event) => {
        event.stopPropagation();
        const opening = menu.classList.contains("is-hidden");
        closeMenus();
        menu.classList.toggle("is-hidden", !opening);
        more.setAttribute("aria-expanded", String(opening));
        if (opening) {
          const bounds = menu.getBoundingClientRect();
          menu.classList.toggle("flip", bounds.bottom > panel.getBoundingClientRect().bottom - 24);
          menu.querySelector("button:not(:disabled)")?.focus();
        }
      });
      menu.addEventListener("click", () => closeMenus());
      const rename = buttons.find((button) => button.dataset.actionLabel === "Rename");
      rename?.addEventListener("click", () => {
        const input = info.querySelector("input");
        if (input) {
          input.setAttribute("aria-label", "Project name");
          input.focus();
          input.select();
          input.addEventListener("keydown", (event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              info.querySelector(".library-rename-actions button")?.click();
            }
            if (event.key === "Escape") {
              event.preventDefault();
              event.stopPropagation();
              window.DirectorEditor.library.renderLibrary();
            }
          });
        }
      });
    });
  }
  new MutationObserver(enhanceRows).observe(list, { childList: true });
  // One callback per opening/closing; no per-frame effects or polling.
  const sync = () => {
    const opened = !overlay.classList.contains("is-hidden");
    if (opened !== wasOpen) {
      wasOpen = opened;
      window.DirectorEditor.transport.post("projectDialog", { open: opened });
      if (opened) {
        returnFocus = document.activeElement;
        setTab(false);
        search.value = "";
        window.DirectorEditor.library.renderLibrary();
        document.getElementById("libraryCloseButton").focus();
      } else {
        closeMenus();
        returnFocus?.focus?.();
        returnFocus = null;
      }
    }
  };
  new MutationObserver(sync).observe(overlay, {
    attributes: true,
    attributeFilter: ["class"],
  });
  document.addEventListener("click", (event) => {
    if (!event.target.closest(".library-actions")) closeMenus();
  });
  overlay.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && panel.querySelector(".library-menu:not(.is-hidden)")) {
      event.preventDefault();
      event.stopPropagation();
      const trigger = panel.querySelector(".library-menu:not(.is-hidden)").previousElementSibling;
      closeMenus();
      trigger.focus();
      return;
    }
    if (event.key !== "Tab") return;
    const scope = !document.getElementById("libraryConfirm").classList.contains("is-hidden")
      ? document.getElementById("libraryConfirm")
      : panel;
    const nodes = Array.from(scope.querySelectorAll("button,input,textarea")).filter(
      (el) => !el.disabled && el.getClientRects().length,
    );
    const first = nodes[0],
      last = nodes[nodes.length - 1];
    if (!first) return;
    if (
      event.shiftKey &&
      (document.activeElement === first || !scope.contains(document.activeElement))
    ) {
      event.preventDefault();
      last.focus();
    } else if (
      !event.shiftKey &&
      (document.activeElement === last || !scope.contains(document.activeElement))
    ) {
      event.preventDefault();
      first.focus();
    }
  });
  new MutationObserver(() => {
    if (!document.getElementById("libraryConfirm").classList.contains("is-hidden"))
      document.getElementById("libraryCancelButton").focus();
  }).observe(document.getElementById("libraryConfirm"), {
    attributes: true,
    attributeFilter: ["class"],
  });
  enhanceRows();
  sync();
})();
