"""Analyze an explicitly delimited straight-line run; no fabricated benchmarks."""
import argparse
import csv
import json
import math
from pathlib import Path

MPH_TO_MS = 0.44704


def crossing(rows, speed, descending=False):
    for a, b in zip(rows, rows[1:]):
        va, vb = a["speed_m_s"], b["speed_m_s"]
        crossed = va > speed >= vb if descending else va < speed <= vb
        if crossed and vb != va:
            fraction = (speed - va) / (vb - va)
            return a["sim_time_s"] + fraction * (b["sim_time_s"] - a["sim_time_s"])
    return None


def analyze(rows, mode, target_mph):
    if len(rows) < 2:
        raise ValueError("At least two samples required")
    identity = {(r.get("capture_id"), r.get("vehicle_id"), r.get("generation")) for r in rows}
    if len(identity) != 1:
        raise ValueError("Split runs at capture restarts, vehicle changes or resets")
    for a, b in zip(rows, rows[1:]):
        if not b["sim_time_s"] > a["sim_time_s"]:
            raise ValueError("Non-monotonic simulation time")
    if any(not math.isfinite(r["speed_m_s"]) or r["speed_m_s"] < 0 for r in rows):
        raise ValueError("Invalid speed")
    target = target_mph * MPH_TO_MS
    if mode == "acceleration":
        # Start at first movement crossing, with a separate rollout threshold reported.
        start = crossing(rows, 0.1)
        end = crossing(rows, target)
    else:
        start = crossing(rows, target, True)
        end = crossing(rows, 0.1, True)
    if start is None or end is None or end <= start:
        raise ValueError("Required start/end crossings absent")
    distance = 0.0
    for a, b in zip(rows, rows[1:]):
        ta, tb = a["sim_time_s"], b["sim_time_s"]
        lo, hi = max(ta, start), min(tb, end)
        if hi <= lo:
            continue
        def speed_at(t):
            return a["speed_m_s"] + (b["speed_m_s"] - a["speed_m_s"]) * (t - ta) / (tb - ta)
        distance += (speed_at(lo) + speed_at(hi)) * (hi - lo) / 2
    return {"mode": mode, "target_mph": target_mph, "start_time_s": start,
            "end_time_s": end, "elapsed_s": end - start, "distance_m": distance,
            "rollout_or_stop_threshold_m_s": 0.1, "samples": len(rows),
            "max_sample_gap_s": max(b["sim_time_s"]-a["sim_time_s"] for a,b in zip(rows,rows[1:])),
            "distance_method": "trapezoidal speed integral; actual road path not verified"}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("input", type=Path)
    p.add_argument("--mode", choices=["acceleration", "braking"], required=True)
    p.add_argument("--target-mph", type=float, choices=[60, 100], default=60)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    rows = [json.loads(line) for line in a.input.read_text(encoding="utf-8").splitlines() if line.strip()]
    result = analyze(rows, a.mode, a.target_mph)
    a.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    with a.output.with_suffix(".csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["sim_time_s", "speed_m_s", "throttle", "brake", "rpm", "gear"])
        writer.writeheader()
        writer.writerows({k:r.get(k) for k in writer.fieldnames} for r in rows)
    print(json.dumps(result, indent=2))
