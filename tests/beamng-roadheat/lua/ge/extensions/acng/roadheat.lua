-- FR001c isolated sustained tire heat and pressure check; not distributed in the mod.
-- FR001 only proved the Road preset over a short moderate run. This drives the stock etkc
-- through the T007 lap-like cycle (limit corner, fast straight, brake) for longer, once
-- with ACNG tires off (native pressure baseline), once on Road and once on Sport, all
-- chosen through the real acng_core preset switch. A reset between sets gives fresh
-- ambient tires. Samples every tire once a second; scripts/analyze_tirecool.py reads it.
local M={}
local elapsed,stageTime,phase,simTime,controlTime,sampleTime,saveTime=0,0,0,0,0,0,0
local CORNER_S,STRAIGHT_S,CYCLES,PARK_S=20,15,16,60
local CORNER_STEER,CORNER_SPEED,STRAIGHT_SPEED,BRAKE_TO=0.5,10,38,12
local SETS={{name='OFF',tires=false},{name='road',tires=true},{name='sport',tires=true}}
local result={schema_version=1,test='FR001c sustained tire heat and pressure, OFF/Road/Sport',model='etkc',config='kc6_360_M',completed=false,
  cycle={corner_s=CORNER_S,straight_s=STRAIGHT_S,cycles=CYCLES,park_s=PARK_S,corner_steer=CORNER_STEER,
    corner_speed_m_s=CORNER_SPEED,straight_speed_m_s=STRAIGHT_SPEED,brake_to_m_s=BRAKE_TO},
  sets={},events={},checks={}}
local setIndex,cur,drive,cycle=0,nil,nil,0
local function save() jsonWriteFile('/acng-roadheat-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_FR001c',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngFR3",{})
function acngFR3.sample(tag)
  local loaded=extensions.isExtensionLoaded('acng_tires')
  local h=loaded and extensions.acng_tires.HEAT or nil
  local snap=loaded and extensions.acng_tires.getSnapshot() or nil
  local out={tag=tag,loaded=loaded,profile=snap and snap.profile or nil,friction=h and h.friction or nil,env=h and h.nodeToEnv or nil,w={}}
  for _,wd in pairs(wheels.wheelRotators) do
    if wd.hasTire then
      local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
      local pa=pg and obj:getGroupPressure(pg) or nil
      out.w[wd.name]={s=obj:getWheelAvgTemperature(wd.wheelID)-273.15,c=obj:getWheelCoreTemperature(wd.wheelID)-273.15,
        psi=pa and (pa-101325)/6894.757 or nil}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_roadheat.receive(%q)',jsonEncode(out)))
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
    if not FS:getUserPath():gsub('\\','/'):lower():match('/acng%-roadheat%-[%w%-]+/current/?$') then
      result.error='Fresh isolated roadheat profile required';save();phase=99;return
    end
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  if cur then
    sampleTime=sampleTime+dtSim
    if sampleTime>=1 then sampleTime=0;command(veh,'acngFR3.sample("s")') end
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
    result.checks.default_profile_road=status().tire_profile=='road'
    extensions.acng_core.setEnabled(true)
    event('enabled');phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    setIndex=setIndex+1
    local set=SETS[setIndex]
    if not set then phase,stageTime=30,0;return end
    cur={name=set.name,samples={}}
    result.sets[#result.sets+1]=cur
    if set.tires then extensions.acng_core.setTireProfile(set.name) end
    extensions.acng_core.setFeature('tire_temperature',set.tires)
    event(set.name..'_select');phase,stageTime=11,0
  elseif phase==11 and stageTime>3 then
    local st=status()
    cur.core_profile=st.tire_profile;cur.core_physics_writes=st.physics_writes
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    event(cur.name..'_reset');phase,stageTime=12,0
  elseif phase==12 and stageTime>4 then
    cycle=1;sampleTime=1;setDrive(veh,'corner',CORNER_STEER);event(cur.name..'_drive');phase,stageTime=13,0
  elseif phase==20 and stageTime>PARK_S then
    command(veh,'acngFR3.sample("park_end")');phase,stageTime=21,0
  elseif phase==21 and stageTime>1 then
    phase,stageTime=10,0
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
