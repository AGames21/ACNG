-- T003 isolated native grip-versus-temperature curve probe only; not distributed in the mod.
-- The native heat model stays off, so tire temperature stays at the environment value.
-- Each trial resets the stock car, applies one wobj:setFrictionThermalSensitivity curve,
-- drives a fixed steering input at a held speed and measures the circle it actually holds
-- (yaw rate -> radius and lateral acceleration). Less grip -> wider circle.
local M={}
local elapsed,stageTime,phase,controlTime,sampleTime=0,0,0,0,0
local STEER,SPEED,SETTLE_S,MEASURE_S=0.5,10,10,8
local result={test='T003c native grip curve calibration',model='etkc',config='kc6_360_M',completed=false,
  curve_params='lowTemp,highTemp,lowSlope,highSlope,smoothCoef,coefLow,coefMiddle,coefHigh',
  trials={},events={}}
-- Stock (engine default) curve is flat 1.0.
local STOCK={-300,1e7,1e-10,1e-10,10,1,1,1}
-- T003c: half lock at a held 10 m/s keeps the front tires at their limit without the
-- speed collapsing (T003b at full lock was grip-and-wheelspin limited). Tire at 288.15 K.
-- Calibrates coefMiddle, checks coefLow against it, then maps the low-side slope.
local TRIALS={
  {label='stock',curve=STOCK},
  {label='middle=0.9',curve={-300,1e7,1e-10,1e-10,10,1,0.9,1}},
  {label='middle=0.8',curve={-300,1e7,1e-10,1e-10,10,1,0.8,1}},
  {label='middle=0.6',curve={-300,1e7,1e-10,1e-10,10,1,0.6,1}},
  {label='low d=112 slope=1 coefLow=0.8',curve={400,1e7,1,1e-10,10,0.8,1,1}},
  {label='low d=2 slope=0.01 coefLow=0.8',curve={290.15,1e7,0.01,1e-10,10,0.8,1,1}},
  {label='low d=5 slope=0.01 coefLow=0.8',curve={293.15,1e7,0.01,1e-10,10,0.8,1,1}},
  {label='low d=10 slope=0.001 coefLow=0.8',curve={298.15,1e7,0.001,1e-10,10,0.8,1,1}},
  {label='low d=20 slope=0.001 coefLow=0.8',curve={308.15,1e7,0.001,1e-10,10,0.8,1,1}},
  {label='low d=40 slope=0.001 coefLow=0.8',curve={328.15,1e7,0.001,1e-10,10,0.8,1,1}},
  {label='low d=60 slope=0.001 coefLow=0.8',curve={348.15,1e7,0.001,1e-10,10,0.8,1,1}},
  {label='stock again',curve=STOCK},
}
local idx,trial,acc=1,nil,nil
local lastHeading
local function save() jsonWriteFile('/acng-grip-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name};log('I','ACNG_T003',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function applyCurve(veh,c)
  local parts={}
  for i=1,8 do parts[i]=string.format('%.9g',c[i]) end
  command(veh,"for _,wd in pairs(wheels.wheelRotators) do local w=obj:getWheel(wd.wheelID) if w and wd.hasTire then w:setFrictionThermalSensitivity("..table.concat(parts,',')..") end end")
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim
  if phase==4 then
    controlTime=controlTime+dtReal
    if controlTime>0.1 then
      controlTime=0
      local speed=veh:getVelocity():length()
      command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(SPEED-speed)))))
    end
    -- Yaw rate from the heading change; accumulated only in the measuring window.
    local d=veh:getDirectionVector()
    local h=math.atan2(d.y,d.x)
    if lastHeading and dtSim>0 and stageTime>SETTLE_S then
      local dh=h-lastHeading
      if dh>math.pi then dh=dh-2*math.pi elseif dh<-math.pi then dh=dh+2*math.pi end
      acc.yaw=acc.yaw+dh;acc.t=acc.t+dtSim;acc.v=acc.v+veh:getVelocity():length()*dtSim
    end
    lastHeading=h
  end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    event('spawned');trial=TRIALS[idx];phase,stageTime=3,0
  elseif phase==3 then
    if stageTime<0.05 then
      command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    elseif stageTime>3 and not trial.applied then
      applyCurve(veh,trial.curve);trial.applied=true
      command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('steering',"..STEER..",2)")
      command(veh,"obj:queueGameEngineLua('extensions.acng_gripgate.temp('..obj:getWheelAvgTemperature(wheels.wheelRotators[0].wheelID)..')')")
    elseif stageTime>3.5 then
      acc={yaw=0,t=0,v=0};lastHeading=nil
      phase,stageTime=4,0
    end
  elseif phase==4 and stageTime>SETTLE_S+MEASURE_S then
    local w=math.abs(acc.yaw)/acc.t
    local v=acc.v/acc.t
    trial.yaw_rate_rad_s=w;trial.speed_m_s=v;trial.radius_m=v/w;trial.lateral_m_s2=v*w
    trial.applied=nil
    result.trials[#result.trials+1]={label=trial.label,curve=trial.curve,yaw_rate_rad_s=w,speed_m_s=v,radius_m=v/w,lateral_m_s2=v*w,tire_temp_k=result.last_temp}
    log('I','ACNG_T003',string.format('%s R=%.2f a=%.2f v=%.2f',trial.label,v/w,v*w,v))
    save()
    idx=idx+1
    if TRIALS[idx] then trial=TRIALS[idx];phase,stageTime=3,0
    else
      applyCurve(veh,STOCK)
      command(veh,"input.event('throttle',0,1); input.event('brake',1,1)")
      result.completed=true;event('complete');phase=9
    end
  end
end
M.onUpdate=onUpdate
M.temp=function(k) result.last_temp=k end
return M
