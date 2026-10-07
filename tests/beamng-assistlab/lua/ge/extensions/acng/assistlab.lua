-- T006 isolated in-game validation of the ACNG assists (ABS and TC levels); not distributed
-- in the mod. Every level is picked through the real ACNG controls (acng_core.setEnabled /
-- setAssistLevel / setFeature). Straight-line runs on smallgrid:
--   brake   full throttle to just over 100 km/h, then full brake to a stop: stop distance
--           (scaled to 100 km/h) and the share of frames with a locked wheel
--   launch  full throttle from a standstill for LAUNCH_S: driven-wheel slip and TC action
-- etkc kc6_360_M (native ABS + CMU TC): brake factory / ABS off / ABS 2, launch factory /
-- TC off / TC 3. bolide 350 (no ABS, no TC): brake factory / ABS 2, launch factory / TC 3
-- (ACNG's own TC). After each car the features go OFF and every ABS / TC value must match
-- the stock values read at spawn exactly.
local M={}
local F='factory'
local LAUNCH_S,BRAKE_FROM,ACCEL_TIMEOUT_S=5,28.6,30
-- Wheels count as locked under 30 % of road speed, above the 5 m/s where native ABS stops.
local LOCK_RATIO,LOCK_MIN_SPEED=0.3,6
-- A launch frame counts as wheelspin above 15 % slip (TC level 3 cuts above 8 %).
local SPIN_SLIP=0.15
local CARS={
  {model='etkc',config='vehicles/etkc/kc6_360_M.pc',runs={
    {name='brake_factory',kind='brake',abs=F,tc=F},
    {name='brake_off',kind='brake',abs=0,tc=F},
    {name='brake_l2',kind='brake',abs=2,tc=F},
    {name='launch_factory',kind='launch',abs=F,tc=F},
    {name='launch_off',kind='launch',abs=F,tc=0},
    {name='launch_l3',kind='launch',abs=F,tc=3}}},
  {model='bolide',config='vehicles/bolide/350.pc',runs={
    {name='brake_factory',kind='brake',abs=F,tc=F},
    {name='brake_l2',kind='brake',abs=2,tc=F},
    {name='launch_factory',kind='launch',abs=F,tc=F},
    {name='launch_l3',kind='launch',abs=F,tc=3}}},
  {model='fullsize',config='vehicles/fullsize/stock.pc',runs={
    {name='launch_factory',kind='launch',abs=F,tc=F},
    {name='launch_l3',kind='launch',abs=F,tc=3}}}}
local result={schema_version=1,test='T006 assists in-game validation',completed=false,
  checks={},states={},runs={},events={},summary={}}
local elapsed,simTime,phase=0,0,0
local co,run
local states={}
local function save() jsonWriteFile('/acng-assistlab-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T006',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngAL",{})
local function first(t) local l=controller.getControllersByType(t) return l and l[1] end
local function th(c)
  local out={}
  local cfg=c and c.getConfig and c.getConfig()
  local g=cfg and cfg.tractionControl and cfg.tractionControl.wheelGroupSettings
  if type(g)=='table' then for k,v in pairs(g) do if type(v)=='table' then out[k]=v.slipThreshold end end end
  return out
end
function acngAL.state(tag)
  local loaded=extensions.isExtensionLoaded('acng_assists')
  local out={tag=tag,loaded=loaded,tf=electrics.values.throttleFactor,has_abs=electrics.values.hasABS,rot={},
    snap=loaded and extensions.acng_assists.getSnapshot() or nil}
  for i=0,(wheels.wheelRotatorCount or 0)-1 do
    local wd=wheels.wheelRotators[i]
    if wd then out.rot[#out.rot+1]={name=wd.name,tire=wd.hasTire,abs=wd.hasABS,slip=wd.slipRatioTarget,
      brake=wd.updateBrake==wd.updateBrakeABS and 'abs' or 'noabs'} end
  end
  local tc=first('drivingDynamics/supervisors/tractionControl')
  if tc then out.tc={enabled=tc.getConfig().isEnabled,motor=th(first('drivingDynamics/supervisors/components/motorTorqueControl')),
    brake=th(first('drivingDynamics/supervisors/components/brakeControl'))} end
  obj:queueGameEngineLua(string.format('extensions.acng_assistlab.receiveState(%q)',jsonEncode(out)))
end
function acngAL.tick()
  local ev=electrics.values
  local out={v=ev.airspeed or 0,abs=ev.absActive==true or ev.absActive==1,tcs=ev.tcsActive==true or ev.tcsActive==1,tf=ev.throttleFactor,w={}}
  for i=0,(wheels.wheelRotatorCount or 0)-1 do
    local wd=wheels.wheelRotators[i]
    if wd and wd.hasTire then out.w[#out.w+1]={av=wd.angularVelocity or 0,r=wd.radius or 0,p=wd.isPropulsed==true} end
  end
  obj:queueGameEngineLua(string.format('extensions.acng_assistlab.receiveTick(%q)',jsonEncode(out)))
end
]]

local function receiveState(text)
  local s=jsonDecode(text) or {}
  s.t=simTime
  states[s.tag]=s
  result.states[#result.states+1]=s
  save()
end
-- Per-frame data from the vehicle during a run.
local function receiveTick(text)
  if not run then return end
  local s=jsonDecode(text) or {}
  local v=math.abs(s.v or 0)
  run.ticks=run.ticks+1
  if s.abs then run.abs_frames=run.abs_frames+1 end
  if s.tcs then run.tcs_frames=run.tcs_frames+1 end
  if type(s.tf)=='number' then run.min_tf=math.min(run.min_tf or 1,s.tf) end
  if run.kind=='brake' and run.braking and v>LOCK_MIN_SPEED then
    local locked=false
    for _,w in ipairs(s.w or {}) do
      local ratio=math.abs(w.av)*w.r/v
      run.min_ratio=math.min(run.min_ratio or 1,ratio)
      if ratio<LOCK_RATIO then locked=true end
    end
    run.brake_frames=run.brake_frames+1
    if locked then run.lock_frames=run.lock_frames+1 end
  elseif run.kind=='launch' and run.launching then
    -- Same slip as acng_assists: driven wheels against the undriven ones (airspeed if all driven).
    local driven,free,nFree=nil,0,0
    for _,w in ipairs(s.w or {}) do
      local surface=math.abs(w.av)*w.r
      if w.p then driven=math.max(driven or 0,surface) else free,nFree=free+surface,nFree+1 end
    end
    local road=nFree>0 and free/nFree or v
    local slip=driven and math.max(0,(driven-road)/math.max(road,3)) or 0
    run.slip_sum=run.slip_sum+slip;run.slip_n=run.slip_n+1
    run.max_slip=math.max(run.max_slip,slip)
    if slip>SPIN_SLIP then run.spin_frames=run.spin_frames+1 end
    -- Every 4th frame of the launch, for diagnosing the TC: speed, slip, throttle factor.
    run.trace=run.trace or {}
    if run.slip_n%4==1 then run.trace[#run.trace+1]={math.floor(v*100+0.5)/100,math.floor(slip*1000+0.5)/1000,s.tf} end
  end
end

-- Coroutine helpers: the script below runs one step per frame.
local function wait(s) local t=0 while t<s do t=t+coroutine.yield() end end
local function waitFor(fn,timeout) local t=0 while not fn() and t<timeout do t=t+coroutine.yield() end return fn() end
local function veh() return be:getPlayerVehicle(0) end
local function speed() local v=veh() return v and v:getVelocity():length() or 0 end
local function state(tag)
  states[tag]=nil
  command(veh(),string.format('acngAL.state(%q)',tag))
  waitFor(function() return states[tag]~=nil end,5)
  return states[tag]
end
local function setAssist(key,lvl)
  if lvl==F then extensions.acng_core.setFeature(key,false)
  else
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setAssistLevel(key,lvl)
    extensions.acng_core.setFeature(key,true)
  end
end
local function resetCar()
  command(veh(),"input.event('throttle',0,1); input.event('brake',0,1); obj:requestReset(RESET_PHYSICS)")
  wait(3)
end
local function go()
  command(veh(),"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,2); input.event('throttle',1,1)")
end
-- Stop with the realistic gearbox, clutch in and foot brake; the arcade gearbox reverses
-- under brake at a standstill (T004a).
local function park()
  command(veh(),"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function newRun(car,spec)
  local p=veh():getPosition()
  return {car=car.model,name=spec.name,kind=spec.kind,abs=spec.abs,tc=spec.tc,ticks=0,abs_frames=0,tcs_frames=0,
    brake_frames=0,lock_frames=0,spin_frames=0,slip_sum=0,slip_n=0,max_slip=0,distance_m=0,start_pos={p.x,p.y,p.z}}
end
local function brakeRun(r)
  go()
  r.accel_ok=waitFor(function() return speed()>=BRAKE_FROM end,ACCEL_TIMEOUT_S)
  r.brake_from_m_s=speed()
  command(veh(),"input.event('throttle',0,1); input.event('brake',1,1)")
  r.braking=true
  local t=0
  while speed()>0.3 and t<15 do local dt=coroutine.yield();t=t+dt;r.distance_m=r.distance_m+speed()*dt end
  r.braking=false;r.stop_time_s=t
  park()
  r.distance_100_m=r.brake_from_m_s>0 and r.distance_m*(27.778/r.brake_from_m_s)^2 or nil
  r.lock_share=r.brake_frames>0 and r.lock_frames/r.brake_frames or nil
end
local function launchRun(r)
  go()
  r.launching=true
  local t=0
  while t<LAUNCH_S do local dt=coroutine.yield();t=t+dt;r.distance_m=r.distance_m+speed()*dt end
  r.launching=false
  r.end_speed_m_s=speed()
  park()
  r.mean_slip=r.slip_n>0 and r.slip_sum/r.slip_n or nil
  r.spin_share=r.slip_n>0 and r.spin_frames/r.slip_n or nil
end

local function script()
  while not (core_modmanager.isReady() and elapsed>12) do coroutine.yield() end
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  while worldReadyState~=2 or not veh() do coroutine.yield() end
  local layout=false
  for ci,car in ipairs(CARS) do
    core_vehicles.replaceVehicle(car.model,{config=car.config})
    waitFor(function() return veh() and veh():getJBeamFilename()==car.model end,30)
    wait(8)
    command(veh(),HELPER)
    wait(0.5)
    local stock=state(car.model..'_stock')
    if ci==1 then
      local st=status()
      result.checks.default_master_off=not st.enabled
      result.checks.default_assists_off=st.features.abs==false and st.features.tc==false and st.physics_writes==0
        and st.assists_vehicle_id==nil and stock~=nil and stock.loaded==false
    end
    event(car.model..'_spawned')
    for _,spec in ipairs(car.runs) do
      setAssist('abs',spec.abs);setAssist('tc',spec.tc)
      if not layout then
        extensions.load('ui_appLayouts')
        local id=ui_appLayouts.createLayout({title='ACNG Assists Lab',type='freeroam',apps={
          {appName='acngAssists',placement={left='24px',top='120px',width='330px',height='150px'}}}})
        ui_appLayouts.setUsedLayout(id)
        guihooks.trigger('ChangeState',{state='play'})
        result.layout=id;layout=true
      end
      wait(1.5)
      state(car.model..'_'..spec.name..'_cfg')
      resetCar()
      run=newRun(car,spec)
      result.runs[#result.runs+1]=run
      event(car.model..'_'..spec.name)
      if spec.kind=='brake' then brakeRun(run) else launchRun(run) end
      run.status=status()
      run=nil;save()
      wait(2)
    end
    extensions.acng_core.setFeature('abs',false)
    extensions.acng_core.setFeature('tc',false)
    extensions.acng_core.setEnabled(false)
    wait(2)
    state(car.model..'_restored')
    event(car.model..'_restored')
  end
  -- Click the real app buttons (T006 first set levels from Lua only and missed a button
  -- command that BeamNG's callback wrapper could not run). Each click must reach acng_core.
  result.buttons={}
  local clicks={
    {label='ABS 2',ok=function(st) return st.enabled and st.features.abs==true and st.assist_levels.abs==2 end},
    {label='TC 3',ok=function(st) return st.enabled and st.features.tc==true and st.assist_levels.tc==3 end},
    {label='TC OFF',ok=function(st) return st.features.tc==true and st.assist_levels.tc==0 end},
    {label='ABS FACTORY',ok=function(st) return st.features.abs==false end},
    {label='TC FACTORY',ok=function(st) return st.features.tc==false end}}
  for _,c in ipairs(clicks) do
    local selector='.acng-assists button[aria-label="'..c.label..'"]'
    be:queueJS('(function(){var e=document.querySelector('..jsonEncode(selector)..');if(e)e.click();})()')
    result.buttons[c.label]=waitFor(function() return c.ok(status()) end,5) and true or false
    wait(0.5)
  end
  extensions.acng_core.setEnabled(false)
  event('buttons_clicked')
end

local function near(a,b) return math.abs(a-b)<1e-6 end
local function deepEqual(a,b)
  if type(a)~=type(b) then return false end
  if type(a)=='number' then return near(a,b) end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not deepEqual(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function findRun(car,name) for _,r in ipairs(result.runs) do if r.car==car and r.name==name then return r end end end
-- ABS and TC values that must come back exactly: each rotator's ABS fields and brake
-- function, the CMU TC switch and thresholds, and no throttle factor electric.
local function restorable(s) return s and {rot=s.rot,tc=s.tc,tf=s.tf,has_abs=s.has_abs} end
local function same(a,b) return a~=nil and b~=nil and deepEqual(restorable(a),restorable(b)) end
local function allRot(s,fn)
  local any=false
  for i,r in ipairs(s and s.rot or {}) do any=true;if not fn(r,i) then return false end end
  return any
end
local function allValues(t,fn)
  local any=false
  for _,v in pairs(t or {}) do any=true;if not fn(v) then return false end end
  return any
end

local function evaluate()
  local c,sum=result.checks,result.summary
  local clicked=0
  for _,v in pairs(result.buttons or {}) do if v then clicked=clicked+1 end end
  c.app_buttons_work=clicked==5
  local S=function(tag) return states[tag] end
  for _,r in ipairs(result.runs) do
    sum[r.car..'_'..r.name]={distance_100_m=r.distance_100_m,lock_share=r.lock_share,abs_frames=r.abs_frames,
      mean_slip=r.mean_slip,spin_share=r.spin_share,max_slip=r.max_slip,tcs_frames=r.tcs_frames,min_tf=r.min_tf,end_speed_m_s=r.end_speed_m_s}
  end
  -- etkc: native ABS and CMU TC.
  local es=S('etkc_stock')
  c.etkc_abs_factory_untouched=same(S('etkc_brake_factory_cfg'),es)
  c.etkc_abs_off_applied=allRot(S('etkc_brake_off_cfg'),function(r) return r.abs~=true and r.brake=='noabs' end)
  c.etkc_abs_l2_applied=allRot(S('etkc_brake_l2_cfg'),function(r,i)
    if r.tire==false then return r.abs==es.rot[i].abs end
    return r.abs==true and near(r.slip,0.18) and r.brake=='abs'
  end)
  c.etkc_tc_mode_cmu=(S('etkc_launch_l3_cfg') and S('etkc_launch_l3_cfg').snap and S('etkc_launch_l3_cfg').snap.tc_mode=='cmu') or false
  local l3=S('etkc_launch_l3_cfg')
  c.etkc_tc_l3_applied=(l3 and l3.tc and l3.tc.enabled==true and allValues(l3.tc.motor,function(v) return near(v,0.08) end)
    and allValues(l3.tc.brake,function(v) return near(v,0.064) end)) or false
  c.etkc_tc_off_applied=(S('etkc_launch_off_cfg') and S('etkc_launch_off_cfg').tc and S('etkc_launch_off_cfg').tc.enabled==false) or false
  local bf,bo,b2=findRun('etkc','brake_factory'),findRun('etkc','brake_off'),findRun('etkc','brake_l2')
  c.etkc_brake_runs_reached_100=(bf and bf.accel_ok and bo and bo.accel_ok and b2 and b2.accel_ok) or false
  c.etkc_abs_off_locks=(bo and bo.lock_share and bo.lock_share>0.5 and bo.abs_frames==0) or false
  c.etkc_abs_on_no_lock=(bf and b2 and bf.lock_share and b2.lock_share and bf.lock_share<0.15 and b2.lock_share<0.15
    and bf.abs_frames>0 and b2.abs_frames>0) or false
  c.etkc_abs_stops_shorter=(bo and b2 and bo.distance_100_m and b2.distance_100_m and b2.distance_100_m<bo.distance_100_m) or false
  local lf,lo,lt=findRun('etkc','launch_factory'),findRun('etkc','launch_off'),findRun('etkc','launch_l3')
  c.etkc_tc_off_spins=(lo and lo.max_slip>0.3 and lo.tcs_frames==0) or false
  c.etkc_tc_l3_cuts=(lo and lt and lt.mean_slip and lo.mean_slip and lt.mean_slip<lo.mean_slip*0.7 and lt.tcs_frames>0) or false
  c.etkc_restored_exact=same(S('etkc_restored'),es) and S('etkc_restored').loaded==false
    and S('etkc_restored').tf==nil
  -- bolide: no ABS and no TC, so ABS is added and ACNG's own TC runs.
  local bs=S('bolide_stock')
  c.bolide_has_no_abs_or_tc=(bs and bs.tc==nil and allRot(bs,function(r) return r.abs~=true end)) or false
  c.bolide_tc_mode_acng=(S('bolide_launch_l3_cfg') and S('bolide_launch_l3_cfg').snap and S('bolide_launch_l3_cfg').snap.tc_mode=='acng') or false
  local abf,ab2=findRun('bolide','brake_factory'),findRun('bolide','brake_l2')
  c.bolide_abs_added=(S('bolide_brake_l2_cfg') and allRot(S('bolide_brake_l2_cfg'),function(r) return r.tire==false or (r.abs==true and r.brake=='abs') end)
    and ab2 and ab2.abs_frames>0 and abf and ab2.lock_share and abf.lock_share and ab2.lock_share<abf.lock_share) or false
  -- Own TC: the factory launch spins with no throttle factor. Level 3 cuts the throttle
  -- factor, lowers the peak slip, at least halves the mean slip, keeps wheelspin frames to
  -- half of factory or under 5 %, and costs no more than 5 % of the speed at 5 s (a car
  -- that barely spins should barely be touched). Until T006e the peak had to halve too; the
  -- bolide's peak (2.6 against 4.0) comes in the first frames off the line, under 0.3 m/s,
  -- with the throttle already at the 20 % floor.
  local function ownTC(car)
    local f,l=findRun(car,'launch_factory'),findRun(car,'launch_l3')
    return (f and f.max_slip>0.3 and f.min_tf==nil) or false,
      (f and l and l.min_tf and l.min_tf<0.9 and l.max_slip<f.max_slip
        and l.mean_slip<=f.mean_slip*0.5
        and l.spin_share<=math.max(f.spin_share*0.5,0.05) and l.end_speed_m_s>=f.end_speed_m_s*0.95) or false
  end
  c.bolide_factory_spins_untouched,c.bolide_own_tc_cuts=ownTC('bolide')
  c.fullsize_factory_spins_untouched,c.fullsize_own_tc_cuts=ownTC('fullsize')
  local fs=S('fullsize_stock')
  c.fullsize_tc_mode_acng=(S('fullsize_launch_l3_cfg') and S('fullsize_launch_l3_cfg').snap and S('fullsize_launch_l3_cfg').snap.tc_mode=='acng') or false
  c.fullsize_restored_exact=same(S('fullsize_restored'),fs) and S('fullsize_restored').loaded==false
    and S('fullsize_restored').tf==nil
  c.bolide_restored_exact=same(S('bolide_restored'),bs) and S('bolide_restored').loaded==false
    and S('bolide_restored').tf==nil
  local pass=true
  for _,v in pairs(c) do pass=pass and v==true end
  result.passed=pass
end

local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  simTime=simTime+dtSim
  if phase~=0 then return end
  if not co then co=coroutine.create(script) end
  local v=veh()
  if run and v then command(v,'acngAL.tick()') end
  local ok,err=coroutine.resume(co,dtSim)
  if not ok then result.error=tostring(err);phase=1;event('error');return end
  if coroutine.status(co)=='dead' then
    local ok2,err2=pcall(evaluate)
    if not ok2 then result.error=tostring(err2) end
    result.completed=true;phase=1;event('complete')
  end
end
M.onUpdate=onUpdate
M.receiveState=receiveState
M.receiveTick=receiveTick
return M
