-- Isolated B001 pilot only. Stock car, controller inputs, no physics parameter writes.
local M = {}
local realTime, stageTime = 0, 0
local phase = 0
local result = {test='B001 stock straight-line pilot', model='etkc', config='kc6_360_M',
  assists='factory', gearbox_behavior='arcade acceleration; realistic braking', master=false, events={}, pilot=true}
local function event(name, veh)
  result.events[#result.events+1]={name=name,stage_sim_time_s=stageTime,speed_m_s=veh and veh:getVelocity():length() or nil}
  log('I','ACNG_B001',name)
end
local function command(veh, text) veh:queueLuaCommand(text) end
local function onUpdate(dtReal, dtSim)
  realTime = realTime + dtReal
  if phase == 0 and realTime > 10 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/')
    phase = 1
    return
  end
  if worldReadyState ~= 2 then return end
  local veh = be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime = stageTime + dtSim
  if phase == 1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'})
    phase, stageTime = 2, 0
  elseif phase == 2 and stageTime > 8 and veh:getJBeamFilename() == 'etkc' then
    extensions.acng_core.setEnabled(false)
    extensions.acng_core.setTelemetryEnabled(true)
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('parkingbrake',0,1); input.event('throttle',0,1); input.event('brake',1,1); input.event('steering',0,1)")
    event('settle',veh)
    phase,stageTime = 3,0
  elseif phase == 3 and stageTime > 5 then
    command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('brake',0,1); input.event('throttle',1,1)")
    event('accelerate',veh)
    phase,stageTime = 4,0
  elseif phase == 4 and (veh:getVelocity():length() > 46 or stageTime > 35) then
    event('brake',veh)
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('brake',1,1)")
    phase,stageTime = 5,0
  elseif phase == 5 and stageTime > 10 and veh:getVelocity():length() < 0.1 then
    event('stopped',veh)
    extensions.acng_core.setTelemetryEnabled(false)
    result.completed=true
    jsonWriteFile('/acng-b001.json',result,true)
    phase=6
  elseif phase == 5 and stageTime > 35 then
    command(veh,"input.event('throttle',0,1); input.event('brake',1,1)")
    extensions.acng_core.setTelemetryEnabled(false)
    result.completed=false
    result.failure='did not stop in 35 simulation seconds'
    jsonWriteFile('/acng-b001.json',result,true)
    phase=6
  end
end
M.onUpdate=onUpdate
return M
