const resource =
  typeof GetParentResourceName === "function"
    ? GetParentResourceName()
    : "vanta_director_free";
const root = document.getElementById("director");
const keyframeList = document.getElementById("keyframeList");
const markers = document.getElementById("markers");
const trackLane = document.getElementById("trackLane");
const actorTracks = document.getElementById("actorTracks");
const scrubber = document.getElementById("timelineScrubber");
const durationInput = document.getElementById("duration");
const projectNameInput = document.getElementById("projectName");
const statusMessage = document.getElementById("statusMessage");
const toast = document.getElementById("toast");
const exitOverlay = document.getElementById("exitOverlay");
let project = {
  name: "Untitled Project",
  duration: 20,
  playhead: 0,
  keyframes: [],
  actors: [],
  look: {},
};
let camera = null;
let keyState = {};
let toastTimeout = null;
let nameTimeout = null;
let keySequence = 0;
let previewPlaying = false;
let playheadAnchorTime = 0;
let playheadAnchorClock = 0;
let animationScheduled = false;
let scrubbing = false;
let looking = false;
let lookDeltaX = 0;
let lookDeltaY = 0;
let lookScheduled = false;
let lastMouseX = null;
let lastMouseY = null;
let seekSequence = 0;
let timelineDrag = null;
let lastDragSeekAt = 0;
let bridgeReady = false;
let leftHeld = false;
let actorDragging = false;
let actorDragScheduled = false;
let actorDragSequence = 0;
let actorDragPointer = null;
let selectedActorId = null;
let selectedFrameTime = null;
let sceneTabActive = false;
let lookTabActive = false;
let saveDirty = false;
let savePending = false;
let savePendingTimeout = null;
let libraryState = { activeId: null, projects: [], limit: Infinity };
let libraryBusy = false;
let libraryWaitTimer = null;
let pendingLibraryConfirm = null;
const actorPinElements = new Map();
const mutatingCalls = new Set([
  "addRecordedGesture",
  "pasteTimeline",
  "saveLocation",
  "deleteLocation",
  "duplicateActors",
  "setActorGroup",
  "trimRecording",
  "createCameraShot",
  "updateCameraShot",
  "deleteCameraShot",
  "duplicateCameraShot",
  "applyCameraPreset",
  "addKeyframe",
  "deleteKeyframe",
  "moveKeyframe",
  "setDuration",
  "setProjectName",
  "addActor",
  "placeBrowserModel",
  "deleteActor",
  "setActorTransform",
  "endActorDrag",
  "addAction",
  "deleteAction",
  "moveAction",
  "setKeyframeFov",
  "setKeyframeName",
  "setSceneLook",
  "setCameraRig",
  "commitRoute",
  "undo",
  "redo",
]);
// GTA dictionary/clip identifiers verified against the pinned dumps listed in SOURCES.md.
const animationCatalog = [
  {
    id: "salute",
    name: "Salut militaire",
    category: "Gestes",
    description: "Un salut pour une présentation ou une rencontre.",
    dict: "anim@mp_player_intuppersalute",
    clip: "idle_a",
    english: "Salute",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Salute",
  },
  {
    id: "point",
    name: "Montrer devant soi",
    category: "Gestes",
    description: "Désigner un lieu ou un personnage.",
    dict: "gestures@f@standing@casual",
    clip: "gesture_point",
    english: "Point ahead",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Point ahead",
  },
  {
    id: "point_right",
    name: "Montrer à droite",
    category: "Gestes",
    description: "Attirer le regard sur le côté droit.",
    dict: "mp_gun_shop_tut",
    clip: "indicate_right",
    english: "Point right",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Point right",
  },
  {
    id: "surrender",
    name: "Mains en l’air",
    category: "Gestes",
    description: "Une pose de reddition pour une scène tendue.",
    dict: "random@arrests@busted",
    clip: "idle_a",
    english: "Hands up",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Hands up",
  },
  {
    id: "wave",
    name: "Faire signe",
    category: "Gestes",
    description: "Saluer quelqu’un à distance.",
    dict: "friends@frj@ig_1",
    clip: "wave_a",
    english: "Wave",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Wave ",
  },
  {
    id: "wave2",
    name: "Salut de la main",
    category: "Gestes",
    description: "Une variante de salut.",
    dict: "anim@mp_player_intcelebrationfemale@wave",
    clip: "wave",
    english: "Wave 2",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Wave 2 ",
  },
  {
    id: "wave4",
    name: "Salut bref",
    category: "Gestes",
    description: "Un signe de la main joué une fois.",
    dict: "random@mugging5",
    clip: "001445_01_gangintimidation_1_female_idle_b",
    english: "Wave 4",
    loop: false,
    props: [],
    placement: "",
    caution: "",
    tags: "Wave 4 ",
  },
  {
    id: "thumbsup",
    name: "Pouce levé",
    category: "Gestes",
    description: "Exprimer son accord.",
    dict: "anim@mp_player_intupperthumbs_up",
    clip: "idle_a",
    english: "Thumbs Up",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Thumbs Up ",
  },
  {
    id: "hangout",
    name: "Attendre dans la rue",
    category: "Vie quotidienne",
    description: "Une attente détendue pour donner vie au décor.",
    dict: "amb@world_human_hang_out_street@male_b@idle_a",
    clip: "idle_b",
    english: "Hang out",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Hang out",
  },
  {
    id: "eat",
    name: "Manger, geste bref",
    category: "Vie quotidienne",
    description: "Porter la main à la bouche.",
    dict: "mp_player_inteat@burger",
    clip: "mp_player_int_eat_burger",
    english: "Eat",
    loop: false,
    props: [],
    placement: "Placer un aliment si nécessaire pour le plan.",
    caution: "",
    tags: "Eat ",
  },
  {
    id: "warmth",
    name: "Se réchauffer",
    category: "Vie quotidienne",
    description: "Tendre les mains vers une source de chaleur.",
    dict: "amb@world_human_stand_fire@male@idle_a",
    clip: "idle_a",
    english: "Warmth",
    loop: true,
    props: [],
    placement: "Placer une source de chaleur devant le sujet.",
    caution: "",
    tags: "Warmth ",
  },
  {
    id: "wait",
    name: "Attendre calmement",
    category: "Vie quotidienne",
    description: "Une attente simple pour un personnage secondaire.",
    dict: "random@shop_tattoo",
    clip: "_idle_a",
    english: "Wait",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Wait ",
  },
  {
    id: "wait2",
    name: "Attendre, mains devant",
    category: "Vie quotidienne",
    description: "Une autre posture d’attente.",
    dict: "missbigscore2aig_3",
    clip: "wait_for_van_c",
    english: "Wait 2",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Wait 2 ",
  },
  {
    id: "medic",
    name: "Examiner une personne",
    category: "Métiers",
    description: "Un geste de soin auprès d’une personne au sol.",
    dict: "amb@medic@standing@tendtodead@base",
    clip: "base",
    english: "Tend to someone",
    loop: true,
    props: [],
    placement: "Placer une personne allongée devant le sujet.",
    caution: "",
    tags: "Tend to someone",
  },
  {
    id: "mechanic",
    name: "Réparation de véhicule",
    category: "Métiers",
    description: "Une posture de mécanicien près d’un véhicule.",
    dict: "amb@world_human_vehicle_mechanic@male@base",
    clip: "base",
    english: "Work on vehicle",
    loop: true,
    props: [],
    placement: "Placer le sujet face à la zone à réparer.",
    caution: "",
    tags: "Work on vehicle",
  },
  {
    id: "mechanic3",
    name: "Travail à l’établi",
    category: "Métiers",
    description: "Une gestuelle de réparation.",
    dict: "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
    clip: "machinic_loop_mechandplayer",
    english: "Mechanic 3",
    loop: true,
    props: [],
    placement: "Aligner le sujet avec un établi ou une zone de travail.",
    caution: "",
    tags: "Mechanic 3 ",
  },
  {
    id: "cop2",
    name: "Surveillance, policier",
    category: "Métiers",
    description: "Une posture de surveillance.",
    dict: "anim@amb@nightclub@peds@",
    clip: "rcmme_amanda1_stand_loop_cop",
    english: "Cop 2",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Cop 2 ",
  },
  {
    id: "cpr",
    name: "Massage cardiaque",
    category: "Métiers",
    description: "Un geste de secours auprès d’une victime.",
    dict: "mini@cpr@char_a@cpr_str",
    clip: "cpr_pumpchest",
    english: "CPR",
    loop: true,
    props: [],
    placement:
      "Placer une personne allongée devant le sujet ; pas de synchronisation automatique.",
    caution: "",
    tags: "CPR ",
  },
  {
    id: "pushups",
    name: "Faire des pompes",
    category: "Action",
    description: "Un exercice au sol.",
    dict: "amb@world_human_push_ups@male@idle_a",
    clip: "idle_d",
    english: "Push-ups",
    loop: true,
    props: [],
    placement: "Prévoir de la place devant le sujet.",
    caution: "",
    tags: "Push-ups",
  },
  {
    id: "pickup",
    name: "Ramasser au sol",
    category: "Action",
    description: "Se baisser pour récupérer quelque chose.",
    dict: "random@domestic",
    clip: "pickup_low",
    english: "Pickup",
    loop: false,
    props: [],
    placement:
      "Placer l’objet près du sujet ; rien n’est ramassé automatiquement.",
    caution:
      "Cette pose peut décaler le corps : vérifier le placement en prévisualisation.",
    tags: "Pickup ",
  },
  {
    id: "refuse",
    name: "Refuser",
    category: "Dialogue et réactions",
    description: "Exprimer son désaccord pendant une discussion.",
    dict: "anim@heists@ornate_bank@chat_manager",
    clip: "fail",
    english: "Refuse",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Refuse",
  },
  {
    id: "lean_wall",
    name: "Appui contre un mur",
    category: "Positions et repos",
    description: "Une pose debout avec un pied relevé.",
    dict: "amb@world_human_leaning@male@wall@back@foot_up@idle_a",
    clip: "idle_a",
    english: "Lean on wall",
    loop: true,
    props: [],
    placement: "Aligner le dos contre un mur.",
    caution: "",
    tags: "Lean on wall",
  },
  {
    id: "lean_hands",
    name: "Appui, mains réunies",
    category: "Positions et repos",
    description: "Une attente calme contre un mur.",
    dict: "amb@world_human_leaning@male@wall@back@hands_together@idle_b",
    clip: "idle_d",
    english: "Lean, hands together",
    loop: true,
    props: [],
    placement: "Aligner le dos contre un mur.",
    caution: "",
    tags: "Lean, hands together",
  },
  {
    id: "sit_ground",
    name: "Assis au sol",
    category: "Positions et repos",
    description: "Une pause assise sur le sol.",
    dict: "amb@world_human_picnic@male@idle_a",
    clip: "idle_a",
    english: "Sit on ground",
    loop: true,
    props: [],
    placement: "Ajuster la hauteur au niveau du sol.",
    caution: "",
    tags: "Sit on ground",
  },
  {
    id: "sit_relaxed",
    name: "Assis, détendu",
    category: "Positions et repos",
    description: "Une pose assise relâchée.",
    dict: "rcm_barry3",
    clip: "barry_3_sit_loop",
    english: "Sit, relaxed",
    loop: true,
    props: [],
    placement: "Ajuster la hauteur au niveau du sol.",
    caution: "",
    tags: "Sit, relaxed",
  },
  {
    id: "breath",
    name: "Reprendre son souffle",
    category: "Horreur et tension",
    description: "Une respiration difficile après une fuite.",
    dict: "re@construction",
    clip: "out_of_breath",
    english: "Out of breath",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Out of breath",
  },
  {
    id: "scared",
    name: "Panique debout",
    category: "Horreur et tension",
    description: "Une réaction de détresse pour une découverte inquiétante.",
    dict: "random@domestic",
    clip: "f_distressed_loop",
    english: "Distressed",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Distressed",
  },
  {
    id: "shot",
    name: "Blessé au sol",
    category: "Horreur et tension",
    description: "Une pose de blessure pour une scène dramatique.",
    dict: "random@dealgonewrong",
    clip: "idle_a",
    english: "Wounded",
    loop: true,
    props: [],
    placement: "Ajuster la pose au sol.",
    caution: "",
    tags: "Wounded",
  },
  {
    id: "sleep",
    name: "Dormir",
    category: "Positions et repos",
    description: "Une pose couchée pour une scène calme ou inquiétante.",
    dict: "timetable@tracy@sleep@",
    clip: "idle_c",
    english: "Sleep",
    loop: true,
    props: [],
    placement: "Aligner la pose avec le sol ou un lit.",
    caution: "",
    tags: "Sleep",
  },
  {
    id: "scared2",
    name: "Peur à genoux",
    category: "Horreur et tension",
    description: "Se recroqueviller face à une menace.",
    dict: "random@homelandsecurity",
    clip: "knees_loop_girl",
    english: "Scared 2",
    loop: true,
    props: [],
    placement: "Ajuster la pose au sol.",
    caution: "",
    tags: "Scared 2 horror fear scared peur panique suspense halloween",
  },
  {
    id: "nervous",
    name: "Agitation nerveuse",
    category: "Horreur et tension",
    description: "Une attente inquiète avec de petits gestes.",
    dict: "amb@world_human_bum_standing@twitchy@idle_a",
    clip: "idle_c",
    english: "Nervous",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Nervous horror fear scared peur panique suspense halloween",
  },
  {
    id: "nervous2",
    name: "Anxiété, attente",
    category: "Horreur et tension",
    description: "Rester tendu avant un événement.",
    dict: "mp_missheist_countrybank@nervous",
    clip: "nervous_idle",
    english: "Nervous 2",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Nervous 2 horror fear scared peur panique suspense halloween",
  },
  {
    id: "nervous3",
    name: "Nervosité marquée",
    category: "Horreur et tension",
    description: "Une nervosité plus visible pour un plan rapproché.",
    dict: "rcmme_tracey1",
    clip: "nervous_loop",
    english: "Nervous 3",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Nervous 3 horror fear scared peur panique suspense halloween",
  },
  {
    id: "sitscared",
    name: "Otages, réaction",
    category: "Horreur et tension",
    description: "Une posture de victime effrayée.",
    dict: "anim@heists@ornate_bank@hostages@hit",
    clip: "hit_loop_ped_b",
    english: "Sit Scared",
    loop: true,
    props: [],
    placement: "Ajuster la pose assise au sol.",
    caution: "",
    tags: "Sit Scared horror fear scared peur panique suspense halloween",
  },
  {
    id: "sitscared2",
    name: "Peur assise, sursaut",
    category: "Horreur et tension",
    description: "Une réaction inquiète en position basse.",
    dict: "anim@heists@ornate_bank@hostages@ped_c@",
    clip: "flinch_loop",
    english: "Sit Scared 2",
    loop: true,
    props: [],
    placement: "Ajuster la pose assise au sol.",
    caution: "",
    tags: "Sit Scared 2 horror fear scared peur panique suspense halloween",
  },
  {
    id: "sitscared3",
    name: "Peur assise, protection",
    category: "Horreur et tension",
    description: "Se protéger en restant au sol.",
    dict: "anim@heists@ornate_bank@hostages@ped_e@",
    clip: "flinch_loop",
    english: "Sit Scared 3",
    loop: true,
    props: [],
    placement: "Ajuster la pose assise au sol.",
    caution: "",
    tags: "Sit Scared 3 horror fear scared peur panique suspense halloween",
  },
  {
    id: "peek",
    name: "Guetter sur le côté",
    category: "Horreur et tension",
    description: "Observer prudemment derrière un obstacle.",
    dict: "random@paparazzi@peek",
    clip: "left_peek_a",
    english: "Peek",
    loop: true,
    props: [],
    placement: "Aligner le sujet près du bord d’un mur ou d’un arbre.",
    caution: "",
    tags: "Peek horror fear scared peur panique suspense halloween",
  },
  {
    id: "cough",
    name: "Tousser",
    category: "Horreur et tension",
    description: "Une toux pour une ambiance de fatigue ou de malaise.",
    dict: "timetable@gardener@smoking_joint",
    clip: "idle_cough",
    english: "Cough",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Cough horror fear scared peur panique suspense halloween",
  },
  {
    id: "stunned",
    name: "Choc, tremblements",
    category: "Horreur et tension",
    description: "Une réaction de choc pour une scène dramatique.",
    dict: "stungun@standing",
    clip: "damage",
    english: "Stunned",
    loop: true,
    props: [],
    placement: "",
    caution: "",
    tags: "Stunned horror fear scared peur panique suspense halloween",
  },
  {
    id: "passout",
    name: "Inconscient au sol",
    category: "Horreur et tension",
    description: "Un personnage immobile après un malaise.",
    dict: "missarmenian2",
    clip: "drunk_loop",
    english: "Passout",
    loop: true,
    props: [],
    placement: "Ajuster la pose au sol.",
    caution: "",
    tags: "Passout horror fear scared peur panique suspense halloween",
  },
];
let animationActorId = null;
let animationSelectedId = animationCatalog[0].id;
let animationCategory = "All";
let animationPreviewActive = false;
let animationPreviewSequence = 0;
let animationAddPending = false;

const animationStorageKey = resource + ":animation-library:v1";
const animationIds = new Set(animationCatalog.map((item) => item.id));
const animationCategories = [
  "All",
  "Favorites",
  "Recent",
  ...new Set(animationCatalog.map((item) => item.category)),
];
const animationCategoryNames = {
  All: "Tout",
  Favorites: "Favoris",
  Recent: "Récents",
};
function animationIdList(value, limit) {
  return Array.isArray(value)
    ? [
        ...new Set(
          value.filter((id) => typeof id === "string" && animationIds.has(id)),
        ),
      ].slice(0, limit)
    : [];
}
function readAnimationMemory() {
  try {
    const raw = window.localStorage?.getItem(animationStorageKey);
    if (!raw) return { favorites: [], recent: [] };
    if (raw.length > 65536) throw Error("Invalid animation preferences");
    const data = JSON.parse(raw);
    if (!data || data.version !== 1) return { favorites: [], recent: [] };
    return {
      favorites: animationIdList(data.favorites, animationCatalog.length),
      recent: animationIdList(data.recent, 20),
    };
  } catch {
    return { favorites: [], recent: [] };
  }
}
const animationMemory = readAnimationMemory();
function storeAnimationMemory() {
  try {
    if (!window.localStorage) throw Error("Storage unavailable");
    window.localStorage.setItem(
      animationStorageKey,
      JSON.stringify({ version: 1, ...animationMemory }),
    );
    return true;
  } catch {
    return false;
  }
}
function recordAnimationUse(id) {
  if (!animationIds.has(id)) return;
  animationMemory.recent = [
    id,
    ...animationMemory.recent.filter((item) => item !== id),
  ].slice(0, 20);
  storeAnimationMemory();
}
function animationSearchText(text) {
  return String(text)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}
const animationSearchIndex = new Map(
  animationCatalog.map((item) => [
    item.id,
    animationSearchText(
      [
        item.name,
        item.english,
        item.category,
        item.description,
        item.tags,
        item.dict,
        item.clip,
        item.placement,
        ...item.props,
      ].join(" "),
    ),
  ]),
);
const physicalKeys = {
  KeyW: "w",
  KeyA: "a",
  KeyS: "s",
  KeyD: "d",
  KeyQ: "q",
  KeyE: "e",
  ArrowLeft: "arrowleft",
  ArrowRight: "arrowright",
  ArrowUp: "arrowup",
  ArrowDown: "arrowdown",
  KeyK: "k",
  Escape: "escape",
};
const hintIds = {
  KeyW: "forwardKeyLabel",
  KeyA: "leftKeyLabel",
  KeyQ: "lowerKeyLabel",
};

const unavailableCalls = new Set(["collaboration"]);
async function post(name, data = {}) {
  if (unavailableCalls.has(name)) {
    const message = "Cette fonction est disponible dans Director complet.";
    showStatus(message);
    return { ok: false, message };
  }
  if (!bridgeReady) return { ok: false, message: "Director is closed." };
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timeout = controller
    ? setTimeout(() => controller.abort(), 15000)
    : null;
  try {
    const response = await fetch(`https://${resource}/${name}`, {
      method: "POST",
      ...(controller ? { signal: controller.signal } : {}),
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    });
    const result = await response.json();
    if (!result.ok && result.message) showStatus(result.message);
    if (result.ok && mutatingCalls.has(name)) {
      setSaveState(false);
      window.VantaWorkflow?.invalidate();
    }
    if (
      result.ok &&
      window.VantaTutorialActive &&
      typeof window.dispatchEvent === "function"
    )
      window.dispatchEvent(
        new CustomEvent("directorAction", { detail: { name, data, result } }),
      );
    return result;
  } catch (_) {
    showStatus("Could not reach the game client.");
    return { ok: false, message: "Could not reach the game client." };
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function setSaveState(saved) {
  saveDirty = !saved;
  const label = document.getElementById("saveState");
  label.textContent = saved
    ? "Saved on server"
    : savePending
      ? "Saving on server…"
      : "Unsaved changes";
  if (saved) {
    label.classList.add("saved");
    label.classList.remove("dirty");
  } else {
    label.classList.add("dirty");
    label.classList.remove("saved");
  }
  window.VantaWorkflow?.render();
}

function setSavePending(pending) {
  savePending = pending;
  clearTimeout(savePendingTimeout);
  savePendingTimeout = pending
    ? setTimeout(() => {
        setSavePending(false);
        setSaveState(false);
        showStatus(
          "Save is taking too long. Check the project before trying again.",
        );
      }, 12000)
    : null;
  const button = document.getElementById("saveButton");
  button.disabled = pending || sessionRole === "viewer";
  button.textContent = pending ? "Saving…" : "Save project";
  button.classList.toggle("saving", pending);
  if (pending)
    document.getElementById("saveState").textContent = "Saving on server…";
  window.VantaWorkflow?.render();
}

function requestClose() {
  clearKeys();
  if ((saveDirty && window.VantaPreferences?.warning !== false) || savePending)
    exitOverlay.classList.remove("is-hidden");
  else post("close");
}
document
  .getElementById("exitCancelButton")
  .addEventListener("click", () => exitOverlay.classList.add("is-hidden"));
document.getElementById("exitConfirmButton").addEventListener("click", () => {
  exitOverlay.classList.add("is-hidden");
  post("close");
});

function selectedFrame() {
  return selectedFrameTime === null
    ? null
    : project.keyframes.find(
        (frame) => Math.abs(frame.time - selectedFrameTime) < 0.05,
      ) || null;
}

function selectCameraFrame(index) {
  const frame = project.keyframes[index];
  if (!frame) return;
  selectedFrameTime = frame.time;
  selectSceneTab(false);
  renderProject();
  seek(frame.time);
}

function showStatus(message) {
  message = window.VantaI18n?.t(message) ?? message;
  if (!message) return;
  statusMessage.textContent = message;
  toast.textContent = message;
  toast.classList.add("visible");
  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => toast.classList.remove("visible"), 2400);
}

const libraryOverlay = document.getElementById("libraryOverlay");
const libraryPanel = libraryOverlay.querySelector(".library-panel");
const libraryList = document.getElementById("libraryList");
const libraryConfirm = document.getElementById("libraryConfirm");
function closeLibrary() {
  libraryOverlay.classList.add("is-hidden");
  libraryConfirm.classList.add("is-hidden");
  pendingLibraryConfirm = null;
}
function setLibraryBusy(busy) {
  libraryBusy = busy;
  clearTimeout(libraryWaitTimer);
  libraryWaitTimer = busy
    ? setTimeout(() => {
        setLibraryBusy(false);
        showStatus("No server response. Reopen the library before retrying.");
      }, 12000)
    : null;
  libraryPanel.classList.toggle("busy", busy);
}
function confirmLibraryAction(title, message, action) {
  pendingLibraryConfirm = action;
  document.getElementById("libraryConfirmTitle").textContent = title;
  document.getElementById("libraryConfirmText").textContent = message;
  libraryConfirm.classList.remove("is-hidden");
}
async function performLibraryAction(operation, id, name) {
  libraryConfirm.classList.add("is-hidden");
  pendingLibraryConfirm = null;
  clearTimeout(nameTimeout);
  nameTimeout = null;
  setLibraryBusy(true);
  const result = await post("manageProject", { operation, id, name });
  if (!result.ok) {
    setLibraryBusy(false);
    showStatus(result.message || "Project action failed.");
  }
}
function requestLibraryAction(operation, id, name) {
  if (libraryBusy) return;
  if (operation === "open" && id === libraryState.activeId) {
    closeLibrary();
    return;
  }
  const item = libraryState.projects.find((entry) => entry.id === id);
  if (operation === "delete") {
    confirmLibraryAction(
      "Delete this project?",
      `“${item?.name || "Project"}” will be removed permanently.${saveDirty ? " Your unsaved changes will also be lost." : ""}`,
      () => performLibraryAction(operation, id, name),
    );
  } else if (saveDirty && operation !== "rename") {
    confirmLibraryAction(
      "Unsaved changes",
      "Save the current project first, or continue and discard your unsaved changes.",
      () => performLibraryAction(operation, id, name),
    );
  } else performLibraryAction(operation, id, name);
}
function libraryButton(label, action, className = "") {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.dataset.actionLabel = label;
  button.className = className;
  button.addEventListener("click", action);
  return button;
}
function renderLibrary() {
  const allItems = libraryState.projects;
  const query = (document.getElementById("librarySearch").value || "")
    .trim()
    .toLowerCase();
  const items = allItems.filter((item) =>
    item.name.toLowerCase().includes(query),
  );
  document.getElementById("libraryCount").textContent = Number.isFinite(
    libraryState.limit,
  )
    ? `${allItems.length} / ${libraryState.limit}`
    : `${allItems.length}`;
  document.getElementById("newProjectButton").disabled =
    allItems.length >= libraryState.limit || allItems.length === 0;
  libraryList.innerHTML = "";
  if (!items.length) {
    const empty = document.createElement("p");
    empty.className = "library-empty";
    empty.textContent = allItems.length
      ? "No matching projects. Try another name."
      : "Loading projects…";
    libraryList.appendChild(empty);
    return;
  }
  items.forEach((item) => {
    const row = document.createElement("div");
    row.className = `library-row${item.id === libraryState.activeId ? " active" : ""}`;
    const info = document.createElement("div");
    const title = document.createElement("strong");
    title.textContent = item.name;
    title.dataset.i18nUser = "true";
    info.appendChild(title);
    if (item.id === libraryState.activeId) {
      const badge = document.createElement("span");
      badge.className = "active-label";
      badge.textContent = "CURRENT";
      info.appendChild(badge);
    }
    const detail = document.createElement("small");
    detail.textContent = `${item.shots} shots · ${item.actors} actors · ${Math.round(Number(item.duration) || 20)} sec`;
    info.appendChild(detail);
    const actions = document.createElement("div");
    actions.className = "library-actions";
    if (item.id !== libraryState.activeId) {
      const open = libraryButton(
        "Open",
        () => requestLibraryAction("open", item.id),
        "library-open",
      );
      open.disabled = item.available === false;
      open.title = item.error || "";
      actions.appendChild(open);
    }
    if (item.available === false) {
      detail.textContent += " · Damaged project (preserved)";
      row.title = item.error || "Damaged project";
    }
    const duplicateButton = libraryButton("Duplicate", () =>
      requestLibraryAction("duplicate", item.id),
    );
    duplicateButton.disabled = item.available === false;
    actions.appendChild(duplicateButton);
    actions.appendChild(
      libraryButton("Rename", () => {
        info.innerHTML = "";
        actions.innerHTML = "";
        const input = document.createElement("input");
        input.type = "text";
        input.maxLength = 64;
        input.value = item.name;
        info.appendChild(input);
        const renameActions = document.createElement("div");
        renameActions.className = "library-rename-actions";
        renameActions.appendChild(
          libraryButton("Save name", () =>
            requestLibraryAction("rename", item.id, input.value.trim()),
          ),
        );
        renameActions.appendChild(libraryButton("Cancel", renderLibrary));
        info.appendChild(renameActions);
      }),
    );
    const deleteButton = libraryButton("Delete", () =>
      requestLibraryAction("delete", item.id),
    );
    deleteButton.disabled = allItems.length === 1;
    actions.appendChild(deleteButton);
    row.appendChild(info);
    row.appendChild(actions);
    libraryList.appendChild(row);
  });
}
document
  .getElementById("projectLibraryButton")
  .addEventListener("click", () => {
    clearKeys();
    renderLibrary();
    libraryOverlay.classList.remove("is-hidden");
  });
document
  .getElementById("libraryCloseButton")
  .addEventListener("click", closeLibrary);
document
  .getElementById("newProjectButton")
  .addEventListener("click", () => requestLibraryAction("create"));
document.getElementById("libraryCancelButton").addEventListener("click", () => {
  libraryConfirm.classList.add("is-hidden");
  pendingLibraryConfirm = null;
});
document
  .getElementById("libraryContinueButton")
  .addEventListener("click", () => {
    if (pendingLibraryConfirm) pendingLibraryConfirm();
  });

const animationOverlay = document.getElementById("animationOverlay");
const animationPreviewBar = document.getElementById("animationPreviewBar");
const animationSearch = document.getElementById("animationSearch");
function selectedAnimation() {
  return animationCatalog.find((item) => item.id === animationSelectedId);
}
function renderAnimationCatalog() {
  const words = animationSearchText(animationSearch.value.trim())
    .split(/\s+/)
    .filter(Boolean);
  const categories = document.getElementById("animationCategories");
  categories.innerHTML = "";
  for (const category of animationCategories) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = animationCategoryNames[category] || category;
    button.className = category === animationCategory ? "active" : "";
    button.addEventListener("click", () => {
      animationCategory = category;
      renderAnimationCatalog();
    });
    categories.appendChild(button);
  }
  const visible = animationCatalog.filter(
    (item) =>
      (animationCategory === "All" ||
        item.category === animationCategory ||
        (animationCategory === "Favorites" &&
          animationMemory.favorites.includes(item.id)) ||
        (animationCategory === "Recent" &&
          animationMemory.recent.includes(item.id))) &&
      words.every((word) => animationSearchIndex.get(item.id).includes(word)),
  );
  if (animationCategory === "Recent")
    visible.sort(
      (a, b) =>
        animationMemory.recent.indexOf(a.id) -
        animationMemory.recent.indexOf(b.id),
    );
  document.getElementById("animationCount").textContent =
    visible.length + " / " + animationCatalog.length + " animations";
  if (!visible.some((item) => item.id === animationSelectedId))
    animationSelectedId = visible[0]?.id || null;
  const results = document.getElementById("animationResults");
  results.innerHTML = "";
  if (!visible.length) {
    const empty = document.createElement("div");
    empty.className = "animation-empty";
    empty.textContent =
      animationCategory === "Favorites"
        ? "Ajoute une animation aux favoris avec le bouton étoile."
        : animationCategory === "Recent"
          ? "Les animations prévisualisées ou ajoutées apparaîtront ici."
          : "Aucune animation ne correspond à cette recherche.";
    results.appendChild(empty);
  }
  visible.forEach((item) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `animation-result${item.id === animationSelectedId ? " active" : ""}`;
    row.dataset.animationId = item.id;
    const label = document.createElement("span");
    const title = document.createElement("strong");
    title.textContent = item.name;
    const category = document.createElement("small");
    category.textContent =
      item.category +
      " · " +
      (item.loop ? "Boucle" : "Une fois") +
      (animationMemory.favorites.includes(item.id) ? " · ★" : "");
    label.appendChild(title);
    label.appendChild(category);
    const arrow = document.createElement("span");
    arrow.className = "preview-glyph";
    arrow.textContent = "›";
    row.appendChild(label);
    row.appendChild(arrow);
    row.addEventListener("click", () => {
      if (animationSelectedId !== item.id) stopCatalogPreview();
      animationSelectedId = item.id;
      renderAnimationCatalog();
    });
    results.appendChild(row);
  });
  const item = selectedAnimation();
  document.getElementById("animationName").textContent =
    item?.name || "Aucune animation";
  document.getElementById("animationDescription").textContent =
    item?.description || "Choisis une autre catégorie ou une autre recherche.";
  document.getElementById("animationDict").textContent = item?.dict || "—";
  document.getElementById("animationClip").textContent = item?.clip || "—";
  document.getElementById("animationLoop").textContent = item
    ? item.loop
      ? "Boucle, jusqu’à la fin du segment"
      : "Action courte, jouée une fois"
    : "—";
  document.getElementById("animationRequirements").textContent = item
    ? [
        item.placement,
        item.props.length
          ? "Objet(s) à placer comme accessoires : " +
            item.props.join(", ") +
            ". Aucun objet n’est créé automatiquement."
          : "",
        item.caution,
      ]
        .filter(Boolean)
        .join(" ")
    : "";
  document.getElementById("animationDurationLabel").textContent =
    item && !item.loop
      ? "DURÉE MAX. (SEC) · 0 = DURÉE NATIVE"
      : "DURÉE (SEC) · 0 = JUSQU’À REMPLACEMENT";
  const favorite = document.getElementById("animationFavoriteButton");
  favorite.disabled = !item;
  favorite.setAttribute(
    "aria-pressed",
    String(Boolean(item && animationMemory.favorites.includes(item.id))),
  );
  favorite.textContent =
    item && animationMemory.favorites.includes(item.id)
      ? "★ Retirer des favoris"
      : "☆ Ajouter aux favoris";
  document.getElementById("animationPlayButton").disabled = !item;
  document.getElementById("animationAddButton").disabled = !item;
}
function openAnimationCatalog(actorId) {
  const actor = project.actors.find(
    (item) => item.id === actorId && item.kind === "ped",
  );
  if (!actor) return showStatus("Select a staged ped first.");
  animationActorId = actorId;
  animationPreviewSequence++;
  animationCategory = "All";
  animationSearch.value = "";
  animationSelectedId = animationCatalog[0].id;
  animationPreviewActive = false;
  document.getElementById("animationContext").textContent =
    `Personnage ${String(actorId).padStart(2, "0")} · Ajouter à ${formatTime(project.playhead)}`;
  document.getElementById("animationPreviewStatus").textContent =
    "Choisis une pose et regarde son aperçu sur le personnage.";
  post("stopPreview");
  clearKeys();
  renderAnimationCatalog();
  animationPreviewBar.classList.add("is-hidden");
  animationOverlay.classList.remove("is-hidden");
}
async function stopCatalogPreview() {
  const sequence = ++animationPreviewSequence;
  animationPreviewActive = false;
  const result = await post("stopAnimationPreview");
  if (sequence !== animationPreviewSequence) return;
  const message = result.ok
    ? "Aperçu arrêté. La scène est restaurée au curseur."
    : result.message || "Impossible d’arrêter l’aperçu.";
  document.getElementById("animationPreviewStatus").textContent = message;
  document.getElementById("animationBarStatus").textContent = message;
  return result;
}
function closeAnimationCatalog() {
  if (
    animationOverlay.classList.contains("is-hidden") &&
    animationPreviewBar.classList.contains("is-hidden")
  )
    return;
  animationOverlay.classList.add("is-hidden");
  animationPreviewBar.classList.add("is-hidden");
  animationPreviewSequence++;
  post("stopAnimationPreview");
  animationPreviewActive = false;
  animationActorId = null;
}
animationSearch.addEventListener("input", renderAnimationCatalog);
document
  .getElementById("animationFavoriteButton")
  .addEventListener("click", () => {
    const item = selectedAnimation();
    if (!item) return;
    const ids = animationMemory.favorites;
    animationMemory.favorites = ids.includes(item.id)
      ? ids.filter((id) => id !== item.id)
      : [...ids, item.id];
    if (!storeAnimationMemory())
      document.getElementById("animationPreviewStatus").textContent =
        "Favoris conservés pour cette session ; le stockage local est indisponible.";
    renderAnimationCatalog();
  });
document
  .getElementById("animationCloseButton")
  .addEventListener("click", closeAnimationCatalog);
document
  .getElementById("animationPlayButton")
  .addEventListener("click", async () => {
    const item = selectedAnimation();
    if (!item || animationActorId == null) return;
    const sequence = ++animationPreviewSequence;
    document.getElementById("animationPreviewStatus").textContent =
      "Chargement de l’animation…";
    document.getElementById("animationBarName").textContent = item.name;
    document.getElementById("animationBarStatus").textContent =
      "Chargement de l’animation…";
    animationOverlay.classList.add("is-hidden");
    animationPreviewBar.classList.remove("is-hidden");
    const result = await post("previewAnimation", {
      id: animationActorId,
      dict: item.dict,
      clip: item.clip,
      loop: item.loop,
    });
    if (
      sequence !== animationPreviewSequence ||
      animationPreviewBar.classList.contains("is-hidden")
    )
      return;
    animationPreviewActive = result.ok;
    if (result.ok) {
      recordAnimationUse(item.id);
      renderAnimationCatalog();
    }
    const message = result.ok
      ? "Aperçu sur le personnage. Arrête-le pour restaurer la scène."
      : result.message || "Animation indisponible.";
    document.getElementById("animationPreviewStatus").textContent = message;
    document.getElementById("animationBarStatus").textContent = message;
    if (!result.ok) {
      animationPreviewBar.classList.add("is-hidden");
      animationOverlay.classList.remove("is-hidden");
    }
  });
document
  .getElementById("animationStopButton")
  .addEventListener("click", stopCatalogPreview);
document
  .getElementById("animationBarStopButton")
  .addEventListener("click", stopCatalogPreview);
document
  .getElementById("animationBarBackButton")
  .addEventListener("click", async () => {
    animationPreviewBar.classList.add("is-hidden");
    animationOverlay.classList.remove("is-hidden");
    await stopCatalogPreview();
  });
async function addSelectedAnimation() {
  const item = selectedAnimation();
  if (!item || animationActorId == null || animationAddPending) return;
  const id = animationActorId;
  const seconds = Number(document.getElementById("animationDuration").value);
  if (!Number.isFinite(seconds) || seconds < 0)
    return showStatus(
      "Choisis une durée positive, ou 0 pour la durée par défaut.",
    );
  animationAddPending = true;
  try {
    const stopped = stopCatalogPreview(),
      sequence = animationPreviewSequence;
    const stopResult = await stopped;
    if (sequence !== animationPreviewSequence || id !== animationActorId)
      return;
    if (!stopResult?.ok)
      return showStatus(
        stopResult?.message || "Impossible d’arrêter l’aperçu.",
      );
    const result = await post("addAction", {
      id,
      type: "animation",
      dict: item.dict,
      clip: item.clip,
      loop: item.loop,
      duration: seconds || undefined,
    });
    if (sequence !== animationPreviewSequence || id !== animationActorId)
      return;
    if (result.ok) {
      recordAnimationUse(item.id);
      closeAnimationCatalog();
      showStatus(`${item.name} ajouté à ${formatTime(project.playhead)}.`);
    } else showStatus(result.message || "Impossible d’ajouter l’animation.");
  } finally {
    animationAddPending = false;
  }
}
document
  .getElementById("animationAddButton")
  .addEventListener("click", addSelectedAnimation);
document
  .getElementById("animationBarAddButton")
  .addEventListener("click", addSelectedAnimation);

function formatTime(value) {
  const time = Math.max(0, Number(value) || 0);
  const minutes = Math.floor(time / 60);
  const seconds = (time % 60).toFixed(1).padStart(4, "0");
  return `${String(minutes).padStart(2, "0")}:${seconds}`;
}

function actorLabel(kind, short = false) {
  if (kind === "vehicle") return short ? "CAR" : "Vehicle";
  if (kind === "prop") return short ? "OBJ" : "Object";
  return short ? "PED" : "Ped";
}

function actionLabel(action) {
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
  if (action.type === "visibility")
    return action.visible ? "Show object" : "Hide object";
  if (action.type === "engine")
    return action.enabled ? "Engine on" : "Engine off";
  if (action.type === "lights")
    return action.enabled ? "Lights on" : "Lights off";
  if (action.type === "door") {
    const door =
      [
        "Driver front",
        "Driver rear",
        "Passenger front",
        "Passenger rear",
        "Hood",
        "Trunk",
      ][action.door] || "Door";
    return `${door} ${action.enabled ? "open" : "closed"}`;
  }
  return `Animation ${action.clip}${action.duration ? " · " + Number(action.duration).toFixed(1) + "s" : " · until replaced"}`;
}

function renderRuler() {
  const max = Number(project.duration) || 20;
  const interval =
    max <= 30 ? 5 : max <= 90 ? 15 : max <= 300 ? 30 : max <= 1200 ? 120 : 600;
  const ticks = [];
  for (let value = 0; value <= max; value += interval) {
    ticks.push(
      `<span style="left:${(value / max) * 100}%">${formatTime(value).slice(0, 5)}</span>`,
    );
  }
  if (max % interval !== 0)
    ticks.push(`<span style="left:100%">${formatTime(max).slice(0, 5)}</span>`);
  document.getElementById("ruler").innerHTML = ticks.join("");
}

function updateRigFields() {
  const mode = document.getElementById("rigMode").value;
  document
    .getElementById("rigSubjectFields")
    .classList.toggle("is-hidden", mode === "manual");
  document
    .getElementById("rigFollowFields")
    .classList.toggle("is-hidden", mode !== "follow");
  document
    .getElementById("rigOrbitFields")
    .classList.toggle("is-hidden", mode !== "orbit");
  const hints = {
    manual: "Move the camera freely or create a keyframe path.",
    target:
      "Keep the subject framed while moving freely or playing your keyframe path.",
    follow:
      "Apply from your current view to capture the distance and angle. Switch to Manual to reframe.",
    orbit:
      "Orbit uses the timeline time. Negative speed reverses direction. Switch to Manual to move freely.",
  };
  document.getElementById("rigHint").textContent = hints[mode] || hints.manual;
}

function renderCameraRig() {
  const rig = project.cameraRig || { mode: "manual" };
  document.getElementById("rigMode").value = rig.mode;
  document.getElementById("rigBadge").textContent = rig.mode.toUpperCase();
  const target = document.getElementById("rigTarget");
  const previous = target.value;
  target.innerHTML = "";
  project.actors.forEach((actor) => {
    const option = document.createElement("option");
    option.value = actor.id;
    option.textContent = `${actor.kind.toUpperCase()} ${actor.id} · ${actor.model}`;
    target.appendChild(option);
  });
  target.value = String(
    rig.targetId || previous || project.actors[0]?.id || "",
  );
  document.getElementById("rigHeight").value = rig.targetHeight ?? 1;
  document.getElementById("rigRadius").value = rig.radius ?? 8;
  document.getElementById("rigElevation").value = rig.elevation ?? 2;
  document.getElementById("rigSpeed").value = rig.speed ?? 15;
  document.getElementById("rigRelative").checked = rig.relative ?? true;
  document.getElementById("rigAvoidObstacles").checked =
    rig.avoidObstacles === true;
  updateRigFields();
}

document.getElementById("rigMode").addEventListener("change", updateRigFields);
document.getElementById("rigApply").addEventListener("click", async () => {
  const mode = document.getElementById("rigMode").value;
  const targetId = Number(document.getElementById("rigTarget").value);
  if (
    mode !== "manual" &&
    !project.actors.some((actor) => actor.id === targetId)
  ) {
    showStatus("Place a subject in the scene first.");
    return;
  }
  const button = document.getElementById("rigApply");
  button.disabled = true;
  try {
    const result = await post("setCameraRig", {
      mode,
      targetId,
      targetHeight: Number(document.getElementById("rigHeight").value),
      radius: Number(document.getElementById("rigRadius").value),
      elevation: Number(document.getElementById("rigElevation").value),
      speed: Number(document.getElementById("rigSpeed").value),
      relative: document.getElementById("rigRelative").checked,
      avoidObstacles: document.getElementById("rigAvoidObstacles").checked,
    });
    if (result.ok)
      showStatus(
        mode === "manual"
          ? "Manual camera restored."
          : "Automatic camera applied. Preview the timeline to see the shot.",
      );
  } finally {
    button.disabled = false;
  }
});

function renderShotSubjects() {
  const select = document.getElementById("shotSubject"),
    previous = select.value;
  select.innerHTML = "";
  const aim = document.createElement("option");
  aim.value = "0";
  aim.textContent = "Point at camera aim";
  select.appendChild(aim);
  project.actors.forEach((actor) => {
    const option = document.createElement("option");
    option.value = String(actor.id);
    option.textContent = actor.name || actor.model;
    option.dataset.i18nUser = "true";
    select.appendChild(option);
  });
  select.value = project.actors.some((actor) => String(actor.id) === previous)
    ? previous
    : "0";
}
const shotKind = document.getElementById("shotPreset");
shotKind.addEventListener("change", () => {
  document
    .getElementById("shotTravelField")
    .classList.toggle(
      "is-hidden",
      ["orbit", "follow"].includes(shotKind.value),
    );
  document.getElementById("shotHint").textContent =
    shotKind.value === "follow"
      ? "Tracks a moving scene actor inside this independent shot."
      : "Frames the subject’s current position. Check clearance in the preview; adjust the resulting keyframes freely.";
  document.getElementById("shotAdd").textContent =
    shotKind.value === "follow" ? "Add Follow shot" : "Add at playhead";
});
for (const [id, call] of [
  ["shotPreview", "previewCameraPreset"],
  ["shotAdd", "applyCameraPreset"],
]) {
  document.getElementById(id).addEventListener("click", async () => {
    const button = document.getElementById(id);
    button.disabled = true;
    try {
      const result = await post(call, {
        kind: shotKind.value,
        targetId: Number(document.getElementById("shotSubject").value),
        seconds: Number(document.getElementById("shotSeconds").value),
        distance: Number(document.getElementById("shotDistance").value),
        height: Number(document.getElementById("shotHeight").value),
        travel: Number(document.getElementById("shotTravel").value),
      });
      if (result.ok) showStatus(result.message);
    } finally {
      button.disabled = false;
    }
  });
}
document
  .getElementById("shotCancel")
  .addEventListener("click", () => post("cancelCameraPreset"));
let sessionInvitation = null;
document.getElementById("projectExport").addEventListener("click", async () => {
  if (libraryBusy) return;
  const button = document.getElementById("projectExport");
  button.disabled = true;
  const result = await post("exportProject");
  button.disabled = false;
  if (result.ok) {
    document.getElementById("projectJson").value = result.json;
    showStatus(
      result.message || "Project exported. Copy the JSON to share it.",
    );
  } else showStatus(result.message || "Export failed.");
});
document.getElementById("projectImport").addEventListener("click", () => {
  if (libraryBusy) return;
  const json = document.getElementById("projectJson").value.trim();
  if (!json) {
    showStatus("Paste a project JSON before importing.");
    return;
  }
  if (json.length > 2000000) {
    showStatus("This project is too large to import.");
    return;
  }
  try {
    JSON.parse(json);
  } catch {
    showStatus("Invalid JSON. Paste a complete exported project.");
    return;
  }
  const run = async () => {
    libraryConfirm.classList.add("is-hidden");
    pendingLibraryConfirm = null;
    setLibraryBusy(true);
    const result = await post("importProject", { json });
    if (!result.ok) {
      setLibraryBusy(false);
      showStatus(result.message || "Import failed.");
    }
  };
  if (saveDirty || savePending)
    confirmLibraryAction(
      "Import a project?",
      "Save your current project first, or continue and discard its unsaved changes.",
      run,
    );
  else run();
});
for (const [id, operation] of [
  ["sessionCreate", "create"],
  ["sessionInviteButton", "invite"],
  ["sessionPublish", "publish"],
  ["sessionPlay", "play"],
  ["sessionStop", "stop"],
  ["sessionLeave", "leave"],
])
  document
    .getElementById(id)
    .addEventListener("click", () =>
      post("collaboration", {
        operation,
        target: Number(document.getElementById("sessionTarget").value),
      }),
    );
for (const [id, operation] of [
  ["sessionAccept", "accept"],
  ["sessionDecline", "decline"],
])
  document.getElementById(id).addEventListener("click", () => {
    if (sessionInvitation)
      post("collaboration", { operation, id: sessionInvitation });
    document.getElementById("sessionInviteOverlay").classList.add("is-hidden");
    sessionInvitation = null;
  });
let copiedSequence = null;
let timelineCopied = false;
let sessionRole = "none";
function updateContextControls() {
  const viewer = sessionRole === "viewer",
    host = sessionRole === "host",
    shot = selectedSequence();
  const actor = project.actors.find((a) => a.id === selectedActorId);
  const recorded = actor?.actions?.some((a) => a.type === "recording");
  for (const [id, disabled] of Object.entries({
    sequenceCopy: !shot || viewer,
    sequenceDelete: !shot || viewer,
    sequenceUpdate: !shot || viewer,
    sequencePaste: !copiedSequence || viewer,
    timelineCopy: !timelineSelection.size || viewer,
    timelinePaste: !timelineCopied || viewer,
    stagingDuplicate: !stagingIds().length || viewer,
    stagingGroupApply: !stagingIds().length || viewer,
    recordingTrim: !recorded || viewer,
    recordedGestureAdd: !recorded || actor?.kind !== "ped" || viewer,
    sessionCreate: sessionRole !== "none",
    sessionInviteButton: !host,
    sessionPublish: !host,
    sessionPlay: !host,
    sessionStop: !host,
    sessionLeave: sessionRole === "none",
    saveButton: savePending || viewer,
  }))
    document.getElementById(id).disabled = disabled;
  root.classList.toggle("session-viewer", viewer);
}
function selectedSequence() {
  return (project.cameraShots || []).find(
    (s) => s.id === project.selectedShotId,
  );
}
function renderSequences() {
  const shots = project.cameraShots || [],
    list = document.getElementById("sequenceList");
  list.innerHTML = "";
  document.getElementById("sequenceCount").textContent = String(
    shots.length,
  ).padStart(2, "0");
  for (const [index, shot] of shots.entries()) {
    const button = document.createElement("button");
    button.className =
      "sequence-row" + (shot.id === project.selectedShotId ? " active" : "");
    button.title = shot.name;
    button.innerHTML =
      '<span class="sequence-number"></span><span class="sequence-info"><strong></strong><small></small></span><span class="sequence-length"></span>';
    button.querySelector(".sequence-number").textContent = String(
      index + 1,
    ).padStart(2, "0");
    button.querySelector("strong").textContent = shot.name;
    button.querySelector("small").textContent =
      { smooth: "Smooth path", linear: "Linear", easeInOut: "Ease in / out" }[
        shot.ease
      ] +
      " · " +
      (shot.frames || []).length +
      " keys";
    button.querySelector(".sequence-length").textContent =
      shot.duration.toFixed(1) + "s";
    button.addEventListener("click", () => {
      selectedFrameTime = null;
      post("selectCameraShot", { id: shot.id });
    });
    list.appendChild(button);
  }
  const shot = selectedSequence();
  document.getElementById("sequenceEdit").classList.toggle("is-hidden", !shot);
  if (shot)
    for (const [id, value] of Object.entries({
      sequenceName: shot.name,
      sequenceTime: shot.time,
      sequenceDuration: shot.duration,
      sequenceEase: shot.ease,
      sequenceBlend: shot.blend || 0,
    })) {
      const el = document.getElementById(id);
      if (document.activeElement !== el) el.value = value;
    }
}
document
  .getElementById("newCameraSequence")
  .addEventListener("click", () => post("createCameraShot", { duration: 6 }));
document.getElementById("legacyCameraEdit").addEventListener("click", () => {
  selectedFrameTime = null;
  post("selectCameraShot", { id: 0 });
});
document.getElementById("sequenceUpdate").addEventListener("click", () => {
  const shot = selectedSequence();
  if (shot)
    post("updateCameraShot", {
      id: shot.id,
      name: document.getElementById("sequenceName").value,
      time: Number(document.getElementById("sequenceTime").value),
      duration: Number(document.getElementById("sequenceDuration").value),
      ease: document.getElementById("sequenceEase").value,
      blend: Number(document.getElementById("sequenceBlend").value),
    });
});
document.getElementById("sequenceCopy").addEventListener("click", () => {
  copiedSequence = selectedSequence()?.id;
  updateContextControls();
  showStatus(
    "Shot copied. Move the playhead to an empty interval, then paste.",
  );
});
document.getElementById("sequencePaste").addEventListener("click", () => {
  if (copiedSequence)
    post("duplicateCameraShot", { id: copiedSequence, time: project.playhead });
});
document.getElementById("sequenceDelete").addEventListener("click", () => {
  const shot = selectedSequence();
  if (shot) post("deleteCameraShot", { id: shot.id });
});
document.getElementById("timelineZoom").addEventListener("input", (event) => {
  document.getElementById("timelineContent").style.width =
    Number(event.target.value) * 100 + "%";
});
function renderSequenceMarkers() {
  for (const shot of project.cameraShots || []) {
    const marker = document.createElement("button");
    marker.className =
      "camera-sequence" +
      (shot.id === project.selectedShotId ? " selected" : "");
    const name = document.createElement("span");
    name.className = "clip-name";
    name.textContent = shot.name;
    const length = document.createElement("small");
    length.textContent = shot.duration.toFixed(1) + "s";
    marker.append(name, length);
    marker.title = shot.name;
    marker.style.left = (shot.time / project.duration) * 100 + "%";
    marker.style.width = (shot.duration / project.duration) * 100 + "%";
    for (const edge of ["start", "end"]) {
      const handle = document.createElement("span");
      handle.className = "clip-handle " + edge;
      handle.dataset.edge = edge;
      handle.title = "Trim " + edge;
      marker.appendChild(handle);
    }
    marker.addEventListener("mousedown", (event) =>
      beginTimelineDrag(event, marker, trackLane, {
        kind: "shot",
        id: shot.id,
        time: shot.time,
        duration: shot.duration,
        maxTime: project.duration - shot.duration,
      }),
    );
    markers.appendChild(marker);
  }
}
const timelineSelection = new Map();
const selectionKey = (item) =>
  item.kind +
  ":" +
  (item.id || item.index || item.actorId + ":" + item.actionId);
function updateTimelineSelection() {
  document.getElementById("timelineSelectionCount").textContent =
    timelineSelection.size + " SELECTED";
  updateContextControls();
}
document.getElementById("timelineCopy").addEventListener("click", async () => {
  const result = await post("copyTimeline", {
    items: [...timelineSelection.values()],
  });
  if (result.ok) {
    timelineCopied = true;
    updateContextControls();
    showStatus(result.message || "Selection copied.");
  }
});
document
  .getElementById("timelinePaste")
  .addEventListener("click", () => post("pasteTimeline"));
document
  .getElementById("stagingSelection")
  .addEventListener("change", updateContextControls);
function stagingIds() {
  const group = document.getElementById("stagingSelection").value;
  return group
    ? project.actors.filter((a) => a.group === group).map((a) => a.id)
    : selectedActorId
      ? [selectedActorId]
      : [];
}
document
  .getElementById("stagingGroupApply")
  .addEventListener("click", () =>
    post("setActorGroup", {
      ids: stagingIds(),
      name: document.getElementById("stagingGroupName").value,
    }),
  );
document
  .getElementById("stagingDuplicate")
  .addEventListener("click", () =>
    post("duplicateActors", {
      ids: stagingIds(),
      x: Number(document.getElementById("stagingOffsetX").value),
      y: Number(document.getElementById("stagingOffsetY").value),
      z: 0,
    }),
  );
document
  .getElementById("recordedGestureAdd")
  .addEventListener("click", () =>
    post("addRecordedGesture", {
      id: selectedActorId,
      gesture: document.getElementById("recordedGesture").value,
      duration: Number(document.getElementById("recordedGestureSeconds").value),
    }),
  );
document
  .getElementById("recordingTrim")
  .addEventListener("click", () =>
    post("trimRecording", {
      id: selectedActorId,
      first: Number(document.getElementById("recordingTrimFirst").value),
      last: Number(document.getElementById("recordingTrimLast").value),
    }),
  );
document
  .getElementById("locationSave")
  .addEventListener("click", () =>
    post("saveLocation", {
      name: document.getElementById("locationName").value || "Location",
    }),
  );
document
  .getElementById("playbackRangeApply")
  .addEventListener("click", () =>
    post("setPlaybackRange", {
      first: Number(document.getElementById("playbackFirst").value),
      last: Number(document.getElementById("playbackLast").value),
      loop: document.getElementById("playbackLoop").checked,
    }),
  );
document
  .getElementById("framingGuide")
  .addEventListener(
    "change",
    (event) =>
      (document.getElementById("framingOverlay").className =
        "framing-overlay " + event.target.value),
  );
document
  .getElementById("lookFocusSubject")
  .addEventListener("change", (event) =>
    post("setSceneLook", {
      field: "focusId",
      value: Number(event.target.value),
    }),
  );
function updateFraming() {
  const surface = document.getElementById("lookSurface"),
    overlay = document.getElementById("framingOverlay");
  const bounds = surface.getBoundingClientRect();
  overlay.style.left = bounds.left + "px";
  overlay.style.top = bounds.top + "px";
  overlay.style.width = bounds.width + "px";
  overlay.style.height = bounds.height + "px";
  overlay.style.right = "auto";
  overlay.style.bottom = "auto";
  const ratio =
    document.getElementById("framingGuide").value === "portrait"
      ? 9 / 16
      : 2.39;
  const width = Math.min(bounds.width, bounds.height * ratio),
    height = width / ratio;
  overlay.style.setProperty?.(
    "--guide-left",
    (bounds.width - width) / 2 + "px",
  );
  overlay.style.setProperty?.(
    "--guide-top",
    (bounds.height - height) / 2 + "px",
  );
}
window.addEventListener("resize", updateFraming);
document
  .getElementById("framingGuide")
  .addEventListener("change", updateFraming);
function renderProductionSelectors() {
  for (const [id, items, value] of [
    [
      "lookFocusSubject",
      [
        [0, "Manual focus distance"],
        ...project.actors.map((a) => [a.id, a.name || a.model]),
      ],
      String(project.look?.focusId || 0),
    ],
    [
      "stagingSelection",
      [
        ["", "Selected actor"],
        ...[...new Set(project.actors.map((a) => a.group).filter(Boolean))].map(
          (g) => [g, g],
        ),
      ],
      document.getElementById("stagingSelection").value,
    ],
  ]) {
    const select = document.getElementById(id),
      signature = JSON.stringify(items);
    if (select.vantaOptionsSignature !== signature) {
      select.innerHTML = "";
      for (const [key, label] of items) {
        const option = document.createElement("option");
        option.value = String(key);
        option.textContent = label;
        select.appendChild(option);
      }
      select.vantaOptionsSignature = signature;
    }
    select.value = items.some((item) => String(item[0]) === value)
      ? value
      : String(items[0][0]);
  }
}
function renderProduction() {
  updateFraming();
  renderProductionSelectors();
  const locations = document.getElementById("locationList");
  locations.innerHTML = "";
  (project.bookmarks || []).forEach((location, index) => {
    const row = document.createElement("div");
    row.className = "location-row";
    const go = document.createElement("button");
    go.textContent = location.name;
    go.dataset.i18nUser = "true";
    go.addEventListener("click", () =>
      post("goLocation", { index: index + 1 }),
    );
    row.appendChild(go);
    const remove = document.createElement("button");
    remove.textContent = "×";
    remove.setAttribute("aria-label", "Delete " + location.name);
    remove.addEventListener("click", () =>
      post("deleteLocation", { index: index + 1 }),
    );
    row.appendChild(remove);
    locations.appendChild(row);
  });
  document.getElementById("playbackFirst").max = project.duration;
  document.getElementById("playbackLast").max = project.duration;
  if (document.activeElement !== document.getElementById("playbackFirst"))
    document.getElementById("playbackFirst").value =
      project.playback?.first ?? 0;
  if (document.activeElement !== document.getElementById("playbackLast"))
    document.getElementById("playbackLast").value =
      project.playback?.last ?? project.duration;
  document.getElementById("playbackLoop").checked =
    project.playback?.loop === true;
}
function renderProject() {
  renderProduction();
  renderSequences();
  renderShotSubjects();
  renderCameraRig();
  if (document.activeElement !== projectNameInput)
    projectNameInput.value = project.name || "Untitled Project";
  if (document.activeElement !== durationInput)
    durationInput.value = Number(project.duration).toFixed(0);
  document.getElementById("durationReadout").textContent = formatTime(
    project.duration,
  );
  document.getElementById("frameCount").textContent = String(
    project.keyframes.length,
  ).padStart(2, "0");
  document
    .getElementById("emptyCamera")
    .classList.toggle("is-hidden", project.keyframes.length > 0);
  document
    .getElementById("cameraNote")
    .classList.toggle("is-hidden", project.keyframes.length === 0);
  scrubber.max = project.duration;
  scrubber.value = Math.min(project.playhead, project.duration);
  document.getElementById("timeReadout").textContent = formatTime(
    project.playhead,
  );
  renderRuler();

  keyframeList.innerHTML = "";
  markers.innerHTML = "";
  document.getElementById("keyMarkers").innerHTML = "";
  project.keyframes.forEach((frame, index) => {
    const row = document.createElement("div");
    row.className = "keyframe-row";
    if (
      selectedFrameTime !== null &&
      Math.abs(frame.time - selectedFrameTime) < 0.05
    )
      row.classList.add("selected");
    row.innerHTML = `<span class="frame-index">${String(index + 1).padStart(2, "0")}</span><span class="frame-meta"><strong></strong><small>FOV ${Number(frame.fov).toFixed(0)}°</small></span><span class="frame-time">${formatTime(frame.time)}</span><button class="delete-frame" title="Delete keyframe" aria-label="Delete keyframe">×</button>`;
    row.querySelector("strong").textContent =
      frame.name || `Shot ${String(index + 1).padStart(2, "0")}`;
    if (frame.name) row.querySelector("strong").dataset.i18nUser = "true";
    row.addEventListener("click", (event) => {
      if (event.target.closest(".delete-frame")) return;
      selectCameraFrame(index);
    });
    row.querySelector(".delete-frame").addEventListener("click", () => {
      if (
        selectedFrameTime !== null &&
        Math.abs(frame.time - selectedFrameTime) < 0.05
      )
        selectedFrameTime = null;
      post("deleteKeyframe", { index: index + 1 });
    });
    keyframeList.appendChild(row);

    const marker = document.createElement("button");
    marker.className = "timeline-marker";
    marker.classList.toggle(
      "selected",
      timelineSelection.has(selectionKey({ kind: "camera", index: index + 1 })),
    );
    marker.style.left = `${(frame.time / project.duration) * 100}%`;
    marker.title = `Keyframe ${index + 1} · ${formatTime(frame.time)}`;
    marker.addEventListener("mousedown", (event) =>
      beginTimelineDrag(
        event,
        marker,
        document.getElementById("keyframeLane"),
        { kind: "camera", index: index + 1, time: frame.time },
      ),
    );
    document.getElementById("keyMarkers").appendChild(marker);
  });
  renderSequenceMarkers();
  renderPlayhead(project.playhead);
  document.getElementById("pathBar").style.width =
    project.cameraRig?.mode && project.cameraRig.mode !== "manual"
      ? "100%"
      : `${(Math.max(...project.keyframes.map((frame) => frame.time), 0) / project.duration) * 100}%`;
  renderActors();
  renderCamera();
  updateFraming();
  window.VantaVisual?.render();
  window.VantaWorkflow?.render();
}

const inspectorSections = new Map();
const sceneModelNames = new Map();
function sceneElementName(actor) {
  return (
    actor.name ||
    sceneModelNames.get(actor.model) ||
    {
      a_m_y_business_01: "Businessman",
      sultan: "Sultan",
      prop_tool_box_04: "Tool box",
    }[actor.model] ||
    actor.model
      .replace(/^(?:a_[mf]_[myo]_?|s_[mf]_[myo]_?|prop_)/, "")
      .replace(/_/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase())
  );
}
function inspectorGroup(actor, name, initiallyOpen) {
  const key = actor.id + ":" + name;
  const section = document.createElement("details");
  section.className = "inspector-group";
  section.dataset.sectionKey = name;
  section.open = inspectorSections.has(key)
    ? inspectorSections.get(key)
    : initiallyOpen;
  const summary = document.createElement("summary");
  summary.textContent = name;
  section.appendChild(summary);
  section.addEventListener("toggle", () =>
    inspectorSections.set(key, section.open),
  );
  return section;
}
let pendingAccessorySelection = null;
function accessoryPanel(actor) {
  const attached = !!actor.attachment;
  const panel = inspectorGroup(
    actor,
    attached ? "Attachment" : "Accessories",
    attached,
  );
  panel.classList.add("accessory-panel");
  const body = document.createElement("div");
  body.className = "appearance-body";
  panel.appendChild(body);
  const field = (title, input) => {
    const label = document.createElement("label");
    label.className = "scene-label";
    label.textContent = title;
    label.appendChild(input);
    body.appendChild(label);
  };
  const dropdown = (items, value) => {
    const el = document.createElement("select");
    for (const [id, label] of items) {
      const o = document.createElement("option");
      o.value = String(id);
      o.textContent = label;
      el.appendChild(o);
    }
    el.value = String(value);
    return el;
  };
  const bones = [
    ["rightHand", "Right hand"],
    ["leftHand", "Left hand"],
    ["back", "Back"],
    ["head", "Head"],
    ["pelvis", "Waist"],
  ];
  if (!attached) {
    const presets = [
      ["prop_phone_ing", "Phone", "rightHand", 0.1, 0, 0, 0, 0, 0],
      ["prop_pap_camera_01", "Camera", "rightHand", 0.1, 0, 0, 0, 0, 0],
      ["p_ld_heist_bag_s", "Bag", "back", 0, -0.15, 0, 0, 90, 0],
      ["w_pi_pistol", "Pistol (visual prop)", "rightHand", 0.1, 0, 0, 0, 0, 0],
    ];
    const choice = dropdown(
      [...presets.map((p) => [p[0], p[1]]), ["custom", "Custom object"]],
      presets[0][0],
    );
    field("ACCESSORY", choice);
    const custom = document.createElement("input");
    custom.type = "text";
    custom.placeholder = "Object model name";
    custom.classList.add("is-hidden");
    body.appendChild(custom);
    const bone = dropdown(bones, "rightHand");
    field("ATTACH TO", bone);
    choice.addEventListener("change", () => {
      custom.classList.toggle("is-hidden", choice.value !== "custom");
      const p = presets.find((p) => p[0] === choice.value);
      if (p) bone.value = p[2];
    });
    const add = document.createElement("button");
    add.className = "aim-button";
    add.textContent = "Add accessory at playhead";
    add.addEventListener("click", async () => {
      const preset = presets.find((p) => p[0] === choice.value);
      const coords = preset?.slice(3) || [0, 0, 0, 0, 0, 0];
      add.disabled = true;
      try {
        const attachment = {
          parentId: actor.id,
          bone: bone.value,
          visible: false,
        };
        ["x", "y", "z", "rx", "ry", "rz"].forEach(
          (key, i) => (attachment[key] = coords[i]),
        );
        const result = await post("addAccessory", {
          parentId: actor.id,
          model: preset?.[0] || custom.value.trim(),
          attachment,
        });
        if (!result.ok)
          return showStatus(result.message || "Could not add accessory.");
        if (project.actors.some((a) => a.id === result.id)) {
          selectedActorId = result.id;
          renderActors();
        } else pendingAccessorySelection = result.id;
      } finally {
        add.disabled = false;
      }
    });
    body.appendChild(add);
  } else {
    let busy = false;
    const update = async (changes) => {
      if (busy) return;
      busy = true;
      body.classList.add("is-applying");
      try {
        const result = await post("setAttachment", {
          id: actor.id,
          attachment: { ...actor.attachment, ...changes },
        });
        if (!result.ok) {
          showStatus(result.message || "Could not adjust accessory.");
          return;
        }
        actor.attachment = result.attachment;
        paint();
      } finally {
        busy = false;
        body.classList.remove("is-applying");
      }
    };
    const paint = () => {
      body.innerHTML = "";
      const parent = dropdown(
        project.actors
          .filter((p) => p.kind === "ped")
          .map((p) => [p.id, sceneElementName(p)]),
        actor.attachment.parentId,
      );
      field("ACTOR", parent);
      parent.addEventListener("change", () =>
        update({ parentId: Number(parent.value) }),
      );
      const bone = dropdown(bones, actor.attachment.bone);
      field("ATTACH TO", bone);
      bone.addEventListener("change", () => update({ bone: bone.value }));
      for (const [key, label, step] of [
        ["x", "Left / right", 0.01],
        ["y", "Back / forward", 0.01],
        ["z", "Down / up", 0.01],
        ["rx", "Tilt", 5],
        ["ry", "Roll", 5],
        ["rz", "Turn", 5],
      ]) {
        const row = document.createElement("div");
        row.className = "appearance-stepper";
        const number = document.createElement("input");
        number.type = "number";
        number.step = String(step);
        number.min = key.startsWith("r") ? "-360" : "-2";
        number.max = key.startsWith("r") ? "360" : "2";
        number.value = actor.attachment[key].toFixed(
          key.startsWith("r") ? 0 : 2,
        );
        number.setAttribute("aria-label", label + " accessory");
        for (const delta of [-1, 1]) {
          const b = document.createElement("button");
          b.innerHTML =
            '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10' +
            (delta > 0 ? "M8 3v10" : "") +
            '"/></svg>';
          b.setAttribute(
            "aria-label",
            label + (delta < 0 ? " decrease" : " increase"),
          );
          b.addEventListener("click", () =>
            update({
              [key]: Number((actor.attachment[key] + delta * step).toFixed(3)),
            }),
          );
          row.appendChild(b);
          if (delta < 0) row.appendChild(number);
        }
        number.addEventListener("change", () =>
          update({ [key]: Number(number.value) }),
        );
        field(
          label.toUpperCase() + (key.startsWith("r") ? " (DEG)" : " (M)"),
          row,
        );
      }
      const zero = document.createElement("button");
      zero.className = "aim-button";
      zero.textContent = "Reset offsets";
      zero.addEventListener("click", () =>
        update({ x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 }),
      );
      body.appendChild(zero);
    };
    paint();
  }
  const hint = document.createElement("p");
  hint.className = "scene-hint";
  hint.textContent = attached
    ? "Watch the object in the scene while adjusting. Show/hide cues below control when it is worn."
    : "Creates a visual object, not a usable item or weapon. Choose a matching ped animation separately.";
  panel.appendChild(hint);
  return panel;
}
function appearancePanel(actor) {
  const panel = inspectorGroup(actor, "Appearance", false);
  panel.classList.add("appearance-panel");
  const body = document.createElement("div");
  body.className = "appearance-body";
  panel.appendChild(body);
  let loaded = false,
    busy = false,
    selectedSlot = "",
    options;
  const field = (label, input) => {
    const el = document.createElement("label");
    el.className = "scene-label";
    el.textContent = label;
    el.appendChild(input);
    body.appendChild(el);
    return el;
  };
  const select = (items, value) => {
    const el = document.createElement("select");
    for (const [id, name] of items) {
      const o = document.createElement("option");
      o.value = String(id);
      o.textContent = name;
      el.appendChild(o);
    }
    el.value = String(value);
    return el;
  };
  const apply = async (appearance) => {
    if (busy) return;
    busy = true;
    body.classList.add("is-applying");
    try {
      const result = await post("setActorAppearance", {
        id: actor.id,
        appearance,
      });
      if (!result.ok) {
        showStatus(result.message || "Could not apply appearance.");
        return;
      }
      actor.appearance = result.appearance;
      options = result.options;
      paint();
    } finally {
      busy = false;
      body.classList.remove("is-applying");
    }
  };
  const paint = () => {
    body.innerHTML = "";
    if (!options) {
      body.textContent = "Appearance is unavailable.";
      return;
    }
    if (actor.kind === "ped") {
      const slots = [
        ...(options.components || []).map((v) => ({
          ...v,
          type: "components",
        })),
        ...(options.props || []).map((v) => ({ ...v, type: "props" })),
      ];
      if (!slots.length) {
        body.textContent = "This model has no clothing variations.";
        return;
      }
      if (!slots.some((v) => v.type + ":" + v.id === selectedSlot))
        selectedSlot = slots[0].type + ":" + slots[0].id;
      const slot = slots.find((v) => v.type + ":" + v.id === selectedSlot);
      const slotSelect = select(
        slots.map((v) => [v.type + ":" + v.id, v.name]),
        selectedSlot,
      );
      field("CLOTHING / ACCESSORY", slotSelect);
      slotSelect.addEventListener("change", () => {
        selectedSlot = slotSelect.value;
        paint();
      });
      const stepper = document.createElement("div");
      stepper.className = "appearance-stepper";
      const min = slot.type === "props" ? -1 : 0,
        max = slot.count - 1;
      const changeDrawable = (value) => {
        if (!Number.isInteger(value) || value < min || value > max)
          return showStatus("Choose an available variation.");
        apply({
          [slot.type]: [
            {
              id: slot.id,
              drawable: value,
              texture: 0,
              palette: slot.palette || 0,
            },
          ],
        });
      };
      const number = document.createElement("input");
      number.type = "number";
      number.min = String(min);
      number.max = String(max);
      number.step = "1";
      number.value = String(slot.drawable);
      number.setAttribute("aria-label", "Clothing variation");
      for (const [delta, label] of [
        [-1, "Previous variation"],
        [1, "Next variation"],
      ]) {
        const b = document.createElement("button");
        b.textContent = delta < 0 ? "\u2212" : "+";
        b.title = label;
        b.setAttribute("aria-label", label);
        b.disabled = slot.drawable + delta < min || slot.drawable + delta > max;
        b.addEventListener("click", () =>
          changeDrawable(slot.drawable + delta),
        );
        stepper.appendChild(b);
        if (delta < 0) stepper.appendChild(number);
      }
      number.addEventListener("change", () =>
        changeDrawable(Number(number.value)),
      );
      field("VARIATION", stepper);
      const textures = select(
        Array.from({ length: Math.max(1, slot.textures) }, (_, i) => [
          i,
          "Texture " + (i + 1),
        ]),
        slot.texture,
      );
      textures.disabled = slot.drawable < 0;
      field("TEXTURE / COLOUR", textures);
      textures.addEventListener("change", () =>
        apply({
          [slot.type]: [
            {
              id: slot.id,
              drawable: slot.drawable,
              texture: Number(textures.value),
              palette: slot.palette || 0,
            },
          ],
        }),
      );
      const hint = document.createElement("p");
      hint.className = "scene-hint";
      hint.textContent =
        (slot.drawable < 0
          ? "Accessory removed. "
          : "Variation " + (slot.drawable + 1) + " / " + slot.count + ". ") +
        "Changes appear directly on the ped. Clothing combinations depend on the model.";
      body.appendChild(hint);
      if (options.freemode) {
        const details = document.createElement("details");
        details.className = "inspector-group";
        const summary = document.createElement("summary");
        summary.textContent = "Face & colours";
        details.appendChild(summary);
        body.appendChild(details);
        const numeric = (label, value, min, max, step, change) => {
          const row = document.createElement("label");
          row.className = "scene-label";
          row.textContent = label;
          const input = document.createElement("input");
          Object.assign(input, {
            type: "number",
            min: String(min),
            max: String(max),
            step: String(step),
            value: String(value),
          });
          input.setAttribute("aria-label", label);
          input.addEventListener("change", () => {
            const v = Number(input.value);
            if (Number.isFinite(v) && v >= min && v <= max) change(v);
            else showStatus("Choose an available value.");
          });
          row.appendChild(input);
          details.appendChild(row);
        };
        if (options.hair)
          for (const [index, label] of [
            [0, "HAIR COLOUR"],
            [1, "HIGHLIGHT COLOUR"],
          ])
            numeric(label, options.hair[index], 0, 63, 1, (v) => {
              const hair = [...options.hair];
              hair[index] = v;
              apply({ hair });
            });
        if (options.eye !== undefined)
          numeric("EYE COLOUR", options.eye, 0, 31, 1, (v) =>
            apply({ eye: v }),
          );
        const features = [
          "Nose width",
          "Nose peak",
          "Nose length",
          "Nose bone",
          "Nose tip",
          "Nose twist",
          "Brow height",
          "Brow depth",
          "Cheek height",
          "Cheek size",
          "Cheek width",
          "Eye opening",
          "Lip thickness",
          "Jaw width",
          "Jaw shape",
          "Chin height",
          "Chin length",
          "Chin shape",
          "Chin cleft",
          "Neck thickness",
        ];
        for (const feature of options.face || [])
          numeric(features[feature.id], feature.value, -1, 1, 0.05, (v) =>
            apply({ face: [{ id: feature.id, value: v }] }),
          );
      }
    } else {
      for (const name of ["primary", "secondary"]) {
        const rgb = actor.appearance?.[name] || options[name];
        const hex = rgb
          ? "#" +
            rgb.map((v) => Number(v).toString(16).padStart(2, "0")).join("")
          : "";
        const input = document.createElement("input");
        input.type = "text";
        input.value = hex.toUpperCase();
        input.maxLength = 7;
        input.placeholder = "Original paint - choose a custom colour";
        input.setAttribute("aria-label", name + " paint hex colour");
        const applyHex = (value) => {
          if (!/^#[0-9a-f]{6}$/i.test(value))
            return showStatus("Use a colour such as #28B8F4.");
          apply({
            [name]: [1, 3, 5].map((i) => parseInt(value.slice(i, i + 2), 16)),
          });
        };
        input.addEventListener("change", () => applyHex(input.value.trim()));
        field(name.toUpperCase() + " PAINT (HEX)", input);
        const swatches = document.createElement("div");
        swatches.className = "appearance-swatches";
        for (const [colour, label] of [
          ["#28B8F4", "Vanta cyan"],
          ["#1754DC", "Vanta blue"],
          ["#091526", "Navy"],
          ["#111111", "Black"],
          ["#FFFFFF", "White"],
          ["#AF1F2D", "Red"],
          ["#D4B86A", "Gold"],
          ["#647568", "Green"],
        ]) {
          const b = document.createElement("button");
          b.style.backgroundColor = colour;
          b.title = label;
          b.setAttribute("aria-label", name + " paint " + label);
          b.addEventListener("click", () => applyHex(colour));
          swatches.appendChild(b);
        }
        body.appendChild(swatches);
      }
      for (const [key, count, label] of [
        ["livery", options.liveries, "LIVERY"],
        ["modLivery", options.modLiveries, "MOD LIVERY"],
      ])
        if (count > 0) {
          const el = select(
            [
              [-1, "Standard"],
              ...Array.from({ length: count }, (_, i) => [
                i,
                "Livery " + (i + 1),
              ]),
            ],
            options[key],
          );
          field(label, el);
          el.addEventListener("change", () =>
            apply({ [key]: Number(el.value) }),
          );
        }
      for (const extra of options.extras || []) {
        const row = document.createElement("label");
        row.className = "ped-auto-duration";
        const check = document.createElement("input");
        check.type = "checkbox";
        check.checked = extra.enabled;
        row.appendChild(check);
        const text = document.createElement("span");
        text.textContent = "Extra " + extra.id;
        row.appendChild(text);
        body.appendChild(row);
        check.addEventListener("change", () =>
          apply({ extras: [{ id: extra.id, enabled: check.checked }] }),
        );
      }
      if (options.mods?.length) {
        const mods = options.mods;
        if (!mods.some((v) => "mod:" + v.id === selectedSlot))
          selectedSlot = "mod:" + mods[0].id;
        const mod = mods.find((v) => "mod:" + v.id === selectedSlot);
        const category = select(
          mods.map((v) => ["mod:" + v.id, v.name]),
          selectedSlot,
        );
        field("CUSTOMIZATION", category);
        category.addEventListener("change", () => {
          selectedSlot = category.value;
          paint();
        });
        const variation = select(
          [
            [-1, "Stock"],
            ...Array.from({ length: mod.count }, (_, i) => [
              i,
              "Option " + (i + 1),
            ]),
          ],
          mod.index,
        );
        field("MODIFICATION", variation);
        variation.addEventListener("change", () =>
          apply({
            mods: [
              {
                id: mod.id,
                index: Number(variation.value),
                custom: mod.custom,
              },
            ],
          }),
        );
      }
      if (options.wheelType !== undefined) {
        const wheel = select(
          [
            "Sport",
            "Muscle",
            "Lowrider",
            "SUV",
            "Off road",
            "Tuner",
            "Bike",
            "High end",
            "Benny original",
            "Benny bespoke",
            "Open wheel",
            "Street",
            "Track",
          ].map((v, i) => [i, v]),
          options.wheelType,
        );
        field("WHEEL FAMILY", wheel);
        wheel.addEventListener("change", () =>
          apply({
            wheelType: Number(wheel.value),
            mods: [
              { id: 23, index: -1 },
              { id: 24, index: -1 },
            ],
          }),
        );
      }
      if (options.tint !== undefined) {
        const tint = select(
          [
            [-1, "Original"],
            [0, "None"],
            [1, "Pure black"],
            [2, "Dark smoke"],
            [3, "Light smoke"],
            [4, "Stock"],
            [5, "Limo"],
            [6, "Green"],
          ],
          options.tint,
        );
        field("WINDOW TINT", tint);
        tint.addEventListener("change", () =>
          apply({ tint: Number(tint.value) }),
        );
      }
      if (options.plate !== undefined) {
        const plate = document.createElement("input");
        plate.value = options.plate;
        plate.maxLength = 8;
        plate.setAttribute("aria-label", "License plate");
        field("LICENSE PLATE", plate);
        plate.addEventListener("change", () =>
          apply({ plate: plate.value.trim().toUpperCase() }),
        );
      }
      for (const toggle of options.toggles || []) {
        const row = document.createElement("label");
        row.className = "ped-auto-duration";
        const input = document.createElement("input");
        input.type = "checkbox";
        input.checked = toggle.enabled;
        row.append(input, document.createTextNode(toggle.name));
        body.appendChild(row);
        input.addEventListener("change", () =>
          apply({ toggles: [{ id: toggle.id, enabled: input.checked }] }),
        );
      }
      const hint = document.createElement("p");
      hint.className = "scene-hint";
      hint.textContent =
        "Paint uses custom RGB colours. Liveries and extras appear only when supported by the vehicle.";
      body.appendChild(hint);
    }
  };
  const load = async () => {
    if (loaded || !panel.open) return;
    loaded = true;
    body.textContent = "Loading available options...";
    const result = await post("getActorAppearance", { id: actor.id });
    if (result.ok) {
      options = result.options;
      paint();
    } else {
      loaded = false;
      body.textContent = result.message || "Could not load appearance.";
    }
  };
  panel.addEventListener("toggle", load);
  if (panel.open) load();
  return panel;
}
const actorRenderCache = new Map();
let inspectorSignature = "";
function placeCached(parent, node, index) {
  if (parent.children[index] !== node) {
    if (parent.insertBefore)
      parent.insertBefore(node, parent.children[index] || null);
    else parent.appendChild(node);
  }
}
function renderActors() {
  renderShotSubjects();
  renderProductionSelectors();
  const list = document.getElementById("actorList");
  const inspector = document.getElementById("actorInspector");
  const targets = JSON.stringify(
    project.actors.map((a) => [
      a.id,
      a.kind,
      a.model,
      a.name,
      a.group,
      a.modelAvailable,
      sceneElementName(a),
    ]),
  );
  const selected =
    project.actors.find((a) => a.id === selectedActorId) || project.actors[0];
  const nextInspectorSignature = JSON.stringify([
    selected,
    targets,
    project.duration,
    modelsLoaded,
    window.VantaPreferences?.language,
  ]);
  const rebuildInspector = nextInspectorSignature !== inspectorSignature;
  if (rebuildInspector) {
    inspector.innerHTML = "";
    inspectorSignature = nextInspectorSignature;
  }
  const present = new Set(project.actors.map((a) => a.id));
  for (const [id, cached] of actorRenderCache)
    if (!present.has(id)) {
      cached.node.remove();
      actorRenderCache.delete(id);
    }
  document.getElementById("actorCount").textContent = String(
    project.actors.length,
  ).padStart(2, "0");
  document
    .getElementById("emptyActors")
    .classList.toggle("is-hidden", project.actors.length > 0);
  document
    .getElementById("actorNote")
    .classList.toggle("is-hidden", project.actors.length === 0);
  root.classList.toggle("empty-timeline", project.actors.length === 0);
  root.classList.toggle("few-tracks", project.actors.length === 1);
  inspector.classList.toggle("empty-inspector", project.actors.length === 0);
  if (project.actors.length === 0) {
    document.getElementById("actorPins").innerHTML = "";
    actorPinElements.clear();
  }
  if (
    project.actors.length &&
    !project.actors.some((actor) => actor.id === selectedActorId)
  ) {
    selectedActorId = project.actors[0].id;
    if (bridgeReady) post("selectActor", { id: selectedActorId });
  }
  project.actors.forEach((actor, actorIndex) => {
    const selected = actor.id === selectedActorId;
    const signature = JSON.stringify([
      selected,
      selected
        ? actor
        : [
            actor.id,
            actor.kind,
            actor.model,
            actor.name,
            actor.group,
            actor.modelAvailable,
            sceneElementName(actor),
          ],
      selected ? targets : null,
      selected ? project.duration : null,
      modelsLoaded,
    ]);
    const cached = actorRenderCache.get(actor.id);
    if (cached?.signature === signature && (!selected || !rebuildInspector)) {
      placeCached(list, cached.node, actorIndex);
      return;
    }
    if (cached) cached.node.remove();
    const card = document.createElement("div");
    card.className = "actor-card";
    card.actorId = actor.id;
    if (actor.id === selectedActorId) card.classList.add("selected");
    const header = document.createElement("header");
    const label = document.createElement("strong");
    label.textContent = sceneElementName(actor);
    if (actor.name) label.dataset.i18nUser = "true";
    const remove = document.createElement("button");
    remove.className = "delete-frame";
    remove.textContent = "×";
    remove.title = "Remove actor";
    remove.addEventListener("click", () =>
      post("deleteActor", { id: actor.id }),
    );
    header.appendChild(label);
    header.appendChild(remove);
    const coordinates = document.createElement("small");
    coordinates.textContent = `${actorLabel(actor.kind)} ${String(actor.id).padStart(2, "0")}`;
    card.title = actor.model;
    card.classList.add(`scene-element-${actor.kind}`);
    const icon = document.createElement("span");
    icon.className = "actor-type-icon";
    icon.setAttribute("aria-hidden", "true");
    const paths = {
      ped: '<circle cx="12" cy="7" r="3"/><path d="M6 21v-5a6 6 0 0 1 12 0v5"/>',
      vehicle:
        '<path d="m5 9 2-5h10l2 5M4 10h16v9H4zM7 19v2m10-2v2M7 14h2m6 0h2"/>',
      prop: '<path d="m12 3 8 4v10l-8 4-8-4V7zm0 8 8-4m-8 4L4 7m8 4v10"/>',
    };
    icon.innerHTML =
      '<svg viewBox="0 0 24 24">' +
      (paths[actor.kind] || paths.prop) +
      "</svg>";
    if (actor.modelAvailable === false) {
      coordinates.textContent += " · Model unavailable";
      card.title += " · Install the model and reload this project";
    }
    if (!selected) {
      card.appendChild(header);
      card.appendChild(coordinates);
      card.appendChild(icon);
      card.addEventListener("click", (event) => {
        if (event.target.closest(".delete-frame")) return;
        selectedActorId = actor.id;
        post("selectActor", { id: actor.id });
        renderActors();
      });
      actorRenderCache.set(actor.id, { node: card, signature });
      placeCached(list, card, actorIndex);
      return;
    }
    const transform = document.createElement("div");
    transform.className = "actor-transform";
    const inputs = {};
    for (const [field, title] of [
      ["x", "X"],
      ["y", "Y"],
      ["z", "Z"],
      ["heading", "Heading"],
    ]) {
      const wrapper = document.createElement("label");
      wrapper.textContent = title;
      const input = document.createElement("input");
      input.type = "number";
      input.step = field === "heading" ? "1" : "0.05";
      input.value = Number(actor[field]).toFixed(field === "heading" ? 1 : 2);
      inputs[field] = input;
      wrapper.appendChild(input);
      transform.appendChild(wrapper);
    }
    const updateTransform = async (aim) => {
      const data = { id: actor.id, aim };
      for (const field of ["x", "y", "z", "heading"]) {
        data[field] = Number(inputs[field].value);
        if (!Number.isFinite(data[field]))
          return showStatus("Invalid coordinates.");
      }
      const result = await post("setActorTransform", data);
      if (!result.ok) showStatus(result.message || "Could not move actor.");
    };
    for (const input of Object.values(inputs))
      input.addEventListener("change", () => updateTransform(false));
    const aimButton = document.createElement("button");
    aimButton.className = "aim-button";
    aimButton.textContent = "Place at camera aim";
    aimButton.addEventListener("click", () => updateTransform(true));
    const controls = document.createElement("div");
    controls.className = "actor-controls";
    const movementField = document.createElement("label");
    movementField.className = "scene-label";
    movementField.textContent = "MOVE DURATION (SEC)";
    const movementDuration = document.createElement("input");
    movementDuration.type = "number";
    movementDuration.min = "0.1";
    movementDuration.max = String(project.duration);
    movementDuration.step = "0.1";
    movementDuration.value = "3";
    movementField.appendChild(movementDuration);
    const gait = document.createElement("select");
    const automaticDuration = document.createElement("input");
    if (actor.kind === "ped") {
      const gaitField = document.createElement("label");
      gaitField.className = "scene-label ped-gait-field";
      gaitField.textContent = "MOVEMENT STYLE";
      for (const [value, name] of [
        ["auto", "Auto (duration)"],
        ["walk", "Walk"],
        ["run", "Run"],
        ["sprint", "Sprint"],
      ]) {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = name;
        gait.appendChild(option);
      }
      gait.value = "auto";
      gaitField.appendChild(gait);
      controls.appendChild(gaitField);
      const automaticField = document.createElement("label");
      automaticField.className = "ped-auto-duration";
      automaticDuration.type = "checkbox";
      automaticDuration.checked = true;
      automaticField.appendChild(automaticDuration);
      const text = document.createElement("span");
      text.textContent = "Calculate duration from distance";
      automaticField.appendChild(text);
      controls.appendChild(automaticField);
      const updateDurationMode = () => {
        automaticDuration.disabled = gait.value === "auto";
        movementDuration.disabled =
          gait.value !== "auto" && automaticDuration.checked;
      };
      gait.addEventListener("change", updateDurationMode);
      automaticDuration.addEventListener("change", updateDurationMode);
      updateDurationMode();
    }
    const move = document.createElement("button");
    move.className = "free-move-action";
    move.textContent = "Déplacer vers le point visé";
    move.title = "At the playhead, move to the camera aim";
    move.addEventListener("click", async () => {
      const duration = Number(movementDuration.value);
      if (!Number.isFinite(duration) || duration <= 0)
        return showStatus("Enter a valid movement duration.");
      const result = await post("addAction", {
        id: actor.id,
        type: "move",
        duration,
        ...(actor.kind === "ped"
          ? { gait: gait.value, autoDuration: automaticDuration.checked }
          : {}),
      });
      if (!result.ok) showStatus(result.message || "Could not add movement.");
    });
    controls.appendChild(movementField);
    controls.appendChild(move);
    const movementNodes = new Set(controls.children);
    if (actor.kind === "ped") {
      const gazePanel = document.createElement("details");
      gazePanel.className = "animation-panel ped-gaze-panel";
      const gazeSummary = document.createElement("summary");
      gazeSummary.textContent = "Look at a subject";
      gazePanel.appendChild(gazeSummary);
      const targetField = document.createElement("label");
      targetField.className = "scene-label";
      targetField.textContent = "TARGET";
      const target = document.createElement("select");
      const point = document.createElement("option");
      point.value = "";
      point.textContent = "Point at camera aim";
      target.appendChild(point);
      project.actors
        .filter((item) => item.id !== actor.id)
        .forEach((item) => {
          const option = document.createElement("option");
          option.value = item.id;
          option.textContent = `${actorLabel(item.kind)} ${item.id} · ${item.model}`;
          target.appendChild(option);
        });
      target.value = "";
      targetField.appendChild(target);
      gazePanel.appendChild(targetField);
      const gazeField = document.createElement("label");
      gazeField.className = "scene-label";
      gazeField.textContent = "LOOK DURATION (SEC)";
      const gazeDuration = document.createElement("input");
      gazeDuration.type = "number";
      gazeDuration.min = ".1";
      gazeDuration.max = project.duration;
      gazeDuration.step = ".1";
      gazeDuration.value = "3";
      gazeField.appendChild(gazeDuration);
      gazePanel.appendChild(gazeField);
      const gazeButton = document.createElement("button");
      gazeButton.textContent = "Add gaze at playhead";
      gazeButton.addEventListener("click", async () => {
        const seconds = Number(gazeDuration.value);
        if (!Number.isFinite(seconds) || seconds <= 0)
          return showStatus("Enter a valid gaze duration.");
        const result = await post("addAction", {
          id: actor.id,
          type: "lookAt",
          duration: seconds,
          ...(target.value ? { targetId: Number(target.value) } : {}),
        });
        if (!result.ok) showStatus(result.message || "Could not add gaze.");
      });
      gazePanel.appendChild(gazeButton);
      controls.appendChild(gazePanel);
      const browse = document.createElement("button");
      browse.className = "browse-animation";
      browse.type = "button";
      browse.textContent = "Browse animations";
      browse.addEventListener("click", () => openAnimationCatalog(actor.id));
      controls.appendChild(browse);
      const animationPanel = document.createElement("details");
      animationPanel.className = "animation-panel";
      const summary = document.createElement("summary");
      summary.textContent = "Custom animation (advanced)";
      animationPanel.appendChild(summary);
      const dictInput = document.createElement("input");
      dictInput.type = "text";
      dictInput.placeholder = "Animation dictionary";
      dictInput.value = "amb@world_human_hang_out_street@male_b@idle_a";
      const clipInput = document.createElement("input");
      clipInput.type = "text";
      clipInput.placeholder = "Animation clip";
      clipInput.value = "idle_b";
      const animationSeconds = document.createElement("input");
      animationSeconds.type = "number";
      animationSeconds.min = "0";
      animationSeconds.max = String(project.duration);
      animationSeconds.step = ".1";
      animationSeconds.value = "0";
      const animationDurationField = document.createElement("label");
      animationDurationField.className = "scene-label";
      animationDurationField.textContent =
        "DURATION (SEC) · 0 = UNTIL REPLACED";
      animationDurationField.appendChild(animationSeconds);
      const animate = document.createElement("button");
      animate.textContent = "Add animation at playhead";
      animate.addEventListener("click", async () => {
        const result = await post("addAction", {
          id: actor.id,
          type: "animation",
          dict: dictInput.value.trim(),
          clip: clipInput.value.trim(),
          duration: Number(animationSeconds.value) || undefined,
        });
        if (!result.ok)
          showStatus(result.message || "Impossible d’ajouter l’animation.");
      });
      animationPanel.appendChild(dictInput);
      animationPanel.appendChild(clipInput);
      animationPanel.appendChild(animationDurationField);
      animationPanel.appendChild(animate);
      controls.appendChild(animationPanel);
    } else if (actor.kind === "prop") {
      for (const [visible, label] of [
        [true, "Show at playhead"],
        [false, "Hide at playhead"],
      ]) {
        const button = document.createElement("button");
        button.className = visible ? "visibility-show" : "visibility-hide";
        button.type = "button";
        button.textContent = actor.attachment
          ? visible
            ? "Wear at playhead"
            : "Remove at playhead"
          : label;
        button.addEventListener("click", async () => {
          const result = await post("addAction", {
            id: actor.id,
            type: "visibility",
            visible,
          });
          if (!result.ok)
            showStatus(result.message || "Could not change object visibility.");
        });
        controls.appendChild(button);
      }
    } else if (actor.kind === "vehicle") {
      const vehicleCue = (type, enabled, label, door) => {
        const button = document.createElement("button");
        button.className = enabled ? "vehicle-cue-on" : "vehicle-cue-off";
        button.type = "button";
        button.textContent = label;
        button.addEventListener("click", async () => {
          const result = await post("addAction", {
            id: actor.id,
            type,
            enabled,
            ...(door === undefined ? {} : { door: Number(door.value) }),
          });
          if (!result.ok)
            showStatus(result.message || "Could not add vehicle action.");
        });
        controls.appendChild(button);
      };
      vehicleCue("engine", true, "Start engine");
      vehicleCue("engine", false, "Stop engine");
      vehicleCue("lights", true, "Lights on");
      vehicleCue("lights", false, "Lights off");
      const doorField = document.createElement("label");
      doorField.className = "scene-label vehicle-door-field";
      doorField.textContent = "DOOR";
      const doorSelect = document.createElement("select");
      for (const [index, name] of [
        "Driver front",
        "Driver rear",
        "Passenger front",
        "Passenger rear",
        "Hood",
        "Trunk",
      ].entries()) {
        const option = document.createElement("option");
        option.value = String(index);
        option.textContent = name;
        doorSelect.appendChild(option);
      }
      doorField.appendChild(doorSelect);
      controls.appendChild(doorField);
      vehicleCue("door", true, "Open door", doorSelect);
      vehicleCue("door", false, "Close door", doorSelect);
    }
    card.appendChild(header);
    card.appendChild(coordinates);
    if (
      !actor.attachment &&
      !actor.actions?.some((clip) => clip.type === "recording")
    ) {
      card.appendChild(transform);
      card.appendChild(aimButton);
    }
    card.appendChild(controls);
    card.appendChild(icon);
    (actor.actions || []).forEach((action, index) => {
      const row = document.createElement("div");
      row.className = "action-row";
      row.textContent = `${formatTime(action.time)} · ${actionLabel(action)}`;
      const deleteAction = document.createElement("button");
      deleteAction.className = "delete-frame";
      deleteAction.textContent = "×";
      deleteAction.title = "Delete action";
      deleteAction.addEventListener("click", () =>
        post("deleteAction", { id: actor.id, index: index + 1 }),
      );
      if (
        action.type === "move" &&
        (actor.kind === "ped" || actor.kind === "vehicle")
      ) {
        const edit = document.createElement("button");
        edit.textContent = "Edit route";
        edit.className = "route-edit-action";
        edit.addEventListener("click", () =>
          window.VantaRouteEditor?.open(actor, action),
        );
        row.appendChild(edit);
      }
      row.appendChild(deleteAction);
      card.appendChild(row);
    });
    actorRenderCache.set(actor.id, { node: card, signature });
    placeCached(list, card, actorIndex);
    card.addEventListener("click", (event) => {
      if (event.target.closest(".delete-frame")) return;
      if (selectedActorId === actor.id) return;
      selectedActorId = actor.id;
      post("selectActor", { id: actor.id });
      renderActors();
    });
    if (actor.id === selectedActorId) {
      const position = inspectorGroup(actor, "Position", true);
      position.appendChild(transform);
      const placement = document.createElement("div");
      placement.className = "inspector-placement";
      placement.appendChild(aimButton);
      position.appendChild(placement);
      const recordedTake = actor.actions?.find(
        (clip) => clip.type === "recording",
      );
      if (!actor.attachment && !recordedTake) inspector.appendChild(position);

      if (actor.kind === "ped" || actor.kind === "vehicle")
        inspector.appendChild(appearancePanel(actor));
      const movement = inspectorGroup(actor, "Movement", true);
      const movementControls = document.createElement("div");
      movementControls.className = "actor-controls movement-controls";
      const actionControls = document.createElement("div");
      actionControls.className = "actor-controls action-controls";
      for (const element of [...controls.children]) {
        const isMovement = movementNodes.has(element);
        (isMovement ? movementControls : actionControls).appendChild(element);
      }
      movement.appendChild(movementControls);
      if (!actor.attachment && !recordedTake) inspector.appendChild(movement);
      if (recordedTake) {
        const take = inspectorGroup(actor, "Recorded take", true);
        const input = document.createElement("input");
        input.type = "number";
        input.min = "0";
        input.max = String(
          Math.max(0, project.duration - recordedTake.duration),
        );
        input.step = ".1";
        input.value = String(recordedTake.time);
        const label = document.createElement("label");
        label.className = "scene-label";
        label.textContent = "START TIME (SEC)";
        label.appendChild(input);
        take.appendChild(label);
        input.addEventListener("change", async () => {
          const r = await post("moveAction", {
            actorId: actor.id,
            actionId: recordedTake.id,
            time: Number(input.value),
          });
          if (!r.ok) showStatus(r.message || "Could not move take.");
        });
        const note = document.createElement("p");
        note.className = "scene-hint";
        note.textContent =
          Number(recordedTake.duration).toFixed(1) +
          " sec · " +
          recordedTake.samples.length +
          " captured poses. Add camera keyframes or track this actor to film another angle.";
        take.appendChild(note);
        inspector.appendChild(take);
      }
      const actions = inspectorGroup(actor, "Actions", false);
      actions.appendChild(actionControls);
      if (!recordedTake) inspector.appendChild(actions);
      const rows = [...card.children].filter((element) =>
        element.classList.contains("action-row"),
      );
      if (rows.length) {
        const scheduled = inspectorGroup(
          actor,
          "Scheduled actions (" + rows.length + ")",
          true,
        );
        for (const row of rows) scheduled.appendChild(row);
        if (position.parentNode === inspector)
          inspector.insertBefore(scheduled, position.nextSibling);
        else inspector.appendChild(scheduled);
      }
    }
  });
  if (!project.actors.length)
    inspector.textContent =
      "Place a ped, vehicle or object to inspect it here.";
  if (sceneTabActive) renderInspectorMode();
  renderTimelineTracks();
  updateContextControls();
  window.VantaPolish?.render();
  window.VantaWorkflow?.render();
}

function renderInspectorMode() {
  document
    .getElementById("cameraInspector")
    .classList.toggle("is-hidden", sceneTabActive || lookTabActive);
  document
    .getElementById("actorInspector")
    .classList.toggle("is-hidden", !sceneTabActive);
  const actor = project.actors.find((item) => item.id === selectedActorId);
  if (sceneTabActive) {
    document.getElementById("inspectorEyebrow").textContent = actor
      ? `${actorLabel(actor.kind)} ${String(actor.id).padStart(2, "0")} / INSPECTOR`
      : "INSPECTOR";
    document.getElementById("inspectorTitle").textContent = actor
      ? sceneElementName(actor)
      : "Scene";
    document
      .getElementById("inspectorTitle")
      .toggleAttribute("data-i18n-user", Boolean(actor?.name));
    document.getElementById("liveTag").classList.add("is-hidden");
  }
}

function renderActorPins(positions) {
  const container = document.getElementById("actorPins");
  const visible = new Set();
  positions.forEach((position) => {
    visible.add(position.id);
    let pin = actorPinElements.get(position.id);
    if (!pin) {
      pin = document.createElement("div");
      pin.className = "actor-pin";
      const label = document.createElement("span");
      label.textContent = `${position.kind === "vehicle" ? "VEHICLE" : actorLabel(position.kind, true)} ${position.id}`;
      const rotate = document.createElement("button");
      rotate.className = "rotate-grip";
      rotate.type = "button";
      rotate.textContent = "↻";
      rotate.title = "Drag to rotate";
      rotate.addEventListener("mousedown", (event) =>
        startActorDrag(event, position.id, "rotate"),
      );
      pin.appendChild(label);
      pin.appendChild(rotate);
      container.appendChild(pin);
      actorPinElements.set(position.id, pin);
    }
    pin.style.left = `${position.x * 100}%`;
    setText(
      pin.children[0],
      `${position.kind === "vehicle" ? "VEHICLE" : actorLabel(position.kind, true)} ${position.id}`,
    );
    pin.style.top = `${position.y * 100}%`;
    if (position.id === selectedActorId) pin.classList.add("selected");
    else pin.classList.remove("selected");
  });
  for (const [id, pin] of actorPinElements) {
    if (!visible.has(id)) {
      pin.remove();
      actorPinElements.delete(id);
    }
  }
  for (const card of document.getElementById("actorList").children) {
    if (card.actorId === selectedActorId) card.classList.add("selected");
    else card.classList.remove("selected");
  }
}

const trackRenderCache = new Map();
function renderTimelineTracks() {
  const present = new Set(project.actors.map((a) => a.id));
  for (const [id, cached] of trackRenderCache)
    if (!present.has(id)) {
      cached.node.remove();
      trackRenderCache.delete(id);
    }
  let denseTimeline = false;
  project.actors.forEach((actor, actorIndex) => {
    const signature = JSON.stringify([
      actor.id,
      actor.kind,
      actor.model,
      actor.actions,
      project.duration,
    ]);
    const cached = trackRenderCache.get(actor.id);
    if (cached?.signature === signature) {
      placeCached(actorTracks, cached.node, actorIndex);
      denseTimeline ||= cached.dense;
      for (const [marker, key] of cached.markers)
        marker.classList.toggle("selected", timelineSelection.has(key));
      return;
    }
    if (cached) cached.node.remove();
    const track = document.createElement("div");
    track.className = "track-area";
    const label = document.createElement("div");
    label.className = "track-name";
    label.textContent = `${actorLabel(actor.kind, true)} ${actor.id}`;
    label.title = actor.model;
    const lane = document.createElement("div");
    lane.className = "track-lane";
    lane.addEventListener("mousedown", (event) => {
      if (event.target === lane) beginSeekDrag(event, lane);
    });
    const markerEntries = [];
    const cueStacks = new Map();
    let deepestStack = 1;
    (actor.actions || []).forEach((action) => {
      const marker = document.createElement("button");
      marker.className = `timeline-action ${action.type}${action.type === "visibility" ? (action.visible ? " show" : " hide") : ""}`;
      marker.classList.toggle(
        "selected",
        timelineSelection.has(
          selectionKey({
            kind: "action",
            actorId: actor.id,
            actionId: action.id,
          }),
        ),
      );
      marker.style.left = `${(action.time / project.duration) * 100}%`;
      const stackKey = Number(action.time).toFixed(1);
      const stack = cueStacks.get(stackKey) || 0;
      cueStacks.set(stackKey, stack + 1);
      deepestStack = Math.max(deepestStack, stack + 1);
      if (stack) marker.style.top = `${5 + stack * 20}px`;
      marker.title = `${actionLabel(action)} · ${formatTime(action.time)} · drag to retime`;
      if (
        action.type === "move" ||
        action.type === "lookAt" ||
        action.type === "enterVehicle" ||
        action.type === "exitVehicle" ||
        action.type === "recording" ||
        (action.type === "animation" && action.duration)
      ) {
        marker.style.width = `${Math.max(1, (action.duration / project.duration) * 100)}%`;
        marker.textContent =
          action.type === "animation"
            ? "ANIM"
            : action.type === "recording"
              ? "RECORD"
              : action.type === "enterVehicle"
                ? "ENTER"
                : action.type === "exitVehicle"
                  ? "EXIT"
                  : action.type === "lookAt"
                    ? "LOOK"
                    : action.points
                      ? "ROUTE"
                      : action.gait && action.gait !== "auto"
                        ? action.gait.toUpperCase()
                        : "MOVE";
      } else if (action.type === "visibility") {
        marker.textContent = action.visible ? "SHOW" : "HIDE";
      } else if (
        action.type === "engine" ||
        action.type === "lights" ||
        action.type === "door"
      ) {
        marker.textContent =
          action.type === "engine"
            ? "ENGINE"
            : action.type === "lights"
              ? "LIGHTS"
              : "DOOR";
      }
      marker.addEventListener("mousedown", (event) =>
        beginTimelineDrag(event, marker, lane, {
          kind: "action",
          actorId: actor.id,
          actionId: action.id,
          time: action.time,
          maxTime:
            action.type === "move" ||
            action.type === "lookAt" ||
            action.type === "recording" ||
            (action.type === "animation" && action.duration)
              ? Math.max(0, project.duration - action.duration)
              : project.duration,
        }),
      );
      markerEntries.push([
        marker,
        selectionKey({
          kind: "action",
          actorId: actor.id,
          actionId: action.id,
        }),
      ]);
      lane.appendChild(marker);
    });
    if (deepestStack > 1) {
      lane.style.height = `${10 + deepestStack * 20}px`;
      track.style.height = `${26 + deepestStack * 20}px`;
    }
    if (deepestStack > 2) denseTimeline = true;
    track.appendChild(label);
    track.appendChild(lane);
    trackRenderCache.set(actor.id, {
      node: track,
      signature,
      dense: deepestStack > 2,
      markers: markerEntries,
    });
    placeCached(actorTracks, track, actorIndex);
  });
  root.classList.toggle("dense-timeline", denseTimeline);
}

function timeFromPointer(clientX, lane, maximum = project.duration) {
  const bounds = lane.getBoundingClientRect();
  const value = Math.max(
    0,
    Math.min(
      maximum,
      ((clientX - bounds.left) / bounds.width) * project.duration,
    ),
  );
  const step =
    window.VantaPreferences?.snap === false
      ? 0.01
      : window.VantaPreferences?.interval || 0.1;
  return Math.min(maximum, Math.round(value / step) * step);
}

function beginTimelineDrag(event, marker, lane, item) {
  if (event.button !== 0) return;
  event.preventDefault();
  event.stopPropagation();
  if (event.ctrlKey || event.metaKey) {
    const key = selectionKey(item);
    if (timelineSelection.has(key)) timelineSelection.delete(key);
    else timelineSelection.set(key, item);
    marker.classList.toggle("selected", timelineSelection.has(key));
    updateTimelineSelection();
    return;
  }
  timelineDrag = {
    marker,
    lane,
    item,
    startX: event.clientX,
    time: item.time,
    moved: false,
    edge: event.target.closest("[data-edge]")?.dataset.edge,
  };
  if (timelineDrag.edge)
    timelineDrag.original = { time: item.time, duration: item.duration };
  marker.classList.add("selected");
}

function beginSeekDrag(event, lane) {
  if (event.button !== 0) return;
  event.preventDefault();
  timelineDrag = {
    lane,
    seek: true,
    time: timeFromPointer(event.clientX, lane),
  };
  seek(timelineDrag.time);
}

window.addEventListener("mousemove", (event) => {
  if (!timelineDrag) return;
  if (!(event.buttons & 1)) return;
  const drag = timelineDrag;
  const maximum = drag.item
    ? (drag.item.maxTime ?? project.duration)
    : project.duration;
  drag.time = timeFromPointer(event.clientX, drag.lane, maximum);
  if (drag.seek) {
    const now = performance.now();
    if (now - lastDragSeekAt >= 40) {
      lastDragSeekAt = now;
      seek(drag.time);
    }
  } else {
    drag.moved ||= Math.abs(event.clientX - drag.startX) > 3;
    if (drag.edge) {
      const end = drag.original.time + drag.original.duration;
      if (drag.edge === "start") {
        drag.time = Math.min(end - 0.1, drag.time);
        drag.item.duration = end - drag.time;
      } else {
        drag.item.duration = Math.max(
          0.1,
          timeFromPointer(event.clientX, drag.lane) - drag.original.time,
        );
        drag.time = drag.original.time;
      }
      drag.marker.style.width =
        (drag.item.duration / project.duration) * 100 + "%";
    }
    drag.marker.style.left = `${(drag.time / project.duration) * 100}%`;
    renderPlayhead(drag.time);
  }
});

window.addEventListener("mouseup", async (event) => {
  if (!timelineDrag || event.button !== 0) return;
  const drag = timelineDrag;
  timelineDrag = null;
  if (drag.seek) return seek(drag.time);
  drag.marker.classList.remove("selected");
  if (!drag.moved) {
    if (drag.item.kind === "shot")
      return post("selectCameraShot", { id: drag.item.id });
    if (drag.item.kind === "camera")
      return selectCameraFrame(drag.item.index - 1);
    selectedActorId = drag.item.actorId;
    post("selectActor", { id: selectedActorId });
    selectSceneTab(true);
    return seek(drag.item.time);
  }
  const result =
    drag.item.kind === "shot"
      ? await post("updateCameraShot", {
          id: drag.item.id,
          time: drag.time,
          duration: drag.item.duration,
        })
      : drag.item.kind === "camera"
        ? await post("moveKeyframe", {
            index: drag.item.index,
            time: drag.time,
          })
        : await post("moveAction", {
            actorId: drag.item.actorId,
            actionId: drag.item.actionId,
            time: drag.time,
          });
  if (!result.ok) {
    showStatus(result.message || "Could not move timeline item.");
    renderProject();
  } else {
    if (drag.item.kind === "camera") {
      selectedFrameTime = drag.time;
      renderProject();
    }
    seek(drag.time);
  }
});

function selectSceneTab(scene) {
  window.VantaWorkflow?.tab(scene);
  lookTabActive = scene === "look";
  sceneTabActive = scene === true;
  if (scene && selectedFrameTime !== null) {
    selectedFrameTime = null;
    for (const row of keyframeList.children) row.classList.remove("selected");
    renderCamera();
  }
  document
    .getElementById("actorsPane")
    .classList.toggle("is-hidden", !sceneTabActive);
  document
    .getElementById("cameraPane")
    .classList.toggle("is-hidden", sceneTabActive);
  document
    .getElementById("lookPane")
    .classList.toggle("is-hidden", !lookTabActive);
  document
    .getElementById("actorsTab")
    .classList.toggle("active", sceneTabActive);
  document
    .getElementById("cameraTab")
    .classList.toggle("active", !sceneTabActive && !lookTabActive);
  document.getElementById("lookTab").classList.toggle("active", lookTabActive);
  if (sceneTabActive) renderActors();
  else if (lookTabActive) {
    renderLook();
    renderCamera();
  } else renderCamera();
  renderInspectorMode();
  window.VantaPolish?.render();
  window.VantaWorkflow?.render();
}

document
  .getElementById("actorsTab")
  .addEventListener("click", () => selectSceneTab(true));
document
  .getElementById("cameraTab")
  .addEventListener("click", () => selectSceneTab(false));
document
  .getElementById("lookTab")
  .addEventListener("click", () => selectSceneTab("look"));
const lookHour = document.getElementById("lookHour");
for (let hour = 0; hour < 24; hour++) {
  const option = document.createElement("option");
  option.value = String(hour);
  option.textContent = `${String(hour).padStart(2, "0")}:00`;
  lookHour.appendChild(option);
}
function renderLook() {
  const look = project.look || {};
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
  document
    .getElementById("lookFocusControls")
    .classList.toggle("is-hidden", look.dof !== true);
  document.getElementById("lookNearValue").textContent =
    `${Number(look.near ?? 2).toFixed(1)} m`;
  document.getElementById("lookFarValue").textContent =
    `${Number(look.far ?? 30).toFixed(0)} m`;
  document.getElementById("lookStrengthValue").textContent =
    `${Math.round(Number(look.strength ?? 0.5) * 100)}%`;
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
    const result = await post("setSceneLook", { field, value });
    if (!result.ok)
      showStatus(result.message || "Could not update scene look.");
  });
}
const modelOverlay = document.getElementById("modelOverlay");
let modelCatalog = [],
  modelsLoaded = false,
  modelKind = "ped",
  modelPage = 0,
  modelSelection = null,
  modelSequence = 0,
  modelReady = false;
const modelPageSize = 60;
let modelFilterKey = null,
  modelMatches = [],
  modelPlacing = false;
function setModelPlacing(value) {
  modelPlacing = value;
  modelOverlay.classList.toggle("placing", value);
  document.getElementById("modelClose").disabled = value;
  document.getElementById("modelPlace").textContent = value
    ? "Placing model…"
    : "Place at camera aim";
}
function setModelLoading(value) {
  modelOverlay.classList.toggle("loading-preview", value);
  for (const id of [
    "modelAngle",
    "modelZoom",
    "modelFront",
    "modelSide",
    "modelFit",
  ])
    document.getElementById(id).disabled = value || !modelReady;
}
let modelDrag = null,
  modelElevation = 12,
  modelViewScheduled = false;
function modelVisibleViewport() {
  const bounds = document
    .getElementById("modelViewport")
    .getBoundingClientRect();
  const width = Math.max(1, window.innerWidth),
    height = Math.max(1, window.innerHeight);
  const left = Math.max(0, Math.min(width, bounds.left)),
    top = Math.max(0, Math.min(height, bounds.top));
  return {
    left: left / width,
    top: top / height,
    width: Math.max(0, Math.min(width, bounds.right) - left) / width,
    height: Math.max(0, Math.min(height, bounds.bottom) - top) / height,
  };
}
function sendModelView() {
  if (modelViewScheduled) return;
  modelViewScheduled = true;
  requestAnimationFrame(() => {
    modelViewScheduled = false;
    if (modelReady && !modelOverlay.classList.contains("is-hidden"))
      post("modelPreviewView", {
        angle: Number(document.getElementById("modelAngle").value),
        zoom: Number(document.getElementById("modelZoom").value),
        elevation: modelElevation,
        viewport: modelVisibleViewport(),
      });
  });
}
function resetModelView(angle = 135) {
  document.getElementById("modelAngle").value = String(angle);
  document.getElementById("modelZoom").value = "1";
  modelElevation = 12;
  sendModelView();
}
const modelViewport = document.getElementById("modelViewport");
// Refit only when layout changes; no per-frame measurements while idle.
const modelViewportObserver =
  typeof ResizeObserver === "function"
    ? new ResizeObserver(() => sendModelView())
    : null;
modelViewportObserver?.observe(modelViewport);
window.addEventListener("resize", sendModelView);
window.addEventListener("beforeunload", () =>
  modelViewportObserver?.disconnect(),
);
modelViewport.addEventListener("mousedown", (event) => {
  if (event.button !== 0 || !modelReady) return;
  event.preventDefault();
  modelDrag = { x: event.clientX, y: event.clientY };
  modelViewport.classList.add("rotating");
});
window.addEventListener("mousemove", (event) => {
  if (!modelDrag || !modelReady) return;
  if (!(event.buttons & 1)) {
    modelDrag = null;
    modelViewport.classList.remove("rotating");
    return;
  }
  const angle = document.getElementById("modelAngle");
  angle.value = String(
    (Number(angle.value) - (event.clientX - modelDrag.x) * 0.45 + 720) % 360,
  );
  modelElevation = Math.max(
    -15,
    Math.min(75, modelElevation + (event.clientY - modelDrag.y) * 0.3),
  );
  modelDrag = { x: event.clientX, y: event.clientY };
  sendModelView();
});
window.addEventListener("mouseup", () => {
  modelDrag = null;
  modelViewport.classList.remove("rotating");
});
modelViewport.addEventListener(
  "wheel",
  (event) => {
    event.preventDefault();
    if (!modelReady) return;
    const zoom = document.getElementById("modelZoom");
    zoom.value = String(
      Math.max(
        0.6,
        Math.min(2.5, Number(zoom.value) * Math.exp(event.deltaY * 0.001)),
      ),
    );
    sendModelView();
  },
  { passive: false },
);
modelViewport.addEventListener("dblclick", () => resetModelView());
document
  .getElementById("modelFit")
  .addEventListener("click", () => resetModelView());
document
  .getElementById("modelFront")
  .addEventListener("click", () => resetModelView(90));
document
  .getElementById("modelSide")
  .addEventListener("click", () => resetModelView(0));

function localizedModelSearch(item) {
  if (item.localizedSearch) return item.localizedSearch;
  const normalize = (value) =>
    String(value)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase();
  return (item.localizedSearch = normalize(
    item.search +
      " " +
      (window.VantaI18n?.searchText(item.category.replaceAll("_", " ")) || "") +
      " " +
      (window.VantaI18n?.searchText(item.label) || ""),
  ));
}
function renderModels() {
  const query = document
    .getElementById("modelSearch")
    .value.trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
  const category = document.getElementById("modelCategory").value;
  const key = `${modelKind}|${category}|${query}`;
  if (modelFilterKey !== key) {
    modelMatches = modelCatalog.filter(
      (item) =>
        item.kind === modelKind &&
        (!category || item.category === category) &&
        (!query || localizedModelSearch(item).includes(query)),
    );
    modelFilterKey = key;
  }
  const matching = modelMatches;
  const pages = Math.max(1, Math.ceil(matching.length / modelPageSize));
  modelPage = Math.min(modelPage, pages - 1);
  const list = document.getElementById("modelResults");
  list.innerHTML = "";
  matching
    .slice(modelPage * modelPageSize, (modelPage + 1) * modelPageSize)
    .forEach((item) => {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "model-result";
      row.modelKey = `${item.kind}:${item.model}`;
      if (
        modelSelection?.model === item.model &&
        modelSelection.kind === item.kind
      )
        row.classList.add("selected");
      const title = document.createElement("strong");
      title.textContent = item.label;
      const detail = document.createElement("small");
      detail.textContent = `${item.model} · ${item.category.replaceAll("_", " ")}`;
      row.appendChild(title);
      row.appendChild(detail);
      row.addEventListener("click", () => selectModel(item));
      list.appendChild(row);
    });
  if (!matching.length) {
    const empty = document.createElement("p");
    empty.textContent = modelsLoaded
      ? "No matching models on this game build."
      : "Checking models available on your game build…";
    list.appendChild(empty);
  }
  document.getElementById("modelCount").textContent = modelsLoaded
    ? `${matching.length.toLocaleString()} models · ${modelPage + 1}/${pages}`
    : "Loading models…";
  document.getElementById("modelPrevious").disabled = modelPage === 0;
  document.getElementById("modelNext").disabled = modelPage >= pages - 1;
  for (const [id, kind] of [
    ["modelsPed", "ped"],
    ["modelsVehicle", "vehicle"],
    ["modelsProp", "prop"],
  ])
    document.getElementById(id).classList.toggle("active", kind === modelKind);
}

function renderModelCategories() {
  const select = document.getElementById("modelCategory");
  const previous = select.value;
  select.innerHTML = "";
  const all = document.createElement("option");
  all.value = "";
  all.textContent = "All categories";
  select.appendChild(all);
  const categories = [
    ...new Set(
      modelCatalog
        .filter((item) => item.kind === modelKind)
        .map((item) => item.category),
    ),
  ].sort();
  categories.forEach((category) => {
    const option = document.createElement("option");
    option.value = category;
    option.textContent = category.replaceAll("_", " ");
    select.appendChild(option);
  });
  select.value = categories.includes(previous) ? previous : "";
}

async function selectModel(item) {
  if (modelPlacing) return;
  modelDrag = null;
  modelElevation = 12;
  modelSelection = item;
  modelReady = false;
  setModelLoading(true);
  const sequence = ++modelSequence;
  document.getElementById("modelName").textContent = item.label;
  document.getElementById("modelCode").textContent = item.model;
  document.getElementById("modelPlace").disabled = true;
  document.getElementById("modelPreviewStatus").textContent =
    "Loading 3D preview…";
  document.getElementById("modelAngle").value = "135";
  document.getElementById("modelZoom").value = "1";
  for (const row of document.getElementById("modelResults").children)
    row.classList.toggle(
      "selected",
      row.modelKey === `${item.kind}:${item.model}`,
    );
  const result = await post("previewModel", {
    kind: item.kind,
    model: item.model,
    viewport: modelVisibleViewport(),
  });
  if (
    sequence !== modelSequence ||
    modelOverlay.classList.contains("is-hidden")
  )
    return;
  modelReady = Boolean(result.ok);
  setModelLoading(false);
  document.getElementById("modelPlace").disabled = !modelReady;
  document.getElementById("modelPreviewStatus").textContent = result.ok
    ? "Drag the model view to rotate. Scroll to zoom. Reset view to fit the whole model."
    : result.message || "Preview unavailable.";
}

async function closeModels(notify = true) {
  if (modelPlacing && notify) return;
  setModelPlacing(false);
  modelReady = false;
  setModelLoading(false);
  modelDrag = null;
  modelViewport.classList.remove("rotating");
  modelSequence++;
  modelReady = false;
  modelOverlay.classList.add("is-hidden");
  root.classList.remove("model-browsing");
  if (notify) await post("closeModelBrowser");
}

document
  .getElementById("browseModelsButton")
  .addEventListener("click", async () => {
    if (!modelOverlay.classList.contains("is-hidden")) return;
    looking = false;
    lookDeltaX = lookDeltaY = 0;
    clearKeys();
    previewPlaying = false;
    selectedFrameTime = null;
    modelOverlay.classList.remove("is-hidden");
    root.classList.add("model-browsing");
    modelSelection = null;
    modelReady = false;
    modelPage = 0;
    const session = ++modelSequence;
    setModelLoading(false);
    document.getElementById("modelName").textContent = "Choose a model";
    document.getElementById("modelCode").textContent = "—";
    document.getElementById("modelPlace").disabled = true;
    document.getElementById("modelPreviewStatus").textContent =
      "The preview is temporary and does not modify your project.";
    renderModelCategories();
    renderModels();
    const result = await post("openModelBrowser");
    if (
      session !== modelSequence ||
      modelOverlay.classList.contains("is-hidden")
    )
      return;
    if (!result.ok) {
      closeModels(false);
      showStatus(result.message);
    }
  });
document
  .getElementById("modelClose")
  .addEventListener("click", () => closeModels());
for (const [id, kind] of [
  ["modelsPed", "ped"],
  ["modelsVehicle", "vehicle"],
  ["modelsProp", "prop"],
])
  document.getElementById(id).addEventListener("click", () => {
    if (modelPlacing || modelKind === kind) return;
    modelSequence++;
    modelSelection = null;
    modelReady = false;
    setModelLoading(false);
    document.getElementById("modelName").textContent = "Choose a model";
    document.getElementById("modelCode").textContent = "—";
    document.getElementById("modelPlace").disabled = true;
    document.getElementById("modelPreviewStatus").textContent =
      "Select a model to preview it in 3D.";
    post("clearModelPreview");
    modelKind = kind;
    modelPage = 0;
    document.getElementById("modelCategory").value = "";
    renderModelCategories();
    renderModels();
  });
document.getElementById("modelSearch").addEventListener("input", () => {
  modelPage = 0;
  renderModels();
});
document.getElementById("modelCategory").addEventListener("change", () => {
  modelPage = 0;
  renderModels();
});
document.getElementById("modelPrevious").addEventListener("click", () => {
  modelPage = Math.max(0, modelPage - 1);
  renderModels();
});
document.getElementById("modelNext").addEventListener("click", () => {
  modelPage++;
  renderModels();
});
for (const id of ["modelAngle", "modelZoom"])
  document.getElementById(id).addEventListener("input", () => {
    sendModelView();
  });
document.getElementById("modelPlace").addEventListener("click", async () => {
  if (!modelReady || !modelSelection || modelPlacing) return;
  setModelPlacing(true);
  const session = modelSequence;
  document.getElementById("modelPlace").disabled = true;
  const result = await post("placeBrowserModel", {
    kind: modelSelection.kind,
    model: modelSelection.model,
  });
  if (session !== modelSequence || !bridgeReady) return;
  await closeModels(false);
  if (!result.ok) showStatus(result.message || "Could not place model.");
  else showStatus("Model placed at your original camera aim.");
});

document.getElementById("actorKind").addEventListener("change", (event) => {
  document.getElementById("actorModel").value =
    event.target.value === "vehicle"
      ? "sultan"
      : event.target.value === "prop"
        ? "prop_tool_box_04"
        : "a_m_y_business_01";
});
document
  .getElementById("addActorButton")
  .addEventListener("click", async () => {
    const result = await post("addActor", {
      kind: document.getElementById("actorKind").value,
      model: document.getElementById("actorModel").value.trim(),
    });
    if (!result.ok) showStatus(result.message || "Could not place actor.");
    else document.getElementById("actorCreate").open = false;
  });

const lookSurface = document.getElementById("lookSurface");
lookSurface.addEventListener("contextmenu", (event) => event.preventDefault());
lookSurface.addEventListener("mousedown", (event) => {
  if (event.button === 2) {
    event.preventDefault();
    looking = true;
    lastMouseX = Number.isFinite(event.clientX) ? event.clientX : null;
    lastMouseY = Number.isFinite(event.clientY) ? event.clientY : null;
    lookSurface.classList.add("looking");
  } else if (event.button === 0) {
    startActorDrag(event, null, event.altKey ? "rotate" : "move");
  }
});

function startActorDrag(event, id, mode) {
  if (event.button !== 0) return;
  event.preventDefault();
  event.stopPropagation();
  leftHeld = true;
  actorDragPointer = {
    x: event.clientX / window.innerWidth,
    y: event.clientY / window.innerHeight,
    heightOnly: event.shiftKey,
  };
  post("beginActorDrag", {
    ...actorDragPointer,
    id,
    mode,
    aspect: window.innerWidth / window.innerHeight,
  }).then(async (result) => {
    if (!result.ok) return;
    selectedActorId = result.id;
    if (!leftHeld) {
      await post("endActorDrag");
      return;
    }
    setLookHint(
      mode === "rotate"
        ? "DRAG LEFT / RIGHT TO ROTATE"
        : "DRAG TO MOVE · HOLD SHIFT FOR HEIGHT",
    );
    actorDragging = true;
    lookSurface.classList.add("dragging-actor");
    queueActorDrag();
  });
}
window.addEventListener("mouseup", (event) => {
  if (event.button === 2) {
    looking = false;
    lastMouseX = lastMouseY = null;
    lookSurface.classList.remove("looking");
  }
  if (event.button === 0 && leftHeld) {
    leftHeld = false;
    const pointer = actorDragPointer;
    const wasDragging = actorDragging;
    actorDragging = false;
    lookSurface.classList.remove("dragging-actor");
    setLookHint(null);
    if (wasDragging) {
      (async () => {
        if (pointer)
          await post("dragActor", {
            ...pointer,
            sequence: ++actorDragSequence,
          });
        await post("endActorDrag");
      })();
    }
  }
});

function queueActorDrag() {
  if (actorDragScheduled || !actorDragging) return;
  actorDragScheduled = true;
  requestAnimationFrame(() => {
    actorDragScheduled = false;
    if (actorDragging && actorDragPointer)
      post("dragActor", { ...actorDragPointer, sequence: ++actorDragSequence });
  });
}

window.addEventListener("mousemove", (event) => {
  if (!leftHeld) return;
  actorDragPointer = {
    x: event.clientX / window.innerWidth,
    y: event.clientY / window.innerHeight,
    heightOnly: event.shiftKey,
  };
  queueActorDrag();
});
window.addEventListener("mousemove", (event) => {
  if (!looking || !(event.buttons & 2)) return;
  const fallbackX = lastMouseX === null ? 0 : event.clientX - lastMouseX;
  const fallbackY = lastMouseY === null ? 0 : event.clientY - lastMouseY;
  lookDeltaX += Number.isFinite(event.movementX) ? event.movementX : fallbackX;
  lookDeltaY += Number.isFinite(event.movementY) ? event.movementY : fallbackY;
  lastMouseX = Number.isFinite(event.clientX) ? event.clientX : null;
  lastMouseY = Number.isFinite(event.clientY) ? event.clientY : null;
  if (!lookScheduled) {
    lookScheduled = true;
    requestAnimationFrame(() => {
      lookScheduled = false;
      const x = lookDeltaX,
        y = lookDeltaY;
      lookDeltaX = lookDeltaY = 0;
      if (x || y) post("mouseLook", { x, y });
    });
  }
});

function setLookHint(message) {
  if (typeof window.VantaViewHint === "function") window.VantaViewHint(message);
  else
    document.getElementById("lookHint").textContent =
      message ||
      "RIGHT DRAG: CAMERA · LEFT DRAG: ACTORS · ALT / ↻: ROTATE · SHIFT: HEIGHT";
}

function setText(element, value) {
  if (!element?.hasAttribute?.("data-i18n-user"))
    value = window.VantaI18n?.t(value) ?? value;
  if (element && element.textContent !== value) element.textContent = value;
}

function renderPlayhead(time) {
  const value = Math.max(0, Math.min(Number(project.duration), time));
  setText(document.getElementById("timeReadout"), formatTime(value));
  if (!scrubbing) scrubber.value = value;
  document.getElementById("playheadLine").style.left =
    `calc(var(--track-label, 108px) + (100% - var(--track-label, 108px)) * ${value / project.duration})`;
}

function animatePlayhead(now) {
  animationScheduled = false;
  if (!previewPlaying || root.classList.contains("is-hidden")) return;
  if (!scrubbing)
    renderPlayhead(playheadAnchorTime + (now - playheadAnchorClock) / 1000);
  animationScheduled = true;
  requestAnimationFrame(animatePlayhead);
}

function renderCamera() {
  const frame = selectedFrame();
  const display = frame || camera;
  const index = frame ? project.keyframes.indexOf(frame) : -1;
  if (!sceneTabActive) {
    setText(document.getElementById("inspectorEyebrow"), "INSPECTOR");
    document
      .getElementById("inspectorTitle")
      .toggleAttribute("data-i18n-user", Boolean(frame?.name));
    setText(
      document.getElementById("inspectorTitle"),
      frame
        ? frame.name || `Shot ${String(index + 1).padStart(2, "0")}`
        : "Live camera",
    );
  }
  document
    .getElementById("selectedCameraCard")
    .classList[frame ? "remove" : "add"]("is-hidden");
  document
    .getElementById("shotNameField")
    .classList[frame ? "remove" : "add"]("is-hidden");
  document
    .getElementById("selectedCameraActions")
    .classList[frame ? "remove" : "add"]("is-hidden");
  document
    .getElementById("liveTag")
    .classList[frame || sceneTabActive ? "add" : "remove"]("is-hidden");
  if (frame) {
    document.getElementById("selectedCameraName").textContent =
      frame.name || `Shot ${String(index + 1).padStart(2, "0")}`;
    document
      .getElementById("selectedCameraName")
      .toggleAttribute("data-i18n-user", Boolean(frame.name));
    document.getElementById("selectedCameraTime").textContent =
      `Keyframe at ${formatTime(frame.time)}`;
    if (document.activeElement !== document.getElementById("shotNameInput"))
      document.getElementById("shotNameInput").value = frame.name || "";
  }
  if (!display) return;
  for (const [id, value] of Object.entries({
    posX: display.x,
    posY: display.y,
    posZ: display.z,
    rotX: display.rx,
    rotY: display.ry,
    rotZ: display.rz,
  })) {
    setText(
      document.getElementById(id),
      Number.isFinite(Number(value)) ? Number(value).toFixed(2) : "—",
    );
  }
  const fov = Number.isFinite(Number(display.fov))
    ? Math.round(display.fov)
    : 50;
  if (document.activeElement !== document.getElementById("fov")) {
    document.getElementById("fov").value = fov;
    setText(document.getElementById("fovValue"), `${fov}°`);
  }
}

async function seek(time) {
  const clamped = Math.max(
    0,
    Math.min(Number(project.duration), Number(time) || 0),
  );
  if (
    selectedFrameTime !== null &&
    Math.abs(clamped - selectedFrameTime) > 0.05
  ) {
    selectedFrameTime = null;
    for (const row of keyframeList.children) row.classList.remove("selected");
    renderCamera();
  }
  project.playhead = clamped;
  renderPlayhead(clamped);
  await post("setPlayhead", { time: clamped, sequence: ++seekSequence });
}

function isTyping() {
  const target = document.activeElement;
  return (
    target &&
    (target.tagName === "TEXTAREA" ||
      target.isContentEditable ||
      (target.tagName === "INPUT" &&
        !["range", "button", "checkbox"].includes(target.type)))
  );
}

function normalizedKey(event) {
  const layout = window.VantaPreferences?.layout;
  if (
    layout &&
    /^[a-z]$/i.test(event.key || "") &&
    event.key.toLowerCase() !== "k"
  ) {
    const letters =
      layout === "qwerty"
        ? { w: "w", a: "a", s: "s", d: "d", q: "q", e: "e" }
        : { z: "w", q: "a", s: "s", d: "d", a: "q", e: "e" };
    return letters[event.key.toLowerCase()] || null;
  }
  if (event.code) return physicalKeys[event.code] || null;
  // Legacy fallback for AZERTY; CEF normally provides the physical code.
  return (
    {
      z: "w",
      q: "a",
      s: "s",
      d: "d",
      a: "q",
      e: "e",
      k: "k",
      Escape: "escape",
      ArrowLeft: "arrowleft",
      ArrowRight: "arrowright",
      ArrowUp: "arrowup",
      ArrowDown: "arrowdown",
    }[event.key] || null
  );
}

function sendKeys() {
  if (!bridgeReady || root.classList.contains("is-hidden")) return;
  post("setKeys", { keys: { ...keyState }, sequence: ++keySequence });
}

function clearKeys(notifyGame = true) {
  keyState = {};
  if (notifyGame) sendKeys();
}

function updateKeyState(key, pressed) {
  if (
    !key ||
    !Object.values(physicalKeys).includes(key) ||
    key === "escape" ||
    key === "k"
  )
    return;
  if (keyState[key] === pressed) return;
  keyState[key] = pressed;
  sendKeys();
}

document.addEventListener("keydown", (event) => {
  if (!modelOverlay.classList.contains("is-hidden")) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeModels();
    }
    return;
  }
  if (root.classList.contains("is-hidden")) return;
  const key = normalizedKey(event);
  if (!exitOverlay.classList.contains("is-hidden")) {
    if (key === "escape") {
      event.preventDefault();
      exitOverlay.classList.add("is-hidden");
    }
    return;
  }
  if (!libraryOverlay.classList.contains("is-hidden")) {
    if (key === "escape") {
      event.preventDefault();
      if (!libraryConfirm.classList.contains("is-hidden")) {
        libraryConfirm.classList.add("is-hidden");
        pendingLibraryConfirm = null;
      } else closeLibrary();
    }
    return;
  }
  if (!animationOverlay.classList.contains("is-hidden")) {
    if (key === "escape") {
      event.preventDefault();
      closeAnimationCatalog();
    }
    return;
  }
  if (!animationPreviewBar.classList.contains("is-hidden")) {
    if (key === "escape") {
      event.preventDefault();
      document.getElementById("animationBarBackButton").click();
    }
    return;
  }
  if (key === "escape") {
    event.preventDefault();
    requestClose();
    return;
  }
  if (isTyping()) return;
  if (
    !window.VantaPreferences &&
    hintIds[event.code] &&
    event.key.length === 1
  ) {
    document.getElementById(hintIds[event.code]).textContent =
      event.key.toUpperCase();
  }
  if (
    [
      "w",
      "a",
      "s",
      "d",
      "q",
      "e",
      "arrowleft",
      "arrowright",
      "arrowup",
      "arrowdown",
    ].includes(key)
  ) {
    event.preventDefault();
    updateKeyState(key, true);
  }
  if (key === "k" && !event.repeat)
    post("addKeyframe", { time: project.playhead }).then(
      (result) => result.message && showStatus(result.message),
    );
});

document.addEventListener("keyup", (event) =>
  updateKeyState(normalizedKey(event), false),
);
window.addEventListener("blur", () => {
  if (actorDragging) post("endActorDrag");
  clearKeys(false);
  looking = false;
  lastMouseX = lastMouseY = null;
  lookSurface.classList.remove("looking");
  actorDragging = leftHeld = false;
  setLookHint(null);
  lookSurface.classList.remove("dragging-actor");
});
setInterval(() => {
  if (
    bridgeReady &&
    !root.classList.contains("is-hidden") &&
    Object.values(keyState).some(Boolean)
  )
    sendKeys();
}, 250);
window.addEventListener("beforeunload", () => {
  bridgeReady = false;
  keyState = {};
});

document.getElementById("closeButton").addEventListener("click", requestClose);
document.getElementById("controlsButton").addEventListener("click", () => {
  const panel = document.getElementById("controlsPanel");
  if (panel.classList.contains("is-hidden"))
    panel.classList.remove("is-hidden");
  else panel.classList.add("is-hidden");
});
document
  .getElementById("updateFrameButton")
  .addEventListener("click", async () => {
    const frame = selectedFrame();
    if (!frame) return;
    const result = await post("addKeyframe", { time: frame.time });
    if (!result.ok) showStatus(result.message || "Could not update this shot.");
  });
document
  .getElementById("deleteFrameButton")
  .addEventListener("click", async () => {
    const frame = selectedFrame();
    if (!frame) return;
    const index = project.keyframes.indexOf(frame);
    selectedFrameTime = null;
    const result = await post("deleteKeyframe", { index: index + 1 });
    if (!result.ok) showStatus(result.message || "Could not delete this shot.");
  });
document
  .getElementById("shotNameInput")
  .addEventListener("change", async (event) => {
    const frame = selectedFrame();
    if (!frame) return;
    const result = await post("setKeyframeName", {
      index: project.keyframes.indexOf(frame) + 1,
      name: event.target.value.trim(),
    });
    if (!result.ok) showStatus(result.message || "Could not rename this shot.");
  });
document
  .getElementById("addKeyframeButton")
  .addEventListener("click", async () => {
    const result = await post("addKeyframe", { time: project.playhead });
    if (!result.ok) showStatus(result.message || "Could not add keyframe.");
  });
document.getElementById("previewButton").addEventListener("click", async () => {
  if (previewPlaying) {
    await post("stopPreview");
    return;
  }
  const result = await post("preview");
  if (!result.ok)
    showStatus(result.message || "Add a keyframe before previewing.");
});
document
  .getElementById("stopButton")
  .addEventListener("click", () => post("stopPreview"));
document.getElementById("captureButton").addEventListener("click", async () => {
  const result = await post("capture");
  if (!result.ok) showStatus(result.message || "Could not start clean take.");
});
document.getElementById("saveButton").addEventListener("click", async () => {
  if (savePending) return;
  clearTimeout(nameTimeout);
  nameTimeout = null;
  setSavePending(true);
  const nameResult = await post("setProjectName", {
    name: projectNameInput.value,
  });
  if (!nameResult.ok) {
    setSavePending(false);
    showStatus(nameResult.message || "Could not update the project name.");
    return;
  }
  const result = await post("saveProject");
  if (!result.ok) {
    setSavePending(false);
    setSaveState(false);
    showStatus(result.message || "Could not save project.");
  }
});

scrubber.addEventListener("input", () => {
  scrubbing = true;
  project.playhead = Number(scrubber.value);
  renderPlayhead(project.playhead);
});
scrubber.addEventListener("change", () => {
  scrubbing = false;
  seek(scrubber.value);
});

durationInput.addEventListener("change", async () => {
  const value = Math.max(
    Number(durationInput.min) || 1,
    Math.min(
      Number(durationInput.max) || 300,
      Number(durationInput.value) ||
        window.VantaRuntimeConfig?.defaultDuration ||
        20,
    ),
  );
  const result = await post("setDuration", { duration: value });
  if (result.ok) project.duration = value;
  renderProject();
});

document.getElementById("fov").addEventListener("input", (event) => {
  const value = Number(event.target.value);
  document.getElementById("fovValue").textContent = `${value}°`;
  post("setFov", { fov: value });
});
document.getElementById("fov").addEventListener("change", async (event) => {
  const frame = selectedFrame();
  if (!frame) return;
  const index = project.keyframes.indexOf(frame);
  const result = await post("setKeyframeFov", {
    index: index + 1,
    fov: Number(event.target.value),
  });
  if (!result.ok)
    showStatus(result.message || "Could not update field of view.");
});
document.getElementById("speed").addEventListener("input", (event) => {
  const value = Number(event.target.value);
  document.getElementById("speedValue").textContent = value.toFixed(1);
  post("setSpeed", { speed: value });
});

projectNameInput.addEventListener("input", () => {
  setSaveState(false);
  clearTimeout(nameTimeout);
  nameTimeout = setTimeout(
    () => post("setProjectName", { name: projectNameInput.value }),
    180,
  );
});
document.addEventListener("focusin", (event) => {
  if (event.target.matches('input, textarea, [contenteditable="true"]')) {
    clearKeys();
  }
});

document
  .getElementById("motionRecordStart")
  .addEventListener("click", async () => {
    const result = await post("startMotionRecording", {
      kind: document.getElementById("motionRecordKind").value,
      seconds: Number(document.getElementById("motionRecordSeconds").value),
      model: document.getElementById("motionRecordModel").value.trim(),
      occupants: document.getElementById("motionRecordOccupants").checked,
      captureAim: document.getElementById("motionRecordAim").checked,
    });
    if (!result.ok)
      showStatus(result.message || "Could not start movement recording.");
  });
window.addEventListener("message", (event) => {
  const data = event.data || {};
  if (data.action === "motionRecordStarted") {
    clearKeys();
    root.classList.add("is-hidden");
    document
      .getElementById("motionRecordOverlay")
      .classList.remove("is-hidden");
    document.getElementById("motionRecordClock").textContent = "00:00";
  }
  if (data.action === "motionRecordProgress")
    document.getElementById("motionRecordClock").textContent =
      formatTime(data.time) + " / " + Number(data.limit).toFixed(0) + "s";
  if (data.action === "motionRecordFinished") {
    document.getElementById("motionRecordOverlay").classList.add("is-hidden");
    root.classList.remove("is-hidden");
    showStatus(data.message);
  }
  if (data.action === "close") {
    copiedSequence = null;
    timelineCopied = false;
    sessionRole = "none";
    updateContextControls();
    document.getElementById("motionRecordOverlay").classList.add("is-hidden");
    document.getElementById("sessionInviteOverlay").classList.add("is-hidden");
    document.getElementById("sessionBadge").classList.add("is-hidden");
  }
  if (data.action === "open") {
    root.classList.remove("is-hidden");
    bridgeReady = true;
    exitOverlay.classList.add("is-hidden");
    setSavePending(false);
    clearKeys();
    saveDirty = false;
    document.getElementById("saveState").textContent = "Not saved yet";
    libraryState = { activeId: null, projects: [], limit: Infinity };
    renderLibrary();
  }
  if (data.action === "captureCountdown") {
    const countdown = document.getElementById("captureCountdown");
    root.classList.add("is-hidden");
    clearKeys(false);
    countdown.classList.remove("is-hidden");
    let seconds = Number(data.seconds) || 3;
    countdown.textContent = `TAKE STARTS IN ${seconds}`;
    const timer = setInterval(() => {
      seconds -= 1;
      if (seconds <= 0 || countdown.classList.contains("is-hidden")) {
        clearInterval(timer);
      } else {
        countdown.textContent = `TAKE STARTS IN ${seconds}`;
      }
    }, 1000);
  }
  if (data.action === "captureGo") {
    document.getElementById("captureCountdown").classList.add("is-hidden");
  }
  if (data.action === "captureEnd") {
    document.getElementById("captureCountdown").classList.add("is-hidden");
    root.classList.remove("is-hidden");
    selectedFrameTime = null;
    renderProject();
  }
  if (data.action === "requestClose") requestClose();
  if (data.action === "close") {
    closeModels(false);
    bridgeReady = false;
    exitOverlay.classList.add("is-hidden");
    setSavePending(false);
    root.classList.add("is-hidden");
    document.getElementById("captureCountdown").classList.add("is-hidden");
    document.getElementById("actorPins").innerHTML = "";
    actorPinElements.clear();
    selectedActorId = null;
    timelineSelection.clear();
    updateTimelineSelection();
    previewPlaying = false;
    actorRenderCache.clear();
    trackRenderCache.clear();
    inspectorSignature = "";
    document.getElementById("actorList").innerHTML = "";
    actorTracks.innerHTML = "";
    selectedFrameTime = null;
    looking = false;
    leftHeld = actorDragging = false;
    setLookHint(null);
    lookDeltaX = lookDeltaY = 0;
    clearKeys(false);
    setLibraryBusy(false);
    closeLibrary();
    animationOverlay.classList.add("is-hidden");
    animationPreviewBar.classList.add("is-hidden");
    animationPreviewSequence++;
    animationPreviewActive = false;
    animationActorId = null;
  }
  if (data.action === "modelCatalog") {
    if (data.append !== true) {
      modelCatalog = [];
      sceneModelNames.clear();
    }
    const chunk = (Array.isArray(data.models) ? data.models : []).map(
      (item) => ({
        ...item,
        search: (
          item.label +
          " " +
          item.model +
          " " +
          item.category
        ).toLowerCase(),
      }),
    );
    for (const item of chunk) {
      modelCatalog.push(item);
      sceneModelNames.set(item.model, item.label);
    }
    modelsLoaded = data.complete !== false;
    modelFilterKey = null;
    if (modelsLoaded) {
      renderModelCategories();
      renderModels();
      renderActors();
    } else if (data.append !== true) {
      renderModelCategories();
      renderModels();
    }
  }
  if (data.action === "sessionInvite") {
    sessionInvitation = data.id;
    document.getElementById("sessionInviteText").textContent =
      data.name + " invites you to a filming session.";
    document
      .getElementById("sessionInviteOverlay")
      .classList.remove("is-hidden");
  }
  if (data.action === "sessionState") {
    copiedSequence = null;
    timelineCopied = false;
    sessionRole = data.role || "none";
    updateContextControls();
    document
      .getElementById("sessionBadge")
      .classList.toggle("is-hidden", data.role === "none");
    document.getElementById("sessionBadge").textContent =
      data.role === "viewer" ? "SESSION / VIEWER" : "SESSION / HOST";
    document.getElementById("sessionRole").textContent =
      data.role === "none" ? "SOLO" : data.role.toUpperCase();
    document.getElementById("sessionHint").textContent =
      data.role === "viewer"
        ? "Viewing the host’s scene. Only the host can publish edits or start shared playback."
        : data.role === "host"
          ? "Publish after editing, then play together once all participants have loaded."
          : "Host a scene and invite participants by server ID.";
  }
  if (data.action === "project" && data.project) {
    project = {
      ...project,
      ...data.project,
      keyframes: Array.isArray(data.project.keyframes)
        ? data.project.keyframes
        : [],
      actors: Array.isArray(data.project.actors) ? data.project.actors : [],
    };
    for (const [key, item] of timelineSelection) {
      const current =
        item.kind === "action"
          ? project.actors
              .find((a) => a.id === item.actorId)
              ?.actions.find((a) => a.id === item.actionId)
          : item.kind === "camera"
            ? project.keyframes[item.index - 1]
            : item.kind === "shot"
              ? project.cameraShots?.find((s) => s.id === item.id)
              : null;
      if (!current || (item.kind === "camera" && current.time !== item.time))
        timelineSelection.delete(key);
      else
        timelineSelection.set(key, {
          ...item,
          time: current.time,
          duration: current.duration,
        });
    }
    updateTimelineSelection();
    if (selectedFrameTime !== null && !selectedFrame())
      selectedFrameTime = null;
    renderProject();
    renderLook();
  }
  if (data.action === "library") {
    const previousId = libraryState.activeId;
    libraryState = {
      activeId: data.activeId,
      projects: Array.isArray(data.projects) ? data.projects : [],
      limit: Number(data.limit) || Infinity,
    };
    if (previousId !== data.activeId) {
      timelineSelection.clear();
      updateTimelineSelection();
      copiedSequence = null;
      timelineCopied = false;
      closeModels(false);
      setSavePending(false);
      closeAnimationCatalog();
      selectedActorId = null;
      selectedFrameTime = null;
      renderProject();
    }
    renderLibrary();
    setLibraryBusy(false);
    if (
      previousId !== data.activeId &&
      !libraryOverlay.classList.contains("is-hidden")
    )
      closeLibrary();
    if (data.show) libraryOverlay.classList.remove("is-hidden");
  }
  if (data.action === "libraryError") {
    setLibraryBusy(false);
    showStatus(data.message);
  }
  if (data.action === "saveState") setSaveState(Boolean(data.saved));
  if (data.action === "saveResult") {
    setSavePending(false);
    if (!data.ok || data.stale) setSaveState(false);
  }
  if (data.action === "tab")
    selectSceneTab(data.scene === "look" ? "look" : Boolean(data.scene));
  if (data.action === "animationCatalog")
    openAnimationCatalog(Number(data.actorId));
  if (data.action === "animationPreviewStopped") {
    animationPreviewActive = false;
    if (!animationPreviewBar.classList.contains("is-hidden"))
      document.getElementById("animationBarStatus").textContent =
        "Aperçu arrêté. La scène est restaurée au curseur.";
  }
  if (data.action === "actors") {
    project.actors = Array.isArray(data.actors) ? data.actors : [];
    if (
      pendingAccessorySelection &&
      project.actors.some((a) => a.id === pendingAccessorySelection)
    ) {
      selectedActorId = pendingAccessorySelection;
      pendingAccessorySelection = null;
    }
    renderCameraRig();
    renderActors();
  }
  if (data.action === "actorScreen") {
    if (data.selectedId != null && data.selectedId !== selectedActorId) {
      selectedActorId = data.selectedId;
      renderActors();
    }
    renderActorPins(Array.isArray(data.positions) ? data.positions : []);
  }
  if (data.action === "camera") {
    camera = data.camera;
    if (!selectedFrame()) renderCamera();
  }
  if (data.action === "playhead") {
    if (!timelineDrag) project.playhead = Number(data.time) || 0;
    previewPlaying = Boolean(data.playing);
    playheadAnchorTime = project.playhead;
    playheadAnchorClock = performance.now();
    if (!scrubbing && !timelineDrag) renderPlayhead(project.playhead);
    if (window.VantaVisual?.setPlaying)
      window.VantaVisual.setPlaying(previewPlaying);
    else
      document.getElementById("previewButton").textContent = previewPlaying
        ? "Ⅱ"
        : "▶";
    if (previewPlaying && !animationScheduled) {
      animationScheduled = true;
      requestAnimationFrame(animatePlayhead);
    }
  }
  if (data.action === "previewStarted") {
    if (window.VantaVisual?.setPlaying) window.VantaVisual.setPlaying(true);
    else document.getElementById("previewButton").textContent = "Ⅱ";
  }
  if (data.action === "status") showStatus(data.message);
});

trackLane.addEventListener("mousedown", (event) => {
  if (event.target === trackLane) beginSeekDrag(event, trackLane);
});

renderProject();

// Keep capture controls relevant to the selected source.
const recordingSourceFields = () => {
  const car = document.getElementById("motionRecordKind").value === "vehicle";
  document
    .getElementById("motionRecordOccupants")
    .closest("label")
    ?.classList.toggle("is-hidden", !car);
  document
    .getElementById("motionRecordAim")
    .closest("label")
    ?.classList.toggle("is-hidden", car);
};
document
  .getElementById("motionRecordKind")
  .addEventListener("change", recordingSourceFields);
recordingSourceFields();
