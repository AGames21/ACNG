-- P001 isolated performance-timer validation scene only; not distributed in the mod.
-- Drives a stock car with controller inputs and keeps an independent GE-side
-- reference (sim time, ground speed, distance) to compare with acng_perf.
local M={}
local elapsed,stageTime,phase=0,0,0
local result={test='P001 performance timer',model='etkc',config='kc6_360_M',completed=false,
  checks={},events={},snapshots={},reference={}}
local ref={time_s=0,distance_m=0,speed_m_s=nil,start_s=nil}
local START,MPH60,KMH100,MPH100,QM=0.15,60*0.44704,100/3.6,100*0.44704,402.336
local function save() jsonWriteFile('/acng-timer-test.json',result,true) end
local function event(name,veh)
  result.events[#result.events+1]={name=name,stage_sim_time_s=stageTime,
    speed_m_s=veh:getVelocity():length(),acng=extensions.acng_core.getStatus()}
  log('I','ACNG_P001',name);save()
end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function request(veh,label)
  command(veh,string.format("local s=extensions.isExtensionLoaded('acng_perf') and extensions.acng_perf.getSnapshot() or {unloaded=true}; obj:queueGameEngineLua(string.format('extensions.acng_timer.receive(%%q,%%q)',%q,jsonEncode(s)))",label))
end
local function receive(label,text)
  local snapshot=jsonDecode(text) or {}
  result.snapshots[label]=snapshot;save()
end
-- Independent reference: same interpolation idea, sampled at GE frames.
local function track(speed,dt)
  local prev,t0=ref.speed_m_s,ref.time_s
  ref.time_s,ref.speed_m_s=t0+dt,speed
  if not prev or dt<=0 then return end
  local function at(target) return t0+(target-prev)/(speed-prev)*dt end
  if not ref.start_s then
    if prev<START and speed>=START then ref.start_s=at(START);ref.distance_m=0 end
    return
  end
  local before=ref.distance_m
  ref.distance_m=before+(prev+speed)*0.5*dt
  for key,target in pairs({mph_0_60=MPH60,kmh_0_100=KMH100,mph_0_100=MPH100}) do
    if not result.reference[key] and prev<target and speed>=target then result.reference[key]={time_s=at(target)-ref.start_s} end
  end
  if not result.reference.quarter_mile and ref.distance_m>=QM then
    local f=(QM-before)/(ref.distance_m-before)
    result.reference.quarter_mile={time_s=t0+f*dt-ref.start_s,trap_speed_m_s=prev+(speed-prev)*f}
  end
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime=stageTime+dtSim
  local speed=veh:getVelocity():length()
  if phase>=4 and phase<=6 then track(speed,dtSim) end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    result.checks.default_master_off=not extensions.acng_core.getStatus().enabled
    result.checks.timer_absent_while_off=extensions.acng_core.getStatus().performance_timer_vehicle_id==nil
    extensions.acng_core.setEnabled(true)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Timer Lab',type='freeroam',apps={
      {appName='acngPerfTimer',placement={right='24px',top='120px',width='330px',height='205px'}},
      {appName='acngRacingHud',placement={left='30%',bottom='30px',width='460px',height='190px'}}}})
    ui_appLayouts.setUsedLayout(id)
    guihooks.trigger('ChangeState',{state='play'})
    result.layout=id
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('parkingbrake',0,1); input.event('throttle',0,1); input.event('brake',1,1); input.event('steering',0,1)")
    event('settle',veh);phase,stageTime=3,0
  elseif phase==3 and stageTime>5 then
    result.checks.timer_attached=extensions.acng_core.getStatus().performance_timer_vehicle_id==veh:getID()
    request(veh,'before_launch')
    command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('brake',0,1); input.event('throttle',1,1)")
    event('launch',veh);phase,stageTime=4,0
  elseif phase==4 and ((result.reference.quarter_mile and result.reference.mph_0_100) or stageTime>30) then
    request(veh,'end_of_launch')
    command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('brake',1,1)")
    event('brake',veh);phase,stageTime=5,0
  elseif phase==5 and speed<0.05 and stageTime>2 then
    event('stopped',veh);phase,stageTime=6,0
  elseif phase==5 and stageTime>40 then
    result.failure='did not stop in 40 simulation seconds';event('stop_timeout',veh);phase,stageTime=6,0
  elseif phase==6 and stageTime>3 then
    request(veh,'after_stop');phase,stageTime=7,0
  elseif phase==7 and stageTime>2 then
    -- Hold the finished scene for the screenshot, then prove master-off unloads the timer.
    result.checks.results_received=result.snapshots.after_stop~=nil;save()
    if stageTime>25 then
      -- The exact command the timer app's RESET button sends.
      command(veh,"if extensions.isExtensionLoaded('acng_perf') then extensions.acng_perf.clear() end")
      request(veh,'after_reset_button_command')
      phase,stageTime=8,0
    end
  elseif phase==8 and stageTime>2 then
    local reset=result.snapshots.after_reset_button_command or {}
    result.checks.reset_clears_results=reset.run_id==0 and next(reset.last or {})==nil
    extensions.acng_core.setEnabled(false)
    result.checks.timer_detached_after_off=extensions.acng_core.getStatus().performance_timer_vehicle_id==nil
    command(veh,"if extensions.isExtensionLoaded('acng_perf') then extensions.acng_perf.clear() end")
    request(veh,'after_master_off')
    phase,stageTime=9,0
  elseif phase==9 and stageTime>2 then
    result.checks.reset_does_not_reload_after_off=(result.snapshots.after_master_off or {}).unloaded==true
    result.completed=true;event('complete',veh);phase=10
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
