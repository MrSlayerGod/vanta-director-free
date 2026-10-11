(() => {
  const caption = document.querySelector(".selected-sequence-label span");
  if (caption) caption.textContent = "Positions de caméra";
  const keyList = document.querySelector(".keyframe-browser summary");
  if (keyList) keyList.textContent = "Liste des positions";
  const empty = document.getElementById("emptyCamera");
  empty.querySelector("strong").textContent = "Aucune position";
  empty.querySelector("span").textContent = "Place la caméra, puis appuie sur K pour commencer.";
  const panel = document.createElement("aside");
  panel.className = "free-community";
  panel.setAttribute("aria-label", "Director Free et communauté");
  panel.innerHTML =
    '<strong>Director Free · bêta</strong><button id="freeDiscord" type="button" hidden>Rejoindre Vanta</button>';
  document.querySelector(".left-panel .pane-scroll").append(panel);
  const button = panel.querySelector("button");
  let url = "";
  const valid = (value) =>
    typeof value === "string" &&
    value.length <= 256 &&
    /^https:\/\/(?:discord\.gg\/|discord\.com\/invite\/)[\w-]+$/.test(value);
  window.addEventListener("message", (event) => {
    if (event.data?.action !== "runtimeConfig") return;
    const c = event.data.config || {};
    url = valid(c.discordUrl) ? c.discordUrl : "";
    button.hidden = !url;
  });
  button.onclick = () => {
    if (!valid(url)) return;
    try {
      if (typeof window.invokeNative === "function") {
        window.invokeNative("openUrl", url);
        return;
      }
      window.open(url, "_blank", "noopener,noreferrer");
    } catch {
      window.DirectorEditor.status.showStatus("Lien Vanta : " + url);
    }
  };
  window.VantaFree = { ready: true };
})();
