-- Weather, time and depth-of-field presentation.
DirectorClient.modules.environment = function(ctx)
    local editorState = ctx.state
    ctx.environment = {}

    function ctx.environment.applySceneLook(force)
        if not editorState.directorOpen then
            return
        end
        local now = GetGameTimer()
        if force or now - editorState.lastLookUpdate >= 1000 then
            editorState.lastLookUpdate = now
            if editorState.sceneLook.weather ~= "SERVER" then
                SetOverrideWeather(editorState.sceneLook.weather)
                editorState.weatherOwned = true
            end
            if editorState.sceneLook.hour >= 0 then
                NetworkOverrideClockTime(editorState.sceneLook.hour, editorState.sceneLook.minute, 0)
                editorState.clockOwned = true
            end
        end
        if editorState.camera and DoesCamExist(editorState.camera) then
            if force then
                SetCamUseShallowDofMode(editorState.camera, editorState.sceneLook.dof)
            end
            if editorState.sceneLook.dof then
                if force then
                    SetCamNearDof(editorState.camera, editorState.sceneLook.near + 0.0)
                    SetCamFarDof(editorState.camera, editorState.sceneLook.far + 0.0)
                    SetCamDofStrength(editorState.camera, editorState.sceneLook.strength + 0.0)
                end
                if editorState.sceneLook.focusId and now - editorState.lastFocusUpdate >= 100 then
                    editorState.lastFocusUpdate = now
                    local handle = editorState.sceneEntities[editorState.sceneLook.focusId]
                    if handle and DoesEntityExist(handle) then
                        local p, c = GetEntityCoords(handle), GetCamCoord(editorState.camera)
                        local distance = math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 + (p.z - c.z) ^ 2)
                        SetCamNearDof(editorState.camera, (math.max(0.1, distance - 1)) + 0.0)
                        SetCamFarDof(editorState.camera, (math.max(0.2, distance + 1)) + 0.0)
                    end
                end
                SetUseHiDof()
            end
        end
    end

    function ctx.environment.clearSceneLook()
        if editorState.weatherOwned then
            ClearOverrideWeather()
            editorState.weatherOwned = false
        end
        if editorState.clockOwned then
            NetworkClearClockTimeOverride()
            editorState.clockOwned = false
        end
        if editorState.camera and DoesCamExist(editorState.camera) then
            SetCamUseShallowDofMode(editorState.camera, false)
        end
    end

    function ctx.environment.loadSceneLook(value)
        value = type(value) == "table" and value or {}
        local weather = tostring(value.weather or "SERVER"):upper()
        editorState.sceneLook.weather = editorState.weatherTypes[weather] and weather or "SERVER"
        editorState.sceneLook.hour = math.floor(math.max(-1, math.min(23, tonumber(value.hour) or -1)))
        editorState.sceneLook.minute = math.floor(math.max(0, math.min(59, tonumber(value.minute) or 0)))
        editorState.sceneLook.dof = value.dof == true
        editorState.sceneLook.focusId = tonumber(value.focusId)
        editorState.sceneLook.near = math.max(0.1, math.min(100.0, tonumber(value.near) or 2.0))
        editorState.sceneLook.far =
            math.max(editorState.sceneLook.near + 0.1, math.min(500.0, tonumber(value.far) or 30.0))
        editorState.sceneLook.strength = math.max(0.0, math.min(1.0, tonumber(value.strength) or 0.5))
        if editorState.directorOpen then
            ctx.environment.clearSceneLook()
            ctx.environment.applySceneLook(true)
        end
    end

    return function()
        ctx.bridge.editorCallback("setSceneLook", function(data, callback)
            local field, value = tostring(data.field or ""), data.value
            if field == "weather" then
                value = tostring(value or ""):upper()
                if not editorState.weatherTypes[value] then
                    callback({ ok = false, message = "Invalid weather." })
                    return
                end
                editorState.sceneLook.weather = value
            elseif field == "hour" then
                value = tonumber(value)
                if not value or value % 1 ~= 0 or value < -1 or value > 23 then
                    callback({ ok = false, message = "Invalid hour." })
                    return
                end
                editorState.sceneLook.hour = value
            elseif field == "minute" then
                value = tonumber(value)
                if not value or value % 1 ~= 0 or value < 0 or value > 59 then
                    callback({ ok = false, message = "Invalid minute." })
                    return
                end
                editorState.sceneLook.minute = value
            elseif field == "focusId" then
                local id = tonumber(value)
                if id ~= 0 and not editorState.sceneEntities[id] then
                    callback({ ok = false, message = "Choose a scene subject." })
                    return
                end
                editorState.sceneLook.focusId = id ~= 0 and id or nil
            elseif field == "dof" then
                if type(value) ~= "boolean" then
                    callback({ ok = false, message = "Invalid depth of field." })
                    return
                end
                editorState.sceneLook.dof = value
            elseif field == "near" or field == "far" or field == "strength" then
                value = tonumber(value)
                local minimum, maximum =
                    field == "near" and 0.1 or (field == "far" and 0.2 or 0.0),
                    field == "near" and 100.0 or (field == "far" and 500.0 or 1.0)
                if not value or value ~= value or value < minimum or value > maximum then
                    callback({ ok = false, message = "Invalid focus value." })
                    return
                end
                editorState.sceneLook[field] = value
                if editorState.sceneLook.far <= editorState.sceneLook.near then
                    editorState.sceneLook.far = math.min(500.0, editorState.sceneLook.near + 0.1)
                end
            else
                callback({ ok = false, message = "Invalid setting." })
                return
            end
            ctx.environment.clearSceneLook()
            ctx.environment.applySceneLook(true)
            ctx.projects.sendProject()
            callback({ ok = true })
        end)
    end
end
