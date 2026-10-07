-- B002 five-repeat stock straight-line collection. Test controls only.
local M={}
local realTime,simTime,stageTime,phase,runIndex=0,0,0,0,1
local result={test='B002 stock ETK straight-line repeats',model='etkc',config='kc6_360_M',
  master=false,requested_runs=5,runs={},events={},completed=false,
  controls='arcade acceleration; realistic braking with clutch depressed',
  spawn={position={0,0,1},rotation={0,0,0,1}},assists='factory unchanged'}
local function command(veh,text) veh:queueLuaCommand(text) end
local function save() jsonWriteFile('/acng-b002.json',result,true) end
local function event(name,veh)
  local pos=veh:getPosition()
  local status=extensions.acng_core.getStatus()
  local item={name=name,run=runIndex,real_time_s=realTime,sim_time_s=simTime,
    speed_m_s=veh:getVelocity():length(),position_m={pos.x,pos.y,pos.z},
    capture_id=status.attached_capture_id,vehicle_id=veh:getID()}
  result.events[#result.events+1]=item
  log('I','ACNG_B002',name..' run='..runIndex)
  save()
  return item
end
local function spawnRun()
  extensions.acng_core.setTelemetryEnabled(false)
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc',
    pos=vec3(0,0,1),rot=quat(0,0,0,1)})
  phase,stageTime=2,0
end
local function onUpdate(dtReal,dtSim)
  realTime,simTime=realTime+dtReal,simTime+dtSim
  if phase==0 and realTime>10 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/')
    phase=1
    return
  end
  if realTime>550 and phase<8 then
    if extensions.acng_core then extensions.acng_core.setTelemetryEnabled(false) end
    result.failure='550-second wall-clock watchdog'; save(); phase=8
  end
  if worldReadyState~=2 or phase==8 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime=stageTime+dtSim
  if phase==1 then
    extensions.acng_core.setEnabled(false)
    extensions.acng_core.setTelemetryEnabled(true)
    spawnRun()
  elseif phase==2 and stageTime>1 then
    -- replaceVehicle reuses the prior object's transform despite opt.pos/rot.
    -- Apply the native safe teleport after the new vehicle has initialized.
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1))
    phase,stageTime=9,0
  elseif phase==9 and stageTime>8 then
    extensions.acng_core.setTelemetryEnabled(true)
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('parkingbrake',0,1); input.event('clutch',1,1); input.event('throttle',0,1); input.event('brake',1,1); input.event('steering',0,1)")
    event('settle',veh)
    phase,stageTime=3,0
  elseif phase==3 and stageTime>3 then
    event('accelerate',veh)
    command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('clutch',0,1); input.event('brake',0,1); input.event('throttle',1,1)")
    phase,stageTime=4,0
  elseif phase==4 and veh:getVelocity():length()>46 then
    event('brake',veh)
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('throttle',0,1); input.event('brake',1,1)")
    phase,stageTime=5,0
  elseif phase==4 and stageTime>25 then
    result.failure='did not exceed100mph in25sim seconds'; event('failed',veh)
    command(veh,"input.event('throttle',0,1); input.event('clutch',1,1); input.event('brake',1,1)")
    extensions.acng_core.setTelemetryEnabled(false); phase=8
  elseif phase==5 and stageTime>0.5 and veh:getVelocity():length()<0.1 then
    event('stopped',veh)
    phase,stageTime=6,0
  elseif phase==5 and stageTime>20 then
    result.failure='did not stop in20sim seconds'; event('failed',veh)
    extensions.acng_core.setTelemetryEnabled(false); phase=8
  elseif phase==6 and stageTime>2 then
    local finish=event('run_complete',veh)
    result.runs[#result.runs+1]={run=runIndex,capture_id=finish.capture_id,
      vehicle_id=finish.vehicle_id,completed=true}
    save()
    if runIndex<5 then
      runIndex=runIndex+1
      spawnRun()
    else
      extensions.acng_core.setTelemetryEnabled(false)
      result.completed=true; save(); phase=8
    end
  end
end
M.onUpdate=onUpdate
return M
