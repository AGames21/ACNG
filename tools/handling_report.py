"""Summarize original C005 native lab measurements; never infer missing AC results."""
import argparse
import json
import math
import statistics
from pathlib import Path


def distribution(rows, field):
    values = [r[field] for r in rows]
    if len(values) != 5 or any(not math.isfinite(v) or v <= 0 for v in values):
        raise ValueError('Five finite positive straight-line repeats required')
    return {'median': statistics.median(values), 'min': min(values), 'max': max(values), 'n': len(values)}


def summarize(raw, wheelbase=2.660):
    if not raw.get('completed') or not raw.get('checks') or not all(raw['checks'].values()):
        raise ValueError('Incomplete or failed native handling run')
    rows = [r for r in raw['circles'] if r.get('valid_steady')]
    if len(rows) < 3:
        raise ValueError('At least three accepted steady-circle windows required')
    balances = []
    for steer in sorted({r['input'] for r in rows}):
        series = sorted((r for r in rows if r['input'] == steer), key=lambda r: r['lateral_g'])
        if len(series) < 3:
            continue
        xs = [r['lateral_g'] for r in series]
        ys = [math.degrees(r['steer_rad']-math.atan(wheelbase/r['radius_m'])) for r in series]
        mx, my = statistics.mean(xs), statistics.mean(ys)
        variance = sum((x-mx)**2 for x in xs)
        if variance <= 0.01:
            continue
        slope = sum((x-mx)*(y-my) for x, y in zip(xs, ys))/variance
        balances.append({'input': steer, 'gradient_deg_per_g': slope,
                         'classification': 'understeer' if slope > 0.2 else 'oversteer' if slope < -0.2 else 'near neutral',
                         'samples': len(series), 'g_range': [min(xs), max(xs)]})
    return {'schema_version': 1, 'accel_0_100_kmh_s': distribution(raw['acceleration'], 'time_s'),
            'brake_100_0_kmh_m': distribution(raw['braking'], 'distance_m'),
            'max_accepted_steady_lateral_g': max(r['lateral_g'] for r in rows),
            'balance': balances, 'accepted_circles': len(rows), 'rejected_circles': len(raw['circles'])-len(rows),
            'limits': ['0.1 m/s motion/stop threshold', 'Native arcade shift strategy; factory assists',
                       'Maximum accepted sampled window, not exhaustive peak grip',
                       'Balance from wheel steer minus atan(wheelbase/radius); proxy, not subjective feedback']}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('raw', type=Path)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    report = summarize(json.loads(args.raw.read_text()))
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
