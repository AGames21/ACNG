-- Passive telemetry in the vehicle VM. No tire, beam, controller or force writes.
local M = {}
local udp
local interval = 0.02
local elapsed = 0
local simTime = 0
local seq = 0
local generation = 0
local function number(value)
  if type(value) == 'number' and value == value and math.abs(value) < math.huge then return value end
end
local function read(method, ...)
  if not obj[method] then return nil end
  local ok, value = pcall(obj[method], obj, ...)
  if ok then return number(value) end
end
local function stop()
  if udp then udp:close() end
  udp = nil
end
local function start(rate, port)
  stop()
  rate = math.max(1, math.min(100, tonumber(rate) or 50))
  port = tonumber(port) or 44443
  if port < 1024 or port > 65535 or port ~= math.floor(port) then return false end
  local socket = require('socket')
  udp = socket.udp()
  udp:settimeout(0)
  local ok = udp:setpeername('127.0.0.1', port)
  if not ok then stop(); return false end
  interval, elapsed, simTime, seq = 1 / rate, 0, 0, 0
  generation = generation + 1
  log('I', 'ACNG', 'TELEMETRY_STARTED passive=true rate=' .. rate)
  return true
end
local function updateGFX(dt)
  if not udp then return end
  simTime = simTime + dt
  elapsed = elapsed + dt
  if elapsed < interval then return end
  -- Never synthesize catch-up samples: stamp the actual graphics observation.
  elapsed = elapsed % interval
  seq = seq + 1
  local e = electrics.values
  local vel, pos = obj:getVelocity(), obj:getPosition()
  local wheelRows = {}
  for id, wd in pairs(wheels.wheels or {}) do
    local group = wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
    wheelRows[#wheelRows+1] = {
      id=id, name=wd.name, broken=wd.isBroken == true, deflated=wd.isTireDeflated == true,
      angular_velocity_rad_s=number(wd.angularVelocity), speed_m_s=number(wd.wheelSpeed),
      radius_m=number(wd.dynamicRadius or wd.radius), load_raw_n=number(wd.downForceRaw),
      slip_velocity_native=number(wd.lastSlip), side_slip_velocity_native=number(wd.lastSideSlip),
      slip_energy_native=number(wd.slipEnergy),
      tire_average_temperature_native=read('getWheelAvgTemperature', wd.wheelID),
      tire_core_temperature_native=read('getWheelCoreTemperature', wd.wheelID),
      tire_pressure_absolute_pa=group and read('getGroupPressure', group) or nil
    }
  end
  local row = {schema_version=1, source='beamng', sequence=seq, generation=generation,
    vehicle_id=obj:getId(), sim_time_s=simTime, sample_dt_s=dt,
    speed_m_s=number(vel:length()), position_m={pos.x,pos.y,pos.z},
    velocity_world_m_s={vel.x,vel.y,vel.z},
    acceleration_sensor_native={number(sensors.gx),number(sensors.gy),number(sensors.gz)},
    yaw_rate_native_rad_s=read('getYawAngularVelocity'),
    throttle=number(e.throttle), brake=number(e.brake), steering_input=number(e.steering_input),
    rpm=number(e.rpm), gear=number(e.gearIndex), wheels=wheelRows}
  local ok, payload = pcall(jsonEncode, row)
  if ok and #payload < 60000 then udp:send(payload) end
end
local function onReset()
  generation, elapsed, simTime, seq = generation + 1, 0, 0, 0
end
M.start = start
M.stop = stop
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionUnloaded = stop
return M
