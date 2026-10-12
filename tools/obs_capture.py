"""Lab-only portable OBS recorder. Game capture + process audio; no microphone.

Copy an installed OBS bin/data/obs-plugins tree outside the repo and add
portable_mode.txt. Install obsws-python in the developer venv. Existing user OBS
settings are never read or changed. Uses obs-websocket's local RPC protocol.
"""
import ctypes
import ctypes.wintypes as wt
import json
import shutil
import datetime
import secrets
import socket
import subprocess
import time
from pathlib import Path


def window_key(pid):
    u = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def visit(hwnd, _):
        owner = wt.DWORD()
        u.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and u.IsWindowVisible(hwnd):
            title, cls = ctypes.create_unicode_buffer(1024), ctypes.create_unicode_buffer(256)
            u.GetWindowTextW(hwnd, title, len(title))
            u.GetClassNameW(hwnd, cls, len(cls))
            r = wt.RECT(); u.GetClientRect(hwnd, ctypes.byref(r))
            found.append((r.right*r.bottom, title.value, cls.value))
        return True
    u.EnumWindows(visit, 0)
    if not found:
        raise RuntimeError('No visible lab game window')
    _, title, cls = max(found)
    return f'{title}:{cls}:BeamNG.drive.x64.exe'


def dismiss_setup(pid):
    # A first-launch wizard can block recording despite a working websocket.
    # Close only this owned portable process's wizard, never another OBS window.
    u=ctypes.windll.user32
    @ctypes.WINFUNCTYPE(wt.BOOL,wt.HWND,wt.LPARAM)
    def visit(hwnd,_):
        owner=wt.DWORD();u.GetWindowThreadProcessId(hwnd,ctypes.byref(owner))
        if owner.value==pid:
            title=ctypes.create_unicode_buffer(256);u.GetWindowTextW(hwnd,title,256)
            if title.value=='Auto-Configuration Wizard':
                u.PostMessageW(hwnd,0x100,27,1)
                u.PostMessageW(hwnd,0x101,27,1)
        return True
    u.EnumWindows(visit,0)
    time.sleep(1)


def game_inputs(window):
    # OBS native application capture uses executable matching (priority 2).
    return [('ACNG Game', 'game_capture', {'capture_mode':'window', 'window':window,
            'priority':2, 'capture_cursor':False, 'capture_overlays':False}),
            ('ACNG Game Audio', 'wasapi_process_output_capture', {'window':window, 'priority':2})]


class ObsRecorder:
    def __init__(self, root, out_dir, pid, width, height, fps):
        self.root, self.out_dir = Path(root).resolve(), Path(out_dir).resolve()
        marker=self.root/'.acng-film-obs-owned'
        if not marker.exists() or marker.read_text().strip()!='acng-video-tool-only':
            raise RuntimeError('Only an ACNG-owned portable OBS copy may be configured')
        import obsws_python
        import logging
        logging.getLogger("obsws_python").setLevel(logging.CRITICAL)
        if not (self.root/'portable_mode.txt').exists():
            raise RuntimeError('Only a dedicated portable OBS copy may be used')
        exe = self.root/'bin/64bit/obs64.exe'
        config = self.root/'config/obs-studio'
        if config.exists():
            shutil.move(str(config), str(config.with_name('obs-studio-backup-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))))
        config.mkdir(parents=True, exist_ok=True)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
        password=secrets.token_urlsafe(32)
        websocket=config/'plugin_config/obs-websocket/config.json'
        websocket.parent.mkdir(parents=True,exist_ok=True)
        websocket.write_text(json.dumps({'server_enabled':True, 'server_port':port,
            'auth_required':True, 'server_password':password, 'alerts_enabled':False}),encoding='utf-8')
        (config/'global.ini').write_text('[General]\nFirstRun=false\nEnableAutoUpdates=false\n'
            '[Basic]\nProfile=ACNG\nProfileDir=ACNG\nSceneCollection=ACNG\nSceneCollectionFile=ACNG\n',encoding='utf-8')
        profile=config/'basic/profiles/ACNG';profile.mkdir(parents=True,exist_ok=True)
        (profile/'basic.ini').write_text(f'[General]\nName=ACNG\n'
            f'[Video]\nBaseCX={width}\nBaseCY={height}\nOutputCX={width}\nOutputCY={height}\n'
            f'FPSType=0\nFPSCommon={fps}\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n'
            f'[Output]\nMode=Simple\n[SimpleOutput]\nFilePath={self.out_dir.as_posix()}\nRecFormat2=mkv\nRecQuality=HQ\nRecEncoder=nvenc\nRecAudioEncoder=aac\nABitrate=192\n[AdvOut]\nRecType=Standard\nRecFormat2=mkv\n'
            f'RecFilePath={self.out_dir.as_posix()}\nRecEncoder=obs_nvenc_h264_tex\nRecTracks=1\n'
            'RecAudioEncoder=ffmpeg_aac\nTrack1Name=BeamNG game audio\nTrack1Bitrate=192\n',encoding='utf-8')
        scenes=config/'basic/scenes';scenes.mkdir(parents=True,exist_ok=True)
        (scenes/'ACNG.json').write_text(json.dumps({'name':'ACNG','current_scene':'ACNG Film',
            'current_program_scene':'ACNG Film','scene_order':[{'name':'ACNG Film'}],
            'sources':[{'name':'ACNG Film','id':'scene','settings':{'items':[]}}]}),encoding='utf-8')
        si=subprocess.STARTUPINFO();si.dwFlags|=subprocess.STARTF_USESHOWWINDOW;si.wShowWindow=0
        self.proc=subprocess.Popen([str(exe),'--portable','--disable-updater','--disable-shutdown-check','--minimize-to-tray','--profile','ACNG','--collection','ACNG'],
                                   cwd=exe.parent,startupinfo=si)
        self.client=None
        for _ in range(40):
            try:
                self.client=obsws_python.ReqClient(host='127.0.0.1',port=port,password=password,timeout=5)
                break
            except Exception:
                if self.proc.poll() is not None: raise RuntimeError('Portable OBS exited at startup')
                time.sleep(1)
        if self.client is None:
            self.close();raise RuntimeError('Portable OBS websocket unavailable')
        try:
            dismiss_setup(self.proc.pid)
            scenes = self.rpc('GetSceneList')['scenes']
            if not any(x['sceneName']=='ACNG Film' for x in scenes):
                self.rpc('CreateScene',{'sceneName':'ACNG Film'})
            # Remove automatically created audio sources in this isolated copy.
            for item in self.rpc('GetInputList')['inputs']:
                if 'wasapi' in item['inputKind']:
                    self.rpc('RemoveInput',{'inputName':item['inputName']})
            key=window_key(pid)
            for name,kind,settings in game_inputs(key):
                self.rpc('CreateInput',{'sceneName':'ACNG Film','inputName':name,
                    'inputKind':kind,'inputSettings':settings,'sceneItemEnabled':True})
            self.rpc('SetInputAudioTracks',{'inputName':'ACNG Game Audio',
                'inputAudioTracks':{str(i):i==1 for i in range(1,7)}})
            item=self.rpc('GetSceneItemId',{'sceneName':'ACNG Film','sourceName':'ACNG Game'})['sceneItemId']
            self.rpc('SetSceneItemTransform',{'sceneName':'ACNG Film','sceneItemId':item,
                'sceneItemTransform':{'boundsType':'OBS_BOUNDS_STRETCH','boundsWidth':width,'boundsHeight':height,
                    'positionX':0,'positionY':0}})
            self.rpc('SetCurrentProgramScene',{'sceneName':'ACNG Film'})
            self.rpc('SetVideoSettings',{'baseWidth':width,'baseHeight':height,
                'outputWidth':width,'outputHeight':height,'fpsNumerator':fps,'fpsDenominator':1})
            time.sleep(2)
        except Exception:
            self.close();raise

    def rpc(self, kind, data=None):
        return self.client.send(kind, data or {}, raw=True)

    def start(self):
        # Qt can create the first-run wizard after the websocket is already ready.
        for _ in range(3):
            dismiss_setup(self.proc.pid)
            if self.rpc('GetRecordStatus')['outputActive']:return
            self.rpc('StartRecord')
            time.sleep(2)
            if self.rpc('GetRecordStatus')['outputActive']:return
        self.close();raise RuntimeError('OBS recording did not start')

    def alive(self):
        return self.proc.poll() is None

    def stop(self):
        path=Path(self.rpc('StopRecord')['outputPath'])
        for _ in range(50):
            if not self.rpc('GetRecordStatus')['outputActive']:break
            time.sleep(0.1)
        time.sleep(1)
        return path

    def close(self):
        if self.client:
            self.client.disconnect()
        # This handle belongs to the portable process started above, never user OBS.
        if self.proc.poll() is None:
            self.proc.terminate();self.proc.wait(timeout=15)
