-- Shared edition contract. Server validation remains authoritative for persistence.
DirectorFree = {}
DirectorFree.message = "Cette fonction est disponible dans Director complet."
Config.CollaborationEnabled = false
local unavailableCallbacks = { collaboration = true }
function DirectorFree.callback(name)
    if unavailableCallbacks[name] then
        return false, DirectorFree.message
    end
    return true
end
function DirectorFree.project(project)
    if type(project) ~= "table" then
        return false, "Invalid project data."
    end
    return true
end
function DirectorFree.discordUrl()
    local url = Config.DiscordUrl
    if type(url) ~= "string" or #url > 256 then
        return ""
    end
    if url:match("^https://discord%.gg/[%w_-]+$") or url:match("^https://discord%.com/invite/[%w_-]+$") then
        return url
    end
    return ""
end
