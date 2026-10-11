-- Validate operator settings once, on both sides. Bad values use safe defaults.
local function warn(name)
    print(('[VANTA DIRECTOR] config.lua: %s invalid; safe default restored. See README.md.'):format(name))
end
local function validNumber(v,lo,hi,integer)
    return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge and v>=lo and v<=hi and (not integer or v%1==0)
end
local function number(t,k,f,lo,hi,integer,prefix)
    if not validNumber(t[k],lo,hi,integer) then warn((prefix or '')..k);t[k]=f end
end
local function boolean(t,k,f,prefix)
    if type(t[k])~='boolean' then warn((prefix or '')..k);t[k]=f end
end
local function choice(t,k,f,values,prefix)
    local found=false;for _,v in ipairs(values) do if t[k]==v then found=true;break end end
    if not found then warn((prefix or '')..k);t[k]=f end
end
local numeric={
 ServerRequestBurst={40,10,100,true},ServerRequestWindowMs={10000,1000,60000,true},
 ProjectFileLimit={1048576,16384,67108864,true},MaximumProjects={100,1,100000,true},MaximumKeyframes={1000,1,100000,true},
 MaximumActors={100,1,10000,true},MaximumActionsPerActor={200,1,100000,true},MinimumDuration={1,1,86400},MaximumDuration={600,1,86400},DefaultDuration={20,1,86400},
 MaximumCameraShots={200,1,100000,true},MaximumRoutePoints={256,1,100000,true},MaximumSavedLocations={200,1,100000,true},MaximumRecordedGestures={200,1,100000,true},
 MaximumAimCues={1000,1,1000000,true},MaximumTimelineSelection={1000,1,1000000,true},PayloadNodeLimit={500000,1000,10000000,true},
 DefaultCameraSpeed={8,1,30},CameraMoveResponse={.12,.01,1},CameraLookResponse={.10,.01,1},MouseLookSensitivity={.16,.01,1},ActorDragResponse={.045,.01,.5},
 PlacementDistance={150,10,300},ModelLoadTimeoutMs={5000,1000,15000,true},UiUpdateIntervalMs={100,50,250,true},
 CaptureCountdownSeconds={3,1,10,true},RecordingMaximumSeconds={120,1,3600,true},MaximumParticipants={8,2,1000,true},InvitationSeconds={30,10,120,true},PlaybackLeadMs={1500,500,5000,true}
}
for k,v in pairs(numeric) do number(Config,k,v[1],v[2],v[3],v[4]) end
if Config.MinimumDuration>Config.MaximumDuration then warn('MinimumDuration > MaximumDuration');Config.MinimumDuration=Config.MaximumDuration end
if Config.DefaultDuration<Config.MinimumDuration or Config.DefaultDuration>Config.MaximumDuration then warn('DefaultDuration');Config.DefaultDuration=math.max(Config.MinimumDuration,math.min(Config.MaximumDuration,20)) end
for k,v in pairs({RequireAce=true,CollaborationEnabled=true,SelectionOutline=true}) do boolean(Config,k,v) end
for k,v in pairs({Command='director_free',AcePermission='vanta.director.free'}) do
 if type(Config[k])~='string' or #Config[k]>64 or not Config[k]:match('^[%w_.%-]+$') then warn(k);Config[k]=v end
end
for k,v in pairs({DefaultKey='F6',StopTakeKey='F9',StopRecordingKey='F10',CancelRecordingKey='F11'}) do
 if type(Config[k])~='string' or #Config[k]>32 or not Config[k]:match('^[%w_]+$') then warn(k);Config[k]=v end
end
local color=Config.SelectionColor
if type(color)~='table' or #color~=4 or not validNumber(color[1],0,255,true) or not validNumber(color[2],0,255,true) or not validNumber(color[3],0,255,true) or not validNumber(color[4],0,255,true) then warn('SelectionColor');Config.SelectionColor={74,195,225,185} end
if type(Config.DefaultPreferences)~='table' then warn('DefaultPreferences');Config.DefaultPreferences={} end
local p=Config.DefaultPreferences
for k,v in pairs({invert=false,motion=false,tips=true,help=true,snap=true,autosave=false,warning=true,workspace=true,leftCollapsed=false,rightCollapsed=false}) do boolean(p,k,v,'DefaultPreferences.') end
number(p,'sensitivity',1,.2,3,false,'DefaultPreferences.')
for k,v in pairs({layout={'azerty','qwerty'},text={'default','larger'},language={'en','fr'},scale={1,1.1,1.25},interval={.1,.25,.5,1},move={.05,.1,.25,.5},rotation={1,5,15,45},saveInterval={120,60,300}}) do choice(p,k,v[1],v,'DefaultPreferences.') end
if type(Config.RateLimits)~='table' then warn('RateLimits');Config.RateLimits={} end
for k,v in pairs({load=250,save=250,manage=250,import=1000,session=200,publish=1000,invite=1000}) do number(Config.RateLimits,k,v,100,10000,true,'RateLimits.') end
if type(Config.CustomModels)~='table' then warn('CustomModels');Config.CustomModels={} end
-- Catalog loading already validates individual model entries; do not load models here.
