const { chromium } = require("playwright");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "..");
const actor = {
  id: 1,
  kind: "ped",
  model: "a_m_y_business_01",
  modelAvailable: true,
  x: 0,
  y: 0,
  z: 1,
  heading: 0,
  actions: [],
};
const project = {
  name: "Community QA",
  duration: 90,
  playhead: 0,
  keyframes: [],
  cameraShots: [],
  actors: [actor],
  look: { weather: "FOGGY", hour: 22, minute: 0 },
  cameraRig: { mode: "manual" },
  playback: { first: 0, last: 90, loop: false },
};

(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.DIRECTOR_BROWSER ? { executablePath: process.env.DIRECTOR_BROWSER } : {}),
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.addInitScript(() => {
      window.GetParentResourceName = () => "vanta_director_free";
      window.calls = [];
      window.fetch = async (url, options) => {
        const name = String(url).split("/").pop();
        const data = JSON.parse(options?.body || "{}");
        window.calls.push({ name, data });
        return {
          json: async () => ({
            ok: true,
            routeToken: 1,
            points: [],
            preferences: { language: "en", workspace: false, layout: "azerty" },
          }),
        };
      };
    });
    await page.goto(pathToFileURL(path.join(root, "web/index.html")).href);
    await page.waitForFunction(() => !document.documentElement.classList.contains("nui-booting"));
    const send = (data) =>
      page.evaluate((data) => window.dispatchEvent(new MessageEvent("message", { data })), data);
    await send({ action: "open" });
    await send({ action: "preferences", preferences: { language: "en", workspace: false } });
    await send({ action: "project", project });
    await send({ action: "actorScreen", selectedId: 1, positions: [] });
    await send({
      action: "runtimeConfig",
      config: {
        maximumDuration: 600,
        minimumDuration: 1,
        recordingMaximumSeconds: 120,
        projectFileLimit: 1048576,
        collaborationEnabled: true,
      },
    });
    // Exercise cross-module state and transport before testing modal features.
    await page.locator("#projectName").fill("Refactor regression");
    await page.locator("#saveButton").click();
    await page.waitForFunction(() => calls.some((call) => call.name === "saveProject"));
    assert(await page.locator("#saveButton").isDisabled());
    await send({ action: "saveResult", ok: true });
    await send({ action: "saveState", saved: true });
    assert(await page.locator("#saveButton").isEnabled());
    await page.locator("#duration").fill("120");
    await page.locator("#duration").dispatchEvent("change");
    await page.waitForFunction(() =>
      calls.some((call) => call.name === "setDuration" && call.data.duration === 120),
    );
    await page.locator("#addKeyframeButton").dispatchEvent("click");
    await page.waitForFunction(() => calls.some((call) => call.name === "addKeyframe"));
    await page.locator("#previewButton").click();
    await page.waitForFunction(() => calls.some((call) => call.name === "preview"));
    await send({ action: "motionRecordStarted" });
    assert(await page.locator("#director").isHidden());
    assert(await page.locator("#motionRecordOverlay").isVisible());
    await send({ action: "motionRecordFinished", message: "Recorded" });
    assert(await page.locator("#director").isVisible());
    assert(await page.locator("#motionRecordOverlay").isHidden());
    await page.evaluate(() => window.DirectorEditor.tabs.selectSceneTab(true));
    for (const selector of [
      "#shotLibrary",
      "#cameraSequencePanel",
      "#motionRecordPanel",
      "#stagingTools",
      "#collaborationPanel",
      ".route-open",
      ".accessory-panel",
      ".vehicle-interaction-panel",
    ]) {
      assert(await page.locator(selector).count(), "Missing feature control: " + selector);
      assert.notEqual(
        await page
          .locator(selector)
          .first()
          .evaluate((el) => getComputedStyle(el).display),
        "none",
        "Edition-hidden control: " + selector,
      );
    }
    await page.evaluate(() =>
      window.VantaRouteEditor.open(window.DirectorEditor.state.project.actors[0]),
    );
    assert(await page.locator("#routeEditor").isVisible());
    await send({ action: "routeClosed", routeToken: 1 });
    assert(await page.locator("#routeEditor").isHidden());
    await send({ action: "animationCatalog", actorId: 1 });
    assert.equal(await page.locator(".animation-result").count(), 100);
    await page.waitForFunction(
      () =>
        document.getElementById("animationLoop").textContent === "Loop until the end of the clip",
    );
    await page.locator("#animationSearch").fill("coffee");
    assert((await page.locator(".animation-result").count()) > 0);
    await page.locator(".animation-result").first().click();
    await page.locator("#animationAddButton").click();
    await page.waitForFunction(() => calls.some((call) => call.name === "addAction"));
    await send({ action: "animationCatalog", actorId: 1 });
    await page.locator("#animationSearch").fill("");
    fs.mkdirSync(path.join(root, "test-results"), { recursive: true });
    for (const [width, height] of [
      [1280, 720],
      [1920, 1080],
    ]) {
      await page.setViewportSize({ width, height });
      assert(await page.locator("#animationAddButton").isVisible());
      await page.locator("#animationAddButton").scrollIntoViewIfNeeded();
      const buttonBounds = await page.locator("#animationAddButton").boundingBox();
      const modalBounds = await page.locator(".animation-modal").boundingBox();
      assert(
        buttonBounds.y + buttonBounds.height <= modalBounds.y + modalBounds.height,
        "Animation insert button is clipped",
      );
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.screenshot({ path: path.join(root, `test-results/library-${width}.png`) });
    }
    await send({ action: "preferences", preferences: { language: "fr", workspace: false } });
    await page.locator("#animationSearch").fill("carton");
    assert.equal(await page.locator(".animation-result").count(), 1);
    await send({ action: "close" });
    assert(await page.locator("#director").isHidden());
    assert.deepEqual(errors, []);
    console.log(
      "Browser: boot, restored controls/routes, 100 animations, FR/EN search, insertion, two sizes and close passed (mocked NUI).",
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
