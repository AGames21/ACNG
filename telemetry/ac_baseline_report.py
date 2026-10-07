"""Control-delimited AC straight-line measurements with explicit clock limits."""
import argparse
import hashlib
import json
import math
from pathlib import Path
from statistics import median
from telemetry.analyze import analyze


def value_at(rows, time, key):
    for a,b in zip(rows,rows[1:]):
        if a['sim_time_s'] <= time <= b['sim_time_s']:
            f=(time-a['sim_time_s'])/(b['sim_time_s']-a['sim_time_s'])
            return a[key]+f*(b[key]-a[key])
    raise ValueError('Crossing outside control window')


def report(samples, session):
    if not samples:raise ValueError('Empty capture')
    if len({(s['ac_version'],s['shared_memory_version'],s['car_model'],s['track']) for s in samples})!=1:
        raise ValueError('Mixed game/vehicle/track identity')
    # Reuse speed integration, naming the actual clock rather than presenting
    # host polling time as the game's physics-step clock.
    rows=[dict(s,sim_time_s=s['host_monotonic_s']) for s in samples]
    launch=next((i for i,s in enumerate(rows) if s['throttle']>0.1 and s['brake']<0.05),None)
    if launch is None:raise ValueError('No recorded acceleration input')
    brake=next((i for i in range(launch+1,len(rows)) if rows[i]['brake']>0.1),None)
    if brake is None:raise ValueError('No recorded braking input')
    if max(s['speed_m_s'] for s in rows[launch:brake]) < 100*0.44704:
        raise ValueError('Required 100mph acceleration crossing missing')
    stop=next((i for i in range(brake+1,len(rows)) if rows[i]['speed_m_s']<0.1),None)
    if stop is None:raise ValueError('Recorded braking did not stop')
    acceleration=rows[max(0,launch-1):brake+1]
    braking=rows[brake-1:stop+1]
    metrics=[]
    for mode,window in [('acceleration',acceleration),('braking',braking)]:
        for mph in [60,100]:
            m=analyze(window,mode,mph)
            m['clock_source']='host_monotonic_s; native lap clock checked separately'
            m['native_throttle_at_start']=value_at(window,m['start_time_s'],'throttle')
            m['native_brake_at_start']=value_at(window,m['start_time_s'],'brake')
            m['full_brake_at_target']=mode!='braking' or m['native_brake_at_start']>=0.95
            metrics.append(m)
    a,b=rows[launch],rows[stop]
    native_elapsed=b['current_lap_time_s']-a['current_lap_time_s']
    host_elapsed=b['sim_time_s']-a['sim_time_s']
    if native_elapsed<=0:raise ValueError('Lap clock reset/stopped during maneuver')
    residual=max(abs((s['current_lap_time_s']-a['current_lap_time_s'])-
                     (s['sim_time_s']-a['sim_time_s'])) for s in rows[launch:stop+1])
    capture=session['capture']
    checks={'recorded_crossings':True,'exact_cfg_restoration':session['config_restored'],
            'expected_sample_count':capture['accepted']==len(rows),
            'no_reported_incoherent_polls':capture['incoherent_poll']==0,
            'lap_clock_ratio_near_real_time':abs(native_elapsed/host_elapsed-1)<0.005,
            'full_brake_at_both_targets':all(m['full_brake_at_target'] for m in metrics)}
    wheel_ranges={}
    for name in ['FL','FR','RL','RR']:
        wheels=[w for s in samples for w in s['wheels'] if w['name']==name]
        wheel_ranges[name]={k:[min(w[k] for w in wheels),max(w[k] for w in wheels)]
                            for k in ['core_temperature_native','pressure_native','wear_native']}
    gaps=[b['sim_time_s']-a['sim_time_s'] for a,b in zip(rows,rows[1:])]
    return {'test':'AC grid straight-line pilot','quality_checks':checks,
            'passes_recorded_quality_checks':all(checks.values()),'repeats':1,
            'matched_cross_game_reference':False,'identity':session['identity'],
            'requested_layout':session['requested_layout'],'packets':len(rows),
            'max_speed_mph':max(s['speed_m_s'] for s in rows)/0.44704,
            'max_native_acceleration_vector_g':max(math.sqrt(sum(v*v for v in s['acceleration_local_g_native'])) for s in rows),
            'sample_gap_median_s':median(gaps),'sample_gap_max_s':max(gaps),
            'lap_to_host_elapsed_ratio':native_elapsed/host_elapsed,'lap_host_max_residual_s':residual,
            'metrics':metrics,'wheel_native_ranges':wheel_ranges,
            'limits':['One repeat; no running setup/mass/fuel/tire/assist match to BeamNG.',
                      'Keyboard native pedal ramps are measured; braking comparisons require full brake at each target.',
                      'Current prefix lacks car damage and layout identity; straight screenshots do not establish every damage channel.',
                      'Distance is a speed integral; graphics/physics pages are not atomic.']}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('raw',type=Path);p.add_argument('session',type=Path)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    r=report([json.loads(x) for x in a.raw.read_text().splitlines()],json.loads(a.session.read_text()))
    r['evidence_sha256']={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [a.raw,a.session]}
    a.output.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(r,indent=2))
