-- C001 isolated check of the user's local AC-converted car (acng_bmw1m); never deploy to a player profile.
-- The car zip is built locally by converters/build_ac_car.py and placed in this lab profile only by
-- scripts/launch-lab.ps1 -ExtraMod; it is never copied into the repo or ACNG packages.
-- Spawn on smallgrid, confirm the AC meshes replaced the ETK skin, then the FR002b damage path:
-- drive and brake, crash into a parked pickup, puncture and break a wheel, master OFF/ON, reset.
local M={}
local elapsed,co,response=0,nil,nil
local MODEL='acng_bmw1m'
local result={test='C002 1M rig and specifications',completed=false,checks={},probes={},shots={}}
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
if e then local ok,d=pcall(function() return e:getTorqueData() end);if ok then r.specs.peak_hp=d.maxPower;r.specs.peak_nm=d.maxTorque end end
if gb then r.specs.ratios=gb.gearRatios end;if diff then r.specs.final_drive=diff.gearRatio end
local tank=energyStorage.getStorage('mainTank');if tank then r.specs.fuel_capacity_l=tank.capacity;r.specs.fuel_l=tank.remainingVolume end
for _,p in pairs(v.data.props or {}) do if tostring(p.mesh):find('^acng_bmw1m_') then r.props[#r.props+1]={mesh=p.mesh,func=p.func,pid=p.pid,input=electrics.values[p.func] or 0} end end
for id,n in pairs(v.data.nodes or {}) do if n.name=='sh_l3' then local p=obj:getNodePosition(n.cid or id);r.shifter_position={p.x,p.y,p.z} end end
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
local function vcmd(code) be:getPlayerVehicle(0):queueLuaCommand(code) end
local function anyBroken(r) for _,w in ipairs(r.wheels) do if w.broken then return true end end return false end
local function anyDeflated(r) for _,w in ipairs(r.wheels) do if w.deflated then return true end end return false end
local DRIVE="controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,1)"
local STOP="controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('brake',1,1)"
local function peakDuring(seconds)
  local stop,peak=elapsed+seconds,0
  while elapsed<stop do peak=math.max(peak,be:getPlayerVehicle(0):getVelocity():length());coroutine.yield() end
  return peak
end
-- Free camera looking at the car from (dx,dy,dz) metres away; then an in-engine screenshot.
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
    end
    local q=quatFromDir(dir,vec3(0,0,1))
    core_camera.setPosRot(0,eye.x,eye.y,eye.z,q.x,q.y,q.z,q.w)
    if cockpit=='wheel' then commands.setGameCamera();core_camera.setByName(0,'driver',false) end
  end)
  delay(3)
  local file='screenshots/acng_c001_'..name
  local id=type(createScreenshot2)=='function' and createScreenshot2({filename=file,writeJPG=true,superSampling=1}) or 0
  result.shots[#result.shots+1]={name=name,camera=ok,file=file..'.jpg',id=id};save()
  delay(4)
  pcall(function() commands.setGameCamera() end)
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  assert(FS:getUserPath():gsub('\\','/'):lower():match('/acng%-car%-[%w%-]+/current/?$'),'Fresh isolated car profile required')
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,150)
  delay(6)
  check('startup_off',not status().enabled)
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
  check('four_animated_controls',#r.props==4)
  check('native_prop_meshes_created',#r.props==4 and r.props[1].pid~=nil and r.props[2].pid~=nil and r.props[3].pid~=nil and r.props[4].pid~=nil)
  check('unladen_mass_within_three_percent',math.abs(r.mass_kg-1495)/1495<0.03)
  check('power_and_torque_target',math.abs((r.specs.peak_hp or 0)*0.745699872-250)<5 and math.abs((r.specs.peak_nm or 0)-500)<12)
  check('fuel_capacity_target',r.specs.fuel_capacity_l==53)
  check('verified_first_and_sixth_ratios',r.specs.ratios and math.abs((r.specs.ratios['1'] or r.specs.ratios[1] or 0)-4.11)<0.001 and math.abs((r.specs.ratios['6'] or r.specs.ratios[6] or 0)-0.846)<0.001)
  check('verified_final_drive',math.abs((r.specs.final_drive or 0)-3.154)<0.001)
  shot('spawn_front',4.2,5.2,1.4)
  shot('spawn_rear',-4.2,-5.2,1.6)
  shot('cockpit_neutral',0.36,0.18,1.14,'wheel')
  vcmd("controller.mainController.setGearboxMode('realistic');input.event('steering',0.3,1);input.event('brake',1,1);input.event('clutch',1,1)");delay(2)
  r=probe('controls_applied');check('native_controls_received',math.abs(r.controls.steering or 0)>1 and (r.controls.brake or 0)>0.9)
  shot('cockpit_controls',0.36,0.18,1.14,'wheel')
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
  check('tires_road',r.tires and r.profile=='road')
  check('all_tires_tracked',r.native_tires>0 and r.acng_tires==r.native_tires)
  vcmd(DRIVE..";input.event('throttle',1,1)")
  result.drive_peak_m_s=peakDuring(7)
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
M.onUpdate=function(dtReal)
  elapsed=elapsed+dtReal
  if not co then co=coroutine.create(run) end
  if coroutine.status(co)=='dead' then return end
  local ok,err=coroutine.resume(co)
  if not ok then result.error=tostring(err);save();log('E','ACNG_C001',tostring(err)) end
end
return M
