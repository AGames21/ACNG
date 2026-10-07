-- Test-only extension. Deploy into isolated lab, never package with production mod.
local M = {}
local elapsed = 0
local started = false
local phase = 0
local captureTime = 0
local result = {test='ACNG isolated foundation smoke', physics_writes=0, checks={}}
local function onUpdate(dtReal)
  elapsed = elapsed + dtReal
  if not started and elapsed > 12 and core_modmanager.isReady() then
    started = true
    freeroam_freeroam.startFreeroam('/levels/smallgrid/')
    log('I','ACNG_SMOKE','Requested stock smallgrid')
  end
  if not started or worldReadyState ~= 2 then return end
  local veh = be:getPlayerVehicle(0)
  if not veh or not extensions.acng_core then return end
  captureTime = captureTime + dtReal
  if phase == 0 then
    result.checks.loaded = true
    result.checks.default_master_off = not extensions.acng_core.getStatus().enabled
    extensions.acng_core.setEnabled(true)
    result.checks.master_on = extensions.acng_core.getStatus().enabled
    extensions.acng_core.setEnabled(false)
    result.checks.master_off = not extensions.acng_core.getStatus().enabled
    extensions.acng_core.setTelemetryEnabled(true)
    result.checks.vehicle_present = true
    result.vehicle_jbeam = veh:getJBeamFilename()
    phase = 1
    log('I','ACNG_SMOKE','Capturing stock stationary vehicle')
  elseif phase == 1 and captureTime > 15 then
    extensions.acng_core.setTelemetryEnabled(false)
    result.checks.telemetry_disabled = not extensions.acng_core.getStatus().telemetry_enabled
    result.checks.telemetry_detached = extensions.acng_core.getStatus().attached_vehicle_id == nil
    result.capture_duration_real_s = captureTime
    result.game_version = beamng_versionb
    jsonWriteFile('/acng-smoke.json',result,true)
    log('I','ACNG_SMOKE','SMOKE_COMPLETE master=false physics_writes=0')
    phase = 2
  end
end
M.onUpdate = onUpdate
return M
