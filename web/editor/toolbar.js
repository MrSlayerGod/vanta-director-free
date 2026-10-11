window.DirectorEditor.modules.toolbar = function defineModule(ctx) {
  ctx.toolbar = {};

  return function bindEvents() {
    document.getElementById("closeButton").addEventListener("click", ctx.lifecycle.requestClose);

    document.getElementById("controlsButton").addEventListener("click", () => {
      const panel = document.getElementById("controlsPanel");
      if (panel.classList.contains("is-hidden")) panel.classList.remove("is-hidden");
      else panel.classList.add("is-hidden");
    });

    document.getElementById("updateFrameButton").addEventListener("click", async () => {
      const frame = ctx.camera.selectedFrame();
      if (!frame) return;
      const result = await ctx.transport.post("addKeyframe", { time: frame.time });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not update this shot.");
    });

    document.getElementById("deleteFrameButton").addEventListener("click", async () => {
      const frame = ctx.camera.selectedFrame();
      if (!frame) return;
      const index = ctx.state.project.keyframes.indexOf(frame);
      ctx.state.selectedFrameTime = null;
      const result = await ctx.transport.post("deleteKeyframe", { index: index + 1 });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not delete this shot.");
    });

    document.getElementById("shotNameInput").addEventListener("change", async (event) => {
      const frame = ctx.camera.selectedFrame();
      if (!frame) return;
      const result = await ctx.transport.post("setKeyframeName", {
        index: ctx.state.project.keyframes.indexOf(frame) + 1,
        name: event.target.value.trim(),
      });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not rename this shot.");
    });

    document.getElementById("addKeyframeButton").addEventListener("click", async () => {
      const result = await ctx.transport.post("addKeyframe", { time: ctx.state.project.playhead });
      if (!result.ok) ctx.status.showStatus(result.message || "Could not add keyframe.");
    });

    document.getElementById("previewButton").addEventListener("click", async () => {
      if (ctx.state.previewPlaying) {
        await ctx.transport.post("stopPreview");
        return;
      }
      const result = await ctx.transport.post("preview");
      if (!result.ok) ctx.status.showStatus(result.message || "Add a keyframe before previewing.");
    });

    document
      .getElementById("stopButton")
      .addEventListener("click", () => ctx.transport.post("stopPreview"));

    document.getElementById("captureButton").addEventListener("click", async () => {
      const result = await ctx.transport.post("capture");
      if (!result.ok) ctx.status.showStatus(result.message || "Could not start clean take.");
    });
  };
};
