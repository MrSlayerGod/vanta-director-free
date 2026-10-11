DirectorPedCues = {}
DirectorPedCues.gaits = { walk = 1.0, run = 2.0, sprint = 3.0 }

function DirectorPedCues.lookAt(actions, time)
    local latest
    for _, action in ipairs(actions or {}) do
        if action.type == 'lookAt' and action.time <= time and
            (not latest or action.time > latest.time or
                (action.time == latest.time and (action.id or 0) > (latest.id or 0))) then latest = action end
    end
    if latest and time < latest.time + latest.duration then return latest end
end

function DirectorPedCues.speed(action, distance, remaining)
    return math.max(0.1, math.min(8.0, distance / math.max(remaining, 0.1)))
end

-- Standing skeleton calibration is separate from the bounding-box offset used
-- by existing saved route coordinates. Never measure again while walking:
-- airborne animation frames must not turn into an accumulating height offset.
local FOOT_LEFT,FOOT_RIGHT,SOLE_THICKNESS=0x3779,0xCC4D,.04
function DirectorPedCues.calibrateFeet(actor,handle)
    if actor._contactOffset~=nil then return actor._contactOffset end
    local root=GetEntityCoords(handle)
    local left=GetPedBoneCoords(handle,FOOT_LEFT,0.0,0.0,0.0)
    local right=GetPedBoneCoords(handle,FOOT_RIGHT,0.0,0.0,0.0)
    if not root or not left or not right then return nil end
    local function valid(point)
        return type(point.x)=='number' and type(point.y)=='number' and type(point.z)=='number' and
            point.x==point.x and point.y==point.y and point.z==point.z
    end
    if not valid(root) or not valid(left) or not valid(right) then return nil end
    -- Before the skeleton is ready both bone queries can return the entity origin.
    if (left.x-right.x)^2+(left.y-right.y)^2+(left.z-right.z)^2<.0001 then return nil end
    if (left.x-root.x)^2+(left.y-root.y)^2>1 or (right.x-root.x)^2+(right.y-root.y)^2>1 then return nil end
    local offset=root.z-math.min(left.z,right.z)+SOLE_THICKNESS
    if offset<-.25 or offset>1.5 then return nil end
    actor._contactOffset=offset
    return offset
end
function DirectorPedCues.contactOffset(actor,fallback)
    return actor._contactOffset~=nil and actor._contactOffset or fallback
end

-- Ground following uses a bounded FIFO. No waits or raycasts per animation frame.
-- All heights are absolute world coordinates, never added to a ped's moving root.
local groundQueue, groundHead, groundTail = {}, 1, 0
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<100000 end
function DirectorPedCues.resetGround()
    groundQueue, groundHead, groundTail = {}, 1, 0
end
local function enqueue(state)
    if state.queued then return end
    groundTail=groundTail+1; groundQueue[groundTail]=state; state.queued=true
end
-- Preserve a small clearance deliberately set by the user at the original
-- placement. Sample that fixed position, not the moving/animated ped.
function DirectorPedCues.preparePlacement(actor,handle,now,fallback)
    local offset=DirectorPedCues.contactOffset(actor,fallback)
    local cached=actor._placementSignature
    if cached and cached.x==actor.x and cached.y==actor.y and cached.z==actor.z and cached.offset==offset and cached.handle==handle then
        local pending=actor._placementGround
        if pending and not pending.surface and not pending.ray and now>=(pending.nextProbe or 0) then enqueue(pending) end
        return
    end
    if actor._placementGround then actor._placementGround.cancelled=true end
    local signature={x=actor.x,y=actor.y,z=actor.z,offset=offset,handle=handle}
    actor._placementSignature=signature;actor._groundClearance=nil
    local state={handle=handle,nextProbe=0,placement=actor,signature=signature,
        target={x=actor.x,y=actor.y,z=actor.z-offset}}
    actor._placementGround=state
    enqueue(state)
end
local function acceptSurface(state, request, point, normal, now)
    if normal and (not finite(normal.x) or not finite(normal.y) or not finite(normal.z) or normal.z<.35) then return false end
    if not point or not finite(point.z) or point.z<request.z-4 or point.z>request.z+1.5 then return false end
    -- Discard results for an earlier seek or a position the actor has left.
    local target=state.target
    if not target or (target.x-request.x)^2+(target.y-request.y)^2>16 or math.abs(target.z-request.z)>2 then return false end
    state.surface={x=request.x,y=request.y,z=point.z,normal=normal,at=now}
    if state.placement and state.placement._placementSignature==state.signature then
        local clearance=state.target.z-point.z
        -- Large errors in old placements must not reintroduce floating routes.
        state.placement._groundClearance=(clearance>=0 and clearance<=.2) and clearance or 0.0
    end
    return true
end
function DirectorPedCues.groundFrame(now)
    -- Process at most four jobs, in arrival order, including pending probes.
    local jobs=math.min(4,groundTail-groundHead+1)
    for _=1,jobs do
        local state=groundQueue[groundHead];groundQueue[groundHead]=nil;groundHead=groundHead+1;state.queued=false
        if state.cancelled then
            -- Superseded placement or a deleted actor: no further native work.
        elseif state.ray then
            local status,hit,point,normal=GetShapeTestResult(state.ray)
            if status==2 then
                if hit==1 or hit==true then acceptSurface(state,state.request,point,normal,now) end
                state.ray=nil;state.nextProbe=now+100
            elseif status==0 or now-state.started>250 then
                state.ray=nil;state.nextProbe=now+100
            else enqueue(state) end
        elseif state.target then
            local t=state.target
            local request={x=t.x,y=t.y,z=t.z}
            local found,z=GetGroundZFor_3dCoord((t.x) + 0.0,(t.y) + 0.0,(t.z+1.5) + 0.0,false)
            if not state.surface and found and finite(z) and math.abs(z-t.z)<=.6 then
                acceptSurface(state,request,{z=z},nil,now)
            end
            -- World + objects: supports mapped floors; excludes peds and vehicles.
            local ray=StartShapeTestRay((t.x) + 0.0,(t.y) + 0.0,(t.z+1.5) + 0.0,(t.x) + 0.0,(t.y) + 0.0,(t.z-4) + 0.0,1+16,state.handle,7)
            state.nextProbe=now+100
            if ray and ray~=0 then
                state.ray,state.request,state.started=ray,request,now;enqueue(state)
            end
        end
    end
    if groundHead>groundTail then groundQueue,groundHead,groundTail={},1,0 end
end
function DirectorPedCues.groundHeight(actor,handle,x,y,rootZ,offset,now,force)
    local state=actor._ground
    if not state then state={nextProbe=0};actor._ground=state end
    if finite(actor.x) and finite(actor.y) and finite(actor.z) then
        DirectorPedCues.preparePlacement(actor,handle,now,offset)
    end
    local hint=rootZ-offset
    state.handle=handle
    local target=state.target
    if not target then target={};state.target=target end
    target.x,target.y,target.z=x,y,hint
    local surface=state.surface
    if surface and ((surface.x-x)^2+(surface.y-y)^2>16 or math.abs(surface.z-hint)>4) then
        state.surface=nil;surface=nil;state.nextProbe=0
    end
    if (force or now>=(state.nextProbe or 0)) and not state.ray then enqueue(state) end
    if not surface or now-surface.at>1000 then return rootZ end
    local z=surface.z
    local n=surface.normal
    -- A local tangent plane follows slopes between collision probes.
    if n and finite(n.z) and n.z>.35 then
        z=z-(n.x*(x-surface.x)+n.y*(y-surface.y))/n.z
    end
    if finite(z) and math.abs(z-hint)<=4 then
        state.target.z=z
        return z+DirectorPedCues.contactOffset(actor,offset)+(actor._groundClearance or 0.0)
    end
    return rootZ
end

-- Tasks are issued on cue/phase changes, not every frame. During transitions
-- native locomotion owns the ped; the route transform must not teleport it.
function DirectorPedCues.vehicleCue(actor,ped,vehicle,state,playing,force)
    DirectorPedCues.stopRoute(actor,ped)
    local a=state.action
    actor._seatAttached=true;actor._seatVehicle=vehicle
    local key=tostring(a.id)..':'..state.phase
    local seated=GetPedInVehicleSeat(vehicle,a.seat)==ped
    if not playing or force then
        ClearPedTasksImmediately(ped)
        if state.phase=='entering' then
            if IsPedInAnyVehicle(ped,false) then TaskLeaveVehicle(ped,vehicle,16) end
            local p=actor._seatEntryPosition or actor
            SetEntityCoordsNoOffset(ped,(p.x) + 0.0,(p.y) + 0.0,(p.z) + 0.0,false,false,true)
            FreezeEntityPosition(ped,true);actor._frozen=true
        elseif state.phase=='exiting' then
            if IsPedInAnyVehicle(ped,false) then TaskLeaveVehicle(ped,vehicle,16) end
            SetEntityCoordsNoOffset(ped,(a.x) + 0.0,(a.y) + 0.0,(a.z) + 0.0,false,false,true)
            FreezeEntityPosition(ped,true);actor._frozen=true
        else
            if not seated and IsVehicleSeatFree(vehicle,a.seat,false) then SetPedIntoVehicle(ped,vehicle,a.seat) end
            FreezeEntityPosition(ped,false);actor._frozen=false
        end
        actor._seatCue=nil
        return
    end
    if state.phase=='seated' then
          if a.instant and not seated and IsVehicleSeatFree(vehicle,a.seat,false) then
              SetPedIntoVehicle(ped,vehicle,a.seat);FreezeEntityPosition(ped,false);actor._frozen=false
              seated=GetPedInVehicleSeat(vehicle,a.seat)==ped
          end
        if actor._seatFailed~=a.id and not seated then
            actor._seatFailed=a.id
            SendNUIMessage({action='status',message='Vehicle entry did not finish in time. Move the ped closer, keep the vehicle still and increase the entry duration.'})
        end
        actor._seatCue=key
        return
    end
    if state.phase=='exiting' and actor._seatCue==key and not IsPedInAnyVehicle(ped,false) and not actor._seatExitPosition then
        local p=GetEntityCoords(ped);actor._seatExitPosition={id=a.id,x=p.x,y=p.y,z=p.z}
    end
    if actor._seatCue==key then return end
    ClearPedTasksImmediately(ped);actor._playing=nil;actor._lookPlaying=nil
    SetEntityCollision(ped,true,true);FreezeEntityPosition(ped,false);actor._frozen=false
    if state.phase=='entering' then
        actor._seatFailed=nil;actor._seatExitPosition=nil
        if not IsVehicleSeatFree(vehicle,a.seat,false) and not seated then
            actor._seatFailed=a.id
            SendNUIMessage({action='status',message='The selected vehicle seat is occupied.'})
        elseif not seated then TaskEnterVehicle(ped,vehicle,math.floor(a.duration*1000),a.seat,1.0,1,0) end
    else
        if not seated and IsVehicleSeatFree(vehicle,a.seat,false) then SetPedIntoVehicle(ped,vehicle,a.seat) end
        TaskLeaveVehicle(ped,vehicle,0)
    end
    actor._seatCue=key;actor._seatVehicle=vehicle
end


-- Native point routes own locomotion while playing. Never teleport or force a
-- heading to chase the ideal timeline pose between user seeks.
function DirectorPedCues.stopRoute(actor,handle)
    if actor._nativeRoute then SetPedMoveRateOverride(handle,1.0) end
    actor._nativeRoute=nil
end
function DirectorPedCues.playRoute(actor,handle,action,progress,planned,now,restart)
    local route=action._route
    if not route or route.length<.001 then return end
    local speed=DirectorPedCues.speed(action,route.length,action.duration)
    local state=actor._nativeRoute
    local position=GetEntityCoords(handle)
    local issue=restart or not state or state.action~=action.id
    if not issue and state.finish<1 then
        issue=(position.x-state.target.x)^2+(position.y-state.target.y)^2<2.25
    end
    if issue then
        local first=restart and progress or state and state.finish or progress
        local distance=math.min(route.length*(1-first),math.max(8.0,math.min(20.0,speed*4)))
        local finish=math.min(1,first+distance/route.length)
        local count=math.max(1,math.min(8,math.ceil(distance/1.5)))
        TaskFlushRoute()
        local target
        for i=1,count do
            target=DirectorRoutes.sample(route,first+(finish-first)*i/count)
            local reference=DirectorRoutes.sample(route,progress)
            local floor=planned.z-DirectorPedCues.contactOffset(actor,action._rootOffset or 1.0)-(actor._groundClearance or 0.0)+(target.z-reference.z)
            local surface=actor._ground and actor._ground.surface
            local normal=surface and surface.normal
            if surface then floor=surface.z end
            if normal and normal.z>.35 then
                floor=surface.z-(normal.x*(target.x-surface.x)+normal.y*(target.y-surface.y))/normal.z
            end
            TaskExtendRoute(target.x+0.0,target.y+0.0,floor+0.0)
        end
        TaskFollowPointRoute(handle,speed+0.0,0)
        state={action=action.id,finish=finish,target=target,rate=state and state.rate or 1.0,at=now}
        actor._nativeRoute=state
        SetPedMinMoveBlendRatio(handle,0.0)
        SetPedMaxMoveBlendRatio(handle,3.0)
    end
    -- Only adjust cadence gently; physical turning and foot contacts stay native.
    local _,heading=DirectorRoutes.sample(route,progress)
    local angle=math.rad(heading)
    local lag=(planned.x-position.x)*(-math.sin(angle))+(planned.y-position.y)*math.cos(angle)
    local desired=math.max(.85,math.min(1.15,1+lag*.12/math.max(speed,.5)))
    local dt=math.max(0,math.min(.1,(now-state.at)/1000))
    state.rate=state.rate+(desired-state.rate)*(1-math.exp(-dt/.4));state.at=now
    SetPedMoveRateOverride(handle,state.rate+0.0)
end
