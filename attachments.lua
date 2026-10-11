DirectorAttachments = {}
local A=DirectorAttachments
A.bones={rightHand=0xDEAD,leftHand=0x49D9,back=0x60F2,head=0x796E,pelvis=0x2E28}
function A.validate(kind,value)
    if value==nil then return true,nil end
    if kind~='prop' or type(value)~='table' or not A.bones[value.bone] or type(value.parentId)~='number' or value.parentId%1~=0 or value.parentId<1 or type(value.visible)~='boolean' then return false,'Invalid accessory attachment.' end
    local clean={parentId=value.parentId,bone=value.bone,visible=value.visible}
    for _,field in ipairs({'x','y','z','rx','ry','rz'}) do
        local n=value[field];local limit=field:sub(1,1)=='r' and 360 or 2
        if type(n)~='number' or n~=n or math.abs(n)>limit then return false,'Invalid accessory offset.' end
        clean[field]=n
    end
    return true,clean
end
function A.target(actors,id)
    for index,a in ipairs(actors) do if (a.id or index)==id and a.kind=='ped' then return a,index end end
end
-- Attachment is written only on creation/change; GTA follows the bone itself.
function A.apply(actor,handle,parent)
    local v=actor.attachment
    if not v or not parent or not DoesEntityExist(parent) then return false end
    local cached=actor._attachmentSignature
    if cached and cached.handle==handle and cached.parent==parent and cached.bone==v.bone
        and cached.x==v.x and cached.y==v.y and cached.z==v.z
        and cached.rx==v.rx and cached.ry==v.ry and cached.rz==v.rz then return true end
    local bone=GetPedBoneIndex(parent,A.bones[v.bone]);if bone<0 then return false end
    FreezeEntityPosition(handle,false)
    SetEntityCollision(handle,false,false)
    AttachEntityToEntity(handle,parent,bone,(v.x) + 0.0,(v.y) + 0.0,(v.z) + 0.0,(v.rx) + 0.0,(v.ry) + 0.0,(v.rz) + 0.0,false,false,false,true,2,true)
    actor._attachmentSignature={handle=handle,parent=parent,bone=v.bone,
        x=v.x,y=v.y,z=v.z,rx=v.rx,ry=v.ry,rz=v.rz}
    return true
end
