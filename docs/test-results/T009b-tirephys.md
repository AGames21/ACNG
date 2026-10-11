# T009b AC-style tire model lab (TirePhys)

Harness `tests/beamng-tirephys` (GE extension `acng_tirephys`), `-Experiment TirePhys`, each run in a fresh isolated lab profile. Stock ETK K-Series `kc6_360_M` on Small Grid, BeamNG 0.39.4, ambient 15 C. The harness turns the master and `tire_temperature` on through `acng_core` and reads the model's own state per wheel from the vehicle VM. Summary: `t009b-tirephys.json`; the raw files stay outside Git.

## Sequence
1. Spawn with the master OFF. Drive a 20 s circle (steer 0.5, 10 m/s) as the OFF baseline.
2. Heat ON. Sample each profile (auto, road, race, sport) at rest.
3. Reset, then lower the left side by 8 psi and sample.
4. Reset. Drive a 60 s circle, then 40 s straight at 20 m/s, then stop.
5. Reset and sample. Deflate RR and drive a 15 s circle on it.
6. Reset, then time 1200 model updates at rest.
7. Master OFF. Drive the 20 s circle again.

## Results
Run 1 (old ideal pressure): 25/28. Run 2 (installed model): **28/28**, no helper errors, no ACNG errors in the lab log.

| Check | Run 2 |
|---|---|
| Master and tires OFF by default; OFF temperatures flat (0.002 K) | pass |
| 16 / 0 / 16 tread nodes per wheel (inner / middle / outer) | pass |
| Heat grip is the mean zone grip; grip written is heat x pressure x damage (worst error 0.002, 128 samples) | pass |
| Ideal pressure per profile matches the formula | pass |
| Left side 8 psi low: pressure grip 0.925 vs 0.961 (front) | pass |
| Circle splits the zones by up to 48 C | pass |
| Cooked FL (zones 114-118 C) loses heat grip (0.958) | pass |
| Cold sliding grains (FR 0.236); hot sliding blisters (FL 0.006) | pass |
| Grain cleans in the window (FL 0.157 to 0 over 15 s at 87-101 C) | pass |
| Blisters persist; reset gives clean tires | pass |
| Deflated tire skipped (grain and blister frozen at 1.9 psi) | pass |
| Model grip lowers circle lateral (9.01 vs 9.35 m/s2 OFF) | pass |
| 0.008 ms per update, no damage at rest | pass |
| OFF again: tires unloaded, temperatures flat, lateral 9.351 vs 9.349 (within 2%) | pass |

## Run 1 finding: unreachable ideal pressure
The first model set the ideal hot pressure to the cold tuning pressure warmed to the middle of the grip window (Sport 90 C, Race 90 C). Native pressure follows the slow core temperature, not the surface: FR001c measured the core at 26 C on Road and 76 C on Sport after 11 minutes at the limit, and this circle reached only +2.7 psi with a 117 C surface. So the ideal was never reached and pressure was a permanent penalty: 0.94 Sport and 0.89 Race cold, still 0.95 on the cooked FL.

The fix gives each compound an `idealCore` (Road 30, Sport 60, Race 75 C) that its core can reach in long road driving. The ideal is the cold tuning pressure warmed to that core.

| FL at rest, 28.4 psi | Run 1 ideal | Pressure grip | Run 2 ideal | Pressure grip | Grip run 2 |
|---|---:|---:|---:|---:|---:|
| Road | 35.3 | 0.979 | 31.5 | 0.991 | 0.971 |
| Sport | 40.7 | 0.939 | 36.1 | 0.961 | 0.817 |
| Race | 42.2 | 0.890 | 38.4 | 0.920 | 0.644 |

Cold slicks stay slow because of their grip window, not their pressure. Hot FL pressure grip after the circle went from 0.952 to 0.975.

Run 1 also had three harness faults, fixed before run 2. Replaying the fixed checks on run 1's data passes all three.
- Grain cleaning was judged at the braking stop after the straight. Locking cold tires grains them, which is correct. The check now looks for any drop between driving samples.
- Reset expected exactly 0 grain. The car settles for a second after a reset (1e-6), so the limit is now 1e-4.
- The flat tire was compared with 0. It now has to stay unchanged from the moment it deflated.

## Not covered
- Dirt: Small Grid is all tarmac (material 10). Dirt pickup is unit-tested only.
- Rolling strain heat stays 0 until a probe at strain 10 to 25.
- Real roads and other cars: the next FR001 run.
