-- FFB001 isolated in-game validation of the ACNG force feedback; not distributed in the
-- mod. No physical wheel is needed: BeamNG's own hydros.enableVirtualWheel is switched on
-- with a fixed steering angle and a capture function, so every force hydros would send to
-- a wheel is recorded in the vehicle VM. The ETK holds a steady circle on smallgrid at a
-- set speed while settings are changed through acng_core (the same calls the app makes):
--   gain 1.5        force about 1.5x the FFB OFF force, strength = stock x 1.5 exactly
--   min force 0.15  a weak force near the centre grows
--   filter 0.8      BeamNG smoothing 240; STOCK puts the player's value back
--   slip 1          the force buzzes more while the front tires slide
--   Options change  the player's new strength becomes ACNG's stock while ACNG runs
--   OFF             strength, low-speed strength, FFB config and the hook are back exactly
-- Then real app buttons are clicked. Kerb and road feel have offline checks only.
local M={}
local CAR={model='etkc',config='vehicles/etkc/kc6_360_M.pc'}
local SETTLE_S,MEASURE_S=3,3
local A_MID,A_SMALL,A_SLIP=0.05,0.01,0.35
local V_MID,V_SLIP=15,20
local result={schema_version=1,test='FFB001 force feedback in-game validation',completed=false,
  checks={},states={},windows={},events={},summary={}}
local elapsed,simTime,phase=0,0,0
local co
local states={}
local target=nil
local function save() jsonWriteFile('/acng-ffblab-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_FFB001',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
-- Vehicle VM helper: the virtual wheel plus force statistics.
local HELPER=[[
rawset(_G,"acngFL",{angle=0,n=0,sum=0,sq=0,min=1e9,max=-1e9,dn=0,dsq=0,last=nil})
function acngFL.reset() acngFL.n,acngFL.sum,acngFL.sq,acngFL.min,acngFL.max,acngFL.dn,acngFL.dsq,acngFL.last=0,0,0,1e9,-1e9,0,0,nil end
hydros.enableVirtualWheel(true,function() return acngFL.angle end,function(o,id,t)
  acngFL.n=acngFL.n+1; acngFL.sum=acngFL.sum+t; acngFL.sq=acngFL.sq+t*t
  if t<acngFL.min then acngFL.min=t end
  if t>acngFL.max then acngFL.max=t end
  if acngFL.last then local d=t-acngFL.last; acngFL.dn=acngFL.dn+1; acngFL.dsq=acngFL.dsq+d*d end
  acngFL.last=t
end)
function acngFL.state(tag)
  local loaded=extensions.isExtensionLoaded('acng_ffb')
  local n=math.max(acngFL.n,1)
  local mean=acngFL.sum/n
  local slip=0
  for i=0,tableSizeC(wheels.wheels)-1 do
    local wd=wheels.wheels[i]
    if wd and type(wd.name)=='string' and wd.name:sub(1,1)=='F' and type(wd.lastSlip)=='number' then slip=math.max(slip,math.abs(wd.lastSlip)) end
  end
  local out={tag=tag,loaded=loaded,coef=hydros.wheelFFBForceCoef,low=hydros.wheelFFBForceCoefLowSpeed,
    cur=hydros.wheelFFBForceCoefCurrent,cfg=hydros.getFFBConfig(),hook_nil=hydros.testHook==nil,
    ffb_id=hydros.getFFBID(),limit=hydros.curForceLimit,speed=electrics.values.airspeed,front_slip=slip,
    stats={n=acngFL.n,mean=mean,std=math.sqrt(math.max(0,acngFL.sq/n-mean*mean)),min=acngFL.min,max=acngFL.max,
      jitter=acngFL.dn>0 and math.sqrt(acngFL.dsq/acngFL.dn) or 0},
    lab=loaded and extensions.acng_ffb.labState() or nil,snap=loaded and extensions.acng_ffb.getSnapshot() or nil}
  if out.lab then out.lab.stock=out.lab.stock and {coef=out.lab.stock.coef,low=out.lab.stock.low} end
  obj:queueGameEngineLua(string.format('extensions.acng_ffblab.receiveState(%q)',jsonEncode(out)))
end
]]

local function receiveState(text)
  local s=jsonDecode(text) or {}
  s.t=simTime
  states[s.tag]=s
  result.states[#result.states+1]=s
  save()
end

local function wait(s) local t=0 while t<s do t=t+coroutine.yield() end end
local function waitFor(fn,timeout) local t=0 while not fn() and t<timeout do t=t+coroutine.yield() end return fn() end
local function veh() return be:getPlayerVehicle(0) end
local function speed() local v=veh() return v and v:getVelocity():length() or 0 end
local function state(tag)
  states[tag]=nil
  command(veh(),string.format('acngFL.state(%q)',tag))
  waitFor(function() return states[tag]~=nil end,5)
  return states[tag]
end
local function setAngle(a) command(veh(),string.format('acngFL.angle=%.6g',a)) end
-- Hold a steering angle and speed, settle, then record MEASURE_S of force.
local function window(name,angle,speedTarget)
  setAngle(angle)
  target=speedTarget
  wait(SETTLE_S)
  command(veh(),'acngFL.reset()')
  wait(MEASURE_S)
  local s=state(name)
  result.windows[name]=s and {angle=angle,speed=s.speed,mean=s.stats.mean,std=s.stats.std,jitter=s.stats.jitter,
    n=s.stats.n,front_slip=s.front_slip,coef=s.coef,cur=s.cur,extra=s.lab and s.lab.extra or nil,
    slipA=s.lab and s.lab.eff and s.lab.eff.slipA or nil} or nil
  event(name)
  return s
end
local function ffb(name,value) return extensions.acng_core.setFFBSetting(name,value) end

local function script()
  while not (core_modmanager.isReady() and elapsed>12) do coroutine.yield() end
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  while worldReadyState~=2 or not veh() do coroutine.yield() end
  core_vehicles.replaceVehicle(CAR.model,{config=CAR.config})
  waitFor(function() return veh() and veh():getJBeamFilename()==CAR.model end,30)
  wait(8)
  command(veh(),HELPER)
  wait(1)
  local st=status()
  result.checks.default_master_off=not st.enabled
  result.checks.default_ffb_off=st.features.ffb==false and st.ffb_vehicle_id==nil and st.physics_writes==0
  local stock=state('stock')
  result.checks.default_ffb_off=result.checks.default_ffb_off and stock~=nil and stock.loaded==false
  event('spawned')
  command(veh(),"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1)")
  target=V_MID
  wait(6)
  window('off_mid',A_MID,V_MID)
  window('off_small',A_SMALL,V_MID)
  -- Turn on with the effects at zero, so the gain test sees only the gain.
  ffb('kerb',0);ffb('road',0);ffb('slip',0);ffb('min_force',0);ffb('gain',1)
  extensions.acng_core.setEnabled(true)
  extensions.acng_core.setFeature('ffb',true)
  wait(1.5)
  window('on_g1_mid',A_MID,V_MID)
  ffb('gain',1.5)
  wait(1)
  window('on_g15_mid',A_MID,V_MID)
  ffb('gain',1)
  wait(1)
  window('on_g1_small',A_SMALL,V_MID)
  ffb('min_force',0.15)
  wait(1)
  window('on_min_small',A_SMALL,V_MID)
  ffb('min_force',0)
  ffb('filter',0.8)
  wait(1)
  state('filter_08')
  ffb('filter',false)
  wait(1)
  state('filter_stock')
  window('on_slip0',A_SLIP,V_SLIP)
  ffb('slip',1)
  wait(1)
  window('on_slip1',A_SLIP,V_SLIP)
  ffb('slip',0)
  -- The player changes the strength in Options while ACNG runs at gain 1.5.
  ffb('gain',1.5)
  wait(1)
  state('drift_before')
  command(veh(),'hydros.wheelFFBForceCoef=150; hydros.wheelFFBForceCoefLowSpeed=15')
  wait(1)
  state('drift_after')
  extensions.acng_core.setFeature('ffb',false)
  wait(1.5)
  state('drift_off')
  -- Put the original strength back the way Options would, then check OFF again later.
  command(veh(),string.format('hydros.wheelFFBForceCoef=%.17g; hydros.wheelFFBForceCoefLowSpeed=%.17g',stock.coef,stock.low))
  wait(0.5)
  ffb('gain',1);ffb('kerb',0.3);ffb('road',0.5);ffb('slip',0.3)
  extensions.acng_core.setFeature('ffb',true)
  wait(1.5)
  state('defaults_on')
  extensions.acng_core.setEnabled(false)
  wait(1.5)
  state('restored')
  window('restored_mid',A_MID,V_MID)
  -- Real app buttons.
  target=nil
  command(veh(),"input.event('throttle',0,1); input.event('brake',1,1)")
  extensions.load('ui_appLayouts')
  local id=ui_appLayouts.createLayout({title='ACNG FFB Lab',type='freeroam',apps={
    {appName='acngFfb',placement={left='24px',top='120px',width='330px',height='260px'}}}})
  ui_appLayouts.setUsedLayout(id)
  guihooks.trigger('ChangeState',{state='play'})
  result.layout=id
  wait(3)
  result.buttons={}
  local clicks={
    {label='FFB ON',ok=function(s) return s.enabled and s.features.ffb==true end},
    {label='GAIN up',ok=function(s) return math.abs(s.ffb_settings.gain-1.05)<1e-9 end},
    {label='FILTER up',ok=function(s) return s.ffb_settings.filter==0.5 end},
    {label='FILTER stock',ok=function(s) return s.ffb_settings.filter==nil end},
    {label='GAIN down',ok=function(s) return math.abs(s.ffb_settings.gain-1)<1e-9 end},
    {label='FFB OFF',ok=function(s) return s.features.ffb==false end}}
  for _,c in ipairs(clicks) do
    local selector='.acng-ffb button[aria-label="'..c.label..'"]'
    be:queueJS('(function(){var e=document.querySelector('..jsonEncode(selector)..');if(e)e.click();})()')
    result.buttons[c.label]=waitFor(function() return c.ok(status()) end,5) and true or false
    wait(0.7)
  end
  extensions.acng_core.setEnabled(false)
  wait(1.5)
  state('final')
  event('buttons_clicked')
end

-- a==b first: hydros' wheelFFBDampLimit defaults to math.huge, and inf-inf is NaN.
local function near(a,b,tol) return type(a)=='number' and type(b)=='number' and (a==b or math.abs(a-b)<=(tol or 1e-9)) end
local function sameCfg(a,b)
  if type(a)~='table' or type(b)~='table' then return false end
  for k,v in pairs(a) do
    if type(v)=='number' then if not near(v,b[k],1e-9) then return false end
    elseif v~=b[k] then return false end
  end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function exact(s,stock)
  return s~=nil and stock~=nil and s.loaded==false and s.hook_nil==true and near(s.coef,stock.coef) and near(s.low,stock.low)
    and sameCfg(s.cfg,stock.cfg)
end

local function evaluate()
  local c,sum,W=result.checks,result.summary,result.windows
  local S=function(tag) return states[tag] end
  local stock=S('stock')
  local clicked=0
  for _,v in pairs(result.buttons or {}) do if v then clicked=clicked+1 end end
  c.app_buttons_work=clicked==6
  c.virtual_wheel_records=(W.off_mid and W.off_mid.n>100 and stock and stock.ffb_id==0) or false
  c.speed_held=(W.off_mid and W.restored_mid and near(W.off_mid.speed,V_MID,1.5) and near(W.restored_mid.speed,V_MID,1.5)) or false
  -- Gain: strength is stock x 1.5 exactly; the force follows within 15 %.
  local g15=S('on_g15_mid')
  c.gain_scales_strength=(g15 and stock and near(g15.coef,stock.coef*1.5) and near(g15.low,stock.low*1.5)) or false
  local f0,f1,f15=W.off_mid and W.off_mid.mean,W.on_g1_mid and W.on_g1_mid.mean,W.on_g15_mid and W.on_g15_mid.mean
  sum.force_ratio_g15=(f0 and f15 and math.abs(f0)>1e-6) and f15/f0 or nil
  sum.force_ratio_g1=(f0 and f1 and math.abs(f0)>1e-6) and f1/f0 or nil
  c.gain1_matches_off=(sum.force_ratio_g1 and near(sum.force_ratio_g1,1,0.05)) or false
  c.gain15_force_ratio=(sum.force_ratio_g15 and near(sum.force_ratio_g15,1.5,0.225)) or false
  -- Minimum force: same sign and clearly stronger at the small angle.
  local fs,fm=W.on_g1_small and W.on_g1_small.mean,W.on_min_small and W.on_min_small.mean
  sum.min_force_delta=(fs and fm) and math.abs(fm)-math.abs(fs) or nil
  c.min_force_lifts_small_force=(fs and fm and fs*fm>0 and (math.abs(fm)>math.abs(fs)*1.5 or sum.min_force_delta>0.3)) or false
  c.min_force_hook_installed=(S('on_min_small') and S('on_min_small').lab and S('on_min_small').lab.test_hook_is_ours==true) or false
  c.no_hook_without_effects=(S('on_g15_mid') and S('on_g15_mid').hook_nil==true) or false
  -- Filter.
  local f8,fstock=S('filter_08'),S('filter_stock')
  c.filter_sets_smoothing=(f8 and near(f8.cfg.smoothing,240,1e-6)) or false
  c.filter_stock_restores=(fstock and stock and near(fstock.cfg.smoothing,stock.cfg.smoothing,1e-9)) or false
  -- Slip buzz: the front tires slide in both windows; the force varies more with slip 1.
  local s0,s1=W.on_slip0,W.on_slip1
  sum.slip_jitter_ratio=(s0 and s1 and s0.jitter>0) and s1.jitter/s0.jitter or nil
  sum.slip_std_ratio=(s0 and s1 and s0.std>0) and s1.std/s0.std or nil
  c.front_tires_slide=(s0 and s1 and s0.front_slip>1.5 and s1.front_slip>1.5) or false
  c.slip_buzz_adds_vibration=(s1 and s1.slipA and s1.slipA>0.05 and sum.slip_jitter_ratio and sum.slip_jitter_ratio>1.3) or false
  -- Options change while ON becomes the new stock.
  local da,doff=S('drift_after'),S('drift_off')
  c.options_change_followed=(da and near(da.coef,225,1e-6) and near(da.low,22.5,1e-6)) or false
  c.options_change_kept_on_off=(doff and doff.loaded==false and near(doff.coef,150,1e-9) and near(doff.low,15,1e-9)) or false
  -- Defaults hook up and OFF restores exactly.
  local don=S('defaults_on')
  c.defaults_install_hook=(don and don.loaded==true and don.lab and don.lab.test_hook_is_ours==true and near(don.coef,stock.coef)) or false
  c.off_restores_exact=exact(S('restored'),stock)
  c.off_force_matches_baseline=(f0 and W.restored_mid and near(W.restored_mid.mean,f0,math.abs(f0)*0.05+0.01)) or false
  c.final_restores_exact=exact(S('final'),stock)
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
  if target and v then
    local err=target-speed()
    local thr=math.max(0,math.min(1,0.25+err*0.3))
    local brk=err<-2 and math.min(1,-err*0.2) or 0
    command(v,string.format("input.event('throttle',%.3f,1); input.event('brake',%.3f,1)",thr,brk))
  end
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
return M
