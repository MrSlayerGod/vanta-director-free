DirectorStaging={}
local S=DirectorStaging
function S.bookmarks(source)
    if source==nil then return {} end
    if type(source)~='table' or #source>Config.MaximumSavedLocations then return nil,('Maximum %d saved locations.'):format(Config.MaximumSavedLocations) end
    local out={}
    for _,b in ipairs(source) do
        if type(b)~='table' then return nil,'Invalid saved location.' end
        local frame,error=DirectorShots.frames({b.camera},0,300)
        if not frame then return nil,error end
        out[#out+1]={name=tostring(b.name or 'Location'):gsub('[\r\n]',' '):sub(1,48),camera=frame[1]}
    end
    return out
end
function S.duplicate(actors,ids,offset)
    if type(ids)~='table' or #ids==0 or #ids>Config.MaximumActors then return nil,'Choose scene elements.' end
    local selected,nextId={},1
    for _,id in ipairs(ids) do
        local n=DirectorShots.number(id,1,1000000)
        if not n or n%1~=0 then return nil,'Invalid scene selection.' end
        selected[n]=true
    end
    for _,a in ipairs(actors) do nextId=math.max(nextId,a.id+1) end
    for _,a in ipairs(actors) do if a.attachment and selected[a.attachment.parentId] then selected[a.id]=true end end
    local map,chosen={},{}
    for _,a in ipairs(actors) do if selected[a.id] then map[a.id]=nextId;nextId=nextId+1;chosen[#chosen+1]=a end end
    if #chosen==0 or #actors+#chosen>Config.MaximumActors then return nil,'Actor limit reached or selection missing.' end
    for _,k in ipairs({'x','y','z'}) do if not DirectorShots.number(offset[k],-1000,1000) then return nil,'Invalid group offset.' end end
    local out=DirectorShots.copy(actors)
    for _,actor in ipairs(chosen) do
        local a=DirectorShots.copy(actor);a.id=map[a.id];a.name=(a.name or a.model)..' copy'
        for _,k in ipairs({'x','y','z'}) do a[k]=a[k]+offset[k];if math.abs(a[k])>100000 then return nil,'Scene coordinates out of range.' end end
        if a.attachment then a.attachment.parentId=map[a.attachment.parentId] or a.attachment.parentId end
        for _,action in ipairs(a.actions) do
            if action.vehicleId then action.vehicleId=map[action.vehicleId] or action.vehicleId end
            if action.targetId then action.targetId=map[action.targetId] or action.targetId end
            if action.type=='move' or (action.type=='lookAt' and not action.targetId) then
                for _,k in ipairs({'x','y','z'}) do if action[k] then action[k]=action[k]+offset[k] end end
                for _,point in ipairs(action.points or {}) do for _,k in ipairs({'x','y','z'}) do point[k]=point[k]+offset[k] end end
            elseif action.type=='recording' then
                for _,sample in ipairs(action.samples) do sample[2]=sample[2]+offset.x;sample[3]=sample[3]+offset.y;sample[4]=sample[4]+offset.z end
            end
        end
        out[#out+1]=a
    end
    return out,map
end
