DirectorObstacles={}
local O=DirectorObstacles
-- Clip the subject-to-camera segment without modifying saved keyframes.
function O.clip(origin,desired,hit,clearance)
    local dx,dy,dz=desired.x-origin.x,desired.y-origin.y,desired.z-origin.z
    local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
    if distance<.01 then return desired end
    local along=((hit.x-origin.x)*dx+(hit.y-origin.y)*dy+(hit.z-origin.z)*dz)/distance
    local length=math.max(0,math.min(distance,along-(clearance or .25)))
    local state={};for k,v in pairs(desired) do state[k]=v end
    state.x=origin.x+dx*length/distance;state.y=origin.y+dy*length/distance;state.z=origin.z+dz*length/distance
    return state
end
local function delta(a,b)return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
function O.camera(rig,origin,desired,ignore,now,time)
    local cache=rig._obstacle
    if not cache or cache.ignore~=ignore or math.abs(time-cache.time)>.3 then
        cache={ignore=ignore,time=time,next=0};rig._obstacle=cache
    end
    cache.time=time
    if cache.probe then
        local status,hit,point=GetShapeTestResult(cache.probe)
        if status==2 then
            if delta(origin,cache.origin)<.25 and delta(desired,cache.desired)<.25 then
                cache.hit=(hit==1 or hit==true) and {x=point.x,y=point.y,z=point.z} or nil
                cache.validOrigin={x=origin.x,y=origin.y,z=origin.z};cache.validDesired={x=desired.x,y=desired.y,z=desired.z}
            end
            cache.probe=nil
        elseif status==0 or now>=cache.deadline then cache.probe=nil;cache.hit=nil end
    end
    if not cache.probe and now>=cache.next then
        cache.origin={x=origin.x,y=origin.y,z=origin.z};cache.desired={x=desired.x,y=desired.y,z=desired.z}
        cache.probe=StartShapeTestLosProbe((origin.x) + 0.0,(origin.y) + 0.0,(origin.z) + 0.0,(desired.x) + 0.0,(desired.y) + 0.0,(desired.z) + 0.0,1+16,ignore,7)
        cache.deadline=now+250;cache.next=now+50
    end
    if cache.hit and cache.validOrigin and delta(origin,cache.validOrigin)<.25 and delta(desired,cache.validDesired)<.25 then
        return O.clip(origin,desired,cache.hit,.25)
    end
    return desired
end
-- Opt-in, bounded inspection along the compiled curve. No autonomous navmesh.
function O.route(curve,rootOffset,ignore,cancelled)
    local count=math.min(96,math.max(2,math.ceil(curve.length/2)))
    local handles={};local previous=DirectorRoutes.sample(curve,0)
    local started=GetGameTimer()
    for i=1,count do
        if cancelled() then return false,'Route inspection cancelled.' end
        local current=DirectorRoutes.sample(curve,i/count)
        local zOffset=.75-(rootOffset or 0)
        handles[#handles+1]={id=StartShapeTestLosProbe((previous.x) + 0.0,(previous.y) + 0.0,(previous.z+zOffset) + 0.0,(current.x) + 0.0,(current.y) + 0.0,(current.z+zOffset) + 0.0,1+16,ignore,7),segment=i}
        previous=current
    end
    local remaining=#handles
    while remaining>0 and GetGameTimer()-started<500 do
        if cancelled() then return false,'Route inspection cancelled.' end
        for _,probe in ipairs(handles) do if probe.id then
            local status,hit=GetShapeTestResult(probe.id)
            if status~=1 then probe.id=nil;remaining=remaining-1
                if status==2 and (hit==1 or hit==true) then return false,'Obstacle on route near '..math.floor(probe.segment/count*100)..'%. Add a point around it or disable inspection for this take.' end
                if status==0 then return false,'Collision data unavailable. Try again after the area has loaded.' end
            end
        end end
        if remaining>0 then Wait(0) end
    end
    if remaining>0 then return false,'Collision inspection timed out. Try again after the area has loaded.' end
    return true
end
