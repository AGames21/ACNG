"""Read-only scan of reachable Git blobs before authorized repository upload.

Reports paths/object hashes, never matched credential values. This is a targeted
check, not a guarantee that a repository contains no private information.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECRETS = re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-proj-[A-Za-z0-9_-]{30,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)')
FORBIDDEN = {'.exe', '.dll', '.kn5', '.acd', '.bank', '.dds', '.jar', '.pdb'}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    errors = []
    paths = git('ls-files', '-z').decode().split('\0')
    for path in filter(None, paths):
        if Path(path).suffix.lower() in FORBIDDEN or path.startswith(('.local/', '.venv/', 'work/', 'dist/')):
            errors.append(f'Forbidden tracked path: {path}')
        if SECRETS.search((ROOT / path).read_bytes()):
            errors.append(f'Credential pattern in working file: {path}')
    objects = [line.split(b' ', 1)[0] for line in git('rev-list', '--objects', '--all').splitlines()]
    output = subprocess.check_output(['git', 'cat-file', '--batch'], input=b'\n'.join(objects)+b'\n', cwd=ROOT)
    pos = blobs = 0
    while pos < len(output):
        end = output.index(b'\n', pos)
        oid, kind, size = output[pos:end].split(b' ')
        size = int(size);pos = end + 1
        body = output[pos:pos+size];pos += size+1
        if kind == b'blob':
            blobs += 1
            if SECRETS.search(body):
                errors.append(f'Credential pattern in history blob: {oid.decode()}')
    print(f'Checked {len(list(filter(None, paths)))} tracked files and {blobs} historical blobs.')
    for error in errors:
        print(error)
    print('FAIL' if errors else 'PASS: no prohibited current paths or known credential patterns found.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
