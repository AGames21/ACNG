-- Stationary control/UI test, no AI spawning or driving inputs.
local M={};local real,sim,co=0,0,nil;local response
local result={test='GUI003 compact controls and compound/wear failure',completed=false,checks={},vehicles={}}
local uiResponse
local function uiProbe(label)
  uiResponse=nil
  be:queueJS([[(()=>{var e=document.querySelector('.acng-control'),h=e&&e.closest('[data-acng-control-host]');var parents=[],n=e;while(n&&parents.length<5){parents.push({tag:n.tagName,cls:n.className,style:n.getAttribute('style')});n=n.parentElement;}var r=e?{width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height,host:!!h,hostHeight:h&&h.getBoundingClientRect().height,parents:parents}:{};bngApi.engineLua('extensions.acng_controllab.uiReceive('+JSON.stringify(JSON.stringify(r))+')');})()]])
end
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
  if v then v:queueLuaCommand([[local s={id=obj:getID(),tires=extensions.isExtensionLoaded('acng_tires'),ffb=extensions.isExtensionLoaded('acng_ffb'),assists=extensions.isExtensionLoaded('acng_assists'),telemetry=false,wheels={}};for _,wd in pairs(wheels.wheels or {}) do s.wheels[#s.wheels+1]={name=wd.name,deflated=wd.isTireDeflated==true or wd.isTireDeflated==1,broken=wd.isBroken==true or wd.isBroken==1} end;if extensions.isExtensionLoaded('acng_telemetry') then s.telemetry=extensions.acng_telemetry.getStatus().active end;if s.tires then s.state=extensions.acng_tires.getSnapshot() end;obj:queueGameEngineLua(string.format('extensions.acng_controllab.receive(%q)',jsonEncode(s)))]]) end
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
  local layout=ui_appLayouts.createLayout({title='ACNG Freeroam',type='freeroam',apps={{appName='acngControl',placement={right='24px',top='70px',width='220px',height='44px'}}}})
  ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'});delay(5)
  uiProbe();waitFor(function() return uiResponse end);result.collapsed=uiResponse
  check('compact_collapsed_size',uiResponse.width<=230 and uiResponse.height<=50)
  createScreenshot2({filename='screenshots/acng_gui003_collapsed',writeJPG=true});delay(2)
  click('Toggle ACNG master');waitFor(function() return status().enabled end)
  waitFor(function() local r=probe();return r and r.tires and r.state.heat and r.state.wear end)
  check('real_master_click_native_heat_and_wear',true)
  click('Show advanced ACNG settings');delay(1)
  uiProbe();waitFor(function() return uiResponse end);result.expanded=uiResponse
  check('advanced_expands_host',uiResponse.host and uiResponse.hostHeight>=300 and uiResponse.height>100)
  createScreenshot2({filename='screenshots/acng_gui003_expanded',writeJPG=true});delay(2)
  screenshot.takeScreenShot();delay(1)
  click('ACNG tire wear');waitFor(function() return not status().features.tire_wear end)
  waitFor(function() local r=probe();return r and r.state and r.state.heat and not r.state.wear end)
  check('real_advanced_wear_switch',true)
  change('ACNG tire preset','sport');waitFor(function() local r=probe();return r and r.state and r.state.profile=='sport' end)
  check('real_sport_preset_selector',status().tire_profile=='sport')
  change('ACNG tire preset','road');waitFor(function() local r=probe();return r and r.state and r.state.profile=='road' end)
  check('real_road_preset_selector',status().tire_profile=='road')
  change('ACNG tire preset','auto');waitFor(function() local r=probe();return r and r.state and r.state.profile=='auto' end)
  check('auto_detects_native_sport_tires',response.state.tires[1].compound=='sport')
  change('ACNG tire preset','race');waitFor(function() local r=probe();return r and r.state and r.state.profile=='race' end)
  check('race_preset_has_own_window',response.state.window_low_c==85 and response.state.window_high_c==115)
  change('ACNG tire preset','road');waitFor(function() return status().tire_profile=='road' end)
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
  check('native_reload_road_preset',s.tire_profile=='road')
  extensions.acng_core.setFeature('ffb',false);extensions.acng_core.setFFBSetting('gain',1)
  -- Stationary native compatibility: no traffic or automatic driving.
  local function tireReady()
    local v=be:getPlayerVehicle(0);local r=probe()
    return v and r and r.id==v:getID() and r.tires and r.state and r.state.profile=='road' and r.state.heat and r.state.wear
  end
  extensions.acng_core.setFeature('tire_wear',true)
  extensions.acng_core.setControlEnabled(true)
  for _,model in ipairs({'etkc','bolide','pickup'}) do
    response=nil
    core_vehicles.replaceVehicle(model,model=='etkc' and {config='vehicles/etkc/kc6_360_M.pc'} or {})
    delay(8);waitFor(tireReady,25)
    result.vehicles[model]={state=response.state,wheels=response.wheels}
    check(model..'_road_heat_and_wear_attached',#response.state.tires>=4)
    be:getPlayerVehicle(0):queueLuaCommand('obj:requestReset(RESET_PHYSICS)');delay(2);waitFor(tireReady)
    local fresh=true;for _,wheel in ipairs(response.state.tires) do fresh=fresh and wheel.tread==1 end
    check(model..'_reset_fresh_tread',fresh)
  end
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});response=nil;delay(8);waitFor(tireReady)
  local v=be:getPlayerVehicle(0)
  -- Controlled slip-work injection validates the native failure path, not tire life.
  v:queueLuaCommand([[for _,wd in pairs(wheels.wheels) do if wd.name=='FL' then local old=wd.slipEnergy;wd.slipEnergy=1e10;extensions.acng_tires.updateGFX(0.1);wd.slipEnergy=old end end]])
  waitFor(function() local r=probe();if not r then return false end;for _,w in ipairs(r.wheels) do if w.name=='FL' and w.deflated then return true end end;return false end)
  check('native_puncture_survives_acng',true)
  waitFor(function() local r=probe();if not r or not r.state then return false end;for _,w in ipairs(r.state.tires) do if w.name=='FL' then return w.tread==0 and w.worn_through end end end)
  check('zero_tread_caused_native_puncture',true)
  waitFor(function() local r=probe();if not r or not r.state then return false end;for _,w in ipairs(r.state.tires) do if w.name=='FL' then return type(w.psi)=='number' and w.psi<5 end end;return false end)
  check('puncture_pressure_remains_low',true)
  v:queueLuaCommand('obj:requestReset(RESET_PHYSICS)');delay(2)
  waitFor(function() local r=probe();if not r then return false end;for _,w in ipairs(r.wheels) do if w.deflated or w.broken then return false end end;return r.state~=nil end)
  check('native_reset_repairs_puncture',true)
  v:queueLuaCommand("beamstate.breakBreakGroup('wheel_FL')")
  waitFor(function() local r=probe();if not r then return false end;for _,w in ipairs(r.wheels) do if w.name=='FL' and w.broken then return true end end;return false end)
  check('native_broken_wheel_survives_acng',true)
  extensions.acng_core.setControlEnabled(false);delay(1)
  waitFor(function() local r=probe();if not r or r.tires then return false end;for _,w in ipairs(r.wheels) do if w.name=='FL' and w.broken then return true end end;return false end)
  check('master_off_does_not_repair_damage',true)
  v:queueLuaCommand('obj:requestReset(RESET_PHYSICS)');delay(3)
  check('no_physics_modules_left_active',status().physics_writes==0)
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
M.uiReceive=function(s) uiResponse=jsonDecode(s) end
return M
