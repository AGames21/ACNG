-- ACNG performance timer in the vehicle VM. Read-only: integrates the native
-- ground speed over simulation time and never writes controls or forces.
local M = {}

local MPH, KMH = 0.44704, 1 / 3.6
local ARM_SPEED = 0.05        -- m/s; at rest, ready to time a launch
local START_SPEED = 0.15      -- m/s; first movement from rest starts a launch run
local BRAKE_END_SPEED = 0.3   -- m/s; braking runs end here (avoids the creeping stop tail)
local QUARTER_MILE_M = 402.336
local RUN_LIMIT_S = 120
local SEND_INTERVAL_S = 0.1
local LAUNCH = {
  {key='mph_0_60', speed_m_s=60 * MPH}, {key='kmh_0_100', speed_m_s=100 * KMH},
  {key='mph_0_100', speed_m_s=100 * MPH}, {key='kmh_0_200', speed_m_s=200 * KMH}}
local BRAKING = {{key='mph_60_0', speed_m_s=60 * MPH}, {key='kmh_100_0', speed_m_s=100 * KMH}}

local function number(value)
  if type(value) == 'number' and value == value and math.abs(value) < math.huge then return value end
end

local function newState()
  return {mode='rolling', time_s=0, speed_m_s=nil, run=nil, stops={}, run_id=0, last={}, best={}}
end

local function record(state, key, result, metric)
  state.last[key] = result
  local best = state.best[key]
  if not best or result[metric] < best[metric] then state.best[key] = result end
end

-- Advances one simulation step. Crossings are interpolated within the step so
-- results do not depend on the graphics frame rate. Returns true on a new result.
local function step(state, dt, speed, brake, throttle)
  dt, speed = number(dt), number(speed)
  if not dt or dt <= 0 or not speed then return false end
  brake, throttle = number(brake) or 0, number(throttle) or 0
  local prev, t0 = state.speed_m_s, state.time_s
  state.time_s, state.speed_m_s = t0 + dt, speed
  if not prev then
    state.mode = speed < ARM_SPEED and 'armed' or 'rolling'
    return false
  end
  local changed = false
  local function cross(target) return (target - prev) / (speed - prev) end
  local function area(fraction) return (prev + (prev + (speed - prev) * fraction)) * 0.5 * dt * fraction end
  -- Fraction of this step at which area() reaches distance; inverse of area().
  local function reach(distance)
    local a, b = 0.5 * dt * (speed - prev), prev * dt
    if math.abs(a) < 1e-12 then return b > 0 and distance / b or 1 end
    return (-b + math.sqrt(math.max(0, b * b + 4 * a * distance))) / (2 * a)
  end

  -- Launch timing from rest.
  if state.mode == 'armed' and speed >= START_SPEED then
    local f = cross(START_SPEED)
    state.run_id = state.run_id + 1
    state.run = {start_s=t0 + f * dt, distance_m=area(1) - area(f), done={}}
    state.mode = 'launch'
  elseif state.mode == 'launch' then
    local run, before = state.run, state.run.distance_m
    run.distance_m = before + area(1)
    for _, target in ipairs(LAUNCH) do
      if not run.done[target.key] and prev < target.speed_m_s and speed >= target.speed_m_s then
        run.done[target.key] = true
        record(state, target.key, {time_s=t0 + cross(target.speed_m_s) * dt - run.start_s, run_id=state.run_id}, 'time_s')
        changed = true
      end
    end
    if not run.done.quarter_mile and run.distance_m >= QUARTER_MILE_M then
      local f = reach(QUARTER_MILE_M - before)
      run.done.quarter_mile = true
      record(state, 'quarter_mile', {time_s=t0 + f * dt - run.start_s,
        trap_speed_m_s=prev + (speed - prev) * f, run_id=state.run_id}, 'time_s')
      changed = true
    end
    local finished = run.done.quarter_mile
    for _, target in ipairs(LAUNCH) do finished = finished and run.done[target.key] end
    if finished or state.time_s - run.start_s > RUN_LIMIT_S then
      state.mode, state.run = 'rolling', nil
    end
  end

  -- Braking distance from each threshold to a stop, measured independently of launches.
  for _, target in ipairs(BRAKING) do
    local open = state.stops[target.key]
    if open then
      if throttle > 0.2 or speed > target.speed_m_s + 1 then
        state.stops[target.key] = nil
      elseif speed < BRAKE_END_SPEED then
        local f = cross(BRAKE_END_SPEED)
        record(state, target.key, {distance_m=open.distance_m + area(f), time_s=t0 + f * dt - open.start_s}, 'distance_m')
        state.stops[target.key] = nil
        changed = true
      else
        open.distance_m = open.distance_m + area(1)
      end
    elseif brake >= 0.1 and prev >= target.speed_m_s and speed < target.speed_m_s then
      local f = cross(target.speed_m_s)
      state.stops[target.key] = {start_s=t0 + f * dt, distance_m=area(1) - area(f)}
    end
  end

  if speed < ARM_SPEED and state.mode ~= 'armed' then
    state.mode, state.run = 'armed', nil
    changed = true
  end
  return changed
end

local function snapshot(state)
  local run = state.run
  return {schema_version=1, mode=state.mode, run_id=state.run_id, speed_m_s=state.speed_m_s,
    run_time_s=run and state.time_s - run.start_s or nil, run_distance_m=run and run.distance_m or nil,
    last=state.last, best=state.best}
end

-- Vehicle extension wiring.
local state = newState()
local sinceSend = 0
local function send()
  sinceSend = 0
  guihooks.trigger('ACNGPerf', snapshot(state))
end
local function updateGFX(dt)
  local vel = obj:getVelocity()
  local e = electrics.values
  if step(state, dt, vel and vel:length(), e.brake, e.throttle) then return send() end
  sinceSend = sinceSend + (number(dt) or 0)
  if sinceSend >= SEND_INTERVAL_S then send() end
end
local function onReset()
  -- A reset ends any run in progress; keep this vehicle's session results.
  state.speed_m_s, state.run, state.stops = nil, nil, {}
  send()
end
local function clear()
  state = newState()
  send()
end
local function onExtensionLoaded()
  log('I', 'ACNG', 'PERF_TIMER_LOADED physics_writes=0')
end
local function onExtensionUnloaded()
  guihooks.trigger('ACNGPerf', {schema_version=1, mode='off'})
end

M.newState = newState
M.step = step
M.snapshot = snapshot
M.updateGFX = updateGFX
M.onReset = onReset
M.clear = clear
M.getSnapshot = function() return snapshot(state) end
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
