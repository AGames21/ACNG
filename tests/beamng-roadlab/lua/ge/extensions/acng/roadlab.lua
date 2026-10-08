-- FR001: controlled road-speed thermal proxy, not a real-road fidelity claim.
local M={}
local phase,elapsed,t,sim,sampling,control=0,0,0,0,0,0
local sets={
  {name='stock',enabled=false},
  {name='current',enabled=true},
  {name='road_candidate',enabled=true,heat={nodeToEnv=0.10,envMultStationary=0.3,envTerminalSpeed=40,
    nodeToCore=0.001,coreToNodes=0.001,nodeToSurface=0,friction=0.03,flashFriction=0,strain=0,heatAffectsPressure=true}},
}
local stages={{name='idle',duration=10},{name='cruise',duration=40,speed=22,steer=0},
  {name='corner',duration=30,speed=15,steer=0.12},
  {name='cruise_after',duration=30,speed=22,steer=0},{name='park',duration=30}}
local result={schema_version=1,test='FR001 controlled road-speed thermal proxy',completed=false,
  model='etkc',config='kc6_360_M',sets={},checks={},events={}}
local index,stage,cur=0,0,nil
local helper=[[
function acngRoadSample()
  local on=extensions.isExtensionLoaded('acng_tires')
  local out={loaded=on,w={}}
  for _,wd in pairs(wheels.wheelRotators) do if wd.hasTire then
    local pg=wd.pressureGroup and v.data.pressureGroups[wd.pressureGroup]
    out.w[wd.name]={s=obj:getWheelAvgTemperature(wd.wheelID)-273.15,
      c=obj:getWheelCoreTemperature(wd.wheelID)-273.15,
      psi=pg and (obj:getGroupPressure(pg)-101325)/6894.757 or nil}
  end end
  if on then out.heat=extensions.acng_tires.HEAT end
  obj:queueGameEngineLua(string.format('extensions.acng_roadlab.receive(%q)',jsonEncode(out)))
end
]]
local function save() jsonWriteFile('/acng-roadlab.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_s=sim};save();log('I','ACNG_FR001',name) end
local function cmd(v,c) v:queueLuaCommand(c) end
local function stop(v)
  cmd(v,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('brake',1,1); input.event('steering',0,2)")
end
local function receive(text)
  local s=jsonDecode(text);if not s or not cur then return end
  local veh=be:getPlayerVehicle(0)
  s.t=sim;s.stage=stages[stage] and stages[stage].name or 'reset';s.speed=veh and veh:getVelocity():length()
  cur.samples[#cur.samples+1]=s
end
local function nextStage(v)
  stage=stage+1;t=0
  local x=stages[stage]
  if not x then stop(v);phase=10;return end
  event(cur.name..'_'..x.name)
  if not x.speed then stop(v) else
    cmd(v,"controller.mainController.setGearboxMode('arcade'); input.event('clutch',0,1); input.event('parkingbrake',0,1); input.event('brake',0,1); input.event('steering',"..x.steer..",2)")
  end
end
local function onUpdate(dr,ds)
  elapsed=elapsed+dr
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local v=be:getPlayerVehicle(0);if not v then return end
  t=t+ds;sim=sim+ds
  if phase==1 then core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase=2;t=0
  elseif phase==2 and t>8 then
    result.checks.startup_off=not extensions.acng_core.getStatus().enabled
    cmd(v,helper);phase=10
  elseif phase==10 then
    index=index+1
    local set=sets[index]
    if not set then
      extensions.acng_core.setEnabled(false);stop(v);phase=40;t=0;return
    end
    extensions.acng_core.setEnabled(false)
    cur={name=set.name,samples={}};result.sets[#result.sets+1]=cur
    stage=0;stop(v);cmd(v,'obj:requestReset(RESET_PHYSICS)');phase=11;t=0
  elseif phase==11 and t>3 then
    local set=sets[index]
    if set.enabled then
      extensions.acng_core.setEnabled(true)
      extensions.acng_core.setFeature('tire_wear',false)
      extensions.acng_core.setFeature('tire_temperature',true)
    end
    phase=12;t=0
  elseif phase==12 and t>2 then
    local h=sets[index].heat
    if h then cmd(v,string.format('extensions.acng_tires.HEAT=jsonDecode(%q); extensions.acng_tires.onReset()',jsonEncode(h))) end
    phase=13;t=0
  elseif phase==13 and t>1 then nextStage(v);phase=20
  elseif phase==20 then
    sampling=sampling+ds;control=control+dr
    if sampling>=0.5 then sampling=0;cmd(v,'acngRoadSample()') end
    local x=stages[stage]
    if x.speed and control>=0.1 then
      control=0;local speed=v:getVelocity():length()
      cmd(v,string.format("input.event('throttle',%.3f,1); input.event('brake',%.3f,1)",math.max(0,math.min(1,0.25*(x.speed-speed))),math.max(0,math.min(0.4,0.2*(speed-x.speed)))))
    end
    if t>=x.duration then nextStage(v) end
  elseif phase==40 and t>2 then
    result.checks.final_master_off=not extensions.acng_core.getStatus().enabled
    result.checks.final_no_physics_writes=extensions.acng_core.getStatus().physics_writes==0
    result.completed=true;cur=nil;event('complete');phase=99
  end
end
M.onUpdate=onUpdate;M.receive=receive
return M
