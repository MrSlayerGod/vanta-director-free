/* Native select values remain the source of truth for all existing NUI callbacks. */
(() => {
  const widgets = new Map();
  let active = null,
    query = "",
    highlighted = 0,
    typeAhead = "",
    typeTimer;
  const popup = document.createElement("div");
  popup.className = "vanta-select-menu is-hidden";
  popup.setAttribute("role", "listbox");
  popup.id = "vanta-select-options";
  document.getElementById("director").appendChild(popup);
  const close = (restore = false) => {
    const previous = active;
    active = null;
    popup.classList.add("is-hidden");
    if (previous) {
      previous.button.setAttribute("aria-expanded", "false");
      previous.button.removeAttribute("aria-activedescendant");
    }
    popup.removeAttribute("aria-activedescendant");
    if (restore && previous?.button.isConnected) previous.button.focus();
  };
  const refresh = (widget) => {
    const option = widget.select.selectedOptions[0];
    const caption = option?.textContent || "Select…";
    widget.caption.toggleAttribute(
      "data-i18n-user",
      Boolean(option?.hasAttribute("data-i18n-user")),
    );
    if (widget.caption.textContent !== caption)
      widget.caption.textContent = caption;
    widget.button.disabled = widget.select.disabled;
    widget.button.setAttribute(
      "aria-label",
      widget.select.getAttribute("aria-label") ||
        widget.select.closest("label")?.childNodes[0]?.textContent?.trim() ||
        widget.select.id ||
        "Choose option",
    );
  };
  const options = () =>
    Array.from(active.select.options).filter(
      (option) =>
        !option.hidden &&
        !option.disabled &&
        option.textContent.toLowerCase().includes(query),
    );
  const position = () => {
    if (!active) return;
    const bounds = active.button.getBoundingClientRect();
    const below = window.innerHeight - bounds.bottom - 12;
    const above = bounds.top - 12;
    const height = Math.min(310, Math.max(below, above));
    popup.style.width =
      Math.min(Math.max(bounds.width, 190), window.innerWidth - 24) + "px";
    popup.style.left =
      Math.max(
        12,
        Math.min(bounds.left, window.innerWidth - popup.offsetWidth - 12),
      ) + "px";
    popup.style.maxHeight = height + "px";
    popup.style.top =
      (below >= Math.min(popup.scrollHeight, 240) || below >= above
        ? bounds.bottom + 6
        : Math.max(12, bounds.top - Math.min(popup.scrollHeight, height) - 6)) +
      "px";
  };
  const choose = (option) => {
    const widget = active;
    widget.select.value = option.value;
    close(true);
    refresh(widget);
    widget.select.dispatchEvent(new Event("change", { bubbles: true }));
  };
  const renderOptions = () => {
    const list = popup.querySelector(".vanta-select-list");
    list.replaceChildren();
    const entries = options();
    highlighted = Math.max(0, Math.min(highlighted, entries.length - 1));
    entries.forEach((option, index) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "vanta-select-option";
      row.id = "vanta-option-" + index;
      row.setAttribute("role", "option");
      row.setAttribute(
        "aria-selected",
        String(option.value === active.select.value),
      );
      row.textContent = option.textContent;
      if (option.hasAttribute("data-i18n-user")) row.dataset.i18nUser = "true";
      row.classList.toggle("highlighted", index === highlighted);
      row.addEventListener("mousedown", (event) => event.preventDefault());
      row.addEventListener("click", () => choose(option));
      list.appendChild(row);
    });
    if (!entries.length) {
      const empty = document.createElement("div");
      empty.className = "vanta-select-empty";
      empty.textContent = "No matching options";
      list.appendChild(empty);
    }
    popup.setAttribute(
      "aria-activedescendant",
      entries.length ? "vanta-option-" + highlighted : "",
    );
    active.button.setAttribute(
      "aria-activedescendant",
      entries.length ? "vanta-option-" + highlighted : "",
    );
    list.children[highlighted]?.scrollIntoView({ block: "nearest" });
    position();
  };
  const open = (widget) => {
    if (widget.select.disabled) return;
    if (active === widget) return close();
    close();
    clearTimeout(typeTimer);
    typeAhead = "";
    active = widget;
    query = "";
    highlighted = Math.max(
      0,
      Array.from(widget.select.options)
        .filter((o) => !o.hidden && !o.disabled)
        .findIndex((o) => o.value === widget.select.value),
    );
    popup.replaceChildren();
    popup.classList.remove("is-hidden");
    widget.button.setAttribute("aria-expanded", "true");
    popup.setAttribute("aria-label", widget.button.getAttribute("aria-label"));
    if (widget.select.options.length > 8) {
      const search = document.createElement("input");
      search.type = "search";
      search.className = "vanta-select-search";
      search.placeholder = "Search options…";
      search.setAttribute("aria-label", "Search options");
      search.addEventListener("input", () => {
        query = search.value.toLowerCase();
        highlighted = 0;
        renderOptions();
      });
      popup.appendChild(search);
    }
    const list = document.createElement("div");
    list.className = "vanta-select-list";
    popup.appendChild(list);
    renderOptions();
    popup.querySelector("input")?.focus();
  };
  const enhance = (select) => {
    if (widgets.has(select) || select.multiple) return;
    const wrapper = document.createElement("span");
    wrapper.className = "vanta-select";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "vanta-select-trigger";
    button.setAttribute("role", "combobox");
    button.setAttribute("aria-haspopup", "listbox");
    button.setAttribute("aria-controls", popup.id);
    button.setAttribute("aria-expanded", "false");
    const caption = document.createElement("span");
    button.appendChild(caption);
    select.parentNode.insertBefore(wrapper, select);
    wrapper.appendChild(select);
    wrapper.appendChild(button);
    select.classList.add("vanta-native-select");
    select.tabIndex = -1;
    select.setAttribute("aria-hidden", "true");
    const widget = { select, button, caption };
    widgets.set(select, widget);
    button.addEventListener("click", (event) => {
      event.preventDefault();
      open(widget);
    });
    button.addEventListener("keydown", (event) => {
      if (
        !active &&
        ["ArrowDown", "ArrowUp", "Enter", " "].includes(event.key)
      ) {
        event.preventDefault();
        event.stopPropagation();
        open(widget);
      }
    });
    select.addEventListener("change", () => refresh(widget));
    select.addEventListener("focus", () => button.focus());
    refresh(widget);
  };
  const rangeValues = new WeakMap();
  const refreshRanges = () =>
    document.querySelectorAll("input[type=range]").forEach((input) => {
      const state = `${input.value}:${input.min}:${input.max}`;
      if (rangeValues.get(input) === state) return;
      rangeValues.set(input, state);
      const min = Number(input.min || 0),
        max = Number(input.max || 100);
      input.style.setProperty(
        "--range-fill",
        Math.max(
          0,
          Math.min(
            100,
            ((Number(input.value) - min) / Math.max(0.001, max - min)) * 100,
          ),
        ) + "%",
      );
    });
  document.addEventListener("input", (event) => {
    if (event.target.matches("input[type=range]")) refreshRanges();
  });
  window.addEventListener("message", (event) => {
    if (
      ["open", "project", "camera", "look", "modelPreview"].includes(
        event.data?.action,
      )
    )
      refreshRanges();
  });
  refreshRanges();
  const tip = document.createElement("div");
  tip.className = "vanta-tooltip is-hidden";
  tip.id = "vanta-tooltip";
  tip.setAttribute("role", "tooltip");
  document.getElementById("director").appendChild(tip);
  let tipTarget = null,
    tipTitle = "",
    tipTimer;
  const hideTip = () => {
    clearTimeout(tipTimer);
    tip.classList.add("is-hidden");
    if (tipTarget) {
      tipTarget.setAttribute("title", tipTitle);
      tipTarget.removeAttribute("aria-describedby");
    }
    tipTarget = null;
  };
  const showTip = (target) => {
    if (!target || target === tipTarget) return;
    hideTip();
    tipTarget = target;
    tipTitle = target.getAttribute("title");
    target.removeAttribute("title");
    tipTimer = setTimeout(() => {
      if (!target.isConnected || !tipTitle) return hideTip();
      tip.textContent = tipTitle;
      tip.classList.remove("is-hidden");
      target.setAttribute("aria-describedby", tip.id);
      const bounds = target.getBoundingClientRect();
      tip.style.left =
        Math.max(
          8,
          Math.min(bounds.left, window.innerWidth - tip.offsetWidth - 8),
        ) + "px";
      tip.style.top =
        (bounds.bottom + tip.offsetHeight + 14 < window.innerHeight
          ? bounds.bottom + 7
          : Math.max(8, bounds.top - tip.offsetHeight - 7)) + "px";
    }, 400);
  };
  document.addEventListener("pointerover", (event) => {
    if (!tipTarget?.contains(event.target))
      showTip(event.target.closest("[title]"));
  });
  document.addEventListener("pointerout", (event) => {
    if (tipTarget && !tipTarget.contains(event.relatedTarget)) hideTip();
  });
  document.addEventListener("focusin", (event) =>
    showTip(event.target.closest("[title]")),
  );
  document.addEventListener("focusout", hideTip);
  document.addEventListener("mousedown", hideTip);
  document.addEventListener("keydown", hideTip);
  window.addEventListener("resize", hideTip);
  document.querySelectorAll("select").forEach(enhance);
  new MutationObserver((records) => {
    const changed = new Set();
    let removedControls = false;
    records.forEach((record) => {
      const element =
        record.target.nodeType === 1
          ? record.target
          : record.target.parentElement;
      const select = element?.closest("select");
      if (select && widgets.has(select)) changed.add(widgets.get(select));
      for (const node of record.addedNodes || [])
        if (node.nodeType === 1) {
          if (node.matches("select")) enhance(node);
          node.querySelectorAll("select").forEach(enhance);
        }
      for (const node of record.removedNodes || [])
        if (
          node.nodeType === 1 &&
          (node.matches("select") || node.querySelector("select"))
        )
          removedControls = true;
    });
    if (removedControls)
      for (const [select, widget] of widgets)
        if (!select.isConnected) {
          if (active === widget) close();
          widgets.delete(select);
        }
    changed.forEach(refresh);
    if (active && changed.has(active)) renderOptions();
  }).observe(document.getElementById("director"), {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeFilter: ["disabled"],
  });
  window.addEventListener("message", (event) => {
    if (event.data?.action === "modelCatalog" && event.data.complete === false)
      return;
    if (
      [
        "open",
        "project",
        "look",
        "tab",
        "modelCatalog",
        "routeControls",
      ].includes(event.data?.action)
    ) {
      if (["open", "project", "tab"].includes(event.data.action)) close();
      widgets.forEach(refresh);
    }
    if (
      ["close", "capture", "captureCountdown", "motionRecordStarted"].includes(
        event.data?.action,
      )
    ) {
      close();
      hideTip();
    }
  });
  document.addEventListener("mousedown", (event) => {
    if (
      active &&
      !popup.contains(event.target) &&
      !active.button.contains(event.target)
    )
      close();
  });
  document.addEventListener(
    "keydown",
    (event) => {
      if (!active) return;
      if (event.key === "Tab") return close();
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopImmediatePropagation();
        close(true);
        return;
      }
      const entries = options();
      if (
        ["ArrowDown", "ArrowUp", "Home", "End", "Enter", " "].includes(
          event.key,
        ) &&
        !(event.target.matches("input") && event.key === " ")
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (event.key === "Enter" || event.key === " ") {
          if (entries[highlighted]) choose(entries[highlighted]);
          return;
        }
        highlighted =
          event.key === "Home"
            ? 0
            : event.key === "End"
              ? entries.length - 1
              : Math.max(
                  0,
                  Math.min(
                    entries.length - 1,
                    highlighted + (event.key === "ArrowDown" ? 1 : -1),
                  ),
                );
        renderOptions();
      } else if (
        event.key.length === 1 &&
        !event.target.matches("input") &&
        !event.ctrlKey &&
        !event.altKey
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        clearTimeout(typeTimer);
        typeAhead += event.key.toLowerCase();
        const index = entries.findIndex((o) =>
          o.textContent.toLowerCase().startsWith(typeAhead),
        );
        if (index >= 0) {
          highlighted = index;
          renderOptions();
        }
        typeTimer = setTimeout(() => {
          typeAhead = "";
        }, 650);
      }
    },
    true,
  );
  window.addEventListener("resize", close);
  document.addEventListener(
    "scroll",
    (event) => {
      if (active && !popup.contains(event.target)) close();
    },
    true,
  );
})();
