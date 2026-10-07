"""Read-only ACNG memory health check. Does not rewrite or reorganize notes."""
import json
import re
from pathlib import Path


def check(vault):
    vault=Path(vault)
    root=vault/'ACNG'
    if not (vault/'.obsidian').is_dir():raise ValueError('Existing Obsidian configuration required')
    required=['Current Status.md','Roadmap.md','Architecture.md','Decisions.md',
              'Problems.md','Ideas.md','Testing/Benchmarks.md']
    missing=[name for name in required if not (root/name).is_file()]
    if not any((root/name).is_file() for name in ('ACNG Dashboard.md','Home.md')):
        missing.append('ACNG Dashboard.md or Home.md')
    broken=[]
    notes=list(root.rglob('*.md'))
    for note in notes:
        for target in re.findall(r'\[\[([^\]]+)\]\]',note.read_text(encoding='utf-8')):
            target=target.split('|',1)[0].split('#',1)[0]
            if not target:continue
            if target.startswith('ACNG/'):
                dest=vault/(target+'.md')
                if not dest.is_file():broken.append({'note':str(note.relative_to(root)),'target':target})
    return {'notes':len(notes),'missing_required':missing,'broken_acng_links':broken}


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--vault',type=Path)
    a=p.parse_args()
    if a.vault is None:
        local=Path(__file__).resolve().parents[1]/'.local'/'paths.json'
        a.vault=json.loads(local.read_text(encoding='utf-8-sig'))['obsidian_vault']
    result=check(a.vault)
    print(json.dumps(result,indent=2))
    raise SystemExit(bool(result['missing_required'] or result['broken_acng_links']))
