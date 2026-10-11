DirectorRoutes = {}
local function length(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function DirectorRoutes.validate(points)
    if type(points) ~= 'table' or #points < 1 or #points > 64 then return nil, 'A route needs 1 to 64 destinations.' end
    local clean = {}
    for _, point in ipairs(points) do
        if type(point) ~= 'table' then return nil, 'Invalid route point.' end
        local entry = {}
        for _, field in ipairs({'x','y','z'}) do
            local v = tonumber(point[field])
            if not v or v ~= v or math.abs(v) > 100000 then return nil, 'Invalid route coordinates.' end
            entry[field] = v
        end
        clean[#clean+1] = entry
    end
    return clean
end
-- Bounded Hermite tangents, sampled once into an arc-length lookup table.
function DirectorRoutes.compile(start, destinations)
    local points = {start}
    for _, point in ipairs(destinations or {}) do if length(points[#points],point) > .001 then points[#points+1] = point end end
    local samples, tangents = {{x=start.x,y=start.y,z=start.z,distance=0}}, {}
    for i, point in ipairs(points) do
        local before, after = points[math.max(1,i-1)], points[math.min(#points,i+1)]
        local cap = math.min(i>1 and length(point,before) or math.huge, i<#points and length(point,after) or math.huge)
        local vector = {x=(after.x-before.x)*.5,y=(after.y-before.y)*.5,z=(after.z-before.z)*.5}
        local size = math.sqrt(vector.x^2+vector.y^2+vector.z^2)
        local scale = size > cap and cap/size or 1
        tangents[i] = {x=vector.x*scale,y=vector.y*scale,z=vector.z*scale}
    end
    local distance = 0
    for i=1,#points-1 do
        local a,b = points[i],points[i+1]
        for n=1,24 do
            local t=n/24; local t2,t3=t*t,t*t*t
            local sample = {}
            for _, field in ipairs({'x','y','z'}) do
                sample[field] = (2*t3-3*t2+1)*a[field]+(t3-2*t2+t)*tangents[i][field]+(-2*t3+3*t2)*b[field]+(t3-t2)*tangents[i+1][field]
            end
            -- Height must not overshoot below the surrounding route points.
            sample.z = a.z + (b.z-a.z)*t
            distance=distance+length(samples[#samples],sample); sample.distance=distance; samples[#samples+1]=sample
        end
    end
    return {samples=samples,length=distance}
end
function DirectorRoutes.sample(route, progress)
    local distance = math.max(0,math.min(1,progress))*route.length
    local items=route.samples
    if #items==1 then return items[1],0 end
    local lo,hi=2,#items
    while lo<hi do local mid=math.floor((lo+hi)/2); if items[mid].distance<distance then lo=mid+1 else hi=mid end end
    local a,b=items[lo-1],items[lo]; local t=(distance-a.distance)/math.max(.000001,b.distance-a.distance)
    local before,after=items[math.max(1,lo-2)],items[math.min(#items,lo+1)]
    local ax,ay=b.x-before.x,b.y-before.y
    local bx,by=after.x-a.x,after.y-a.y
    local dx,dy=ax+(bx-ax)*t,ay+(by-ay)*t
    return {x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t,z=a.z+(b.z-a.z)*t},(math.deg(math.atan(-dx,dy))+360)%360
end

-- Shared, pure timeline contracts for local staged vehicle interactions.
DirectorSeats={}
function DirectorSeats.state(actions,time)
    local latest
    for _,a in ipairs(actions or {}) do
        if (a.type=='enterVehicle' or a.type=='exitVehicle') and a.time<=time and
            (not latest or a.time>latest.time or (a.time==latest.time and a.id>latest.id)) then latest=a end
    end
    if not latest then return nil end
    if latest.type=='exitVehicle' and time>=latest.time+latest.duration then return nil end
    return {action=latest,phase=latest.type=='exitVehicle' and 'exiting' or
        (not latest.instant and time<latest.time+latest.duration and 'entering' or 'seated')}
end
function DirectorSeats.validate(actors,duration)
    local byId,reservations={},{}
    for i,a in ipairs(actors) do byId[a.id or i]=a end
    for _,actor in ipairs(actors) do
        local actions={};for _,a in ipairs(actor.actions or {}) do actions[#actions+1]=a end
        table.sort(actions,function(a,b) if a.time==b.time then return (a.id or 0)<(b.id or 0) end;return a.time<b.time end)
        local relevant=false;for _,a in ipairs(actions) do if a.type=='enterVehicle' or a.type=='exitVehicle' then relevant=true end end
        if relevant then
        local entry,freeAt=nil,-1
        for _,a in ipairs(actions) do
            if a.type=='enterVehicle' or a.type=='exitVehicle' then
                local vehicle=byId[a.vehicleId]
                if actor.kind~='ped' or not vehicle or vehicle.kind~='vehicle' then return false,'Choose a staged vehicle.' end
                if a.instant~=nil and (type(a.instant)~='boolean' or a.type~='enterVehicle') then return false,'Invalid captured seat cue.' end
                if type(a.seat)~='number' or a.seat%1~=0 or a.seat< -1 or a.seat>15 or
                    type(a.duration)~='number' or a.duration~=a.duration or a.duration<.1 or a.duration>30 or a.time+a.duration>duration+.001 then return false,'Invalid vehicle interaction timing or seat.' end
                if a.time<freeAt then return false,'Vehicle interaction clips must not overlap.' end
                if a.type=='enterVehicle' then
                    if entry then return false,'Add an exit before another vehicle entry.' end
                    entry=a;freeAt=a.time+a.duration
                else
                    if not entry or entry.vehicleId~=a.vehicleId or entry.seat~=a.seat then return false,'Add a matching vehicle entry before exiting.' end
                    reservations[#reservations+1]={vehicle=entry.vehicleId,seat=entry.seat,first=entry.time,last=a.time+a.duration}
                    entry=nil;freeAt=a.time+a.duration
                end
            elseif a.type=='move' or a.type=='animation' then
                if entry or a.time<freeAt then return false,'Place ped movement/animations outside vehicle interaction clips; exit first.' end
                if a.type=='move' then freeAt=math.max(freeAt,a.time+a.duration) end
            end
        end
        if entry then reservations[#reservations+1]={vehicle=entry.vehicleId,seat=entry.seat,first=entry.time,last=duration+.001} end
        end
    end
    for i,a in ipairs(reservations) do for j=i+1,#reservations do
        local b=reservations[j]
        if a.vehicle==b.vehicle and a.seat==b.seat and a.first<b.last and b.first<a.last then return false,'This seat is reserved by another ped at that time.' end
    end end
    return true
end
