-- LR002: full process restart readback of a real LR001 saved reference.
local M={}
local phase,elapsed,stage,poll=0,0,0,0
local expected=jsonReadFile('/acng-lap-restart-expect.json')
local result={test='LR002 full process restart',completed=false,checks={}}
local function save() jsonWriteFile('/acng-lap-restart-test.json',result,true) end
local function fail(reason) result.failure=reason;phase=99;save() end
local function receive(text)
  result.snapshot=jsonDecode(text)
end
local function onUpdate(dt,simdt)
  if phase==99 then return end
  elapsed=elapsed+dt;stage=stage+simdt;poll=poll+dt
  if elapsed>120 then return fail('Host watchdog expired') end
  if phase==0 and elapsed>10 and core_modmanager.isReady() then
    local path=FS:getUserPath():gsub('\\','/'):lower()
    if not path:match('/acng%-laprecords%-[%w%-]+/current/?$') then return fail('Dedicated lab required') end
    if not expected or type(expected.best_time_s)~='number' then return fail('Missing restart expectation') end
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase,stage=1,0;return
  end
  if worldReadyState~=2 then return end
  local v=be:getPlayerVehicle(0)
  if not v or not extensions.isExtensionLoaded('acng_core') then return end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stage=2,0
  elseif phase==2 and stage>8 then
    result.checks.master_off_after_restart=not extensions.acng_core.getStatus().enabled
    extensions.acng_core.setEnabled(true);phase,stage=3,0
  elseif phase==3 then
    if poll>0.5 then
      poll=0
      v:queueLuaCommand("if extensions.isExtensionLoaded('acng_laps') then local s=extensions.acng_laps.getSnapshot(); obj:queueGameEngineLua(string.format('extensions.acng_laprestart.receive(%q)',jsonEncode(s))) end")
    end
    local s=result.snapshot
    if s and s.archive_status=='loaded' then
      result.checks.best_time_restored=s.best~=nil and math.abs(s.best.time_s-expected.best_time_s)<1e-6
      result.checks.reference_length_restored=s.ref_length_m~=nil and math.abs(s.ref_length_m-expected.ref_length_m)<1e-6
      result.checks.new_session_with_line=s.mode=='out_lap' and s.laps==0 and s.last==nil
      result.completed=true;result.passed=true
      for _,ok in pairs(result.checks) do if not ok then result.passed=false end end
      result.expected=expected;result.host_s=elapsed
      extensions.acng_core.setEnabled(false);phase=99;save()
    elseif stage>15 then return fail('Archive was not restored after process restart') end
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
