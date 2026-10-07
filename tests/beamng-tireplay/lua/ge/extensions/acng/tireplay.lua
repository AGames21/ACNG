-- Isolated hands-on playtest. No automatic driving or physics tuning.
local M={}
local phase,elapsed,stage=0,0,0
local result={test='Tire heat playtest',ready=false,button_checks={}}
local actions={{name='tire_temperature',label='Toggle tire heat and grip window',on=true},{name='tire_temperature',label='Toggle tire heat and grip window',on=false},{name='tire_wear',label='Toggle tire wear',on=true},{name='tire_wear',label='Toggle tire wear',on=false}}
local action=1
local vehicleSnapshot
local function receive(text) vehicleSnapshot=jsonDecode(text) end
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
    result.layout=id;result.model=veh:getJBeamFilename();result.status=extensions.acng_core.getStatus()
    result.instructions='Drive a stock lap; HEAT ON; reset to start; compare the same corner cold vs 75-105 C. Leave WEAR OFF.'
    save();phase,stage=3,0
  elseif phase==3 and stage>3 then
    local selector='.acng-tires button[aria-label="'..actions[action].label..'"]'
    be:queueJS('(function(){var e=document.querySelector('..jsonEncode(selector)..');if(e)e.click();})()')
    vehicleSnapshot=nil;phase,stage=4,0
  elseif phase==4 then
    local a=actions[action];local status=extensions.acng_core.getStatus()
    if stage>10 then result.failure='UI toggle acknowledgement timeout: '..a.name..' '..tostring(a.on);phase=99;save();return end
    if status.features[a.name]==a.on then
      veh:queueLuaCommand("local s=extensions.isExtensionLoaded('acng_tires') and extensions.acng_tires.getSnapshot() or {mode='off'};obj:queueGameEngineLua(string.format('extensions.acng_tireplay.receive(%q)',jsonEncode(s)))")
      local v=vehicleSnapshot
      if v and ((a.on and v.mode=='on' and v[a.name=='tire_wear' and 'wear' or 'heat']==true and #v.tires==4) or (not a.on and v.mode=='off')) then
        result.button_checks[a.name..'_'..tostring(a.on)]=true
        if action<#actions then action=action+1;phase,stage=3,0 else
          extensions.acng_core.setEnabled(false);result.status=extensions.acng_core.getStatus();result.ready=true;phase=99;save()
        end
      end
    end
  end
end
M.receive=receive
M.onUpdate=onUpdate
return M
