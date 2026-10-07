-- ACNG AC-style driver assists (ABS and traction control levels) in the vehicle VM.
-- A001 probed ten stock cars: ABS is always the per-wheel ABS in wheels.lua (hasABS and
-- slipRatioTarget on each wheel rotator; the CMU's own ABS list was empty on every car),
-- and traction control is the drivingDynamics CMU (tractionControl supervisor plus the
-- motorTorqueControl and brakeControl components) on cars that have one. Cars without a
-- CMU (covet, pickup, bx, bolide, fullsize) have no traction control at all.
-- Levels drive those native systems. ABS: 0 = off, 1-3 = more intervention (a lower
-- slip target). TC: 0 = off, 1-3 = more intervention (a lower slip threshold). nil means
-- factory: the car's own values, untouched. On a car with no native TC, levels 1-3 run a
-- small ACNG controller through the engine's own throttle factor electric. Unloading
-- puts every saved stock value back. Brakes, tires, suspension and damage stay BeamNG's.
local M = {}

-- Wheel slip ratio the native ABS aims for, per level (stock cars use 0.12 to 0.2).
M.ABS_SLIP = {0.25, 0.18, 0.12}
-- Driven-wheel slip where TC starts cutting, per level (stock CMU cars use 0.12 to 0.3).
M.TC_SLIP = {0.25, 0.15, 0.08}
-- The CMU brakes a spinning wheel a little before it cuts torque; stock cars set the
-- brake threshold at about 0.8 of the torque threshold (0.10/0.12, 0.12/0.15, 0.2/0.3).
M.TC_BRAKE_RATIO = 0.8
-- ACNG's own TC (cars without a CMU): throttle factor 1 - GAIN * (slip - threshold),
-- never below MIN_FACTOR, recovering at RECOVER per second. The slip is smoothed over
-- FILTER_S so a one-frame spike (a shift, a bump) does not cut power; T006b's first
-- controller (gain 5, floor 0.05, no filter) slowed a bolide that barely spins. Slip is
-- measured against at least MIN_SPEED m/s so a standing start does not divide by zero.
M.TC_GAIN = 3
M.TC_MIN_FACTOR = 0.2
M.TC_RECOVER = 3
M.TC_FILTER_S = 0.05
M.TC_MIN_SPEED = 3

local SEND_INTERVAL_S = 0.1
local REAPPLY_DELAY_S = 0.25

local absLevel, tcLevel     -- nil = factory, 0 = off, 1-3 = level
local stock                 -- stock values saved on load
local tcMode = 'none'       -- 'cmu', 'acng' or 'none'
local own = {factor=1, slip=0, slipF=0, wrote=false}
local sinceSend = 0
local reapplyIn

local function level(value)
  if type(value) ~= 'number' or value ~= value then return nil end
  value = math.floor(value)
  if value < 0 or value > 3 then return nil end
  return value
end

local function firstController(typeName)
  local list = controller and controller.getControllersByType and controller.getControllersByType(typeName)
  return list and list[1]
end

local function cmuTC()
  local tc = firstController('drivingDynamics/supervisors/tractionControl')
  if not (tc and tc.setParameters and tc.getConfig) then return nil end
  return {tc=tc, motor=firstController('drivingDynamics/supervisors/components/motorTorqueControl'),
    brake=firstController('drivingDynamics/supervisors/components/brakeControl')}
end

-- {group = slipThreshold} from a component's tractionControl config.
local function groupThresholds(component)
  local out = {}
  local config = component and component.getConfig and component.getConfig()
  local groups = config and config.tractionControl and config.tractionControl.wheelGroupSettings
  if type(groups) == 'table' then
    for name, g in pairs(groups) do
      if type(g) == 'table' and type(g.slipThreshold) == 'number' then out[name] = g.slipThreshold end
    end
  end
  return out
end

local function setThresholds(component, values)
  if not (component and component.setParameters) then return end
  local p = {}
  for name, value in pairs(values) do p['tractionControl.wheelGroupSettings.' .. name .. '.slipThreshold'] = value end
  if next(p) then component.setParameters(p) end
end

local function eachRotator(fn)
  for i = 0, (wheels.wheelRotatorCount or 0) - 1 do
    local wd = wheels.wheelRotators[i]
    if wd then fn(i, wd) end
  end
end

local function saveStock()
  stock = {rotators={}}
  eachRotator(function(i, wd) stock.rotators[i] = {hasABS=wd.hasABS, slipRatioTarget=wd.slipRatioTarget} end)
  local parts = cmuTC()
  if parts then
    tcMode = 'cmu'
    stock.tc = {isEnabled=parts.tc.getConfig().isEnabled, motor=groupThresholds(parts.motor), brake=groupThresholds(parts.brake)}
  elseif firstController('esc') then
    tcMode = 'none'  -- the older esc controller owns the throttle factor; leave it alone
  else
    tcMode = 'acng'
  end
end

-- Re-pick each wheel's brake function (ABS or not) without touching the game's ABS
-- setting: setWheelBrakeUpdate with the wheel's own functions just reruns that choice.
local function refreshBrakes()
  local done = false
  eachRotator(function(_, wd)
    if not done and wd.name and wd.updateBrakeNoABS then
      wheels.setWheelBrakeUpdate(wd.name, wd.updateBrakeNoABS, wd.updateBrakeABS)
      done = true
    end
  end)
end

local function applyABS()
  eachRotator(function(i, wd)
    local s = stock.rotators[i]
    if absLevel == nil or wd.hasTire == false then  -- bare rotators always keep stock
      if s then wd.hasABS, wd.slipRatioTarget = s.hasABS, s.slipRatioTarget end
    elseif absLevel == 0 then
      wd.hasABS = false
    elseif wd.updateBrakeABS then
      wd.hasABS, wd.slipRatioTarget = true, M.ABS_SLIP[absLevel]
    end
  end)
  refreshBrakes()
end

local function clearOwnTC()
  if own.wrote then electrics.values.throttleFactor = nil end
  own.factor, own.slip, own.slipF, own.wrote = 1, 0, 0, false
end

local function applyTC()
  if tcMode == 'cmu' then
    local parts = cmuTC()
    if not parts then return end
    if tcLevel == nil then
      parts.tc.setParameters({isEnabled=stock.tc.isEnabled})
      setThresholds(parts.motor, stock.tc.motor)
      setThresholds(parts.brake, stock.tc.brake)
    elseif tcLevel == 0 then
      parts.tc.setParameters({isEnabled=false})
    else
      local motor, brake = {}, {}
      for name in pairs(stock.tc.motor) do motor[name] = M.TC_SLIP[tcLevel] end
      for name in pairs(stock.tc.brake) do brake[name] = M.TC_SLIP[tcLevel] * M.TC_BRAKE_RATIO end
      setThresholds(parts.motor, motor)
      setThresholds(parts.brake, brake)
      parts.tc.setParameters({isEnabled=true})
    end
  elseif tcMode == 'acng' and not (tcLevel and tcLevel > 0) then
    clearOwnTC()
  end
end

-- Highest driven-wheel slip ratio: (driven wheel surface speed - road speed) / road speed.
-- Road speed is the mean surface speed of the undriven wheels, as real TC measures it, so
-- the loaded tire radius cancels out (T006a: against airspeed, a rolling bolide read 8 %
-- slip with no wheelspin). Cars with every wheel driven fall back to airspeed. Bare
-- rotators (hasTire false) are skipped.
local function drivenSlip()
  local maxDriven, free, nFree
  local tire = function(wd) return wd.hasTire ~= false and type(wd.radius) == 'number' and type(wd.angularVelocity) == 'number' end
  free, nFree = 0, 0
  eachRotator(function(_, wd)
    if tire(wd) then
      local surface = math.abs(wd.angularVelocity) * wd.radius
      if wd.isPropulsed then maxDriven = math.max(maxDriven or 0, surface)
      else free, nFree = free + surface, nFree + 1 end
    end
  end)
  if not maxDriven then return 0 end
  local speed = nFree > 0 and free / nFree or math.abs(electrics.values.airspeed or 0)
  return math.max(0, (maxDriven - speed) / math.max(speed, M.TC_MIN_SPEED))
end

local function ownTCStep(dt)
  own.slip = drivenSlip()
  own.slipF = own.slipF + (own.slip - own.slipF) * math.min(1, dt / M.TC_FILTER_S)
  local want = 1 - M.TC_GAIN * (own.slipF - M.TC_SLIP[tcLevel])
  want = math.max(M.TC_MIN_FACTOR, math.min(1, want))
  if want < own.factor then own.factor = want else own.factor = math.min(want, own.factor + M.TC_RECOVER * dt) end
  electrics.values.throttleFactor = own.factor
  own.wrote = true
end

local function round(x, step)
  return type(x) == 'number' and math.floor(x / step + 0.5) * step or nil
end

-- electrics.lua turns boolean electrics into 1/0 each frame, so a flag can read either way.
local function on(x) return x == true or x == 1 end

local function snapshot()
  local ev = electrics.values
  local tcActive
  if tcMode == 'cmu' then tcActive = on(ev.tcsActive)
  elseif tcMode == 'acng' then tcActive = own.wrote and own.factor < 0.98 end
  return {schema_version=1, mode='on', abs_level=absLevel, tc_level=tcLevel, tc_mode=tcMode,
    abs_available=on(ev.hasABS), abs_active=on(ev.absActive),
    tc_active=tcActive == true, tc_factor=tcMode == 'acng' and round(own.factor, 0.01) or nil,
    abs_setting=settings and settings.getValue and settings.getValue('absBehavior') or nil,
    abs_slip=absLevel and absLevel > 0 and M.ABS_SLIP[absLevel] or nil,
    tc_slip=tcLevel and tcLevel > 0 and M.TC_SLIP[tcLevel] or nil}
end

local function apply()
  if not stock then return end
  applyABS()
  applyTC()
end

local function updateGFX(dt)
  if not stock then return end
  if reapplyIn then
    reapplyIn = reapplyIn - dt
    if reapplyIn <= 0 then reapplyIn = nil; apply() end
  end
  if tcMode == 'acng' and tcLevel and tcLevel > 0 then ownTCStep(dt) end
  sinceSend = sinceSend + dt
  if sinceSend >= SEND_INTERVAL_S then
    sinceSend = 0
    guihooks.trigger('ACNGAssists', snapshot())
  end
end

-- A reset keeps the wheels' ABS fields, but put the levels back once the controllers
-- have finished resetting in case one of them reloaded its settings.
local function onReset()
  if own.wrote then own.factor, own.slipF = 1, 0 end
  reapplyIn = REAPPLY_DELAY_S
end

local function onExtensionLoaded()
  saveStock()
  absLevel, tcLevel = nil, nil
  sinceSend = 0
end

-- acng_core calls this after loading and whenever a flag or level changes; nil keeps the
-- factory setting for that assist.
local function configure(abs, tc)
  if not stock then saveStock() end
  absLevel, tcLevel = level(abs), level(tc)
  apply()
end

local function onExtensionUnloaded()
  if stock then
    absLevel, tcLevel = nil, nil
    applyABS()
    applyTC()
    clearOwnTC()
  end
  stock, reapplyIn = nil, nil
  guihooks.trigger('ACNGAssists', {schema_version=1, mode='off'})
end

M.level = level
M.drivenSlip = drivenSlip
M.configure = configure
M.snapshot = snapshot
M.getSnapshot = snapshot
M.getTCMode = function() return tcMode end
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
