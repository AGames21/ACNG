"""Read-only AC prefix adapter; stationary and short-motion smoke on AC1.16.4.

Uses OpenFileMappingW, never CreateFileMapping/mmap(tagname), so an absent game
cannot produce an empty fabricated mapping. No process attach or memory writes.
"""
import argparse
import ctypes as C
import json
import math
import os
import struct
import time
from pathlib import Path

I32, F32, U16 = C.c_int32, C.c_float, C.c_uint16


class PhysicsPrefix(C.LittleEndianStructure):
    _pack_ = 4
    _fields_ = [("packetId",I32),("gas",F32),("brake",F32),("fuel",F32),
                ("gear",I32),("rpms",I32),("steerAngle",F32),("speedKmh",F32),
                ("velocity",F32*3),("accG",F32*3)] + [
        (name,F32*4) for name in ("wheelSlip","wheelLoad","wheelsPressure",
        "wheelAngularSpeed","tyreWear","tyreDirtyLevel","tyreCoreTemperature",
        "camberRAD","suspensionTravel")]


class StaticPrefix(C.LittleEndianStructure):
    _pack_ = 4
    _fields_ = [("smVersion",U16*15),("acVersion",U16*15),
                ("numberOfSessions",I32),("numCars",I32),
                ("carModel",U16*33),("track",U16*33)]


class GraphicsPrefix(C.LittleEndianStructure):
    _pack_ = 4
    _fields_ = [("packetId",I32),("status",I32),("session",I32)] + [
        (name,U16*15) for name in ("currentTime","lastTime","bestTime","split")] + [
        ("completedLaps",I32),("position",I32),("iCurrentTime",I32)]


def wide(value):
    return bytes(value).decode("utf-16-le").split("\0",1)[0]


class ExistingMapping:
    def __init__(self,name,size):
        if os.name != "nt":
            raise OSError("Assetto Corsa mapping reader requires Windows")
        from ctypes import wintypes as W
        self.api=C.WinDLL("kernel32",use_last_error=True)
        self.api.OpenFileMappingW.argtypes=[W.DWORD,W.BOOL,W.LPCWSTR]
        self.api.OpenFileMappingW.restype=W.HANDLE
        self.api.MapViewOfFile.argtypes=[W.HANDLE,W.DWORD,W.DWORD,W.DWORD,C.c_size_t]
        self.api.MapViewOfFile.restype=C.c_void_p
        self.api.UnmapViewOfFile.argtypes=[C.c_void_p]
        self.api.CloseHandle.argtypes=[W.HANDLE]
        self.handle=self.api.OpenFileMappingW(0x0004,False,name)  # FILE_MAP_READ
        if not self.handle:
            raise FileNotFoundError(C.get_last_error(),"AC mapping absent: "+name)
        self.address=self.api.MapViewOfFile(self.handle,0x0004,0,0,size)
        if not self.address:
            self.api.CloseHandle(self.handle)
            raise OSError(C.get_last_error(),"Unable to map existing AC page")
        self.size=size

    def read(self):
        return C.string_at(self.address,self.size)

    def coherent_read(self,retries=3):
        # Packet-ID equality detects some torn reads; AC supplies no reader lock.
        for _ in range(retries):
            before=C.string_at(self.address,4)
            data=self.read()
            after=C.string_at(self.address,4)
            if before==data[:4]==after:
                return data
        return None

    def close(self):
        if self.address:
            self.api.UnmapViewOfFile(self.address)
            self.address=None
        if self.handle:
            self.api.CloseHandle(self.handle)
            self.handle=None

    def __enter__(self): return self
    def __exit__(self,*args): self.close()


def decode_physics(data):
    if len(data)<C.sizeof(PhysicsPrefix):
        raise ValueError("Truncated physics prefix")
    p=PhysicsPrefix.from_buffer_copy(data)
    if not all(math.isfinite(x) for x in [p.gas,p.brake,p.speedKmh,*p.velocity,*p.accG]):
        raise ValueError("Invalid physics values")
    if not -0.01 <= p.gas <= 1.01 or not -0.01 <= p.brake <= 1.01 or not 0 <= p.speedKmh <= 1500:
        raise ValueError("Physics sanity bounds failed; verify ABI")
    wheels=[]
    for i,name in enumerate(("FL","FR","RL","RR")):
        wheels.append({"name":name,"load_n":p.wheelLoad[i],
            "angular_speed_native":p.wheelAngularSpeed[i],"pressure_native":p.wheelsPressure[i],
            "wear_native":p.tyreWear[i],"core_temperature_native":p.tyreCoreTemperature[i],
            "wheel_slip_native":p.wheelSlip[i],"camber_rad":p.camberRAD[i],
            "suspension_travel_native":p.suspensionTravel[i]})
    return {"schema_version":1,"source":"assetto_corsa","packet_id":p.packetId,
        "speed_m_s":p.speedKmh/3.6,"throttle":p.gas,"brake":p.brake,"rpm":p.rpms,
        "gear":p.gear-1,"steer_angle_native":p.steerAngle,
        "velocity_world_native":list(p.velocity),"acceleration_local_g_native":list(p.accG),
        "wheels":wheels}


def capture(output,duration,rate,expected_version):
    with ExistingMapping('Local\\acpmf_static',C.sizeof(StaticPrefix)) as static:
        s=StaticPrefix.from_buffer_copy(static.read())
        identity={"shared_memory_version":wide(s.smVersion),"ac_version":wide(s.acVersion),
                  "car_model":wide(s.carModel),"track":wide(s.track)}
    if identity['ac_version'] != expected_version:
        raise ValueError("Unexpected game version; re-verify SDK ABI. Observed: "+identity['ac_version'])
    output=Path(output)
    output.parent.mkdir(parents=True,exist_ok=True)
    counts={"accepted":0,"duplicate_poll":0,"incoherent_poll":0,"inactive_poll":0}
    with ExistingMapping('Local\\acpmf_physics',C.sizeof(PhysicsPrefix)) as physics, \
         ExistingMapping('Local\\acpmf_graphics',C.sizeof(GraphicsPrefix)) as graphics, \
         output.open('x',encoding='utf-8') as stream:
        start=time.monotonic()
        last=None
        while time.monotonic()-start<duration:
            data=physics.coherent_read()
            gd=graphics.coherent_read()
            if data is None or gd is None:
                counts['incoherent_poll']+=1
            else:
                g=GraphicsPrefix.from_buffer_copy(gd)
                if g.status!=2:  # AC_LIVE; no samples from pause/menu/replay
                    counts['inactive_poll']+=1
                else:
                    row=decode_physics(data)
                    if row['packet_id']==last:
                        counts['duplicate_poll']+=1
                    else:
                        last=row['packet_id']
                        row.update(identity)
                        row.update(host_monotonic_s=time.monotonic(),
                                   observation_elapsed_s=time.monotonic()-start,
                                   graphics_packet_id=g.packetId,completed_laps=g.completedLaps,
                                   current_lap_time_s=g.iCurrentTime/1000)
                        stream.write(json.dumps(row,allow_nan=False)+'\n')
                        counts['accepted']+=1
            time.sleep(1/rate)
    summary={**counts,**identity,"requested_poll_hz":rate,
        "limitations":["prefix reads do not validate every channel's physical semantics",
          "packet equality is not a writer lock","graphics/physics pages not atomic together",
          "host observation time is not physics simulation time"]}
    output.with_suffix('.summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    return summary


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('output',type=Path)
    p.add_argument('--expected-version',required=True,help='Exact AC version verified from installed SDK/session')
    p.add_argument('--duration',type=float,default=30)
    p.add_argument('--rate',type=int,default=50)
    a=p.parse_args()
    if a.duration<=0 or not 1<=a.rate<=200:p.error('Positive duration and rate 1..200 required')
    print(json.dumps(capture(a.output,a.duration,a.rate,a.expected_version),indent=2))
