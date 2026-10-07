-- T007 isolated in-game tire heat balance sweep; not distributed in the mod. The user found
-- that hot tires stay hot or keep climbing. This drives the stock etkc through lap-like
-- cycles (a limit corner at 10 m/s, then a straight at 38 m/s, then braking) with several
-- candidate acng_tires.HEAT sets, one after another through the real ACNG controls, and
-- samples every tire once a second. A reset between sets brings fresh ambient tires and
-- re-applies the new set. The analysis (heat-up, cooling on straights, whether the cycle
-- peaks settle or keep climbing, park cooling, pressure) runs offline on the saved file.
local M={}
local elapsed,stageTime,phase,simTime,controlTime,sampleTime,saveTime=0,0,0,0,0,0,0
local CORNER_S,STRAIGHT_S,CYCLES,PARK_S=20,15,12,30
local CORNER_STEER,CORNER_SPEED,STRAIGHT_SPEED,BRAKE_TO=0.5,10,38,12
-- T007a swept five sets over 6 cycles (docs/test-results/T007-tire-heat-balance.md).
-- T007b runs the old set and the chosen set over 12 cycles to show whether the core settles.
local SETS={
  {name='A_old',heat={nodeToEnv=0.04,envMultStationary=0.4,envTerminalSpeed=20,nodeToCore=0.01,coreToNodes=0.01,nodeToSurface=0,friction=0.05}},
  {name='F_new',heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.005,coreToNodes=0.005,nodeToSurface=0,friction=0.06}},
}
local result={schema_version=1,test='T007b tire heat balance, old against new',model='etkc',config='kc6_360_M',completed=false,
  cycle={corner_s=CORNER_S,straight_s=STRAIGHT_S,cycles=CYCLES,park_s=PARK_S,corner_steer=CORNER_STEER,
    corner_speed_m_s=CORNER_SPEED,straight_speed_m_s=STRAIGHT_SPEED,brake_to_m_s=BRAKE_TO},
  sets={},events={},checks={}}
local setIndex,cur,drive,cycle=0,nil,nil,0
local function save() jsonWriteFile('/acng-tirecool-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T007',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngT7",{})
function acngT7.sample(tag)
  local loaded=extensions.isExtensionLoaded('acng_tires')
  local h=loaded and extensions.acng_tires.HEAT or nil
  local out={tag=tag,loaded=loaded,friction=h and h.friction or nil,env=h and h.nodeToEnv or nil,w={}}
  for _,wd in pairs(wheels.wheelRotators) do
    if wd.hasTire then
      local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
      local pa=pg and obj:getGroupPressure(pg) or nil
      out.w[wd.name]={s=obj:getWheelAvgTemperature(wd.wheelID)-273.15,c=obj:getWheelCoreTemperature(wd.wheelID)-273.15,
        psi=pa and (pa-101325)/6894.757 or nil}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_tirecool.receive(%q)',jsonEncode(out)))
end
function acngT7.setHeat(text)
  if not extensions.isExtensionLoaded('acng_tires') then return end
  local h=jsonDecode(text)
  h.flashFriction,h.strain,h.heatAffectsPressure=0,0,true
  extensions.acng_tires.HEAT=h
end
]]
local function receive(text)
  local s=jsonDecode(text) or {}
  s.t=simTime;s.phase=drive and drive.name or 'idle';s.cycle=cycle
  local veh=be:getPlayerVehicle(0)
  s.speed=veh and veh:getVelocity():length() or nil
  if cur then cur.samples[#cur.samples+1]=s end
end
local function setDrive(veh,name,steer)
  drive={name=name,t=0}
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',"..steer..",2)")
end
local function stopDrive(veh)
  drive=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function control(veh)
  local speed=veh:getVelocity():length()
  if drive.name=='brake' then
    command(veh,"input.event('throttle',0,1); input.event('brake',0.7,1)")
    return
  end
  local target=drive.name=='corner' and CORNER_SPEED or STRAIGHT_SPEED
  command(veh,string.format("input.event('throttle',%.3f,1); input.event('brake',0,1)",math.max(0,math.min(1,0.25*(target-speed)))))
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  if cur then
    sampleTime=sampleTime+dtSim
    if sampleTime>=1 then sampleTime=0;command(veh,'acngT7.sample("s")') end
  end
  saveTime=saveTime+dtReal
  if saveTime>10 then saveTime=0;save() end
  if drive then
    drive.t=drive.t+dtSim
    controlTime=controlTime+dtReal
    if controlTime>0.1 then controlTime=0;control(veh) end
    local speed=veh:getVelocity():length()
    if drive.name=='corner' and drive.t>=CORNER_S then
      if cycle>=CYCLES then
        stopDrive(veh);event(cur.name..'_park');phase,stageTime=20,0
      else
        setDrive(veh,'straight',0)
      end
    elseif drive.name=='straight' and drive.t>=STRAIGHT_S then
      setDrive(veh,'brake',0)
    elseif drive.name=='brake' and (speed<BRAKE_TO or drive.t>8) then
      cycle=cycle+1;setDrive(veh,'corner',CORNER_STEER)
    end
  end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER)
    result.checks.default_master_off=not status().enabled
    result.checks.default_tires_off=status().features.tire_temperature==false and status().physics_writes==0
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    event('enabled');phase,stageTime=3,0
  elseif phase==3 and stageTime>3 then
    result.checks.core_reports_tires_on=status().tires_vehicle_id==veh:getID() and status().physics_writes==1
    phase=10
  elseif phase==10 then
    setIndex=setIndex+1
    local set=SETS[setIndex]
    if not set then phase,stageTime=30,0;return end
    cur={name=set.name,heat=set.heat,samples={}}
    result.sets[#result.sets+1]=cur
    command(veh,string.format('acngT7.setHeat(%q)',jsonEncode(set.heat)))
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    event(set.name..'_reset');phase,stageTime=11,0
  elseif phase==11 and stageTime>3 then
    cycle=1;sampleTime=1;setDrive(veh,'corner',CORNER_STEER);event(cur.name..'_drive');phase,stageTime=12,0
  elseif phase==20 and stageTime>PARK_S then
    command(veh,'acngT7.sample("park_end")');phase,stageTime=21,0
  elseif phase==21 and stageTime>1 then
    phase=10
  elseif phase==30 then
    extensions.acng_core.setFeature('tire_temperature',false)
    phase,stageTime=31,0
  elseif phase==31 and stageTime>2 then
    result.checks.core_reports_tires_off=status().tires_vehicle_id==nil and status().physics_writes==0
    extensions.acng_core.setEnabled(false)
    cur=nil;result.completed=true;event('complete')
    phase=32
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
