-- Isolated HUD validation scene only; not distributed in the mod.
local M={}
local elapsed,phase,stage=0,0,0
local result={test='HUD001',checks={}}
local function save() jsonWriteFile('/acng-hud-test.json',result,true) end
local function onUpdate(dtReal)
 elapsed=elapsed+dtReal
 if phase==0 and elapsed>12 and core_modmanager.isReady() then
  freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
 end
 if worldReadyState~=2 then return end
 local veh=be:getPlayerVehicle(0)
 if not veh or not extensions.acng_core then return end
 stage=stage+dtReal
 if phase==1 then
  core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase=2;stage=0
 elseif phase==2 and stage>4 then
  result.checks.default_master_off=not extensions.acng_core.getStatus().enabled
  extensions.acng_core.setEnabled(true)
  extensions.load('ui_appLayouts')
  local id=ui_appLayouts.createLayout({title='ACNG HUD Lab',type='freeroam',apps={{appName='acngRacingHud',placement={left='30%',bottom='30px',width='460px',height='190px'}}}})
  ui_appLayouts.setUsedLayout(id)
  guihooks.trigger('ChangeState',{state='play'})
  result.layout=id;result.checks.layout_created=id~=nil;save()
  veh:queueLuaCommand("controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('parkingbrake',1,1); input.event('brake',0.7,1)")
  phase=3;stage=0
 elseif phase==3 and stage>10 then
  veh:queueLuaCommand("input.event('throttle',0.3,1)")
  result.checks.live_pedal_command=true;save();phase=4;stage=0
 elseif phase==4 and stage>12 then
  veh:queueLuaCommand("input.event('throttle',0,1); input.event('brake',1,1)")
  result.checks.complete=true;save();phase=5
 end
end
M.onUpdate=onUpdate
return M
