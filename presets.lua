-- Rebase reusable camera paths and action chains without storing runtime handles.
DirectorPresets = {}
local P = DirectorPresets

function P.point(point, from, to)
    local angle = math.rad((to.heading or to.rz or 0) - (from.heading or from.rz or 0))
    local x, y = point.x - from.x, point.y - from.y
    return {
        x = to.x + x * math.cos(angle) - y * math.sin(angle),
        y = to.y + x * math.sin(angle) + y * math.cos(angle),
        z = to.z + point.z - from.z,
    }
end

function P.references(record)
    local project = record.project
    local references = {}
    local seen = {}
    local function add(id)
        if not id or seen[id] then
            return
        end
        local actor = project.actors[id]
        if not actor then
            return
        end
        seen[id] = true
        references[#references + 1] =
            { id = id, kind = actor.kind, name = actor.name ~= "" and actor.name or actor.model }
    end
    if record.kind == "actions" then
        for _, action in ipairs(project.actors[record.actorIndex].actions) do
            add(action.vehicleId)
            add(action.targetId)
        end
    else
        local shot = DirectorShots.find(project.cameraShots or {}, record.shotId)
        add((shot and shot.rig or project.cameraRig or {}).targetId)
    end
    return references
end

function P.actionChain(source, target, start, mappings, nextId)
    if #source.actions == 0 then
        return nil, "Save an actor with scheduled actions first."
    end
    local first = math.huge
    for _, action in ipairs(source.actions) do
        if action.type == "recording" then
            return nil, "Use a project export to reuse recorded takes."
        end
        first = math.min(first, action.time)
    end
    local actions = DirectorShots.copy(target.actions)
    for _, original in ipairs(source.actions) do
        local action = DirectorShots.copy(original)
        action.id = nextId
        nextId = nextId + 1
        action.time = start + original.time - first
        for _, field in ipairs({ "targetId", "vehicleId" }) do
            if action[field] then
                action[field] = mappings[tostring(action[field])]
                if not action[field] then
                    return nil, "Choose a scene subject for every preset reference."
                end
            end
        end
        if action.x ~= nil then
            local point = P.point(action, source, target)
            action.x, action.y, action.z = point.x, point.y, point.z
        end
        for _, point in ipairs(action.points or {}) do
            local shifted = P.point(point, source, target)
            point.x, point.y, point.z = shifted.x, shifted.y, shifted.z
        end
        actions[#actions + 1] = action
    end
    table.sort(actions, function(a, b)
        return a.time == b.time and a.id < b.id or a.time < b.time
    end)
    return actions, nextId
end

function P.cameraShot(project, shotId, camera, start, mappings)
    local selected = DirectorShots.find(project.cameraShots or {}, shotId)
    local shot = selected and DirectorShots.copy(selected)
        or {
            frames = DirectorShots.copy(project.keyframes),
            rig = DirectorShots.copy(project.cameraRig or { mode = "manual" }),
            ease = "smooth",
            time = 0,
        }
    if not selected then
        local frames = shot.frames
        shot.time = frames[1] and frames[1].time or 0
        shot.duration = math.max(0.1, frames[#frames] and frames[#frames].time - shot.time or project.duration)
    end
    local origin = DirectorShots.copy(shot.frames[1] or shot.rig.anchor)
    if not origin then
        return nil, "Save a camera shot or path first."
    end
    local turn = camera.rz - origin.rz
    for _, frame in ipairs(shot.frames) do
        local point = P.point(frame, origin, camera)
        frame.x, frame.y, frame.z = point.x, point.y, point.z
        frame.rx, frame.ry, frame.rz =
            frame.rx + camera.rx - origin.rx, frame.ry + camera.ry - origin.ry, frame.rz + turn
        frame.time = start + frame.time - shot.time
    end
    if shot.rig.targetId then
        shot.rig.targetId = mappings[tostring(shot.rig.targetId)]
        if not shot.rig.targetId then
            return nil, "Choose a scene subject for every preset reference."
        end
        local point = P.point(shot.rig.anchor, origin, camera)
        shot.rig.anchor.x, shot.rig.anchor.y, shot.rig.anchor.z = point.x, point.y, point.z
        shot.rig.anchor.rz = shot.rig.anchor.rz + turn
        shot.rig.anchor.rx = shot.rig.anchor.rx + camera.rx - origin.rx
        shot.rig.anchor.ry = shot.rig.anchor.ry + camera.ry - origin.ry
        if shot.rig.relative == false then
            local angle = math.rad(turn)
            local x, y = shot.rig.offsetX, shot.rig.offsetY
            shot.rig.offsetX = x * math.cos(angle) - y * math.sin(angle)
            shot.rig.offsetY = x * math.sin(angle) + y * math.cos(angle)
        end
    end
    shot.time = start
    return shot
end
