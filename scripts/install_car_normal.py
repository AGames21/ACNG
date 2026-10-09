"""Install only an independently built, natively tested local 1M ZIP; preserve other mods."""
import argparse
import csv
import datetime
import hashlib
import io
import json
import os
import shutil
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = 'acng_bmw1m'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contains_model(package):
    try:
        with zipfile.ZipFile(package) as archive:
            return 'vehicles/' + MODEL + '/info.json' in archive.namelist()
    except (zipfile.BadZipFile, UnicodeDecodeError):
        # Some third-party ZIPs mark legacy-encoded filenames as UTF-8. Preserve
        # them; this installer does not repair or rewrite somebody else's mod.
        if package.name.lower().startswith('acng'):
            raise RuntimeError('Unreadable ACNG archive requires manual review')
        return False


def verify_local_build(package, test_file):
    package, test_file = Path(package).resolve(), Path(test_file).resolve()
    proof = json.loads(test_file.read_text(encoding='utf-8'))
    version = proof.get('test', '').split(' ', 1)[0]
    if not proof.get('completed') or proof.get('error') or version not in {'C002', 'C003', 'C004', 'C006', 'C007', 'C008', 'C009', 'C010'}:
        raise RuntimeError('A completed C002/C003/C004/C006/C007/C008/C009/C010 native run is required')
    checks = proof.get('checks', {})
    required = {'spawn_undamaged', 'drive_no_self_damage', 'reset_repairs_native',
                'four_animated_controls', 'native_prop_meshes_created', 'native_shifter_moves'}
    if version in {'C003', 'C004', 'C006', 'C007', 'C008', 'C009', 'C010'}:
        required.update({'four_native_gauges', 'three_native_mirrors',
                         'three_native_mirror_cameras', 'four_bmw_rim_meshes',
                         'gauges_receive_native_engine_signals', 'speed_gauge_receives_native_motion'})
    if version in {'C004', 'C006', 'C007', 'C008', 'C009', 'C010'}:
        required.update({'lamp_glow_registered', 'lowbeam_and_brake_signals', 'interior_steady_at_idle',
                         'interior_steady_while_driving', 'tires_auto_compound',
                         'unladen_mass_within_three_percent'})
    if version in {'C008', 'C009', 'C010'}:
        required.add('crash_isolation_groups_found')
    if version in {'C009', 'C010'}:
        required.update({'tires_centred_on_ac_wheels', 'front_wheels_steer_right'})
    if not required.issubset(checks) or not all(value is True for value in checks.values()):
        raise RuntimeError('Native validation is incomplete or failed')
    lab_copy = test_file.parent / 'mods' / package.name
    if not lab_copy.is_file() or digest(package) != digest(lab_copy):
        raise RuntimeError('ZIP differs from the exact content tested in the native lab')
    with zipfile.ZipFile(package) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('Corrupt car ZIP')
        prefix = 'vehicles/' + MODEL + '/'
        if any(not n.startswith(prefix) or '..' in Path(n).parts for n in archive.namelist()):
            raise RuntimeError('Unexpected car ZIP paths')
        if prefix + 'info.json' not in archive.namelist():
            raise RuntimeError('Car metadata missing')
    return digest(package), len(checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', required=True, type=Path)
    parser.add_argument('--test', required=True, type=Path)
    parser.add_argument('--confirm-normal', action='store_true', required=True)
    args = parser.parse_args()
    processes = subprocess.check_output(['tasklist', '/FI', 'IMAGENAME eq BeamNG.drive.x64.exe',
                                         '/FO', 'CSV', '/NH'], text=True)
    if any(row and row[0].lower() == 'beamng.drive.x64.exe' for row in csv.reader(io.StringIO(processes))):
        raise RuntimeError('Close BeamNG before installing in the normal profile')
    sha, count = verify_local_build(args.zip, args.test)
    user = (Path(os.environ['LOCALAPPDATA']) / 'BeamNG/BeamNG.drive/current').resolve()
    if not (user / 'mods/db.json').is_file() or (user / 'mods').is_symlink():
        raise RuntimeError('Normal profile identity is not verified')
    installed = user / 'mods' / (MODEL + '.zip')
    record_path = ROOT / '.local/car-install.json'
    if installed.exists():
        record = json.loads(record_path.read_text()) if record_path.is_file() else {}
        if installed.is_symlink() or digest(installed) != record.get('sha256'):
            raise RuntimeError('Existing car is not our recorded build; preserve and review it')
        if digest(installed) == sha:
            print('Normal profile already has this verified car build.'); return
    for other in (user / 'mods').rglob('info.json'):
        if other.parent.name.lower() == MODEL:
            raise RuntimeError('Another unpacked 1M exists; preserve and review it')
    for other in (user / 'mods').rglob('*.zip'):
        if other == installed:
            continue
        if contains_model(other):
            raise RuntimeError('Another ZIP contains this car; preserve and review it')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = args.zip.resolve().parent / ('normal-install-backup-' + stamp)
    backup.mkdir()
    shutil.copy2(user / 'mods/db.json', backup / 'db.json')
    if installed.exists():
        shutil.copy2(installed, backup / installed.name)
    if record_path.exists():
        shutil.copy2(record_path, backup / 'car-install.json')
    temp = installed.with_suffix('.acng-pending')
    if temp.exists():
        raise RuntimeError('Pending install already exists; preserve and review it')
    shutil.copy2(args.zip, temp)
    if digest(temp) != sha:
        raise RuntimeError('Copied car ZIP hash mismatch')
    temp.replace(installed)
    if digest(installed) != sha:
        raise RuntimeError('Installed car ZIP hash mismatch')
    record_path.parent.mkdir(exist_ok=True)
    record_path.write_text(json.dumps({'installed': str(installed), 'sha256': sha,
        'native_checks': count, 'test': str(args.test.resolve()), 'backup': str(backup),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}, indent=2))
    print(f'Installed local 1M; {count} native checks passed; installed hash matches the tested ZIP.')


if __name__ == '__main__':
    main()
