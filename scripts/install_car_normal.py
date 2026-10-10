"""Install only an independently built, natively tested local AC car ZIP; preserve other mods."""
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
# C014 and later: the generic CarLab (targets from the zip's acng_car/<vehicle>.json, 1M without one).
GENERIC = {'C014'}
GENERIC_REQUIRED = {
    'spawn_undamaged', 'drive_no_self_damage', 'reset_repairs_native', 'native_prop_meshes_created',
    'three_native_mirrors', 'three_native_mirror_cameras', 'four_bmw_rim_meshes',
    'gauges_receive_native_engine_signals', 'speed_gauge_receives_native_motion',
    'lamp_glow_registered', 'lowbeam_and_brake_signals', 'interior_steady_at_idle',
    'interior_steady_while_driving', 'tires_auto_compound', 'unladen_mass_within_three_percent',
    'crash_isolation_groups_found', 'tires_centred_on_ac_wheels', 'front_wheels_steer_right',
    'torque_curve_matches_ac', 'ac_engine_sound_loaded', 'native_top_speed_limit_configured',
    'native_event_samples_loaded', 'power_and_torque_target', 'fuel_capacity_target',
    'verified_first_and_top_ratios', 'verified_final_drive'}
# Counted checks: the car's own number of controls / gauges / top speed is in the name.
GENERIC_PREFIXES = ('animated_controls_', 'native_gauges_', 'top_speed_limiter_holds_')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record_path_for(model):
    # The 1M keeps its original record name so update_normal and old handoffs still find it.
    return ROOT / '.local' / ('car-install.json' if model == 'acng_bmw1m' else f'car-install-{model}.json')


def model_of(package):
    """The single vehicle folder in a car ZIP (vehicles/<model>/)."""
    with zipfile.ZipFile(package) as archive:
        models = {n.split('/')[1] for n in archive.namelist() if n.startswith('vehicles/') and n.count('/') >= 2}
    if len(models) != 1:
        raise RuntimeError('Unexpected car ZIP paths: one vehicles/<model>/ folder required')
    return models.pop()


def contains_model(package, model=MODEL):
    try:
        with zipfile.ZipFile(package) as archive:
            return 'vehicles/' + model + '/info.json' in archive.namelist()
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
    model = model_of(package)
    if not proof.get('completed') or proof.get('error') or version not in {'C002', 'C003', 'C004', 'C006', 'C007', 'C008', 'C009', 'C010', 'C011', 'C012', 'C013'} | GENERIC:
        raise RuntimeError('A completed C002-C014 native run is required')
    if model != MODEL and version not in GENERIC:
        raise RuntimeError('Cars other than the 1M need a C014 or later native run')
    if version in GENERIC and proof.get('model') != model:
        raise RuntimeError('Native run tested a different car')
    with zipfile.ZipFile(package) as archive:
        targets_name = 'acng_car/' + model + '.json'
        targets = json.loads(archive.read(targets_name)) if targets_name in archive.namelist() else None
    checks = proof.get('checks', {})
    required = {'spawn_undamaged', 'drive_no_self_damage', 'reset_repairs_native',
                'four_animated_controls', 'native_prop_meshes_created', 'native_shifter_moves'}
    if version in {'C003', 'C004', 'C006', 'C007', 'C008', 'C009', 'C010', 'C011', 'C012', 'C013'}:
        required.update({'four_native_gauges', 'three_native_mirrors',
                         'three_native_mirror_cameras', 'four_bmw_rim_meshes',
                         'gauges_receive_native_engine_signals', 'speed_gauge_receives_native_motion'})
    if version in {'C004', 'C006', 'C007', 'C008', 'C009', 'C010', 'C011', 'C012', 'C013'}:
        required.update({'lamp_glow_registered', 'lowbeam_and_brake_signals', 'interior_steady_at_idle',
                         'interior_steady_while_driving', 'tires_auto_compound',
                         'unladen_mass_within_three_percent'})
    if version in {'C008', 'C009', 'C010', 'C011', 'C012', 'C013'}:
        required.add('crash_isolation_groups_found')
    if version in {'C009', 'C010', 'C011', 'C012', 'C013'}:
        required.update({'tires_centred_on_ac_wheels', 'front_wheels_steer_right'})
    if version in {'C011', 'C012', 'C013'}:
        required.update({'torque_curve_matches_ac', 'ac_engine_sound_loaded'})
    if version == 'C013':
        required.update({'native_top_speed_limit_configured', 'native_turbo_samples_loaded',
                         'native_shift_samples_loaded', 'top_speed_limiter_holds_250'})
    if version in GENERIC:
        required = set(GENERIC_REQUIRED)
        # A zip without targets is the 1M, which has an animated H-pattern shifter.
        if targets is None or targets.get('shifter_node'):
            required.add('native_shifter_moves')
        if not all(any(k.startswith(prefix) for k in checks) for prefix in GENERIC_PREFIXES):
            raise RuntimeError('Native validation is incomplete or failed')
    if not required.issubset(checks) or not all(value is True for value in checks.values()):
        raise RuntimeError('Native validation is incomplete or failed')
    lab_copy = test_file.parent / 'mods' / package.name
    if not lab_copy.is_file() or digest(package) != digest(lab_copy):
        raise RuntimeError('ZIP differs from the exact content tested in the native lab')
    with zipfile.ZipFile(package) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('Corrupt car ZIP')
        prefix = 'vehicles/' + model + '/'
        if any(not (n.startswith(prefix) or n == targets_name) or '..' in Path(n).parts for n in archive.namelist()):
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
    model = model_of(args.zip)
    user = (Path(os.environ['LOCALAPPDATA']) / 'BeamNG/BeamNG.drive/current').resolve()
    if not (user / 'mods/db.json').is_file() or (user / 'mods').is_symlink():
        raise RuntimeError('Normal profile identity is not verified')
    installed = user / 'mods' / (model + '.zip')
    record_path = record_path_for(model)
    if installed.exists():
        record = json.loads(record_path.read_text()) if record_path.is_file() else {}
        if installed.is_symlink() or digest(installed) != record.get('sha256'):
            raise RuntimeError('Existing car is not our recorded build; preserve and review it')
        if digest(installed) == sha:
            print('Normal profile already has this verified car build.'); return
    for other in (user / 'mods').rglob('info.json'):
        if other.parent.name.lower() == model:
            raise RuntimeError('Another unpacked copy of this car exists; preserve and review it')
    for other in (user / 'mods').rglob('*.zip'):
        if other == installed:
            continue
        if contains_model(other, model):
            raise RuntimeError('Another ZIP contains this car; preserve and review it')
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup = args.zip.resolve().parent / ('normal-install-backup-' + stamp)
    backup.mkdir()
    shutil.copy2(user / 'mods/db.json', backup / 'db.json')
    if installed.exists():
        shutil.copy2(installed, backup / installed.name)
    if record_path.exists():
        shutil.copy2(record_path, backup / record_path.name)
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
    record_path.write_text(json.dumps({'model': model, 'installed': str(installed), 'sha256': sha,
        'native_checks': count, 'test': str(args.test.resolve()), 'backup': str(backup),
        'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()}, indent=2))
    print(f'Installed local {model}; {count} native checks passed; installed hash matches the tested ZIP.')


if __name__ == '__main__':
    main()
