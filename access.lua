DirectorAccess={}
local last,budgets={},{}
function DirectorAccess.allowed(player)
    if type(player)~='number' or player%1~=0 or player<1 or player>65535 then return false end
    return not Config.RequireAce or IsPlayerAceAllowed(player,Config.AcePermission or 'vanta.director.free')
end
function DirectorAccess.check(player,channel,interval)
    if not DirectorAccess.allowed(player) then return false,'Director access denied.' end
    if type(GetGameTimer)=='function' then
        local limits=Config.RateLimits or {}
        interval=limits[channel] or (channel:sub(1,8)=='session:' and (limits[channel:sub(9)] or limits.session)) or interval or 250
        local now=GetGameTimer();local key=tostring(player)..':'..channel
        if last[key] and now>=last[key] and now-last[key]<(interval or 250) then return false,'Please wait before repeating this action.' end
        local budget=budgets[player]
        local window=Config.ServerRequestWindowMs or 10000
        if not budget or now<budget.started or now-budget.started>=window then
            budget={started=now,count=0};budgets[player]=budget
        end
        if budget.count>=(Config.ServerRequestBurst or 40) then return false,'Too many Director requests. Please wait.' end
        budget.count=budget.count+1
        last[key]=now
    end
    return true
end
AddEventHandler('playerDropped',function()
    budgets[source]=nil
    local prefix=tostring(source)..':'
    for key in pairs(last) do if key:sub(1,#prefix)==prefix then last[key]=nil end end
end)
