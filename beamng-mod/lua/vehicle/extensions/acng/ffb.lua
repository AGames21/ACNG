-- ACNG AC-style force feedback in the vehicle VM. BeamNG's own steering force is kept:
-- hydros.lua turns the steering rack's resistance into a wheel force, smooths it, then
-- compresses and limits it for the wheel. ACNG only changes what hydros already exposes:
--   gain       scales hydros.wheelFFBForceCoef and wheelFFBForceCoefLowSpeed (the same two
--              fields BeamNG's own inputTests.lua scales), so everything grows together
--   filter     optional smoothing (nil keeps the player's own BeamNG smoothing setting)
--   min force  lifts small forces so a weak wheel does not feel dead around the centre
--   kerb, road and slip feel, added as an external force inside the FFB calculation
-- Minimum force and the effects go through hydros.setExternalForce, set at physics rate
-- from hydros.testHook (called every physics step just before the FFB calculation, with
-- the same rack positions the stock force is made from), so the stock force is known
-- exactly and no feedback loop is built on last frame's output. Unloading puts back the
-- saved coefficients and smoothing exactly, clears the external force and the hook.
local M = {}

local FFMAX = 10            -- hydros' force scale (forceAtWheel runs -FFMAX to FFMAX)
local REF_COEF = 200        -- BeamNG's default FFB strength (bindings.lua forceCoef)
local SEND_INTERVAL_S = 0.1
local CHECK_INTERVAL_S = 0.25
local TAU = 2 * math.pi

-- Setting ranges. gain and the effect levels are AC-style multipliers (1 = 100 %).
M.GAIN_MAX = 2
M.MIN_FORCE_MAX = 0.3       -- fraction of the wheel's force limit
M.EFFECT_MAX = 2
-- filter 0..1 maps onto BeamNG's smoothing setting 0..FILTER_SMOOTHING_MAX; BeamNG's
-- default smoothing 150 is filter 0.5.
M.FILTER_SMOOTHING_MAX = 300
-- Minimum force fades in over the first MIN_FORCE_RAMP of stock force, so there is no
-- step at the centre (at most 1 + m*limit/ramp times the stock centre slope).
M.MIN_FORCE_RAMP = 0.5
-- Effects, in forceAtWheel units at 100 %, before gain. hydros' smoother (an exponential
-- filter, about 26 ms at the default smoothing) damps fast vibrations, so the kerb and
-- slip buzz stay in the 6-15 Hz band a wheel can still pass through it.
M.KERB_AMP = 1.0
M.KERB_SPACING_M = 1.5      -- kerb ridge spacing used for the buzz frequency
M.KERB_MIN_HZ = 6
M.KERB_MAX_HZ = 15
M.KERB_MIN_SPEED = 2        -- m/s
M.KERB_MATERIAL = 29        -- RUMBLE_STRIP (particles.json; sounds.lua uses it for kerbs)
M.ROAD_GAIN = 1 / 4000      -- force units per newton of sudden left-right front load change
M.ROAD_TAU_S = 0.08         -- high-pass time constant: only quick load changes are felt
M.ROAD_MAX = 1.5
M.SLIP_START = 1.5          -- front tire slip speed (m/s) where the slip buzz starts
M.SLIP_FULL = 5             -- slip speed for full buzz
M.SLIP_AMP = 0.6
M.SLIP_HZ = 10
M.ATTACK_S = 0.03           -- effect amplitude smoothing, so effects never step
M.CLIP_TAU_S = 2            -- clipping share is averaged over about this long

local settings = {gain=1, min_force=0, filter=nil, kerb=0, road=0, slip=0}
local stock             -- {coef, low, ffb} saved on load (ffb = hydros.getFFBConfig())
local written = {}      -- values ACNG last wrote: coef, low, smoothing
local filterApplied     -- smoothing value ACNG has written, or nil
local hookOwned = false
local vcoef = 1.2       -- hydros' vehicleFFBForceCoef: v.data.input.FFBcoef * 1.2
local fronts = {}       -- runtime front wheel indices in wheels.wheels
local eff = {kerbA=0, kerbHz=M.KERB_MIN_HZ, road=0, slipA=0, kerbOn=false, slip=0}
local roadHP = {y=0, x=nil}
local kerbPhase, slipPhase = 0, 0
local lastExtra = 0
local clip = {share=0}
local sinceSend, sinceCheck = 0, 0

local function num(x) return type(x) == 'number' and x == x and x > -math.huge and x < math.huge end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function sgn(x) return x > 0 and 1 or (x < 0 and -1 or 0) end

-- Pure helpers (offline tests use these).

-- Extra force for minimum force m on a stock force fs, with the wheel's limit L.
local function minForceExtra(fs, m, limit, ramp)
  if not (num(fs) and num(m) and num(limit)) or m <= 0 or limit <= 0 then return 0 end
  local a = math.abs(fs)
  if a >= limit then return 0 end
  local s = math.min(1, a / math.max(ramp or M.MIN_FORCE_RAMP, 1e-6))
  return sgn(fs) * s * m * (limit - a)
end

-- Kerb buzz frequency at a road speed.
local function kerbHz(speed)
  if not num(speed) then return M.KERB_MIN_HZ end
  return clamp(math.abs(speed) / M.KERB_SPACING_M, M.KERB_MIN_HZ, M.KERB_MAX_HZ)
end

-- Slip buzz amount 0..1 for a front tire slip speed.
local function slipAmount(slip)
  if not num(slip) then return 0 end
  return clamp((slip - M.SLIP_START) / (M.SLIP_FULL - M.SLIP_START), 0, 1)
end

-- One step of the road feel high-pass on the front left-right load difference x.
local function roadStep(state, x, dt)
  if not num(x) or not num(dt) or dt <= 0 then return state.y end
  if state.x == nil then state.x = x; state.y = 0; return 0 end
  local a = M.ROAD_TAU_S / (M.ROAD_TAU_S + dt)
  state.y = a * (state.y + x - state.x)
  state.x = x
  return state.y
end

local function approach(cur, target, dt)
  local k = math.min(1, dt / M.ATTACK_S)
  return cur + (target - cur) * k
end

-- Settings from acng_core; anything missing or out of range falls back to neutral.
local function sanitize(gain, minForce, filter, kerb, road, slip)
  return {gain=num(gain) and clamp(gain, 0, M.GAIN_MAX) or 1,
    min_force=num(minForce) and clamp(minForce, 0, M.MIN_FORCE_MAX) or 0,
    filter=num(filter) and clamp(filter, 0, 1) or nil,
    kerb=num(kerb) and clamp(kerb, 0, M.EFFECT_MAX) or 0,
    road=num(road) and clamp(road, 0, M.EFFECT_MAX) or 0,
    slip=num(slip) and clamp(slip, 0, M.EFFECT_MAX) or 0}
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

local function saveStock()
  stock = {coef=hydros.wheelFFBForceCoef, low=hydros.wheelFFBForceCoefLowSpeed, ffb=copy(hydros.getFFBConfig())}
end

local function effectsWanted()
  return settings.min_force > 0 or settings.kerb > 0 or settings.road > 0 or settings.slip > 0
end

-- Physics-rate hook: hydros calls it with the averaged sim and actual rack positions; the
-- stock force at the wheel is coefCurrent * vcoef * (sim - actual) * powerSteering.
local function hook(dtSim, simWheelPos, hydroPos)
  local coefCur = hydros.wheelFFBForceCoefCurrent
  if not num(coefCur) or coefCur < 1e-6 or not num(simWheelPos) or not num(hydroPos) then
    lastExtra = 0
    hydros.setExternalForce(0)
    return true, hydroPos
  end
  local fs = coefCur * vcoef * (simWheelPos - hydroPos) * (hydros.wheelPowerSteeringCoef or 1)
  local extra = minForceExtra(fs, settings.min_force, hydros.wheelFFBForceLimit or FFMAX, M.MIN_FORCE_RAMP)
  if eff.kerbA > 0 then
    kerbPhase = (kerbPhase + TAU * eff.kerbHz * dtSim) % TAU
    extra = extra + eff.kerbA * math.sin(kerbPhase)
  end
  if eff.slipA > 0 then
    slipPhase = (slipPhase + TAU * M.SLIP_HZ * dtSim) % TAU
    extra = extra + eff.slipA * math.sin(slipPhase)
  end
  extra = extra + eff.road
  lastExtra = extra
  hydros.setExternalForce(extra / coefCur)
  return true, hydroPos
end

local function installHook()
  if hookOwned then return true end
  if hydros.testHook ~= nil then return false end -- someone else (BeamNG inputTests) owns it
  hydros.testHook = hook
  hookOwned = true
  return true
end

local function removeHook()
  if hookOwned and hydros.testHook == hook then hydros.testHook = nil end
  hookOwned = false
  lastExtra = 0
  hydros.setExternalForce(0)
end

local function findFronts()
  fronts = {}
  local list = wheels and wheels.wheels
  if not list then return end
  for i = 0, tableSizeC(list) - 1 do
    local wd = list[i]
    if wd and type(wd.name) == 'string' and wd.name:sub(1, 1) == 'F' then fronts[#fronts + 1] = i end
  end
end

-- Effect targets from this frame's wheel data (wheels.lua refreshes it every frame).
local function updateEffects(dt)
  local list = wheels and wheels.wheels
  local scale = settings.gain * (stock and stock.coef or REF_COEF) / REF_COEF
  local speed = math.abs(electrics.values.wheelspeed or electrics.values.airspeed or 0)
  local kerbOn, maxSlip, loads = false, 0, {}
  if list then
    for _, i in ipairs(fronts) do
      local wd = list[i]
      if wd and not wd.isBroken then
        if wd.contactMaterialID1 == M.KERB_MATERIAL or wd.contactMaterialID2 == M.KERB_MATERIAL then kerbOn = true end
        if num(wd.lastSlip) then maxSlip = math.max(maxSlip, math.abs(wd.lastSlip)) end
        loads[#loads + 1] = num(wd.downForceRaw) and wd.downForceRaw or 0
      end
    end
  end
  kerbOn = kerbOn and speed > M.KERB_MIN_SPEED
  local kerbT = kerbOn and M.KERB_AMP * settings.kerb * scale or 0
  local slipT = M.SLIP_AMP * settings.slip * scale * slipAmount(maxSlip)
  local roadT = 0
  if #loads >= 2 and settings.road > 0 then
    roadT = clamp(roadStep(roadHP, loads[1] - loads[2], dt) * M.ROAD_GAIN * settings.road * scale, -M.ROAD_MAX, M.ROAD_MAX)
  else
    roadHP.x, roadHP.y = nil, 0
  end
  eff.kerbA = approach(eff.kerbA, kerbT, dt)
  eff.slipA = approach(eff.slipA, slipT, dt)
  eff.road = approach(eff.road, roadT, dt)
  eff.kerbHz = kerbHz(speed)
  eff.kerbOn, eff.slip = kerbOn, maxSlip
end

local function writeCoefs()
  written.coef = stock.coef * settings.gain
  written.low = stock.low * settings.gain
  hydros.wheelFFBForceCoef = written.coef
  hydros.wheelFFBForceCoefLowSpeed = written.low
end

local function writeFilter()
  local want = settings.filter and settings.filter * M.FILTER_SMOOTHING_MAX or nil
  if want == filterApplied then return end
  local p = copy(stock.ffb)
  p.forceCoef = stock.coef
  if want then p.smoothing = want end
  hydros.setFFBConfig(p)
  filterApplied = want
  written.smoothing = hydros.getFFBConfig().smoothing
end

local function apply()
  if not stock then return end
  writeFilter()
  writeCoefs()
  if effectsWanted() then installHook() else removeHook() end
end

-- The player can change BeamNG's FFB settings while ACNG runs (hydros.onFFBConfigChanged
-- writes the new strength and smoothing). Take those as the new stock and reapply on top.
local function followStockChanges()
  if not stock then return end
  local changed = false
  if math.abs(hydros.wheelFFBForceCoef - written.coef) > 1e-9 then stock.coef = hydros.wheelFFBForceCoef; changed = true end
  if math.abs(hydros.wheelFFBForceCoefLowSpeed - written.low) > 1e-9 then stock.low = hydros.wheelFFBForceCoefLowSpeed; changed = true end
  if not filterApplied then
    -- ACNG is not touching smoothing: the live config is the stock one.
    stock.ffb = copy(hydros.getFFBConfig())
  elseif math.abs(hydros.getFFBConfig().smoothing - written.smoothing) > 1e-6 then
    stock.ffb = copy(hydros.getFFBConfig())
    filterApplied = nil
    changed = true
  end
  if changed then
    log('I', 'ACNG', 'FFB_STOCK_CHANGED coef=' .. tostring(stock.coef))
    apply()
  end
end

local function restore()
  if not stock then return 0 end
  removeHook()
  if filterApplied then
    local p = copy(stock.ffb)
    p.forceCoef = stock.coef
    hydros.setFFBConfig(p)
    filterApplied = nil
  end
  hydros.wheelFFBForceCoef = stock.coef
  hydros.wheelFFBForceCoefLowSpeed = stock.low
  return 1
end

local function round(x, step)
  return num(x) and math.floor(x / step + 0.5) * step or nil
end

local function ffbId()
  return hydros.getFFBID and hydros.getFFBID() or -1
end

local function snapshot()
  return {schema_version=1, mode='on', wheel=ffbId() >= 0, ffb_id=ffbId(),
    gain=settings.gain, min_force=settings.min_force, filter=settings.filter,
    kerb=settings.kerb, road=settings.road, slip=settings.slip,
    hook=effectsWanted() and (hookOwned and 'acng' or 'busy') or 'off',
    stock_coef=stock and stock.coef, coef=hydros.wheelFFBForceCoef,
    smoothing=round(hydros.getFFBConfig().smoothing, 0.01),
    force=round(hydros.forceAtDriverNorm, 0.001), limit=round(hydros.curForceLimitNorm, 0.001),
    clip=round(clip.share, 0.001), kerb_on=eff.kerbOn, front_slip=round(eff.slip, 0.01),
    extra=round(lastExtra, 0.001)}
end

local function updateGFX(dt)
  if not stock then return end
  dt = num(dt) and dt or 0
  sinceCheck = sinceCheck + dt
  if sinceCheck >= CHECK_INTERVAL_S then sinceCheck = 0; followStockChanges() end
  if hookOwned then updateEffects(dt) end
  -- Clipping: the output sits at 95 % of the limit or more (deep in hydros' compression).
  local lim, f = hydros.curForceLimit or 0, math.abs(hydros.forceAtDriver or 0)
  local clipping = ffbId() >= 0 and lim > 0.5 and f >= 0.95 * lim
  if dt > 0 then clip.share = clip.share + ((clipping and 1 or 0) - clip.share) * math.min(1, dt / M.CLIP_TAU_S) end
  sinceSend = sinceSend + dt
  if sinceSend >= SEND_INTERVAL_S then
    sinceSend = 0
    guihooks.trigger('ACNGFFB', snapshot())
  end
end

local function onReset()
  eff.kerbA, eff.slipA, eff.road = 0, 0, 0
  roadHP.x, roadHP.y = nil, 0
  clip.share = 0
  findFronts()
end

local function onExtensionLoaded()
  if not hydros or not hydros.getFFBConfig then
    log('E', 'ACNG', 'FFB_UNAVAILABLE no hydros FFB on this vehicle')
    return false
  end
  vcoef = (v.data.input and num(v.data.input.FFBcoef) and v.data.input.FFBcoef or 1) * 1.2
  saveStock()
  written = {coef=stock.coef, low=stock.low}
  filterApplied = nil
  settings = sanitize()
  findFronts()
  sinceSend, sinceCheck = 0, 0
  log('I', 'ACNG', 'FFB_LOADED coef=' .. tostring(stock.coef) .. ' fronts=' .. #fronts .. ' wheel=' .. tostring(ffbId() >= 0))
end

-- acng_core calls this after loading and whenever a setting changes. gain already includes
-- the per-car strength.
local function configure(gain, minForce, filter, kerb, road, slip)
  if not stock then return false end
  settings = sanitize(gain, minForce, filter, kerb, road, slip)
  apply()
  log('I', 'ACNG', string.format('FFB_CONFIG gain=%.2f min=%.2f filter=%s kerb=%.2f road=%.2f slip=%.2f hook=%s',
    settings.gain, settings.min_force, tostring(settings.filter), settings.kerb, settings.road, settings.slip, tostring(hookOwned)))
  return true
end

local function onExtensionUnloaded()
  local n = restore()
  stock = nil
  log('I', 'ACNG', 'FFB_UNLOADED stock_restored=' .. n)
  guihooks.trigger('ACNGFFB', {schema_version=1, mode='off'})
end

-- Lab view of the raw state.
local function labState()
  return {stock=stock and {coef=stock.coef, low=stock.low, ffb=stock.ffb}, written=written,
    filter_applied=filterApplied, hook_owned=hookOwned, test_hook_is_ours=hydros.testHook == hook,
    eff={kerbA=eff.kerbA, slipA=eff.slipA, road=eff.road, kerbHz=eff.kerbHz, slip=eff.slip},
    extra=lastExtra, fronts=#fronts, vcoef=vcoef}
end

M.minForceExtra = minForceExtra
M.kerbHz = kerbHz
M.slipAmount = slipAmount
M.roadStep = roadStep
M.sanitize = sanitize
M.configure = configure
M.snapshot = snapshot
M.getSnapshot = snapshot
M.labState = labState
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
