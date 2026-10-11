window.DirectorEditor.modules.staging = function defineModule(ctx) {
  ctx.staging = {};
  ctx.staging.stagingIds = function stagingIds() {
    const group = document.getElementById("stagingSelection").value;
    return group
      ? ctx.state.project.actors.filter((a) => a.group === group).map((a) => a.id)
      : ctx.state.selectedActorId
        ? [ctx.state.selectedActorId]
        : [];
  };
  return function bindEvents() {
    document.getElementById("stagingGroupApply").addEventListener("click", () =>
      ctx.transport.post("setActorGroup", {
        ids: ctx.staging.stagingIds(),
        name: document.getElementById("stagingGroupName").value,
      }),
    );

    document.getElementById("stagingDuplicate").addEventListener("click", () =>
      ctx.transport.post("duplicateActors", {
        ids: ctx.staging.stagingIds(),
        x: Number(document.getElementById("stagingOffsetX").value),
        y: Number(document.getElementById("stagingOffsetY").value),
        z: 0,
      }),
    );

    document.getElementById("recordedGestureAdd").addEventListener("click", () =>
      ctx.transport.post("addRecordedGesture", {
        id: ctx.state.selectedActorId,
        gesture: document.getElementById("recordedGesture").value,
        duration: Number(document.getElementById("recordedGestureSeconds").value),
      }),
    );

    document.getElementById("recordingTrim").addEventListener("click", () =>
      ctx.transport.post("trimRecording", {
        id: ctx.state.selectedActorId,
        first: Number(document.getElementById("recordingTrimFirst").value),
        last: Number(document.getElementById("recordingTrimLast").value),
      }),
    );
  };
};
