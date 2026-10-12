-- T009c isolated in-game validation of tire dirt; not distributed in the mod.
-- Stock etkc kc6_360_M on the stock Grid Map v2 ground-model area, driven through the real
-- ACNG controls. The car starts on grass north of the spawn_groundmodels point and holds
-- 12 m/s due south along x = -322.7: about 84 m of grass, 14 m of dirt, then asphalt.
--   armed     heat ON (sport) at the start line
--   drive     1 s samples: position, contact material, dirt, damage grip and grip per tire
--   after     stop on asphalt
--   reset     a reset gives clean tires (the car resets onto the grass start)
--   disabled  tire_temperature OFF unloads the tire model
-- It also writes /acng-film-cues.json so tools/film_lab.py can cut a clip of the drive.
local M={}
local elapsed,stageTime,phase,simTime,controlTime=0,0,0,0,0
local SAMPLE_S=1
local LINE_X=-322.68                 -- spawn_groundmodels x + 15 m
local START_Y,END_Y=-391.36,-760     -- spawn y + 100 m; about 270 m of asphalt in
local SPEED=12
local LOOSE={[7]=true,[14]=true,[15]=true,[16]=true,[17]=true,[18]=true,[19]=true,[20]=true,[22]=true,[31]=true}
local TARMAC={[10]=true,[11]=true,[29]=true,[30]=true}
local result={schema_version=1,test='T009c tire dirt in-game validation',model='etkc',config='kc6_360_M',
  level='gridmap_v2',line_x=LINE_X,start_y=START_Y,end_y=END_Y,speed_m_s=SPEED,
  completed=false,checks={},samples={},events={},errors={},summary={}}
local cues={schema_version=1,cues={}}
local drive,startTries=nil,0
local function save() jsonWriteFile('/acng-tiredirt-test.json',result,true) end
local function cue(name) cues.cues[#cues.cues+1]={name=name,seq=#cues.cues+1,sim_time_s=simTime};jsonWriteFile('/acng-film-cues.json',cues,true) end
local function event(name) result.events[#result.events+1]={name=name,sim_time_s=simTime};log('I','ACNG_T009C',name);save() end
local function command(veh,cmd) veh:queueLuaCommand(cmd) end
local function status() return extensions.acng_core.getStatus() end
local HELPER=[[
rawset(_G,"acngTDi",{})
local function send(kind,data) obj:queueGameEngineLua(string.format('extensions.acng_tiredirt.receive(%q,%q)',kind,jsonEncode(data))) end
function acngTDi.sample(tag)
  local ok,err=pcall(function()
    local loaded=extensions.isExtensionLoaded('acng_tires')
    local m=loaded and extensions.acng_tires or nil
    local snap=m and m.getSnapshot() or nil
    local model={}
    for _,t in ipairs(m and m.modelState() or {}) do model[t.name]=t end
    local p=obj:getPosition()
    local out={tag=tag,loaded=loaded,heat=snap and snap.heat,profile=snap and snap.profile,min_grip=m and m.MIN_GRIP,
      grain_loss=m and m.GRAIN_GRIP_LOSS,blister_loss=m and m.BLISTER_GRIP_LOSS,dirt_loss=m and m.DIRT_GRIP_LOSS,
      pos={p.x,p.y,p.z},wheels={}}
    for i=0,tableSizeC(v.data.wheels)-1 do
      local wd=v.data.wheels[i]
      local rt=wheels.wheels[wd.cid] or {}
      local ms=model[wd.name] or {}
      out.wheels[#out.wheels+1]={name=wd.name,mat=rt.contactMaterialID1,wheel_speed=rt.wheelSpeed,
        deflated=rt.isTireDeflated==true,heat_grip=ms.heat_grip,pressure_grip=ms.pressure_grip,
        damage_grip=ms.damage_grip,grain=ms.grain,blister=ms.blister,dirt=ms.dirt,surface=ms.surface,grip=ms.grip}
    end
    send('sample',out)
  end)
  if not ok then send('error',{tag=tag,error=tostring(err)}) end
end
]]
local function sample(veh,tag) command(veh,string.format('acngTDi.sample(%q)',tag)) end
local function receive(kind,text)
  local d=jsonDecode(text) or {}
  if kind=='error' then result.errors[#result.errors+1]=d
  else
    d.t=simTime;d.part=d.tag and d.tag:match('^[^#]+')
    result.samples[#result.samples+1]=d
  end
  save()
end
local function heading() return quatFromDir(vec3(0,-1,0),vec3(0,0,1)) end
local function teleport(veh,flip)
  local pos=vec3(LINE_X,START_Y,0)
  pos.z=be:getSurfaceHeightBelow(vec3(LINE_X,START_Y,200))+0.3
  local rot=flip and quatFromDir(vec3(0,1,0),vec3(0,0,1)) or heading()
  spawn.safeTeleport(veh,pos,rot)
  result.teleport={x=pos.x,y=pos.y,z=pos.z,flipped=flip==true}
end
-- Hold SPEED with throttle and the line with steering: steering right is positive, and
-- facing south the car's right is west (-x).
local function startDrive(veh)
  drive={t=0,n=0,maxOff=0}
  command(veh,"controller.mainController.setGearboxMode('arcade'); input.event('parkingbrake',0,1); input.event('clutch',0,1); input.event('brake',0,1); input.event('steering',0,2)")
end
local function stopDrive(veh)
  drive=nil
  command(veh,"controller.mainController.setGearboxMode('realistic'); input.event('throttle',0,1); input.event('clutch',1,1); input.event('steering',0,2); input.event('parkingbrake',0,1); input.event('brake',1,1)")
end
local function driveStep(veh,dtReal,dtSim)
  drive.t=drive.t+dtSim
  controlTime=controlTime+dtReal
  local p,d=veh:getPosition(),veh:getDirectionVector()
  local off=p.x-LINE_X
  drive.maxOff=math.max(drive.maxOff,math.abs(off))
  if controlTime>0.1 then
    controlTime=0
    local speed=veh:getVelocity():length()
    local steer=math.max(-0.3,math.min(0.3,0.04*off+1.2*d.x))
    command(veh,string.format("input.event('throttle',%.3f,1); input.event('steering',%.3f,2)",math.max(0,math.min(1,0.25*(SPEED-speed))),steer))
  end
  local n=math.floor(drive.t/SAMPLE_S)
  if n>drive.n then drive.n=n;sample(veh,'drive#'..n) end
end
local function find(tag) for _,s in ipairs(result.samples) do if s.tag==tag then return s end end end
local function partSamples(name)
  local out={}
  for _,s in ipairs(result.samples) do if s.part==name then out[#out+1]=s end end
  table.sort(out,function(a,b) return a.t<b.t end)
  return out
end
local function wheel(s,name) for _,w in ipairs(s and s.wheels or {}) do if w.name==name then return w end end end
local function dist2(a,b) return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2) end
local function evaluate()
  local c,sum=result.checks,result.summary
  local spawnS,armed=find('spawn'),find('armed')
  c.tires_not_loaded_while_off=spawnS~=nil and spawnS.loaded==false
  c.loaded_with_heat=armed~=nil and armed.loaded==true and armed.heat==true and armed.profile=='sport'
  -- The car settles on grass for a few seconds after the teleport and the reset; the wheels
  -- creep a few centimetres, which picks up a trace of dirt (0.001 is 4 cm).
  local start=true
  for _,w in ipairs(armed and armed.wheels or {}) do if (w.dirt or 1)>1e-3 then start=false end end
  c.clean_at_start=armed~=nil and start
  local samples=partSamples('drive')
  sum.drive_samples=#samples
  local mats,loose,maxLooseDirt,tarmacSeen={},false,0,false
  local offOk,onOk,nOff,nOn,nProduct,nLag,worstProduct=true,true,0,0,0,0,0
  for _,s in ipairs(samples) do
    for _,w in ipairs(s.wheels or {}) do
      if type(w.mat)=='number' then
        mats[tostring(w.mat)]=(mats[tostring(w.mat)] or 0)+1
        if LOOSE[w.mat] then loose=true;if not tarmacSeen then maxLooseDirt=math.max(maxLooseDirt,w.dirt or 0) end end
        if TARMAC[w.mat] then tarmacSeen=true end
      end
      if w.damage_grip and s.grain_loss then
        local base=(1-s.grain_loss*(w.grain or 0))*(1-s.blister_loss*(w.blister or 0))
        if TARMAC[w.surface] then
          if (w.dirt or 0)>0.01 then
            nOn=nOn+1
            if math.abs(w.damage_grip-base*(1-s.dirt_loss*w.dirt))>1e-6 then onOk=false end
          end
        else
          nOff=nOff+1
          if math.abs(w.damage_grip-base)>1e-6 then offOk=false end
        end
        if w.grip and w.heat_grip and w.pressure_grip then
          nProduct=nProduct+1
          local want=math.max(s.min_grip or 0.6,w.heat_grip*w.pressure_grip*w.damage_grip)
          worstProduct=math.max(worstProduct,math.abs(w.grip-want))
          if math.abs(w.grip-want)>0.006 then nLag=nLag+1 end
        end
      end
    end
  end
  sum.contact_materials=mats;sum.max_dirt_on_loose=maxLooseDirt
  sum.off_tarmac_tire_samples=nOff;sum.on_tarmac_dirty_tire_samples=nOn;sum.worst_grip_product_error=worstProduct
  sum.grip_product_lag_samples=nLag
  c.loose_ground_seen=loose
  c.tarmac_seen=tarmacSeen
  c.dirt_builds_on_loose=maxLooseDirt>=0.9
  c.no_dirt_loss_off_tarmac=nOff>=8 and offOk
  c.dirt_costs_grip_on_tarmac=nOn>=8 and onOk
  -- The model writes grip every 0.1 s and only on a GRIP_STEP (0.002) move, while the
  -- factors here are read live; a pressure swing between writes (e.g. a surface edge)
  -- leaves a lagging sample. Allow 2% of samples over 0.006, none over 0.015.
  c.grip_written_is_product=nProduct>=20 and nLag<=math.max(1,math.floor(nProduct*0.02)) and worstProduct<=0.015
  -- Cleaning: dirt lost per metre of road across the longest run of samples where a tire
  -- stayed on tarmac, against 1/DIRT_CLEAN_M (600 m). Wheel speed and road speed differ by
  -- the tire's slip and radius, so allow 25 %.
  sum.clean_rate={}
  local rates={}
  for _,name in ipairs({'FL','FR','RL','RR'}) do
    local first,last=nil,nil
    for _,s in ipairs(samples) do
      local w=wheel(s,name)
      if w and TARMAC[w.mat] and TARMAC[w.surface] and (w.dirt or 0)>0 then
        if not first then first={s=s,w=w} end
        last={s=s,w=w}
      elseif first and w and not TARMAC[w.mat] then first,last=nil,nil end
    end
    if first and last and last.s~=first.s then
      local m=dist2(first.s.pos,last.s.pos)
      local per=(first.w.dirt-last.w.dirt)/m
      sum.clean_rate[name]={metres=m,dirt_from=first.w.dirt,dirt_to=last.w.dirt,per_metre=per,expected=1/600}
      rates[#rates+1]=per
    end
  end
  local cleanOk=#rates==4
  for _,r in ipairs(rates) do if math.abs(r*600-1)>0.25 then cleanOk=false end end
  c.dirt_cleans_on_tarmac=cleanOk
  local last=samples[#samples]
  sum.end_pos=last and last.pos
  sum.max_line_offset_m=result.max_line_offset_m
  c.drove_the_line=(result.max_line_offset_m or 99)<3 and last~=nil and last.pos[2]<START_Y-250
  local rs=find('reset')
  local clean=rs~=nil and rs.loaded==true and #rs.wheels==4
  for _,w in ipairs(rs and rs.wheels or {}) do if (w.dirt or 1)>5e-3 then clean=false end end
  c.reset_clears_dirt=clean
  local ds=find('disabled')
  c.tires_unloaded_after_disable=ds~=nil and ds.loaded==false
  c.no_helper_errors=#result.errors==0
  local pass=true
  for _,v in pairs(c) do pass=pass and v==true end
  result.passed=pass
end
local function onUpdate(dtReal,dtSim)
  elapsed=elapsed+dtReal
  if phase==0 and elapsed>12 and core_modmanager.isReady() then
    freeroam_freeroam.startFreeroamByName('gridmap_v2','spawn_groundmodels');phase=1;return
  end
  if worldReadyState~=2 then return end
  local veh=be:getPlayerVehicle(0)
  if not veh then return end
  stageTime=stageTime+dtSim;simTime=simTime+dtSim
  if drive then driveStep(veh,dtReal,dtSim) end
  if phase==1 then
    core_vehicles.replaceVehicle('etkc',{config='vehicles/etkc/kc6_360_M.pc'});phase,stageTime=2,0
  elseif phase==2 and stageTime>8 and veh:getJBeamFilename()=='etkc' then
    command(veh,HELPER)
    -- A scripted level load leaves the main menu drawn over the drive; switch the UI to
    -- play so the film shows the ACNG HUD (and no menu or account name).
    guihooks.trigger('ChangeState',{state='play'})
    local st=status()
    result.checks.default_master_off=not st.enabled
    result.checks.default_tires_off=st.features.tire_temperature==false and st.physics_writes==0
    sample(veh,'spawn');event('spawned');phase,stageTime=3,0
  elseif phase==3 and stageTime>1 then
    teleport(veh,startTries>0);startTries=startTries+1;phase,stageTime=4,0
  elseif phase==4 and stageTime>3 then
    local d=veh:getDirectionVector()
    result.heading={x=d.x,y=d.y}
    if d.y<-0.95 then event('at_start');phase,stageTime=5,0
    elseif startTries<2 then phase,stageTime=3,0
    else result.checks.heading_south=false;evaluate();result.completed=true;event('wrong_heading');phase=99 end
  elseif phase==5 then
    result.checks.heading_south=true
    extensions.acng_core.setEnabled(true)
    extensions.acng_core.setFeature('tire_temperature',true)
    extensions.acng_core.setTireProfile('sport')
    event('heat_enabled');phase,stageTime=6,0
  elseif phase==6 and stageTime>3 then
    sample(veh,'armed')
    local st=status()
    result.checks.core_reports_heat=st.tires_vehicle_id==veh:getID() and st.physics_writes==1 and st.features.tire_temperature==true
    phase,stageTime=7,0
  elseif phase==7 and stageTime>1 then
    startDrive(veh);cue('drive_start');event('drive');phase,stageTime=8,0
  elseif phase==8 then
    local p=veh:getPosition()
    result.max_line_offset_m=drive and drive.maxOff
    local stuck=stageTime>10 and veh:getVelocity():length()<1
    if p.y<END_Y or stageTime>70 or stuck then
      if stuck then result.stuck_at={p.x,p.y} end
      sample(veh,'after_drive');stopDrive(veh);cue('drive_end');event('stop');phase,stageTime=9,0
    end
  elseif phase==9 and stageTime>4 then
    sample(veh,'after')
    command(veh,"input.event('throttle',0,1); obj:requestReset(RESET_PHYSICS)");phase,stageTime=10,0
  elseif phase==10 and stageTime>2 then
    sample(veh,'reset');phase,stageTime=11,0
  elseif phase==11 and stageTime>1 then
    extensions.acng_core.setFeature('tire_temperature',false);event('disabled');phase,stageTime=12,0
  elseif phase==12 and stageTime>3 then
    sample(veh,'disabled')
    local st=status()
    result.checks.core_reports_tires_off=st.tires_vehicle_id==nil and st.physics_writes==0
    phase,stageTime=13,0
  elseif phase==13 and stageTime>2 then
    evaluate();result.completed=true;cue('complete');event('complete');phase=14
  end
end
M.onUpdate=onUpdate
M.receive=receive
return M
