"""Build/install ONLY ACNG's own mod. Existing deployment is backed up first."""
import argparse
import hashlib
import json
import shutil
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def deploy(user):
    user = Path(user).resolve()
    target = user / "mods" / "unpacked" / "acng"
    if ROOT in user.parents or user == ROOT:
        raise ValueError("Game user folder must be outside source repository")
    if target.is_symlink() or target.is_junction():
        raise ValueError("Refusing linked deployment target")
    if target.exists():
        if not (target / ".acng-owned.json").is_file():
            raise ValueError("Refusing to overwrite an unowned directory")
        backup = ROOT / ".local" / "backups" / str(time.time_ns())
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(target, backup)
    target.mkdir(parents=True, exist_ok=True)
    hashes = {}
    # Merge copies: never recursively delete anything in the user's profile.
    for src in (ROOT / "beamng-mod").rglob("*"):
        if src.is_file():
            relative = src.relative_to(ROOT / "beamng-mod")
            dst = target / relative
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            hashes[relative.as_posix()] = hashlib.sha256(src.read_bytes()).hexdigest()
    (target / ".acng-owned.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8")
    return target


def package():
    destination = ROOT / "dist" / "acng-foundation.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as z:
        for src in sorted((ROOT / "beamng-mod").rglob("*")):
            if src.is_file():
                z.write(src, src.relative_to(ROOT / "beamng-mod").as_posix())
    return destination


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--user", type=Path)
    p.add_argument("--package", action="store_true")
    a = p.parse_args()
    if a.user:
        print(deploy(a.user))
    if a.package:
        print(package())
    if not a.user and not a.package:
        p.error("Specify --user or --package")
