"""Explicitly authorized: switch the normal freeroam layout to the minimal ACNG HUD.

Removes the stock speed/boost/powertrain/drag widgets and the ACNG racing HUD, and
moves the ACNG pill and tire tiles out of the way. Every other app is kept as is.
"""
import argparse
import csv
import datetime
import io
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REMOVE={'tacho2','forcedInduction','simplePowertrainControl','dragRace','acngRacingHud'}
PLACE={'acngControl':{'right':'24px','top':'70px','width':'150px','height':'32px','position':'absolute'},
       'acngTires':{'right':'16px','bottom':'16px','width':'210px','height':'130px','position':'absolute'}}


def minimal_layout(data):
    """Return a copy of a uilayout with the clutter removed and the ACNG apps placed."""
    out=json.loads(json.dumps(data))
    apps=[a for a in out['apps'] if a.get('appName') not in REMOVE]
    names={a.get('appName') for a in apps}
    for app in apps:
        if app.get('appName') in PLACE:
            app['placement']=dict(PLACE[app['appName']])
    for name in ('acngControl','acngTires'):
        if name not in names:
            apps.append({'appName':name,'placement':dict(PLACE[name])})
    out['apps']=apps
    return out


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
    if user!=expected:
        raise RuntimeError('Registered normal profile identity not verified')
    layout=user/'settings/ui_apps/layouts/default/freeroam.uilayout.json'
    old_bytes=layout.read_bytes()
    new=minimal_layout(json.loads(old_bytes))
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=Path(paths['lab_user']).parents[1]/('ACNG-layout-backup-'+stamp)
    backup.mkdir()
    shutil.copy2(layout,backup/layout.name)
    temp=layout.with_suffix('.acng-pending')
    temp.write_text(json.dumps(new,indent=2)+'\n',encoding='utf-8')
    if layout.read_bytes()!=old_bytes:
        temp.unlink()
        raise RuntimeError('Layout changed concurrently; stop')
    temp.replace(layout)
    kept=[a['appName'] for a in new['apps']]
    print('Minimal HUD layout applied. Apps now:',', '.join(kept))
    print('Restore by copying back:',backup/layout.name)


if __name__=='__main__':
    main()
