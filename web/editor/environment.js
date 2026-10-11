window.DirectorEditor.modules.environment = function defineModule(ctx) {
  ctx.environment = {};
  ctx.environment.renderLook = function renderLook() {
    const look = ctx.state.project.look || {};
    for (const [id, value] of Object.entries({
      lookWeather: look.weather || "SERVER",
      lookHour: look.hour ?? -1,
      lookMinute: look.minute ?? 0,
      lookNear: look.near ?? 2,
      lookFar: look.far ?? 30,
      lookStrength: look.strength ?? 0.5,
    })) {
      const element = document.getElementById(id);
      if (document.activeElement !== element) element.value = value;
    }
    document.getElementById("lookDof").checked = look.dof === true;
    document.getElementById("lookMinute").disabled = Number(look.hour ?? -1) < 0;
    document.getElementById("lookFocusControls").classList.toggle("is-hidden", look.dof !== true);
    document.getElementById("lookNearValue").textContent = `${Number(look.near ?? 2).toFixed(1)} m`;
    document.getElementById("lookFarValue").textContent = `${Number(look.far ?? 30).toFixed(0)} m`;
    document.getElementById("lookStrengthValue").textContent =
      `${Math.round(Number(look.strength ?? 0.5) * 100)}%`;
  };
  return function bindEvents() {
    for (let hour = 0; hour < 24; hour++) {
      const option = document.createElement("option");
      option.value = String(hour);
      option.textContent = `${String(hour).padStart(2, "0")}:00`;
      ctx.elements.lookHour.appendChild(option);
    }

    for (const [id, field, event] of [
      ["lookWeather", "weather", "change"],
      ["lookHour", "hour", "change"],
      ["lookMinute", "minute", "change"],
      ["lookDof", "dof", "change"],
      ["lookNear", "near", "change"],
      ["lookFar", "far", "change"],
      ["lookStrength", "strength", "change"],
    ]) {
      document.getElementById(id).addEventListener(event, async (e) => {
        const value =
          field === "dof"
            ? e.target.checked
            : field === "weather"
              ? e.target.value
              : Number(e.target.value);
        const result = await ctx.transport.post("setSceneLook", { field, value });
        if (!result.ok) ctx.status.showStatus(result.message || "Could not update scene look.");
      });
    }
  };
};
