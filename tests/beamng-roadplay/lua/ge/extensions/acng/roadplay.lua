-- Prepare a parked freeroam scene, then go inert. No driving, damage or AI inputs.
local M={};local phase,t=0,0
local function onUpdate(dt)
  t=t+dt
  if phase==0 and t>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/west_coast_usa/');phase=1;t=0
  elseif phase==1 and worldReadyState==2 and be:getPlayerVehicle(0) then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase=2;t=0
  elseif phase==2 and t>8 then
    extensions.acng_core.setTireProfile('road')
    extensions.acng_core.setFeature('tire_temperature',true)
    extensions.acng_core.setFeature('tire_wear',true)
    extensions.acng_core.setControlEnabled(false)
    extensions.acng_core.saveSettings()
    extensions.load('ui_appLayouts')
    local layout=ui_appLayouts.createLayout({title='ACNG Road Playtest',type='freeroam',apps={
      {appName='acngControl',placement={right='24px',top='70px',width='360px',height='480px'}},
      {appName='acngTires',placement={left='24px',top='70px',width='400px',height='330px'}}}})
    ui_appLayouts.setUsedLayout(layout);guihooks.trigger('ChangeState',{state='play'})
    phase=3;t=0
  elseif phase==3 and t>5 then
    jsonWriteFile('/acng-roadplay-ready.json',{ready=true,status=extensions.acng_core.getStatus()},true)
    phase=99
  end
end
M.onUpdate=onUpdate
return M
