local M={}
local phase,time,stage,run,clock=0,0,0,1,os.time()
local factors={0,0.0001,0.01}
local result={test='T001 native heating capability',completed=false,events={},snapshots={},factors=factors,pressure_effect=false,grip_effect=false}
local function save() jsonWriteFile('/acng-t001.json',result,true) end
local function receive(text) local s=jsonDecode(text);s.run=run;result.snapshots[#result.snapshots+1]=s;save() end
local function command(v,text) v:queueLuaCommand(text) end
local function event(name,v)
 result.events[#result.events+1]={name=name,run=run,factor=factors[run],time=time,speed=v:getVelocity():length()};save()
end
local function onUpdate(dt,simdt)
 time=time+dt
 if os.time()-clock>360 and phase<9 then
  result.failure='Host watchdog';extensions.acng_core.setTelemetryEnabled(false);save();phase=9
 end
 if phase==0 and time>10 and core_modmanager.isReady() then freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return end
 if worldReadyState~=2 or phase==9 then return end
 local v=be:getPlayerVehicle(0);if not v or not extensions.acng_core then return end
 stage=stage+simdt
 if phase==1 then
  extensions.acng_core.setTelemetryEnabled(false)
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase=2;stage=0
 elseif phase==2 and stage>1 then
  spawn.safeTeleport(v,vec3(0,0,1),quat(0,0,0,1));phase=3;stage=0
 elseif phase==3 and stage>8 then
  command(v,"extensions.load('acng_thermalProbe'); extensions.acng_thermalProbe.configure("..factors[run]..")")
  extensions.acng_core.setTelemetryEnabled(true);event('configured',v);phase=4;stage=0
 elseif phase==4 and stage>3 then
  command(v,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('throttle',1,1)")
  event('accelerate',v);phase=5;stage=0
 elseif phase==5 and (v:getVelocity():length()>46 or stage>25) then
  command(v,"controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('throttle',0,1); input.event('brake',1,1)")
  event('brake',v);phase=6;stage=0
 elseif phase==6 and stage>8 then
  command(v,"extensions.acng_thermalProbe.snapshot('after_braking'); extensions.acng_thermalProbe.restore()")
  event('restored',v);phase=7;stage=0
 elseif phase==7 and stage>3 then
  extensions.acng_core.setTelemetryEnabled(false)
  if run<#factors then run=run+1;phase=1;stage=0 else result.completed=true;save();phase=9 end
 end
end
M.onUpdate=onUpdate
M.receive=receive
return M
