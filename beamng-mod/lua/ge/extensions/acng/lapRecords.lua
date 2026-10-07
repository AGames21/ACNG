-- Original ACNG local lap archive. No vehicle physics or input writes.
local M = {}
local PATH = '/settings/acng/lap-records.json'
local db, readOnly, bindings = nil, false, {}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function sequence(t,limit)
  if type(t)~='table' or #t>limit then return false end
  local count=0
  for k in pairs(t) do
    if type(k)~='number' or k%1~=0 or k<1 or k>#t then return false end
    count=count+1
  end
  return count==#t
end
local function valid(r)
  if type(r)~='table' or type(r.line)~='table' then return false end
  local l=r.line
  for _,k in ipairs({'x','y','nx','ny'}) do if not finite(l[k]) then return false end end
  if math.abs(l.nx*l.nx+l.ny*l.ny-1)>0.001 then return false end
  if not sequence(r.best_sectors,3) then return false end
  if r.best==nil then return r.best_trace==nil and r.ref_length_m==nil and #r.best_sectors==0 end
  local b,t=r.best,r.best_trace
  if type(b)~='table' or not finite(b.time_s) or b.time_s<5 or b.time_s>86400
    or not finite(b.distance_m) or b.distance_m<50 or b.distance_m>20000
    or not finite(r.ref_length_m) or r.ref_length_m<50 or r.ref_length_m>20000 then return false end
  if type(t)~='table' or not sequence(t.d,10000) or not sequence(t.t,10000)
    or #t.d<2 or #t.d>10000 or #t.d~=#t.t or t.d[1]~=0 or t.t[1]~=0 then return false end
  for i=1,#t.d do
    if not finite(t.d[i]) or not finite(t.t[i]) then return false end
    if i>1 and (t.d[i]<=t.d[i-1] or t.t[i]<t.t[i-1]) then return false end
  end
  if math.abs(t.d[#t.d]-b.distance_m)>0.001 or math.abs(t.t[#t.t]-b.time_s)>0.001 then return false end
  if type(r.best_sectors)~='table' then return false end
  if #r.best_sectors~=0 and #r.best_sectors~=3 then return false end
  for _,s in ipairs(r.best_sectors) do if not finite(s) or s<=0 or s>b.time_s then return false end end
  return true
end
-- Stable ordering: native config table iteration order must not split records.
local function canonical(v,depth)
  depth=depth or 0
  assert(depth<12,'Config nesting too deep')
  if type(v)~='table' then
    assert(v==nil or type(v)=='string' or type(v)=='boolean' or finite(v),'Unsupported config value')
    return jsonEncode(v)
  end
  local keys,out={},{}
  for k in pairs(v) do assert(type(k)=='string','Config keys must be strings');keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do out[#out+1]=jsonEncode(k)..':'..canonical(v[k],depth+1) end
  return '{'..table.concat(out,',')..'}'
end
local function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)=='number' then return math.abs(a-b)<=1e-10*math.max(1,math.abs(a),math.abs(b)) end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function validDB(d)
  if type(d)~='table' or d.schema_version~=1 or type(d.records)~='table' or #d.records>32 then return false end
  local count=0
  for k in pairs(d.records) do
    if type(k)~='number' or k%1~=0 or k<1 or k>#d.records then return false end
    count=count+1
  end
  if count~=#d.records then return false end
  local seen={}
  for _,r in ipairs(d.records) do
    if type(r)~='table' or type(r.key)~='string' or #r.key>65536 or seen[r.key] or not valid(r.value) then return false end
    seen[r.key]=true
  end
  return true
end
local function load()
  if db then return end
  db={schema_version=1,records={}}
  if FS:fileExists(PATH) then
    local ok,d=pcall(jsonReadFile,PATH)
    if ok and validDB(d) then db=d else
      readOnly=true -- preserve malformed file; never silently overwrite history
      local backupOK,backup=pcall(jsonReadFile,PATH..'.previous')
      if backupOK and validDB(backup) then db=backup end
    end
  end
end
local function context(id)
  local veh=be:getPlayerVehicle(0)
  if not veh or veh:getID()~=id then return nil end
  local map=getMissionFilename()
  local data=core_vehicle_manager.getVehicleData(id)
  if type(map)~='string' or map=='' or not data or type(data.config)~='table' then return nil end
  local c=data.config
  local ok,key=pcall(canonical,{map=map,model=veh:getJBeamFilename(),parts=c.parts or {},vars=c.vars or {},mainPartName=c.mainPartName})
  if not ok or #key>65536 then return nil end
  return key,veh
end
local function reply(veh,token,record,status)
  veh:queueLuaCommand(string.format("if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.receiveArchive(%q,%q,%q) end",token,jsonEncode(record or {}),status))
end
local function request(id,token)
  if type(token)~='string' or #token>128 then return false end
  load()
  local key,veh=context(id)
  if not key then
    local active=be:getPlayerVehicle(0)
    if active and active:getID()==id then reply(active,token,nil,'unavailable') end
    return false
  end
  bindings[id]={key=key,token=token}
  local value
  for _,r in ipairs(db.records) do if r.key==key then value=r.value;break end end
  reply(veh,token,value,readOnly and 'read_only' or value and 'loaded' or 'ready')
  return true
end
local function save(id,token,text)
  load()
  local key,veh=context(id)
  local bind=bindings[id]
  if not key or not bind or bind.key~=key or bind.token~=token then return false end
  if readOnly then reply(veh,token,nil,'read_only');return false end
  if type(text)~='string' or #text>1000000 then return false end
  local ok,value=pcall(jsonDecode,text)
  if not ok or not valid(value) then reply(veh,token,nil,'not_saved');return false end
  local nextDB={schema_version=1,records={{key=key,value=value}}}
  for _,r in ipairs(db.records) do if r.key~=key and #nextDB.records<32 then nextDB.records[#nextDB.records+1]=r end end
  -- Keep the last successful database as recovery evidence before replacing it.
  local backupOK,backupResult=pcall(jsonWriteFile,PATH..'.previous',db,true)
  local writeOK,writeResult=false,false
  if backupOK and backupResult~=false then writeOK,writeResult=pcall(jsonWriteFile,PATH,nextDB,true) end
  local checkOK,check=pcall(jsonReadFile,PATH)
  if not writeOK or writeResult==false or not checkOK or not validDB(check) or not same(check,nextDB) then
    readOnly=true;reply(veh,token,nil,'not_saved');return false
  end
  db=nextDB;reply(veh,token,nil,'saved');return true
end
M.request=request
M.save=save
M.validate=valid
M.canonical=canonical
M.onClientEndMission=function() bindings={} end
return M
