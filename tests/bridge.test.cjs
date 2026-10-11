const assert = require("node:assert/strict");
const { test } = require("node:test");
const { createBridge } = require("../web/nui-bridge.js");

test("NUI transport preserves rejection details and encodes JSON", async () => {
  const bridge = createBridge("vanta_director_free", async (url, request) => {
    assert.equal(url, "https://vanta_director_free/commitRoute");
    assert.deepEqual(JSON.parse(request.body), { routeToken: 7 });
    return { json: async () => ({ ok: false, message: "Scene changed." }) };
  });
  assert.deepEqual(await bridge.request("commitRoute", { routeToken: 7 }), {
    ok: false,
    message: "Scene changed.",
  });
});

test("NUI transport handles malformed responses and network failures", async () => {
  for (const response of [null, [], {}, { ok: "yes" }]) {
    const bridge = createBridge("test", async () => ({ json: async () => response }));
    assert.equal((await bridge.request("open")).ok, false);
  }
  const bridge = createBridge("test", async () => {
    throw new Error("offline");
  });
  assert.equal((await bridge.request("open")).ok, false);
});

test("route close cancels its pending NUI request", async () => {
  const controller = new AbortController();
  const bridge = createBridge(
    "test",
    async (_, options) =>
      new Promise((_, reject) => {
        options.signal.addEventListener("abort", () => reject(new Error("cancelled")), {
          once: true,
        });
      }),
  );
  const request = bridge.request("moveRoutePoint", {}, { signal: controller.signal });
  controller.abort();
  assert.equal((await request).ok, false);
});

test("unanswered game callbacks time out", async () => {
  const bridge = createBridge(
    "test",
    async (_, options) =>
      new Promise((_, reject) => {
        options.signal.addEventListener("abort", () => reject(new Error("timeout")), {
          once: true,
        });
      }),
    10,
  );
  assert.equal((await bridge.request("beginRoute")).ok, false);
});
