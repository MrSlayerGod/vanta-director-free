/* Presentation-only FR/EN localization. No project values or native identifiers are rewritten. */
(() => {
  "use strict";
  const catalog = window.VantaLocales;
  if (!catalog) throw new Error("Director locale catalog is missing");
  const exact = new Map(),
    patterns = [],
    textState = new WeakMap(),
    attrState = new WeakMap();
  let language = window.VantaPreferences?.language === "en" ? "en" : "fr";
  const cache = new Map(),
    pending = new Set();
  let queued = false;
  const attributes = ["title", "placeholder", "aria-label", "alt"];
  const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  for (const [key, entry] of Object.entries(catalog.messages)) {
    if (!entry.en && !entry.fr) {
      console.warn("[Director locale] Empty entry:", key);
      continue;
    }
    if (!entry.en || !entry.fr)
      console.warn("[Director locale] Using fallback for:", key);
    if ((entry.en || entry.fr).includes("{")) {
      for (const source of [
        entry.en,
        entry.fr,
        ...(entry.aliases || []),
      ].filter(Boolean)) {
        const names = [];
        const expression = source
          .split(/(\{\w+\})/)
          .map((part) => {
            if (!/^\{\w+\}$/.test(part)) return escape(part);
            const name = part.slice(1, -1);
            names.push(name);
            return "(" + (catalog.arguments[name] || ".+?") + ")";
          })
          .join("");
        patterns.push({
          entry,
          names,
          regex: new RegExp("^" + expression + "$"),
        });
      }
    } else
      for (const source of [
        entry.en,
        entry.fr,
        ...(entry.aliases || []),
      ].filter(Boolean)) {
        // First canonical entry wins for synonymous source captions.
        if (!exact.has(source)) exact.set(source, entry);
      }
  }
  function core(source, depth = 0) {
    if (!source || depth > 5 || !/[A-Za-zÀ-ÿ]/.test(source)) return source;
    const entry = exact.get(source);
    if (entry) return entry[language] || entry.en || entry.fr || source;
    for (const pattern of patterns) {
      if (
        pattern.entry.en === "{model} · {category}" ||
        pattern.entry.en.startsWith("{category} · {mode}")
      )
        continue;
      const match = pattern.regex.exec(source);
      if (!match) continue;
      const args = Object.fromEntries(
        pattern.names.map((name, i) => [name, match[i + 1]]),
      );
      // Only semantic fragments are translated recursively. Model IDs and user names stay verbatim.
      for (const name of pattern.entry.translate || [])
        if (args[name]) args[name] = core(args[name], depth + 1);
      return (
        pattern.entry[language] ||
        pattern.entry.en ||
        pattern.entry.fr
      ).replace(/\{(\w+)\}/g, (_, name) => args[name] ?? "{" + name + "}");
    }
    // Compound hints and badges consist of known phrases separated by a dot, line break or sentence.
    if (source.includes(" · "))
      return source
        .split(" · ")
        .map((part) => core(part, depth + 1))
        .join(" · ");
    for (const separator of [". ", "; ", "\n"]) {
      if (source.includes(separator)) {
        const parts = source.split(separator);
        return parts
          .map((part, i) => {
            const punctuation =
              separator === ". " && i < parts.length - 1 ? "." : "";
            const value = core(part + punctuation, depth + 1);
            return punctuation && value.endsWith(".")
              ? value.slice(0, -1)
              : value;
          })
          .join(separator);
      }
    }
    return source; // Unsupported/native/user supplied content is never guessed or sent to a service.
  }
  function t(value) {
    const source = String(value ?? "");
    if (cache.has(source)) return cache.get(source);
    const trimmed = source.trim();
    const valueOut =
      source.slice(0, source.indexOf(trimmed)) +
      core(trimmed) +
      source.slice(source.indexOf(trimmed) + trimmed.length);
    if (cache.size >= 2048) cache.clear();
    cache.set(source, valueOut);
    return valueOut;
  }
  function excluded(element) {
    return (
      !element ||
      !!element.closest(
        'script,style,textarea,code,[contenteditable="true"],[data-i18n-user]',
      )
    );
  }
  function text(node) {
    if (excluded(node.parentElement)) return;
    const current = node.nodeValue,
      previous = textState.get(node);
    const source =
      previous && current === previous.output ? previous.source : current;
    const output = t(source);
    textState.set(node, { source, output });
    if (output !== current) node.nodeValue = output;
  }
  function element(node) {
    if (excluded(node)) return;
    // Native option values must remain stable even when HTML did not provide an explicit value.
    if (node.tagName === "OPTION" && !node.hasAttribute("value"))
      node.setAttribute("value", node.value);
    let state = attrState.get(node);
    if (!state) {
      state = {};
      attrState.set(node, state);
    }
    for (const name of attributes) {
      if (!node.hasAttribute(name)) continue;
      const current = node.getAttribute(name),
        previous = state[name];
      const source =
        previous && current === previous.output ? previous.source : current;
      const output = t(source);
      state[name] = { source, output };
      if (output !== current) node.setAttribute(name, output);
    }
  }
  function subtree(node) {
    if (!node.isConnected) return;
    if (node.nodeType === Node.TEXT_NODE) return text(node);
    if (node.nodeType !== Node.ELEMENT_NODE || excluded(node)) return;
    element(node);
    const walk = document.createTreeWalker(
      node,
      NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT,
    );
    let child;
    while ((child = walk.nextNode())) {
      if (child.nodeType === Node.TEXT_NODE) text(child);
      else element(child);
    }
  }
  const observer = new MutationObserver((records) => {
    for (const record of records) {
      if (record.type === "childList")
        for (const node of record.addedNodes) pending.add(node);
      else pending.add(record.target);
    }
    if (!queued && pending.size) {
      queued = true;
      queueMicrotask(flush);
    }
  });
  const watch = () =>
    observer.observe(document.body, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: attributes,
    });
  function flush(all = false) {
    queued = false;
    observer.disconnect();
    try {
      if (all) subtree(document.body);
      else for (const node of pending) subtree(node);
      pending.clear();
    } finally {
      watch();
    }
  }
  function setLanguage(value) {
    language = value === "en" ? "en" : "fr";
    cache.clear();
    document.documentElement.lang = language;
    document.documentElement.style.setProperty(
      "--model-loading-label",
      JSON.stringify(t("Loading 3D preview…")),
    );
    flush(true);
    window.dispatchEvent(
      new CustomEvent("directorLanguage", { detail: { language } }),
    );
  }
  window.VantaI18n = {
    ready: true,
    t,
    setLanguage,
    get language() {
      return language;
    },
    searchText(source) {
      const entry = exact.get(source);
      return entry ? entry.en + " " + entry.fr : source;
    },
    has(source) {
      return exact.has(source) || patterns.some((p) => p.regex.test(source));
    },
    key(key, args = {}) {
      const entry = catalog.messages[key];
      if (!entry) {
        if (window.VantaRuntimeConfig?.debug)
          console.warn("[Director locale] Missing key:", key);
        return key;
      }
      return (entry[language] || entry.en || entry.fr || key).replace(
        /\{(\w+)\}/g,
        (_, name) => String(args[name] ?? "{" + name + "}"),
      );
    },
  };
  window.addEventListener("directorPreferences", (event) =>
    setLanguage(event.detail?.language),
  );
  setLanguage(language);
})();
