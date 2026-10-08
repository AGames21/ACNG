-- Isolated user playtest setup only; never drives or clicks session controls.
local M={};local phase,elapsed,stage=0,0,0
local result={test='Race Weekend hands-on playtest',ready=false}
local function save() jsonWriteFile('/acng-weekend-playtest.json',result,true) end
local function onUpdate(dt,dtSim)
  if phase==99 then return end
  elapsed=elapsed+dt;stage=stage+dtSim
  if elapsed>150 then result.failure='Setup watchdog';phase=99;save();return end
  if phase==0 and elapsed>8 and core_modmanager.isReady() then
    if not FS:getUserPath():gsub('\\','/'):lower():match('/acng%-weekend%-[%w%-]+/current/?$') then result.failure='Isolated profile required';phase=99;save();return end
    freeroam_freeroam.startFreeroam('/levels/hirochi_raceway/');phase,stage=1,0
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0);if not veh or not extensions.isExtensionLoaded('acng_core') then return end
  if phase==1 then core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stage=2,0
  elseif phase==2 and stage>8 and veh:getJBeamFilename()=='etkc' then
    extensions.acng_core.setEnabled(false)
    extensions.load('ui_appLayouts')
    local id=ui_appLayouts.createLayout({title='ACNG Driving and Racing',type='freeroam',apps={
      {appName='acngWeekend',placement={right='20px',top='60px',width='400px',height='340px'}},
      {appName='acngTires',placement={left='20px',top='60px',width='330px',height='240px'}},
      {appName='acngAssists',placement={left='20px',top='310px',width='330px',height='170px'}},
      {appName='acngRacingHud',placement={left='30%',bottom='20px',width='460px',height='190px'}}}})
    ui_appLayouts.setUsedLayout(id);guihooks.trigger('ChangeState',{state='play'})
    result.layout=id;result.model=veh:getJBeamFilename();result.status=extensions.acng_core.getStatus()
    result.instructions='No opponents by default. PREPARE then PRACTICE for solo laps. No automatic driving. Leave HEAT/WEAR OFF to isolate timing.'
    result.ready=true;phase=99;save()
  end
end
M.onUpdate=onUpdate;return M
