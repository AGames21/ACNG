-- Test-only sparse native damage snapshots, not a physics model.
local M={}
local function snapshot(label)
  local groups={}
  for name,group in pairs(beamstate.deformGroupDamage or {}) do
    if (group.eventCount or 0)>0 then
      groups[name]={event_count=group.eventCount,damage_native=group.damage}
    end
  end
  local wheelRows={}
  for id,wd in pairs(wheels.wheels or {}) do
    wheelRows[#wheelRows+1]={id=id,cid=wd.cid,name=wd.name,broken=wd.isBroken==true,
      deflated=wd.isTireDeflated==true,break_group=wd.breakGroup}
  end
  local data={label=label,damage_native=beamstate.damage,deform_groups=groups,wheels=wheelRows}
  obj:queueGameEngineLua(string.format('extensions.acng_damage.receive(%q)',jsonEncode(data)))
end
local function puncture()
  for _,wd in pairs(wheels.wheels or {}) do
    if wd.name=='FL' then beamstate.deflateTire(wd.cid); snapshot('puncture_requested'); return end
  end
  snapshot('puncture_unavailable')
end
local function breakWheel()
  local present=false
  for _,beam in pairs(v.data.beams or {}) do
    if beam.breakGroup=='wheel_FL' then present=true;break end
    if type(beam.breakGroup)=='table' then
      for _,group in pairs(beam.breakGroup) do if group=='wheel_FL' then present=true end end
    end
  end
  if present then beamstate.breakBreakGroup('wheel_FL'); snapshot('wheel_break_requested')
  else snapshot('wheel_break_unavailable') end
end
M.snapshot=snapshot
M.puncture=puncture
M.breakWheel=breakWheel
return M
