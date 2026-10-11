/* NUI transport shared by the editor and route tools. UI side effects stay with callers. */
(function (scope) {
  function createBridge(resource, fetchRequest = scope.fetch.bind(scope), timeoutMs = 15000) {
    async function request(name, data = {}, options = {}) {
      const controller = new AbortController();
      const cancel = () => controller.abort();
      const signal = options.signal;
      if (signal?.aborted) controller.abort();
      else signal?.addEventListener("abort", cancel, { once: true });
      const timer = setTimeout(cancel, timeoutMs);
      try {
        if (!/^[a-zA-Z][a-zA-Z0-9]*$/.test(name)) throw new Error("Invalid callback");
        const response = await fetchRequest(`https://${resource}/${name}`, {
          method: "POST",
          signal: controller.signal,
          headers: { "Content-Type": "application/json; charset=UTF-8" },
          body: JSON.stringify(data),
        });
        if (response.ok === false) throw new Error("NUI request failed");
        const result = await response.json();
        if (!result || typeof result.ok !== "boolean") throw new Error("Invalid NUI response");
        return result;
      } catch {
        return { ok: false, message: "Could not reach the game client." };
      } finally {
        clearTimeout(timer);
        signal?.removeEventListener("abort", cancel);
      }
    }
    return { request };
  }
  if (typeof module !== "undefined" && module.exports) module.exports = { createBridge };
  else {
    const resource =
      typeof GetParentResourceName === "function" ? GetParentResourceName() : "vanta_director_free";
    scope.VantaBridge = createBridge(resource);
  }
})(globalThis);
