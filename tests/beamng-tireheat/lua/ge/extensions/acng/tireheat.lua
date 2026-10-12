-- T009d isolated in-game tire heat run for film and HUD checks; not distributed in the mod.
-- Stock etkc kc6_360_M on smallgrid, driven through the real ACNG controls (sport profile).
--   armed     heat ON: every tire starts cold
--   circle    55 s half-lock circle at 10 m/s: the outer front heats through the window
--   straight  20 s at 18 m/s holding the heading: the hot tire cools
--   disabled  tire_temperature OFF unloads the tire model
-- 1 s samples carry the HUD snapshot (surface, zones, state) and the grip factors per tire.
-- It also writes /acng-film-cues.json (drive_start, circle_end, drive_end, complete) so
-- tools/film_lab.py can cut clips of the circle and the cool-down.
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local SAMPLE_S=1
local CIRCLE_S,CIRCLE_SPEED,CIRCLE_STEER=55,10,0.5
local STRAIGHT_S,STRAIGHT_SPEED=20,18
local result={schema_version=1,test='T009d tire heat in-game run',model='etkc',config='kc6_360_M',level='smallgrid',
  circle_s=CIRCLE_S,circle_speed_m_s=CIRCLE_SPEED,circle_steer=CIRCLE_STEER,straight_s=STRAIGHT_S,
  straight_speed_m_s=STRAIGHT_SPEED,completed=false,checks={},samples={},events={},errors={},summary={}}
local cues={schema_version=1,cues={}}
local drive=nil
local function save() jsonWriteFile('/acng-tireheat-test.json',result,true) end
local function cue(name) cues.cues[#cues.cues+1]={name=name,seq=#cues.cues+1,sim_time_s=simTime};jsonWriteFile('/acng-film-cues.json',cues,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T009D',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngTHi",{})
local function send(kind,data) obj:queueGameEngineLua(string.format('extensions.acng_tireheat.receive(%q,%q)',kind,jsonEncode(data))) end
function acngTHi.sample(tag)
  local ok,err=pcall(function()
    local loaded=extensions.isExtensionLoaded('acng_tires')
    local m=loaded and extensions.acng_tires or nil
    local snap=m and m.getSnapshot() or nil
    local model={}
    for _,t in ipairs(m and m.modelState() or {}) do model[t.name]=t end
    local out={tag=tag,loaded=loaded,heat=snap and snap.heat,profile=snap and snap.profile,min_grip=m and m.MIN_GRIP,wheels={}}
    for _,t in ipairs(snap and snap.tires or {}) do
      local ms=model[t.name] or {}
      out.wheels[#out.wheels+1]={name=t.name,surface_c=t.surface_c,core_c=t.core_c,zones_c=t.zones_c,state=t.state,
        low_c=t.window_low_c,high_c=t.window_high_c,psi=t.psi,heat_grip=ms.heat_grip,pressure_grip=ms.pressure_grip,
        damage_grip=ms.damage_grip,grip=ms.grip}
    end
    send('sample',out)
  end)
  if not ok then send('error',{tag=tag,error=tostring(err)}) end
end
]]
local function sample(veh,tag) command(veh,string.format('acngTHi.sample(%q)',tag)) end
local function receive(kind,text)
  local d=jsonDecode(text) or {}
  if kind=='error' then result.errors[#result.errors+1]=d
  else
    d.t=simTime;d.part=d.tag and d.tag:match('^[^#]+')
    result.samples[#result.samples+1]=d
  end
  save()
end
-- Hold a speed with throttle. The circle holds a fixed steer; the straight holds the
-- heading it starts with (steering right is positive).
local function startDrive(veh,part,speed,steer)
  drive={part=part,speed=speed,steer=steer,t=0,n=0}
  if not steer then local d=veh:getDirectionVector();drive.dir={x=d.x,y=d.y} end
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',"..(steer or 0)..",2)")
end
local function stopDrive(veh)
  drive=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function driveStep(veh,dtReal,dtSim)
  drive.t=drive.t+dtSim
  controlTime=controlTime+dtReal
  if controlTime>0.1 then
    controlTime=0
    local speed=veh:getVelocity():length()
    local steer=drive.steer
    if not steer then
      local d=veh:getDirectionVector()
      steer=math.max(-0.3,math.min(0.3,-1.2*(d.x*drive.dir.y-d.y*drive.dir.x)))
    end
    command(veh,string.format("input.event('throttle',%.3f,1); input.event('steering',%.3f,2)",math.max(0,math.min(1,0.25*(drive.speed-speed))),steer))
  end
  local n=math.floor(drive.t/SAMPLE_S)
  if n>drive.n then drive.n=n;sample(veh,drive.part..'#'..n) end
end
local function find(tag) for _,s in ipairs(result.samples) do if s.tag==tag then return s end end end
local function partSamples(name)
  local out={}
  for _,s in ipairs(result.samples) do if s.part==name then out[#out+1]=s end end
  table.sort(out,function(a,b) return a.t<b.t end)
  return out
end
local function wheel(s,name) for _,w in ipairs(s and s.wheels or {}) do if w.name==name then return w end end end
local OPPOSITE={FL='FR',FR='FL',RL='RR',RR='RL'}
local function evaluate()
  local c,sum=result.checks,result.summary
  local spawnS,armed=find('spawn'),find('armed')
  c.tires_not_loaded_while_off=spawnS~=nil and spawnS.loaded==false
  c.loaded_with_heat=armed~=nil and armed.loaded==true and armed.heat==true and armed.profile=='sport'
  local cold=armed~=nil and #armed.wheels==4
  for _,w in ipairs(armed and armed.wheels or {}) do if w.state~='cold' then cold=false end end
  c.starts_cold=cold
  local circle,straight=partSamples('circle'),partSamples('straight')
  sum.circle_samples,sum.straight_samples=#circle,#straight
  -- The hottest tire at the end of the circle is the loaded outer one.
  local ce,se=circle[#circle],straight[#straight]
  local hot,hotC=nil,-1
  for _,w in ipairs(ce and ce.wheels or {}) do if (w.surface_c or -1)>hotC then hot,hotC=w.name,w.surface_c end end
  sum.hottest=hot
  local a0=wheel(armed,hot)
  local opp=wheel(ce,OPPOSITE[hot or ''])
  sum.hottest_armed_c=a0 and a0.surface_c
  sum.hottest_circle_end_c=hotC
  sum.opposite_circle_end_c=opp and opp.surface_c
  c.outer_tire_heats=a0~=nil and hotC-(a0.surface_c or 0)>=30
  c.load_side_hotter=opp~=nil and hotC-(opp.surface_c or 0)>=20
  -- When the hottest tire changed state, by circle time.
  sum.hottest_states={}
  local last=nil
  for _,s in ipairs(circle) do
    local w=wheel(s,hot)
    if w and w.state~=last then
      sum.hottest_states[#sum.hottest_states+1]={state=w.state,t=s.t-circle[1].t+SAMPLE_S,surface_c=w.surface_c}
      last=w.state
    end
  end
  local seenWindow=false
  for _,x in ipairs(sum.hottest_states) do if x.state=='window' then seenWindow=true end end
  c.reaches_window=seenWindow
  local hs=wheel(se,hot)
  sum.hottest_straight_end_c=hs and hs.surface_c
  c.straight_cools_hot_tire=hs~=nil and (hs.surface_c or 999)<hotC-5
  -- The HUD state follows the compound window (surface_c is rounded to 0.1 C).
  local stateOk,nState,nProduct,nLag,worst=true,0,0,0,0
  local all={}
  for _,s in ipairs(circle) do all[#all+1]=s end
  for _,s in ipairs(straight) do all[#all+1]=s end
  for _,s in ipairs(all) do
    for _,w in ipairs(s.wheels or {}) do
      if w.surface_c and w.low_c and w.high_c and w.state then
        local near=math.abs(w.surface_c-w.low_c)<=0.1 or math.abs(w.surface_c-w.high_c)<=0.1
        local want=w.surface_c<w.low_c and 'cold' or (w.surface_c>w.high_c and 'hot' or 'window')
        nState=nState+1
        if w.state~=want and not near then stateOk=false end
      end
      if w.grip and w.heat_grip and w.pressure_grip and w.damage_grip then
        nProduct=nProduct+1
        local want=math.max(s.min_grip or 0.6,w.heat_grip*w.pressure_grip*w.damage_grip)
        worst=math.max(worst,math.abs(w.grip-want))
        if math.abs(w.grip-want)>0.006 then nLag=nLag+1 end
      end
    end
  end
  sum.state_samples,sum.worst_grip_product_error,sum.grip_product_lag_samples=nState,worst,nLag
  c.hud_state_matches_window=nState>=100 and stateOk
  -- Grip is written every 0.1 s on a 0.002 move while the factors are read live (T009c).
  c.grip_written_is_product=nProduct>=100 and nLag<=math.max(1,math.floor(nProduct*0.02)) and worst<=0.015
  sum.curve={}
  for _,s in ipairs(all) do
    local row={part=s.part,t=s.t}
    for _,w in ipairs(s.wheels or {}) do row[w.name]=w.surface_c;row[w.name..'_state']=w.state end
    sum.curve[#sum.curve+1]=row
  end
  local ds=find('disabled')
  c.tires_unloaded_after_disable=ds~=nil and ds.loaded==false
  c.no_helper_errors=#result.errors==0
  local pass=true
  for _,v in pairs(c) do pass=pass and v==true end
  result.passed=pass
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
  if drive then driveStep(veh,dtReal,dtSim) end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER)
    -- A scripted level load leaves the main menu drawn over the game (T009c).
    guihooks.trigger('ChangeState',{state='play'})
    local st=status()
    result.checks.default_master_off=not st.enabled
    result.checks.default_tires_off=st.features.tire_temperature==false and st.physics_writes==0
    sample(veh,'spawn');event('spawned');phase,stageTime=3,0
  elseif phase==3 and stageTime>1 then
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    extensions.acng_core.setTireProfile('sport')
    event('heat_enabled');phase,stageTime=4,0
  elseif phase==4 and stageTime>3 then
    sample(veh,'armed')
    local st=status()
    result.checks.core_reports_heat=st.tires_vehicle_id==veh:getID() and st.physics_writes==1 and st.features.tire_temperature==true
    phase,stageTime=5,0
  elseif phase==5 and stageTime>1 then
    startDrive(veh,'circle',CIRCLE_SPEED,CIRCLE_STEER);cue('drive_start');event('circle');phase,stageTime=6,0
  elseif phase==6 and stageTime>CIRCLE_S then
    startDrive(veh,'straight',STRAIGHT_SPEED,nil);cue('circle_end');event('straight');phase,stageTime=7,0
  elseif phase==7 and stageTime>STRAIGHT_S then
    stopDrive(veh);cue('drive_end');event('stop');phase,stageTime=8,0
  elseif phase==8 and stageTime>4 then
    sample(veh,'after')
    extensions.acng_core.setFeature('tire_temperature',false);event('disabled');phase,stageTime=9,0
  elseif phase==9 and stageTime>3 then
    sample(veh,'disabled')
    local st=status()
    result.checks.core_reports_tires_off=st.tires_vehicle_id==nil and st.physics_writes==0
    phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    evaluate();result.completed=true;cue('complete');event('complete');phase=11
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
