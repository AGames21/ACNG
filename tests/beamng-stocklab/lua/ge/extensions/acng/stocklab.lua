-- FR002b isolated stock-vehicle damage coverage; never deploy this helper to a player profile.
-- For each stock model, with master ON and Road tires, wear, ABS and TC all ON:
-- spawn, drive and brake hard, crash into a parked stock pickup at speed, then natively
-- puncture a front tire and break a wheel off, drive the wrecked car, switch master OFF
-- (damage must stay) and ON again, and reset (native repair, fresh tread).
-- Every check reads the vehicle VM: ACNG tire state, native damage and wheel flags.
local M={}
local elapsed,co,response=0,nil,nil
local MODELS={'covet','barstow','sunburst2','pigeon','van','us_semi'}
local result={test='FR002b stock vehicle damage coverage',completed=false,checks={},vehicles={}}
local stage='start'
local function save() jsonWriteFile('/acng-stocklab-test.json',result,true) end
local cur
-- Record a check without stopping the run, so one vehicle's failure does not hide the rest.
local function check(name,ok)
  local key=(cur and cur.model..'.' or '')..name
  result.checks[key]=ok==true;save()
  if not ok then log('W','ACNG_FR002b','FAIL '..key) end
  return ok==true
end
local function waitFor(fn,timeout)
  local start=elapsed
  while not fn() do if elapsed-start>(timeout or 12) then error('Native wait timeout at '..stage) end;coroutine.yield() end
end
local function delay(seconds) local stop=elapsed+seconds;while elapsed<stop do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local PROBE=[[
local r={tires=extensions.isExtensionLoaded('acng_tires'),assists=extensions.isExtensionLoaded('acng_assists'),
  damage=beamstate.damage,wheels={},native_tires=0,finite=true,tread_min=nil,grip_min=nil}
local wd=v.data.wheels
if wd then for i=0,tableSizeC(wd)-1 do local w=wd[i];if w and (w.hasTire or w.hasTire==nil) then r.native_tires=r.native_tires+1 end end end
for _,w in pairs(wheels.wheels or {}) do r.wheels[#r.wheels+1]={name=w.name,broken=w.isBroken==true,deflated=w.isTireDeflated==true} end
if r.tires then
  local s=extensions.acng_tires.getSnapshot();r.profile=s.profile;r.acng_tires=#s.tires;r.temps={}
  for _,t in ipairs(s.tires) do
    if t.surface_c==nil or t.grip==nil then r.finite=false end
    if t.tread then r.tread_min=math.min(r.tread_min or 1,t.tread) end
    if t.grip then r.grip_min=math.min(r.grip_min or 9,t.grip) end
    r.temps[t.name]=t.surface_c
  end
end
obj:queueGameEngineLua(string.format('extensions.acng_stocklab.receive(%q)',jsonEncode(r)))]]
local function probe(label,code)
  stage=cur.model..' '..label;local veh=be:getPlayerVehicle(0);assert(veh);response=nil
  -- newline, not ';': LuaJIT rejects a chunk that starts with an empty statement.
  veh:queueLuaCommand((code or '')..'\n'..PROBE)
  waitFor(function() return response~=nil end)
  response.label=label;cur.probes[#cur.probes+1]=response;save()
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
local function runVehicle(model)
  cur={model=model,probes={}};result.vehicles[#result.vehicles+1]=cur
  stage=model..' spawn'
  core_vehicles.replaceVehicle(model,{})
  waitFor(function() local v=be:getPlayerVehicle(0);return v and v:getJBeamFilename()==model end,60)
  delay(8)
  local veh=be:getPlayerVehicle(0)
  spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(4)
  local st=status()
  check('core_attaches_tires',st.tires_vehicle_id==veh:getID())
  local r=probe('spawn')
  check('spawn_tires_road',r.tires and r.assists and r.profile=='road')
  check('spawn_all_tires_tracked',r.native_tires>0 and r.acng_tires==r.native_tires)
  check('spawn_finite',r.finite and r.tread_min==1)
  -- Full throttle then a hard stop with ABS and TC on.
  vcmd(DRIVE..";input.event('throttle',1,1)")
  cur.drive_peak_m_s=peakDuring(7)
  vcmd("input.event('throttle',0,1); input.event('brake',1,1)");delay(5)
  r=probe('driven')
  check('drive_moved',cur.drive_peak_m_s>5)
  check('drive_tires_finite',r.tires and r.finite and r.acng_tires==r.native_tires)
  -- Crash into a parked stock pickup at speed.
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
  cur.crash_peak_m_s=peakDuring(9)
  vcmd(STOP);delay(4)
  r=probe('post_crash')
  check('crash_native_damage',(r.damage or 0)>(before.damage or 0)+1000)
  check('crash_tires_still_running',r.tires and r.finite)
  if obstacle then obstacle:delete();obstacle=nil end
  -- Native puncture and a detached wheel on the wrecked car, then drive on it.
  probe('puncture',[[for _,w in pairs(wheels.wheels) do if w.name=='FL' or w.name=='F' then beamstate.deflateTire(w.cid);break end end]])
  delay(2)
  local groups={}
  for _,w in pairs({'wheel_FL','wheel_FR','wheel_F','wheel_RL'}) do groups[#groups+1]=string.format('%q',w) end
  probe('break',[[local want={]]..table.concat(groups,',')..[[}
    local have={}
    for _,b in pairs(v.data.beams or {}) do
      local g=b.breakGroup
      if type(g)=='string' then have[g]=true elseif type(g)=='table' then for _,x in pairs(g) do have[x]=true end end
    end
    for _,g in ipairs(want) do if have[g] then beamstate.breakBreakGroup(g);break end end]])
  delay(3)
  r=probe('damaged')
  cur.damaged_flags={deflated=anyDeflated(r),broken=anyBroken(r)}
  check('native_puncture_or_break_present',anyDeflated(r) or anyBroken(r))
  check('damaged_tires_still_running',r.tires and r.finite)
  vcmd(DRIVE..";input.event('throttle',0.5,1)");cur.wreck_peak_m_s=peakDuring(4)
  vcmd(STOP);delay(3)
  r=probe('wreck_driven')
  check('wreck_drive_tires_finite',r.tires and r.finite)
  local wreckDamage=r.damage
  -- Master OFF must unload ACNG and leave every native damage state alone.
  extensions.acng_core.setEnabled(false);delay(3)
  r=probe('master_off')
  check('off_unloads',not r.tires and not r.assists and status().physics_writes==0)
  check('off_keeps_damage',(r.damage or 0)>=(wreckDamage or 0)-1 and (anyDeflated(r) or not cur.damaged_flags.deflated) and (anyBroken(r) or not cur.damaged_flags.broken))
  extensions.acng_core.setEnabled(true);delay(4)
  r=probe('master_on_wrecked')
  check('on_reattaches_to_wreck',r.tires and r.assists and r.finite)
  -- Native reset repairs; ACNG gives fresh tread.
  vcmd("obj:requestReset(RESET_PHYSICS)");delay(5)
  r=probe('reset')
  check('reset_repairs_native',not anyBroken(r) and not anyDeflated(r))
  check('reset_fresh_tread',r.tires and r.finite and r.tread_min==1 and r.acng_tires==r.native_tires)
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  assert(FS:getUserPath():gsub('\\','/'):lower():match('/acng%-stock%-[%w%-]+/current/?$'),'Fresh isolated stock profile required')
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,150)
  delay(6)
  result.checks.startup_off=not status().enabled
  extensions.acng_core.setEnabled(true)
  for _,f in ipairs({'tire_temperature','tire_wear','abs','tc'}) do extensions.acng_core.setFeature(f,true) end
  delay(3)
  for _,model in ipairs(MODELS) do
    local ok,err=pcall(runVehicle,model)
    if not ok then cur.error=tostring(err);result.checks[model..'.completed']=false;save()
      -- Leave the next vehicle a working master.
      extensions.acng_core.setEnabled(true)
    else result.checks[model..'.completed']=true end
    -- A failed vehicle may leave the obstacle behind; clear anything that is not the player.
    pcall(function()
      for i=be:getObjectCount()-1,0,-1 do
        local o=be:getObject(i)
        if o and o~=be:getPlayerVehicle(0) and o:getJBeamFilename()=='pickup' then o:delete() end
      end
    end)
    delay(2)
  end
  extensions.acng_core.setEnabled(false);delay(2)
  result.checks.final_off=status().physics_writes==0
  result.completed=true;save();log('I','ACNG_FR002b','FR002b complete')
end
M.receive=function(encoded) response=jsonDecode(encoded) end
M.onUpdate=function(dtReal)
  elapsed=elapsed+dtReal
  if not co then co=coroutine.create(run) end
  if coroutine.status(co)=='dead' then return end
  local ok,err=coroutine.resume(co)
  if not ok then result.error=tostring(err);save();log('E','ACNG_FR002b',tostring(err)) end
end
return M
