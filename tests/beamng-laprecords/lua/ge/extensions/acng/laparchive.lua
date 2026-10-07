-- LR001: native filesystem / vehicle-VM archive round trip. LAB PROFILE ONLY.
-- Preparation does not run this. Explicit quiet-time clearance is required to launch.
local M={}
local phase,elapsed,stage,control,poll=0,0,0,0,0
local result={test='LR001 saved lap archive',completed=false,checks={},snapshots={},events={}}
local FILE='/acng-lap-records-test.json'
local function save() jsonWriteFile(FILE,result,true) end
local function command(v,s) v:queueLuaCommand(s) end
local function stop(v)
  if v then command(v,"controller.mainController.setGearboxMode('realistic'); input.event('clutch',1,1); input.event('throttle',0,1); input.event('brake',1,1); input.event('steering',0,2)") end
end
local function fail(reason,v)
  result.failure=reason;result.completed=false;phase=99;stop(v);save()
end
local function transition(nextPhase)
  phase,stage,poll=nextPhase,0,0
  result.events[#result.events+1]={phase=phase,host_s=elapsed};save()
end
local function request(v,label)
  command(v,string.format("local s=extensions.isExtensionLoaded('acng_laps') and extensions.acng_laps.getSnapshot() or {unloaded=true}; obj:queueGameEngineLua(string.format('extensions.acng_laparchive.receive(%%q,%%q)',%q,jsonEncode(s)))",label))
end
local function receive(label,text)
  result.snapshots[label]=jsonDecode(text);save()
end
local function matching(s)
  local before=result.snapshots.recorded
  return s and s.best and before and before.best and
    math.abs(s.best.time_s-before.best.time_s)<1e-6 and
    math.abs(s.ref_length_m-before.ref_length_m)<1e-6 and s.laps==0 and
    s.mode=='out_lap' and s.archive_status=='loaded'
end
local function onUpdate(dt,simdt)
  if phase==99 then return end
  elapsed=elapsed+dt;stage=stage+simdt;control=control+dt;poll=poll+dt
  local v=be:getPlayerVehicle(0)
  if elapsed>300 then return fail('Host watchdog expired',v) end
  if phase==0 and elapsed>10 and core_modmanager.isReady() then
    local userPath=FS:getUserPath():gsub('\\','/'):lower()
    if not userPath:match('/acng%-laprecords%-[%w%-]+/current/?$') then return fail('Dedicated ACNG-laprecords profile required',nil) end
    -- Do not run destructive CLEAR against an existing player's archive.
    if FS:fileExists('/settings/acng/lap-records.json') or FS:fileExists('/settings/acng/lap-records.json.previous') then return fail('Fresh isolated profile required',nil) end
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');transition(1);return
  end
  if worldReadyState~=2 or not v or not extensions.isExtensionLoaded('acng_core') then return end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});transition(2)
  elseif phase==2 and stage>8 then
    result.checks.default_master_off=not extensions.acng_core.getStatus().enabled
    extensions.acng_core.setEnabled(true)
    command(v,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('steering',0.25,2)")
    transition(3)
  elseif phase==3 or phase==4 then
    if control>0.1 then
      control=0;command(v,string.format("input.event('throttle',%.4f,1)",math.max(0,math.min(1,0.25*(12-v:getVelocity():length())))))
    end
    if phase==3 and stage>25 then
      command(v,"if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.setLineHere() end");transition(4)
    elseif phase==4 then
      if poll>0.5 then poll=0;request(v,'recorded') end
      local s=result.snapshots.recorded
      if s and s.best and s.archive_status=='saved' then
        stop(v)
        local db=jsonReadFile('/settings/acng/lap-records.json')
        local r=db and db.records and db.records[1]
        result.checks.native_file_saved=r and r.value and r.value.best and math.abs(r.value.best.time_s-s.best.time_s)<1e-6 or false
        transition(5)
      end
    end
  elseif phase==5 and stage>4 then
    extensions.acng_core.setEnabled(false);transition(6)
  elseif phase==6 and stage>2 then
    -- New GE archive VM forces a real disk read, not just an in-memory return.
    extensions.unload('acng_lapRecords')
    extensions.acng_core.setEnabled(true);transition(7)
  elseif phase==7 then
    if poll>0.5 then poll=0;request(v,'reloaded') end
    if matching(result.snapshots.reloaded) then
      result.checks.disk_and_vehicle_vm_reload=true
      command(v,"extensions.acng_laps.clear()");transition(8)
    elseif stage>10 then return fail('Reload did not restore matching reference',v) end
  elseif phase==8 then
    if poll>0.5 then poll=0;request(v,'cleared') end
    local s=result.snapshots.cleared
    if s and not s.best and s.mode=='out_lap' and s.archive_status=='saved' then
      result.checks.clear_acknowledged=true
      extensions.acng_core.setEnabled(false);transition(9)
    elseif stage>10 then return fail('CLEAR did not reach storage',v) end
  elseif phase==9 and stage>2 then
    extensions.unload('acng_lapRecords');extensions.acng_core.setEnabled(true);transition(10)
  elseif phase==10 then
    if poll>0.5 then poll=0;request(v,'after_clear_reload') end
    local s=result.snapshots.after_clear_reload
    if s and s.mode=='out_lap' and not s.best and s.laps==0 and s.archive_status=='loaded' then
      result.checks.clear_persisted=true
      local all=true;for _,ok in pairs(result.checks) do if ok~=true then all=false end end
      result.completed=true;result.passed=all
      result.limitations={'GE/VE VM reload is not a full game-process restart','map/config separation tested offline only','no physical UI click verification'}
      stop(v);extensions.acng_core.setEnabled(false);phase=99;save()
    elseif stage>10 then return fail('Cleared reference returned or line was lost',v) end
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
