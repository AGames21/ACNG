# FR001c sustained tire heat and pressure: OFF, Road, Sport

The run's raw lab file calls it FR003; renumbered to fit the FR001 (heat) and FR002 (damage) series in TESTING.md, which keeps FR003 for the physical wheel.

Setup:
- 2026-10-08, BeamNG 0.39.4, Small Grid, ETK K-Series `kc6_360_M`
- a fresh isolated lab profile, master OFF at start (checked), Road the default preset (checked)
- harness `tests/beamng-roadheat` (GE extension `acng_roadheat`)

Each set picks its preset through the real `acng_core` switch, then resets the car for fresh 15 C tires. It then drives 16 T007 lap-like cycles: a 20 s limit corner (steer 0.5 at 10 m/s), a 15 s straight at about 31 m/s, and braking to 12 m/s. That is about 11 minutes of hard driving, followed by 60 s parked. Every tire is sampled once a second (about 650 samples per set). OFF means master ON with ACNG tires off, so it shows what native BeamNG does to pressure on its own.

## Hottest tire (front left, the outside front)
| Set | Corner peak, cycle 1 | Corner peak, cycles 2-16 | End of straight | Core at end | Pressure rise | After 60 s parked |
|---|---:|---:|---:|---:|---:|---:|
| OFF (native) | 15.0 C | 15.0 C | 15.0 C | 15.0 C | +0.4 psi max | 15.0 C |
| **Road** | 43 C | **50 C, flat** | 24-26 C | 25.7 C | **+1.7 psi** | 22 C surface, 26 C core |
| Sport | 72 C | 87 C, then 105 C by cycle 14 | 33-43 C | 76.4 C | +8.5 psi | 36 C surface, 73 C core |

All four tires, largest pressure rise: Road FL +1.71, RL +0.98, FR +0.62, RR +0.57 psi. Sport FL +8.45, RL +4.52, FR +4.11, RR +2.54 psi.

## What this shows
- **Road no longer builds heat.** From cycle 2 to 16 the corner peak stays at 50 C (cycle-to-cycle change under 0.5 K). Each straight cools the surface by about 25 K, back below the 35 C window floor, which costs only the Road preset's 2% cold-grip penalty. The core still creeps up (15.6 to 25.7 C, slowing from 0.8 to 0.3 K per cycle), so pressure keeps rising a little in a very long session, but it was still only +1.7 psi after 11 minutes at the limit.
- **The old +7.8 psi problem is gone on Road.** Sport, which keeps the previous T007 setup, still reaches +8.5 psi and a 76 C core, matching T007b. Sport stays the optional track preset.
- **Native BeamNG alone moves pressure by at most 0.4 psi** in this drive, so nearly all of the Road and Sport rise comes from tire heat.
- Parked for 60 s, the Road surface returns close to ambient. The Road core is 11 K above ambient. The Sport core stays hot (73 C).
- No ACNG errors in the lab log. Turning the feature off made core report no physics writes.

## Limits
- One car, one flat map, one scripted cycle. There was no city traffic, cruising or winding-road playtest, and no other vehicle or tire size.
- The cycle is harder than normal road driving (11 minutes at the grip limit). Real road temperatures should sit lower than these numbers.
- Neither preset is a measured real-compound model. Road is a gentle engineering preset; this test only shows that it settles and keeps pressure in a sensible range.

Machine-readable summary: `FR001c-sustained-heat.json`. Raw samples stay in the ignored lab profile. Re-run with `scripts/launch-lab.ps1 -Experiment RoadHeat -LabUser <fresh>/ACNG-roadheat-NNN/current`, then `python scripts/analyze_tirecool.py <profile>/acng-roadheat-test.json`.
