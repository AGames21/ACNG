-- P002 isolated Spa pit-lane check. Never deploy this helper to a player profile.
-- Needs the user's own Spa download placed in the lab profile's mods folder by
-- scripts/launch-lab.ps1 -ExtraMod; the map is never copied into the repo or packages.
-- Loads Spa at its "Pit Start" spawn, puts the stock ETK there, drives a short way down
-- the pit lane on Road tires, then runs P001's pit service through the real panel buttons.
local M={}
local elapsed,co,response=0,nil,nil
local result={test='P002 Spa pit lane',completed=false,checks={},clicks={}}
local function save() jsonWriteFile('/acng-spa-test.json',result,true) end
local stage='start'
local function check(name,ok) result.checks[name]=ok==true;save();if not ok then error(name) end end
local function waitFor(fn,timeout)
  local start=elapsed
  while not fn() do if elapsed-start>(timeout or 12) then error('Native wait timeout at '..stage) end;coroutine.yield() end
end
local function delay(seconds) local stop=elapsed+seconds;while elapsed<stop do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local function command(code)
  stage='vehicle command';local veh=be:getPlayerVehicle(0);assert(veh);response=nil
  -- newline, not ';': LuaJIT rejects a chunk that starts with an empty statement.
  veh:queueLuaCommand(code..'\n'..[[local r={pit=extensions.isExtensionLoaded('acng_pits'),tires=extensions.isExtensionLoaded('acng_tires'),fuel={},wheels={},damage=beamstate.damage}
    if r.pit then r.service=extensions.acng_pits.getSnapshot() end
    if r.tires then r.tire_state=extensions.acng_tires.getSnapshot() end
    for name,s in pairs(energyStorage.getStorages()) do if s.type=='fuelTank' then r.fuel[name]={liters=s.storedEnergy/(s.fuelLiquidDensity*s.energyDensity),capacity=s.capacity,leak=s.currentLeakRate} end end
    for _,w in pairs(wheels.wheels) do r.wheels[w.name]={broken=w.isBroken==true,deflated=w.isTireDeflated==true} end
    obj:queueGameEngineLua(string.format('extensions.acng_spalab.receive(%q)',jsonEncode(r)))]])
  waitFor(function() return response~=nil end)
  return response
end
local function click(label)
  stage='click '..label;delay(0.8)
  be:queueJS('(function(){var e=document.querySelector('..jsonEncode('.acng-control [aria-label="'..label..'"]')..');if(e)e.click();bngApi.engineLua("extensions.acng_spalab.clicked("+JSON.stringify('..jsonEncode(label)..')+","+(e?(e.disabled?"\\"disabled\\"":"true"):"false")+")");})()');delay(1)
end
local function pos() local p=be:getPlayerVehicle(0):getPosition();return {x=p.x,y=p.y,z=p.z} end
local function finite(tires)
  if not tires or #tires==0 then return false end
  for _,t in ipairs(tires) do if t.surface_c==nil or t.grip==nil or t.surface_c~=t.surface_c then return false end end
  return true
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  assert(FS:getUserPath():gsub('\\','/'):lower():match('/acng%-spa%-[%w%-]+/current/?$'),'Fresh isolated Spa profile required')
  stage='find level'
  local names={}
  for _,l in ipairs(core_levels.getList()) do if tostring(l.levelName):lower():find('spa') then names[#names+1]=l.levelName end end
  result.spa_levels=names;save()
  check('spa_level_found',#names>0)
  result.level=names[1]
  check('spa_start_requested',freeroam_freeroam.startFreeroamByName(names[1],'SpawnSphere_Pit'))
  stage='load spa'
  local t0=elapsed
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,400)
  result.load_s=elapsed-t0
  check('spa_loaded',getMissionFilename():lower():find('spa')~=nil)
  result.mission=getMissionFilename()
  local sp=scenetree.findObject('SpawnSphere_Pit')
  check('pit_spawn_present',sp~=nil)
  local spp=sp:getPosition();result.pit_spawn={x=spp.x,y=spp.y,z=spp.z}
  stage='spawn etkc'
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'})
  waitFor(function() local v=be:getPlayerVehicle(0);return v and v:getJBeamFilename()=='etkc' end,60)
  delay(10)
  local p=pos();result.spawn_pos=p
  check('car_at_pit_spawn',math.sqrt((p.x-spp.x)^2+(p.y-spp.y)^2)<15)
  check('car_resting_on_ground',math.abs(p.z-spp.z)<5 and be:getPlayerVehicle(0):getVelocity():length()<0.5)
  check('startup_off',not status().enabled)
  -- Same real panel path as P001.
  extensions.load('ui_appLayouts')
  local layout=ui_appLayouts.createLayout({title='ACNG Spa Test',type='freeroam',apps={{appName='acngControl',placement={right='24px',top='70px',width='380px',height='600px'}}}})
  ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'});delay(5)
  click('Toggle ACNG master');waitFor(function() return status().enabled end)
  extensions.acng_core.setFeature('tire_temperature',true);delay(2)
  local r=command('');check('road_tires_on_spa',r.tires and r.tire_state.profile=='road' and finite(r.tire_state.tires))
  -- Short straight creep on Spa's pit-lane surface: about 9 km/h for 5 s, then stop.
  -- Observed in P002 attempts: driving straight from the pit spawn hits a wall after about
  -- 18 m (the lane curves), and the level's AI road graph has no road within 8 m of the
  -- spawn, so no automatic lane following is attempted. The full lane is a user playtest.
  stage='pit lane creep'
  local veh=be:getPlayerVehicle(0)
  local damageBefore=r.damage or 0
  veh:queueLuaCommand("controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,1)")
  local stop,peak,frames,realStart=elapsed+5,0,0,elapsed
  local ctl=0
  while elapsed<stop do
    local s=veh:getVelocity():length();peak=math.max(peak,s);frames=frames+1
    ctl=ctl+1
    if ctl%6==0 then veh:queueLuaCommand(string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(0.35,0.12*(2.5-s))))) end
    coroutine.yield()
  end
  result.roll={peak_m_s=peak,fps=frames/math.max(0.001,elapsed-realStart),start=p,finish=pos(),damage_before=damageBefore}
  veh:queueLuaCommand("controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('brake',1,1)")
  delay(5)
  local f=result.roll.finish;result.roll.distance_m=math.sqrt((f.x-p.x)^2+(f.y-p.y)^2)
  r=command('');result.after_roll=r
  check('pit_lane_creep_moved',result.roll.distance_m>3 and result.roll.distance_m<15)
  check('pit_lane_creep_no_crash',(r.damage or 0)-damageBefore<500)
  check('pit_lane_tires_finite',r.tires and finite(r.tire_state.tires))
  -- Pit service in the real Spa pit lane.
  click('Show advanced ACNG settings');click('ACNG pits tab');click('ACNG pit services')
  waitFor(function() return status().features.pits end)
  delay(1);check('panel_enables_pit_service',command('').pit)
  click('ACNG pit fresh tread')
  command([[for _,s in pairs(energyStorage.getStorages()) do if s.type=='fuelTank' then s:setRemainingVolume(5) end end
    input.event('parkingbrake',1,1)
    for _,w in pairs(wheels.wheels) do w.slipEnergy=1e6 end
    extensions.acng_tires.updateGFX(1)
    for _,w in pairs(wheels.wheels) do w.slipEnergy=0 end]])
  delay(2)
  click('ACNG pits tab')
  click('ACNG mark pit box')
  local before=command('');result.before=before
  check('box_marked_in_spa_pit_lane',before.service.in_box and before.service.stopped)
  click('ACNG start pit service')
  check('service_countdown',command('').service.servicing)
  delay(21)
  local after=command('');result.after=after
  check('service_finished',not after.service.servicing and after.service.message:find('complete')~=nil)
  local filled,found=true,false
  for _,s in pairs(after.fuel) do found=true;if math.abs(s.liters-s.capacity)>0.1 then filled=false end end
  check('fuel_filled',found and filled)
  local fresh=true
  for _,w in ipairs(after.tire_state.tires) do if w.tread~=1 then fresh=false end end
  check('tread_fresh',fresh)
  extensions.acng_core.setControlEnabled(false);delay(2)
  local off=command('');result.off=off
  check('master_off_unloads',not off.pit and not off.tires and status().physics_writes==0)
  result.completed=true;save();log('I','ACNGSpaLab','P002 complete')
  -- Park the camera on the car for an outside screenshot.
  delay(2);result.final_pos=pos();save()
end
M.receive=function(encoded) response=jsonDecode(encoded) end
M.clicked=function(label,state) result.clicks[#result.clicks+1]=label..'='..tostring(state);save() end
M.onUpdate=function(dtReal)
  elapsed=elapsed+dtReal
  if not co then co=coroutine.create(run) end
  if coroutine.status(co)=='dead' then return end
  local ok,err=coroutine.resume(co)
  if not ok then result.error=tostring(err);save();log('E','ACNGSpaLab',tostring(err)) end
end
return M
