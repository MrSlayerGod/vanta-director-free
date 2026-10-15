window.DirectorEditor.modules.transport = function defineModule(ctx) {
  ctx.transport = {};
  ctx.transport.post = async function post(name, data = {}, options = {}) {
    if (!ctx.state.bridgeReady) return { ok: false, message: "Director is closed." };
    const result = await window.VantaBridge.request(name, data);
    if (!result.ok && result.message && !options.silent) ctx.status.showStatus(result.message);
    if (result.ok && ctx.state.mutatingCalls.has(name)) {
      ctx.saving.setSaveState(false);
      window.VantaWorkflow?.invalidate();
    }
    if (result.ok && window.VantaTutorialActive) {
      window.dispatchEvent(new CustomEvent("directorAction", { detail: { name, data, result } }));
    }
    return result;
  };
  return function bindEvents() {};
};
