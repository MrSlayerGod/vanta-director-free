// Define services first: event handlers only bind once the shared state exists.
(() => {
  const ctx = window.DirectorEditor;
  const moduleNames = [
    "animations",
    "transport",
    "saving",
    "lifecycle",
    "camera",
    "status",
    "library",
    "formatting",
    "timeline",
    "collaboration",
    "sequences",
    "actionChain",
    "presets",
    "staging",
    "production",
    "projectView",
    "inspector",
    "accessories",
    "appearance",
    "actors",
    "pins",
    "tabs",
    "environment",
    "models",
    "input",
    "toolbar",
    "recording",
    "events",
  ];
  const bindings = moduleNames.map((name) => ctx.modules[name](ctx));
  ctx.initializeState(ctx);
  for (const bind of bindings) bind();
  ctx.projectView.renderProject();
  ctx.state.recordingSourceFields();
  ctx.ready = true;
})();
