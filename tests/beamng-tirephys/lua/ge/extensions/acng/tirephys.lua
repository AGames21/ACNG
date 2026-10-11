-- T009b isolated in-game validation of the T009 tire model; not distributed in the mod.
-- Stock etkc kc6_360_M on smallgrid, driven through the real ACNG controls
-- (acng_core.setEnabled / setFeature / setTireProfile). Sequence:
--   off        OFF baseline: half-lock circle at 10 m/s, extension not loaded
--   profiles   heat ON; auto, road, race and sport each give their own ideal hot pressure
--   pressure   one side 8 psi down: that side loses pressure grip
--   circle     60 s half-lock circle (sport): tread zones split, the cooked tire loses
--              heat grip, cold sliding grains, hot sliding blisters
--   straight   40 s at 20 m/s: grain cleans while a tire rolls in its window, blisters stay
--   reset      a reset gives clean tires
--   flat       a deflated tire is skipped by the damage step while the others still grain
--   perf       1200 updateGFX calls at a standstill, CPU time per call
--   off_again  tire_temperature OFF: unloaded, the circle must match the baseline
-- Dirt needs loose ground; smallgrid materials are recorded, the dirt part is not covered.
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local WINDOW_S=5
local AMBIENT_K=288.15
local COLD_PSI={F=30,R=28}    -- etkc kc6_360_M tire pressure variable defaults (T009a)
local CORE_C={road=30,sport=60,race=75}  -- each compound's idealCore
local result={schema_version=1,test='T009b tire model in-game validation',model='etkc',config='kc6_360_M',level='smallgrid',
  completed=false,checks={},windows={},samples={},events={},errors={},summary={}}
local drive,win,lastHeading=nil,nil,nil
local function save() jsonWriteFile('/acng-tirephys-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T009B',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngTPh",{})
local K=273.15
local function send(kind,data) obj:queueGameEngineLua(string.format('extensions.acng_tirephys.receive(%q,%q)',kind,jsonEncode(data))) end
local function wheelList() local out={} for i=0,tableSizeC(v.data.wheels)-1 do out[#out+1]=v.data.wheels[i] end return out end
local function psi(wd)
  local pg=wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
  local pa=pg and obj:getGroupPressure(pg)
  return type(pa)=='number' and (pa-101325)/6894.757 or nil
end
function acngTPh.sample(tag)
  local ok,err=pcall(function()
    local loaded=extensions.isExtensionLoaded('acng_tires')
    local m=loaded and extensions.acng_tires or nil
    local snap=m and m.getSnapshot() or nil
    local model,snapBy={},{}
    for _,t in ipairs(m and m.modelState() or {}) do model[t.name]=t end
    for _,t in ipairs(snap and snap.tires or {}) do snapBy[t.name]=t end
    local out={tag=tag,loaded=loaded,heat=snap and snap.heat,profile=snap and snap.profile,mode=snap and snap.mode,
      min_grip=m and m.MIN_GRIP,wheels={}}
    for _,wd in ipairs(wheelList()) do
      local rt=wheels.wheels[wd.cid] or {}
      local ms,st=model[wd.name] or {},snapBy[wd.name] or {}
      local w={name=wd.name,id=wd.wheelID,avg=obj:getWheelAvgTemperature(wd.wheelID)-K,psi=psi(wd),slip=rt.slipEnergy,
        mat=rt.contactMaterialID1,deflated=rt.isTireDeflated==true,broken=rt.isBroken==true,compound=st.compound,
        state=st.state,zone_nodes=ms.zone_nodes,zones_c=ms.zones_c,ideal_psi=ms.ideal_psi,heat_grip=ms.heat_grip,
        pressure_grip=ms.pressure_grip,damage_grip=ms.damage_grip,grain=ms.grain,blister=ms.blister,dirt=ms.dirt,
        surface=ms.surface,grip=ms.grip}
      if m and ms.zones_c then
        local z=ms.zones_c
        w.heat_grip_check=(m.gripAt(z[1],wd)+m.gripAt(z[2],wd)+m.gripAt(z[3],wd))/3
        w.avg_grip=m.gripAt(w.avg,wd)
      end
      out.wheels[#out.wheels+1]=w
    end
    send('sample',out)
  end)
  if not ok then send('error',{tag=tag,error=tostring(err)}) end
end
function acngTPh.sidePressure(side,dpsi)
  for _,wd in ipairs(wheelList()) do
    local pg=wd.pressureGroup and v.data.pressureGroups[wd.pressureGroup]
    if pg and tostring(wd.name):sub(-1)==side then obj:setGroupPressure(pg,obj:getGroupPressure(pg)+dpsi*6894.757) end
  end
end
local function damageSum(m)
  local s=0
  for _,t in ipairs(m.modelState()) do s=s+(t.grain or 0)+(t.blister or 0)+(t.dirt or 0) end
  return s
end
function acngTPh.perf(n)
  local ok,err=pcall(function()
    local m=extensions.isExtensionLoaded('acng_tires') and extensions.acng_tires
    if not m then send('perf',{error='acng_tires not loaded'}) return end
    local before=damageSum(m)
    local t0=os.clock()
    for _=1,n do m.updateGFX(1/60) end
    local cpu=os.clock()-t0
    send('perf',{calls=n,total_ms=cpu*1000,per_call_ms=cpu*1000/n,damage_before=before,damage_after=damageSum(m)})
  end)
  if not ok then send('error',{tag='perf',error=tostring(err)}) end
end
]]
local function sample(veh,tag) command(veh,string.format('acngTPh.sample(%q)',tag)) end
local function receive(kind,text)
  local d=jsonDecode(text) or {}
  if kind=='error' then result.errors[#result.errors+1]=d
  elseif kind=='perf' then result.perf=d
  else
    d.t=simTime;d.part=d.tag and d.tag:match('^[^#]+')
    result.samples[#result.samples+1]=d
  end
  save()
end
-- Drive at a held speed and fixed steering; windowed drives record the circle per 5 s
-- window (yaw rate -> lateral acceleration) and sample at each window end, others sample
-- every 5 s.
local function startDrive(veh,part,speed,steer,windowed)
  drive={part=part,speed=speed,steer=steer,windowed=windowed,t=0,n=0};lastHeading=nil
  win={index=1,t=0,yaw=0,v=0}
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',"..steer..",2)")
end
-- Stop with the realistic gearbox, clutch in and foot brake; the arcade gearbox reverses
-- under brake at a standstill (T004a).
local function stopDrive(veh)
  drive=nil;win=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function driveStep(veh,dtReal,dtSim)
  controlTime=controlTime+dtReal
  if controlTime>0.1 then
    controlTime=0
    local speed=veh:getVelocity():length()
    command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(drive.speed-speed)))))
  end
  drive.t=drive.t+dtSim
  if drive.windowed then
    local d=veh:getDirectionVector()
    local h=math.atan2(d.y,d.x)
    if lastHeading and dtSim>0 then
      local dh=h-lastHeading
      if dh>math.pi then dh=dh-2*math.pi elseif dh<-math.pi then dh=dh+2*math.pi end
      win.yaw=win.yaw+dh;win.t=win.t+dtSim;win.v=win.v+veh:getVelocity():length()*dtSim
    end
    lastHeading=h
    if win.t>=WINDOW_S then
      local yaw,v=math.abs(win.yaw)/win.t,win.v/win.t
      result.windows[#result.windows+1]={part=drive.part,index=win.index,speed_m_s=v,lateral_m_s2=v*yaw,radius_m=v/yaw}
      sample(veh,drive.part..'#'..win.index)
      win={index=win.index+1,t=0,yaw=0,v=0}
    end
  else
    local n=math.floor(drive.t/WINDOW_S)
    if n>drive.n then drive.n=n;sample(veh,drive.part..'#'..n) end
  end
end
local function find(tag) for _,s in ipairs(result.samples) do if s.tag==tag then return s end end end
local function wheel(s,name) for _,w in ipairs(s and s.wheels or {}) do if w.name==name then return w end end end
local function partSamples(name)
  local out={}
  for _,s in ipairs(result.samples) do if s.part==name then out[#out+1]=s end end
  return out
end
local function meanLateral(name,from,to)
  local t,n=0,0
  for _,w in ipairs(result.windows) do
    if w.part==name and w.index>=from and w.index<=to then t=t+w.lateral_m_s2;n=n+1 end
  end
  return n>0 and t/n or nil
end
local function idealFor(name,profile)
  local cold=COLD_PSI[tostring(name):sub(1,1)]
  return ((cold*6894.757+101325)*(CORE_C[profile]+273.15)/(20+273.15)-101325)/6894.757
end
local function idealOk(s,profile)
  if not s or not s.loaded or #s.wheels==0 then return false end
  for _,w in ipairs(s.wheels) do
    if type(w.ideal_psi)~='number' or math.abs(w.ideal_psi-idealFor(w.name,profile))>0.3 then return false end
  end
  return true
end
local function worstDev(name)
  local worst=0
  for _,s in ipairs(partSamples(name)) do
    for _,w in ipairs(s.wheels or {}) do worst=math.max(worst,math.abs(w.avg+273.15-AMBIENT_K)) end
  end
  return worst
end
local function evaluate()
  local c,sum=result.checks,result.summary
  local spawn,sport=find('spawn'),find('sport')
  c.tires_not_loaded_while_off=spawn~=nil and spawn.loaded==false
  sum.off_worst_temp_dev_k=worstDev('off')
  c.off_temps_flat=#partSamples('off')>0 and sum.off_worst_temp_dev_k<0.5
  sum.off_lateral=meanLateral('off',3,4)
  -- Enable and profiles.
  c.loaded_with_heat=sport~=nil and sport.loaded==true and sport.heat==true and sport.profile=='sport'
  sum.auto_compound={};for _,w in ipairs(find('auto') and find('auto').wheels or {}) do sum.auto_compound[w.name]=w.compound end
  sum.ideal_psi={}
  for _,p in ipairs({'auto','road','sport','race'}) do
    local s=find(p);sum.ideal_psi[p]={}
    for _,w in ipairs(s and s.wheels or {}) do sum.ideal_psi[p][w.name]=w.ideal_psi end
  end
  c.ideal_psi_per_profile=idealOk(find('road'),'road') and idealOk(sport,'sport') and idealOk(find('race'),'race')
  local zonesFound=sport~=nil and #sport.wheels==4
  sum.zone_nodes={}
  for _,w in ipairs(sport and sport.wheels or {}) do
    sum.zone_nodes[w.name]=w.zone_nodes
    if not (w.zone_nodes and w.zone_nodes[1]>0 and w.zone_nodes[3]>0) then zonesFound=false end
  end
  c.tread_zones_found=zonesFound
  -- Every heat-on sample: heat grip is the mean zone grip, the grip written is the product
  -- of the factors, and with equal edge node counts the edges average to the middle (the
  -- zones keep the wheel average as their level).
  local meanOk,productOk,anchorOk,nOn,worstProduct=true,true,true,0,0
  for _,s in ipairs(result.samples) do
    if s.loaded and s.heat then
      for _,w in ipairs(s.wheels or {}) do
        if w.heat_grip and w.heat_grip_check then
          nOn=nOn+1
          if math.abs(w.heat_grip-w.heat_grip_check)>1e-6 then meanOk=false end
          local want=math.max(s.min_grip or 0.6,w.heat_grip*w.pressure_grip*w.damage_grip)
          if w.grip then worstProduct=math.max(worstProduct,math.abs(w.grip-want)) end
          if not w.grip or math.abs(w.grip-want)>0.006 then productOk=false end
          local z,zn=w.zones_c,w.zone_nodes
          if zn and zn[1]==zn[3] and zn[2]==0 and math.abs((z[1]+z[3])/2-z[2])>0.05 then anchorOk=false end
        end
      end
    end
  end
  sum.heat_on_tire_samples=nOn;sum.worst_grip_product_error=worstProduct
  c.heat_grip_is_zone_mean=nOn>20 and meanOk
  c.grip_written_is_product=nOn>20 and productOk
  c.zones_anchored_on_average=nOn>20 and anchorOk
  -- Pressure.
  local ps=find('pressure')
  local pressureOk=ps~=nil and ps.loaded==true
  sum.pressure={}
  for _,axle in ipairs({'F','R'}) do
    local l,r=wheel(ps,axle..'L'),wheel(ps,axle..'R')
    sum.pressure[axle]=l and r and {left_psi=l.psi,right_psi=r.psi,left_grip=l.pressure_grip,right_grip=r.pressure_grip,ideal=l.ideal_psi}
    if not (l and r and l.psi<r.psi-6 and l.pressure_grip<r.pressure_grip-0.02 and l.grip<r.grip) then pressureOk=false end
  end
  c.low_pressure_loses_grip=pressureOk
  -- Circle.
  local circle=partSamples('circle')
  local split,cooked,grained,blistered,edge=0,false,false,false,false
  for _,s in ipairs(circle) do
    for _,w in ipairs(s.wheels or {}) do
      local z=w.zones_c
      if z then
        split=math.max(split,math.abs(z[1]-z[3]))
        if math.max(z[1],z[2],z[3])>105 and w.heat_grip<0.99 then cooked=true end
        if w.avg>=75 and w.avg<=105 and w.avg_grip==1 and w.heat_grip<0.999 then edge=true end
      end
      if (w.grain or 0)>0.005 then grained=true end
      if (w.blister or 0)>0.001 then blistered=true end
    end
  end
  sum.circle_max_zone_split_c=split;sum.edge_penalty_with_average_in_window=edge
  c.corner_splits_zones=#circle>=10 and split>5
  c.cooked_tire_loses_heat_grip=cooked
  c.cold_sliding_grains=grained
  c.hot_sliding_blisters=blistered
  sum.circle_lateral=meanLateral('circle',3,12)
  c.model_grip_reduces_lateral=(sum.circle_lateral and sum.off_lateral and sum.circle_lateral<sum.off_lateral*0.99) or false
  local ce,as=circle[#circle],find('after_straight')
  sum.circle_end,sum.after_straight={}, {}
  -- Grain only falls by cleaning, so any drop between consecutive driving samples is it.
  -- (The stop after the straight brakes cold tires to a slide, which grains them again.)
  local cleaned,persist,anyBlister=false,as~=nil,false
  local driving={};for _,s in ipairs(circle) do driving[#driving+1]=s end
  for _,s in ipairs(partSamples('straight')) do driving[#driving+1]=s end
  sum.grain_cleaned={}
  for i=2,#driving do
    for _,w in ipairs(driving[i].wheels or {}) do
      local prev=wheel(driving[i-1],w.name)
      if prev and (prev.grain or 0)>0.002 and (w.grain or 0)<(prev.grain or 0)-0.002 then
        cleaned=true
        sum.grain_cleaned[#sum.grain_cleaned+1]={name=w.name,tag=driving[i].tag,from=prev.grain,to=w.grain,avg=w.avg}
      end
    end
  end
  for _,w in ipairs(ce and ce.wheels or {}) do
    local a=wheel(as,w.name)
    sum.circle_end[w.name]={avg=w.avg,zones_c=w.zones_c,grain=w.grain,blister=w.blister,heat_grip=w.heat_grip,pressure_grip=w.pressure_grip,psi=w.psi,grip=w.grip}
    if a then
      sum.after_straight[w.name]={avg=a.avg,grain=a.grain,blister=a.blister,grip=a.grip}
      if (a.blister or 0)<(w.blister or 0)-1e-9 then persist=false end
      if (w.blister or 0)>0 then anyBlister=true end
    end
  end
  c.grain_cleans_in_window=cleaned
  c.blisters_persist=persist and anyBlister
  -- Reset.
  local rs=find('reset')
  local clean=rs~=nil and rs.loaded==true and #rs.wheels==4
  -- The car settles for a second after the reset, so allow the grain of that settle.
  for _,w in ipairs(rs and rs.wheels or {}) do
    if (w.grain or 1)>1e-4 or (w.blister or 1)>1e-4 or (w.dirt or 1)>1e-4 or not w.zones_c then clean=false end
  end
  c.reset_gives_clean_tires=clean
  -- Flat.
  -- The deflated tire's grain and blister freeze at their flat_start values.
  local fs,fe=find('flat_start'),find('flat_end')
  local flatSkipped,flatSeen,othersGrain=fs~=nil and fe~=nil,false,false
  for _,w in ipairs(fe and fe.wheels or {}) do
    if w.deflated then
      flatSeen=true
      local w0=wheel(fs,w.name)
      if not w0 or math.abs((w.grain or 0)-(w0.grain or 0))>1e-9 or math.abs((w.blister or 0)-(w0.blister or 0))>1e-9 then flatSkipped=false end
      sum.flat_tire={name=w.name,psi=w.psi,grain=w.grain,blister=w.blister,grip=w.grip}
    elseif (w.grain or 0)>0 then othersGrain=true end
  end
  c.deflated_tire_skipped=flatSkipped and flatSeen and othersGrain and fe.loaded==true
  -- Performance and errors.
  local perf=result.perf or {}
  sum.perf=perf
  c.perf_under_0_1_ms=type(perf.per_call_ms)=='number' and perf.per_call_ms<0.1
  c.perf_standstill_no_damage=type(perf.damage_before)=='number' and math.abs(perf.damage_after-perf.damage_before)<1e-9
  c.no_helper_errors=#result.errors==0
  -- Dirt: only on loose ground; record what smallgrid offered.
  local mats,loose={},false
  local LOOSE={[7]=true,[14]=true,[15]=true,[16]=true,[17]=true,[18]=true,[19]=true,[20]=true,[22]=true,[31]=true}
  for _,s in ipairs(result.samples) do
    for _,w in ipairs(s.wheels or {}) do
      if type(w.mat)=='number' then mats[tostring(w.mat)]=true;if LOOSE[w.mat] then loose=true end end
    end
  end
  sum.contact_materials=mats;sum.dirt_covered=loose
  -- OFF again.
  local ds=find('disabled')
  c.tires_unloaded_after_disable=ds~=nil and ds.loaded==false
  sum.off_again_worst_temp_dev_k=worstDev('off_again')
  c.off_again_temps_flat=#partSamples('off_again')>0 and sum.off_again_worst_temp_dev_k<0.5
  sum.off_again_lateral=meanLateral('off_again',3,4)
  c.off_again_matches_baseline=(sum.off_again_lateral and sum.off_lateral and math.abs(sum.off_again_lateral-sum.off_lateral)<sum.off_lateral*0.02) or false
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
    local st=status()
    result.checks.default_master_off=not st.enabled
    result.checks.default_tires_off=st.features.tire_temperature==false and st.features.tire_wear==false and st.physics_writes==0
    sample(veh,'spawn');event('spawned');phase,stageTime=3,0
  elseif phase==3 and stageTime>1 then
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=4,0
  elseif phase==4 and stageTime>3 then
    startDrive(veh,'off',10,0.5,true);event('off_drive');phase,stageTime=5,0
  elseif phase==5 and stageTime>20.5 then
    stopDrive(veh);phase,stageTime=6,0
  elseif phase==6 and stageTime>3 then
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    event('heat_enabled');phase,stageTime=7,0
  elseif phase==7 and stageTime>3 then
    sample(veh,'auto')
    local st=status()
    result.checks.core_reports_heat=st.tires_vehicle_id==veh:getID() and st.physics_writes==1 and st.features.tire_temperature==true
    extensions.acng_core.setTireProfile('road');phase,stageTime=8,0
  elseif phase==8 and stageTime>2 then
    sample(veh,'road');extensions.acng_core.setTireProfile('race');phase,stageTime=9,0
  elseif phase==9 and stageTime>2 then
    sample(veh,'race');extensions.acng_core.setTireProfile('sport');phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    sample(veh,'sport')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=11,0
  elseif phase==11 and stageTime>3 then
    command(veh,"acngTPh.sidePressure('L',-8)");event('left_minus_8psi');phase,stageTime=12,0
  elseif phase==12 and stageTime>1.5 then
    sample(veh,'pressure')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=13,0
  elseif phase==13 and stageTime>3 then
    startDrive(veh,'circle',10,0.5,true);event('circle');phase,stageTime=14,0
  elseif phase==14 and stageTime>60.5 then
    startDrive(veh,'straight',20,0,false);event('straight');phase,stageTime=15,0
  elseif phase==15 and stageTime>40.5 then
    stopDrive(veh);phase,stageTime=16,0
  elseif phase==16 and stageTime>4 then
    sample(veh,'after_straight')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=17,0
  elseif phase==17 and stageTime>2 then
    sample(veh,'reset');phase,stageTime=18,0
  elseif phase==18 and stageTime>1 then
    command(veh,"beamstate.deflateTire(0)");event('flat');phase,stageTime=19,0
  elseif phase==19 and stageTime>3 then
    sample(veh,'flat_start');startDrive(veh,'flat',10,0.5,false);phase,stageTime=20,0
  elseif phase==20 and stageTime>15.5 then
    sample(veh,'flat_end');stopDrive(veh);phase,stageTime=21,0
  elseif phase==21 and stageTime>3 then
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=22,0
  elseif phase==22 and stageTime>3 then
    command(veh,'acngTPh.perf(1200)');event('perf');phase,stageTime=23,0
  elseif phase==23 and stageTime>2 then
    extensions.acng_core.setFeature('tire_temperature',false);event('disabled');phase,stageTime=24,0
  elseif phase==24 and stageTime>3 then
    sample(veh,'disabled')
    local st=status()
    result.checks.core_reports_tires_off=st.tires_vehicle_id==nil and st.physics_writes==0
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=25,0
  elseif phase==25 and stageTime>3 then
    startDrive(veh,'off_again',10,0.5,true);event('off_again_drive');phase,stageTime=26,0
  elseif phase==26 and stageTime>20.5 then
    stopDrive(veh);phase,stageTime=27,0
  elseif phase==27 and stageTime>2 then
    evaluate();result.completed=true;event('complete');phase=28
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
