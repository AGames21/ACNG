-- T004 isolated in-game validation of the shipped tire feature only; not distributed in
-- the mod. Drives the stock etkc in steady half-lock circles at a held 10 m/s through the
-- real ACNG controls (acng_core.setEnabled / setFeature), measuring the circle it holds
-- (yaw rate -> lateral acceleration) per 5 s window while sampling tire temperature,
-- pressure and the grip the feature wrote. Sequence: OFF baseline, ON cold, warm-up,
-- parked cool-down, flat tire, OFF again.
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local STEER,SPEED,WINDOW_S=0.5,10,5
local AMBIENT_K=288.15
local result={test='T004 tire model in-game validation',model='etkc',config='kc6_360_M',completed=false,
  checks={},windows={},samples={},events={},summary={}}
local driving,part,win,lastHeading=false,nil,nil,nil
local function save() jsonWriteFile('/acng-tiremodel-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T004',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngT4",{})
function acngT4.sample(tag)
  local loaded=extensions.isExtensionLoaded('acng_tires')
  local snap=loaded and extensions.acng_tires.getSnapshot() or nil
  local grips={}
  for _,t in ipairs(snap and snap.tires or {}) do grips[t.name]=t.grip end
  local out={tag=tag,loaded=loaded,wheels={}}
  for _,wd in pairs(wheels.wheelRotators) do
    if wd.hasTire then
      local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
      out.wheels[#out.wheels+1]={name=wd.name,id=wd.wheelID,avg=obj:getWheelAvgTemperature(wd.wheelID),
        core=obj:getWheelCoreTemperature(wd.wheelID),pa=pg and obj:getGroupPressure(pg) or nil,grip=grips[wd.name]}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_tiremodel.receive(%q)',jsonEncode(out)))
end
]]
local function sample(veh,tag) command(veh,string.format('acngT4.sample(%q)',tag)) end
local function stats(s)
  local n,t,mx,core,psi,grip,gn=0,0,-1e30,0,0,0,0
  for _,w in ipairs(s and s.wheels or {}) do
    n=n+1;t=t+w.avg;mx=math.max(mx,w.avg);core=core+w.core;psi=psi+((w.pa or 101325)-101325)/6894.757
    if w.grip then grip=grip+w.grip;gn=gn+1 end
  end
  if n==0 then return nil end
  return {mean_c=t/n-273.15,max_c=mx-273.15,core_c=core/n-273.15,psi=psi/n,grip=gn>0 and grip/gn or nil}
end
local function receive(text)
  local s=jsonDecode(text) or {}
  s.t=simTime;s.stats=stats(s)
  s.part=s.tag and s.tag:match('^[^#]+') or part
  result.samples[#result.samples+1]=s
  save()
end
local function startDrive(veh,name)
  part=name;driving=true;lastHeading=nil
  win={index=1,t=0,yaw=0,v=0}
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',"..STEER..",2)")
end
-- Stop as the B002/P001 harnesses do: realistic gearbox, clutch in, foot brake. The arcade
-- gearbox reverses under brake at a standstill (T002/T004a), which drove the parked car.
local function stopDrive(veh)
  driving=false;win=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
-- Each 5 s window records the circle held and asks for a tire sample tagged part#index.
local function closeWindow(veh)
  local yaw=math.abs(win.yaw)/win.t
  local v=win.v/win.t
  result.windows[#result.windows+1]={part=part,index=win.index,end_s=win.index*WINDOW_S,speed_m_s=v,lateral_m_s2=v*yaw,radius_m=v/yaw}
  sample(veh,part..'#'..win.index)
  win={index=win.index+1,t=0,yaw=0,v=0}
end
local function windowOf(name,i)
  for _,w in ipairs(result.windows) do if w.part==name and w.index==i then return w end end
end
local function meanLateral(name,from,to)
  local t,n=0,0
  for i=from,to do local w=windowOf(name,i) if w then t=t+w.lateral_m_s2;n=n+1 end end
  return n>0 and t/n or nil
end
local function find(tag) for _,s in ipairs(result.samples) do if s.tag==tag then return s end end end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  if driving then
    controlTime=controlTime+dtReal
    if controlTime>0.1 then
      controlTime=0
      local speed=veh:getVelocity():length()
      command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(SPEED-speed)))))
    end
    local d=veh:getDirectionVector()
    local h=math.atan2(d.y,d.x)
    if lastHeading and dtSim>0 then
      local dh=h-lastHeading
      if dh>math.pi then dh=dh-2*math.pi elseif dh<-math.pi then dh=dh+2*math.pi end
      win.yaw=win.yaw+dh;win.t=win.t+dtSim;win.v=win.v+veh:getVelocity():length()*dtSim
    end
    lastHeading=h
    if win.t>=WINDOW_S then closeWindow(veh) end
  end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER)
    result.checks.default_master_off=not status().enabled
    result.checks.default_tires_off=status().features.tire_temperature==false and status().physics_writes==0
    sample(veh,'spawn')
    event('spawned');phase,stageTime=3,0
  elseif phase==3 and stageTime>1 then
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=4,0
  elseif phase==4 and stageTime>3 then
    startDrive(veh,'off');event('off_drive');phase,stageTime=5,0
  elseif phase==5 and stageTime>20.5 then
    stopDrive(veh)
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Tires Lab',type='freeroam',apps={
      {appName='acngTires',placement={left='24px',top='120px',width='330px',height='210px'}},
      {appName='acngRacingHud',placement={left='30%',bottom='30px',width='460px',height='190px'}}}})
    ui_appLayouts.setUsedLayout(id)
    guihooks.trigger('ChangeState',{state='play'})
    result.layout=id
    event('enabled');phase,stageTime=6,0
  elseif phase==6 and stageTime>3 then
    sample(veh,'enabled')
    result.checks.core_reports_tires_on=status().tires_vehicle_id==veh:getID() and status().physics_writes==1
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=7,0
  elseif phase==7 and stageTime>3 then
    startDrive(veh,'on');event('on_drive');phase,stageTime=8,0
  elseif phase==8 and stageTime>60 and not result.screenshot_at then
    result.screenshot_at=simTime;event('screenshot_window')
  elseif phase==8 and stageTime>150.5 then
    stopDrive(veh);part='park';event('park');phase,stageTime=9,0
    sample(veh,'park#0')
  elseif phase==9 then
    local n=math.floor(stageTime/5)
    if n>(result.park_n or 0) and n<=8 then result.park_n=n;sample(veh,'park#'..n) end
    if stageTime>41 then
      sample(veh,'flat#0')
      command(veh,"beamstate.deflateTire(0)")
      event('flat');phase,stageTime=10,0
    end
  elseif phase==10 and stageTime>8 then
    sample(veh,'flat#8')
    phase,stageTime=11,0
  elseif phase==11 and stageTime>1 then
    extensions.acng_core.setFeature('tire_temperature',false)
    event('disabled');phase,stageTime=12,0
  elseif phase==12 and stageTime>3 then
    sample(veh,'disabled')
    result.checks.core_reports_tires_off=status().tires_vehicle_id==nil and status().physics_writes==0
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=13,0
  elseif phase==13 and stageTime>3 then
    startDrive(veh,'off_again');event('off_again_drive');phase,stageTime=14,0
  elseif phase==14 and stageTime>20.5 then
    stopDrive(veh);phase,stageTime=15,0
  elseif phase==15 and stageTime>2 then
    local c,sum=result.checks,result.summary
    local function worstDev(name)
      local worst=0
      for _,s in ipairs(result.samples) do
        if s.part==name then for _,w in ipairs(s.wheels or {}) do worst=math.max(worst,math.abs(w.avg-AMBIENT_K)) end end
      end
      return worst
    end
    sum.off_lateral=meanLateral('off',3,4)
    sum.on_cold_lateral=meanLateral('on',3,4)
    sum.off_again_lateral=meanLateral('off_again',3,4)
    sum.off_worst_temp_dev_k=worstDev('off')
    sum.off_again_worst_temp_dev_k=worstDev('off_again')
    -- Warm-up: hottest sample, and the window where the feature gave the most grip.
    local first=find('on#1') and find('on#1').stats
    local hot,best,bestLat
    for i=1,30 do
      local s=find('on#'..i)
      local w=windowOf('on',i)
      if s and s.stats then
        if not hot or s.stats.max_c>hot.max_c then hot=s.stats end
        if w and i>=3 and s.stats.grip and (not best or s.stats.grip>best.grip) then best=s.stats;bestLat=w.lateral_m_s2 end
      end
    end
    sum.on_first=first;sum.on_hottest=hot;sum.on_best_grip=best;sum.on_best_grip_lateral=bestLat
    local p0,p8=find('park#0'),find('park#8')
    sum.park_start=p0 and p0.stats;sum.park_end=p8 and p8.stats
    local function psi0(s) for _,w in ipairs(s and s.wheels or {}) do if w.id==0 then return ((w.pa or 101325)-101325)/6894.757 end end end
    sum.flat_psi_before=psi0(find('flat#0'));sum.flat_psi_after=psi0(find('flat#8'))
    c.tires_not_loaded_while_off=find('spawn')~=nil and find('spawn').loaded==false
    c.off_temps_flat=sum.off_worst_temp_dev_k<0.5
    c.tires_loaded_after_enable=find('enabled')~=nil and find('enabled').loaded==true
    c.temps_rise_with_driving=(hot and first and hot.max_c>first.max_c+20) or false
    c.cold_tires_less_grip=(sum.on_cold_lateral and sum.off_lateral and sum.on_cold_lateral<sum.off_lateral*0.98) or false
    -- Grip follows temperature: across the settled warm-up windows the circle held tracks
    -- the mean grip the feature wrote (Pearson r), and the change is more than noise.
    local xs,ys,lo,hi={}, {}, math.huge, -math.huge
    for i=3,30 do
      local s,w=find('on#'..i),windowOf('on',i)
      if s and s.stats and s.stats.grip and w then
        xs[#xs+1]=s.stats.grip;ys[#ys+1]=w.lateral_m_s2
        lo,hi=math.min(lo,w.lateral_m_s2),math.max(hi,w.lateral_m_s2)
      end
    end
    local n,mx,my=#xs,0,0
    for i=1,n do mx=mx+xs[i]/n;my=my+ys[i]/n end
    local sxy,sxx,syy=0,0,0
    for i=1,n do sxy=sxy+(xs[i]-mx)*(ys[i]-my);sxx=sxx+(xs[i]-mx)^2;syy=syy+(ys[i]-my)^2 end
    sum.grip_lateral_r=(sxx>0 and syy>0) and sxy/math.sqrt(sxx*syy) or 0
    sum.on_lateral_span=hi-lo
    c.grip_follows_temperature=n>=10 and sum.grip_lateral_r>0.5 and hi-lo>0.015*hi
    c.pressure_rises_with_heat=(hot and first and hot.psi>first.psi+0.5) or false
    c.park_cools=(sum.park_start and sum.park_end and sum.park_end.mean_c<sum.park_start.mean_c-5) or false
    c.flat_still_deflates=(sum.flat_psi_before and sum.flat_psi_after and sum.flat_psi_after<sum.flat_psi_before-10) or false
    c.tires_unloaded_after_disable=find('disabled')~=nil and find('disabled').loaded==false
    c.off_again_temps_flat=sum.off_again_worst_temp_dev_k<0.5
    c.off_again_grip_matches_baseline=(sum.off_again_lateral and sum.off_lateral and math.abs(sum.off_again_lateral-sum.off_lateral)<sum.off_lateral*0.02) or false
    local pass=true
    for _,v in pairs(c) do pass=pass and v==true end
    result.passed=pass
    result.completed=true;event('complete');phase=16
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
