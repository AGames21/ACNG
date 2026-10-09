"""One command for a local car import: build, test in a fresh isolated lab, optionally install.

Runs the same steps as a manual car checkpoint (docs/CAR-IMPORT.md):
  1. build the car with converters/build_ac_car.py into the next numbered folder outside the repo
  2. start the CarLab harness in the next fresh ACNG-car-NNN lab profile with that exact ZIP
  3. wait for the lab result, then stop that lab game (only the process this script started)
  4. print every native check; with --install, hand the tested ZIP to install_car_normal.py

Refuses to start while any BeamNG is running, so a player's drive is never touched.

Usage:
  python scripts/car_pipeline.py                     # build + lab test, report only
  python scripts/car_pipeline.py --install           # ... and install if every check passed
  python scripts/car_pipeline.py --zip <tested.zip>  # skip the build, test an existing ZIP
"""
import argparse
import csv
import io
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = 'BeamNG.drive.x64.exe'
RESULT = 'acng-car-test.json'


def load_paths():
    return json.loads((ROOT / '.local' / 'paths.json').read_text(encoding='utf-8'))


def next_folder(parent, prefix):
    """parent/prefix-NNN with NNN one above the highest existing number (gaps are not reused)."""
    pattern = re.compile(re.escape(prefix) + r'-(\d{3,})$')
    used = [int(m.group(1)) for p in Path(parent).iterdir() if (m := pattern.match(p.name))] \
        if Path(parent).is_dir() else []
    return Path(parent) / f'{prefix}-{max(used, default=0) + 1:03d}'


def game_running():
    out = subprocess.check_output(['tasklist', '/FI', f'IMAGENAME eq {GAME}', '/FO', 'CSV', '/NH'], text=True)
    return any(row and row[0].lower() == GAME.lower() for row in csv.reader(io.StringIO(out)))


def process_path(pid):
    out = subprocess.run(['powershell', '-NoProfile', '-Command', f'(Get-Process -Id {int(pid)} -ErrorAction SilentlyContinue).Path'],
                         capture_output=True, text=True)
    return out.stdout.strip()


def stop_lab_game(pid):
    path = process_path(pid)
    if not path:
        return 'already exited'
    if 'beamng' not in path.lower():
        return f'PID {pid} is not BeamNG ({path}); left running'
    subprocess.run(['powershell', '-NoProfile', '-Command', f'Stop-Process -Id {int(pid)}'], check=True)
    for _ in range(30):
        if not process_path(pid):
            return 'stopped'
        time.sleep(1)
    return 'stop requested; still exiting'


def summarize(result):
    checks = result.get('checks', {})
    failed = sorted(k for k, v in checks.items() if v is not True)
    return {'test': result.get('test'), 'completed': result.get('completed') is True, 'error': result.get('error'),
            'stage': result.get('stage'), 'passed': len(checks) - len(failed), 'total': len(checks), 'failed': failed,
            'ok': result.get('completed') is True and not result.get('error') and not failed and bool(checks)}


def wait_for_result(result_file, pid, timeout_s, poll_s=10):
    start, last_stage = time.time(), None
    while time.time() - start < timeout_s:
        if result_file.is_file():
            try:
                result = json.loads(result_file.read_text(encoding='utf-8'))
            except (ValueError, OSError):
                result = None  # mid-write; read again next poll
            if result:
                if result.get('stage') != last_stage:
                    last_stage = result.get('stage')
                    print(f'  lab stage: {last_stage}', flush=True)
                if result.get('completed') or result.get('error'):
                    return result
        if not process_path(pid):
            return json.loads(result_file.read_text(encoding='utf-8')) if result_file.is_file() else {}
        time.sleep(poll_s)
    return json.loads(result_file.read_text(encoding='utf-8')) if result_file.is_file() else {}


def main():
    paths = load_paths()
    work = Path(paths['lab_user']).resolve().parents[1]
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--ac-car', default=str(Path(paths['assetto']) / 'content' / 'cars' / 'bmw_1m'))
    ap.add_argument('--skin', default='valencia_orange')
    ap.add_argument('--zip', type=Path, help='test this already-built ZIP instead of building')
    ap.add_argument('--install', action='store_true', help='install in the normal profile if every check passes')
    ap.add_argument('--timeout', type=int, default=1800, help='seconds to wait for the lab run')
    a = ap.parse_args()

    if game_running():
        raise SystemExit('BeamNG is running. Close it first; this pipeline never touches a running game.')

    if a.zip:
        package = a.zip.resolve()
    else:
        out = next_folder(work / 'ACNG-car', 'bmw1m-fix')
        print(f'1/4 build -> {out}', flush=True)
        subprocess.run([sys.executable, str(ROOT / 'converters' / 'build_ac_car.py'), '--ac-car', a.ac_car,
                        '--beamng', paths['beamng'], '--out', str(out), '--skin', a.skin], check=True)
        package = out / 'acng_bmw1m.zip'
    if not package.is_file():
        raise SystemExit(f'No car ZIP at {package}')

    lab = next_folder(work, 'ACNG-car') / 'current'
    print(f'2/4 lab -> {lab.parent}', flush=True)
    launch = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                             str(ROOT / 'scripts' / 'launch-lab.ps1'), '-Experiment', 'CarLab',
                             '-LabUser', str(lab), '-ExtraMod', str(package)],
                            capture_output=True, text=True)
    print(launch.stdout.strip())
    found = re.search(r'PID (\d+)', launch.stdout)
    if launch.returncode != 0 or not found:
        raise SystemExit('Lab launch failed:\n' + launch.stderr)
    pid = int(found.group(1))

    print(f'3/4 waiting for the lab (up to {a.timeout // 60} min)', flush=True)
    try:
        result = wait_for_result(lab / RESULT, pid, a.timeout)
    finally:
        print(f'  lab game: {stop_lab_game(pid)}')

    summary = summarize(result)
    summary.update(zip=str(package), lab_result=str(lab / RESULT))
    (package.parent / 'pipeline_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(f"4/4 {summary['test']}: {summary['passed']}/{summary['total']} checks"
          + (f", stopped at '{summary['stage']}'" if not summary['completed'] else '')
          + (f", error: {summary['error']}" if summary['error'] else ''))
    for name in summary['failed']:
        print(f'  FAIL {name}')
    if not summary['ok']:
        raise SystemExit('Not installed: the lab run did not pass every check.')
    if a.install:
        subprocess.run([sys.executable, str(ROOT / 'scripts' / 'install_car_normal.py'), '--zip', str(package),
                        '--test', str(lab / RESULT), '--confirm-normal'], check=True)
    else:
        print('All checks passed. To install this exact ZIP:\n  python scripts/install_car_normal.py '
              f'--zip "{package}" --test "{lab / RESULT}" --confirm-normal')


if __name__ == '__main__':
    main()
