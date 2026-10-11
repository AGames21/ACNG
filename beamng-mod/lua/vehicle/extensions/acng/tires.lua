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
-- press is the grip lost per psi away from the ideal hot pressure and damage scales
-- graining and blistering (T009, below): a street tire barely cares, a slick does.
local profile = 'sport'
local PROFILES = {
  road={low=35,high=75,cold=0.98,hot=0.85,coldRange=20,hotRange=40,wear=0.6,press=0.003,damage=0.5,
    heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.001,
      coreToNodes=0.001,nodeToSurface=0,friction=0.03,flashFriction=0,strain=0,heatAffectsPressure=true}},
  sport={low=75,high=105,cold=0.85,hot=0.85,coldRange=60,hotRange=40,wear=1,press=0.005,damage=1,
    heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,nodeToCore=0.005,
      coreToNodes=0.005,nodeToSurface=0,friction=0.06,flashFriction=0,strain=0,heatAffectsPressure=true}},
  race={low=85,high=115,cold=0.70,hot=0.75,coldRange=65,hotRange=30,wear=1.7,press=0.008,damage=1.5,
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
-- Grip over tread life, AC style rather than a straight line: a new tire is slightly
-- off its best until the first 2 % of tread scrubs in, holds near peak through mid
-- life, then falls away faster towards the cords. Each point is {tread, share of
-- WEAR_GRIP_LOSS lost}, so WEAR_GRIP_LOSS stays the grip left on a bald tire.
M.WEAR_CURVE = {{0, 1}, {0.25, 1/3}, {0.5, 1/6}, {0.98, 0}, {1, 1/15}}

-- T009 tire model, run with the heat part. An original ACNG model shaped after the tire
-- behaviours Kunos documents in the public AC SDK (tyres.ini: ideal pressure and its grip
-- gain, grain and blister gamma/gain, dirt pickup); ACNG values, no AC code or data:
--   zones    inner, middle and outer tread temperatures from BeamNG's own tread nodes.
--            Grip is the mean of each zone's window grip, so a tire cooked on one edge
--            (camber, pressure) loses grip even when its average looks fine.
--   pressure grip falls by the compound's press per psi away from the ideal hot
--            pressure: the car's default cold pressure warmed to mid-window. Native heat
--            raises pressure, so cold tires sit under it and set-up changes move it.
--   grain    sliding a tire below its window tears the surface; grain cleans off again
--            while the tire rolls inside its window.
--   blister  sliding above the window blisters the tread; blisters stay until fresh tires.
--   dirt     rolling on loose ground picks up dirt that costs grip back on tarmac until
--            it wears off with distance. Off tarmac the native surface grip rules alone.
-- Slip power is scaled by SLIP_REF_W, about one tire at the limit (T005a: 5.7 kW).
M.SLIP_REF_W = 5000
M.SLIP_LOAD_MAX = 3
M.GRAIN_GAIN = 1/40
M.GRAIN_GAMMA = 1.5
M.GRAIN_CLEAN_S = 90
M.GRAIN_GRIP_LOSS = 0.06
M.BLISTER_GAIN = 1/150
M.BLISTER_GAMMA = 2
M.BLISTER_GRIP_LOSS = 0.08
M.DIRT_PICKUP_M = 40
M.DIRT_CLEAN_M = 600
M.DIRT_GRIP_LOSS = 0.08
M.PRESSURE_REF_C = 20
M.PRESSURE_MAX_LOSS = 0.12
M.MIN_GRIP = 0.6
local MOVING_MS = 3
-- BeamNG ground material IDs (lua/common/particles.json).
local LOOSE = {[7]=true, [14]=true, [15]=true, [16]=true, [17]=true, [18]=true, [19]=true, [20]=true, [22]=true, [31]=true}
local TARMAC = {[10]=true, [11]=true, [29]=true, [30]=true}

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
local zones = {}    -- wheelID -> {inner, middle, outer} tread node lists
local zoneC = {}    -- wheelID -> {inner, middle, outer} Celsius at the last grip update
local ideal = {}    -- wheelID -> ideal hot pressure, psi gauge
local grain, blister, dirt = {}, {}, {} -- wheelID -> 0 clean to 1 at full loss
local surface = {}  -- wheelID -> last ground material the tire touched

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

-- Grip factor for the tread left, along WEAR_CURVE: 1 - WEAR_GRIP_LOSS with no tread.
local function wearGrip(left)
  if type(left) ~= 'number' or left ~= left then return 1 end
  left = math.max(0, math.min(1, left))
  local curve = M.WEAR_CURVE
  for i = 2, #curve do
    local a, b = curve[i - 1], curve[i]
    if left <= b[1] then
      return 1 - M.WEAR_GRIP_LOSS * (a[2] + (b[2] - a[2]) * (left - a[1]) / (b[1] - a[1]))
    end
  end
  return 1 - M.WEAR_GRIP_LOSS * curve[#curve][2]
end

local function psiOf(wd)
  local group = wd.pressureGroup and v.data.pressureGroups and v.data.pressureGroups[wd.pressureGroup]
  local pa = group and obj:getGroupPressure(group)
  return type(pa) == 'number' and (pa - ATM_PA) / PSI_PA or nil
end

-- Split each tire's tread nodes into inner, middle and outer thirds across the tread,
-- by their rest offset along the hub axis; inner is the hub end nearer the car's centre.
-- Stock BeamNG tires have tread nodes on the two tread edges only (T009a: 16 + 16 on the
-- etkc), so the middle third is usually empty. Tires without usable tread nodes keep no
-- zones and use their average temperature.
local function buildZones()
  zones, zoneC = {}, {}
  if not obj.getNodePosition or not obj.getNodeTemperature then return end
  local hubs, centre, n = {}, nil, 0
  eachTire(function(wd)
    if wd.node1 and wd.node2 then
      local p1, p2 = obj:getNodePosition(wd.node1), obj:getNodePosition(wd.node2)
      hubs[wd.wheelID] = {p1, p2}
      centre = centre and centre + (p1 + p2) * 0.5 or (p1 + p2) * 0.5
      n = n + 1
    end
  end)
  if n == 0 then return end
  centre = centre / n
  eachTire(function(wd)
    local hub = hubs[wd.wheelID]
    if not hub or type(wd.treadNodes) ~= 'table' then return end
    local inner, outer = hub[1], hub[2]
    if (outer - centre):length() < (inner - centre):length() then inner, outer = outer, inner end
    local axis, mid = (outer - inner):normalized(), (inner + outer) * 0.5
    local list, lo, hi = {}, math.huge, -math.huge
    for _, nid in pairs(wd.treadNodes) do
      local o = (obj:getNodePosition(nid) - mid):dot(axis)
      list[#list + 1] = {nid, o}
      lo, hi = math.min(lo, o), math.max(hi, o)
    end
    if #list < 3 or hi - lo < 1e-3 then return end
    local z = {{}, {}, {}}
    for _, e in ipairs(list) do
      local t = (e[2] - lo) / (hi - lo)
      local k = t < 1 / 3 and 1 or t > 2 / 3 and 3 or 2
      z[k][#z[k] + 1] = e[1]
    end
    if #z[1] > 0 and #z[3] > 0 then zones[wd.wheelID] = z end
  end)
end

-- Zone temperatures keep the wheel's average temperature as their level and take only the
-- spread across the tread from the tread nodes. Raw tread nodes run far hotter than the
-- average the grip windows were calibrated on (T009a: 99 C edge vs 53 C average after a
-- launch) and cool much faster. An empty middle zone reads the average itself.
local function zoneTemps(id, avg)
  local z = zones[id]
  if not z or type(avg) ~= 'number' then return nil end
  local means, all, count = {}, 0, 0
  for k = 1, 3 do
    local sum, n = 0, 0
    for _, nid in ipairs(z[k]) do
      local t = obj:getNodeTemperature(nid)
      if type(t) == 'number' and t == t then sum, n = sum + t, n + 1 end
    end
    if n == 0 and k ~= 2 then return nil end
    means[k] = n > 0 and sum / n or nil
    all, count = all + sum, count + n
  end
  local tread = all / count
  return {avg + means[1] - tread, means[2] and avg + means[2] - tread or avg, avg + means[3] - tread}
end

-- The car's default cold pressure for this tire: the default of its tire pressure
-- tuning variable (so a player's own pressure change moves the tire off its ideal),
-- else the jbeam pressure the tire was built with.
local function defaultPsi(wd)
  local axle = tostring(wd.name or ''):match('^([FfRr])')
  local any
  for name, var in pairs(v.data.variables or {}) do
    local n = tostring(name):lower()
    if type(var) == 'table' and type(var.default) == 'number' and n:find('tire', 1, true) and n:find('press', 1, true) then
      if axle and n:sub(-2) == '_' .. axle:lower() then return var.default end
      any = any or var.default
    end
  end
  return any or (type(wd.pressurePSI) == 'number' and wd.pressurePSI) or nil
end

-- Ideal hot pressure: the default cold pressure warmed from PRESSURE_REF_C to the middle
-- of the compound's window at constant volume.
local function idealPsi(wd)
  local cold = defaultPsi(wd)
  local p = PROFILES[compoundFor(wd)]
  if type(cold) ~= 'number' or cold <= 0 or not p then return nil end
  return ((cold * PSI_PA + ATM_PA) * ((p.low + p.high) / 2 + K) / (M.PRESSURE_REF_C + K) - ATM_PA) / PSI_PA
end

local function pressureGrip(wd, psi, target)
  if type(psi) ~= 'number' or type(target) ~= 'number' or psi ~= psi then return 1 end
  local p = PROFILES[compoundFor(wd)]
  return math.max(1 - M.PRESSURE_MAX_LOSS, 1 - (p and p.press or 0) * math.abs(psi - target))
end

-- Heat grip: the mean of each tread zone's window grip, or the average temperature's.
local function heatGrip(wd, c, z)
  if z then return (gripAt(z[1], wd) + gripAt(z[2], wd) + gripAt(z[3], wd)) / 3 end
  return gripAt(c, wd)
end

-- Grain, blister and dirt for this frame, from each tire's slip power, last surface
-- temperature, rolling speed and ground material.
local function damageStep(dt)
  local data = v.data.wheels
  local runtime = wheels and wheels.wheels
  if not data or not runtime or dt <= 0 then return end
  for i = 0, tableSizeC(data) - 1 do
    local wd = data[i]
    local id = wd and wd.wheelID
    local rt = wd and runtime[wd.cid]
    local p = rt and grain[id] and PROFILES[compoundFor(wd)]
    if p and not rt.isBroken and not rt.isTireDeflated then
      local e = rt.slipEnergy
      local load = type(e) == 'number' and e > 0 and e < math.huge and math.min(M.SLIP_LOAD_MAX, e / M.SLIP_REF_W) or 0
      local speed = type(rt.wheelSpeed) == 'number' and math.abs(rt.wheelSpeed) or 0
      if speed ~= speed or speed == math.huge then speed = 0 end
      local c = lastC[id]
      if type(c) == 'number' and c == c then
        if c < p.low then
          local cold = math.min(1, (p.low - c) / p.coldRange) ^ M.GRAIN_GAMMA
          grain[id] = math.min(1, grain[id] + dt * M.GRAIN_GAIN * p.damage * load * cold)
        elseif c <= p.high then
          if speed > MOVING_MS then grain[id] = math.max(0, grain[id] - dt / M.GRAIN_CLEAN_S) end
        else
          local hot = math.min(1, (c - p.high) / p.hotRange) ^ M.BLISTER_GAMMA
          blister[id] = math.min(1, blister[id] + dt * M.BLISTER_GAIN * p.damage * load * hot)
        end
      end
      local mat = rt.contactMaterialID1
      if LOOSE[mat] then
        dirt[id] = math.min(1, dirt[id] + speed * dt / M.DIRT_PICKUP_M)
      elseif TARMAC[mat] then
        dirt[id] = math.max(0, dirt[id] - speed * dt / M.DIRT_CLEAN_M)
      end
      if type(mat) == 'number' and mat >= 0 then surface[id] = mat end
    end
  end
end

-- Grip factor from grain, blister and (on tarmac only) dirt.
local function damageGrip(id)
  local g = (1 - M.GRAIN_GRIP_LOSS * (grain[id] or 0)) * (1 - M.BLISTER_GRIP_LOSS * (blister[id] or 0))
  if TARMAC[surface[id]] then g = g * (1 - M.DIRT_GRIP_LOSS * (dirt[id] or 0)) end
  return g
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

-- The grip written to a tire. Heat part: zone window grip, pressure, grain, blister and
-- dirt. Wear part: the tread curve. Never below MIN_GRIP.
local function targetGrip(wd, c)
  local id, grip = wd.wheelID, 1
  if parts.heat then
    grip = heatGrip(wd, c, zoneC[id])
    if not grip then return nil end
    grip = grip * pressureGrip(wd, psiOf(wd), ideal[id]) * damageGrip(id)
  end
  return math.max(M.MIN_GRIP, grip * (parts.wear and wearGrip(tread[id]) or 1))
end

local function setGrip(wobj, grip)
  local c = acngCurve(grip)
  wobj:setFrictionThermalSensitivity(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
end

local function freshTires()
  tread, slipWork, compoundCache, puncturedByWear = {}, {}, {}, {}
  grain, blister, dirt, surface = {}, {}, {}, {}
  eachTire(function(wd)
    local id = wd.wheelID
    tread[id], slipWork[id], grain[id], blister[id], dirt[id] = 1, 0, 0, 0, 0
  end)
end

local function applyAcng()
  applied = {}
  buildZones()
  return eachTire(function(wd, wobj)
    local c = surfaceC(wd)
    ideal[wd.wheelID] = idealPsi(wd)
    zoneC[wd.wheelID] = zoneTemps(wd.wheelID, c)
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
    zoneC[wd.wheelID] = zoneTemps(wd.wheelID, c)
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
    local id, z = wd.wheelID, parts.heat and zoneC[wd.wheelID]
    tires[#tires + 1] = {name=wd.name, surface_c=round(c, 0.1),
      core_c=type(core) == 'number' and round(core - K, 0.1) or nil,
      psi=round(psiOf(wd), 0.1), ideal_psi=parts.heat and round(ideal[id], 0.1) or nil,
      zones_c=z and {round(z[1], 0.1), round(z[2], 0.1), round(z[3], 0.1)} or nil,
      grain=parts.heat and round(grain[id], 0.001) or nil, blister=parts.heat and round(blister[id], 0.001) or nil,
      dirt=parts.heat and round(dirt[id], 0.001) or nil,
      state=parts.heat and windowState(c, wd) or nil,
      compound=compound, worn_through=puncturedByWear[wd.wheelID]==true,
      window_low_c=parts.heat and tireProfile.low or nil,
      window_high_c=parts.heat and tireProfile.high or nil,
      grip=round(applied[wd.wheelID] or targetGrip(wd, c), 0.001),
      tread=parts.wear and round(tread[wd.wheelID], 0.001) or nil}
  end)
  return {schema_version=2, mode=active and 'on' or 'off', heat=parts.heat, wear=parts.wear, profile=profile,
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

-- Raw T009 state for lab harnesses: zone node counts and every grip factor per tire.
local function modelState()
  local out = {}
  eachTire(function(wd)
    local id, z = wd.wheelID, zones[wd.wheelID]
    out[#out + 1] = {name=wd.name, zone_nodes=z and {#z[1], #z[2], #z[3]} or nil, zones_c=zoneC[id],
      psi=psiOf(wd), ideal_psi=ideal[id], heat_grip=heatGrip(wd, lastC[id], zoneC[id]),
      pressure_grip=pressureGrip(wd, psiOf(wd), ideal[id]), damage_grip=damageGrip(id),
      grain=grain[id], blister=blister[id], dirt=dirt[id], surface=surface[id], grip=applied[id]}
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
  if active and parts.heat then damageStep(dt) end
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
  guihooks.trigger('ACNGTires', {schema_version=2, mode='off'})
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
M.modelState = modelState
M.idealPsi = idealPsi
M.pressureGrip = pressureGrip
M.damageGrip = damageGrip
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
