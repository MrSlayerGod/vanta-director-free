const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const root = path.resolve(__dirname, "..");
const camera = { time: 0, x: 0, y: -10, z: 4, rx: -15, ry: 0, rz: 0, fov: 50 };
const project = {
  id: "p1",
  name: "Workflow regression",
  duration: 20,
  playhead: 0,
  keyframes: [camera, { ...camera, time: 8, x: 3 }],
  cameraShots: [],
  cameraRig: { mode: "manual" },
  look: {},
  actors: [
    {
      id: 1,
      kind: "ped",
      model: "a_m_y_business_01",
      x: 0,
      y: 0,
      z: 1,
      heading: 0,
      modelAvailable: true,
      actions: [
        { id: 1, type: "move", time: 2, duration: 4, x: 5, y: 0, z: 1, gait: "walk" },
        {
          id: 2,
          type: "animation",
          time: 6,
          duration: 3,
          dict: "anim@test",
          clip: "idle",
          loop: true,
        },
      ],
    },
  ],
};
(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.DIRECTOR_BROWSER ? { executablePath: process.env.DIRECTOR_BROWSER } : {}),
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
    page.setDefaultTimeout(10000);
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
            entries: [
              { id: 1, name: "Reusable camera", kind: "camera", available: true, references: [] },
            ],
            preferences: { language: "en", workspace: false },
          }),
        };
      };
    });
    await page.goto(pathToFileURL(path.join(root, "web/index.html")).href);
    await page.waitForFunction(() => !document.documentElement.classList.contains("nui-booting"));
    const send = (data) =>
      page.evaluate((data) => window.dispatchEvent(new MessageEvent("message", { data })), data);
    await send({ action: "open" });
    await send({
      action: "preferences",
      preferences: { language: "en", workspace: false, snap: true },
    });
    await send({ action: "project", project });
    await send({
      action: "library",
      activeId: "p1",
      projects: [{ id: "p1", name: project.name, duration: 20, actors: 1, shots: 2 }],
      limit: 100,
    });
    await send({ action: "camera", camera });
    await page.evaluate(() => window.DirectorEditor.tabs.selectSceneTab(true));
    const clip = page.locator('.timeline-action[data-action-id="1"]');
    const lane = await page.locator("#keyframeLane").boundingBox();
    const initial = await clip.boundingBox();
    // Clicking off-centre then moving two seconds must retain the grab offset.
    await page.keyboard.down("Alt");
    await page.mouse.move(initial.x + initial.width * 0.7, initial.y + initial.height / 2);
    await page.mouse.down();
    await page.mouse.move(
      initial.x + initial.width * 0.7 + lane.width * 0.1,
      initial.y + initial.height / 2,
      { steps: 6 },
    );
    await page.mouse.up();
    await page.keyboard.up("Alt");
    await page.waitForFunction(() => calls.some((c) => c.name === "editActionTiming"));
    let timing = await page.evaluate(
      () => calls.filter((c) => c.name === "editActionTiming").at(-1).data,
    );
    assert(Math.abs(timing.time - 4) < 0.05, "Dragging must preserve the cursor offset");
    await send({ action: "project", project });
    const end = await clip.locator(".clip-handle.end").boundingBox();
    await page.keyboard.down("Alt");
    await page.mouse.move(end.x + end.width / 2, end.y + end.height / 2);
    await page.mouse.down();
    await page.mouse.move(end.x + end.width / 2 + lane.width * 0.05, end.y + end.height / 2, {
      steps: 6,
    });
    await page.mouse.up();
    await page.keyboard.up("Alt");
    timing = await page.evaluate(
      () => calls.filter((c) => c.name === "editActionTiming").at(-1).data,
    );
    assert(
      Math.abs(timing.duration - 5) < 0.05 && timing.time === 2,
      "Resizing must keep the start fixed",
    );
    // Escape cancels a draft drag and restores the original visual width.
    await send({ action: "project", project });
    const count = await page.evaluate(
      () => calls.filter((c) => c.name === "editActionTiming").length,
    );
    const cancel = await clip.boundingBox();
    await page.mouse.move(cancel.x + 20, cancel.y + 8);
    await page.mouse.down();
    await page.mouse.move(cancel.x + 100, cancel.y + 8);
    await page.keyboard.press("Escape");
    await page.mouse.up();
    assert.equal(
      await page.evaluate(() => calls.filter((c) => c.name === "editActionTiming").length),
      count,
    );
    assert.equal(await page.evaluate(() => DirectorEditor.state.timelineDrag), null);
    // Snapping follows neighbouring clip edges; Alt permits sub-grid placement.
    for (const bypass of [false, true]) {
      await send({ action: "project", project });
      const bounds = await clip.boundingBox();
      if (bypass) await page.keyboard.down("Alt");
      await page.mouse.move(bounds.x + 20, bounds.y + 8);
      await page.mouse.down();
      await page.mouse.move(bounds.x + 20 + lane.width * (3.94 / 20), bounds.y + 8, { steps: 5 });
      await page.mouse.up();
      if (bypass) await page.keyboard.up("Alt");
      const at = await page.evaluate(
        () => calls.filter((c) => c.name === "editActionTiming").at(-1).data.time,
      );
      assert(
        Math.abs(at - (bypass ? 5.94 : 6)) < 0.025,
        JSON.stringify({ bypass, at, width: lane.width }),
      );
    }
    await send({ action: "project", project });
    // Zoom is anchored to the cursor rather than resetting the scroll position.
    const viewport = await page.locator("#timelineViewport").boundingBox();
    const pointer = viewport.x + viewport.width * 0.6;
    const before = await page.locator("#keyframeLane").boundingBox();
    const anchor = (pointer - before.x) / before.width;
    await page.mouse.move(pointer, viewport.y + 40);
    await page.keyboard.down("Control");
    await page.mouse.wheel(0, -120);
    await page.keyboard.up("Control");
    const after = await page.locator("#keyframeLane").boundingBox();
    assert(Math.abs((pointer - after.x) / after.width - anchor) < 0.01);
    await page.locator("#timelineFit").click();
    assert.equal(await page.locator("#timelineZoom").inputValue(), "1");
    // Existing inspector, richer action steps, no layout replacement.
    assert((await page.locator(".action-step").count()) === 2);
    await page.locator(".action-step summary").first().click();
    assert(
      await page.getByRole("button", { name: "Next step at end", exact: true }).first().isVisible(),
    );
    await page.locator("#projectLibraryButton").click();
    await send({
      action: "recoveryState",
      draft: { revision: 42, name: "Unsaved scene", projectId: "p1" },
    });
    assert(await page.locator(".recovery-banner").isVisible());
    await page.getByRole("button", { name: "Restore as new project", exact: true }).click();
    await page.locator("#libraryContinueButton").click();
    await page.waitForFunction(() =>
      calls.some(
        (c) =>
          c.name === "manageRecovery" && c.data.operation === "restore" && c.data.revision === 42,
      ),
    );
    await send({ action: "recoveryState", draft: false });
    assert(await page.locator(".recovery-banner").isHidden());
    await page.locator("#personalPresetOpen").click();
    assert(await page.locator("#personalPresetDialog").isVisible());
    await page.locator("#personalPresetName").fill("Arrival camera");
    await page.locator("#personalPresetSave").click();
    await page.waitForFunction(() =>
      calls.some((c) => c.name === "savePreset" && c.data.name === "Arrival camera"),
    );
    await page.locator("#personalPresetApply").click();
    await page.waitForFunction(() => calls.some((c) => c.name === "applyPreset"));
    assert(await page.locator("#personalPresetDialog").isHidden());
    await page.evaluate(() => DirectorEditor.presets.open());
    await page.keyboard.press("Escape");
    assert(await page.locator("#personalPresetDialog").isHidden());
    assert(
      !(await page.evaluate(() => calls.some((c) => c.name === "close"))),
      "Escape from preset dialog must not close Director",
    );
    await page.locator("#projectLibraryButton").click();
    await page.locator(".starter-scenes summary").click();
    await page.locator('[data-template-kind="dialogue"]').click();
    await page.locator("#libraryContinueButton").click();
    await page.waitForFunction(() =>
      calls.some((c) => c.name === "createTemplate" && c.data.kind === "dialogue"),
    );
    await send({
      action: "library",
      activeId: "p2",
      projects: [{ id: "p2", name: "Starter", duration: 8, actors: 2, shots: 2 }],
      limit: 100,
    });
    await send({ action: "project", project });
    await send({ action: "sessionState", role: "viewer" });
    const viewer = await clip.boundingBox();
    const oldCount = await page.evaluate(
      () => calls.filter((c) => c.name === "editActionTiming").length,
    );
    await page.mouse.move(viewer.x + 10, viewer.y + 8);
    await page.mouse.down();
    await page.mouse.move(viewer.x + 100, viewer.y + 8);
    await page.mouse.up();
    assert.equal(
      await page.evaluate(() => calls.filter((c) => c.name === "editActionTiming").length),
      oldCount,
    );
    await send({ action: "sessionState", role: "none" });
    // A draft is only advertised as protected after the server acknowledges it.
    await page.clock.install();
    await page.evaluate(() => {
      document.activeElement.blur();
      DirectorEditor.saving.resetDraft();
      DirectorEditor.saving.setSaveState(false);
    });
    const previousDrafts = await page.evaluate(
      () => calls.filter((c) => c.name === "saveDraft").length,
    );
    await page.clock.fastForward(31000);
    await page.waitForFunction(
      (previous) => calls.filter((c) => c.name === "saveDraft").length > previous,
      previousDrafts,
    );
    await send({ action: "draftResult", ok: true });
    assert.equal(await page.locator("#saveState").textContent(), "Unsaved · draft protected");
    const protectedDrafts = await page.evaluate(
      () => calls.filter((c) => c.name === "saveDraft").length,
    );
    await page.clock.fastForward(31000);
    assert.equal(
      await page.evaluate(() => calls.filter((c) => c.name === "saveDraft").length),
      protectedDrafts,
    );
    await page.evaluate(() => {
      DirectorEditor.state.previewPlaying = true;
      DirectorEditor.saving.setSaveState(false);
    });
    await page.clock.fastForward(31000);
    assert.equal(
      await page.evaluate(() => calls.filter((c) => c.name === "saveDraft").length),
      protectedDrafts,
      "Playback must pause background drafts",
    );
    await page.evaluate(() => (DirectorEditor.state.previewPlaying = false));
    fs.mkdirSync(path.join(root, "test-results"), { recursive: true });
    for (const [width, height] of [
      [1920, 1080],
      [1280, 720],
    ]) {
      await page.setViewportSize({ width, height });
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.screenshot({ path: path.join(root, `test-results/workflow-${width}.png`) });
    }
    await send({ action: "preferences", preferences: { language: "fr", workspace: false } });
    await page.evaluate(() => DirectorEditor.presets.open());
    await page.waitForFunction(
      () => document.getElementById("personalPresetTitle").textContent === "Modèles personnels",
    );
    await send({ action: "close" });
    assert(await page.locator("#personalPresetDialog").isHidden());
    assert.deepEqual(errors, []);
    console.log(
      "Workflow browser: offset drag, resize, cancel, pointer zoom, action steps, recovery, presets, starter scenes, viewer, FR and two resolutions passed (mocked NUI).",
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
