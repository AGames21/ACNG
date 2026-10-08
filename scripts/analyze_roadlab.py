"""Summarize FR001 without claiming real-road or AC equivalence."""
import argparse
import json
import math
from pathlib import Path


def summarize(data):
    rows = []
    for case in data.get('sets', []):
        samples = case.get('samples', [])
        first = next((s for s in samples if s.get('w')), None)
        if not first:
            raise ValueError(f"No tire samples: {case['name']}")
        tires = {}
        for name, initial in first['w'].items():
            readings = [s['w'][name] for s in samples if name in s.get('w', {})]
            pressure = [r['psi'] for r in readings if isinstance(r.get('psi'), (int, float)) and math.isfinite(r['psi'])]
            tires[name] = {
                'peak_surface_c': max(r['s'] for r in readings),
                'peak_core_c': max(r['c'] for r in readings),
                'pressure_rise_psi': max(pressure) - initial['psi'] if pressure and initial.get('psi') is not None else None,
                'last_surface_c': readings[-1]['s'],
            }
        stages = {}
        for stage in ('idle', 'cruise', 'corner', 'cruise_after', 'park'):
            values = [s['speed'] for s in samples if s['stage'] == stage and isinstance(s.get('speed'), (int, float))]
            stages[stage] = {'samples': len(values), 'mean_speed_m_s': sum(values) / len(values) if values else None}
        rows.append({'name': case['name'], 'samples': len(samples), 'tires': tires, 'stages': stages})
    return {'schema_version': 1, 'test': data.get('test'), 'completed': data.get('completed', False),
            'checks': data.get('checks', {}), 'summary': rows,
            'limits': ['Controlled flat-map proxy, not a real city/twisty route.',
                       'One ETK configuration; road compound constants remain hypotheses.',
                       'No physical-wheel feel or full AC calibration measured.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = summarize(json.loads(args.input.read_text(encoding='utf-8-sig')))
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    for case in result['summary']:
        print(case['name'], 'samples', case['samples'],
              'peak C', round(max(x['peak_surface_c'] for x in case['tires'].values()), 2),
              'max rise psi', round(max(x['pressure_rise_psi'] for x in case['tires'].values() if x['pressure_rise_psi'] is not None), 2))
    print('completed', result['completed'], 'checks', result['checks'])


if __name__ == '__main__':
    main()
