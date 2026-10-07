-- Isolated hands-on playtest. No automatic driving or physics tuning.
local M={}
local phase,elapsed,stage=0,0,0
local result={test='Tire heat playtest',ready=false}
local function save() jsonWriteFile('/acng-tire-playtest.json',result,true) end
local function onUpdate(dt,simdt)
  if phase==99 then return end
  elapsed=elapsed+dt;stage=stage+simdt
  if elapsed>120 then result.failure='Setup watchdog';phase=99;save();return end
  if phase==0 and elapsed>10 and core_modmanager.isReady() then
    if not FS:getUserPath():gsub('\\','/'):lower():match('/acng%-tireplay%-[%w%-]+/current/?$') then result.failure='Isolated playtest profile required';phase=99;save();return end
    freeroam_freeroam.startFreeroam('/levels/hirochi_raceway/');phase,stage=1,0;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh or not extensions.isExtensionLoaded('acng_core') then return end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stage=2,0
  elseif phase==2 and stage>8 and veh:getJBeamFilename()=='etkc' then
    extensions.acng_core.setEnabled(false)
    extensions.acng_core.setFeature('tire_temperature',false)
    extensions.acng_core.setFeature('tire_wear',false)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Tire Playtest',type='freeroam',apps={
      {appName='acngTires',placement={right='24px',top='100px',width='330px',height='240px'}},
      {appName='acngRacingHud',placement={left='30%',bottom='25px',width='460px',height='190px'}}}})
    ui_appLayouts.setUsedLayout(id)
    guihooks.trigger('ChangeState',{state='play'})
    result.ready=true;result.layout=id;result.model=veh:getJBeamFilename();result.status=extensions.acng_core.getStatus()
    result.instructions='Drive a stock lap; HEAT ON; reset to start; compare the same corner cold vs 75-105 C. Leave WEAR OFF.'
    save();phase=99
  end
end
M.onUpdate=onUpdate
return M
