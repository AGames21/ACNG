-- ACNG control plane. Foundation version never changes vehicle physics.
local M = {}
local config
local attachedId
local pollTime = 0
local function defaults()
  return jsonReadFile('/settings/acng/defaults.json')
end
local function stopVehicle()
  if attachedId then
    local veh = be:getObjectByID(attachedId)
    if veh then veh:queueLuaCommand("if extensions.acng_telemetry then extensions.acng_telemetry.stop() end") end
  end
  attachedId = nil
end
local function onExtensionLoaded()
  config = defaults()
  if not config then
    log('E', 'ACNG', 'Missing defaults; extension will not initialize')
    return false
  end
  -- Runtime overrides are deliberately limited to known, passive settings.
  local saved = jsonReadFile('/settings/acng/runtime.json')
  if saved and saved.schema_version == 1 then
    config.enabled = saved.enabled == true
    config.developer_mode = saved.developer_mode == true
    if saved.telemetry then config.telemetry.enabled = saved.telemetry.enabled == true end
  end
  log('I', 'ACNG', 'FOUNDATION_LOADED schema=1 master=' .. tostring(config.enabled) .. ' physics_writes=0')
end
local function setEnabled(value)
  config.enabled = value == true
  -- No implemented dynamics modules yet. Pending features stay inactive.
  log('I', 'ACNG', 'MASTER=' .. tostring(config.enabled) .. ' physics_writes=0')
  return config.enabled
end
local function setTelemetryEnabled(value)
  config.telemetry.enabled = value == true
  if not config.telemetry.enabled then stopVehicle() end
end
local function onUpdate(dtReal)
  if not config or not config.telemetry.enabled then return end
  pollTime = pollTime + dtReal
  if pollTime < 0.25 then return end
  pollTime = 0
  local veh = be:getPlayerVehicle(0)
  local id = veh and veh:getID()
  if id ~= attachedId then
    stopVehicle()
    if veh then
      local cmd = string.format("extensions.load('acng_telemetry'); extensions.acng_telemetry.start(%d,%d)", config.telemetry.rate_hz, config.telemetry.port)
      veh:queueLuaCommand(cmd)
      attachedId = id
    end
  end
end
local function getStatus()
  return {schema_version=1, enabled=config and config.enabled or false,
    telemetry_enabled=config and config.telemetry.enabled or false,
    attached_vehicle_id=attachedId, implemented_physics_features={}, physics_writes=0}
end
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = stopVehicle
M.onClientEndMission = stopVehicle
M.onUpdate = onUpdate
M.setEnabled = setEnabled
M.setTelemetryEnabled = setTelemetryEnabled
M.getStatus = getStatus
return M
