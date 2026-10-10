"""Replace the ACNG ZIP in the authorized normal profile with a newer verified build.

Only touches mods/acng-freeroam.zip. Backs up the old ZIP, ACNG settings and the
mod database first. Refuses if BeamNG is running, if the installed ZIP is not the
one this tool or install_normal.py recorded, or if the new build fails its hashes.
"""
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

ROOT=Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_package(package):
    manifest=json.loads(package.with_suffix('.build.json').read_text())
    if digest(package)!=manifest['sha256']:
        raise RuntimeError('Package hash does not match verified build')
    with zipfile.ZipFile(package) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('Corrupt player ZIP')
        names=archive.namelist()
        if any('weekend' in name.lower() or name.startswith('tests/') or '..' in Path(name).parts for name in names):
            raise RuntimeError('Unexpected player ZIP content')
        for item in manifest['files']:
            if hashlib.sha256(archive.read(item['path'])).hexdigest()!=item['sha256']:
                raise RuntimeError('Player file hash mismatch: '+item['path'])
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-normal',action='store_true',required=True)
    parser.parse_args()
    processes=subprocess.check_output(['tasklist','/FI','IMAGENAME eq BeamNG.drive.x64.exe','/FO','CSV','/NH'],text=True)
    if any(row and row[0].lower()=='beamng.drive.x64.exe' for row in csv.reader(io.StringIO(processes))):
        raise RuntimeError('Close BeamNG before changing its normal profile')
    record_path=ROOT/'.local/normal-install.json'
    record=json.loads(record_path.read_text(encoding='utf-8'))
    user=Path(record['profile']).resolve()
    expected=(Path(os.environ['LOCALAPPDATA'])/'BeamNG/BeamNG.drive/current').resolve()
    if user!=expected or not (user/'mods/db.json').is_file():
        raise RuntimeError('Registered normal profile identity not verified')
    installed=user/'mods/acng-freeroam.zip'
    if not installed.is_file() or installed.is_symlink():
        raise RuntimeError('Recorded ACNG ZIP is missing; review by hand')
    if digest(installed)!=record['package_sha256']:
        raise RuntimeError('Installed ACNG ZIP is not the recorded build; review by hand')
    # A separately verified local vehicle is not another copy of the ACNG extension.
    # Never exclude arbitrary similarly named ZIPs: require our installer record/hash.
    # One record per installed car: car-install.json (1M) and car-install-<model>.json.
    allowed_cars=set()
    for car_record_path in sorted((ROOT/'.local').glob('car-install*.json')):
        car_record=json.loads(car_record_path.read_text(encoding='utf-8'))
        candidate=user/'mods'/(car_record.get('model','acng_bmw1m')+'.zip')
        if (candidate.is_file() and not candidate.is_symlink()
                and Path(car_record.get('installed','')).resolve()==candidate.resolve()
                and digest(candidate)==car_record.get('sha256')):
            allowed_cars.add(candidate)
    others=[p for p in (user/'mods').rglob('*') if p.name.lower().startswith('acng') and p!=installed and p not in allowed_cars]
    if others:
        raise RuntimeError('Another ACNG copy needs review: '+str(others[0]))
    package=ROOT/'dist/acng-freeroam.zip'
    manifest=verify_package(package)
    if manifest['sha256']==record['package_sha256']:
        print('Normal profile already has this build.');return
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=Path(record['backup']).parent/('ACNG-normal-update-'+stamp)
    backup.mkdir()
    shutil.copy2(installed,backup/'acng-freeroam.zip')
    if (user/'settings/acng').is_dir():
        shutil.copytree(user/'settings/acng',backup/'settings-acng',symlinks=False)
    shutil.copy2(user/'mods/db.json',backup/'db.json')
    temp=installed.with_suffix('.acng-pending')
    shutil.copy2(package,temp)
    if digest(temp)!=manifest['sha256']:
        temp.unlink();raise RuntimeError('Copied ZIP hash mismatch')
    temp.replace(installed)
    if digest(installed)!=manifest['sha256']:
        shutil.copy2(backup/'acng-freeroam.zip',installed)
        raise RuntimeError('Installed ZIP hash mismatch; old ZIP restored')
    updates=record.get('updates',[])
    updates.append({'time':stamp,'backup':str(backup),'from_sha256':record['package_sha256'],'from_commit':record['source_commit'],
                    'to_sha256':manifest['sha256'],'to_commit':manifest['source_commit']})
    record.update({'package_sha256':manifest['sha256'],'source_commit':manifest['source_commit'],'updates':updates})
    record_path.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    (backup/'update-record.json').write_text(json.dumps(updates[-1],indent=2)+'\n',encoding='utf-8')
    print(f"Updated normal-profile ACNG {updates[-1]['from_commit'][:7]} -> {manifest['source_commit'][:7]}. Old ZIP and ACNG settings backed up.")
    print('Backup:',backup)


if __name__=='__main__':
    main()
