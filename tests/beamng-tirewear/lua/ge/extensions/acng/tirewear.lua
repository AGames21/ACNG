-- T005 isolated in-game validation of ACNG tire wear; not distributed in the mod. Drives
-- the stock etkc in the T004 half-lock circle at a held 10 m/s through the real ACNG
-- controls (acng_core.setEnabled / setFeature), measuring the circle held per 5 s window
-- (yaw rate -> lateral acceleration) while sampling each tire's temperature, pressure,
-- grip written, tread and slip work. Sequence:
--   off       OFF baseline
--   wear      tire_wear alone (heat stays stock, so temperatures stay at ambient); after
--             three windows the wear rate is raised so the busiest tire would lose about
--             60 % of its tread in the drive: grip must fall at an unchanged temperature
--   reset     a vehicle reset must give fresh tires
--   both      tire_temperature added on the loaded extension, wear rate back to 1
--   flat      a deflated tire must still go flat
--   off_again both features OFF, which must match the baseline
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local STEER,SPEED,WINDOW_S=0.5,10,5
local WEAR_S,BOTH_S=150,60
local TARGET_LOSS=0.6
local AMBIENT_K=288.15
local result={schema_version=1,test='T005 tire wear in-game validation',model='etkc',config='kc6_360_M',
  completed=false,checks={},windows={},samples={},events={},summary={}}
local driving,part,win,lastHeading=false,nil,nil,nil
local function save() jsonWriteFile('/acng-tirewear-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T005',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngT5",{})
function acngT5.sample(tag)
  local loaded=extensions.isExtensionLoaded('acng_tires')
  local m=loaded and extensions.acng_tires or nil
  local snap=m and m.getSnapshot() or nil
  local by={}
  for _,t in ipairs(snap and snap.tires or {}) do by[t.name]={grip=t.grip} end
  for _,t in ipairs(m and m.wearState() or {}) do
    by[t.name]=by[t.name] or {}
    by[t.name].tread=t.tread;by[t.name].slip_work=t.slip_work
  end
  local out={tag=tag,loaded=loaded,heat=snap and snap.heat,wear=snap and snap.wear,
    wear_rate=m and m.WEAR_RATE,wear_energy=m and m.WEAR_ENERGY,wheels={}}
  for _,wd in pairs(wheels.wheelRotators) do
    if wd.hasTire then
      local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
      local b=by[wd.name] or {}
      out.wheels[#out.wheels+1]={name=wd.name,id=wd.wheelID,avg=obj:getWheelAvgTemperature(wd.wheelID),
        core=obj:getWheelCoreTemperature(wd.wheelID),pa=pg and obj:getGroupPressure(pg) or nil,
        grip=b.grip,tread=b.tread,slip_work=b.slip_work}
    end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_tirewear.receive(%q)',jsonEncode(out)))
end
]]
local function sample(veh,tag) command(veh,string.format('acngT5.sample(%q)',tag)) end
local function stats(s)
  local n,t,mx,core,psi,grip,gn,tread,tn,minTread,work=0,0,-1e30,0,0,0,0,0,0,math.huge,0
  for _,w in ipairs(s and s.wheels or {}) do
    n=n+1;t=t+w.avg;mx=math.max(mx,w.avg);core=core+w.core;psi=psi+((w.pa or 101325)-101325)/6894.757
    if w.grip then grip=grip+w.grip;gn=gn+1 end
    if w.tread then tread=tread+w.tread;tn=tn+1;minTread=math.min(minTread,w.tread) end
    if w.slip_work then work=math.max(work,w.slip_work) end
  end
  if n==0 then return nil end
  return {mean_c=t/n-273.15,max_c=mx-273.15,core_c=core/n-273.15,psi=psi/n,grip=gn>0 and grip/gn or nil,
    tread=tn>0 and tread/tn or nil,min_tread=tn>0 and minTread or nil,max_slip_work=work}
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
-- Stop with the realistic gearbox, clutch in and foot brake; the arcade gearbox reverses
-- under brake at a standstill (T004a).
local function stopDrive(veh)
  driving=false;win=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
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
local function wheel(s,name) for _,w in ipairs(s and s.wheels or {}) do if w.name==name then return w end end end
-- The tire that did the most slip work in a sample.
local function busiest(s)
  local best
  for _,w in ipairs(s and s.wheels or {}) do if w.slip_work and (not best or w.slip_work>best.slip_work) then best=w end end
  return best
end
local function pearson(xs,ys)
  local n,mx,my=#xs,0,0
  if n<3 then return 0 end
  for i=1,n do mx=mx+xs[i]/n;my=my+ys[i]/n end
  local sxy,sxx,syy=0,0,0
  for i=1,n do sxy=sxy+(xs[i]-mx)*(ys[i]-my);sxx=sxx+(xs[i]-mx)^2;syy=syy+(ys[i]-my)^2 end
  return (sxx>0 and syy>0) and sxy/math.sqrt(sxx*syy) or 0
end
-- After window 3 of the wear drive, raise the rate from the slip power measured over
-- window 3 (window 2 still holds the launch, T005a) so the busiest tire would lose
-- TARGET_LOSS of its tread by the end.
local function tuneRate(veh)
  local a,b=find('wear#2'),find('wear#3')
  local wb=busiest(b)
  local wa=wb and wheel(a,wb.name)
  if not (wa and wb and wa.slip_work and b.wear_energy) then result.summary.rate_error='no slip work';return end
  local power=(wb.slip_work-wa.slip_work)/WINDOW_S
  local rate=power>0 and TARGET_LOSS*b.wear_energy/(power*(WEAR_S-3*WINDOW_S)) or 100
  rate=math.max(1,math.min(100,rate))
  result.summary.wear_tire=wb.name;result.summary.wear_power_w3=power;result.summary.wear_rate=rate
  command(veh,string.format("extensions.acng_tires.setWearRate(%.4f)",rate))
  event('rate_set')
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
    local st=status()
    result.checks.default_master_off=not st.enabled
    result.checks.default_wear_off=st.features.tire_wear==false and st.features.tire_temperature==false and st.physics_writes==0
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
    extensions.acng_core.setFeature('tire_wear',true)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Tire Wear Lab',type='freeroam',apps={
      {appName='acngTires',placement={left='24px',top='120px',width='330px',height='240px'}}}})
    ui_appLayouts.setUsedLayout(id)
    guihooks.trigger('ChangeState',{state='play'})
    result.layout=id
    event('wear_enabled');phase,stageTime=6,0
  elseif phase==6 and stageTime>3 then
    sample(veh,'wear_enabled')
    local st=status()
    result.checks.core_reports_wear_only=st.tires_vehicle_id==veh:getID() and st.physics_writes==1
      and st.features.tire_wear==true and st.features.tire_temperature==false
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=7,0
  elseif phase==7 and stageTime>3 then
    startDrive(veh,'wear');event('wear_drive');phase,stageTime=8,0
  elseif phase==8 then
    if not result.summary.wear_rate and not result.summary.rate_error and find('wear#3') then tuneRate(veh) end
    if stageTime>60 and not result.screenshot_at then result.screenshot_at=simTime;event('screenshot_window') end
    if stageTime>WEAR_S+0.5 then
      stopDrive(veh);event('wear_stop');phase,stageTime=9,0
    end
  elseif phase==9 and stageTime>3 then
    sample(veh,'worn')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    sample(veh,'reset')
    command(veh,"extensions.acng_tires.setWearRate(1)")
    extensions.acng_core.setFeature('tire_temperature',true)
    event('both_enabled');phase,stageTime=11,0
  elseif phase==11 and stageTime>2 then
    sample(veh,'both_enabled')
    local st=status()
    result.checks.core_reports_both=st.tires_vehicle_id==veh:getID() and st.physics_writes==1
      and st.features.tire_wear==true and st.features.tire_temperature==true
    startDrive(veh,'both');event('both_drive');phase,stageTime=12,0
  elseif phase==12 and stageTime>BOTH_S+0.5 then
    stopDrive(veh);event('both_stop');phase,stageTime=13,0
  elseif phase==13 and stageTime>3 then
    sample(veh,'flat#0')
    command(veh,"beamstate.deflateTire(0)")
    event('flat');phase,stageTime=14,0
  elseif phase==14 and stageTime>8 then
    sample(veh,'flat#8')
    phase,stageTime=15,0
  elseif phase==15 and stageTime>1 then
    extensions.acng_core.setFeature('tire_temperature',false)
    extensions.acng_core.setFeature('tire_wear',false)
    event('disabled');phase,stageTime=16,0
  elseif phase==16 and stageTime>3 then
    sample(veh,'disabled')
    local st=status()
    result.checks.core_reports_tires_off=st.tires_vehicle_id==nil and st.physics_writes==0
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=17,0
  elseif phase==17 and stageTime>3 then
    startDrive(veh,'off_again');event('off_again_drive');phase,stageTime=18,0
  elseif phase==18 and stageTime>20.5 then
    stopDrive(veh);phase,stageTime=19,0
  elseif phase==19 and stageTime>2 then
    local c,sum=result.checks,result.summary
    local function worstDev(name)
      local worst=0
      for _,s in ipairs(result.samples) do
        if s.part==name then for _,w in ipairs(s.wheels or {}) do worst=math.max(worst,math.abs(w.avg-AMBIENT_K)) end end
      end
      return worst
    end
    local nWear=math.floor(WEAR_S/WINDOW_S)
    sum.off_lateral=meanLateral('off',3,4)
    sum.off_again_lateral=meanLateral('off_again',3,4)
    sum.wear_early_lateral=meanLateral('wear',3,4)
    sum.wear_late_lateral=meanLateral('wear',nWear-1,nWear)
    sum.wear_worst_temp_dev_k=worstDev('wear')
    sum.off_worst_temp_dev_k=worstDev('off')
    sum.off_again_worst_temp_dev_k=worstDev('off_again')
    local first,last=find('wear#3'),find('wear#'..nWear)
    sum.wear_tread_start=first and first.stats and first.stats.tread
    sum.wear_tread_end=last and last.stats and last.stats.tread
    sum.wear_min_tread_end=last and last.stats and last.stats.min_tread
    sum.wear_grip_end=last and last.stats and last.stats.grip
    -- Calibration: each tire's slip power over the steady wear windows (3 to end).
    local w2=find('wear#2')
    sum.slip_power_w={}
    if w2 and last then
      for _,w in ipairs(last.wheels or {}) do
        local a=wheel(w2,w.name)
        if a and a.slip_work and w.slip_work then sum.slip_power_w[w.name]=(w.slip_work-a.slip_work)/((nWear-2)*WINDOW_S) end
      end
    end
    -- Grip falls with tread at an unchanged temperature: lateral tracks the mean grip
    -- written over windows 3 to the end, and the late circle is smaller than the early one.
    -- A fresh set after a reset may show a trace of slip work from the car settling.
    local xs,ys,monotonic,prev={}, {}, true, nil
    for i=3,nWear do
      local s,w=find('wear#'..i),windowOf('wear',i)
      if s and s.stats and s.stats.grip and w then xs[#xs+1]=s.stats.grip;ys[#ys+1]=w.lateral_m_s2 end
      if s and s.stats and s.stats.min_tread then
        if prev and s.stats.min_tread>prev+1e-9 then monotonic=false end
        prev=s.stats.min_tread
      end
    end
    sum.wear_grip_lateral_r=pearson(xs,ys)
    local ws,wd=find('worn'),find('reset')
    local bothEnd=find('both#'..math.floor(BOTH_S/WINDOW_S))
    sum.worn=ws and ws.stats;sum.reset=wd and wd.stats;sum.both_end=bothEnd and bothEnd.stats
    local bb=busiest(bothEnd)
    sum.both_busiest=bb and {name=bb.name,tread=bb.tread,slip_work=bb.slip_work,surface_c=bb.avg-273.15,grip=bb.grip}
    sum.both_rate=bothEnd and bothEnd.wear_rate
    local function psi0(s) for _,w in ipairs(s and s.wheels or {}) do if w.id==0 then return ((w.pa or 101325)-101325)/6894.757 end end end
    sum.flat_psi_before=psi0(find('flat#0'));sum.flat_psi_after=psi0(find('flat#8'))
    c.tires_not_loaded_while_off=find('spawn')~=nil and find('spawn').loaded==false
    c.off_temps_flat=sum.off_worst_temp_dev_k<0.5
    c.wear_loaded_heat_off=find('wear_enabled')~=nil and find('wear_enabled').loaded==true
      and find('wear_enabled').wear==true and find('wear_enabled').heat==false
    c.rate_raised=(sum.wear_rate or 0)>1
    c.tread_falls=(sum.wear_min_tread_end and sum.wear_min_tread_end<0.8 and monotonic) or false
    c.temperature_unchanged_during_wear=sum.wear_worst_temp_dev_k<0.5
    c.grip_falls_with_tread=(#xs>=10 and sum.wear_grip_lateral_r>0.5 and sum.wear_late_lateral
      and sum.wear_late_lateral<sum.wear_early_lateral*0.97) or false
    c.reset_gives_fresh_tires=(wd and wd.stats and ws and ws.stats and ws.stats.min_tread<0.5
      and wd.stats.min_tread>0.9999 and wd.stats.max_slip_work<100) or false
    c.both_loaded_without_reload=find('both_enabled')~=nil and find('both_enabled').loaded==true
      and find('both_enabled').heat==true and find('both_enabled').wear==true
    c.both_heat_and_wear=(sum.both_busiest and sum.both_busiest.tread<1 and sum.both_busiest.surface_c>40) or false
    c.flat_still_deflates=(sum.flat_psi_before and sum.flat_psi_after and sum.flat_psi_after<sum.flat_psi_before-10) or false
    c.tires_unloaded_after_disable=find('disabled')~=nil and find('disabled').loaded==false
    c.off_again_temps_flat=sum.off_again_worst_temp_dev_k<0.5
    c.off_again_grip_matches_baseline=(sum.off_again_lateral and sum.off_lateral and math.abs(sum.off_again_lateral-sum.off_lateral)<sum.off_lateral*0.02) or false
    local pass=true
    for _,v in pairs(c) do pass=pass and v==true end
    result.passed=pass
    result.completed=true;event('complete');phase=20
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
