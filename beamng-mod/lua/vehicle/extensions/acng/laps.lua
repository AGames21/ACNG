-- ACNG lap timer in the vehicle VM. Read-only: follows the vehicle's own
-- position over simulation time and never writes controls or forces.
local M = {}

local HALF_WIDTH_M = 15     -- a crossing counts within this distance of the line point
local MIN_LAP_S = 5         -- re-crossings sooner than this are wobble on the line, not laps
local MIN_LAP_M = 50
local TELEPORT_M = 30       -- one step longer than this is a teleport, not driving
local TRACE_STEP_M = 2      -- best-lap trace resolution for the live delta
local SECTORS = 3
local HISTORY = 5
local SEND_INTERVAL_S = 0.1

local function number(value)
  if type(value) == 'number' and value == value and math.abs(value) < math.huge then return value end
end

local function newState()
  return {time_s=0, pos=nil, line=nil, lap=nil, laps=0, last=nil, best=nil, best_trace=nil,
    best_sectors={}, ref_length_m=nil, history={}, note=nil}
end

local function clearLaps(state)
  state.lap, state.laps, state.last, state.best, state.best_trace = nil, 0, nil, nil, nil
  state.best_sectors, state.ref_length_m, state.history, state.note = {}, nil, {}, nil
end

-- Start/finish gate through (x, y), crossed in the forward direction (fx, fy).
-- A new line is a new track, so earlier laps are cleared.
local function setLine(state, x, y, fx, fy)
  x, y, fx, fy = number(x), number(y), number(fx), number(fy)
  if not (x and y and fx and fy) then return false end
  local len = math.sqrt(fx * fx + fy * fy)
  if len < 1e-6 then return false end
  clearLaps(state)
  state.line = {x=x, y=y, nx=fx / len, ny=fy / len}
  return true
end

-- Lap time at distance d along a recorded trace, or nil beyond its end.
local function timeAt(trace, d)
  local ds, ts = trace.d, trace.t
  local n = #ds
  if n == 0 or d > ds[n] then return nil end
  if d <= ds[1] then return ts[1] end
  local lo, hi = 1, n
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if ds[mid] <= d then lo = mid else hi = mid end
  end
  local span = ds[hi] - ds[lo]
  if span <= 0 then return ts[hi] end
  return ts[lo] + (ts[hi] - ts[lo]) * (d - ds[lo]) / span
end

local function newLap(start)
  return {start_s=start, time_s=0, distance_m=0, trace={d={0}, t={0}}, next_sample=TRACE_STEP_M, splits={}}
end

-- Moves the lap to lap time t with dd more distance. Position is linear within
-- a step, so distance and time are proportional inside it.
local function advance(state, lap, t, dd)
  local t0, d0 = lap.time_s, lap.distance_m
  local d1 = d0 + dd
  local function timeAtD(d) return dd > 0 and t0 + (t - t0) * (d - d0) / dd or t end
  while lap.next_sample <= d1 do
    local n = #lap.trace.d + 1
    lap.trace.d[n], lap.trace.t[n] = lap.next_sample, timeAtD(lap.next_sample)
    lap.next_sample = lap.next_sample + TRACE_STEP_M
  end
  if state.ref_length_m then
    while #lap.splits < SECTORS - 1 do
      local boundary = state.ref_length_m * (#lap.splits + 1) / SECTORS
      if d1 < boundary then break end
      lap.splits[#lap.splits + 1] = timeAtD(boundary)
    end
  end
  lap.time_s, lap.distance_m = t, d1
end

local function sectorsOf(splits, total)
  if #splits < SECTORS - 1 then return nil end
  local sectors, prev = {}, 0
  for k = 1, SECTORS - 1 do sectors[k], prev = splits[k] - prev, splits[k] end
  sectors[SECTORS] = total - prev
  return sectors
end

local function finishLap(state, lapTime)
  local lap = state.lap
  local n = #lap.trace.d
  if lap.trace.d[n] < lap.distance_m then lap.trace.d[n + 1], lap.trace.t[n + 1] = lap.distance_m, lapTime end
  if not state.ref_length_m then
    -- The first full lap defines the sector boundaries; split it from its own trace.
    state.ref_length_m = lap.distance_m
    for k = 1, SECTORS - 1 do lap.splits[k] = timeAt(lap.trace, state.ref_length_m * k / SECTORS) end
  end
  local sectors = sectorsOf(lap.splits, lapTime)
  state.laps = state.laps + 1
  local result = {lap=state.laps, time_s=lapTime, distance_m=lap.distance_m, sectors=sectors}
  state.last = result
  if sectors then
    for k = 1, SECTORS do
      if not state.best_sectors[k] or sectors[k] < state.best_sectors[k] then state.best_sectors[k] = sectors[k] end
    end
  end
  if not state.best or lapTime < state.best.time_s then state.best, state.best_trace = result, lap.trace end
  table.insert(state.history, 1, result)
  if #state.history > HISTORY then table.remove(state.history) end
end

-- Advances one simulation step to position (x, y, z). Line crossings are
-- interpolated within the step. Returns true when a lap starts, ends or is abandoned.
local function step(state, dt, x, y, z)
  dt, x, y, z = number(dt), number(x), number(y), number(z) or 0
  if not dt or dt <= 0 or not x or not y then return false end
  local prev, t0 = state.pos, state.time_s
  state.time_s, state.pos = t0 + dt, {x=x, y=y, z=z}
  if not prev or not state.line then return false end
  local dx, dy, dz = x - prev.x, y - prev.y, z - prev.z
  local seg = math.sqrt(dx * dx + dy * dy + dz * dz)
  local line, lap = state.line, state.lap
  if seg > TELEPORT_M then
    if not lap then return false end
    state.lap, state.note = nil, 'teleport'
    return true
  end
  local s0 = (prev.x - line.x) * line.nx + (prev.y - line.y) * line.ny
  local s1 = (x - line.x) * line.nx + (y - line.y) * line.ny
  local f
  if (s0 < 0) ~= (s1 < 0) then
    f = s0 / (s0 - s1)
    local cx, cy = prev.x + dx * f - line.x, prev.y + dy * f - line.y
    if math.abs(cy * line.nx - cx * line.ny) > HALF_WIDTH_M then f = nil end
  end
  if f and s1 < 0 then
    -- Crossing the line backwards abandons the lap in progress.
    if not lap then return false end
    state.lap, state.note = nil, 'reversed'
    return true
  end
  if f and lap and (t0 + f * dt - lap.start_s < MIN_LAP_S or lap.distance_m + seg * f < MIN_LAP_M) then f = nil end
  if not f then
    if lap then advance(state, lap, state.time_s - lap.start_s, seg) end
    return false
  end
  local crossing = t0 + f * dt
  if lap then
    advance(state, lap, crossing - lap.start_s, seg * f)
    finishLap(state, crossing - lap.start_s)
  end
  state.lap, state.note = newLap(crossing), nil
  advance(state, state.lap, state.time_s - crossing, seg * (1 - f))
  return true
end

local function snapshot(state)
  local lap = state.lap
  local delta, live, optimal, prev
  if lap then
    if state.best_trace then
      local bestTime = timeAt(state.best_trace, lap.distance_m)
      if bestTime then delta = lap.time_s - bestTime end
    end
    live, prev = {}, 0
    for k = 1, #lap.splits do live[k], prev = lap.splits[k] - prev, lap.splits[k] end
  end
  if #state.best_sectors == SECTORS then
    optimal = 0
    for k = 1, SECTORS do optimal = optimal + state.best_sectors[k] end
  end
  return {schema_version=1, mode=not state.line and 'no_line' or lap and 'lap' or 'out_lap', note=state.note,
    lap_number=lap and state.laps + 1 or nil, current_s=lap and lap.time_s or nil,
    distance_m=lap and lap.distance_m or nil, delta_s=delta, sectors_live=live,
    last=state.last, best=state.best, best_sectors=state.best_sectors, optimal_s=optimal,
    laps=state.laps, history=state.history, ref_length_m=state.ref_length_m}
end

-- Vehicle extension wiring.
local state = newState()
local sinceSend = 0
local function send()
  sinceSend = 0
  guihooks.trigger('ACNGLaps', snapshot(state))
end
local function updateGFX(dt)
  local p = obj:getPosition()
  if step(state, dt, p and p.x, p and p.y, p and p.z) then return send() end
  sinceSend = sinceSend + (number(dt) or 0)
  if sinceSend >= SEND_INTERVAL_S then send() end
end
local function setLineHere()
  local p, d = obj:getPosition(), obj:getDirectionVector()
  if not (p and d and setLine(state, p.x, p.y, d.x, d.y)) then return false end
  -- The car is on the line now; its next forward crossing starts the first lap.
  state.pos = {x=p.x, y=p.y, z=p.z}
  send()
  return true
end
local function onReset()
  -- A reset moves the car; the lap in progress cannot be completed fairly.
  if state.lap then state.note = 'reset' end
  state.pos, state.lap = nil, nil
  send()
end
local function clear()
  clearLaps(state)
  send()
end
local function onExtensionLoaded()
  log('I', 'ACNG', 'LAP_TIMER_LOADED physics_writes=0')
end
local function onExtensionUnloaded()
  guihooks.trigger('ACNGLaps', {schema_version=1, mode='off'})
end

M.newState = newState
M.setLine = setLine
M.step = step
M.snapshot = snapshot
M.timeAt = timeAt
M.updateGFX = updateGFX
M.setLineHere = setLineHere
M.onReset = onReset
M.clear = clear
M.getSnapshot = function() return snapshot(state) end
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
