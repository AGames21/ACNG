-- ACNG tire heat and grip window in the vehicle VM. BeamNG's physics core already has
-- a per-wheel tire heat model (wobj:setThermal) and a temperature-to-grip curve
-- (wobj:setFrictionThermalSensitivity), but no stock jbeam sets them, so both are off.
-- Loading this switches them on with ACNG values; unloading puts back each wheel's own
-- jbeam values exactly as jbeam/stage2.lua set them. Everything stays in the native
-- physics step: tires, suspension, deformation and damage remain BeamNG's.
local M = {}

local K = 273.15
local PSI_PA = 6894.757
local ATM_PA = 101325
local SEND_INTERVAL_S = 0.1

-- Heat (T002 sweep and T004 skidpad, etkc kc6). Friction heat is linear in its
-- coefficient. At 0.1 a front tire held at the limit (0.95 g circle) passed 240 C with
-- its core over 110 C (+13 psi); 0.05 is aimed at about 130 C there, with launches and
-- brisk driving warming tires into the window. Environment 0.04 cools a parked tire
-- in about half a minute; core coupling 0.01 lets the carcass lag behind.
M.HEAT = {nodeToEnv=0.04, envMultStationary=0.4, envTerminalSpeed=20, nodeToCore=0.01,
  coreToNodes=0.01, nodeToSurface=0, friction=0.05, flashFriction=0, strain=0,
  heatAffectsPressure=true}

-- Grip window. Full grip from WINDOW_LOW_C to WINDOW_HIGH_C; below it grip ramps down
-- to COLD_GRIP over COLD_RANGE_C, above it to HOT_GRIP over HOT_RANGE_C. T003c showed the
-- native curve drops to coefLow within a few K of lowTemp whatever the slope, a step
-- that would cost the full penalty one degree under the window. So the curve itself is
-- kept flat (all three coefficients equal) and this ramp sets that flat value per tire
-- from its own temperature, GRIP_INTERVAL_S at a time. coefMiddle scales grip almost
-- linearly at the limit (T003c: 0.9 -> 96 %, 0.8 -> 89 % lateral on the etkc).
M.WINDOW_LOW_C = 75
M.WINDOW_HIGH_C = 105
M.COLD_GRIP = 0.85
M.HOT_GRIP = 0.85
M.COLD_RANGE_C = 60
M.HOT_RANGE_C = 40
M.GRIP_STEP = 0.002
local GRIP_INTERVAL_S = 0.1

local active = false
local sinceSend = 0
local sinceGrip = 0
local applied = {}  -- wheelID -> grip last written

local function checkNum(value, default)
  return type(value) == 'number' and value or (default or 0)
end

local function hasTire(wd)
  return wd.hasTire or wd.hasTire == nil
end

-- The exact arguments jbeam/stage2.lua passes for this wheel's jbeam data.
local function stockThermal(wd)
  return {checkNum(wd.heatCoefNodeToEnv), checkNum(wd.heatCoefEnvMultStationary, 0.4),
    checkNum(wd.heatCoefEnvTerminalSpeed, 20), checkNum(wd.heatCoefNodeToCore),
    checkNum(wd.heatCoefCoreToNodes), checkNum(wd.heatCoefNodeToSurface),
    checkNum(wd.heatCoefFriction), checkNum(wd.heatCoefFlashFriction),
    checkNum(wd.heatCoefStrain), checkNum(wd.smokingTemp, 1e18), checkNum(wd.meltingTemp, 1e19),
    type(wd.heatAffectsPressure) == 'boolean' and wd.heatAffectsPressure or false}
end

local function stockCurve(wd)
  return {checkNum(wd.frictionLowTemp, -300), checkNum(wd.frictionHighTemp, 1e7),
    checkNum(wd.frictionLowSlope, 1e-10), checkNum(wd.frictionHighSlope, 1e-10),
    checkNum(wd.frictionSlopeSmoothCoef, 10), checkNum(wd.frictionCoefLow, 1),
    checkNum(wd.frictionCoefMiddle, 1), checkNum(wd.frictionCoefHigh, 1)}
end

-- ACNG heat; the wheel keeps its own smoking and melting temperatures.
local function acngThermal(wd)
  local h, stock = M.HEAT, stockThermal(wd)
  return {h.nodeToEnv, h.envMultStationary, h.envTerminalSpeed, h.nodeToCore, h.coreToNodes,
    h.nodeToSurface, h.friction, h.flashFriction, h.strain, stock[10], stock[11], h.heatAffectsPressure}
end

-- A flat curve: the same grip at every temperature, so only the ramp below decides it.
local function acngCurve(grip)
  return {-300, 1e7, 1e-10, 1e-10, 10, grip, grip, grip}
end

local function eachTire(fn)
  local wheels = v.data.wheels
  if not wheels then return 0 end
  local n = 0
  for i = 0, tableSizeC(wheels) - 1 do
    local wd = wheels[i]
    local wobj = wd and hasTire(wd) and obj:getWheel(wd.wheelID)
    if wobj then fn(wd, wobj); n = n + 1 end
  end
  return n
end

-- 'cold', 'window' or 'hot' for a surface temperature in Celsius.
local function windowState(c)
  if type(c) ~= 'number' then return nil end
  if c < M.WINDOW_LOW_C then return 'cold' end
  if c > M.WINDOW_HIGH_C then return 'hot' end
  return 'window'
end

-- Grip factor at a surface temperature in Celsius: the value written to the tire.
local function gripAt(c)
  if type(c) ~= 'number' or c ~= c then return nil end
  if c < M.WINDOW_LOW_C then
    return math.max(M.COLD_GRIP, 1 - (1 - M.COLD_GRIP) * (M.WINDOW_LOW_C - c) / M.COLD_RANGE_C)
  end
  if c > M.WINDOW_HIGH_C then
    return math.max(M.HOT_GRIP, 1 - (1 - M.HOT_GRIP) * (c - M.WINDOW_HIGH_C) / M.HOT_RANGE_C)
  end
  return 1
end

local function surfaceC(wd)
  local t = obj:getWheelAvgTemperature(wd.wheelID)
  return type(t) == 'number' and t - K or nil
end

local function setGrip(wobj, grip)
  local c = acngCurve(grip)
  wobj:setFrictionThermalSensitivity(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
end

local function applyAcng()
  applied = {}
  return eachTire(function(wd, wobj)
    local t = acngThermal(wd)
    wobj:setThermal(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
    local grip = gripAt(surfaceC(wd)) or 1
    setGrip(wobj, grip)
    applied[wd.wheelID] = grip
  end)
end

-- Follow each tire's temperature; only write when the grip moved by GRIP_STEP.
local function updateGrip()
  sinceGrip = 0
  eachTire(function(wd, wobj)
    local grip = gripAt(surfaceC(wd))
    local last = applied[wd.wheelID]
    if grip and (not last or math.abs(grip - last) >= M.GRIP_STEP) then
      setGrip(wobj, grip)
      applied[wd.wheelID] = grip
    end
  end)
end

local function applyStock()
  applied = {}
  return eachTire(function(wd, wobj)
    local t, c = stockThermal(wd), stockCurve(wd)
    wobj:setThermal(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
    wobj:setFrictionThermalSensitivity(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
  end)
end

local function round(x, step)
  if type(x) ~= 'number' or x ~= x then return nil end
  return math.floor(x / step + 0.5) * step
end

local function snapshot()
  local tires = {}
  eachTire(function(wd)
    local c = surfaceC(wd)
    local core = obj:getWheelCoreTemperature(wd.wheelID)
    local group = wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
    local pa = group and obj:getGroupPressure(group)
    tires[#tires + 1] = {name=wd.name, surface_c=round(c, 0.1),
      core_c=type(core) == 'number' and round(core - K, 0.1) or nil,
      psi=type(pa) == 'number' and round((pa - ATM_PA) / PSI_PA, 0.1) or nil,
      state=windowState(c), grip=round(applied[wd.wheelID] or gripAt(c), 0.001)}
  end)
  return {schema_version=1, mode=active and 'on' or 'off', window_low_c=M.WINDOW_LOW_C,
    window_high_c=M.WINDOW_HIGH_C, tires=tires}
end

local function send()
  sinceSend = 0
  guihooks.trigger('ACNGTires', snapshot())
end

local function updateGFX(dt)
  dt = type(dt) == 'number' and dt or 0
  sinceSend, sinceGrip = sinceSend + dt, sinceGrip + dt
  if active and sinceGrip >= GRIP_INTERVAL_S then updateGrip() end
  if sinceSend >= SEND_INTERVAL_S then send() end
end

local function onReset()
  -- A reset brings fresh, ambient tires; make sure the ACNG values still hold.
  if active then applyAcng() end
  send()
end

local function onExtensionLoaded()
  local n = applyAcng()
  active = n > 0
  log('I', 'ACNG', 'TIRES_LOADED tires=' .. n .. ' physics_writes=' .. (active and 1 or 0))
  send()
end

local function onExtensionUnloaded()
  local n = applyStock()
  active = false
  log('I', 'ACNG', 'TIRES_UNLOADED stock_restored=' .. n .. ' physics_writes=0')
  guihooks.trigger('ACNGTires', {schema_version=1, mode='off'})
end

M.stockThermal = stockThermal
M.stockCurve = stockCurve
M.acngThermal = acngThermal
M.acngCurve = acngCurve
M.updateGrip = updateGrip
M.windowState = windowState
M.gripAt = gripAt
M.snapshot = snapshot
M.getSnapshot = snapshot
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
