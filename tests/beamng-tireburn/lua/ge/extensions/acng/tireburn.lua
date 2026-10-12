-- T009f stock Barstow burnout showcase. WEAR x10 is explicitly recorded, not stock rate.
-- Never forces tread to zero or calls deflateTire: ACNG's existing wear model must do it.
local M={}
local elapsed,stage,phase,sim,n=0,0,0,0,0
local result={test='T009f burnout and native wear puncture',model='barstow',config='423m_sport',
  schema_version=1,wear_rate=10,completed=false,checks={},samples={},errors={}}
local cues={schema_version=1,cues={}}
local popped=false
local function save() jsonWriteFile('/acng-tireburn-test.json',result,true) end
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
 obj:queueGameEngineLua(string.format('extensions.acng_tireburn.receive(%q)',jsonEncode(out)))
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
local function camera(veh)
 local f=veh:getDirectionVector():normalized();local up=veh:getDirectionVectorUp():normalized()
 local p=veh:getSpawnWorldOOBB():getCenter()-up*0.55
 local left=up:cross(f):normalized()
 local target=p+left*0.9-f*1.25+up*0.35
 local eye=target+left*2-f*1+up*0.6
 local q=quatFromDir((target-eye):normalized(),up)
 core_camera.setPosRot(0,eye.x,eye.y,eye.z,q.x,q.y,q.z,q.w)
end
local function onPreRender()
 if phase>=5 and phase<=6 then local veh=be:getPlayerVehicle(0);if veh then camera(veh) end end
end
local function onUpdate(dtReal,dtSim)
 elapsed=elapsed+dtReal
 if phase==0 and elapsed>12 and core_modmanager.isReady() then
  freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
 end
 if worldReadyState~=2 then return end
 local veh=be:getPlayerVehicle(0);if not veh then return end
 stage=stage+dtSim;sim=sim+dtSim
 if phase==1 then
  core_vehicles.replaceVehicle('barstow',{config='vehicles/barstow/423m_sport.pc'});phase,stage=2,0
 elseif phase==2 and stage>8 and veh:getJBeamFilename()=='barstow' then
  guihooks.trigger('ChangeState',{state='play'})
  extensions.acng_core.setEnabled(true);extensions.acng_core.setFeature('tire_temperature',true)
  extensions.acng_core.setFeature('tire_wear',true);extensions.acng_core.setTireProfile('road')
  phase,stage=3,0
 elseif phase==3 and stage>3 then
  veh:queueLuaCommand(HELPER)
  veh:queueLuaCommand("extensions.acng_tires.setWearRate(10); controller.mainController.setGearboxMode('realistic'); controller.mainController.shiftToGearIndex(1); input.event('clutch',1,1); input.event('throttle',1,1); input.event('parkingbrake',0,1); input.event('brake',0.24,1)")
  commands.setFreeCamera();phase,stage=4,0
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
  result.passed=true;for _,v in pairs(result.checks) do result.passed=result.passed and v==true end
  result.completed=true;save();cue('complete');phase=7
 end
end
M.onPreRender=onPreRender
M.onUpdate=onUpdate
M.receive=receive
return M
