-- LT isolated lap-timer validation scene only; not distributed in the mod.
-- Drives a stock car in steady circles with controller inputs and keeps an
-- independent GE-side reference (sim time, object position) to compare with acng_laps.
local M={}
local elapsed,stageTime,phase=0,0,0
local result={test='LT lap timer',model='etkc',config='kc6_360_M',completed=false,
  checks={},events={},snapshots={},reference={crossings={},laps={}}}
local line,lastPos,speedTarget,controlTime=nil,nil,12,0
local STEER,HALF_WIDTH,MIN_LAP=0.25,15,5
local function save() jsonWriteFile('/acng-laps-test.json',result,true) end
local function status() return extensions.acng_core.getStatus() end
local function event(name,veh)
  result.events[#result.events+1]={name=name,stage_sim_time_s=stageTime,
    speed_m_s=veh:getVelocity():length(),acng=status()}
  log('I','ACNG_LT',name);save()
end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function request(veh,label)
  command(veh,string.format("local s=extensions.isExtensionLoaded('acng_laps') and extensions.acng_laps.getSnapshot() or {unloaded=true}; obj:queueGameEngineLua(string.format('extensions.acng_lapgate.receive(%%q,%%q)',%q,jsonEncode(s)))",label))
end
local function receive(label,text)
  result.snapshots[label]=jsonDecode(text) or {};save()
end
-- The exact commands the lap app's buttons send.
local SET_LINE="if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.setLineHere() end"
local CLEAR="if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.clear() end"
-- Independent reference: forward gate crossings interpolated between GE frames.
local function track(veh,simTime,dt)
  local p=veh:getPosition()
  local prev=lastPos
  lastPos={x=p.x,y=p.y,t=simTime}
  if not (line and prev) then return end
  local s0=(prev.x-line.x)*line.nx+(prev.y-line.y)*line.ny
  local s1=(p.x-line.x)*line.nx+(p.y-line.y)*line.ny
  if not (s0<0 and s1>=0) then return end
  local f=s0/(s0-s1)
  local cx,cy=prev.x+(p.x-prev.x)*f-line.x,prev.y+(p.y-prev.y)*f-line.y
  if math.abs(cy*line.nx-cx*line.ny)>HALF_WIDTH then return end
  local t=prev.t+(simTime-prev.t)*f
  local c=result.reference.crossings
  if #c>0 and t-c[#c]<MIN_LAP then return end
  c[#c+1]=t
  if #c>1 then result.reference.laps[#c-1]=t-c[#c-1] end
  save()
end
local simTime=0
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  local speed=veh:getVelocity():length()
  if phase>=4 and phase<=8 then
    track(veh,simTime,dtSim)
    -- Simple speed hold; steering is constant, so the car laps a steady circle.
    controlTime=controlTime+dtReal
    if controlTime>0.1 then
      controlTime=0
      command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(speedTarget-speed)))))
    end
  end
  local laps=#result.reference.laps
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    result.checks.default_master_off=not status().enabled
    result.checks.timer_absent_while_off=status().lap_timer_vehicle_id==nil
    extensions.acng_core.setEnabled(true)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Laps Lab',type='freeroam',apps={
      {appName='acngLapTimer',placement={right='24px',top='120px',width='350px',height='190px'}},
      {appName='acngRacingHud',placement={left='30%',bottom='30px',width='460px',height='190px'}}}})
    ui_appLayouts.setUsedLayout(id)
    guihooks.trigger('ChangeState',{state='play'})
    result.layout=id
    command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('steering',"..STEER..",2)")
    event('start_circling',veh);phase,stageTime=3,0
  elseif phase==3 and stageTime>4 then
    result.checks.lap_timer_attached=status().lap_timer_vehicle_id==veh:getID()
    request(veh,'before_line')
    phase,stageTime=4,0
  elseif phase==4 and stageTime>20 then
    -- Steady circle reached: set the line where the car is now, as the SET LINE button does.
    command(veh,SET_LINE)
    local p,d=veh:getPosition(),veh:getDirectionVector()
    local len=math.sqrt(d.x*d.x+d.y*d.y)
    line={x=p.x,y=p.y,nx=d.x/len,ny=d.y/len}
    result.reference.line_speed_m_s=speed
    event('line_set',veh);phase,stageTime=5,0
  elseif phase==5 and laps>=3 then
    speedTarget=9
    event('slow_lap',veh);phase,stageTime=6,0
  elseif phase==6 and stageTime>1 and not result.snapshots.after_three_laps then
    -- Ask a second after the reference crossing so the vehicle has logged the same lap.
    request(veh,'after_three_laps')
  elseif phase==6 and result.reference.laps[1] and stageTime>result.reference.laps[1]*0.6 then
    request(veh,'slow_lap_mid')
    phase,stageTime=7,0
  elseif phase==7 and laps>=4 then
    speedTarget=12
    event('screenshot_window',veh);phase,stageTime=8,0
  elseif phase==8 and stageTime>1 and not result.snapshots.after_slow_lap then
    request(veh,'after_slow_lap')
  elseif phase==8 and stageTime>30 then
    request(veh,'before_reset')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    event('reset',veh);phase,stageTime=9,0
  elseif phase==9 and stageTime>2 then
    request(veh,'after_reset')
    command(veh,CLEAR)
    request(veh,'after_clear')
    phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    extensions.acng_core.setEnabled(false)
    result.checks.detached_after_off=status().lap_timer_vehicle_id==nil
    command(veh,CLEAR)
    request(veh,'after_master_off')
    phase,stageTime=11,0
  elseif phase==11 and stageTime>2 then
    local s=result.snapshots
    local three,slowMid,slow=s.after_three_laps or {},s.slow_lap_mid or {},s.after_slow_lap or {}
    local reset,cleared=s.after_reset or {},s.after_clear or {}
    result.checks.no_line_before_set=(s.before_line or {}).mode=='no_line'
    result.checks.three_laps_recorded=three.laps==3
    -- Every lap in the vehicle history (the last five, slow lap included) against the reference.
    local final,worst,compared=s.before_reset or {},0,0
    for _,lap in ipairs(final.history or {}) do
      local ref=result.reference.laps[lap.lap]
      worst=math.max(worst,ref and math.abs(lap.time_s-ref) or math.huge);compared=compared+1
    end
    result.reference.worst_lap_difference_s=worst
    result.reference.laps_compared=compared
    result.checks.lap_count_matches_reference=final.laps==#result.reference.laps
    result.checks.lap_times_match_reference=compared>=5 and worst<0.02
    result.checks.slow_lap_recorded=slow.laps==4 and slow.last and slow.last.lap==4
      and math.abs(slow.last.time_s-(result.reference.laps[4] or 0))<0.02
    local sec=(slow.last or {}).sectors or {}
    result.checks.sectors_sum_to_lap=#sec==3 and math.abs(sec[1]+sec[2]+sec[3]-slow.last.time_s)<1e-6
    result.checks.slow_lap_shows_positive_delta=(slowMid.delta_s or 0)>0.3
    result.checks.best_kept_after_slow_lap=slow.best and slow.last and slow.best.time_s<slow.last.time_s-1 and slow.best.lap~=4
    result.checks.reset_abandons_lap=reset.mode=='out_lap' and reset.note=='reset' and reset.laps==(s.before_reset or {}).laps
    result.checks.clear_keeps_line=cleared.mode=='out_lap' and cleared.laps==0
    result.checks.clear_does_not_reload_after_off=(s.after_master_off or {}).unloaded==true
    result.completed=true;event('complete',veh);phase=12
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
