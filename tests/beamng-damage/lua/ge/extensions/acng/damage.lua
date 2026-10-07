-- D001 sacrificial stock scene; original installations/profiles untouched.
local M={}
local elapsed,stageTime,phase,obstacleId=0,0,0,nil
local wallStart=os.time()
local result={test='D001 native damage observer',completed=false,events={},snapshots={},
  model='etkc',config='kc6_360_M',master_during_damage=true,peak_speed_m_s=0}
local function save() jsonWriteFile('/acng-damage.json',result,true) end
local function event(name,veh)
  local p=veh:getPosition()
  result.events[#result.events+1]={name=name,ge_real_elapsed_s=elapsed,
    speed_m_s=veh:getVelocity():length(),position_m={p.x,p.y,p.z},
    acng=extensions.acng_core.getStatus()}
  log('I','ACNG_D001',name);save()
end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function probe(veh,label)
  command(veh,string.format("extensions.load('acng_damageProbe'); extensions.acng_damageProbe.snapshot(%q)",label))
end
local function deleteObstacle()
  if obstacleId then
    local obstacle=be:getObjectByID(obstacleId)
    if obstacle and obstacle~=be:getPlayerVehicle(0) then obstacle:delete() end
    obstacleId=nil
  end
end
local function receive(text)
  result.snapshots[#result.snapshots+1]=jsonDecode(text);save()
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if os.time()-wallStart>220 and phase<12 then
    if extensions.acng_core then extensions.acng_core.setTelemetryEnabled(false) end
    deleteObstacle();result.failure='220-second host watchdog';save();phase=12
  end
  if phase==0 and elapsed>10 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 or phase==12 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime=stageTime+dtSim
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'})
    phase,stageTime=2,0
  elseif phase==2 and stageTime>1 then
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1))
    local obstacle=core_vehicles.spawnNewVehicle('pickup',{autoEnterVehicle=false,
      pos=vec3(0,45,1),rot=quat(0,0,1,0)})
    if not obstacle then result.failure='obstacle spawn failed';save();phase=12;return end
    obstacleId=obstacle:getID()
    phase,stageTime=3,0
  elseif phase==3 and stageTime>2 then
    local obstacle=be:getObjectByID(obstacleId)
    spawn.safeTeleport(obstacle,vec3(0,45,1),quat(0,0,1,0))
    command(obstacle,"controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('brake',1,1); input.event('parkingbrake',1,1); input.event('throttle',0,1)")
    phase,stageTime=4,0
  elseif phase==4 and stageTime>8 then
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setTelemetryEnabled(true)
    command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,1); input.event('throttle',0,1)")
    event('baseline',veh);probe(veh,'baseline')
    phase,stageTime=5,0
  elseif phase==5 and stageTime>3 then
    event('accelerate_into_stock_obstacle',veh)
    command(veh,"input.event('throttle',1,1)")
    phase,stageTime=6,0
  elseif phase==6 then
    result.peak_speed_m_s=math.max(result.peak_speed_m_s,veh:getVelocity():length())
    if stageTime>8 then
      command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('throttle',0,1); input.event('brake',1,1)")
      event('post_collision',veh);probe(veh,'post_collision')
      phase,stageTime=7,0
    end
  elseif phase==7 and stageTime>15 then
    deleteObstacle()
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1))
    event('repair_reset',veh)
    phase,stageTime=8,0
  elseif phase==8 and stageTime>5 then
    probe(veh,'after_repair')
    command(veh,"extensions.load('acng_damageProbe'); extensions.acng_damageProbe.puncture()")
    event('native_puncture',veh)
    phase,stageTime=9,0
  elseif phase==9 and stageTime>6 then
    probe(veh,'after_puncture')
    command(veh,"extensions.acng_damageProbe.breakWheel()")
    event('native_wheel_break',veh)
    phase,stageTime=10,0
  elseif phase==10 and stageTime>8 then
    probe(veh,'after_wheel_break')
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1))
    event('final_repair_reset',veh)
    phase,stageTime=11,0
  elseif phase==11 and stageTime>5 then
    probe(veh,'final_repaired')
    extensions.acng_core.setTelemetryEnabled(false)
    extensions.acng_core.setEnabled(false)
    result.completed=true;event('complete',veh);phase=12
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
