"""Validate the D001 native collision/puncture/wheel-break/reset trace."""
import argparse
import hashlib
import json
from pathlib import Path
from statistics import median


def report(events, samples, receiver):
    snapshots = {s['label']: s for s in events['snapshots']}
    required = ['baseline', 'post_collision', 'after_repair', 'after_puncture',
                'after_wheel_break', 'final_repaired']
    if any(label not in snapshots for label in required):
        raise ValueError('Missing acknowledged damage snapshot')
    wheels = lambda label: {w['name']: w for w in snapshots[label]['wheels']}
    clean = lambda label: snapshots[label]['damage_native'] == 0 and not any(
        w['broken'] or w['deflated'] for w in wheels(label).values())
    damaged = snapshots['post_collision']
    identity = {(s['capture_id'], s['vehicle_id'], s['vehicle_model']) for s in samples}
    generation = sorted({s['generation'] for s in samples})
    broken = [s for s in samples if any(w['name'] == 'FL' and w['broken']
                                       for w in s['wheels'])]
    broken_duration = (broken[-1]['sim_time_s'] - broken[0]['sim_time_s']) if broken else 0
    punctured = [s for s in samples if any(w['name'] == 'FL' and w['deflated'] and not w['broken']
                                         for w in s['wheels'])]
    pressures = [w['tire_pressure_absolute_pa'] for s in punctured for w in s['wheels']
                 if w['name'] == 'FL' and 'tire_pressure_absolute_pa' in w]
    initial = [w['tire_pressure_absolute_pa'] for s in samples if s['generation'] == generation[0]
               for w in s['wheels'] if w['name'] == 'FL' and 'tire_pressure_absolute_pa' in w]
    pressure_ratio = min(pressures) / median(initial) if pressures and initial else None
    checks = {
        'completed': events['completed'],
        'native_collision_damage': damaged['damage_native'] > 0 and bool(damaged['deform_groups']),
        'baseline_clean': clean('baseline'),
        'collision_repair_clean': clean('after_repair'),
        'native_puncture': wheels('after_puncture')['FL']['deflated'],
        'acknowledged_broken_wheel': wheels('after_wheel_break')['FL']['broken'],
        'broken_wheel_telemetry_persists': broken_duration >= 7,
        # Native setGroupPressure changes the initial state; subsequent volume
        # deformation need not keep measured pressure at a fixed atmosphere.
        'puncture_pressure_drops_by_half': pressure_ratio is not None and pressure_ratio < 0.5,
        'final_repair_clean': clean('final_repaired'),
        'three_reset_generations': len(generation) == 3,
        'one_vehicle_capture': len(identity) == 1,
        'passive_observer': all(e['acng']['physics_writes'] == 0 for e in events['events']),
        'master_off_after_test': not events['events'][-1]['acng']['enabled'],
        'receiver_no_reported_loss': receiver['accepted'] == len(samples) and all(
            receiver[k] == 0 for k in ['malformed', 'sequence_gaps', 'out_of_order']),
    }
    return {'test': 'D001', 'passed': all(checks.values()), 'checks': checks,
            'packets': len(samples), 'generations': generation,
            'peak_speed_m_s': events['peak_speed_m_s'],
            'collision_damage_native': damaged['damage_native'],
            'collision_deform_groups': list(damaged['deform_groups']),
            'broken_wheel_duration_sim_s': broken_duration,
            'punctured_fl_pressure_absolute_pa_range': [min(pressures), max(pressures)] if pressures else None,
            'minimum_punctured_to_initial_fl_pressure_ratio': pressure_ratio,
            'limits': 'Tests native stock damage with a passive observer; does not validate future tire forces, bent alignment, AI or detached-wheel dynamics.'}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('events', type=Path)
    p.add_argument('telemetry', type=Path)
    p.add_argument('receiver', type=Path)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    result = report(json.loads(a.events.read_text()),
                    [json.loads(line) for line in a.telemetry.read_text().splitlines()],
                    json.loads(a.receiver.read_text()))
    result['evidence_sha256'] = {str(f.name): hashlib.sha256(f.read_bytes()).hexdigest()
                                 for f in [a.events, a.telemetry, a.receiver]}
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
