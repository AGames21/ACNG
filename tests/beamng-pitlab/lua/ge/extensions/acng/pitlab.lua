-- P001 isolated native pit-service regression. Never deploy this helper to a player profile.
local M={}
local elapsed,co,response=0,nil,nil
local result={test='P001 native pit service',completed=false,checks={}}
local function save() jsonWriteFile('/acng-pit-test.json',result,true) end
local function check(name,ok) result.checks[name]=ok==true;save();if not ok then error(name) end end
local stage='start'
local function waitFor(fn,timeout)
  local start=elapsed
  while not fn() do if elapsed-start>(timeout or 12) then error('Native wait timeout at '..stage) end;coroutine.yield() end
end
local function delay(seconds) local stop=elapsed+seconds;while elapsed<stop do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local function command(code)
  stage='vehicle command';local veh=be:getPlayerVehicle(0);assert(veh);response=nil
  -- newline, not ';': LuaJIT rejects a chunk that starts with an empty statement.
  veh:queueLuaCommand(code..'\n'..[[local r={pit=extensions.isExtensionLoaded('acng_pits'),tires=extensions.isExtensionLoaded('acng_tires'),fuel={},wheels={}}
    if r.pit then r.service=extensions.acng_pits.getSnapshot() end
    if r.tires then r.tire_state=extensions.acng_tires.getSnapshot() end
    for name,s in pairs(energyStorage.getStorages()) do if s.type=='fuelTank' then r.fuel[name]={liters=s.storedEnergy/(s.fuelLiquidDensity*s.energyDensity),capacity=s.capacity,leak=s.currentLeakRate} end end
    for _,w in pairs(wheels.wheels) do r.wheels[w.name]={broken=w.isBroken==true,deflated=w.isTireDeflated==true} end
    obj:queueGameEngineLua(string.format('extensions.acng_pitlab.receive(%q)',jsonEncode(r)))]])
  waitFor(function() return response~=nil end)
  return response
end
result.clicks={}
local function click(label)
  stage='click '..label;delay(0.8)
  be:queueJS('(function(){var e=document.querySelector('..jsonEncode('.acng-control [aria-label="'..label..'"]')..');if(e)e.click();bngApi.engineLua("extensions.acng_pitlab.clicked("+JSON.stringify('..jsonEncode(label)..')+","+(e?(e.disabled?"\\"disabled\\"":"true"):"false")+")");})()');delay(1)
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  assert(FS:getUserPath():gsub('\\','/'):lower():match('/acng%-pit%-[%w%-]+/current/?$'),'Fresh isolated pit profile required')
  freeroam_freeroam.startFreeroam('/levels/smallgrid/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,150)
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});delay(8)
  check('startup_off',not status().enabled)
  extensions.load('ui_appLayouts')
  local layout=ui_appLayouts.createLayout({title='ACNG Pit Test',type='freeroam',apps={{appName='acngControl',placement={right='24px',top='70px',width='380px',height='600px'}}}})
  ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'});delay(5)
  click('Toggle ACNG master');waitFor(function() return status().enabled end)
  click('Show advanced ACNG settings');click('ACNG pits tab');click('ACNG pit services')
  waitFor(function() return status().features.pits end)
  delay(1);check('real_ui_enables_native_service',command('').pit)
  click('ACNG pit fresh tread')
  command([[for _,s in pairs(energyStorage.getStorages()) do if s.type=='fuelTank' then s:setRemainingVolume(5) end end
    input.event('parkingbrake',1,1)
    for _,w in pairs(wheels.wheels) do w.slipEnergy=1e6 end
    extensions.acng_tires.updateGFX(1)
    for _,w in pairs(wheels.wheels) do w.slipEnergy=0 end]])
  delay(2)
  click('ACNG pits tab')
  -- Mark/start through the same bridge used by the panel; native outcome is acknowledged.
  click('ACNG mark pit box')
  local before=command('');check('native_box_contains_stopped_vehicle',before.service.in_box and before.service.stopped)
  result.before=before
  click('ACNG start pit service')
  check('native_countdown_active',command('').service.servicing)
  delay(21)
  local after=command('');result.after=after
  check('native_service_finished',not after.service.servicing and after.service.message:find('complete')~=nil)
  local filled=true;local found=false
  for _,s in pairs(after.fuel) do found=true;if math.abs(s.liters-s.capacity)>0.1 then filled=false end end
  check('native_fuel_storage_filled',found and filled)
  local fresh=true
  for _,w in ipairs(after.tire_state.tires) do if w.tread~=1 then fresh=false end end
  check('native_tread_fresh',fresh)
  -- Damage is genuinely applied by BeamNG's native puncture API in this sacrificial profile.
  local damaged=command([[for _,w in pairs(wheels.wheels) do if w.name=='FL' then beamstate.deflateTire(w.cid) end end]])
  delay(1);damaged=command('');check('native_puncture_created',damaged.wheels.FL.deflated)
  extensions.acng_core.pitCommand('service',false,true);delay(1)
  local refused=command('');result.damaged=refused
  check('native_puncture_service_refused',not refused.service.servicing and refused.service.message:find('refused')~=nil)
  check('native_puncture_stays_damaged',refused.wheels.FL.deflated)
  extensions.acng_core.pitCommand('service',true,false);delay(1)
  check('fuel_only_service_active',command('').service.servicing)
  extensions.acng_core.setControlEnabled(false);delay(2)
  local off=command('');result.off=off
  check('master_off_unloads_service_and_tires',not off.pit and not off.tires)
  check('master_off_keeps_puncture',off.wheels.FL.deflated)
  result.completed=true;save();log('I','ACNGPitLab','P001 complete')
end
M.receive=function(encoded) response=jsonDecode(encoded) end
M.clicked=function(label,state) result.clicks[#result.clicks+1]=label..'='..tostring(state);save() end
M.onUpdate=function(dtReal)
  elapsed=elapsed+dtReal
  if not co then co=coroutine.create(run) end
  if coroutine.status(co)=='dead' then return end
  local ok,err=coroutine.resume(co)
  if not ok then result.error=tostring(err);save();log('E','ACNGPitLab',tostring(err)) end
end
return M
