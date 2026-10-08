-- ACNG tire heat, grip window and wear in the vehicle VM. BeamNG's physics core already has
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

-- Heat (T002 sweep, T004 skidpad, T007 lap cycles; etkc kc6). Friction heat is linear in
-- its coefficient. T007 drove 20 s limit corners and 15 s straights at about 31 m/s: the
-- old set (friction 0.05, environment 0.04 full at 20 m/s, core coupling 0.01) kept
-- soaking heat into the core, so every lap started hotter and a parked tire stayed hot.
-- Now air cooling is stronger and keeps rising with speed up to 40 m/s (x0.3 parked),
-- so the surface heats in a corner and comes back down on a straight, and the core is
-- coupled half as hard, so it follows the lap average slowly and settles instead of
-- holding the surface up. Friction 0.06 keeps the warm-up into the window about the same.
M.HEAT = {nodeToEnv=0.10, envMultStationary=0.3, envTerminalSpeed=40, nodeToCore=0.005,
  coreToNodes=0.005, nodeToSurface=0, friction=0.06, flashFriction=0, strain=0,
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

-- Compounds sit on top of the tire's own native grip (vanilla race tires already grip
-- far more than standard ones: noLoadCoef about 1.74-2.15 against 1.04-1.45). ACNG adds
-- how each compound behaves with heat and wear, AC style, as engineering presets, not a
-- measured real-compound model:
--   road  works from cold, wide window, warms slowly, lasts longest (wear x0.6);
--   sport the T007 setup: needs some heat, moderate cold/hot penalties (wear x1);
--   race  slick behaviour: poor grip cold, warms fast under load, narrow hot side and
--         wears fastest (wear x1.7).
local profile = 'sport'
local PROFILES = {
  road={low=35,high=75,cold=0.98,hot=0.85,coldRange=20,hotRange=40,wear=0.6,
    heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.001,
      coreToNodes=0.001,nodeToSurface=0,friction=0.03,flashFriction=0,strain=0,heatAffectsPressure=true}},
  sport={low=75,high=105,cold=0.85,hot=0.85,coldRange=60,hotRange=40,wear=1,
    heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.005,
      coreToNodes=0.005,nodeToSurface=0,friction=0.06,flashFriction=0,strain=0,heatAffectsPressure=true}},
  race={low=85,high=115,cold=0.70,hot=0.75,coldRange=65,hotRange=30,wear=1.7,
    heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.006,
      coreToNodes=0.006,nodeToSurface=0,friction=0.08,flashFriction=0,strain=0,heatAffectsPressure=true}}
}

-- Heat ceiling. Real tread surfaces start to smoke and shed rubber around 200 C, which
-- carries heat away; burnouts do not keep climbing past 300 C. From HEAT_FADE_C the
-- friction heat written to the native model fades to nothing at HEAT_LIMIT_C, so the
-- physics settles below the limit (the readout is never clamped). Cooling is unchanged.
M.HEAT_FADE_C = 200
M.HEAT_LIMIT_C = 250
-- Past the hot ramp, wear keeps climbing to WEAR_BURN_MULT at the ceiling, so a long
-- burnout wears through and the tire punctures natively.
M.WEAR_BURN_MULT = 4
local compoundCache={}
local puncturedByWear={}

-- Compound from a native tire part name: most vanilla names end in the tire type.
-- Names without one (whitewalls, redlines, mixed) return nil and physics decides.
local ROAD_WORDS = {'standard', 'eco', 'offroad', 'heavy', 'desert', 'rally', 'mud', 'allterrain',
  'snow', 'winter', 'touring', 'drift'}
local function compoundFromName(part)
  part=tostring(part or ''):lower()
  if part:find('semislick',1,true) or part:find('semi_slick',1,true) or part:find('sport',1,true) then return 'sport' end
  if part:find('race',1,true) or part:find('slick',1,true) or part:find('asphalt',1,true)
    or part:find('drag',1,true) then return 'race' end
  for _,word in ipairs(ROAD_WORDS) do if part:find(word,1,true) then return 'road' end end
  return nil
end

-- Compound from the wheel's own native tire physics, for mod tires without a usable
-- name: slick tread with race-level grip is race, sport-level grip is sport.
local function compoundFromPhysics(wd)
  local grip, treadCoef = tonumber(wd and wd.noLoadCoef), tonumber(wd and wd.treadCoef)
  if not grip then return nil end
  if grip >= 1.7 and treadCoef and treadCoef <= 0.2 then return 'race' end
  if grip >= 1.5 then return 'sport' end
  return 'road'
end

-- Auto: the fitted front/rear native tire part decides, once per reset/configuration;
-- without one clear part the wheel's own physics decides, and failing that Road.
-- Native peak grip is never overwritten.
local function compoundFor(wd)
  if profile~='auto' then return profile end
  local id=wd and wd.wheelID
  if id~=nil and compoundCache[id] then return compoundCache[id] end
  local axle=wd and tostring(wd.name or ''):match('^([FR])[LR]')
  local found={}
  for slot,part in pairs(v.config and v.config.parts or {}) do
    if type(slot)=='string' and type(part)=='string' and part~='' and axle and slot:match('^tire_'..axle..'_') then
      local name=compoundFromName(part)
      if name then found[name]=true end
    end
  end
  local selected,count=nil,0
  for name in pairs(found) do selected=name;count=count+1 end
  if count~=1 then selected=compoundFromPhysics(wd) or 'road' end
  if id~=nil then compoundCache[id]=selected end
  return selected
end

-- Wear. Each tire's tread starts at 1 (new) and is worn down by the slip energy BeamNG
-- reports per wheel every frame (wheels.wheels[cid].slipEnergy, the same slip work the
-- tire sounds use), so sliding, spinning and locking wear a tire and rolling does not.
-- WEAR_ENERGY is the slip work that takes a tread from 1 to 0. T005a measured about
-- 5.7 kW of slip power on the outer front of the etkc held at the limit (0.95 g circle),
-- so 7.5e6 bald-tires that corner in about 22 minutes of nonstop limit cornering inside
-- the window, or about 11 minutes when cooked; real laps with straights take far longer.
-- Above the grip window the wear rate climbs, to WEAR_HOT_MULT at HOT_RANGE_C past it,
-- so cooking a tire costs tread. Grip falls linearly to 1 - WEAR_GRIP_LOSS at no tread.
-- WEAR_RATE is the AC-style wear multiplier (1 = normal; labs raise it to wear faster).
M.WEAR_ENERGY = 7.5e6
M.WEAR_GRIP_LOSS = 0.15
M.WEAR_HOT_MULT = 2
M.WEAR_RATE = 1

-- Which parts run. acng_core calls configure() right after loading, from its feature
-- flags tire_temperature (heat) and tire_wear (wear).
local parts = {heat=true, wear=false}

local active = false
local sinceSend = 0
local sinceGrip = 0
local applied = {}  -- wheelID -> grip last written
local heatScale = {} -- wheelID -> heat-ceiling fade last written
local tread = {}    -- wheelID -> tread left, 1 new to 0 gone
local slipWork = {} -- wheelID -> slip energy integrated since the last fresh set
local lastC = {}    -- wheelID -> surface temperature at the last grip update

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

-- ACNG heat; the wheel keeps its own smoking and melting temperatures. scale (0..1)
-- is the heat-ceiling fade on friction heat.
local function acngThermal(wd, scale)
  local h, stock = profile=='auto' and PROFILES[compoundFor(wd)].heat or M.HEAT, stockThermal(wd)
  scale = type(scale) == 'number' and scale or 1
  return {h.nodeToEnv, h.envMultStationary, h.envTerminalSpeed, h.nodeToCore, h.coreToNodes,
    h.nodeToSurface, h.friction * scale, h.flashFriction * scale, h.strain, stock[10], stock[11],
    h.heatAffectsPressure}
end

-- Friction-heat multiplier at a surface temperature: 1 up to HEAT_FADE_C, 0 at
-- HEAT_LIMIT_C, in tenths so the native parameters are only rewritten on real change.
local function heatFade(c)
  if type(c) ~= 'number' or c ~= c or c <= M.HEAT_FADE_C then return 1 end
  if c >= M.HEAT_LIMIT_C then return 0 end
  return math.ceil(10 * (M.HEAT_LIMIT_C - c) / (M.HEAT_LIMIT_C - M.HEAT_FADE_C)) / 10
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
local function windowState(c, wd)
  if type(c) ~= 'number' then return nil end
  local p=profile=='auto' and PROFILES[compoundFor(wd)]
  if c < (p and p.low or M.WINDOW_LOW_C) then return 'cold' end
  if c > (p and p.high or M.WINDOW_HIGH_C) then return 'hot' end
  return 'window'
end

-- Grip factor at a surface temperature in Celsius: the value written to the tire.
local function gripAt(c, wd)
  if type(c) ~= 'number' or c ~= c then return nil end
  local p=profile=='auto' and PROFILES[compoundFor(wd)]
  local low,high=p and p.low or M.WINDOW_LOW_C,p and p.high or M.WINDOW_HIGH_C
  local cold,hot=p and p.cold or M.COLD_GRIP,p and p.hot or M.HOT_GRIP
  if c < low then
    return math.max(cold, 1 - (1 - cold) * (low - c) / (p and p.coldRange or M.COLD_RANGE_C))
  end
  if c > high then
    return math.max(hot, 1 - (1 - hot) * (c - high) / (p and p.hotRange or M.HOT_RANGE_C))
  end
  return 1
end

local function surfaceC(wd)
  local t = obj:getWheelAvgTemperature(wd.wheelID)
  return type(t) == 'number' and t - K or nil
end

-- Grip factor for the tread left: 1 when new, 1 - WEAR_GRIP_LOSS with no tread.
local function wearGrip(left)
  if type(left) ~= 'number' or left ~= left then return 1 end
  return 1 - M.WEAR_GRIP_LOSS * (1 - math.max(0, math.min(1, left)))
end

-- Wear rate multiplier at a surface temperature: 1 up to the window top, rising
-- linearly to WEAR_HOT_MULT at HOT_RANGE_C past it, then on to WEAR_BURN_MULT at the
-- heat ceiling. Without heat it stays 1.
local function wearHeatMult(c, wd)
  local p=profile=='auto' and PROFILES[compoundFor(wd)]
  local high=p and p.high or M.WINDOW_HIGH_C
  if not parts.heat or type(c) ~= 'number' or c ~= c or c <= high then return 1 end
  local hot = high + (p and p.hotRange or M.HOT_RANGE_C)
  if c <= hot then return 1 + (M.WEAR_HOT_MULT - 1) * (c - high) / (hot - high) end
  if hot >= M.HEAT_LIMIT_C then return M.WEAR_HOT_MULT end
  return M.WEAR_HOT_MULT + (M.WEAR_BURN_MULT - M.WEAR_HOT_MULT) * math.min(1, (c - hot) / (M.HEAT_LIMIT_C - hot))
end

-- Compound wear multiplier: road tires last longer, race tires wear faster.
local function compoundWear(wd)
  local p = PROFILES[compoundFor(wd)]
  return p and p.wear or 1
end

-- The grip written to a tire: heat window times wear, each only while its part is on.
local function targetGrip(wd, c)
  local heatGrip = 1
  if parts.heat then
    heatGrip = gripAt(c, wd)
    if not heatGrip then return nil end
  end
  return heatGrip * (parts.wear and wearGrip(tread[wd.wheelID]) or 1)
end

local function setGrip(wobj, grip)
  local c = acngCurve(grip)
  wobj:setFrictionThermalSensitivity(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
end

local function freshTires()
  tread, slipWork, compoundCache, puncturedByWear = {}, {}, {}, {}
  eachTire(function(wd) tread[wd.wheelID], slipWork[wd.wheelID] = 1, 0 end)
end

local function applyAcng()
  applied = {}
  return eachTire(function(wd, wobj)
    local c = surfaceC(wd)
    heatScale[wd.wheelID] = heatFade(c)
    local t = parts.heat and acngThermal(wd, heatScale[wd.wheelID]) or stockThermal(wd)
    wobj:setThermal(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
    lastC[wd.wheelID] = c
    local grip = targetGrip(wd, c) or 1
    setGrip(wobj, grip)
    applied[wd.wheelID] = grip
  end)
end

-- Follow each tire's temperature and tread; only write when the grip moved by GRIP_STEP.
local function updateGrip()
  sinceGrip = 0
  eachTire(function(wd, wobj)
    local c = surfaceC(wd)
    lastC[wd.wheelID] = c
    if parts.heat then
      local fade = heatFade(c)
      if fade ~= heatScale[wd.wheelID] then
        local t = acngThermal(wd, fade)
        wobj:setThermal(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
        heatScale[wd.wheelID] = fade
      end
    end
    local grip = targetGrip(wd, c)
    local last = applied[wd.wheelID]
    if grip and (not last or math.abs(grip - last) >= M.GRIP_STEP) then
      setGrip(wobj, grip)
      applied[wd.wheelID] = grip
    end
  end)
end

-- Integrate this frame's slip energy into each tire's tread. The runtime wheel table
-- (wheels.wheels, by cid) carries slipEnergy; missing or broken wheels are skipped.
local function wearStep(dt)
  local data = v.data.wheels
  local runtime = wheels and wheels.wheels
  if not data or not runtime or dt <= 0 then return end
  local scale = dt * M.WEAR_RATE / M.WEAR_ENERGY
  for i = 0, tableSizeC(data) - 1 do
    local wd = data[i]
    local id = wd and wd.wheelID
    local rt = wd and runtime[wd.cid]
    local e = rt and rt.slipEnergy
    if tread[id] and rt and not rt.isBroken and not rt.isTireDeflated and type(e) == 'number' and e > 0 and e < math.huge then
      slipWork[id] = slipWork[id] + e * dt
      tread[id] = math.max(0, tread[id] - e * scale * wearHeatMult(lastC[id], wd) * compoundWear(wd))
      if tread[id]<=0 and not puncturedByWear[id] and beamstate and type(beamstate.deflateTire)=='function' then
        -- Native puncture persists across ACNG OFF. Only native repair/reset fixes it.
        beamstate.deflateTire(wd.cid)
        puncturedByWear[id]=true
      end
    end
  end
end

local function applyStock()
  applied, heatScale = {}, {}
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
    local compound=compoundFor(wd)
    local tireProfile=PROFILES[compound]
    local core = obj:getWheelCoreTemperature(wd.wheelID)
    local group = wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
    local pa = group and obj:getGroupPressure(group)
    tires[#tires + 1] = {name=wd.name, surface_c=round(c, 0.1),
      core_c=type(core) == 'number' and round(core - K, 0.1) or nil,
      psi=type(pa) == 'number' and round((pa - ATM_PA) / PSI_PA, 0.1) or nil,
      state=parts.heat and windowState(c, wd) or nil,
      compound=compound, worn_through=puncturedByWear[wd.wheelID]==true,
      window_low_c=parts.heat and tireProfile.low or nil,
      window_high_c=parts.heat and tireProfile.high or nil,
      grip=round(applied[wd.wheelID] or targetGrip(wd, c), 0.001),
      tread=parts.wear and round(tread[wd.wheelID], 0.001) or nil}
  end)
  return {schema_version=1, mode=active and 'on' or 'off', heat=parts.heat, wear=parts.wear, profile=profile,
    window_low_c=parts.heat and M.WINDOW_LOW_C or nil, window_high_c=parts.heat and M.WINDOW_HIGH_C or nil,
    wear_rate=parts.wear and M.WEAR_RATE or nil, tires=tires}
end

-- Raw wear state for lab harnesses: tread and integrated slip work per tire.
local function wearState()
  local out = {}
  eachTire(function(wd)
    out[#out + 1] = {name=wd.name, tread=tread[wd.wheelID], slip_work=slipWork[wd.wheelID]}
  end)
  return out
end

local function send()
  sinceSend = 0
  guihooks.trigger('ACNGTires', snapshot())
end

local function updateGFX(dt)
  dt = type(dt) == 'number' and dt or 0
  sinceSend, sinceGrip = sinceSend + dt, sinceGrip + dt
  if active and parts.wear then wearStep(dt) end
  if active and sinceGrip >= GRIP_INTERVAL_S then updateGrip() end
  if sinceSend >= SEND_INTERVAL_S then send() end
end

local function onReset()
  -- A reset brings fresh, ambient tires; make sure the ACNG values still hold.
  freshTires()
  if active then applyAcng() end
  send()
end

local function onExtensionLoaded()
  freshTires()
  local n = applyAcng()
  active = n > 0
  log('I', 'ACNG', 'TIRES_LOADED tires=' .. n .. ' physics_writes=' .. (active and 1 or 0))
  send()
end

-- Choose the parts that run (heat window, wear). Tread carries over; only a reset or a
-- reload gives fresh tires. With neither part on, acng_core unloads the extension.
local function setProfile(name)
  local p=PROFILES[name=='auto' and 'road' or name]
  if not p then return false end
  profile=name
  compoundCache={}
  M.HEAT={};for k,value in pairs(p.heat) do M.HEAT[k]=value end
  M.WINDOW_LOW_C,M.WINDOW_HIGH_C=p.low,p.high
  M.COLD_GRIP,M.HOT_GRIP=p.cold,p.hot
  M.COLD_RANGE_C,M.HOT_RANGE_C=p.coldRange,p.hotRange
  if active then applyAcng() end
  return true
end

local function configure(heat, wear, name)
  parts = {heat=heat == true, wear=wear == true}
  if name then setProfile(name) end
  if active then applyAcng() end
  log('I', 'ACNG', 'TIRES_PARTS heat=' .. tostring(parts.heat) .. ' wear=' .. tostring(parts.wear))
  send()
  return parts.heat, parts.wear
end

-- Lab hook: the AC-style wear multiplier (clamped 0 to 100).
local function setWearRate(rate)
  if type(rate) == 'number' and rate == rate then M.WEAR_RATE = math.max(0, math.min(100, rate)) end
  return M.WEAR_RATE
end

local function onExtensionUnloaded()
  local n = applyStock()
  active = false
  log('I', 'ACNG', 'TIRES_UNLOADED stock_restored=' .. n .. ' physics_writes=0')
  guihooks.trigger('ACNGTires', {schema_version=1, mode='off'})
end

-- Pit service changes only ACNG tread accounting, never native damage or temperature.
local function canServiceTread()
  if not active or not parts.wear then return false,'Enable ACNG tire wear first' end
  local count=0
  for _,wd in pairs(v.data.wheels or {}) do
    if hasTire(wd) then
      local runtime=wheels and wheels.wheels and wheels.wheels[wd.cid]
      if not runtime or runtime.isBroken or runtime.isTireDeflated or not obj:getWheel(wd.wheelID) then
        return false,'Damaged or unavailable wheel: tread service refused'
      end
      count=count+1
    end
  end
  return count>0,count>0 and nil or 'No supported tires'
end
local function serviceTread()
  if not canServiceTread() then return false end
  freshTires();updateGrip();return true
end
M.canServiceTread=canServiceTread
M.serviceTread=serviceTread
M.stockThermal = stockThermal
M.stockCurve = stockCurve
M.acngThermal = acngThermal
M.acngCurve = acngCurve
M.updateGrip = updateGrip
M.windowState = windowState
M.gripAt = gripAt
M.wearGrip = wearGrip
M.wearHeatMult = wearHeatMult
M.heatFade = heatFade
M.compoundWear = compoundWear
M.compoundFromName = compoundFromName
M.compoundFromPhysics = compoundFromPhysics
M.wearState = wearState
M.configure = configure
M.setProfile = setProfile
M.compoundFor = compoundFor
M.setWearRate = setWearRate
M.snapshot = snapshot
M.getSnapshot = snapshot
M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
return M
