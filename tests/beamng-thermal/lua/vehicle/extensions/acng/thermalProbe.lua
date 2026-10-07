-- T001: bounded native API experiment. Not a production physics module.
local M={}
local keys={'heatCoefNodeToEnv','heatCoefEnvMultStationary','heatCoefEnvTerminalSpeed','heatCoefNodeToCore','heatCoefCoreToNodes','heatCoefNodeToSurface','heatCoefFriction','heatCoefFlashFriction','heatCoefStrain','smokingTemp','meltingTemp','heatAffectsPressure'}
local fallback={0,0.4,20,0,0,0,0,0,0,1e18,1e19,false}
local saved={}
local function send(label,extra)
 local data={label=label,wheels={},extra=extra}
 for _,wd in pairs(wheels.wheels) do
  data.wheels[#data.wheels+1]={name=wd.name,average=obj:getWheelAvgTemperature(wd.wheelID),core=obj:getWheelCoreTemperature(wd.wheelID),broken=wd.isBroken,deflated=wd.isTireDeflated}
 end
 obj:queueGameEngineLua(string.format('extensions.acng_thermal.receive(%q)',jsonEncode(data)))
end
local function configure(factor)
 local records={}
 for _,wd in pairs(wheels.wheels) do
  local raw=v.data.wheels[wd.cid]
  assert(raw and wd.obj and wd.obj.setThermal,'Native thermal capability missing')
  assert(not wd.isBroken and not wd.isTireDeflated,'Test requires intact tires')
  assert((raw.frictionCoefLow or 1)==1 and (raw.frictionCoefMiddle or 1)==1 and (raw.frictionCoefHigh or 1)==1,'Factory thermal grip must be neutral')
  local params={}
  for i,key in ipairs(keys) do
   if raw[key]==nil then params[i]=fallback[i] else params[i]=raw[key] end
  end
  assert(params[12]==false,'Factory heat-to-pressure must be disabled')
  saved[wd.cid]={object=wd.obj,params=params}
  local changed={unpack(params)};changed[7]=factor
  wd.obj:setThermal(unpack(changed))
  records[#records+1]={name=wd.name,factory=params,factor=factor}
 end
 send('configured',records)
end
local function restore()
 for _,item in pairs(saved) do item.object:setThermal(unpack(item.params)) end
 saved={};send('restored')
end
M.configure=configure
M.snapshot=send
M.restore=restore
return M
