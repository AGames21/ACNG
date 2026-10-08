"""Explicitly authorized normal-profile install; no game files or unrelated mods changed."""
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


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--confirm-normal',action='store_true',required=True)
    parser.parse_args()
    processes=subprocess.check_output(['tasklist','/FI','IMAGENAME eq BeamNG.drive.x64.exe','/FO','CSV','/NH'],text=True)
    if any(row and row[0].lower()=='beamng.drive.x64.exe' for row in csv.reader(io.StringIO(processes))):
        raise RuntimeError('Close BeamNG before changing its normal profile')
    paths=json.loads((ROOT/'.local/paths.json').read_text(encoding='utf-8-sig'))
    user=Path(paths['beamng_user']).resolve()
    expected=(Path(os.environ['LOCALAPPDATA'])/'BeamNG/BeamNG.drive/current').resolve()
    if user!=expected or not (user/'mods/db.json').is_file():
        raise RuntimeError('Registered normal profile identity not verified')
    package=ROOT/'dist/acng-freeroam.zip'
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
    # Never guess which differently named ZIP/mod belongs to ACNG.
    existing=[p for p in (user/'mods').rglob('*') if p.name.lower().startswith('acng')]
    if existing:
        raise RuntimeError('Existing ACNG needs a separate backup/duplicate review: '+str(existing[0]))
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=Path(paths['lab_user']).parents[1]/('ACNG-normal-backup-'+stamp)
    backup.mkdir()
    shutil.copytree(user/'settings',backup/'settings',symlinks=False)
    if (user/'vehicles').exists():
        shutil.copytree(user/'vehicles',backup/'vehicles',symlinks=False)
    (backup/'mods').mkdir();shutil.copy2(user/'mods/db.json',backup/'mods/db.json')
    layout=user/'settings/ui_apps/layouts/default/freeroam.uilayout.json'
    old_bytes=layout.read_bytes();old=json.loads(old_bytes)
    data=json.loads(old_bytes)
    if any(app.get('appName')=='acngControl' for app in data['apps']):
        raise RuntimeError('ACNG UI already present; stop duplicate install')
    data['apps'].append({'appName':'acngControl','placement':{'right':'24px','top':'70px','width':'360px','height':'480px','position':'absolute'}})
    temp=layout.with_suffix('.acng-pending')
    destination=user/'mods/acng-freeroam.zip'
    copied=False;layout_written=False
    try:
        temp.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
        if layout.read_bytes()!=old_bytes:
            raise RuntimeError('UI changed concurrently; stop')
        shutil.copy2(package,destination);copied=True
        if digest(destination)!=manifest['sha256']:
            raise RuntimeError('Installed ZIP hash mismatch')
        temp.replace(layout)
        layout_written=True
        actual=json.loads(layout.read_text())
        if actual['apps'][:-1]!=old['apps']:
            raise RuntimeError('Existing UI apps changed unexpectedly')
    except Exception:
        if copied and destination.exists():
            destination.rename(backup/'failed-acng-freeroam.zip')
        if temp.exists(): temp.unlink()
        if layout_written: layout.write_bytes(old_bytes)
        raise
    record={'profile':str(user),'backup':str(backup),'installed':str(destination),
            'package_sha256':manifest['sha256'],'source_commit':manifest['source_commit'],
            'layout':str(layout),'existing_apps_preserved':len(old['apps'])}
    (ROOT/'.local/normal-install.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    (backup/'install-record.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(f'Installed verified ZIP; preserved {len(old["apps"])} existing apps. Settings/saves/vehicle configs backed up.')
    print('Backup:',backup)


if __name__=='__main__':
    main()
