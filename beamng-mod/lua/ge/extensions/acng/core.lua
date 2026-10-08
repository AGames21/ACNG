-- ACNG control plane. Physics features stay off unless the master and the feature are ON.
local M = {}
local config
local settingsDirty, settingsTime, settingsError = false, 0, nil
local function changed() settingsDirty,settingsTime=true,0 end
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
local IMPLEMENTED = {tire_temperature=true, tire_wear=true, abs=true, tc=true, ffb=true, race_sessions=true}
-- tire_temperature and tire_wear share the acng_tires vehicle extension; configure()
-- tells it which parts run, and is sent again whenever either flag changes.
local TIRES_LOAD = "extensions.load('acng_tires')"
local TIRES_CONFIGURE = "if extensions.isExtensionLoaded('acng_tires') then extensions.acng_tires.configure(%s,%s) end"
local TIRES_UNLOAD = "extensions.unload('acng_tires')"
local tiresId
local tiresParts
-- abs and tc share the acng_assists vehicle extension. Each flag ON hands that assist
-- to ACNG at its level (0 = off, 1-3); a flag OFF leaves the car's factory assist.
local ASSISTS_LOAD = "extensions.load('acng_assists')"
local ASSISTS_CONFIGURE = "if extensions.isExtensionLoaded('acng_assists') then extensions.acng_assists.configure(%s,%s) end"
local ASSISTS_UNLOAD = "extensions.unload('acng_assists')"
local ASSIST_LEVEL_DEFAULT = 2
local assistsId
local assistsParts
-- ffb loads the acng_ffb vehicle extension: AC-style gain, filter, minimum force and
-- kerb/road/slip feel on top of BeamNG's own steering force. gain is multiplied by the
-- per-car strength (car_gain, by vehicle model) before it is sent.
local FFB_LOAD = "extensions.load('acng_ffb')"
local FFB_CONFIGURE = "if extensions.isExtensionLoaded('acng_ffb') then extensions.acng_ffb.configure(%s,%s,%s,%s,%s,%s) end"
local FFB_UNLOAD = "extensions.unload('acng_ffb')"
-- name = {default, min, max}; filter may also be nil (keep the player's BeamNG smoothing).
local FFB_LIMITS = {gain={1, 0, 2}, min_force={0, 0, 0.3}, filter={nil, 0, 1}, kerb={0.3, 0, 2},
  road={0.5, 0, 2}, slip={0.3, 0, 2}}
local FFB_NAMES = {'gain', 'min_force', 'filter', 'kerb', 'road', 'slip'}
local CAR_GAIN_MAX = 2
local ffbId
local ffbParts
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
local function stopAssists()
  if assistsId then
    local veh = be:getObjectByID(assistsId)
    if veh then veh:queueLuaCommand(ASSISTS_UNLOAD) end
  end
  assistsId = nil
  assistsParts = nil
end
local function stopFFB()
  if ffbId then
    local veh = be:getObjectByID(ffbId)
    if veh then veh:queueLuaCommand(FFB_UNLOAD) end
  end
  ffbId = nil
  ffbParts = nil
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
local function assistsWanted()
  return config and config.enabled and (feature('abs') or feature('tc'))
end
local function assistLevel(name)
  local levels = config and config.assist_levels
  local value = levels and levels[name]
  if type(value) ~= 'number' or value ~= math.floor(value) or value < 0 or value > 3 then return ASSIST_LEVEL_DEFAULT end
  return value
end
local function assistsConfigure()
  return string.format(ASSISTS_CONFIGURE, feature('abs') and tostring(assistLevel('abs')) or 'nil',
    feature('tc') and tostring(assistLevel('tc')) or 'nil')
end
local function ffbWanted()
  return config and config.enabled and feature('ffb')
end
local function validFFB(name, value)
  local lim = FFB_LIMITS[name]
  return lim and type(value) == 'number' and value == value and value >= lim[2] and value <= lim[3]
end
local function ffbSetting(name)
  local s = config and config.ffb_settings
  local value = s and s[name]
  if validFFB(name, value) then return value end
  return FFB_LIMITS[name][1]
end
local function carGain(model)
  local map = config and config.ffb_settings and config.ffb_settings.car_gain
  local value = type(model) == 'string' and type(map) == 'table' and map[model]
  if type(value) == 'number' and value == value and value >= 0 and value <= CAR_GAIN_MAX then return value end
  return 1
end
local function luaNum(x)
  return x == nil and 'nil' or string.format('%.6g', x)
end
local function ffbConfigure(model)
  return string.format(FFB_CONFIGURE, luaNum(ffbSetting('gain') * carGain(model)), luaNum(ffbSetting('min_force')),
    luaNum(ffbSetting('filter')), luaNum(ffbSetting('kerb')), luaNum(ffbSetting('road')), luaNum(ffbSetting('slip')))
end
local function vehicleModel(veh)
  return veh and veh.getJBeamFilename and veh:getJBeamFilename() or nil
end
local function physicsWrites()
  return (tiresId and 1 or 0) + (assistsId and 1 or 0) + (ffbId and 1 or 0)
end
local function stopWeekend()
  if extensions and extensions.isExtensionLoaded('acng_weekend') then extensions.acng_weekend.cancel() end
end
local function stopAll()
  stopWeekend()
  stopVehicle()
  stopPerf()
  stopTires()
  stopAssists()
  stopFFB()
end
local function saveSettings()
  if not config or type(jsonWriteFile)~='function' or not FS then return false end
  local ok,err=pcall(function()
    FS:directoryCreate('/settings/acng/')
    local previous=jsonReadFile('/settings/acng/runtime.json')
    if type(previous)=='table' then assert(jsonWriteFile('/settings/acng/runtime.previous.json',previous,true,nil,true)==true) end
    local saved=deepcopy(config)
    -- Remember choices, never start a fresh game with effects/logging active.
    saved.enabled=false;saved.telemetry.enabled=false
    assert(jsonWriteFile('/settings/acng/runtime.json',saved,true,nil,true)==true)
    local check=jsonReadFile('/settings/acng/runtime.json')
    assert(type(check)=='table' and check.schema_version==1 and check.enabled==false)
  end)
  if ok then settingsError=nil;settingsDirty=false else
    if not settingsError then log('W','ACNG','Preference save failed: '..tostring(err)) end
    settingsError='Preferences could not be saved'
  end
  return ok
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
    config.control_panel_initialized=saved.control_panel_initialized==true
    config.enabled = saved.enabled == true
    config.developer_mode = saved.developer_mode == true
    if saved.telemetry then config.telemetry.enabled = saved.telemetry.enabled == true end
    if type(saved.features) == 'table' then
      config.features = config.features or {}
      for name in pairs(IMPLEMENTED) do config.features[name] = saved.features[name] == true end
    end
    if type(saved.assist_levels) == 'table' then
      config.assist_levels = config.assist_levels or {}
      for _, name in ipairs({'abs', 'tc'}) do
        if saved.assist_levels[name] ~= nil then config.assist_levels[name] = saved.assist_levels[name] end
      end
    end
    if type(saved.ffb_settings) == 'table' then
      config.ffb_settings = config.ffb_settings or {}
      for _, name in ipairs(FFB_NAMES) do
        if saved.ffb_settings[name] ~= nil then config.ffb_settings[name] = saved.ffb_settings[name] end
      end
      if type(saved.ffb_settings.car_gain) == 'table' then config.ffb_settings.car_gain = saved.ffb_settings.car_gain end
    end
  end
  log('I', 'ACNG', 'FOUNDATION_LOADED schema=1 master=' .. tostring(config.enabled) .. ' physics_writes=0')
end
local function setEnabled(value)
  config.enabled = value == true
  if not config.enabled then stopWeekend() end
  if not config.enabled then stopPerf(); stopTires(); stopAssists(); stopFFB() else pollTime = 0.25 end
  log('I', 'ACNG', 'MASTER=' .. tostring(config.enabled) .. ' physics_writes=' .. physicsWrites())
  changed()
  return config.enabled
end
-- Only implemented features can be switched; reserved flags stay off.
local function setFeature(name, value)
  if not config or not IMPLEMENTED[name] then return false end
  config.features = config.features or {}
  config.features[name] = value == true
  if name~='race_sessions' then config.control_panel_initialized=true end
  changed()
  if name == 'race_sessions' and not config.features[name] then stopWeekend() end
  if not tiresWanted() then stopTires() else pollTime = 0.25 end
  if not assistsWanted() then stopAssists() else pollTime = 0.25 end
  if not ffbWanted() then stopFFB() else pollTime = 0.25 end
  log('I', 'ACNG', 'FEATURE ' .. name .. '=' .. tostring(config.features[name]))
  return config.features[name]
end
-- ABS or TC level: 0 = off, 1-3 = light to strong. It applies while that flag is ON.
local function setAssistLevel(name, value)
  if not config or (name ~= 'abs' and name ~= 'tc') then return false end
  if type(value) ~= 'number' or value ~= math.floor(value) or value < 0 or value > 3 then return false end
  config.assist_levels = config.assist_levels or {}
  config.assist_levels[name] = value
  changed()
  pollTime = 0.25
  log('I', 'ACNG', 'ASSIST ' .. name .. '_level=' .. value)
  return value
end
-- One FFB setting (see FFB_LIMITS). filter also takes false to go back to BeamNG's own
-- smoothing. Applies while the ffb flag is ON.
local function setFFBSetting(name, value)
  if not config or not FFB_LIMITS[name] then return false end
  if name == 'filter' and (value == false or value == nil) then value = nil
  elseif not validFFB(name, value) then return false end
  config.ffb_settings = config.ffb_settings or {}
  config.ffb_settings[name] = value
  changed()
  pollTime = 0.25
  log('I', 'ACNG', 'FFB ' .. name .. '=' .. tostring(value))
  return value == nil and 'stock' or value
end
-- Per-car FFB strength (multiplies gain) for a vehicle model; nil model = the player's car.
local function setCarGain(model, value)
  if not config then return false end
  if model == nil then model = vehicleModel(be:getPlayerVehicle(0)) end
  if type(model) ~= 'string' or model == '' then return false end
  if type(value) ~= 'number' or value ~= value or value < 0 or value > CAR_GAIN_MAX then return false end
  config.ffb_settings = config.ffb_settings or {}
  config.ffb_settings.car_gain = config.ffb_settings.car_gain or {}
  config.ffb_settings.car_gain[model] = value
  changed()
  pollTime = 0.25
  log('I', 'ACNG', 'FFB car_gain ' .. model .. '=' .. value)
  return value
end
local function setTelemetryEnabled(value)
  config.telemetry.enabled = value == true
  changed()
  if not config.telemetry.enabled then stopVehicle() end
end
local function setControlEnabled(value)
  if not config then return false end
  if value==true and not config.control_panel_initialized then
    local picked=feature('tire_temperature') or feature('tire_wear') or feature('abs') or feature('tc') or feature('ffb')
    if not picked then config.features.tire_temperature=true;config.features.tire_wear=true end
    config.control_panel_initialized=true
  end
  if value~=true then setTelemetryEnabled(false) end
  return setEnabled(value)
end
local function onUpdate(dtReal)
  if settingsDirty then
    settingsTime=settingsTime+dtReal
    if settingsTime>=(settingsError and 5 or 0.5) then settingsTime=0;saveSettings() end
  end
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
  if assistsWanted() then
    local parts = assistsConfigure()
    if id ~= assistsId then
      stopAssists()
      if veh then
        veh:queueLuaCommand(ASSISTS_LOAD .. '; ' .. parts)
        assistsId, assistsParts = id, parts
      end
    elseif parts ~= assistsParts and veh then
      veh:queueLuaCommand(parts)
      assistsParts = parts
    end
  end
  if ffbWanted() then
    local parts = ffbConfigure(vehicleModel(veh))
    if id ~= ffbId then
      stopFFB()
      if veh then
        veh:queueLuaCommand(FFB_LOAD .. '; ' .. parts)
        ffbId, ffbParts = id, parts
      end
    elseif parts ~= ffbParts and veh then
      veh:queueLuaCommand(parts)
      ffbParts = parts
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
  if id == assistsId then
    assistsId, assistsParts = nil, nil
    pollTime = 0.25
  end
  if id == ffbId then
    ffbId, ffbParts = nil, nil
    pollTime = 0.25
  end
end
local function getStatus()
  local model = vehicleModel(be:getPlayerVehicle(0))
  local ffb = {car_model=model, car_gain=carGain(model)}
  for _, name in ipairs(FFB_NAMES) do ffb[name] = ffbSetting(name) end
  return {schema_version=1, enabled=config and config.enabled or false,
    control_panel_initialized=config and config.control_panel_initialized==true or false,
    settings_error=settingsError, settings_pending=settingsDirty,
    telemetry_enabled=config and config.telemetry.enabled or false,
    attached_vehicle_id=attachedId, attached_capture_id=attachedCaptureId,
    performance_timer_vehicle_id=perfId, lap_timer_vehicle_id=perfId,
    tires_vehicle_id=tiresId, assists_vehicle_id=assistsId, ffb_vehicle_id=ffbId,
    features={tire_temperature=feature('tire_temperature'), tire_wear=feature('tire_wear'),
      abs=feature('abs'), tc=feature('tc'), ffb=feature('ffb'), race_sessions=feature('race_sessions')},
    assist_levels={abs=assistLevel('abs'), tc=assistLevel('tc')}, ffb_settings=ffb,
    implemented_physics_features={'tire_temperature', 'tire_wear', 'abs', 'tc', 'ffb'}, physics_writes=physicsWrites()}
end
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = function() if settingsDirty then saveSettings() end;stopAll() end
M.onClientEndMission = stopAll
M.onUpdate = onUpdate
M.onVehicleSpawned = onVehicleSpawned
M.setEnabled = setEnabled
M.setControlEnabled = setControlEnabled
M.saveSettings = saveSettings
M.setTelemetryEnabled = setTelemetryEnabled
M.setFeature = setFeature
M.setAssistLevel = setAssistLevel
M.setFFBSetting = setFFBSetting
M.setCarGain = setCarGain
M.getStatus = getStatus
return M
