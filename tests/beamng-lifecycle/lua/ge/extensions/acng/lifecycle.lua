-- Sacrificial isolated stock-vehicle lifecycle experiment, not production mod.
local M={}
local elapsed,stageTime,phase=0,0,0
local result={test='L001 passive observer reset/reload/switch',events={},completed=false}
local function record(name,veh)
  result.events[#result.events+1]={name=name,real_time_s=elapsed,
    vehicle_id=veh and veh:getID(),model=veh and veh:getJBeamFilename(),
    acng=extensions.acng_core and extensions.acng_core.getStatus()}
  jsonWriteFile('/acng-lifecycle.json',result,true)
  log('I','ACNG_L001',name)
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>10 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/')
    phase=1
    return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime=stageTime+dtReal
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'})
    phase,stageTime=2,0
  elseif phase==2 and stageTime>5 then
    extensions.acng_core.setEnabled(false)
    extensions.acng_core.setTelemetryEnabled(true)
    record('initial_capture',veh)
    phase,stageTime=3,0
  elseif phase==3 and stageTime>6 then
    record('reset_requested',veh)
    be:resetVehicle(0)
    phase,stageTime=4,0
  elseif phase==4 and stageTime>6 then
    record('same_model_reload_requested',veh)
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'})
    phase,stageTime=5,0
  elseif phase==5 and stageTime>8 then
    record('different_model_switch_requested',veh)
    core_vehicles.replaceVehicle('pickup',{})
    phase,stageTime=6,0
  elseif phase==6 and stageTime>8 then
    record('stop_requested',veh)
    extensions.acng_core.setTelemetryEnabled(false)
    phase,stageTime=7,0
  elseif phase==7 and stageTime>3 then
    record('complete',veh)
    result.completed=true
    jsonWriteFile('/acng-lifecycle.json',result,true)
    phase=8
  end
  if elapsed>150 and phase<8 then
    extensions.acng_core.setTelemetryEnabled(false)
    result.failure='150-second watchdog'
    record('failed',veh)
    phase=8
  end
end
M.onUpdate=onUpdate
return M
