DirectorRecording =
    { maximumSeconds = Config.RecordingMaximumSeconds, maximumSamples = Config.RecordingMaximumSeconds * 20 + 2 }
local R = DirectorRecording
R.weapons = {
    "weapon_pistol",
    "weapon_combatpistol",
    "weapon_appistol",
    "weapon_pistol50",
    "weapon_smg",
    "weapon_microsmg",
    "weapon_carbinerifle",
    "weapon_assaultrifle",
    "weapon_pumpshotgun",
    "weapon_sniperrifle",
}
local weaponAllowed = {}
for _, name in ipairs(R.weapons) do
    weaponAllowed[name] = true
end
function R.validateAimCues(cues, seconds)
    if cues == nil then
        return {}
    end
    if type(cues) ~= "table" or #cues > Config.MaximumAimCues then
        return nil, "Too many recorded aim cues."
    end
    local clean = {}
    local finish = -1
    for _, c in ipairs(cues) do
        if
            type(c) ~= "table"
            or not weaponAllowed[c.weapon]
            or type(c.time) ~= "number"
            or c.time ~= c.time
            or c.time < finish - 0.00001
            or c.time < 0
            or type(c.duration) ~= "number"
            or c.duration ~= c.duration
            or c.duration < 0.02
            or c.duration > 0.5
            or c.time + c.duration > seconds + 0.001
            or type(c.fired) ~= "boolean"
        then
            return nil, "Invalid recorded aim cue."
        end
        local row = { time = c.time, duration = c.duration, weapon = c.weapon, fired = c.fired }
        for _, key in ipairs({ "x", "y", "z" }) do
            local n = c[key]
            if type(n) ~= "number" or n ~= n or math.abs(n) > 100000 then
                return nil, "Invalid aim point."
            end
            row[key] = n
        end
        finish = c.time + c.duration
        clean[#clean + 1] = row
    end
    return clean
end
function R.aimAt(cues, at)
    if not cues or #cues == 0 then
        return nil
    end
    local lo, hi = 1, #cues
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if cues[mid].time <= at then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local cue = cues[lo]
    if at >= cue.time and at < cue.time + cue.duration then
        return cue, lo
    end
end
function R.trimAimCues(cues, first, last)
    local out = {}
    for _, c in ipairs(cues or {}) do
        local start, finish = math.max(first, c.time), math.min(last, c.time + c.duration)
        if finish - start >= 0.02 then
            out[#out + 1] =
                { time = start - first, duration = finish - start, weapon = c.weapon, fired = c.fired, x = c.x, y = c.y, z = c.z }
        end
    end
    return out
end
R.gestures = {
    salute = { dict = "anim@mp_player_intuppersalute", clip = "idle_a" },
    point = { dict = "gestures@f@standing@casual", clip = "gesture_point" },
    refuse = { dict = "anim@heists@ornate_bank@chat_manager", clip = "fail" },
    pointRight = { dict = "mp_gun_shop_tut", clip = "indicate_right" },
    hangout = { dict = "amb@world_human_hang_out_street@male_b@idle_a", clip = "idle_b", flags = 1 },
    leanWall = { dict = "amb@world_human_leaning@male@wall@back@foot_up@idle_a", clip = "idle_a", flags = 1 },
    leanHands = { dict = "amb@world_human_leaning@male@wall@back@hands_together@idle_b", clip = "idle_b", flags = 1 },
    sitGround = { dict = "amb@world_human_picnic@male@idle_a", clip = "idle_a", flags = 1 },
    medic = { dict = "amb@medic@standing@tendtodead@base", clip = "base", flags = 1 },
    mechanic = { dict = "amb@world_human_vehicle_mechanic@male@base", clip = "idle_a", flags = 1 },
    pushups = { dict = "amb@world_human_push_ups@male@idle_a", clip = "idle_d", flags = 1 },
}
function R.validateCues(cues, seconds)
    if cues == nil then
        return {}
    end
    if type(cues) ~= "table" or #cues > Config.MaximumRecordedGestures then
        return nil, ("Maximum %d recorded gestures."):format(Config.MaximumRecordedGestures)
    end
    local clean = {}
    for _, cue in ipairs(cues) do
        if
            type(cue) ~= "table"
            or not R.gestures[cue.gesture]
            or type(cue.time) ~= "number"
            or cue.time ~= cue.time
            or cue.time < 0
            or type(cue.duration) ~= "number"
            or cue.duration ~= cue.duration
            or cue.duration < 0.1
            or cue.time + cue.duration > seconds + 0.001
        then
            return nil, "Invalid recorded gesture."
        end
        clean[#clean + 1] = { gesture = cue.gesture, time = cue.time, duration = cue.duration }
    end
    table.sort(clean, function(a, b)
        return a.time < b.time
    end)
    return clean
end
function R.trimCues(cues, first, last)
    local out = {}
    for _, cue in ipairs(cues or {}) do
        local start, finish = math.max(first, cue.time), math.min(last, cue.time + cue.duration)
        if finish - start >= 0.1 then
            out[#out + 1] = { gesture = cue.gesture, time = start - first, duration = finish - start }
        end
    end
    return out
end
function R.validate(samples)
    if type(samples) ~= "table" or #samples < 2 or #samples > R.maximumSamples then
        return false, "Invalid recorded sample count."
    end
    local clean = {}
    local previous = -1
    for i, s in ipairs(samples) do
        if type(s) ~= "table" or #s ~= 8 then
            return false, "Invalid recorded pose."
        end
        local row = {}
        for j = 1, 8 do
            local n = s[j]
            local limit = j == 1 and R.maximumSeconds or (j <= 4 and 100000 or (j == 8 and 150 or 360))
            if type(n) ~= "number" or n ~= n or math.abs(n) > limit or (j == 8 and n < 0) then
                return false, "Invalid recorded value."
            end
            row[j] = n
        end
        if s[1] <= previous or (i == 1 and s[1] ~= 0) then
            return false, "Recorded timestamps must start at zero and increase."
        end
        previous = s[1]
        clean[i] = row
    end
    if previous < 0.1 then
        return false, "Record at least one tenth of a second."
    end
    return true, clean
end
local function angle(a, b, t)
    return a + ((b - a + 180) % 360 - 180) * t
end
function R.trim(samples, first, last)
    local ok, clean = R.validate(samples)
    if not ok then
        return nil, clean
    end
    if
        type(first) ~= "number"
        or type(last) ~= "number"
        or first ~= first
        or last ~= last
        or first < 0
        or last - first < 0.1
        or last > clean[#clean][1]
    then
        return nil, "Invalid trim range."
    end
    local function row(at, time)
        local p = R.sample(clean, at)
        return { time, p.x, p.y, p.z, (p.rx + 180) % 360 - 180, (p.ry + 180) % 360 - 180, (p.heading + 180) % 360 - 180, p.speed }
    end
    local out = { row(first, 0) }
    for _, s in ipairs(clean) do
        if s[1] > first + 0.000001 and s[1] < last - 0.000001 then
            local sample = { table.unpack(s) }
            sample[1] = s[1] - first
            out[#out + 1] = sample
        end
    end
    out[#out + 1] = row(last, last - first)
    return out
end
function R.sample(samples, time)
    local lo, hi = 1, #samples
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if samples[mid][1] <= time then
            lo = mid
        else
            hi = mid - 1
        end
    end
    local a = samples[lo]
    local b = samples[math.min(lo + 1, #samples)]
    local t = a == b and 0 or math.max(0, math.min(1, (time - a[1]) / (b[1] - a[1])))
    return {
        x = a[2] + (b[2] - a[2]) * t,
        y = a[3] + (b[3] - a[3]) * t,
        z = a[4] + (b[4] - a[4]) * t,
        rx = angle(a[5], b[5], t),
        ry = angle(a[6], b[6], t),
        heading = angle(a[7], b[7], t),
        speed = a[8] + (b[8] - a[8]) * t,
    }
end
function R.apply(actor, handle, clip, time, playing, force)
    local at = math.max(0, math.min(clip.duration, time - clip.time))
    local p = R.sample(clip.samples, at)
    local moving = playing and time >= clip.time and time < clip.time + clip.duration and p.speed > 0.1
    local aim, aimIndex
    if actor.kind == "ped" and playing and time >= clip.time and time < clip.time + clip.duration then
        aim, aimIndex = R.aimAt(clip.aimCues, at)
    end
    if actor.kind == "ped" then
        if force then
            if actor._recordCue then
                ClearPedTasksImmediately(handle)
                actor._recordTaskAt = nil
            end
            actor._recordCue = nil
            actor._cueWanted = nil
        end
        local cue, index
        for i, c in ipairs(clip.poseCues or {}) do
            if at >= c.time and at < c.time + c.duration and time >= clip.time and time < clip.time + clip.duration then
                cue, index = c, i
            end
        end
        if cue and playing and not aim then
            if actor._recordCue ~= index and actor._recordCue ~= -index then
                local gesture = R.gestures[cue.gesture]
                if actor._cueWanted ~= index then
                    RequestAnimDict(gesture.dict)
                    actor._cueWanted = index
                    actor._cueRequested = gesture.dict
                    actor._cueDeadline = GetGameTimer() + 2000
                end
                if HasAnimDictLoaded(gesture.dict) then
                    TaskPlayAnim(
                        handle,
                        gesture.dict,
                        gesture.clip,
                        8.0,
                        -8.0,
                        math.ceil((cue.time + cue.duration - at) * 1000),
                        gesture.flags or 49,
                        0.0,
                        false,
                        false,
                        false
                    )
                    actor._recordCue = index
                    actor._recordTaskAt = nil
                elseif GetGameTimer() > actor._cueDeadline then
                    actor._recordCue = -index
                end
            end
        else
            if actor._recordCue then
                ClearPedTasksImmediately(handle)
                actor._recordCue = nil
                actor._recordTaskAt = nil
            end
        end
        if moving and not aim and (not (cue and playing) or actor._recordCue == -index) then
            if force or not actor._recordTaskAt or GetGameTimer() - actor._recordTaskAt >= 400 then
                local target = R.sample(clip.samples, math.min(clip.duration, at + 0.6))
                FreezeEntityPosition(handle, false)
                actor._frozen = false
                TaskGoStraightToCoord(
                    handle,
                    target.x + 0.0,
                    target.y + 0.0,
                    target.z + 0.0,
                    (math.min(3, math.max(1, p.speed))) + 0.0,
                    1000,
                    p.heading + 0.0,
                    0.1
                )
                actor._recordTaskAt = GetGameTimer()
            end
        elseif not cue and actor._recordTaskAt then
            ClearPedTasksImmediately(handle)
            actor._recordTaskAt = nil
            FreezeEntityPosition(handle, true)
            actor._frozen = true
        end
    end
    if actor.kind == "ped" then
        if aim then
            if actor._frozen then
                FreezeEntityPosition(handle, false)
                actor._frozen = false
            end
            if actor._aimWeapon ~= aim.weapon then
                RemoveAllPedWeapons(handle, true)
                GiveWeaponToPed(handle, GetHashKey(aim.weapon), 0, false, true)
                actor._aimWeapon = aim.weapon
            end
            if force or actor._aimCue ~= aimIndex then
                if moving then
                    local destination = R.sample(clip.samples, math.min(clip.duration, at + 0.6))
                    TaskGoToCoordWhileAimingAtCoord(
                        handle,
                        destination.x + 0.0,
                        destination.y + 0.0,
                        destination.z + 0.0,
                        aim.x + 0.0,
                        aim.y + 0.0,
                        aim.z + 0.0,
                        (math.min(3, math.max(1, p.speed))) + 0.0,
                        false,
                        2.0,
                        0.5,
                        false,
                        0,
                        false,
                        0
                    )
                else
                    TaskAimGunAtCoord(
                        handle,
                        aim.x + 0.0,
                        aim.y + 0.0,
                        aim.z + 0.0,
                        math.max(1, math.ceil((aim.time + aim.duration - at) * 1000)),
                        true,
                        false
                    )
                end
                actor._aimCue = aimIndex
                actor._recordTaskAt = nil
            end
        elseif actor._aimWeapon then
            RemoveAllPedWeapons(handle, true)
            ClearPedTasksImmediately(handle)
            actor._aimWeapon = nil
            actor._aimCue = nil
            actor._recordTaskAt = nil
            actor._recordCue = nil
        end
        if not playing and actor._frozen == false then
            FreezeEntityPosition(handle, true)
            actor._frozen = true
        end
    end
    -- Original root heights are captured from the live entity: no added ground offset.
    SetEntityCoordsNoOffset(handle, p.x + 0.0, p.y + 0.0, p.z + 0.0, true, true, true)
    if actor.kind == "vehicle" then
        SetEntityRotation(handle, p.rx + 0.0, p.ry + 0.0, p.heading + 0.0, 2, true)
        if not clip._travel then
            clip._travel = { 0 }
            for i = 2, #clip.samples do
                local a, b = clip.samples[i - 1], clip.samples[i]
                clip._travel[i] = clip._travel[i - 1] + math.sqrt(
                    (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2 + (b[4] - a[4]) ^ 2
                )
            end
        end
        local lo, hi = 1, #clip.samples
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if clip.samples[mid][1] <= at then
                lo = mid
            else
                hi = mid - 1
            end
        end
        local s = clip.samples[lo]
        local distance = clip._travel[lo] + math.sqrt((p.x - s[2]) ^ 2 + (p.y - s[3]) ^ 2 + (p.z - s[4]) ^ 2)
        for wheel = 0, GetVehicleNumberOfWheels(handle) - 1 do
            SetVehicleWheelYRotation(handle, wheel, distance / 0.35)
        end
    else
        SetEntityHeading(handle, p.heading + 0.0)
    end
end
