DirectorCommunity = {}
function DirectorCommunity.discordUrl()
    local url = Config.DiscordUrl
    if type(url) ~= "string" or #url > 256 then
        return ""
    end
    if url:match("^https://discord%.gg/[%w_-]+$") or url:match("^https://discord%.com/invite/[%w_-]+$") then
        return url
    end
    return ""
end
