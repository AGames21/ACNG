"""Film an ACNG lab experiment: launch it in a fresh lab profile, record the game window
and cut clips between the harness's film cues.

    python tools/film_lab.py --experiment TireDirt
    python tools/film_lab.py --experiment TireDirt --clip dirt=drive_start:drive_end --size 1920x1080

Lab only. It never touches the normal BeamNG profile: the window size and the HUD layout
are written into the new lab profile before the first launch. The harness writes
/acng-film-cues.json ({"cues": [{"name", "seq", "sim_time_s"}]}); this tool notes the
video time each cue appears and cuts [first cue - pad, second cue + pad]. Raw video and
clips stay in the lab folder, outside the repository. Needs ffmpeg on PATH (or --ffmpeg).
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from minimal_hud import PLACE  # noqa: E402

GAME_EXE = 'BeamNG.drive.x64.exe'


def parse_size(text):
    m = re.fullmatch(r'(\d{3,4})x(\d{3,4})', text)
    if not m:
        raise argparse.ArgumentTypeError('size is WIDTHxHEIGHT, e.g. 1920x1080')
    return int(m.group(1)), int(m.group(2))


def parse_clip(text):
    """'name=start_cue:end_cue' -> (name, start, end)."""
    m = re.fullmatch(r'([A-Za-z0-9_-]+)=([A-Za-z0-9_]+):([A-Za-z0-9_]+)', text)
    if not m:
        raise argparse.ArgumentTypeError('clip is name=start_cue:end_cue')
    return m.groups()


def lab_settings(width, height):
    """Settings for a new lab profile: a plain window of the film size."""
    return {'GraphicDisplayModes': 'Window', 'GraphicDisplayResolutions': f'{width} {height}'}


# BeamNG 0.39.4 stock freeroam apps; used when the game's original layout can't be read.
STOCK_APPS = ('forcedInduction', 'simplePowertrainControl', 'damageApp', 'tacho2', 'inputHints',
              'topLeftApps', 'topCenterApps', 'dragRace')


def original_layout(beamng):
    """The game's own freeroam layout (lenient JSON: trailing commas), or None."""
    path = Path(beamng) / 'settings' / 'ui_apps' / 'originalLayouts' / 'default' / 'freeroam.uilayout.json'
    try:
        text = path.read_text(encoding='utf-8-sig')
        return json.loads(re.sub(r',(\s*[}\]])', r'\1', text))
    except (OSError, ValueError):
        return None


def film_layout(original=None):
    """Freeroam layout with only the ACNG pill and tire tiles. On load the game merges every
    versioned stock app back into a user layout unless removedApps marks it, and replaces the
    whole layout if its version is older, so both come from the game's original layout."""
    original = original or {}
    stock = [a.get('appName') for a in original.get('apps', [])] or list(STOCK_APPS)
    removed = dict(original.get('removedApps') or {})
    removed.update({name: True for name in stock if name})
    return {'apps': [{'appName': name, 'placement': dict(PLACE[name])} for name in ('acngControl', 'acngTires')],
            'removedApps': removed, 'title': 'Freeroam', 'type': 'freeroam',
            'version': original.get('version', 0.54)}


def prepare_profile(lab, width, height, original=None):
    """Write the window size and HUD layout into a lab profile that does not exist yet."""
    if lab.exists():
        raise RuntimeError(f'{lab} exists; film in a fresh lab profile')
    settings = lab / 'settings' / 'settings.json'
    layout = lab / 'settings' / 'ui_apps' / 'layouts' / 'default' / 'freeroam.uilayout.json'
    for path, data in ((settings, lab_settings(width, height)), (layout, film_layout(original))):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')


def new_cues(data, seen):
    """Cues in a cue file not seen yet, in order."""
    cues = sorted((data or {}).get('cues', []), key=lambda c: c.get('seq', 0))
    return [c for c in cues if c.get('seq') not in seen]


def clip_windows(times, clips, pad_before, pad_after, length=None):
    """{cue name: video seconds} and [(name, start, end)] -> [(name, start, end)] cut windows.
    A clip whose cues never came is skipped."""
    out = []
    for name, a, b in clips:
        if a in times and b in times and times[b] > times[a]:
            start = max(0.0, times[a] - pad_before)
            end = times[b] + pad_after
            if length is not None:
                end = min(end, length)
            out.append((name, round(start, 3), round(end, 3)))
    return out


def encoder_args(ffmpeg):
    """NVENC when this ffmpeg and GPU have it, else x264."""
    probe = subprocess.run([ffmpeg, '-hide_banner', '-f', 'lavfi', '-i', 'color=c=black:s=256x256:d=0.2',
                            '-c:v', 'h264_nvenc', '-f', 'null', '-'], capture_output=True)
    if probe.returncode == 0:
        return ['-c:v', 'h264_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', '19', '-b:v', '0']
    return ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18']


def record_args(ffmpeg, rect, fps, out, encoder):
    """gdigrab of a desktop region (the game client area); DWM composes D3D windows there."""
    x, y, w, h = rect
    return [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'gdigrab', '-framerate', str(fps),
            '-draw_mouse', '0', '-offset_x', str(x), '-offset_y', str(y), '-video_size', f'{w}x{h}',
            '-i', 'desktop', *encoder, '-pix_fmt', 'yuv420p', str(out)]


def cut_args(ffmpeg, raw, start, end, out):
    return [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-ss', f'{start:.3f}', '-to', f'{end:.3f}',
            '-i', str(raw), '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p',
            '-movflags', '+faststart', str(out)]


# --- Windows helpers ---------------------------------------------------------------

def game_pids():
    rows = subprocess.run(['tasklist', '/FI', f'IMAGENAME eq {GAME_EXE}', '/FO', 'CSV', '/NH'],
                          capture_output=True, text=True).stdout
    return [int(r.split('","')[1]) for r in rows.splitlines() if r.lower().startswith(f'"{GAME_EXE.lower()}"')]


def window_rect(pid):
    """Screen rect (x, y, w, h) of the biggest visible top-level window of pid, or None."""
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def visit(hwnd, _):
        owner = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            r = wt.RECT()
            user32.GetClientRect(hwnd, ctypes.byref(r))
            p = wt.POINT(0, 0)
            user32.ClientToScreen(hwnd, ctypes.byref(p))
            found.append((r.right * r.bottom, hwnd, (p.x, p.y, r.right, r.bottom)))
        return True

    user32.EnumWindows(visit, 0)
    if not found:
        return None
    area, hwnd, rect = max(found)
    if area < 640 * 360:
        return None
    user32.SetForegroundWindow(hwnd)
    return rect


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--experiment', required=True)
    ap.add_argument('--lab', type=Path, help='new lab profile (…\\current); default a stamped ACNG-film folder')
    ap.add_argument('--size', type=parse_size, default=(1920, 1080))
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--clip', type=parse_clip, action='append', help='name=start_cue:end_cue (repeatable)')
    ap.add_argument('--pad-before', type=float, default=1.5)
    ap.add_argument('--pad-after', type=float, default=1.5)
    ap.add_argument('--end-cue', default='complete')
    ap.add_argument('--timeout', type=float, default=600)
    ap.add_argument('--keep-open', action='store_true', help='leave the lab game running afterwards')
    ap.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    args = ap.parse_args(argv)
    if not args.ffmpeg:
        ap.error('ffmpeg not found; pass --ffmpeg')
    if game_pids():
        raise RuntimeError('Close BeamNG before filming a lab')
    clips = args.clip or [('drive', 'drive_start', 'drive_end')]
    paths = json.loads((ROOT / '.local' / 'paths.json').read_text(encoding='utf-8-sig'))
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    lab = (args.lab or Path(paths['lab_user']).parents[1] / f'ACNG-film-{args.experiment.lower()}-{stamp}' / 'current').resolve()
    if lab == Path(paths['beamng_user']).resolve():
        raise RuntimeError('Film in a lab profile, never the normal one')
    out_dir = lab.parent / 'film'
    prepare_profile(lab, *args.size, original=original_layout(paths['beamng']))
    out_dir.mkdir(parents=True, exist_ok=True)
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
    launch = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                             str(ROOT / 'scripts' / 'launch-lab.ps1'), '-Experiment', args.experiment,
                             '-LabUser', str(lab), '-Visible'], capture_output=True, text=True)
    print(launch.stdout.strip())
    m = re.search(r'PID (\d+)', launch.stdout)
    if launch.returncode != 0 or not m:
        raise RuntimeError('lab launch failed: ' + launch.stderr.strip())
    pid = int(m.group(1))
    deadline = time.time() + args.timeout
    rect = None
    while time.time() < deadline and rect is None:
        time.sleep(1)
        rect = window_rect(pid)
    if rect is None:
        raise RuntimeError('game window never appeared')
    time.sleep(3)
    rect = window_rect(pid) or rect
    rect = (rect[0], rect[1], rect[2] // 2 * 2, rect[3] // 2 * 2)  # yuv420p wants even sizes
    raw = out_dir / f'{args.experiment.lower()}-raw.mp4'
    print('recording', rect, '->', raw)
    rec = subprocess.Popen(record_args(args.ffmpeg, rect, args.fps, raw, encoder_args(args.ffmpeg)),
                           stdin=subprocess.PIPE)
    t0 = time.time()
    cue_file, seen, times, log = lab / 'acng-film-cues.json', set(), {}, []
    try:
        while time.time() < deadline and args.end_cue not in times:
            time.sleep(0.1)
            if rec.poll() is not None:
                raise RuntimeError('ffmpeg stopped early')
            try:
                data = json.loads(cue_file.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                continue
            for c in new_cues(data, seen):
                seen.add(c.get('seq'))
                times[c['name']] = round(time.time() - t0, 3)
                log.append({**c, 'video_s': times[c['name']]})
                print(f"cue {c['name']} at {times[c['name']]:.1f}s")
        time.sleep(args.pad_after + 0.5)
    finally:
        rec.communicate(b'q', timeout=30)
        if not args.keep_open and pid in game_pids():
            subprocess.run(['taskkill', '/PID', str(pid), '/T', '/F'], capture_output=True)
    length = time.time() - t0
    windows = clip_windows(times, clips, args.pad_before, args.pad_after, length)
    for name, start, end in windows:
        out = out_dir / f'{args.experiment.lower()}-{name}.mp4'
        subprocess.run(cut_args(args.ffmpeg, raw, start, end, out), check=True)
        print('clip', out, f'{end - start:.1f}s')
    (out_dir / 'film-cues.json').write_text(json.dumps({'lab': str(lab), 'rect': rect, 'cues': log,
                                                        'clips': windows}, indent=2) + '\n', encoding='utf-8')
    missing = [c[0] for c in clips if c[0] not in {w[0] for w in windows}]
    if missing:
        print('no cues for clips:', ', '.join(missing))
    return 0 if windows and not missing else 1


if __name__ == '__main__':
    sys.exit(main())
