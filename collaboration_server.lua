DirectorCollaboration = {}
function DirectorCollaboration.register(validateProject)
    local sessions, members, offers = {}, {}, {}
    local serial = 0
    local function error(player, message)
        TriggerClientEvent("vanta_director_free:collaborationStatus", player, message)
    end
    local function snapshot(s)
        for player in pairs(s.members) do
            TriggerClientEvent(
                "vanta_director_free:sessionState",
                player,
                s.id,
                s.host,
                player == s.host and "host" or "viewer",
                s.revision,
                s.project
            )
        end
    end
    local function leave(player)
        offers[player] = nil
        local s = members[player] and sessions[members[player]]
        if not s then
            return
        end
        if s.host == player then
            for id in pairs(s.members) do
                members[id] = nil
                TriggerClientEvent("vanta_director_free:sessionEnded", id, "The host ended the session.")
            end
            sessions[s.id] = nil
            for target, offer in pairs(offers) do
                if offer.id == s.id then
                    offers[target] = nil
                end
            end
        else
            s.ready[player] = nil
            s.members[player] = nil
            members[player] = nil
            TriggerClientEvent("vanta_director_free:sessionEnded", player, "You left the session.")
        end
    end
    RegisterNetEvent("vanta_director_free:sessionAction", function(action, data)
        local player = source
        -- This operation only cleans up source's own participation.
        if action == "leave" then
            if members[player] or offers[player] then
                leave(player)
                TriggerClientEvent("vanta_director_free:sessionLeft", player)
            end
            return
        end
        if not Config.CollaborationEnabled then
            error(player, "Collaboration is disabled in config.lua.")
            return
        end
        local allowedActions = {
            create = true,
            leave = true,
            accept = true,
            decline = true,
            ready = true,
            invite = true,
            publish = true,
            play = true,
            stop = true,
        }
        if type(action) ~= "string" or not allowedActions[action] then
            error(player, "Unknown session action.")
            return
        end
        local allowed, message = DirectorAccess.check(
            player,
            "session:" .. action,
            (action == "publish" or action == "invite") and 1000 or 200
        )
        if not allowed then
            error(player, message)
            return
        end
        data = type(data) == "table" and data or {}
        local s = members[player] and sessions[members[player]]
        if action == "leave" then
            leave(player)
            return
        end
        if action == "create" then
            if s then
                error(player, "Leave the current session first.")
                return
            end
            local ok, project = validateProject(data.project)
            if not ok then
                error(player, project)
                return
            end
            serial = serial + 1
            local id = tostring(player) .. ":" .. serial
            s = { id = id, host = player, members = { [player] = true }, project = project, revision = 1, ready = {} }
            sessions[id] = s
            members[player] = id
            snapshot(s)
            return
        end
        if action == "accept" then
            local offer = offers[player]
            offers[player] = nil
            if s or not offer or offer.expires < os.time() or offer.id ~= data.id or not sessions[offer.id] then
                error(player, "Invitation expired or a session is already open.")
                return
            end
            s = sessions[offer.id]
            local count = 0
            for _ in pairs(s.members) do
                count = count + 1
            end
            if count >= (Config.MaximumParticipants or 8) then
                error(player, "Session limit reached.")
                return
            end
            s.members[player] = true
            members[player] = s.id
            TriggerClientEvent(
                "vanta_director_free:sessionState",
                player,
                s.id,
                s.host,
                "viewer",
                s.revision,
                s.project
            )
            error(s.host, "A participant joined.")
            return
        end
        if action == "decline" then
            offers[player] = nil
            return
        end
        if not s or data.id ~= s.id then
            error(player, "Session not found.")
            return
        end
        if action == "ready" then
            if data.revision == s.revision then
                s.ready[player] = s.revision
            end
            return
        end
        if s.host ~= player then
            error(player, "Only the host can publish, invite or control playback.")
            return
        end
        if action == "invite" then
            local target = DirectorShots.number(data.target, 1, 65535)
            if
                not target
                or target % 1 ~= 0
                or target == player
                or not GetPlayerName(target)
                or not DirectorAccess.allowed(target)
                or members[target]
            then
                error(player, "Choose an available player with Director access.")
                return
            end
            offers[target] = { id = s.id, expires = os.time() + (Config.InvitationSeconds or 30) }
            TriggerClientEvent(
                "vanta_director_free:sessionInvite",
                target,
                s.id,
                GetPlayerName(player) or "Director host"
            )
            error(player, ("Invitation sent. It expires in %d seconds."):format(Config.InvitationSeconds or 30))
        elseif action == "publish" then
            local ok, project = validateProject(data.project)
            if not ok then
                error(player, project)
                return
            end
            s.project = project
            s.revision = s.revision + 1
            s.ready = {}
            snapshot(s)
        elseif action == "play" then
            for id in pairs(s.members) do
                if s.ready[id] ~= s.revision then
                    error(player, "Wait for every participant to finish loading the scene.")
                    return
                end
            end
            local start = DirectorShots.number(data.start, 0, s.project.duration)
            local finish = DirectorShots.number(data.finish, 0, s.project.duration)
            local clock = DirectorShots.number(data.clock, -2147483648, 4294967295)
            if not start or not finish or finish - start < 0.1 or not clock or clock % 1 ~= 0 then
                error(player, "Invalid session playback.")
                return
            end
            for id in pairs(s.members) do
                TriggerClientEvent("vanta_director_free:sessionPlay", id, s.id, s.revision, start, finish, clock)
            end
        elseif action == "stop" then
            for id in pairs(s.members) do
                TriggerClientEvent("vanta_director_free:sessionStop", id, s.id)
            end
        else
            error(player, "Unknown session action.")
        end
    end)
    AddEventHandler("playerDropped", function()
        leave(source)
    end)
end
