-- T002 isolated native tire-thermal coefficient sweep only; not distributed in the mod.
-- Each trial resets the stock car (fresh temperatures), applies one set of native wheel
-- thermal coefficients (wobj:setThermal), drives steady circles, then parks. T002a showed
-- the native model integrates nothing while heatCoefNodeToEnv is 0, so every heat trial
-- keeps a small environment coefficient. Coefficients escalate until the tires warm.
local M={}
local elapsed,stageTime,phase,simTime,controlTime,sampleTime=0,0,0,0,0,0
local STEER,SPEED,DRIVE_S,PARK_S,WARM_K=0.25,12,25,10,15
local ENV=1e-4
local result={test='T002 tire thermal sweep',model='etkc',config='kc6_360_M',completed=false,
  params='nodeToEnv,envMultStationary,envTerminalSpeed,nodeToCore,coreToNodes,nodeToSurface,friction,flashFriction,strain,smokingTemp,meltingTemp,heatAffectsPressure',
  env_k=nil,trials={},samples={},events={},found={}}
local SOURCES={{name='friction',index=7},{name='strain',index=9},{name='flashFriction',index=8}}
local HEAT={1e-7,1e-6,1e-5,1e-4,1e-3,1e-2,1e-1,1}
local latest,trial,queue=nil,nil,{}
local src,val=1,1
local function save() jsonWriteFile('/acng-tires-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T002',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local HELPER=[[
rawset(_G,"acngT2",{})
function acngT2.apply(p)
  local n=0
  for _,wd in pairs(wheels.wheelRotators) do
    local w=obj:getWheel(wd.wheelID)
    if w and wd.hasTire then w:setThermal(p[1],p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12]);n=n+1 end
  end
  obj:queueGameEngineLua('extensions.acng_tiregate.applied('..n..')')
end
function acngT2.sample()
  local out={}
  for _,wd in pairs(wheels.wheelRotators) do
    if wd.hasTire then
      local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
      out[#out+1]={name=wd.name,avg=obj:getWheelAvgTemperature(wd.wheelID),core=obj:getWheelCoreTemperature(wd.wheelID),
        pa=pg and obj:getGroupPressure(pg) or nil}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_tiregate.receive(%q)',jsonEncode(out)))
end
]]
local function params(o)
  local p={0,0.4,20,0,0,0,0,0,0,1e18,1e19,false}
  for i,v in pairs(o) do p[i]=v end
  return p
end
local function apply(veh,p)
  local parts={}
  for i=1,11 do parts[i]=string.format('%.9g',p[i]) end
  parts[12]=tostring(p[12])
  command(veh,'acngT2.apply({'..table.concat(parts,',')..'})')
end
local function stats(s)
  local t,n,mx,core=0,0,-1e30,0
  for _,w in ipairs(s or {}) do t=t+w.avg;n=n+1;mx=math.max(mx,w.avg);core=core+w.core end
  if n==0 then return nil end
  return {mean=t/n,max=mx,core=core/n}
end
local function receive(text)
  latest=jsonDecode(text) or {}
  result.samples[#result.samples+1]={t=simTime,trial=trial and trial.label or 'pre',part=trial and trial.part or nil,wheels=latest}
  if #result.samples%40==0 then save() end
end
local function applied(n) result.wheels_applied=n end
local function nextHeatTrial()
  local s=SOURCES[src]
  return {label=s.name..'='..HEAT[val],kind='heat',source=s.name,value=HEAT[val],p=params({[1]=ENV,[s.index]=HEAT[val]})}
end
-- Called after each trial; decides the next one.
local function plan(done)
  if done.kind=='heat' then
    if done.drive_rise_k>WARM_K or val==#HEAT then
      if done.drive_rise_k>WARM_K then result.found[done.source]=done.value end
      src,val=src+1,1
      if src>#SOURCES then
        local f=result.found.friction or result.found.strain or 1e-3
        local idx=result.found.friction and 7 or 9
        for _,e in ipairs({1e-3,1e-2,1e-1}) do queue[#queue+1]={label='cooling env='..e,kind='cool',value=e,p=params({[1]=e,[idx]=f})} end
        for _,c in ipairs({1e-4,1e-3,1e-2}) do queue[#queue+1]={label='core='..c,kind='core',value=c,p=params({[1]=ENV,[idx]=f,[4]=c,[5]=c})} end
        return table.remove(queue,1)
      end
    else
      val=val+1
    end
    return nextHeatTrial()
  end
  return table.remove(queue,1)
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
  if phase>=3 and phase<9 then
    sampleTime=sampleTime+dtSim
    if sampleTime>0.5 then sampleTime=0;command(veh,'acngT2.sample()') end
  end
  if phase==5 then
    controlTime=controlTime+dtReal
    if controlTime>0.1 then
      controlTime=0
      local speed=veh:getVelocity():length()
      command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(SPEED-speed)))))
    end
  end
  local s=stats(latest)
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER)
    event('spawned');phase,stageTime=3,0
  elseif phase==3 and stageTime>3 and s then
    result.env_k=s.mean
    trial={label='stock',kind='stock',p=nil}
    phase,stageTime=4,0
  elseif phase==4 then
    -- Reset for fresh temperatures, then apply this trial's coefficients.
    if stageTime<0.05 then
      command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    elseif stageTime>3 and not trial.applied then
      if trial.p then apply(veh,trial.p) end
      trial.applied=true
      command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('steering',"..STEER..",2)")
    elseif stageTime>4 and s then
      trial.start=s;trial.part='drive'
      phase,stageTime=5,0
    end
  elseif phase==5 and stageTime>DRIVE_S then
    trial.after_drive=s;trial.drive_rise_k=s.mean-trial.start.mean;trial.part='park'
    command(veh,"input.event('throttle',0,1); input.event('brake',1,1)")
    phase,stageTime=6,0
  elseif phase==6 and stageTime>PARK_S then
    trial.after_park=s;trial.park_drop_k=trial.after_drive.mean-s.mean
    result.trials[#result.trials+1]=trial
    log('I','ACNG_T002',string.format('%s rise=%.3f drop=%.3f',trial.label,trial.drive_rise_k,trial.park_drop_k))
    local nxt
    if trial.kind=='stock' then nxt=nextHeatTrial() else nxt=plan(trial) end
    save()
    if nxt then trial=nxt;phase,stageTime=4,0
    else
      command(veh,'acngT2.apply({0,0.4,20,0,0,0,0,0,0,1e18,1e19,false})')
      result.completed=true;event('complete');phase=9
    end
  end
end
M.onUpdate=onUpdate
M.receive=receive
M.applied=applied
return M
