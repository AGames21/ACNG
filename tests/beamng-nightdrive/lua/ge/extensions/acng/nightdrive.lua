-- V003 isolated stock-car cinematics. Native AI drives only this lab's player car.
local M={}
local elapsed,stage,sim,phase,frames=0,0,0,0,0
local shot=nil
local shots={'front','side','door','rear'}
local result={schema_version=1,test='V003 West Coast night drive',model='barstow',
 config='423m_sport',level='west_coast_usa',time_of_day=0.38,
 completed=false,checks={},samples={},errors={},shots={}}
local cues={schema_version=1,cues={}}
local function save() jsonWriteFile('/acng-nightdrive-test.json',result,true) end
local function cue(name)
 cues.cues[#cues.cues+1]={name=name,seq=#cues.cues+1,sim_time_s=sim}
 jsonWriteFile('/acng-film-cues.json',cues,true)
end
local function receive(text)
 local d=jsonDecode(text);d.t=sim;result.samples[#result.samples+1]=d;save()
end
local function sample(veh)
 veh:queueLuaCommand([[obj:queueGameEngineLua(string.format('extensions.acng_nightdrive.receive(%q)',jsonEncode({speed_m_s=obj:getVelocity():length(),headlights=electrics.values.lowbeam,damage=beamstate.damage}))) ]])
end
local function onPreRender()
 if not shot then return end
 local veh=be:getPlayerVehicle(0);if not veh then return end
 local ok,err=pcall(function()
  local f=veh:getDirectionVector():normalized();local up=veh:getDirectionVectorUp():normalized()
  local p=veh:getWorldBox():getCenter();local left=up:cross(f):normalized()
  local eye,target
  if shot=='front' then eye=p+f*6+left*3+up*0.8;target=p+f*0.6+up*0.65
  elseif shot=='side' then eye=p+left*6-f*1+up*1;target=p+up*0.7
  elseif shot=='door' then eye=p+left*2.3-f*0.6+up*0.45;target=p+left*0.82+f*1.3-up*0.3
  else eye=p-f*6+left*2+up*1.2;target=p+up*0.8 end
  local q=quatFromDir((target-eye):normalized(),up)
  core_camera.setPosRot(0,eye.x,eye.y,eye.z,q.x,q.y,q.z,q.w)
  veh:setMeshAlpha(1,'',false)
  frames=frames+1;result.shots[shot]=true
 end)
 if not ok then result.errors[#result.errors+1]=tostring(err);shot=nil;save() end
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
  core_vehicles.replaceVehicle('barstow',{config='vehicles/barstow/423m_sport.pc',color=ColorF(0.02,0.45,0.5,1)});phase,stage=2,0
 elseif phase==2 and stage>8 and veh:getJBeamFilename()=='barstow' then
  guihooks.trigger('ChangeState',{state='play'})
  result.original_mesh_alpha=veh:getMeshAlpha('')
  veh:setMeshAlpha(1,'',false)
  core_environment.setTimeOfDay({time=0.38,play=false})
  veh:queueLuaCommand("electrics.setLightsState(1);controller.mainController.setGearboxMode('arcade');input.event('parkingbrake',0,1);ai.setMode('span');ai.driveInLane('on');ai.setSpeedMode('limit');ai.setSpeed(15);ai.setAggression(0.35)")
  commands.setFreeCamera();phase,stage=3,0
 elseif phase==3 and stage>4 then
  shot='front';cue('front_start');cue('drive_start');phase,stage=4,0
 elseif phase==4 then
  local i=math.min(4,math.floor(stage/10)+1)
  if shot~=shots[i] then cue(shot..'_end');shot=shots[i];cue(shot..'_start') end
  local bucket=math.floor(stage)
  if bucket>(result.last_bucket or -1) then result.last_bucket=bucket;sample(veh) end
  if stage>40 then
   cue(shot..'_end');cue('drive_end');shot=nil
   veh:queueLuaCommand("ai.setMode('disabled');input.event('throttle',0,1);input.event('brake',1,1)")
   phase,stage=5,0
  end
 elseif phase==5 and stage>3 then
  local max,lit=0,false
  for _,s in ipairs(result.samples) do max=math.max(max,s.speed_m_s or 0);lit=lit or s.headlights==1 or s.headlights==true end
  local tod=core_environment.getTimeOfDay();result.environment=tod;result.camera_frames=frames;result.max_speed_m_s=max
  result.checks.stock_barstow=veh:getJBeamFilename()=='barstow'
  result.checks.night_time=tod~=nil and math.abs((tod.time or -1)-0.38)<0.002
  result.checks.car_actually_driven=max>5 and #result.samples>=30
  result.checks.headlights_on=lit
  result.checks.all_camera_shots=frames>300 and result.shots.front and result.shots.side and result.shots.door and result.shots.rear or false
  result.checks.no_camera_errors=#result.errors==0
  result.passed=true;for _,v in pairs(result.checks) do result.passed=result.passed and v==true end
  result.completed=true;save();cue('complete');phase=6
 end
end
M.onUpdate=onUpdate;M.onPreRender=onPreRender;M.receive=receive
return M
