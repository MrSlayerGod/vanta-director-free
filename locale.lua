-- Console help uses the player's preference, or the configured server default.
-- NUI owns its full FR/EN catalog so each player can use a different language.
DirectorLocale = {}
local french = {
    ["VANTA DIRECTOR: open or close camera mode"] = "VANTA DIRECTOR : ouvrir ou fermer le mode caméra",
    ["VANTA DIRECTOR: stop clean take"] = "VANTA DIRECTOR : arrêter la prise propre",
    ["Director access denied."] = "Accès à Director refusé.",
    ["Please wait before repeating this action."] = "Patiente avant de répéter cette action.",
    ["Too many Director requests. Please wait."] = "Trop de requêtes Director. Patiente un instant.",
    ["[VANTA DIRECTOR] Open the editor first."] = "[VANTA DIRECTOR] Ouvre d’abord l’éditeur.",
    ["[VANTA DIRECTOR] Interface failed to start. Focus released; check the packaged NUI files and refresh the resource."] = "[VANTA DIRECTOR] L’interface n’a pas démarré. La souris est libérée ; vérifie les fichiers NUI et redémarre la ressource.",
    ["[VANTA DIRECTOR] Performance measurements: use resmon 1 and profiler record 500 in F8. This report does not measure resource CPU time."] = "[VANTA DIRECTOR] Pour mesurer les performances, utilise resmon 1 et profiler record 500 dans F8. Ce rapport ne mesure pas le temps CPU de la ressource.",
}
function DirectorLocale.text(message, language)
    local defaults = type(Config.DefaultPreferences) == "table" and Config.DefaultPreferences or {}
    language = language or defaults.language or "fr"
    if language == "en" then
        return message
    end
    return french[message] or message
end
