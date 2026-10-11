-- T008a exploratory probe for the AC-style tire model; not distributed in the mod.
-- Records, on the stock etkc at smallgrid: the tread node layout across each tire (for
-- inner/middle/outer zone temperatures), the native tire pressure variables, how native
-- strain (rolling flex) heat scales with its coefficient and with tire pressure, and
-- whether native tread node temperatures already split across the tire in a corner.
-- Right-side wheels get the probed strain value, left-side wheels stay at the ACNG
-- default (strain 0), so each straight-line segment has its own control.
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local result={test='T008a tire model probe',model='etkc',config='kc6_360_M',completed=false,
  structure=nil,segments={},samples={},events={}}
local SEGMENTS={
  {name='strain_0.001',strainR=0.001,speed=25,steer=0,time=45},
  {name='strain_0.01',strainR=0.01,speed=25,steer=0,time=45},
  {name='strain_0.1',strainR=0.1,speed=25,steer=0,time=45},
  {name='strain_1',strainR=1,speed=25,steer=0,time=45},
  {name='pressure_left_minus8',strainAll=0.1,leftPsi=-8,speed=25,steer=0,time=45},
  {name='circle',speed=10,steer=0.5,time=60},
}
local seg,segIndex,driving,sampleN=nil,0,false,0
local function save() jsonWriteFile('/acng-tireprobe-test.json',result,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T008A',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local HELPER=[[
rawset(_G,"acngTP",{zones={}})
local K=273.15
local function send(kind,data) obj:queueGameEngineLua(string.format('extensions.acng_tireprobe.receive(%q,%q)',kind,jsonEncode(data))) end
local function wheelList() local out={} for i=0,tableSizeC(v.data.wheels)-1 do out[#out+1]=v.data.wheels[i] end return out end
function acngTP.structure()
  local out={wheels={},vars={},env_c=obj:getEnvTemperature()-K}
  local list=wheelList()
  local centre=vec3(0,0,0)
  for _,wd in ipairs(list) do centre=centre+(obj:getNodePosition(wd.node1)+obj:getNodePosition(wd.node2))*0.5 end
  centre=centre/math.max(1,#list)
  for _,wd in ipairs(list) do
    local p1,p2=obj:getNodePosition(wd.node1),obj:getNodePosition(wd.node2)
    local innerIs1=(p1-centre):length()<(p2-centre):length()
    local pin,pout=innerIs1 and p1 or p2,innerIs1 and p2 or p1
    local axis=(pout-pin):normalized()
    local mid=(p1+p2)*0.5
    local offs,lo,hi={},math.huge,-math.huge
    for _,nid in pairs(wd.treadNodes or {}) do
      local o=(obj:getNodePosition(nid)-mid):dot(axis)
      offs[#offs+1]={nid=nid,o=o};lo=math.min(lo,o);hi=math.max(hi,o)
    end
    local z={inner={},mid={},outer={}}
    local hist={}
    for _,e in ipairs(offs) do
      local t=hi>lo and (e.o-lo)/(hi-lo) or 0.5
      local key=t<1/3 and 'inner' or t>2/3 and 'outer' or 'mid'
      table.insert(z[key],e.nid)
      local r=string.format('%.3f',e.o);hist[r]=(hist[r] or 0)+1
    end
    acngTP.zones[wd.wheelID]=z
    local nodeCount=0 for _ in pairs(wd.nodes or {}) do nodeCount=nodeCount+1 end
    out.wheels[#out.wheels+1]={name=wd.name,id=wd.wheelID,cid=wd.cid,node1=wd.node1,node2=wd.node2,
      inner_is_node1=innerIs1,tread_nodes=#offs,nodes=nodeCount,offset_hist=hist,
      zone_counts={#z.inner,#z.mid,#z.outer},pressure_group=wd.pressureGroup,pressure_psi=wd.pressurePSI,radius=wd.radius,
      width=(p2-p1):length(),noLoadCoef=wd.noLoadCoef,fullLoadCoef=wd.fullLoadCoef,
      loadSensitivitySlope=wd.loadSensitivitySlope,treadCoef=wd.treadCoef}
  end
  for name,var in pairs(v.data.variables or {}) do
    local n=tostring(name):lower()
    if n:find('press',1,true) or n:find('tire',1,true) or n:find('camber',1,true) then
      out.vars[name]={val=var.val,default=var.default,min=var.min,max=var.max,unit=var.unit,title=var.title}
    end
  end
  send('structure',out)
end
function acngTP.setStrain(rightValue,allValue)
  for _,wd in ipairs(wheelList()) do
    local wobj=obj:getWheel(wd.wheelID)
    local value=allValue or (tostring(wd.name):match('R$') and rightValue) or nil
    if wobj and value then
      local t=extensions.acng_tires.acngThermal(wd)
      t[9]=value
      wobj:setThermal(t[1],t[2],t[3],t[4],t[5],t[6],t[7],t[8],t[9],t[10],t[11],t[12])
    end
  end
end
function acngTP.leftPressure(dpsi)
  for _,wd in ipairs(wheelList()) do
    local pg=wd.pressureGroup and v.data.pressureGroups[wd.pressureGroup]
    if pg and tostring(wd.name):match('L$') then obj:setGroupPressure(pg,obj:getGroupPressure(pg)+dpsi*6894.757) end
  end
end
local function mean(list)
  local s,n=0,0
  for _,nid in ipairs(list or {}) do local t=obj:getNodeTemperature(nid) if type(t)=='number' then s=s+t;n=n+1 end end
  return n>0 and s/n-K or nil
end
function acngTP.sample(tag)
  local out={tag=tag,wheels={}}
  for _,wd in ipairs(wheelList()) do
    local z=acngTP.zones[wd.wheelID] or {}
    local pg=wd.pressureGroup and v.data.pressureGroups[wd.pressureGroup]
    local rt=wheels.wheels[wd.cid] or {}
    out.wheels[#out.wheels+1]={name=wd.name,avg=obj:getWheelAvgTemperature(wd.wheelID)-K,
      core=obj:getWheelCoreTemperature(wd.wheelID)-K,psi=pg and (obj:getGroupPressure(pg)-101325)/6894.757 or nil,
      inner=mean(z.inner),mid=mean(z.mid),outer=mean(z.outer),mat1=rt.contactMaterialID1,mat2=rt.contactMaterialID2,
      down=rt.downForce,slip=rt.slipEnergy,side=rt.lastSideSlip}
  end
  send('sample',out)
end
]]
local function sample(veh,tag) command(veh,string.format('acngTP.sample(%q)',tag)) end
local function receive(kind,text)
  local d=jsonDecode(text) or {}
  if kind=='structure' then result.structure=d
  else d.t=simTime;d.segment=seg and seg.name;result.samples[#result.samples+1]=d end
  save()
end
local function startDrive(veh)
  driving=true
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',"..seg.steer..",2)")
end
local function stopDrive(veh)
  driving=false
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroam('/levels/smallgrid/');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  if driving then
    controlTime=controlTime+dtReal
    if controlTime>0.1 then
      controlTime=0
      local speed=veh:getVelocity():length()
      command(veh,string.format("input.event('throttle',%.3f,1)",math.max(0,math.min(1,0.25*(seg.speed-speed)))))
    end
  end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER);command(veh,'acngTP.structure()')
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    event('enabled');phase,stageTime=3,0
  elseif phase==3 and stageTime>2 then
    segIndex=segIndex+1;seg=SEGMENTS[segIndex]
    if not seg then result.completed=true;event('complete');phase=99;return end
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)")
    phase,stageTime=4,0
  elseif phase==4 and stageTime>2.5 then
    command(veh,string.format('acngTP.setStrain(%s,%s)',tostring(seg.strainR or 'nil'),tostring(seg.strainAll or 'nil')))
    if seg.leftPsi then command(veh,string.format('acngTP.leftPressure(%s)',seg.leftPsi)) end
    phase,stageTime=5,0
  elseif phase==5 and stageTime>1 then
    sample(veh,seg.name..'#0');sampleN=0;startDrive(veh);event(seg.name);phase,stageTime=6,0
  elseif phase==6 then
    local n=math.floor(stageTime/5)
    if n>sampleN then sampleN=n;sample(veh,seg.name..'#'..n) end
    if stageTime>seg.time+0.5 then stopDrive(veh);phase,stageTime=3,0 end
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
