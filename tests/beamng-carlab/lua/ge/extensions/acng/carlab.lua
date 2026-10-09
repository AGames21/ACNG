-- C001 isolated check of the user's local AC-converted car (acng_bmw1m); never deploy to a player profile.
-- The car zip is built locally by converters/build_ac_car.py and placed in this lab profile only by
-- scripts/launch-lab.ps1 -ExtraMod; it is never copied into the repo or ACNG packages.
-- Spawn on smallgrid, confirm the AC meshes replaced the ETK skin, then the FR002b damage path:
-- drive and brake, crash into a parked pickup, puncture and break a wheel, master OFF/ON, reset.
local M={}
local elapsed,co,response=0,nil,nil
local simElapsed=0
local MODEL='acng_bmw1m'
local result={test='C013 1M native limiter and event sounds',completed=false,checks={},probes={},shots={}}
local stage='start'
local function save() result.stage=stage;jsonWriteFile('/acng-car-test.json',result,true) end
local function check(name,ok) result.checks[name]=ok==true;save();if not ok then log('W','ACNG_C001','FAIL '..name) end;return ok==true end
local function waitFor(fn,timeout)
  local start=elapsed
  while not fn() do if elapsed-start>(timeout or 12) then error('Native wait timeout at '..stage) end;coroutine.yield() end
end
local function delay(seconds) local stop=elapsed+seconds;while elapsed<stop do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local PROBE=[[
local r={props={},mass_kg=0,body_mass_kg=0,specs={},tires=extensions.isExtensionLoaded('acng_tires'),damage=beamstate.damage,wheels={},native_tires=0,finite=true,
  tread_min=nil,ac_meshes={},etk_skin=0,flexbodies=0}
local wd=v.data.wheels
if wd then for i=0,tableSizeC(wd)-1 do local w=wd[i];if w and (w.hasTire or w.hasTire==nil) then r.native_tires=r.native_tires+1 end end end
for _,w in pairs(wheels.wheels or {}) do r.wheels[#r.wheels+1]={name=w.name,broken=w.isBroken==true,deflated=w.isTireDeflated==true} end
for id,node in pairs(v.data.nodes or {}) do local mass=obj:getNodeMass(node.cid or id);r.mass_kg=r.mass_kg+mass;if node.partOrigin=='etkc_body' then r.body_mass_kg=r.body_mass_kg+mass end end
r.broken_beams={};r.new_nodes={}
for id,b in pairs(v.data.beams or {}) do
 if obj:beamIsBroken(b.cid or id) and #r.broken_beams<12 then
  r.broken_beams[#r.broken_beams+1]={part=b.partOrigin,n1=v.data.nodes[b.id1].name,n2=v.data.nodes[b.id2].name}
 end
end
for id,n in pairs(v.data.nodes or {}) do if tostring(n.name):find('^acng_bmw1m') then
 local p=obj:getNodePosition(n.cid or id);r.new_nodes[#r.new_nodes+1]={name=n.name,cid=n.cid or id,x=p.x,y=p.y,z=p.z,mass=obj:getNodeMass(n.cid or id)}
end end
local e=powertrain.getDevice('mainEngine');local gb=powertrain.getDevice('gearbox');local diff=powertrain.getDevice('differential_R')
if e then local ok,d=pcall(function() return e:getTorqueData() end);if ok then r.specs.peak_hp=d.maxPower;r.specs.peak_nm=d.maxTorque
  -- Full-boost curve (highest priority: Turbo over NA), indexed rpm+1 by getTorqueData.
  local best;for _,c in pairs(d.curves or {}) do if not best or c.priority>best.priority then best=c end end
  if best then r.specs.curve_name=best.name;r.specs.curve={}
   for rpm=1000,7000,500 do local nm=best.torque[rpm+1];if nm then r.specs.curve[#r.specs.curve+1]={rpm,nm} end end end end
 r.specs.idle_rpm=e.idleRPM;r.specs.max_rpm=e.maxRPM end
if gb then r.specs.ratios=gb.gearRatios end;if diff then r.specs.final_drive=diff.gearRatio end
local tank=energyStorage.getStorage('mainTank');if tank then r.specs.fuel_capacity_l=tank.capacity;r.specs.fuel_l=tank.remainingVolume end
r.glow=0;for k,_ in pairs(v.data.glowMap or {}) do if tostring(k):find('^acng_bmw1m_') then r.glow=r.glow+1 end end
if e and e.soundConfiguration then local c=e.soundConfiguration
  r.sound={engine=c.engine and c.engine.blendFile,exhaust=c.exhaust and c.exhaust.blendFile,id=e.engineSoundID,id_exhaust=e.engineSoundIDExhaust} end
r.limiter={configured_m_s=v.data.vehicleController and v.data.vehicleController.topSpeedLimit,
  wheel_m_s=electrics.values.wheelspeed,throttle_input=electrics.values.throttle_input,
  controller_throttle=controller.mainController.throttle}
local events=rawget(_G,'acngEventSounds');if events then r.event_sounds=events;rawset(_G,'acngEventSounds',nil) end
-- rawget/rawset: plain globals trip BeamNG's undeclared-global warning.
local fit=rawget(_G,'acngFit');if fit then r.fit=fit;rawset(_G,'acngFit',nil) end
r.lights={lowbeam=electrics.values.lowbeam,brakelights=electrics.values.brakelights,reverse=electrics.values.reverse}
local J=rawget(_G,'acngJ')
if J then
  local worst,wname,base=0,nil,0
  for name,s in pairs(J.span) do local d=s[2]-s[1]
    if name=='__chassis' then base=d elseif d>worst then worst,wname=d,name end end
  r.jitter={max_mm=worst*1000,worst=wname,chassis_mm=base*1000,frames=J.frames}
  rawset(_G,'acngJ',nil)
end
for _,p in pairs(v.data.props or {}) do if tostring(p.mesh):find('^acng_bmw1m_') then r.props[#r.props+1]={mesh=p.mesh,func=p.func,pid=p.pid,input=electrics.values[p.func] or 0} end end
 r.mirrors={};for _,m in pairs(v.data.mirrors or {}) do r.mirrors[#r.mirrors+1]={mesh=m.mesh,id=m.id} end
for id,n in pairs(v.data.nodes or {}) do if n.name=='sh_l3' then local p=obj:getNodePosition(n.cid or id);r.shifter_position={p.x,p.y,p.z} end end
-- Front wheel axle yaw in the car frame, to read the steering direction from physics.
r.wheel_yaw={};pcall(function()
 local fwd,up=obj:getDirectionVector(),obj:getDirectionVectorUp();local right=fwd:cross(up)
 for i=0,tableSizeC(wd)-1 do local w=wd[i];if w and (w.name=='FL' or w.name=='FR') then
  local p1=obj:getNodePosition(w.node1);local x1,y1,z1=p1.x,p1.y,p1.z  -- copy: the vector may be reused
  local p2=obj:getNodePosition(w.node2);local a=vec3(p2.x-x1,p2.y-y1,p2.z-z1)
  r.wheel_yaw[w.name]=math.deg(math.atan2(a:dot(fwd),a:dot(right))) end end end)
r.controls={steering=electrics.values.steering,brake=electrics.values.brake,throttle=electrics.values.throttle,clutch=electrics.values.clutch,shift_x=electrics.values.hPatternAxisX,shift_y=electrics.values.hPatternAxisY}
for _,f in pairs(v.data.flexbodies or {}) do
  r.flexbodies=r.flexbodies+1
  local m=tostring(f.mesh)
  if m:find('^acng_bmw1m_') then r.ac_meshes[#r.ac_meshes+1]=m end
  if m=='etkc_body' or m=='etkc_door_L' or m=='etkc_hood' or m=='etkc_dash' then r.etk_skin=r.etk_skin+1 end
end
if r.tires then
  local s=extensions.acng_tires.getSnapshot();r.profile=s.profile;r.acng_tires=#s.tires
  for _,t in ipairs(s.tires) do
    if t.surface_c==nil or t.grip==nil then r.finite=false end
    if t.tread then r.tread_min=math.min(r.tread_min or 1,t.tread) end
    r.compound=t.compound
  end
end
obj:queueGameEngineLua(string.format('extensions.acng_carlab.receive(%q)',jsonEncode(r)))]]
local function probe(label,code)
  stage=label;local veh=be:getPlayerVehicle(0);assert(veh);response=nil
  -- newline, not ';': LuaJIT rejects a chunk that starts with an empty statement.
  veh:queueLuaCommand((code or '')..'\n'..PROBE)
  waitFor(function() return response~=nil end)
  response.label=label;response.ac_meshes_n=#response.ac_meshes
  local keep={}
  for k,v in pairs(response) do if k~='ac_meshes' then keep[k]=v end end
  result.probes[#result.probes+1]=keep;save()
  return response
end
-- Static tire position in the jbeam/mesh frame (same frame as the AC meshes): tire-ring nodes
-- (radius > 0.29 m from the hub axis) from their initial jbeam positions. C007 mixed world
-- node positions with jbeam positions and reported a 3.11 m wheelbase.
local FIT=[[
local fit,nodes,wd={},v.data.nodes,v.data.wheels
for i=0,tableSizeC(wd)-1 do local w=wd[i]
 if w and w.name and nodes[w.node1] and nodes[w.node2] and nodes[w.node1].pos then
  local h1,h2=nodes[w.node1].pos,nodes[w.node2].pos;local a=(h2-h1):normalized()
  local f={n=0,xmin=1e9,xmax=-1e9,y=0,z=0,hub={(h1.x+h2.x)/2,(h1.y+h2.y)/2,(h1.z+h2.z)/2}}
  for _,n in pairs(nodes) do if n.wheelID==i and n.pos then local d=n.pos-h1;local rad=(d-a*d:dot(a)):length()
   if rad>0.29 then f.n=f.n+1;f.xmin=math.min(f.xmin,n.pos.x);f.xmax=math.max(f.xmax,n.pos.x);f.y=f.y+n.pos.y;f.z=f.z+n.pos.z end end end
  if f.n>0 then f.y=f.y/f.n;f.z=f.z/f.n end
  fit[w.name]=f
 end
end
rawset(_G,'acngFit',fit)]]
local function vcmd(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
-- Distance from every ACNG seat/prop node to dash node dsh3, sampled once per frame. A steady
-- mount keeps it within a millimetre or two; the old 2%-damped mounts rang visibly.
local JIT=[[
local J=rawget(_G,'acngJ')
if not J then J={pairs={},span={},frames=0};rawset(_G,'acngJ',J)
  local cid={};for id,n in pairs(v.data.nodes) do if n.name then cid[n.name]=n.cid or id end end
  for name,c in pairs(cid) do if tostring(name):find('^acng_bmw1m_') then J.pairs[name]={c,cid.dsh3} end end
  J.pairs.__chassis={cid.dsh1l,cid.f7l}
end
J.frames=J.frames+1
-- Copy coordinates at once: getNodePosition may hand back a reused vector.
for name,p in pairs(J.pairs) do local a=obj:getNodePosition(p[1]);local ax,ay,az=a.x,a.y,a.z
  local b=obj:getNodePosition(p[2]);local d=math.sqrt((ax-b.x)^2+(ay-b.y)^2+(az-b.z)^2)
  local s=J.span[name];if s then s[1]=math.min(s[1],d);s[2]=math.max(s[2],d) else J.span[name]={d,d} end end]]
local function sampleJitter(seconds)
  local stop=elapsed+seconds
  while elapsed<stop do vcmd(JIT);coroutine.yield() end
end
local function anyBroken(r) for _,w in ipairs(r.wheels) do if w.broken then return true end end return false end
local function anyDeflated(r) for _,w in ipairs(r.wheels) do if w.deflated then return true end end return false end
local DRIVE="controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,1)"
local STOP="controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('brake',1,1)"
local EVENT_SOUNDS=[[
local out={}
local turbo=v.data.turbocharger or {};local h=v.data.hPattern or {}
local slots={turbo=turbo.whineLoopEvent,flutter_4=turbo.bovSoundFileName,
  gearup=h.shiftSoundEventHPatternGearIn,geardn=h.shiftSoundEventHPatternGearOut}
for _,name in ipairs({'turbo','flutter_4','gearup','geardn'}) do
 local expected='vehicles/acng_bmw1m/sounds/acng_1m_'..name..'.wav'
 local file=slots[name];local entry={file=file,configured=file==expected,exists=FS:fileExists('/'..expected)}
 if entry.configured and entry.exists then
  local ok,id=pcall(function() return obj:createSFXSource2(file,'AudioDefaultLoop3D','ACNG_C013_'..name,0,0) end)
  entry.source_id=ok and id or nil;entry.loaded=ok and type(id)=='number' and id>=0
  if entry.loaded then obj:stopSFX(id) end
 end
 out[name]=entry
end
rawset(_G,'acngEventSounds',out)]]
local function testSpeedLimiter()
  stage='sustained native speed limiter';save()
  local samples={};local start,nextSample=simElapsed,simElapsed
  local reached,peak=nil,0
  vcmd(DRIVE..";input.event('throttle',1,1)")
  while simElapsed-start<180 do
    local speed=be:getPlayerVehicle(0):getVelocity():length()*3.6
    peak=math.max(peak,speed)
    if simElapsed>=nextSample then
      local p=probe('limiter sample')
      samples[#samples+1]={time_s=simElapsed-start,km_h=speed,signals=p.limiter}
      nextSample=simElapsed+2
    end
    if speed>=245 and not reached then reached=simElapsed end
    if reached and simElapsed-reached>=15 then break end
    coroutine.yield()
  end
  local held,cut,count=true,false,0
  for _,s in ipairs(samples) do
    if reached and s.time_s>=reached-start+5 then
      -- The limiter governs wheel speed (also what the speedometer shows); ground speed sits
      -- about 1 % lower from tire slip at 250 (C013 first run: wheel 250.0, ground 247.9).
      local l=s.signals or {}
      local wheel=(l.wheel_m_s or 0)*3.6
      count=count+1;held=held and wheel>=248 and wheel<=252 and s.km_h>=245
      cut=cut or ((l.throttle_input or 0)>0.95 and (l.controller_throttle or 1)<0.95)
    end
  end
  result.speed_limiter={samples=samples,peak_km_h=peak,held_samples=count,throttle_reduction=cut}
  check('top_speed_limiter_holds_250',reached~=nil and count>=4 and held and cut and peak<=253)
  vcmd(STOP);delay(3)
  vcmd('obj:requestReset(RESET_PHYSICS)');delay(5)
  spawn.safeTeleport(be:getPlayerVehicle(0),vec3(0,0,1),quat(0,0,0,1));delay(4)
end
local function peakDuring(seconds,jitter)
  local stop,peak=elapsed+seconds,0
  while elapsed<stop do
    peak=math.max(peak,be:getPlayerVehicle(0):getVelocity():length())
    if jitter then vcmd(JIT) end
    coroutine.yield()
  end
  return peak
end
-- Free camera looking at the car from (dx,dy,dz) metres away; then an in-engine screenshot.
-- The stock screenshot module must know the job id, or later captures are silently dropped.
local function capture(file)
  local opts={filename=file,writeJPG=true,superSampling=1}
  if screenshot and screenshot.createScreenshotTracked then return screenshot.createScreenshotTracked(opts) or 0 end
  return type(createScreenshot2)=='function' and createScreenshot2(opts) or 0
end
local function shot(name,dx,dy,dz,cockpit)
  stage='shot '..name
  local p=be:getPlayerVehicle(0):getPosition()
  local ok=pcall(function()
    commands.setFreeCamera()
    local eye=vec3(p.x+dx,p.y+dy,p.z+dz)
    local dir=(vec3(p.x,p.y,p.z+0.5)-eye):normalized()
    if cockpit then
      local veh=be:getPlayerVehicle(0);local f=veh:getDirectionVector();local up=veh:getDirectionVectorUp();local right=f:cross(up)
      eye=p-right*dx-f*dy+up*dz
      local target=p-right*0.36-f*(-0.75)+up*(cockpit=='pedals' and 0.32 or 0.87)
      dir=(target-eye):normalized()
      if cockpit=='pedals' then
        local snapshot=result.probes[#result.probes]
        for _,n in ipairs(snapshot.new_nodes or {}) do if n.name=='acng_bmw1m_pedal_brake_ref' then
          target=p+veh:getNodePosition(n.cid)-up*0.05
          eye=target-f*0.42+up*0.24
          dir=(target-eye):normalized()
        end end
      end
      if cockpit=='gauges' then
        local points={};local snapshot=result.probes[#result.probes]
        for _,n in ipairs(snapshot.new_nodes or {}) do
          if n.name=='acng_bmw1m_gauge_rpm_ref' or n.name=='acng_bmw1m_gauge_speed_ref' then points[#points+1]=p+veh:getNodePosition(n.cid) end
        end
        assert(#points==2,'Gauge pivots missing')
        target=(points[1]+points[2])*0.5;eye=target-f*0.18+up*0.015
        dir=(target-eye):normalized()
      end
    end
    local q=quatFromDir(dir,vec3(0,0,1))
    core_camera.setPosRot(0,eye.x,eye.y,eye.z,q.x,q.y,q.z,q.w)
    if cockpit=='wheel' then commands.setGameCamera();core_camera.setByName(0,'driver',false) end
  end)
  delay(3)
  local file='screenshots/acng_c001_'..name
  local id=capture(file)
  result.shots[#result.shots+1]={name=name,camera=ok,file=file..'.jpg',id=id};save()
  delay(4)
  pcall(function() commands.setGameCamera() end)
end
-- Camera placed relative to the car: eye/target are {forward, right, up} metres from its position.
local function localShot(name,eye,target)
  stage='shot '..name
  local ok=pcall(function()
    local veh=be:getPlayerVehicle(0);local p=veh:getPosition()
    local f=veh:getDirectionVector();local up=veh:getDirectionVectorUp();local right=f:cross(up)
    local function at(o) return p+f*o[1]+right*o[2]+up*o[3] end
    commands.setFreeCamera()
    local e=at(eye);local q=quatFromDir((at(target)-e):normalized(),vec3(0,0,1))
    core_camera.setPosRot(0,e.x,e.y,e.z,q.x,q.y,q.z,q.w)
  end)
  delay(3)
  local file='screenshots/acng_c001_'..name
  local id=capture(file)
  result.shots[#result.shots+1]={name=name,camera=ok,file=file..'.jpg',id=id};save()
  delay(4)
  pcall(function() commands.setGameCamera() end)
end
-- Crash spike check: show one AC mesh group at a time on the wrecked car, from the front and the
-- left-front corner, so a stretched panel can be told apart from its neighbours.
local ISOLATE={{'lights_F','_lights_F[LR]'},{'bumper_F','_bumper_F'},{'fenders','_fender_'},{'hood','_hood'},{'body','_body'}}
local function isolationShots()
  local veh=be:getPlayerVehicle(0)
  for _,g in ipairs(ISOLATE) do
    local shown=0
    pcall(function() veh:setMeshAlpha(0,'',false)
      for _,m in ipairs(result.ac_meshes or {}) do if m:find(g[2]) then veh:setMeshAlpha(1,m,false);shown=shown+1 end end end)
    result.isolated=result.isolated or {};result.isolated[g[1]]=shown
    localShot('iso_'..g[1]..'_front',{4.5,0,1.2},{0,0,0.5})
    localShot('iso_'..g[1]..'_FL',{2.5,-3.5,1.3},{1.4,-0.6,0.5})
  end
  pcall(function() veh:setMeshAlpha(1,'',false) end)
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  assert(FS:getUserPath():gsub('\\','/'):lower():match('/acng%-car%-[%w%-]+/current/?$'),'Fresh isolated car profile required')
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,150)
  delay(6)
  check('startup_off',not status().enabled)
  settings.setValue('GraphicDynMirrorsEnabled',true) -- isolated lab only
  check('detailed_mirrors_enabled',settings.getValue('GraphicDynMirrorsEnabled')==true)
  stage='spawn'
  core_vehicles.replaceVehicle(MODEL,{config='vehicles/'..MODEL..'/acng_etk_baseline.pc'})
  waitFor(function() local v=be:getPlayerVehicle(0);return v and v:getJBeamFilename()==MODEL end,90)
  delay(8)
  local baseline=probe('etk_baseline');check('donor_baseline_undamaged',(baseline.damage or 0)<50)
  core_vehicles.replaceVehicle(MODEL,{})
  waitFor(function() local v=be:getPlayerVehicle(0);return v and v:getJBeamFilename()==MODEL end,90)
  delay(8)
  local veh=be:getPlayerVehicle(0)
  spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(5)
  check('model_loaded',veh:getJBeamFilename()==MODEL)
  local r=probe('spawn')
  result.ac_meshes=r.ac_meshes
  check('ac_meshes_bound',r.ac_meshes_n>=11)
  check('etk_skin_removed',r.etk_skin==0)
  check('car_at_rest',veh:getVelocity():length()<0.3)
  check('spawn_undamaged',(r.damage or 0)<50)
  local controls,gauges,created=0,0,true
  for _,p in ipairs(r.props) do if p.mesh:find('gauge_') then gauges=gauges+1 else controls=controls+1 end;created=created and p.pid~=nil end
  check('four_animated_controls',controls==4)
  check('four_native_gauges',gauges==4)
  check('native_prop_meshes_created',#r.props==8 and created)
  check('three_native_mirrors',#r.mirrors==3)
  local liveMirrors=0;for _,m in ipairs(r.mirrors) do if m.id and veh:getMirror(m.id) then liveMirrors=liveMirrors+1 end end
  check('three_native_mirror_cameras',liveMirrors==3)
  local rims=0;for _,m in ipairs(r.ac_meshes) do if m:find('rim_') then rims=rims+1 end end
  check('four_bmw_rim_meshes',rims==4)
  check('unladen_mass_within_three_percent',math.abs(r.mass_kg-1495)/1495<0.03)
  check('power_and_torque_target',math.abs((r.specs.peak_hp or 0)*0.745699872-250)<5 and math.abs((r.specs.peak_nm or 0)-500)<12)
  check('fuel_capacity_target',r.specs.fuel_capacity_l==53)
  -- AC ui_car.json torque curve (Nm, crank): flat 500 to 4000, 406 at 6000 (~255 kW).
  local AC={[2000]=500,[2500]=500,[3000]=500,[3500]=500,[4000]=500,[4500]=480,[5000]=441,[5500]=415,[6000]=406,[6500]=357}
  local worst,at=nil,nil
  for _,p in ipairs(r.specs.curve or {}) do local ref=AC[p[1]]
    if ref then local err=math.abs(p[2]-ref)/ref;if not worst or err>worst then worst,at=err,p[1] end end end
  result.torque_curve={curve=r.specs.curve,name=r.specs.curve_name,worst_error=worst,worst_rpm=at,idle_rpm=r.specs.idle_rpm,max_rpm=r.specs.max_rpm}
  check('torque_curve_matches_ac',worst~=nil and worst<0.05)
  check('verified_first_and_sixth_ratios',r.specs.ratios and math.abs((r.specs.ratios['1'] or r.specs.ratios[1] or 0)-4.11)<0.001 and math.abs((r.specs.ratios['6'] or r.specs.ratios[6] or 0)-0.846)<0.001)
  check('verified_final_drive',math.abs((r.specs.final_drive or 0)-3.154)<0.001)
  -- Optional C005 benchmark. Existing 45 C004 regression checks remain intact.
  if FS:fileExists('/acng-handling-plan.json') then
    extensions.load('acng_handlinglab')
    local function simDelay(s) local finish=simElapsed+s;while simElapsed<finish do coroutine.yield() end end
    result.handling=extensions.acng_handlinglab.run(veh,function() return simElapsed end,simDelay)
    save();vcmd('obj:requestReset(RESET_PHYSICS)');delay(5)
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(4)
  end
  check('lamp_glow_registered',(r.glow or 0)>=5)
  check('ac_engine_sound_loaded',r.sound and tostring(r.sound.engine):find('acng_1m_engine',1,true)~=nil and tostring(r.sound.exhaust):find('acng_1m_exhaust',1,true)~=nil and r.sound.id~=nil)
  check('native_top_speed_limit_configured',r.limiter and math.abs((r.limiter.configured_m_s or 0)*3.6-250)<0.1)
  r=probe('native event sound sources',EVENT_SOUNDS);result.event_sounds=r.event_sounds
  local es=r.event_sounds or {}
  check('native_turbo_samples_loaded',es.turbo and es.turbo.loaded and es.flutter_4 and es.flutter_4.loaded)
  check('native_shift_samples_loaded',es.gearup and es.gearup.loaded and es.geardn and es.geardn.loaded)
  testSpeedLimiter()
  r=probe('fitment',FIT);result.fitment=r.fit
  -- AC tire centres sit at |x| 0.754 (kn5 WHEEL_* pivots); C008 measured 0.770 front, 0.805 rear.
  local centred=r.fit and true or false
  for _,name in ipairs({'FL','FR','RL','RR'}) do local f=r.fit and r.fit[name]
    if not (f and f.n>0 and math.abs(math.abs((f.xmin+f.xmax)/2)-0.754)<0.012) then centred=false end end
  check('tires_centred_on_ac_wheels',centred)
  sampleJitter(3);r=probe('idle_jitter');result.idle_jitter=r.jitter
  -- worst is nil when nothing was measured; never pass on an empty sample.
  check('interior_steady_at_idle',r.jitter and r.jitter.worst and r.jitter.frames>20 and r.jitter.max_mm<2)
  shot('spawn_front',4.2,5.2,1.4)
  shot('spawn_rear',-4.2,-5.2,1.6)
  localShot('wheelwell_FL',{2.7,-2.3,0.5},{1.33,-0.82,0.1})
  localShot('wheelwell_FR',{2.7,2.3,0.5},{1.33,0.82,0.1})
  localShot('wheelwell_RL',{-2.7,-2.3,0.5},{-1.35,-0.82,0.1})
  localShot('wheelwell_RR',{-2.7,2.3,0.5},{-1.35,0.82,0.1})
  localShot('rear_track',{-6,0,0.45},{0,0,0.4})
  localShot('fuel_door_RR',{0.2,1.9,0.9},{-1.4,0.8,0.5})
  -- Brake discs must sit centred in the rims (C010: off-centre discs looked bolted to the wheel).
  localShot('brake_FL',{1.6,-1.75,0.15},{1.33,-0.7,0.08})
  localShot('brake_FR',{1.6,1.75,0.15},{1.33,0.7,0.08})
  localShot('brake_RL',{-1.1,-1.75,0.15},{-1.35,-0.7,0.08})
  localShot('brake_RR',{-1.1,1.75,0.15},{-1.35,0.7,0.08})
  localShot('plate_rear',{-4.0,0.3,0.75},{-2.15,0,0.45})
  -- Realistic gearbox: in arcade mode a held brake at rest selects reverse instead.
  vcmd(STOP..";electrics.setLightsState(1)");delay(2)
  r=probe('lights_on')
  check('lowbeam_and_brake_signals',(r.lights.lowbeam or 0)>0.4 and (r.lights.brakelights or 0)>0.4)
  localShot('lights_front',{5.5,1.8,0.6},{1.8,0,0.35})
  localShot('lights_rear',{-5.5,1.8,0.8},{-2,0,0.5})
  vcmd("electrics.setLightsState(0);input.event('brake',0,1);input.event('clutch',0,1)");delay(2)
  r=probe('controls_neutral');result.wheel_yaw_neutral=r.wheel_yaw
  shot('cockpit_neutral',0.36,0.18,1.14,'wheel')
  shot('pedals_neutral',0.36,0.25,0.60,'pedals')
  localShot('steer_neutral_wheels',{3.6,0,2.6},{1.3,0,0.2})
  shot('gauges_idle',0,0,0,'gauges')
  vcmd(STOP..";input.event('throttle',0.35,1)");delay(3)
  r=probe('gauges_revved')
  local rpm,fuel,oil=0,nil,nil
  for _,p in ipairs(r.props) do if p.func=='rpm' then rpm=p.input elseif p.func=='fuel' then fuel=p.input elseif p.func=='oiltemp' then oil=p.input end end
  check('gauges_receive_native_engine_signals',rpm>2000 and fuel and fuel>0.8 and fuel<=1 and oil and oil>0)
  shot('gauges_revved',0,0,0,'gauges')
  vcmd(STOP);delay(2)
  vcmd("controller.mainController.setGearboxMode('realistic');input.event('steering',0.3,1);input.event('brake',1,1);input.event('clutch',1,1)");delay(2)
  r=probe('controls_applied');check('native_controls_received',math.abs(r.controls.steering or 0)>1 and (r.controls.brake or 0)>0.9)
  result.wheel_yaw_applied=r.wheel_yaw;result.steering_applied=r.controls.steering
  -- Input +0.3 steers right: the left front axle turns clockwise seen from above (yaw falls).
  local y0,y1=result.wheel_yaw_neutral and result.wheel_yaw_neutral.FL,r.wheel_yaw and r.wheel_yaw.FL
  check('front_wheels_steer_right',y0~=nil and y1~=nil and y1<y0-3)
  shot('cockpit_controls',0.36,0.18,1.14,'wheel')
  localShot('steer_applied_wheels',{3.6,0,2.6},{1.3,0,0.2})
  shot('pedals_applied',0.36,0.25,0.60,'pedals')
  vcmd("controller.mainController.shiftToGearIndex(1)");delay(2)
  local first=probe('shifter_first')
  vcmd("controller.mainController.shiftToGearIndex(2)");delay(2)
  local second=probe('shifter_second')
  check('native_shifter_moves',first.shifter_position and second.shifter_position and vec3(unpack(first.shifter_position)):distance(vec3(unpack(second.shifter_position)))>0.005)
  vcmd("input.event('steering',0,1);input.event('brake',0,1);input.event('clutch',0,1)")
  -- ACNG on this car: master, Road tires, wear, ABS and TC.
  extensions.acng_core.setEnabled(true)
  for _,f in ipairs({'tire_temperature','tire_wear','abs','tc'}) do extensions.acng_core.setFeature(f,true) end
  delay(3)
  check('core_attaches_tires',status().tires_vehicle_id==veh:getID())
  r=probe('acng_on')
  check('tires_auto_compound',r.tires and r.profile=='auto' and (r.compound=='road' or r.compound=='sport' or r.compound=='race'))
  result.auto_compound=r.compound
  check('all_tires_tracked',r.native_tires>0 and r.acng_tires==r.native_tires)
  vcmd(DRIVE..";input.event('throttle',1,1)")
  delay(3);r=probe('gauges_driving');local speed=0
  for _,p in ipairs(r.props) do if p.func=='wheelspeed' then speed=p.input end end
  check('speed_gauge_receives_native_motion',speed>3)
  shot('gauges_driving',0,0,0,'gauges')
  result.drive_peak_m_s=peakDuring(7,true)
  r=probe('drive_jitter');result.drive_jitter=r.jitter
  check('interior_steady_while_driving',r.jitter and r.jitter.worst and r.jitter.frames>50 and r.jitter.max_mm<4)
  vcmd("input.event('throttle',0,1); input.event('brake',1,1)");delay(5)
  r=probe('driven')
  check('drive_moved',result.drive_peak_m_s>8)
  check('drive_tires_finite',r.tires and r.finite)
  check('drive_no_self_damage',(r.damage or 0)<200)
  -- Crash into a parked stock pickup.
  vcmd(STOP);delay(1)
  spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(3)
  local obstacle=core_vehicles.spawnNewVehicle('pickup',{autoEnterVehicle=false,pos=vec3(0,45,1),rot=quat(0,0,1,0)})
  check('obstacle_spawned',obstacle~=nil)
  if obstacle then
    delay(2);spawn.safeTeleport(obstacle,vec3(0,45,1),quat(0,0,1,0))
    obstacle:queueLuaCommand("controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('brake',1,1); input.event('parkingbrake',1,1); input.event('throttle',0,1)")
    delay(6)
  end
  local before=probe('pre_crash')
  vcmd(DRIVE..";input.event('throttle',1,1)")
  result.crash_peak_m_s=peakDuring(9)
  vcmd(STOP);delay(4)
  r=probe('post_crash')
  check('crash_native_damage',(r.damage or 0)>(before.damage or 0)+1000)
  check('crash_tires_still_running',r.tires and r.finite)
  shot('crash_front',3.5,-4.0,1.5)
  localShot('crash_side_FL',{1.2,-3.2,0.9},{1.0,-0.8,0.5})
  if obstacle then obstacle:delete();obstacle=nil end
  -- Second, offset hit on the left front corner to knock a headlight loose (stretch check).
  vcmd('obj:requestReset(RESET_PHYSICS)');delay(5)
  spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(3)
  obstacle=core_vehicles.spawnNewVehicle('pickup',{autoEnterVehicle=false,pos=vec3(-1.1,40,1),rot=quat(0,0,1,0)})
  if obstacle then delay(2);spawn.safeTeleport(obstacle,vec3(-1.1,40,1),quat(0,0,1,0))
    obstacle:queueLuaCommand("controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('brake',1,1); input.event('parkingbrake',1,1)");delay(5) end
  vcmd(DRIVE..";input.event('throttle',1,1)");result.crash2_peak_m_s=peakDuring(8)
  vcmd(STOP);delay(4)
  if obstacle then obstacle:delete();obstacle=nil end
  delay(2);r=probe('post_crash_offset')
  localShot('crash2_front',{4.5,0,1.2},{0,0,0.5})
  localShot('crash2_FL',{2.5,-3.5,1.3},{1.4,-0.6,0.5})
  localShot('crash2_FR',{2.5,3.5,1.3},{1.4,0.6,0.5})
  localShot('crash2_top',{1.5,0.01,6},{1.4,0,0.4})
  isolationShots()
  check('crash_isolation_groups_found',result.isolated and result.isolated.bumper_F>0 and result.isolated.lights_F>0 and result.isolated.body>0)
  if obstacle then obstacle:delete();obstacle=nil end
  -- Native puncture and a detached wheel, then drive the wreck.
  probe('puncture',[[for _,w in pairs(wheels.wheels) do if w.name=='FL' then beamstate.deflateTire(w.cid);break end end]])
  delay(2)
  probe('break',[[beamstate.breakBreakGroup('wheel_RL')]])
  delay(3)
  r=probe('damaged')
  local flags={deflated=anyDeflated(r),broken=anyBroken(r)};result.damaged_flags=flags
  check('native_puncture_or_break_present',flags.deflated or flags.broken)
  check('damaged_tires_still_running',r.tires and r.finite)
  vcmd(DRIVE..";input.event('throttle',0.5,1)");result.wreck_peak_m_s=peakDuring(4)
  vcmd(STOP);delay(3)
  r=probe('wreck_driven')
  local wreckDamage=r.damage
  extensions.acng_core.setEnabled(false);delay(3)
  r=probe('master_off')
  check('off_unloads',not r.tires and status().physics_writes==0)
  check('off_keeps_damage',(r.damage or 0)>=(wreckDamage or 0)-1 and (anyDeflated(r) or not flags.deflated) and (anyBroken(r) or not flags.broken))
  extensions.acng_core.setEnabled(true);delay(4)
  r=probe('master_on_wrecked')
  check('on_reattaches_to_wreck',r.tires and r.finite)
  vcmd("obj:requestReset(RESET_PHYSICS)");delay(5)
  r=probe('reset')
  check('reset_repairs_native',not anyBroken(r) and not anyDeflated(r) and (r.damage or 0)<50)
  check('reset_fresh_tread',r.tires and r.finite and r.tread_min==1)
  check('reset_keeps_ac_meshes',r.ac_meshes_n>=11)
  extensions.acng_core.setEnabled(false);delay(2)
  check('final_off',status().physics_writes==0)
  result.completed=true;stage='done';save();log('I','ACNG_C001','C001 complete')
end
M.receive=function(encoded) response=jsonDecode(encoded) end
M.onUpdate=function(dtReal,dtSim)
  elapsed=elapsed+dtReal
  simElapsed=simElapsed+(dtSim or 0)
  if not co then co=coroutine.create(run) end
  if coroutine.status(co)=='dead' then return end
  local ok,err=coroutine.resume(co)
  if not ok then result.error=tostring(err);save();log('E','ACNG_C001',tostring(err)) end
end
return M
