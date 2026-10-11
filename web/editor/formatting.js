window.DirectorEditor.modules.formatting = function defineModule(ctx) {
  ctx.formatting = {};
  ctx.formatting.formatTime = function formatTime(value) {
    const time = Math.max(0, Number(value) || 0);
    const minutes = Math.floor(time / 60);
    const seconds = (time % 60).toFixed(1).padStart(4, "0");
    return `${String(minutes).padStart(2, "0")}:${seconds}`;
  };

  ctx.formatting.actorLabel = function actorLabel(kind, short = false) {
    if (kind === "vehicle") return short ? "CAR" : "Vehicle";
    if (kind === "prop") return short ? "OBJ" : "Object";
    return short ? "PED" : "Ped";
  };

  ctx.formatting.actionLabel = function actionLabel(action) {
    if (action.type === "move" && action.points)
      return `Route \u00b7 ${action.points.length} points \u00b7 ${Number(action.duration).toFixed(1)} sec`;
    if (action.type === "move")
      return `${action.gait && action.gait !== "auto" ? action.gait.toUpperCase() : "Move"} ${Number(action.duration).toFixed(1)}s`;
    if (action.type === "lookAt")
      return `Look at ${action.targetId ? `subject ${action.targetId}` : "point"} · ${Number(action.duration).toFixed(1)}s`;
    if (action.type === "enterVehicle" || action.type === "exitVehicle")
      return `${action.type === "enterVehicle" ? "Enter" : "Exit"} vehicle ${action.vehicleId} · ${action.seat === -1 ? "Driver" : "Passenger " + (action.seat + 1)} · ${Number(action.duration).toFixed(1)}s`;
    if (action.type === "recording")
      return "Recorded movement · " + Number(action.duration).toFixed(1) + " sec";
    if (action.type === "visibility") return action.visible ? "Show object" : "Hide object";
    if (action.type === "engine") return action.enabled ? "Engine on" : "Engine off";
    if (action.type === "lights") return action.enabled ? "Lights on" : "Lights off";
    if (action.type === "door") {
      const door =
        ["Driver front", "Driver rear", "Passenger front", "Passenger rear", "Hood", "Trunk"][
          action.door
        ] || "Door";
      return `${door} ${action.enabled ? "open" : "closed"}`;
    }
    return `Animation ${action.clip}${action.duration ? " · " + Number(action.duration).toFixed(1) + "s" : " · until replaced"}`;
  };
  return function bindEvents() {};
};
