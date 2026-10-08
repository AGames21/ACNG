-- Original session orchestration over BeamNG's native ordered-checkpoint race API.
local M = {}
local phase, message = 'off', 'Load Hirochi Raceway, then PREPARE.'
local entrants, owned, qualifying = {}, {}, {}
local race, path, startPos, startRot, playerId
local clock, countdown, uiTime, spawning = 0, 0, 0, 0
local options = {opponents=0, laps=3, minutes=3, aggression=0.75}
local pendingPhase, positioning = nil, false
local function object(id) return be:getObjectByID(id) end
local function master()
  if not extensions.isExtensionLoaded('acng_core') then return false end
  local s=extensions.acng_core.getStatus();return s.enabled and s.features.race_sessions==true
end
local function stopAI()
  for id in pairs(owned) do local v=object(id); if v then v:queueLuaCommand('ai.setMode("stop");controller.setFreeze(false)') end end
end
local function releasePlayer()
  local v=playerId and object(playerId); if v then v:queueLuaCommand('controller.setFreeze(false)') end
end
local function cancel()
  if race then race.started=false end
  stopAI(); releasePlayer()
  for id in pairs(owned) do local v=object(id); if v then v:delete() end end
  race,path,playerId=nil,nil,nil; entrants,owned,qualifying={},{},{}
  phase,pendingPhase='off',nil; message='Weekend stopped; owned opponents removed.'
  return true
end
local function fail(text)
  cancel(); message=text; return false
end
local function setOption(name,value)
  if phase~='off' and phase~='ready' and phase~='results' then return false end
  local limits={opponents={0,3},laps={1,10},minutes={1,15},aggression={0.3,1}}
  local lim=limits[name]
  if not lim or type(value)~='number' or value~=value or value<lim[1] or value>lim[2] then return false end
  if name~='aggression' and value~=math.floor(value) then return false end
  if name=='opponents' and phase~='off' then return false end
  options[name]=value; return true
end
local function qualificationOrder(list,times)
  local out={}; for i,e in ipairs(list) do out[i]=e end
  table.sort(out,function(a,b)
    local av,bv=times[a.id],times[b.id]
    if av==bv then return a.seed<b.seed end
    if not av then return false end; if not bv then return true end
    return av<bv
  end)
  return out
end
local function bestLap(state)
  local best
  -- BeamNG 0.39 initializes bestLapTime but does not populate it; completed laps
  -- are authoritative in historicTimes, each with a duration in seconds.
  for _,lap in ipairs(state and state.historicTimes or {}) do
    local t=lap.duration
    if type(t)=='number' and t==t and t>0 and t<math.huge and (not best or t<best) then best=t end
  end
  return best
end
local function makePath()
  local names={'hr_start','quickrace_wp6','quickrace_wp4'}; local checkpoints={}
  for _,name in ipairs(names) do
    local cp=scenetree.findObject(name); if not cp then return false,'Circuit waypoint unavailable: '..name end
    checkpoints[#checkpoints+1]=cp
  end
  path=require('/lua/ge/extensions/gameplay/race/path')('ACNG Hirochi Short')
  path:fromCheckpointList(checkpoints,true)
  path.startNode=path.pathnodes.sorted[1].id; path:autoConfig()
  if not path.config.closed or path.branching then return false,'A closed, unbranched circuit is required.' end
  local first=path.pathnodes.sorted[1]
  local dir=first.normal or (path.pathnodes.sorted[2].pos-first.pos):normalized()
  startPos=vec3(first.pos); startRot=quatFromDir(dir,vec3(0,0,1))
  return true
end
local function grid(list)
  positioning=true
  for i,e in ipairs(list) do
    local v=object(e.id)
    if v then
      -- Native start-position movement with repair=false preserves existing damage.
      local sp=path.startPositions:create('ACNG grid '..i)
      sp.pos=startPos+startRot*vec3((i%2==1 and -1 or 1)*1.8,8+math.floor((i-1)/2)*8,0.15)
      sp.rot=startRot
      sp:moveResetVehicleTo(e.id,false,false)
      path.startPositions:remove(sp.id)
      v:queueLuaCommand('controller.setFreeze(true)')
    end
  end
  positioning=false
end
local function prepare()
  if phase~='off' then return false end
  if not master() then message='Enable the ACNG master first.'; return false end
  if not getMissionFilename() or not getMissionFilename():lower():find('hirochi_raceway',1,true) then
    message='First release supports Hirochi Raceway Short only.'; return false
  end
  if extensions.isExtensionLoaded('scenario_scenarios') and scenario_scenarios.getScenario() then
    message='Return to freeroam before preparing a weekend.'; return false
  end
  local veh=be:getPlayerVehicle(0); if not veh then return false end
  local ok,why=makePath(); if not ok then return fail(why) end
  playerId=veh:getID(); entrants={{id=playerId,name='YOU',seed=1,player=true}}
  phase,spawning,clock='preparing',0,0; message='Building your grid…'
  return true
end
local function begin(which)
  if not master() then return false end
  if which~='practice' and which~='qualifying' and which~='race' then return false end
  if phase~='ready' and phase~='results' then return false end
  if which=='qualifying' then qualifying={} end
  pendingPhase=which
  grid(which=='race' and qualificationOrder(entrants,qualifying) or entrants)
  phase,countdown,clock='countdown',5,0; message='Grid forming'
  return true
end
local function finish()
  stopAI(); releasePlayer(); if race then race.started=false end
  phase='results'; message=pendingPhase=='race' and 'CHEQUERED FLAG' or 'SESSION COMPLETE'
end
local function retire(id,reason)
  for _,e in ipairs(entrants) do
    if e.id==id then
      e.retired=reason or 'DNF'
      if race and race.states[id] then race.states[id].active=false end
      local v=owned[id] and object(id); if v then v:queueLuaCommand('ai.setMode("stop")') end
      return true
    end
  end
  return false
end
local function startSession()
  for _,e in ipairs(entrants) do e.retired=nil;e.stopped=nil;e.stalled=0 end
  race=require('/lua/ge/extensions/gameplay/race/race')()
  race.useHotlappingApp=false; race.useLapTimesApp=false; race.useWaypointAudio=false
  race.alwaysAdvanceTime=true; race:setPath(path)
  race.lapCount=pendingPhase=='race' and options.laps or 9999
  local ids={}; for _,e in ipairs(entrants) do if object(e.id) then ids[#ids+1]=e.id end end
  race:setVehicleIds(ids); race:startRace()
  for id in pairs(owned) do if object(id) then race:startAiVehicle(id,options.aggression) end end
  releasePlayer(); phase,clock=pendingPhase,0; message='GREEN FLAG'
end
local function snapshot()
  local rows={}
  for _,e in ipairs(entrants) do
    local s=race and race.states[e.id]
    rows[#rows+1]={id=e.id,name=e.name,player=e.player==true,retired=e.retired,
      position=s and s.placement or e.seed,lap=s and s.currentLap or 0,
      best_s=bestLap(s) or qualifying[e.id],
      qualifying_s=qualifying[e.id],finished=s and s.complete or false,
      finish_s=s and s.complete and s.endTime or nil,
      gap_s=s and s.timeDifferenceToFirst and s.timeDifferenceToFirst/1000 or nil}
  end
  if pendingPhase=='qualifying' then
    table.sort(rows,function(a,b) local x,y=a.best_s or math.huge,b.best_s or math.huge; if x==y then return a.id<b.id end; return x<y end)
  else
    table.sort(rows,function(a,b)
      if a.retired~=nil and b.retired==nil then return false end
      if b.retired~=nil and a.retired==nil then return true end
      if a.position==b.position then return a.id<b.id end
      return a.position<b.position
    end)
  end
  return {schema_version=1,phase=phase,session=pendingPhase,message=message,clock_s=clock,
    remaining_s=math.max(0,options.minutes*60-clock),countdown_s=math.ceil(countdown),
    options=deepcopy(options),standings=rows,track='Hirochi Raceway Short'}
end
local function onUpdate(dtReal,dtSim)
  uiTime=uiTime+dtReal
  if phase~='off' and not master() then cancel() end
  if phase~='off' and playerId~=be:getPlayerVehicleID(0) then fail('Player vehicle changed; weekend cancelled.') end
  if phase=='preparing' then
    clock=clock+dtSim
    if clock>40 then fail('Opponent spawn timed out.')
    elseif spawning<options.opponents then
      local last=entrants[#entrants]; local v=object(last.id)
      if v and v:getWheelCount()>0 then
        local model=be:getPlayerVehicle(0):getJBeamFilename()
        local ai=core_vehicles.spawnNewVehicle(model,{config=model=='etkc' and 'vehicles/etkc/kc6_360_M.pc' or nil,
          pos=startPos+vec3(0,0,3+spawning*4),autoEnterVehicle=false})
        if not ai then fail('Unable to spawn opponent.');return end
        spawning=spawning+1; local id=ai:getID(); owned[id]=true
        entrants[#entrants+1]={id=id,name='AI '..spawning,seed=spawning+1}
      end
    elseif object(entrants[#entrants].id) and object(entrants[#entrants].id):getWheelCount()>0 then
      grid(entrants); releasePlayer(); stopAI(); phase,clock='ready',0;message='Ready: practice, qualify, or race.'
    end
  elseif phase=='countdown' then
    countdown=countdown-dtSim
    if countdown<=0 then startSession() else message='START IN '..math.ceil(countdown) end
  elseif phase=='practice' or phase=='qualifying' or phase=='race' then
    for _,e in ipairs(entrants) do if not object(e.id) then retire(e.id,'Removed') end end
    clock=clock+dtSim; race:onUpdate(dtSim)
    for _,e in ipairs(entrants) do
      local s=race.states[e.id]
      if not object(e.id) then retire(e.id,'Removed') end
      if phase=='qualifying' and s then qualifying[e.id]=bestLap(s) end
      if s and s.complete and owned[e.id] and not e.stopped then
        e.stopped=true;local v=object(e.id);if v then v:queueLuaCommand('ai.setMode("stop")') end
      end
      if phase=='race' and owned[e.id] and not e.retired and s and not s.complete and clock>15 then
        local v=object(e.id)
        e.stalled=v and v:getVelocity():length()<0.5 and (e.stalled or 0)+dtSim or 0
        if e.stalled>=45 then retire(e.id,'Stopped / damaged') end
      end
    end
    if phase~='race' and clock>=options.minutes*60 then finish()
    elseif phase=='race' then
      local done=true
      for _,e in ipairs(entrants) do local s=race.states[e.id]; if not e.retired and s and not s.complete then done=false end end
      if done then finish() end
    end
  end
  if uiTime>=0.2 then uiTime=0;guihooks.trigger('ACNGWeekend',snapshot()) end
end
local function onVehicleResetted(id)
  if positioning then return end
  if phase=='race' or phase=='qualifying' then retire(id,'Reset') end
end
M.prepare=prepare; M.begin=begin; M.cancel=cancel; M.endSession=function() if race and race.started then finish();return true end return false end
M.setOption=setOption;M.getSnapshot=snapshot;M.qualificationOrder=qualificationOrder
M.bestLap=bestLap
M.onUpdate=onUpdate;M.onVehicleResetted=onVehicleResetted
M.onClientEndMission=cancel; M.onExtensionUnloaded=cancel
return M
