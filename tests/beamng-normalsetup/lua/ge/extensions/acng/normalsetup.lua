-- One-shot authorized normal-profile smoke. Retired after setup, never shipped.
local M={};local real,co,response=0,nil,nil
local result={schema_version=1,test='N001 normal profile setup',completed=false,checks={}}
local function save() jsonWriteFile('/acng-normal-setup.json',result,true) end
local function check(name,x) result.checks[name]=x==true;save();if not x then error(name) end end
local function wait(f,seconds)
  local start=real;while not f() do if real-start>(seconds or 20) then error('Timeout waiting for setup') end;coroutine.yield() end
end
local function delay(seconds) local endTime=real+seconds;while real<endTime do coroutine.yield() end end
local function status() return extensions.acng_core.getStatus() end
local function probe()
  local v=be:getPlayerVehicle(0)
  if v then v:queueLuaCommand([[local s={tires=extensions.isExtensionLoaded('acng_tires'),ffb=extensions.isExtensionLoaded('acng_ffb'),assists=extensions.isExtensionLoaded('acng_assists')};if s.tires then s.state=extensions.acng_tires.getSnapshot() end;obj:queueGameEngineLua(string.format('extensions.acng_normalsetup.receive(%q)',jsonEncode(s)))]]) end
  return response
end
local function click()
  be:queueJS([[var e=document.querySelector('.acng-control [aria-label="Toggle ACNG master"]');if(e)e.click();]])
end
local function run()
  local target=rawget(_G,'ACNG_NORMAL_SETUP_TARGET')
  check('registered_normal_profile',type(target)=='string' and FS:getUserPath():gsub('\\','/'):lower():gsub('/$','')==target:gsub('\\','/'):lower():gsub('/$',''))
  wait(function() return core_modmanager.isReady() end,180)
  check('production_mod_loaded',extensions.isExtensionLoaded('acng_core'))
  check('startup_master_off',not status().enabled)
  freeroam_freeroam.startFreeroam('/levels/west_coast_usa/')
  wait(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,240)
  result.vehicle=be:getPlayerVehicle(0):getJBeamFilename()
  extensions.load('ui_appLayouts');ui_appLayouts.setUsedLayout('freeroam')
  local layout=ui_appLayouts.getCurrentLayout();result.app_count=#layout.apps
  local found=false;for _,app in ipairs(layout.apps) do if app.appName=='acngControl' then found=true end end
  check('normal_freeroam_layout_has_acng',found)
  guihooks.trigger('ChangeState',{state='play'});delay(5)
  click();wait(function() return status().enabled end)
  wait(function() local r=probe();return r and r.tires and r.state and r.state.heat and r.state.wear and r.state.profile=='road' end)
  check('normal_master_click_applies_road_heat_wear',true)
  click();wait(function() local r=probe();return not status().enabled and r and not r.tires and not r.ffb and not r.assists end)
  check('normal_master_off_unloads_effects',true)
  check('telemetry_off',not status().telemetry_enabled)
  check('preferences_saved',extensions.acng_core.saveSettings())
  screenshot.takeScreenShot();delay(1)
  result.status=status();result.completed=true;save()
end
local function onUpdate(dt)
  real=real+dt;if result.completed or result.failure or real<8 then return end
  if not co then co=coroutine.create(run) end
  local ok,err=coroutine.resume(co)
  if not ok then
    result.failure=tostring(err)
    if extensions.isExtensionLoaded('acng_core') then extensions.acng_core.setControlEnabled(false) end
    save();log('E','ACNG_N001',result.failure)
  end
end
M.onUpdate=onUpdate;M.receive=function(s) response=jsonDecode(s) end
return M
