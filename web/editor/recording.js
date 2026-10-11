window.DirectorEditor.modules.recording = function defineModule(ctx) {
  ctx.recording = {};

  return function bindEvents() {
    document.getElementById("motionRecordStart").addEventListener("click", async () => {
      const result = await ctx.transport.post("startMotionRecording", {
        kind: document.getElementById("motionRecordKind").value,
        seconds: Number(document.getElementById("motionRecordSeconds").value),
        model: document.getElementById("motionRecordModel").value.trim(),
        occupants: document.getElementById("motionRecordOccupants").checked,
        captureAim: document.getElementById("motionRecordAim").checked,
      });
      if (!result.ok)
        ctx.status.showStatus(result.message || "Could not start movement recording.");
    });

    document
      .getElementById("motionRecordKind")
      .addEventListener("change", ctx.state.recordingSourceFields);
  };
};
