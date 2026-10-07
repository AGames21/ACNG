-- A001 isolated, read-only probe of BeamNG's native driver assists; not distributed in the
-- mod. Spawns several stock cars in turn and records which assist systems each one has:
-- per-wheel ABS in wheels.lua (hasABS, slipRatioTarget, absFrequency), the drivingDynamics
-- CMU supervisors (traction control, brake control, yaw control) with their configs, the
-- older esc controller's current configuration, and the engine throttle-factor names.
-- Nothing is written to the vehicles.
local M={}
local CARS={
  {model='etkc',config='vehicles/etkc/kc6_360_M.pc'},
  {model='vivace'},{model='sunburst'},{model='scintilla'},{model='covet'},
  {model='pickup'},{model='bx'},{model='bolide'},{model='etk800'},{model='fullsize'},
}
local elapsed,stageTime,phase,index=0,0,0,0
local result={schema_version=1,test='A001 native assist probe',completed=false,abs_setting=nil,cars={},events={}}
local function save() jsonWriteFile('/acng-assistprobe-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,real_s=elapsed};log('I','ACNG_A001',name);save() end
local HELPER=[[
rawset(_G,"acngA1",{})
local function safe(f,...) local ok,r=pcall(f,...) if ok then return r end return 'ERR:'..tostring(r) end
function acngA1.probe(tag)
  local out={tag=tag,config=v.config and v.config.partConfigFilename,controllers={},rotators={},engines={},
    hasABS=electrics.values.hasABS,hasTCS=electrics.values.hasTCS,hasESC=electrics.values.hasESC,
    throttleFactor=electrics.values.throttleFactor}
  for name,c in pairs(controller.getAllControllers()) do out.controllers[#out.controllers+1]={name=name,type=c.typeName} end
  local cmu=controller.getControllersByType('drivingDynamics/CMU')[1]
  if cmu then
    out.cmu={supervisors={}}
    for _,s in ipairs(cmu.getSupervisors()) do
      local e={type=s.typeName,isActive=s.isActive}
      if s.getConfig then e.config=safe(s.getConfig) end
      out.cmu.supervisors[#out.cmu.supervisors+1]=e
    end
  end
  for _,esc in ipairs(controller.getControllersByType('esc')) do
    local c=esc.getCurrentConfigData and esc.getCurrentConfigData()
    out.esc=out.esc or {}
    out.esc[#out.esc+1]=c and {name=c.name,escEnabled=c.escEnabled,slipThreshold=c.slipThreshold,
      tcsWheelSpeedThreshold=c.tcsWheelSpeedThreshold,minThrottleFactor=c.minThrottleFactor} or 'no config'
  end
  for i=0,wheels.wheelRotatorCount-1 do
    local wd=wheels.wheelRotators[i]
    out.rotators[#out.rotators+1]={name=wd.name,hasABS=wd.hasABS,slipRatioTarget=wd.slipRatioTarget,
      absFrequency=wd.absFrequency,usesABS=wd.updateBrake==wd.updateBrakeABS,brakeTorque=wd.brakeTorque}
  end
  local engines=safe(powertrain.getDevicesByCategory,'engine')
  if type(engines)=='table' then
    for _,e in pairs(engines) do
      out.engines[#out.engines+1]={name=e.name,type=e.type,throttleFactorName=e.electricsThrottleFactorName,throttleFactor=e.throttleFactor}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_assistprobe.receive(%q)',jsonEncode(out)))
end
]]
local function receive(text)
  local s=jsonDecode(text) or {raw=text}
  local car=CARS[index]
  s.model=car and car.model
  result.cars[#result.cars+1]=s
  save()
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 or phase>=20 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtReal
  if phase==1 then
    result.abs_setting=settings.getValue('absBehavior')
    index=1;phase,stageTime=2,0
    local car=CARS[index]
    core_vehicles.replaceVehicle(car.model,car.config and {config=car.config} or {})
  elseif phase==2 then
    local car=CARS[index]
    local ok=be:getPlayerVehicle(0):getJBeamFilename()==car.model
    if ok and stageTime>6 then
      veh:queueLuaCommand(HELPER)
      veh:queueLuaCommand(string.format('acngA1.probe(%q)',car.model))
      phase,stageTime=3,0
    elseif stageTime>30 then
      result.cars[#result.cars+1]={model=car.model,error='did not spawn'}
      event('spawn_timeout_'..car.model);phase,stageTime=3,0
    end
  elseif phase==3 and stageTime>2 then
    event('probed_'..CARS[index].model)
    index=index+1
    if index>#CARS then
      result.completed=true;event('complete');phase=20
    else
      local car=CARS[index]
      core_vehicles.replaceVehicle(car.model,car.config and {config=car.config} or {})
      phase,stageTime=2,0
    end
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
