local M={}
local result={schema_version=1,test='RW001 native race weekend',completed=false,checks={},events={}}
local real,sim,co,reportTime=0,0,nil,0
local damage={}
local function receiveDamage(tag,value) damage[tag]=value end
local function save() jsonWriteFile('/acng-weekend-test.json',result,true) end
local function check(name,ok) result.checks[name]=ok==true;save();if not ok then error('Check failed: '..name) end end
local function event(name) result.events[#result.events+1]={name=name,sim_s=sim};save() end
local function waitFor(fn,timeout)
  local t=sim; while not fn() do if sim-t>(timeout or 15) then error('Wait timed out') end;coroutine.yield() end
end
local function delay(t) local untilTime=sim+t;while sim<untilTime do coroutine.yield() end end
local function s() return extensions.acng_weekend.getSnapshot() end
local function click(label)
  -- GE can see the phase change a frame before Angular enables the corresponding button.
  delay(0.8)
  local selector='.acng-weekend button[aria-label="'..label..'"]'
  be:queueJS('(function(){var e=document.querySelector('..jsonEncode(selector)..');if(e)e.click();})()')
end
local function drivePlayer()
  local checkpoints={};for _,name in ipairs({'hr_start','quickrace_wp6','quickrace_wp4'}) do checkpoints[#checkpoints+1]=scenetree.findObject(name) end
  local p=require('/lua/ge/extensions/gameplay/race/path')('lab driver');p:fromCheckpointList(checkpoints,true);p.startNode=p.pathnodes.sorted[1].id;p:autoConfig()
  local r=require('/lua/ge/extensions/gameplay/race/race')();r:setPath(p);r.lapCount=9999;r:startAiVehicle(be:getPlayerVehicleID(0),0.7)
end
local function run()
  waitFor(function() return core_modmanager.isReady() end,60)
  if not FS:getUserPath():gsub('\\','/'):lower():match('/acng%-weekend%-[%w%-]+/current/?$') then error('Isolated profile required') end
  freeroam_freeroam.startFreeroam('/levels/hirochi_raceway/')
  waitFor(function() return worldReadyState==2 and be:getPlayerVehicle(0) end,100)
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});delay(8)
  extensions.load('acng_weekend');check('default_off',s().phase=='off')
  extensions.acng_core.setEnabled(true)
  extensions.load('ui_appLayouts')
  local layout=ui_appLayouts.createLayout({title='ACNG Race Weekend Lab',type='freeroam',apps={
    {appName='acngWeekend',placement={right='20px',top='65px',width='400px',height='340px'}},
    {appName='acngRacingHud',placement={left='30%',bottom='20px',width='460px',height='190px'}}}})
  ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'});delay(5)
  -- Explicit opt-in for this automated test only; production defaults to no AI.
  be:queueJS('(function(){var e=document.querySelector(".acng-weekend select");if(e){for(var i=0;i<e.options.length;i++){if(e.options[i].text.trim()==="2"){e.selectedIndex=i;break;}}e.dispatchEvent(new Event("change",{bubbles:true}));}})()');delay(1)
  click('Prepare race weekend');waitFor(function() return s().phase=='ready' end,45)
  result.initial=s();check('ui_prepare_three_entrants',#s().standings==3);event('ready')
  local p=be:getPlayerVehicle(0):getPosition()
  click('Start practice');waitFor(function() return s().phase=='practice' end,12);delay(15)
  local moved=false;for _,r in ipairs(s().standings) do if not r.player then local v=be:getObjectByID(r.id);if v and v:getVelocity():length()>3 then moved=true end end end
  check('native_ai_moves',moved);check('simulation_clock_advances',s().clock_s>10)
  click('End current session');waitFor(function() return s().phase=='results' end,8);check('ui_end_practice',true)
  click('Start qualifying');waitFor(function() return s().phase=='qualifying' end,12);drivePlayer()
  waitFor(function() for _,r in ipairs(s().standings) do if r.best_s then return true end end return false end,200)
  result.qualifying=s();check('native_completed_qualifying_lap',true)
  click('End current session');waitFor(function() return s().phase=='results' end,8)
  be:getPlayerVehicle(0):queueLuaCommand('ai.setMode("disabled")')
  extensions.acng_weekend.setOption('laps',1)
  -- Select through the real change event; Angular debug scopes may be unavailable
  -- or belong to an outer app container rather than this directive's link scope.
  be:queueJS('(function(){var e=document.querySelector(\'.acng-weekend select[aria-label="Race laps"]\');if(e){for(var i=0;i<e.options.length;i++){if(e.options[i].text.trim()==="1"){e.selectedIndex=i;break;}}e.dispatchEvent(new Event("change",{bubbles:true}));}})()');delay(1)
  click('Start race');waitFor(function() return s().phase=='race' end,12);drivePlayer()
  check('real_lap_selector_one_lap',s().options.laps==1)
  waitFor(function() return s().phase=='results' end,240)
  result.race=s();check('lap_limit_finish_flag',s().message=='CHEQUERED FLAG')
  local count=0;for _,r in ipairs(s().standings) do if r.finished then count=count+1 end end
  check('all_entrants_finish',count==3)
  be:getPlayerVehicle(0):queueLuaCommand('ai.setMode("disabled")')
  click('Start qualifying');waitFor(function() return s().phase=='qualifying' end,12)
  be:getPlayerVehicle(0):reset();delay(2)
  local retired=false;for _,r in ipairs(s().standings) do if r.player and r.retired=='Reset' then retired=true end end
  check('actual_reset_retires_player',retired)
  click('End current session');waitFor(function() return s().phase=='results' end,8)
  be:getPlayerVehicle(0):queueLuaCommand('beamstate.deflateTire(0);obj:queueGameEngineLua("extensions.acng_weekendlab.receiveDamage(\"before\","..tostring(wheels.wheels[0].isTireDeflated==true)..")")')
  waitFor(function() return damage.before~=nil end,8);check('flat_created',damage.before)
  click('Start practice');waitFor(function() return s().phase=='practice' end,12)
  be:getPlayerVehicle(0):queueLuaCommand('obj:queueGameEngineLua("extensions.acng_weekendlab.receiveDamage(\"after\","..tostring(wheels.wheels[0].isTireDeflated==true)..")")')
  waitFor(function() return damage.after~=nil end,8);check('grid_preserves_flat_tire',damage.after)
  local opponents={};for _,r in ipairs(s().standings) do if not r.player then opponents[#opponents+1]=r.id end end
  click('Cancel race weekend');waitFor(function() return s().phase=='off' end,8)
  check('cancel_keeps_player',be:getPlayerVehicle(0)~=nil)
  local removed=true;for _,id in ipairs(opponents) do if be:getObjectByID(id) then removed=false end end
  check('cancel_removes_owned_opponents',removed)
  extensions.acng_core.setEnabled(false)
  result.completed=true;save();event('complete')
end
local function onUpdate(dt,dtSim)
  real=real+dt;sim=sim+dtSim
  if result.completed or result.failure then return end
  if real<8 then return end
  if not co then co=coroutine.create(run) end
  local ok,err=coroutine.resume(co)
  if extensions.isExtensionLoaded('acng_weekend') and real-reportTime>5 then
    reportTime=real;result.live=s();save()
  end
  if not ok then result.failure=tostring(err);save();log('E','ACNG_RW001',result.failure) end
end
M.receiveDamage=receiveDamage
M.onUpdate=onUpdate
return M
