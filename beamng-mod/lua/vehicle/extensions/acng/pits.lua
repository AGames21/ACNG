-- Optional local service box. No respawn, repair, pressure or structural writes.
local M = {}
local active, box, job, message, sinceSend = false, nil, nil, 'Pit service OFF', 0
local RADIUS, STOP_SPEED = 4, 0.2
local function number(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function speed()
  local vel=obj:getVelocity()
  if not vel or not number(vel.x) or not number(vel.y) or not number(vel.z) then return nil end
  return math.sqrt(vel.x*vel.x+vel.y*vel.y+vel.z*vel.z)
end
local function atBox()
  if not box then return false end
  local pos=obj:getPosition()
  if not pos or not number(pos.x) or not number(pos.y) or not number(pos.z) then return false end
  local dx,dy,dz=pos.x-box.x,pos.y-box.y,pos.z-box.z
  return dx*dx+dy*dy+dz*dz<=RADIUS*RADIUS
end
local function stopped() local s=speed(); return s and s<=STOP_SPEED end
local function fuelTanks()
  local out={}
  if not energyStorage or type(energyStorage.getStorages)~='function' then return nil,'Fuel storage unavailable' end
  for _,s in pairs(energyStorage.getStorages()) do
    if s.type=='fuelTank' then
      if not number(s.capacity) or s.capacity<=0 or type(s.setRemainingVolume)~='function' then
        return nil,'Unsupported fuel tank'
      end
      if not number(s.currentLeakRate) or s.currentLeakRate~=0 then return nil,'Fuel tank is leaking or unknown' end
      out[#out+1]=s
    end
  end
  if #out==0 then return nil,'No supported liquid fuel tank' end
  return out
end
local function treadCheck()
  if not extensions or not extensions.isExtensionLoaded('acng_tires') then return false,'Enable ACNG tire wear first' end
  local tires=extensions.acng_tires
  if not tires or type(tires.canServiceTread)~='function' then return false,'Enable ACNG tire wear first' end
  return tires.canServiceTread()
end
local function cancel(reason) job=nil; message=reason or 'Service cancelled' end
local function snapshot()
  return {enabled=active,box_marked=box~=nil,in_box=atBox(),stopped=stopped()==true,
    servicing=job~=nil,remaining_s=job and math.max(0,job.duration-job.elapsed) or 0,
    message=message,radius_m=RADIUS}
end
local function send() if guihooks then guihooks.trigger('ACNGPit',snapshot()) end end
local function markHere()
  if not active or job then return false end
  if not stopped() then message='Stop before marking a pit box';send();return false end
  local p=obj:getPosition()
  if not p or not number(p.x) or not number(p.y) or not number(p.z) then return false end
  box={x=p.x,y=p.y,z=p.z};message='Pit box marked here (4 m radius)';send();return true
end
local function request(refuel,tread)
  if not active or job then return false end
  if not atBox() or not stopped() then message='Park inside your marked pit box';send();return false end
  refuel,tread=refuel==true,tread==true
  if not refuel and not tread then message='Choose a service';send();return false end
  if refuel then local tanks,err=fuelTanks();if not tanks then message=err;send();return false end end
  if tread then local ok,err=treadCheck();if not ok then message=err;send();return false end end
  job={refuel=refuel,tread=tread,elapsed=0,duration=refuel and 20 or 8}
  message='Service in progress; stay stopped';send();return true
end
local function updateGFX(dt)
  if not active or not number(dt) or dt<0 then return end
  if job then
    if not atBox() or not stopped() then cancel('Cancelled: vehicle moved')
    else
      job.elapsed=job.elapsed+dt
      if job.elapsed>=job.duration then
        local current=job
        local tanks,err
        if current.refuel then tanks,err=fuelTanks() end
        local ok,why=true,nil
        if current.tread then ok,why=treadCheck() end
        if (current.refuel and not tanks) or not ok then cancel(err or why)
        else
          local success,failure=pcall(function()
            if current.tread then assert(extensions.acng_tires.serviceTread()) end
            if current.refuel then for _,tank in ipairs(tanks) do tank:setRemainingVolume(tank.capacity) end end
          end)
          cancel(success and 'Service complete; damage and tire heat preserved' or 'Service failed; inspect Lua log')
          if not success and log then log('E','ACNGPit',tostring(failure)) end
        end
      end
    end
  end
  sinceSend=sinceSend+dt
  if sinceSend>=0.2 then sinceSend=0;send() end
end
M.configure=function(value) active=value==true;if not active then cancel('Pit service OFF') end;send() end
M.markHere=markHere
M.request=request
M.cancel=function() cancel();send() end
M.getSnapshot=snapshot
M.updateGFX=updateGFX
M.onReset=function() box=nil;cancel('Vehicle reset: mark a new pit box');send() end
M.onExtensionUnloaded=function() active=false;box=nil;cancel('Pit service OFF');send() end
return M
