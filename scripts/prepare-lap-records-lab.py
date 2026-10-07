"""Prepare a fresh LR001 profile from committed code. Never launches any process/game."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]

def prepare(parent):
    parent=Path(parent).resolve()
    if any(c.isspace() for c in str(parent)):
        raise ValueError("Use a whitespace-free parent for this BeamNG launch parser")
    commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip()
    # Read committed trees only: another assistant's unfinished edits stay out.
    archives={
        "acng.zip":subprocess.check_output(["git","archive","--format=zip",commit+":beamng-mod"],cwd=ROOT),
        "acng-lap-records-test.zip":subprocess.check_output(["git","archive","--format=zip",commit+":tests/beamng-laprecords"],cwd=ROOT),
    }
    lab=parent/("ACNG-laprecords-"+commit[:10]+"-"+str(time.time_ns()))
    lab.mkdir(parents=True,exist_ok=False)
    current=lab/"current";mods=current/"mods";mods.mkdir(parents=True)
    for name,data in archives.items(): (mods/name).write_bytes(data)
    manifest={"test":"LR001","source_commit":commit,"launched":False,
              "files":{name:hashlib.sha256(data).hexdigest() for name,data in archives.items()},
              "constraint":"Do not launch until user releases uninterrupted Roblox/Chrome use."}
    (current/"acng-lab-manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    (lab/"README.txt").write_text(
        "LR001 isolated test profile. PREPARED ONLY; NEVER AUTO-LAUNCHED.\n"
        "Wait for explicit release of uninterrupted Roblox/Chrome use.\n"
        "After that: launch BeamNG with -userpath pointing at this parent directory, not current.\n"
        "Result: current/acng-lap-records-test.json. completed alone is not a pass; require passed=true.\n"
        "The test drives a stock car, tests archive reload/CLEAR, then stops it.\n"
        "Do not copy the test mod into a normal user profile. Full process restart still needs a separate test.\n",
        encoding="utf-8")
    return current

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent",type=Path,required=True)
    print(prepare(parser.parse_args().parent))
