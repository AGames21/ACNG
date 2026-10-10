-- C005 native handling measurements. Test-profile only; no production hooks or force writes.
local M={}
local latest
local G=9.80665
local SAMPLE=[[
local r={damage=beamstate.damage,wheels={}}
local f=obj:getDirectionVector();local u=obj:getDirectionVectorUp();local right=f:cross(u)
local vel=obj:getVelocity();r.forward_m_s=vel:dot(f);r.side_m_s=vel:dot(right)
for _,w in pairs(wheels.wheelRotators) do if w.hasTire then
 local a=obj:getNodePosition(w.node1);local ax,ay,az=a.x,a.y,a.z
 local b=obj:getNodePosition(w.node2);local axis=vec3(ax-b.x,ay-b.y,az-b.z):normalized()
 local longitudinal=axis:cross(u);if longitudinal:dot(f)<0 then longitudinal=-longitudinal end
 r.wheels[#r.wheels+1]={name=w.name,load_n=w.downForceRaw,
  steer_rad=math.atan2(longitudinal:dot(right),longitudinal:dot(f)),
  slip_m_s=w.lastSlip,side_slip_m_s=w.lastSideSlip,
  broken=w.isBroken==true,deflated=w.isTireDeflated==true}
end end
r.throttle=electrics.values.throttle;r.brake=electrics.values.brake
r.gear=electrics.values.gearIndex;r.rpm=electrics.values.rpm
if not acngC5Mass then
 local mass,cg,front,rear,nf,nr=0,0,0,0,0,0
 for id,node in pairs(v.data.nodes) do
  local m=obj:getNodeMass(node.cid or id);local p=obj:getNodePosition(node.cid or id)
  mass=mass+m;cg=cg+m*p:dot(f)
 end
 for _,w in pairs(wheels.wheelRotators) do if w.hasTire then
  local a=obj:getNodePosition(w.node1);local along=a:dot(f)
  local b=obj:getNodePosition(w.node2);along=(along+b:dot(f))*0.5
  if w.name=='FL' or w.name=='FR' then front=front+along;nf=nf+1
  elseif w.name=='RL' or w.name=='RR' then rear=rear+along;nr=nr+1 end
 end end
 assert(nf==2 and nr==2 and mass>0,'Static axle geometry unavailable')
 front=front/nf;rear=rear/nr
 acngC5Mass={mass_kg=mass,wheelbase_m=front-rear,front_mass_fraction=(cg/mass-rear)/(front-rear)}
end
r.static=acngC5Mass
obj:queueGameEngineLua(string.format('extensions.acng_handlinglab.receive(%q)',jsonEncode(r)))
]]
M.receive=function(encoded) latest=jsonDecode(encoded) end
function M.run(veh,now,delay,massKg)
  massKg=massKg or 1495 -- BMW 1M
  local out={schema_version=1,completed=false,map='smallgrid',master=false,
    transmission='native arcade automatic shifts',assists='native donor factory defaults',
    acceleration={},braking={},circles={},samples={},starts={},checks={}}
  local function save() jsonWriteFile('/acng-handling-test.json',out,true) end
  local function command(s) veh:queueLuaCommand(s) end
  local function stop()
    command("controller.mainController.setGearboxMode('realistic');input.event('throttle',0,1);input.event('brake',1,1);input.event('clutch',1,1);input.event('steering',0,2)")
  end
  local function reset()
    stop();delay(1);command('obj:requestReset(RESET_PHYSICS)');delay(3)
    spawn.safeTeleport(veh,vec3(0,0,1),quat(0,0,0,1));delay(4)
    command("controller.mainController.setGearboxMode('arcade');input.event('parkingbrake',0,1);input.event('clutch',0,1);input.event('brake',0,1);input.event('steering',0,2);input.event('throttle',0,1)")
    delay(1);latest=nil;command('acngC5Mass=nil\n'..SAMPLE);delay(0.3)
    assert(latest and latest.damage<50,'Handling start damaged or missing native sample')
    assert(veh:getVelocity():length()<0.1,'Handling start is moving')
    assert(latest.static and math.abs(latest.static.mass_kg-massKg)/massKg<0.03,'Handling mass outside target')
    out.starts[#out.starts+1]={stage=out.stage,static=latest.static}
  end
  local function record(phase)
    local p=veh:getPosition();local v=veh:getVelocity();local d=veh:getDirectionVector()
    local r={t=now(),phase=phase,speed_m_s=v:length(),x=p.x,y=p.y,
      heading_rad=math.atan2(d.y,d.x),native=latest}
    out.samples[#out.samples+1]=r
    if not out.last_probe_t or r.t-out.last_probe_t>=0.05 then command(SAMPLE);out.last_probe_t=r.t end
    return r
  end
  local function cross(a,b,speed,key)
    local q=(speed-a.speed_m_s)/(b.speed_m_s-a.speed_m_s)
    return a[key]+q*(b[key]-a[key])
  end
  for i=1,5 do
    out.stage='straight '..i;reset();save()
    local start=now();command("input.event('throttle',1,1)")
    local last=record('accel_'..i);local first,finish
    while now()-start<25 do
      coroutine.yield();local r=record('accel_'..i)
      if not first and last.speed_m_s<=0.1 and r.speed_m_s>0.1 then first=cross(last,r,0.1,'t') end
      if last.speed_m_s<100/3.6 and r.speed_m_s>=100/3.6 then finish=cross(last,r,100/3.6,'t');break end
      last=r
    end
    assert(first and finish,'100 km/h acceleration crossing missing')
    out.acceleration[#out.acceleration+1]={repeat_index=i,time_s=finish-first,start_threshold_m_s=0.1}
    -- Accelerate slightly past 100; stamp the actual descending crossing after the brake edge.
    command("input.event('throttle',0,1);controller.mainController.setGearboxMode('realistic');input.event('clutch',1,1);input.event('brake',1,1)")
    last=record('brake_'..i);local from,to,fromX,fromY,toX,toY
    local brakeVerified=false
    local deadline=now()+15
    while now()<deadline do
      coroutine.yield();local r=record('brake_'..i)
      if r.speed_m_s>10 and r.speed_m_s<25 and latest and (latest.brake or 0)>0.95 then brakeVerified=true end
      if not from and last.speed_m_s>=100/3.6 and r.speed_m_s<100/3.6 then
        from=cross(last,r,100/3.6,'t');fromX=cross(last,r,100/3.6,'x');fromY=cross(last,r,100/3.6,'y')
      end
      if from and last.speed_m_s>0.1 and r.speed_m_s<=0.1 then
        to=cross(last,r,0.1,'t');toX=cross(last,r,0.1,'x');toY=cross(last,r,0.1,'y');break
      end
      last=r
    end
    assert(from and to,'100-0 descending crossings missing')
    assert(brakeVerified,'Actual native full brake not verified')
    out.braking[#out.braking+1]={repeat_index=i,time_s=to-from,distance_m=math.sqrt((toX-fromX)^2+(toY-fromY)^2),stop_threshold_m_s=0.1}
    stop();save()
  end
  for _,steer in ipairs({0.12,0.25}) do
    for _,target in ipairs({6,10,14,18,22}) do
      out.stage=string.format('circle %.2f %.0f',steer,target);reset();save()
      command(string.format("input.event('steering',%.3f,2)",steer))
      local start,control,last=now(),-1,nil
      local rows={};local yawSum,speedSum,duration,sideMax=0,0,0,0
      while now()-start<22 do
        coroutine.yield();local t=now();local speed=veh:getVelocity():length()
        if t-control>=0.1 then
          local err=target-speed
          command(string.format("input.event('throttle',%.4f,1);input.event('brake',%.4f,1)",math.max(0,math.min(1,err*0.4)),math.max(0,math.min(0.3,-err*0.15))))
          control=t
        end
        local r=record(out.stage)
        if t-start>=12 and last and t>last.t then
          local dt=t-last.t;local dh=(r.heading_rad-last.heading_rad+math.pi)%(2*math.pi)-math.pi
          yawSum=yawSum+dh;speedSum=speedSum+0.5*(r.speed_m_s+last.speed_m_s)*dt;duration=duration+dt
          local beta=latest and math.atan2(latest.side_m_s,latest.forward_m_s) or math.pi
          sideMax=math.max(sideMax,math.abs(beta));rows[#rows+1]=r
        end
        last=r
      end
      local mean=speedSum/duration;local yaw=math.abs(yawSum/duration)
      local speedDev=0;for _,r in ipairs(rows) do speedDev=math.max(speedDev,math.abs(r.speed_m_s-mean)) end
      local angle,n,fl,rl=0,0,0,0
      for _,r in ipairs(rows) do for _,w in ipairs(r.native and r.native.wheels or {}) do
        if w.name=='FL' or w.name=='FR' then angle=angle+math.abs(w.steer_rad);n=n+1;fl=fl+(w.load_n or 0)
        elseif w.name=='RL' or w.name=='RR' then rl=rl+(w.load_n or 0) end
      end end
      local valid=duration>8 and speedDev<0.5 and math.abs(mean-target)<0.5 and sideMax<math.rad(8) and yaw>0.01 and latest and latest.damage<200
      out.circles[#out.circles+1]={input=steer,target_m_s=target,speed_m_s=mean,yaw_rad_s=yaw,radius_m=mean/yaw,
        lateral_g=mean*yaw/G,steer_rad=n>0 and angle/n or nil,max_body_sideslip_deg=math.deg(sideMax),
        max_speed_deviation_m_s=speedDev,front_load_fraction=(fl+rl)>0 and fl/(fl+rl) or nil,valid_steady=valid}
      stop();save()
    end
  end
  local maxg=0;local valid=0
  for _,r in ipairs(out.circles) do if r.valid_steady then maxg=math.max(maxg,r.lateral_g);valid=valid+1 end end
  out.max_valid_steady_lateral_g=maxg;out.checks.five_straight_repeats=#out.acceleration==5 and #out.braking==5
  out.checks.steady_circle_samples=valid>=3;out.checks.finished_undamaged=latest and latest.damage<200
  out.completed=true;out.stage='done';stop();save();return out
end
return M
