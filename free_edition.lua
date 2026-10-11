-- Shared edition contract. Server validation remains authoritative for persistence.
DirectorFree = {}
DirectorFree.message = 'Cette fonction est disponible dans Director complet.'
local ceilings = {MaximumProjects=3,MaximumActors=6,MaximumKeyframes=30,MaximumActionsPerActor=20,MaximumDuration=60}
for name, maximum in pairs(ceilings) do Config[name]=math.min(Config[name],maximum) end
Config.MinimumDuration=math.min(Config.MinimumDuration,Config.MaximumDuration)
Config.DefaultDuration=math.max(Config.MinimumDuration,math.min(Config.DefaultDuration,Config.MaximumDuration))
Config.CollaborationEnabled=false
local advanced={previewCameraPreset=true,cancelCameraPreset=true,applyCameraPreset=true,createCameraShot=true,selectCameraShot=true,updateCameraShot=true,deleteCameraShot=true,duplicateCameraShot=true,startMotionRecording=true,trimRecording=true,addRecordedGesture=true,addAccessory=true,setAttachment=true,duplicateActors=true,setActorGroup=true,beginRoute=true,addRoutePoint=true,beginRoutePoint=true,moveRoutePoint=true,endRoutePoint=true,deleteRoutePoint=true,cancelRoute=true,commitRoute=true,collaboration=true,vehicleSeats=true}
local actionTypes={move=true,animation=true,lookAt=true,visibility=true,engine=true,lights=true,door=true}
function DirectorFree.callback(name,data)
    if advanced[name] then return false,DirectorFree.message end
    if name=='setCameraRig' and data.mode~='manual' then return false,DirectorFree.message end
    if name=='addAction' and (not actionTypes[data.type] or data.points~=nil or data.recording~=nil) then return false,DirectorFree.message end
    return true
end
function DirectorFree.project(project)
    if type(project)~='table' then return false,'Invalid project data.' end
    if project.cameraRig~=nil then
        if type(project.cameraRig)~='table' then return false,'Invalid camera mode.' end
        if project.cameraRig.mode~=nil and project.cameraRig.mode~='manual' then return false,DirectorFree.message end
    end
    if project.cameraShots~=nil then
        if type(project.cameraShots)~='table' then return false,'Invalid camera shots.' end
        if next(project.cameraShots)~=nil then return false,DirectorFree.message end
    end
    if type(project.actors)=='table' then
        for _,actor in pairs(project.actors) do
            if type(actor)=='table' then
                if actor.attachment~=nil then return false,DirectorFree.message end
                if type(actor.actions)=='table' then
                    for _,action in pairs(actor.actions) do
                        if type(action)=='table' and (not actionTypes[action.type] or action.points~=nil or action.recording~=nil) then return false,DirectorFree.message end
                    end
                end
            end
        end
    end
    return true
end
function DirectorFree.discordUrl()
    local url=Config.DiscordUrl
    if type(url)~='string' or #url>256 then return '' end
    if url:match('^https://discord%.gg/[%w_-]+$') or url:match('^https://discord%.com/invite/[%w_-]+$') then return url end
    return ''
end
