-- VANTA DIRECTOR FREE - server configuration.
-- Edit values, then restart vanta_director_free. See README.md.
-- Saved player preferences take priority over initial defaults.
-- RequireAce: true restricts access using AcePermission; false allows everyone.
-- Limits: projects 1..3, subjects 1..6, camera positions 1..30, actions 1..20.
-- Scene duration: 1..60 seconds. Project file limit: 16384..131072 bytes.
-- Camera speed: metres/second. Response settings: seconds; lower is more direct.
-- ModelLoadTimeoutMs and UiUpdateIntervalMs use milliseconds.
-- Clean takes require OBS or another recorder; no built-in MP4 export.
-- DefaultPreferences.language: 'fr' or 'en'. Players can switch in Settings.
-- CustomModels: models must already be streamed to clients.
-- Example: { kind = 'ped', model = 'my_ped', label = 'My character', category = 'Server' }
-- Collaboration is unavailable in Free; leave CollaborationEnabled false.
-- RateLimits use milliseconds. DiscordUrl: empty string hides the button.
Config = {}

Config.Command = 'director_free'
Config.DefaultKey = 'F6'
Config.StopTakeKey = 'F9'
Config.StopRecordingKey = 'F10'
Config.CancelRecordingKey = 'F11'
Config.RequireAce = true
Config.AcePermission = 'vanta.director.free'

Config.ProjectFileLimit = 131072
Config.MaximumProjects = 3
Config.MaximumKeyframes = 30
Config.MaximumActors = 6
Config.MaximumActionsPerActor = 20
Config.MinimumDuration = 1.0
Config.MaximumDuration = 60.0
Config.DefaultDuration = 20.0

Config.DefaultCameraSpeed = 8.0
Config.CameraMoveResponse = 0.12
Config.CameraLookResponse = 0.10
Config.MouseLookSensitivity = 0.16
Config.ActorDragResponse = 0.045
Config.PlacementDistance = 150.0
Config.SelectionOutline = true
Config.SelectionColor = {74, 195, 225, 185}

Config.ModelLoadTimeoutMs = 5000
Config.UiUpdateIntervalMs = 100

Config.CaptureCountdownSeconds = 3
Config.RecordingMaximumSeconds = 30

Config.DefaultPreferences = {
    layout = 'azerty',
    sensitivity = 1.0,
    invert = false,
    scale = 1.0,
    text = 'default',
    motion = false,
    tips = true, help = true,
    snap = true, interval = 0.1,
    move = 0.05,
    rotation = 1,
    autosave = false, saveInterval = 120,
    warning = true,
    language = 'fr',
    workspace = true, leftCollapsed = false, rightCollapsed = false,
}

Config.CustomModels = {
}

Config.CollaborationEnabled = false
Config.MaximumParticipants = 8
Config.InvitationSeconds = 30
Config.PlaybackLeadMs = 1500

Config.RateLimits = {
    load = 250, save = 250, manage = 250, import = 1000,
    session = 200, publish = 1000, invite = 1000,
}

Config.ServerRequestBurst = 40
Config.ServerRequestWindowMs = 10000

Config.DiscordUrl = 'https://discord.gg/BUdg2bx6H'
