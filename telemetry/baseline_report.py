"""Summarize delimited repeated BeamNG runs, preserving quality limitations."""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import statistics

from telemetry.analyze import analyze,MPH_TO_MS


def maneuver_windows(samples):
    # This is the explicit B002 protocol, not a generic maneuver classifier.
    # Warm-up can contain a falling/stopping vehicle before the actual launch.
    launch=next((i for i,r in enumerate(samples) if r.get('throttle',0)>0.8),None)
    high=next((i for i,r in enumerate(samples) if launch is not None and i>=launch and r['speed_m_s']>100*MPH_TO_MS),None)
    brake=next((i for i,r in enumerate(samples) if high is not None and i>=high
        and r.get('brake',0)>0.05 and r.get('throttle',0)<0.1),None)
    if launch is None or high is None or brake is None:
        raise ValueError('B002 launch/high-speed/braking control boundaries absent')
    return samples[max(0,launch-1):brake+1],samples[max(0,brake-1):],{
        'launch_first_full_throttle_s':samples[launch]['sim_time_s'],
        'brake_first_pedal_s':samples[brake]['sim_time_s'],
        'method':'B002 recorded full-throttle launch and brake after exceeding100mph; include preceding samples for crossing interpolation'}


def report(rows,events):
    if not events.get('completed') or len(events.get('runs',[]))!=events.get('requested_runs'):
        raise ValueError('Harness has not completed all requested runs')
    groups=collections.defaultdict(list)
    for row in rows:groups[row.get('capture_id')].append(row)
    runs=[]
    for run in events['runs']:
        capture=run.get('capture_id')
        if not capture or capture not in groups:raise ValueError('Completed run has no matching capture')
        samples=groups[capture]
        if {r.get('vehicle_model') for r in samples}!={events['model']}:
            raise ValueError('Unexpected vehicle model')
        if any(w.get('broken') or w.get('deflated') for r in samples for w in r.get('wheels',[])):
            raise ValueError('Damaged vehicle is not a stock handling baseline')
        metrics={}
        acceleration,braking,window= maneuver_windows(samples)
        for mode in ('acceleration','braking'):
            selected=acceleration if mode=='acceleration' else braking
            for speed in (60,100):metrics[f'{0 if mode=="acceleration" else speed}-{speed if mode=="acceleration" else 0}']=analyze(selected,mode,speed)
        origin=samples[0]['position_m']
        motion=[r for r in samples if r['speed_m_s']>5]
        cosines=[]
        for r in motion:
            f=r.get('forward_world_native')
            if f:cosines.append(sum(x*y for x,y in zip(f,r['velocity_world_m_s']))/r['speed_m_s'])
        final=samples[-1]
        runs.append({'run':run['run'],'capture_id':capture,'samples':len(samples),'metrics':metrics,
            'maneuver_windows':window,
            'initial_position_m':origin,'final_position_m':final['position_m'],
            'final_rpm':final.get('rpm'),'final_gear':final.get('gear'),
            'moving_velocity_forward_median_cosine':statistics.median(cosines) if cosines else None,
            'position_axis_spans_m':[max(r['position_m'][i] for r in samples)-min(r['position_m'][i] for r in samples) for i in range(3)],
            'maximum_abs_steering_input':max(abs(r.get('steering_input') or 0) for r in samples)})
    aggregate={}
    for name in ('0-60','0-100','60-0','100-0'):
        aggregate[name]={}
        for value in ('elapsed_s','distance_m'):
            values=[r['metrics'][name][value] for r in runs]
            aggregate[name][value]={'median':statistics.median(values),'min':min(values),
                'max':max(values),'range':max(values)-min(values),'sample_stddev':statistics.stdev(values) if len(values)>1 else 0}
    start_spread=[max(r['initial_position_m'][i] for r in runs)-min(r['initial_position_m'][i] for r in runs) for i in range(3)]
    return {'test':events['test'],'runs':runs,'aggregate':aggregate,
        'initial_position_spread_m':start_spread,'identical_start_gate_passed':max(start_spread)<0.05,
        'controls':events['controls'],'assists':events['assists'],'spawn':events['spawn'],
        'limitations':['factory assists and automatic acceleration shifts are part of this control protocol',
          'speed-integral distance; physical road-path equivalence not proved',
          'native yaw/acceleration/pressure/slip semantics still need calibration',
          'published UI mass is not verified running mass','not an Assetto Corsa comparison']}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('raw',type=Path)
    p.add_argument('events',type=Path)
    p.add_argument('--output',required=True,type=Path)
    a=p.parse_args()
    receiver=a.raw.with_suffix('.summary.json')
    if not receiver.is_file():p.error('Receiver is still running or its summary is missing; wait for completion')
    counts=json.loads(receiver.read_text())
    if any(counts[k] for k in ('malformed','sequence_gaps','out_of_order')):
        p.error('Receiver quality counters are nonzero; investigate before reporting a valid repeat set')
    rows=[json.loads(line) for line in a.raw.read_text().splitlines()]
    result=report(rows,json.loads(a.events.read_text(encoding='utf-8-sig')))
    if not result['identical_start_gate_passed']:
        p.error('Initial positions differ by more than0.05m; repeat set is provisional, not an identical-start baseline')
    result.update(raw_sha256=hashlib.sha256(a.raw.read_bytes()).hexdigest(),receiver=counts)
    with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2)
    print(json.dumps(result['aggregate'],indent=2))
