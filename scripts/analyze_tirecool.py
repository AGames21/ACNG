"""Summarise a T007 tire heat balance sweep (tests/beamng-tirecool) per HEAT set.

Also reads FR001c (tests/beamng-roadheat) output, whose sets name a core preset.

Usage: python scripts/analyze_tirecool.py <acng-tirecool-test.json or acng-roadheat-test.json> [out.json]
"""
import json
import sys


def summarise(s):
    samples = [x for x in s['samples'] if x.get('w')]
    drive = [x for x in samples if x['phase'] in ('corner', 'straight', 'brake')]
    if not drive:
        return {'name': s['name'], 'error': 'no samples'}
    names = list(drive[0]['w'].keys())
    hot = max(names, key=lambda n: max(x['w'][n]['s'] for x in drive))
    first = drive[0]['w'][hot]['psi']
    cycles = sorted({x['cycle'] for x in drive})
    per = []
    for c in cycles:
        cs = [x for x in drive if x['cycle'] == c]
        corner = [x['w'][hot]['s'] for x in cs if x['phase'] == 'corner']
        straight = [x for x in cs if x['phase'] == 'straight']
        row = {'cycle': c, 'corner_peak_c': round(max(corner), 1) if corner else None,
               'core_end_c': round(cs[-1]['w'][hot]['c'], 1)}
        if straight:
            row['straight_start_c'] = round(straight[0]['w'][hot]['s'], 1)
            row['straight_end_c'] = round(straight[-1]['w'][hot]['s'], 1)
            row['straight_mean_speed_m_s'] = round(sum(x['speed'] for x in straight) / len(straight), 1)
        per.append(row)
    full = [r for r in per if r.get('straight_end_c') is not None]
    last = [x for x in drive if x['cycle'] >= cycles[-1] - 1]
    park = [x for x in samples if x['phase'] == 'idle' and x is not samples[0]]
    end = drive[-1]['w'][hot]
    out = {
        'name': s['name'], 'heat': s.get('heat'), 'profile': drive[-1].get('profile'),
        'applied_friction': drive[-1].get('friction'),
        'hot_tire': hot,
        'cycles': per,
        'peak_c': round(max(x['w'][hot]['s'] for x in drive), 1),
        'last_two_cycles_mean_hot_c': round(sum(x['w'][hot]['s'] for x in last) / len(last), 1),
        'last_two_cycles_mean_all_c': round(sum(sum(x['w'][n]['s'] for n in names) / len(names) for x in last) / len(last), 1),
        'peak_climb_last_cycle_k': round(per[-1]['corner_peak_c'] - per[-2]['corner_peak_c'], 1) if len(per) > 1 else None,
        'straight_drop_mean_k': round(sum(r['straight_start_c'] - r['straight_end_c'] for r in full[1:]) / max(1, len(full) - 1), 1) if full else None,
        'core_end_c': round(end['c'], 1),
        'psi_rise_hot': round(end['psi'] - first, 1) if end.get('psi') is not None and first is not None else None,
    }
    if park:
        out['park_start_c'] = round(drive[-1]['w'][hot]['s'], 1)
        out['park_end_c'] = round(park[-1]['w'][hot]['s'], 1)
        out['park_core_end_c'] = round(park[-1]['w'][hot]['c'], 1)
    return out


def main():
    data = json.load(open(sys.argv[1]))
    rows = [summarise(s) for s in data['sets']]
    for r in rows:
        print(r['name'], 'friction', r.get('applied_friction'), 'hot', r.get('hot_tire'))
        for c in r.get('cycles', []):
            print('   ', c)
        print('   peak', r.get('peak_c'), 'mean last2 hot', r.get('last_two_cycles_mean_hot_c'),
              'all', r.get('last_two_cycles_mean_all_c'), 'climb', r.get('peak_climb_last_cycle_k'),
              'straight drop', r.get('straight_drop_mean_k'), 'core', r.get('core_end_c'),
              'psi+', r.get('psi_rise_hot'), 'park', r.get('park_start_c'), '->', r.get('park_end_c'))
    print('checks', data.get('checks'), 'completed', data.get('completed'))
    if len(sys.argv) > 2:
        json.dump({'schema_version': 1, 'test': data.get('test'), 'cycle': data.get('cycle'),
                   'checks': data.get('checks'), 'completed': data.get('completed'), 'summary': rows},
                  open(sys.argv[2], 'w'), indent=1)


if __name__ == '__main__':
    main()
