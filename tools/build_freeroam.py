"""Build only committed original player files; omit unfinished track modules."""
import hashlib
import io
import json
import subprocess
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def main():
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    archive=subprocess.check_output(['git','archive','--format=zip',commit,'beamng-mod'],cwd=ROOT)
    target=ROOT/'dist'/'acng-freeroam.zip';target.parent.mkdir(exist_ok=True)
    files=[]
    with zipfile.ZipFile(io.BytesIO(archive)) as src, zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as out:
        for name in src.namelist():
            relative=name.removeprefix('beamng-mod/')
            if name.endswith('/') or relative.endswith('.gitkeep') or relative=='lua/ge/extensions/acng/weekend.lua' or relative.startswith('ui/modules/apps/ACNGWeekend/'):
                continue
            data=src.read(name);out.writestr(relative,data)
            files.append({'path':relative,'sha256':hashlib.sha256(data).hexdigest()})
    with zipfile.ZipFile(target) as check:
        assert check.testzip() is None
        assert 'lua/ge/extensions/acng/core.lua' in check.namelist()
        assert 'ui/modules/apps/ACNGControl/app.js' in check.namelist()
        assert all('weekend' not in name.lower() for name in check.namelist())
    manifest={'source_commit':commit,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'files':files}
    target.with_suffix('.build.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(f'Built {len(files)} committed player files; ZIP integrity passed; source {commit[:7]}.')


if __name__=='__main__':
    main()
