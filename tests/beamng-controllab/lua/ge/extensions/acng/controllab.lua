-- Stationary control/UI test, no AI spawning or driving inputs.
local M={};local real,sim,co=0,0,nil;local response
local result={test='GUI001 freeroam control panel',completed=false,checks={}}
local function save() jsonWriteFile('/acng-control-test.json',result,true) end
local function check(k,x) result.checks[k]=x==true;save();if not x then error(k) end end
local function waitFor(f,t) local start=real;while not f() do if real-start>(t or 12) then error('wait timeout') end;coroutine.yield() end end
local function delay(t) local untilTime=real+t;while real<untilTime do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local function click(label)
  delay(0.8)
  be:queueJS('(function(){var e=document.querySelector('..jsonEncode('.acng-control [aria-label="'..label..'"]')..');if(e)e.click();})()')
end
local function change(label,value)
  delay(0.8)
  be:queueJS('(function(){var e=document.querySelector('..jsonEncode('.acng-control [aria-label="'..label..'"]')..');if(e){e.value='..jsonEncode(tostring(value))..';e.dispatchEvent(new Event("input",{bubbles:true}));e.dispatchEvent(new Event("change",{bubbles:true}));}})()')
end
local function probe()
  local v=be:getPlayerVehicle(0)
  if v then v:queueLuaCommand([[local s={tires=extensions.isExtensionLoaded('acng_tires'),ffb=extensions.isExtensionLoaded('acng_ffb'),assists=extensions.isExtensionLoaded('acng_assists'),telemetry=false};if extensions.isExtensionLoaded('acng_telemetry') then s.telemetry=extensions.acng_telemetry.getStatus().active end;if s.tires then s.state=extensions.acng_tires.getSnapshot() end;obj:queueGameEngineLua(string.format('extensions.acng_controllab.receive(%q)',jsonEncode(s)))]]) end
  return response
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  if not FS:getUserPath():gsub('\\','/'):lower():match('/acng%-control%-[%w%-]+/current/?$') then error('Isolated profile required') end
  freeroam_freeroam.startFreeroam('/levels/west_coast_usa/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,150)
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});delay(8)
  check('startup_off',not status().enabled)
  extensions.load('ui_appLayouts')
  local layout=ui_appLayouts.createLayout({title='ACNG Freeroam',type='freeroam',apps={{appName='acngControl',placement={right='24px',top='70px',width='360px',height='480px'}}}})
  ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'});delay(5)
  click('Toggle ACNG master');waitFor(function() return status().enabled end)
  waitFor(function() local r=probe();return r and r.tires and r.state.heat and r.state.wear end)
  check('real_master_click_native_heat_and_wear',true)
  click('Show advanced ACNG settings');delay(1)
  screenshot.takeScreenShot();delay(1)
  click('ACNG tire wear');waitFor(function() return not status().features.tire_wear end)
  waitFor(function() local r=probe();return r and r.state and r.state.heat and not r.state.wear end)
  check('real_advanced_wear_switch',true)
  click('ACNG steering tab');delay(1)
  click('ACNG force feedback');waitFor(function() local r=probe();return status().features.ffb and r and r.ffb end)
  check('real_ffb_switch',true)
  change('ACNG Strength',150);waitFor(function() return status().ffb_settings.gain==1.5 end)
  check('real_ffb_strength_slider',true)
  click('ACNG assists tab');delay(1)
  change('ACNG ABS',0);waitFor(function() return status().features.abs and status().assist_levels.abs==0 end)
  check('real_abs_selector',true)
  change('ACNG ABS','factory');waitFor(function() return not status().features.abs end)
  check('real_factory_restore_selector',true)
  click('ACNG diagnostics tab');delay(1)
  click('ACNG telemetry stream');waitFor(function() local r=probe();return status().telemetry_enabled and r and r.telemetry end)
  check('real_telemetry_switch',true)
  click('Toggle ACNG master');waitFor(function() local r=probe();return not status().enabled and not status().telemetry_enabled and r and not r.tires and not r.ffb and not r.assists and not r.telemetry end)
  check('master_off_unloads_all_effects_and_stream',true)
  click('Toggle ACNG master');waitFor(function() local r=probe();return status().enabled and r and r.state and r.state.heat and not r.state.wear end)
  check('master_on_keeps_custom_choices',true)
  click('Toggle ACNG master');waitFor(function() return not status().enabled end)
  check('preferences_saved',extensions.acng_core.saveSettings())
  extensions.unload('acng_core');extensions.load('acng_core');setExtensionUnloadMode('acng_core','manual');delay(1)
  local s=status()
  check('native_reload_preferences_master_off',not s.enabled and not s.telemetry_enabled and s.features.tire_temperature and not s.features.tire_wear and s.features.ffb and s.ffb_settings.gain==1.5)
  extensions.acng_core.setFeature('ffb',false);extensions.acng_core.setFFBSetting('gain',1)
  extensions.acng_core.setFeature('tire_wear',true);extensions.acng_core.setControlEnabled(false);extensions.acng_core.saveSettings()
  click('Show advanced ACNG settings');delay(1)
  screenshot.takeScreenShot();delay(1)
  result.status=status();result.layout=layout;result.completed=true;result.ready=true;save()
end
local function onUpdate(dt,dts)
  real=real+dt;sim=sim+dts;if result.completed or result.failure or real<8 then return end
  if not co then co=coroutine.create(run) end
  local ok,err=coroutine.resume(co)
  if not ok then result.failure=tostring(err);save();log('E','ACNG_GUI001',result.failure) end
end
M.onUpdate=onUpdate;M.receive=function(s) response=jsonDecode(s) end
return M
