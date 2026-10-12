-- T009f stock Barstow burnout showcase. WEAR x10 is explicitly recorded, not stock rate.
-- Never forces tread to zero or calls deflateTire: ACNG's existing wear model must do it.
local M={}
local elapsed,stage,phase,sim,n=0,0,0,0,0
local result={test='V003 West Coast night burnout and native wear puncture',model='barstow',config='423m_sport',
  schema_version=1,wear_rate=10,completed=false,checks={},samples={},errors={}}
local cues={schema_version=1,cues={}}
local popped=false
local cameraShot='front'
local cameraFrames=0
local shotNames={'front','side','door','rear'}
result.cruise_samples={};result.camera_shots={}
local function save() jsonWriteFile('/acng-nightburn-test.json',result,true) end
local function cue(name) cues.cues[#cues.cues+1]={name=name,seq=#cues.cues+1,sim_time_s=sim};jsonWriteFile('/acng-film-cues.json',cues,true) end
local HELPER=[[
rawset(_G,'acngBurn',{})
function acngBurn.sample()
 local snap=extensions.acng_tires.getSnapshot()
 local out={snapshot=snap,native={}}
 for _,wd in pairs(wheels.wheelRotators) do
  if wd.hasTire then
   local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
   out.native[wd.name]={pa=pg and obj:getGroupPressure(pg),wheel_speed=wd.angularVelocity,
    deflated=wd.isTireDeflated}
  end
 end
 obj:queueGameEngineLua(string.format('extensions.acng_nightburn.receive(%q)',jsonEncode(out)))
end
]]
local function receive(text)
 local d=jsonDecode(text);d.t=sim;result.samples[#result.samples+1]=d
 for _,t in ipairs(d.snapshot and d.snapshot.tires or {}) do
  if t.worn_through==true and t.tread==0 and not popped then
   popped=true;result.pop_s=sim;result.popped_wheel=t.name;cue('tire_pop')
  end
 end
 save()
end
-- Use the native orbit renderer instead of moving the free camera each frame.
local function camera(veh)
 local data=core_camera.getCameraDataById(veh:getID())
 local orbit=data and data.orbit
 assert(orbit and orbit.deserialize,'Native orbit camera unavailable')
 local yaw,dist,pitch=45,5,-10
 if phase==8 then
  local angles={front=165,side=85,door=130,rear=25}
  yaw=angles[cameraShot];dist=cameraShot=='door' and 3.4 or 6
  result.camera_shots[cameraShot]=true;cameraFrames=cameraFrames+1
 end
 orbit:deserialize({rot={x=yaw,y=pitch,z=0},dist=dist,fov=55})
end
local function onPreRender()
 if (phase>=5 and phase<=6) or phase==8 then
  local veh=be:getPlayerVehicle(0)
  if veh then local ok,err=pcall(camera,veh);if not ok then result.errors[#result.errors+1]=tostring(err) end end
 end
end
local function onUpdate(dtReal,dtSim)
 elapsed=elapsed+dtReal
 if phase==0 and elapsed>12 and core_modmanager.isReady() then
  phase=-1
  core_gamestate.requestEnterLoadingScreen('acng_nightfilm',function()
   freeroam_freeroam.startFreeroamByName('west_coast_usa','spawns_chinatown')
   phase,stage=1,0
   core_gamestate.requestExitLoadingScreen('acng_nightfilm')
  end)
  return
 end
 if worldReadyState~=2 then return end
 local veh=be:getPlayerVehicle(0);if not veh then return end
 stage=stage+dtSim;sim=sim+dtSim
 if phase==1 then
  core_vehicles.replaceVehicle('barstow',{config='vehicles/barstow/423m_sport.pc'});phase,stage=2,0
 elseif phase==2 and stage>8 and veh:getJBeamFilename()=='barstow' then
  guihooks.trigger('ChangeState',{state='play'})
  result.original_mesh_alpha=veh:getMeshAlpha('')
  veh:setMeshAlpha(1,'',false)
  core_environment.setTimeOfDay({time=0.38,play=false})
  veh:queueLuaCommand("electrics.setLightsState(1)")
  extensions.acng_core.setEnabled(true);extensions.acng_core.setFeature('tire_temperature',true)
  extensions.acng_core.setFeature('tire_wear',true);extensions.acng_core.setTireProfile('road')
  veh:queueLuaCommand("controller.mainController.setGearboxMode('arcade');input.event('parkingbrake',0,1);ai.setMode('span');ai.driveInLane('on');ai.setSpeedMode('limit');ai.setSpeed(12);ai.setAggression(0.3)")
  commands.setGameCamera();core_camera.setByName(0,'orbit');cameraShot='front';cue('front_start');phase,stage=8,0
 elseif phase==8 then
  local i=math.min(4,math.floor(stage/8)+1)
  if cameraShot~=shotNames[i] then cue(cameraShot..'_end');cameraShot=shotNames[i];cue(cameraShot..'_start') end
  local bucket=math.floor(stage)
  if bucket>(result.cruise_bucket or -1) then
   result.cruise_bucket=bucket
   result.cruise_samples[#result.cruise_samples+1]={t=stage,speed_m_s=veh:getVelocity():length()}
  end
  if stage>32 then
   cue(cameraShot..'_end');cue('cruise_end')
   veh:queueLuaCommand("ai.setMode('disabled');input.event('throttle',0,1);input.event('brake',1,1)")
   phase,stage=3,0
  end
 elseif phase==3 and stage>3 then
  veh:queueLuaCommand(HELPER)
  veh:queueLuaCommand("extensions.acng_tires.setWearRate(10); controller.mainController.setGearboxMode('realistic'); controller.mainController.shiftToGearIndex(1); input.event('clutch',1,1); input.event('throttle',1,1); input.event('parkingbrake',0,1); input.event('brake',0.24,1)")
  commands.setGameCamera();core_camera.setByName(0,'orbit');phase,stage=4,0
 elseif phase==4 and stage>2 then
  veh:queueLuaCommand("input.event('clutch',0,1)")
  cue('burn_start');cue('drive_start');phase,stage=5,0
 elseif phase==5 then
  local next=math.floor(stage*2)
  if next>n then n=next;veh:queueLuaCommand('acngBurn.sample()') end
  if (popped and sim-result.pop_s>6) or stage>120 then
   veh:queueLuaCommand("input.event('throttle',0,1);input.event('clutch',1,1);input.event('brake',1,1)")
   cue('burn_end');cue('drive_end');phase,stage=6,0
  end
 elseif phase==6 and stage>3 then
  local min,max=1,0;local native=false
  local baseline=result.samples[1] and result.samples[1].native or {}
  for _,s in ipairs(result.samples) do
   for _,t in ipairs(s.snapshot and s.snapshot.tires or {}) do
    if t.name:sub(1,1)=='R' then min=math.min(min,t.tread or 1);max=math.max(max,t.tread or 0) end
    local w=s.native[t.name]
    -- Native deflation retains residual pressure; zero absolute/gauge pressure
    -- is not its contract. Require the engine's flag and >=75% gauge loss.
    local initial=baseline[t.name]
    if t.worn_through==true and w and (w.deflated==true or w.deflated==1) and w.pa
      and initial and initial.pa and w.pa-101325<=(initial.pa-101325)*0.25 then native=true end
   end
  end
  result.checks.tread_wore_down=max-min>0.5
  result.checks.wear_reached_zero=popped
  result.checks.native_pressure_lost=native
  result.checks.samples_collected=#result.samples>10
  result.environment=core_environment.getTimeOfDay()
  result.checks.night_time=result.environment~=nil and math.abs((result.environment.time or -1)-0.38)<0.002
  local maxSpeed=0;for _,s in ipairs(result.cruise_samples) do maxSpeed=math.max(maxSpeed,s.speed_m_s) end
  result.cruise_max_m_s=maxSpeed;result.camera_frames=cameraFrames
  result.checks.cruise_driven=maxSpeed>5 and #result.cruise_samples>20
  result.checks.cruise_camera=cameraFrames>300 and result.camera_shots.front and result.camera_shots.side and result.camera_shots.door and result.camera_shots.rear or false
  result.checks.no_camera_errors=#result.errors==0
  result.passed=true;for _,v in pairs(result.checks) do result.passed=result.passed and v==true end
  result.completed=true;save();cue('complete');phase=7
 end
end
M.onPreRender=onPreRender
M.onUpdate=onUpdate
M.receive=receive
return M
