DirectorShots = {}
local S=DirectorShots
function S.number(value,minimum,maximum)
    local n=tonumber(value)
    if not n or n~=n or n<minimum or n>maximum then return nil end
    return n
end
function S.copy(value)
    if type(value)~='table' then return value end
    local out={}
    for k,v in pairs(value) do if type(k)~='string' or k:sub(1,1)~='_' then out[k]=S.copy(v) end end
    return out
end
function S.rig(rig,actors)
    if rig==nil then return {mode='manual'} end
    if type(rig)~='table' then return nil,'Invalid automatic camera.' end
    if rig.mode=='manual' then return {mode='manual'} end
    if rig.mode~='target' and rig.mode~='follow' and rig.mode~='orbit' then return nil,'Invalid camera mode.' end
    local target
    for i,a in ipairs(actors) do if (a.id or i)==rig.targetId then target=i;break end end
    if not target then return nil,'Camera subject is missing.' end
    if type(rig.relative)~='boolean' or type(rig.anchor)~='table' then return nil,'Invalid camera settings.' end
    local clean={mode=rig.mode,targetId=target,relative=rig.relative,anchor={}}
    if rig.avoidObstacles~=nil and type(rig.avoidObstacles)~='boolean' then return nil,'Invalid camera obstacle option.' end
    clean.avoidObstacles=rig.avoidObstacles==true
    for k,limit in pairs({targetHeight=20,offsetX=100000,offsetY=100000,offsetZ=100000,radius=1000,elevation=100,speed=90,startAngle=360000}) do
        local n=S.number(rig[k],-limit,limit);if not n then return nil,'Invalid camera settings.' end;clean[k]=n
    end
    if clean.radius<.5 then return nil,'Invalid orbit radius.' end
    for _,k in ipairs({'x','y','z','rx','ry','rz','fov'}) do
        local n=S.number(rig.anchor[k],-100000,100000);if not n then return nil,'Invalid camera anchor.' end;clean.anchor[k]=n
    end
    if clean.anchor.fov<20 or clean.anchor.fov>100 then return nil,'Invalid field of view.' end
    return clean
end
function S.frames(frames,start,finish)
    if type(frames)~='table' or #frames>Config.MaximumKeyframes then return nil,'Too many camera keys.' end
    local out={}
    for _,f in ipairs(frames) do
        if type(f)~='table' then return nil,'Invalid camera key.' end
        local frame={name=tostring(f.name or ''):gsub('[\r\n]',' '):sub(1,48)}
        frame.time=S.number(f.time,start,finish)
        if not frame.time then return nil,'Camera key outside its shot.' end
        for _,k in ipairs({'x','y','z','rx','ry','rz','fov'}) do
            local n=S.number(f[k],-100000,100000);if not n then return nil,'Invalid camera key.' end;frame[k]=n
        end
        if frame.fov<20 or frame.fov>100 then return nil,'Invalid field of view.' end
        out[#out+1]=frame
    end
    table.sort(out,function(a,b)return a.time<b.time end)
    for i=2,#out do if out[i].time-out[i-1].time<.049 then return nil,'Camera keys must be separated.' end end
    return out
end
function S.validate(shots,duration,actors,baseCount,preserveIds)
    if shots==nil then return {} end
    if type(shots)~='table' or #shots>30 then return nil,'Maximum 30 camera shots.' end
    local clean,seen,total={},{},baseCount or 0
    for _,shot in ipairs(shots) do
        if type(shot)~='table' then return nil,'Invalid camera shot.' end
        local id=S.number(shot.id,1,1000000)
        local start=S.number(shot.time,0,duration)
        local seconds=S.number(shot.duration,.1,duration)
        if not id or id%1~=0 or seen[id] or not start or not seconds or start+seconds>duration+.001 then return nil,'Invalid shot timing or ID.' end
        seen[id]=true
        local frames,error=S.frames(shot.frames or {},start,start+seconds)
        if not frames then return nil,error end
        local rig,error=S.rig(shot.rig,actors)
        if not rig then return nil,error end
        if preserveIds and rig.targetId then rig.targetId=actors[rig.targetId].id or rig.targetId end
        if #frames==0 and rig.mode=='manual' then return nil,'A manual shot needs a camera key.' end
        if shot.ease~=nil and shot.ease~='smooth' and shot.ease~='linear' and shot.ease~='easeInOut' then return nil,'Invalid camera curve.' end
        total=total+#frames
        if total>Config.MaximumKeyframes then return nil,'Camera keyframe limit reached.' end
        local blend=S.number(shot.blend or 0,0,math.min(2,seconds))
        if not blend then return nil,'Invalid camera transition.' end
        clean[#clean+1]={id=id,name=tostring(shot.name or 'Camera shot'):gsub('[\r\n]',' '):sub(1,48),time=start,duration=seconds,frames=frames,rig=rig,ease=shot.ease or 'smooth',blend=blend}
    end
    table.sort(clean,function(a,b)return a.time<b.time end)
    for i=2,#clean do if clean[i].time<clean[i-1].time+clean[i-1].duration-.001 then return nil,'Camera shots cannot overlap.' end end
    return clean
end
function S.at(shots,time)
    for _,shot in ipairs(shots) do if time>=shot.time and time<shot.time+shot.duration then return shot end end
    local last=shots[#shots]
    if last and math.abs(time-last.time-last.duration)<.001 then return last end
end
function S.find(shots,id)
    for _,shot in ipairs(shots) do if shot.id==tonumber(id) then return shot end end
end
function S.retime(shot,time,seconds)
    local out=S.copy(shot)
    for _,frame in ipairs(out.frames) do frame.time=time+(frame.time-shot.time)*seconds/shot.duration end
    if out.rig and out.rig.mode=='orbit' then out.rig.speed=out.rig.speed*shot.duration/seconds end
    out.time,out.duration=time,seconds
    out.blend=math.min(out.blend or 0,seconds)
    return out
end
function S.blend(first,last,alpha)
    local t=math.max(0,math.min(1,alpha));t=t*t*(3-2*t)
    local state={}
    for _,field in ipairs({'x','y','z','rx','ry','rz','fov'}) do
        local a,b=first[field],last[field]
        if field=='rx' or field=='ry' or field=='rz' then b=a+(b-a+180)%360-180 end
        state[field]=a+(b-a)*t
    end
    return state
end
