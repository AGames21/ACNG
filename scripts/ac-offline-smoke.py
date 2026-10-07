"""Temporary offline stock AC session with exact config backups/restoration.

Uses the legitimate installed executable/Steam. No hooks, game-install edits or
inputs. Closes only the process this script starts. Ctrl+C runs restoration.
Backups and a manifest permit recovery after host interruption.
"""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from telemetry.ac_shared_memory import ExistingMapping,StaticPrefix,GraphicsPrefix,wide,capture

RACE='''[HEADER]
VERSION=2
[RACE]
TRACK=magione
CONFIG_TRACK=
MODEL=bmw_1m
MODEL_CONFIG=
CARS=1
AI_LEVEL=90
FIXED_SETUP=0
PENALTIES=0
[SESSION_0]
NAME=ACNG offline telemetry
TYPE=1
DURATION_MINUTES=10
SPAWN_SET=PIT
[CAR_0]
MODEL=-
MODEL_CONFIG=
SKIN=white
DRIVER_NAME=ACNG
NATIONALITY=USA
[REMOTE]
ACTIVE=0
[BENCHMARK]
ACTIVE=0
[REPLAY]
ACTIVE=0
FILENAME=
[GHOST_CAR]
RECORDING=0
PLAYING=0
LOAD=0
[LIGHTING]
SUN_ANGLE=30
TIME_MULT=1
[DYNAMIC_TRACK]
SESSION_START=100
SESSION_TRANSFER=100
RANDOMNESS=0
LAP_GAIN=1
[TEMPERATURE]
AMBIENT=20
ROAD=26
[WEATHER]
NAME=4_mid_clear
'''
VIDEO='''[VIDEO]
FULLSCREEN=0
WIDTH=1280
HEIGHT=720
REFRESH=60
FPS_CAP_MS=16.666667
VSYNC=0
AASAMPLES=2
ANISOTROPIC=4
SHADOW_MAP_SIZE=1024
DISABLE_LEGACY_HDR=1
[CAMERA]
MODE=DEFAULT
[POST_PROCESS]
ENABLED=0
[ASSETTOCORSA]
WORLD_DETAIL=3
[MIRROR]
SIZE=256
HQ=0
'''
ASSISTS='''[ASSISTS]
IDEAL_LINE=0
AUTO_BLIP=1
STABILITY_CONTROL=0
AUTO_BRAKE=0
AUTO_SHIFTER=1
ABS=2
TRACTION_CONTROL=2
AUTO_CLUTCH=1
VISUALDAMAGE=1
DAMAGE=100
FUEL_RATE=1
TYRE_WEAR=1
TYRE_BLANKETS=0
SLIPSTREAM=1
'''
PYTHON='''[CHAT]
ACTIVE=0
[ACNOTIFY]
ACTIVE=0
[GMETER]
ACTIVE=0
'''
KEYBOARD='''[HEADER]
INPUT_METHOD=KEYBOARD
[KEYBOARD]
MINIMUM_STEERING=0
STEERING_SPEED=1.75
STEERING_OPPOSITE_DIRECTION_SPEED=2.5
STEER_GAIN=0.18
STEER_RESET_SPEED=1.8
GAS=0x26
BRAKE=0x28
RIGHT=0x27
LEFT=0x25
MOUSE_STEER=0
MOUSE_ACCELERATOR_BRAKE=0
[STEER]
FF_GAIN=0
FILTER_FF=0
MIN_FF=0
'''


def close_owned(process):
    if process.poll() is not None:return
    from ctypes import wintypes as W
    u=C.WinDLL('user32')
    callback_type=C.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
    u.EnumWindows.argtypes=[callback_type,W.LPARAM]
    u.GetWindowThreadProcessId.argtypes=[W.HWND,C.POINTER(W.DWORD)]
    u.PostMessageW.argtypes=[W.HWND,W.UINT,W.WPARAM,W.LPARAM]
    def visit(window,_):
        pid=W.DWORD()
        u.GetWindowThreadProcessId(window,C.byref(pid))
        if pid.value==process.pid:u.PostMessageW(window,0x0010,0,0)
        return True
    u.EnumWindows(callback_type(visit),0)
    try:process.wait(timeout=8)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=8)


def run(game,user,evidence,wait_seconds=60,mode='idle',capture_duration=15):
    game,user,evidence=map(lambda p:Path(p).resolve(),(game,user,evidence))
    if os.name!='nt':raise OSError('Windows required')
    if subprocess.check_output(['powershell','-NoProfile','-Command',
        "@(Get-Process acs,assettocorsa -ErrorAction SilentlyContinue).Count"],text=True).strip()!='0':
        raise RuntimeError('An AC process already exists; refusing config changes')
    for p in [game/'acs.exe',game/'content/cars/bmw_1m',game/'content/tracks/magione',user/'cfg']:
        if not p.exists():raise FileNotFoundError(p)
    if evidence.exists():raise FileExistsError('Choose a fresh evidence directory')
    evidence.mkdir(parents=True)
    cfg=user/'cfg'
    overlays={'race.ini':RACE,'video.ini':VIDEO,'assists.ini':ASSISTS,'python.ini':PYTHON}
    if mode=='benchmark':
        # Stock launcher uses this exact configuration switch. Native benchmark
        # may select its own stock car/track; record the observed identity.
        overlays['race.ini']=RACE.replace('[BENCHMARK]\nACTIVE=0','[BENCHMARK]\nACTIVE=1')
    elif mode=='keyboard':
        overlays['controls.ini']=KEYBOARD
    originals={}
    # AC itself rewrites additional cfg files (observed acos.ini/user_ff.ini).
    # Snapshot all existing cfg files, not just our explicit overlays.
    names={str(p.relative_to(cfg)) for p in cfg.rglob('*') if p.is_file()} | set(overlays)
    for name in sorted(names):
        target=cfg/name
        if target.is_symlink():raise RuntimeError('Refusing linked configuration')
        originals[name]=target.read_bytes() if target.exists() else None
        if originals[name] is not None:
            backup=evidence/'before'/name
            backup.parent.mkdir(parents=True,exist_ok=True)
            backup.write_bytes(originals[name])
    manifest={name:{'existed':data is not None,'sha256':hashlib.sha256(data).hexdigest() if data is not None else None}
              for name,data in originals.items()}
    (evidence/'restore-manifest.json').write_text(json.dumps(manifest,indent=2))
    process=None
    result={'offline':True,'requested_car':'bmw_1m','requested_track':'magione',
            'mode':mode,'launcher_inputs_sent':False}
    try:
        for name,body in overlays.items():(cfg/name).write_text(body,encoding='utf-8')
        env=os.environ.copy()
        env['SteamAppId']='244210'
        env['SteamGameId']='244210'
        process=subprocess.Popen([str(game/'acs.exe')],cwd=game,env=env)
        result['pid']=process.pid
        print(json.dumps({'launched':process.pid,'offline':True,'restore_manifest':str(evidence/'restore-manifest.json')}),flush=True)
        deadline=time.monotonic()+wait_seconds
        while time.monotonic()<deadline and process.poll() is None:
            try:
                with ExistingMapping('Local\\acpmf_static',C.sizeof(StaticPrefix)) as m:
                    s=StaticPrefix.from_buffer_copy(m.read())
                with ExistingMapping('Local\\acpmf_graphics',C.sizeof(GraphicsPrefix)) as m:
                    g=GraphicsPrefix.from_buffer_copy(m.read())
                identity={'ac_version':wide(s.acVersion),'sm_version':wide(s.smVersion),
                          'car_model':wide(s.carModel),'track':wide(s.track),'status':g.status}
                if result.get('identity')!=identity:
                    print(json.dumps(identity),flush=True)
                    result['identity']=identity
                if g.status==2 and identity['ac_version']:
                    if mode!='benchmark' and (identity['car_model']!='bmw_1m' or identity['track']!='magione'):
                        raise RuntimeError('Unexpected running vehicle/track')
                    for item,folder in [('car_model','cars'),('track','tracks')]:
                        name=identity[item]
                        if not name or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in name):
                            raise RuntimeError('Invalid native benchmark identity')
                        if not (game/'content'/folder/name).is_dir():
                            raise RuntimeError('Benchmark selected unavailable content')
                    result['capture']=capture(evidence/('ac-'+mode+'.jsonl'),capture_duration,50,'1.16.4')
                    break
            except FileNotFoundError:pass
            time.sleep(1)
        result['exit_before_cleanup']=process.poll()
        result['live_capture']=bool(result.get('capture',{}).get('accepted'))
        print(json.dumps(result),flush=True)
    finally:
        try:
            if process is not None:close_owned(process)
        finally:
            result['changed_config_files']=[name for name,data in originals.items()
                if ((cfg/name).read_bytes() if (cfg/name).exists() else None)!=data]
            new_files=[str(p.relative_to(cfg)) for p in cfg.rglob('*') if p.is_file() and str(p.relative_to(cfg)) not in originals]
            result['new_config_files_preserved']=new_files
            for name,data in originals.items():
                target=cfg/name
                if data is None:target.unlink(missing_ok=True)
                else:target.write_bytes(data)
            result['config_restored']=not new_files and all((cfg/name).read_bytes()==data if data is not None else not (cfg/name).exists()
                                                          for name,data in originals.items())
            (evidence/'session-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
            print(json.dumps({'config_restored':result['config_restored']}),flush=True)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--game',type=Path,required=True)
    p.add_argument('--user',type=Path,required=True)
    p.add_argument('--evidence',type=Path,required=True,help='Private directory outside Git (original config backups)')
    p.add_argument('--wait-seconds',type=int,default=60)
    p.add_argument('--mode',choices=['idle','benchmark','keyboard'],default='idle')
    p.add_argument('--capture-duration',type=float,default=15)
    a=p.parse_args()
    if a.capture_duration<=0:p.error('Capture duration must be positive')
    run(a.game,a.user,a.evidence,a.wait_seconds,a.mode,a.capture_duration)
