-- ACNG control plane. Physics features stay off unless the master and the feature are ON.
local M = {}
local config
local attachedId
local attachedCaptureId
local captureSerial = 0
local captureSession = tostring(os.time())
local pollTime = 0
local perfId
-- Read-only driver apps that follow the player vehicle while the master is ON.
local APPS_LOAD = "extensions.load('acng_perf'); extensions.load('acng_laps')"
local APPS_UNLOAD = "extensions.unload('acng_perf'); extensions.unload('acng_laps')"
-- Physics features that are implemented and lab-validated. Each loads into the player
-- vehicle while the master and its own flag are ON; unloading restores stock values.
local IMPLEMENTED = {tire_temperature=true, tire_wear=true}
-- tire_temperature and tire_wear share the acng_tires vehicle extension; configure()
-- tells it which parts run, and is sent again whenever either flag changes.
local TIRES_LOAD = "extensions.load('acng_tires')"
local TIRES_CONFIGURE = "if extensions.isExtensionLoaded('acng_tires') then extensions.acng_tires.configure(%s,%s) end"
local TIRES_UNLOAD = "extensions.unload('acng_tires')"
local tiresId
local tiresParts
local function defaults()
  return jsonReadFile('/settings/acng/defaults.json')
end
local function stopVehicle()
  if attachedId then
    local veh = be:getObjectByID(attachedId)
    if veh then veh:queueLuaCommand("if extensions.isExtensionLoaded('acng_telemetry') then extensions.acng_telemetry.stop() end") end
  end
  attachedId = nil
  attachedCaptureId = nil
end
local function stopPerf()
  if perfId then
    local veh = be:getObjectByID(perfId)
    if veh then veh:queueLuaCommand(APPS_UNLOAD) end
  end
  perfId = nil
end
local function stopTires()
  if tiresId then
    local veh = be:getObjectByID(tiresId)
    if veh then veh:queueLuaCommand(TIRES_UNLOAD) end
  end
  tiresId = nil
  tiresParts = nil
end
local function feature(name)
  return config and config.features and config.features[name] == true or false
end
local function tiresWanted()
  return config and config.enabled and (feature('tire_temperature') or feature('tire_wear'))
end
local function tiresConfigure()
  return string.format(TIRES_CONFIGURE, tostring(feature('tire_temperature')), tostring(feature('tire_wear')))
end
local function physicsWrites()
  return tiresId and 1 or 0
end
local function stopAll()
  stopVehicle()
  stopPerf()
  stopTires()
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
    if type(saved.features) == 'table' then
      config.features = config.features or {}
      for name in pairs(IMPLEMENTED) do config.features[name] = saved.features[name] == true end
    end
  end
  log('I', 'ACNG', 'FOUNDATION_LOADED schema=1 master=' .. tostring(config.enabled) .. ' physics_writes=0')
end
local function setEnabled(value)
  config.enabled = value == true
  if not config.enabled then stopPerf(); stopTires() else pollTime = 0.25 end
  log('I', 'ACNG', 'MASTER=' .. tostring(config.enabled) .. ' physics_writes=' .. physicsWrites())
  return config.enabled
end
-- Only implemented features can be switched; reserved flags stay off.
local function setFeature(name, value)
  if not config or not IMPLEMENTED[name] then return false end
  config.features = config.features or {}
  config.features[name] = value == true
  if not tiresWanted() then stopTires() else pollTime = 0.25 end
  log('I', 'ACNG', 'FEATURE ' .. name .. '=' .. tostring(config.features[name]))
  return config.features[name]
end
local function setTelemetryEnabled(value)
  config.telemetry.enabled = value == true
  if not config.telemetry.enabled then stopVehicle() end
end
local function onUpdate(dtReal)
  if not config or not (config.enabled or config.telemetry.enabled) then return end
  pollTime = pollTime + dtReal
  if pollTime < 0.25 then return end
  pollTime = 0
  local veh = be:getPlayerVehicle(0)
  local id = veh and veh:getID()
  -- The read-only performance and lap timers follow the player vehicle while the master is ON.
  if config.enabled and id ~= perfId then
    stopPerf()
    if veh then
      veh:queueLuaCommand(APPS_LOAD)
      perfId = id
    end
  end
  if tiresWanted() then
    local parts = tiresConfigure()
    if id ~= tiresId then
      stopTires()
      if veh then
        veh:queueLuaCommand(TIRES_LOAD .. '; ' .. parts)
        tiresId, tiresParts = id, parts
      end
    elseif parts ~= tiresParts and veh then
      veh:queueLuaCommand(parts)
      tiresParts = parts
    end
  end
  if not config.telemetry.enabled then return end
  if id ~= attachedId then
    stopVehicle()
    if veh then
      captureSerial = captureSerial + 1
      attachedCaptureId = captureSession .. ':' .. captureSerial
      local model = veh.getJBeamFilename and veh:getJBeamFilename() or ''
      local cmd = string.format("extensions.load('acng_telemetry'); extensions.acng_telemetry.start(%d,%d,%q,%q)", config.telemetry.rate_hz, config.telemetry.port, attachedCaptureId, model)
      veh:queueLuaCommand(cmd)
      attachedId = id
    end
  end
end
local function onVehicleSpawned(id)
  -- BeamNG can reuse a GE object ID while replacing its entire vehicle Lua VM.
  -- The old reader no longer exists; polling only the object ID misses this.
  if id == attachedId then
    attachedId, attachedCaptureId = nil, nil
    pollTime = 0.25
  end
  if id == perfId then
    perfId = nil
    pollTime = 0.25
  end
  if id == tiresId then
    tiresId, tiresParts = nil, nil
    pollTime = 0.25
  end
end
local function getStatus()
  return {schema_version=1, enabled=config and config.enabled or false,
    telemetry_enabled=config and config.telemetry.enabled or false,
    attached_vehicle_id=attachedId, attached_capture_id=attachedCaptureId,
    performance_timer_vehicle_id=perfId, lap_timer_vehicle_id=perfId,
    tires_vehicle_id=tiresId,
    features={tire_temperature=feature('tire_temperature'), tire_wear=feature('tire_wear')},
    implemented_physics_features={'tire_temperature', 'tire_wear'}, physics_writes=physicsWrites()}
end
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = stopAll
M.onClientEndMission = stopAll
M.onUpdate = onUpdate
M.onVehicleSpawned = onVehicleSpawned
M.setEnabled = setEnabled
M.setTelemetryEnabled = setTelemetryEnabled
M.setFeature = setFeature
M.getStatus = getStatus
return M
