-- ACNG one-shot gear-change sound for locally converted cars (original code).
-- BeamNG's playSFXOnceCT only plays FMOD events, so a WAV path given to the native lever
-- controllers is never heard. This plays the car's own upshift / downshift recording through a
-- file source (createSFXSource2 + cutSFX/playSFX, the pattern BeamNG uses for blow-off WAVs) and
-- stops it after the recording's length. The build copies it to vehicles/<model>/lua/controller/.
local M = {}
M.type = "auxiliary"

local gearbox
local node = 0
local volume = 0.5
local sounds = {}
local previousGear = 0
local engagedGear = 0 -- last non-neutral gear, so an H-pattern 3-N-2 still sounds like a downshift
local elapsed = 0

local function source(direction)
  local s = sounds[direction]
  if s and not s.id and s.file then
    s.id = obj:createSFXSource2(s.file, "AudioDefaultLoop3D", "acngShift_" .. direction, node, 0)
  end
  return s and s.id
end

local function play(direction)
  local id = source(direction)
  if not id or id < 0 then return end
  local s = sounds[direction]
  obj:setVolumePitchCT(id, volume, 1, 0, 0)
  obj:cutSFX(id)
  obj:playSFX(id)
  s.stopAt = elapsed + s.seconds
  M.plays = M.plays + 1
  electrics.values.acngShiftSounds = M.plays
end

local function updateGFX(dt)
  elapsed = elapsed + dt
  for _, s in pairs(sounds) do
    if s.stopAt and elapsed >= s.stopAt then
      obj:stopSFX(s.id)
      s.stopAt = nil
    end
  end
  local gear = gearbox.gearIndex or 0
  if gear ~= previousGear then
    -- Into neutral is silent. Each engagement compares with the last engaged gear, so a
    -- sequential 3->2 and an H-pattern 3->N->2 both play "down"; first gear from rest is "up".
    if gear ~= 0 then
      play(gear > engagedGear and "up" or "down")
      engagedGear = gear
    end
    previousGear = gear
  end
end

local function reset()
  previousGear = gearbox and gearbox.gearIndex or 0
  engagedGear = previousGear
  for _, s in pairs(sounds) do
    if s.id and s.stopAt then obj:stopSFX(s.id) end
    s.stopAt = nil
  end
end

local function init(jbeamData)
  M.plays = 0
  electrics.values.acngShiftSounds = 0
  gearbox = powertrain.getDevice(jbeamData.gearboxName or "gearbox")
  local nodes = jbeamData.soundNode_nodes
  node = type(nodes) == "table" and type(nodes[1]) == "number" and nodes[1] or 0
  volume = jbeamData.volume or 0.5
  sounds = {
    up = {file = jbeamData.upSample, seconds = jbeamData.upSeconds or 0.5},
    down = {file = jbeamData.downSample or jbeamData.upSample, seconds = jbeamData.downSeconds or jbeamData.upSeconds or 0.5}
  }
  if not gearbox then
    log("W", "acng_shiftSound.init", "No gearbox device; shift sounds disabled")
    M.updateGFX = nop
    return
  end
  M.updateGFX = updateGFX
  reset()
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX

return M
