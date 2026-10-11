# T009 AC-style tire model

Why: the user asked for AC's tire behaviour, not just "hotter means less grip". ACNG's model is original code shaped after what the public Kunos SDK `tyres.ini` exposes: zone temperatures across the tread, a pressure window, graining, blistering, dirt pickup and scrub-in wear. No AC binary was decompiled and no reverse-engineering tool was used (AGENTS.md; public MIT repository).

## T009a: native structure probe
Harness `tests/beamng-tireprobe` (GE extension `acng_tireprobe`), `-Experiment TireProbe`, fresh isolated lab profile, stock ETK K-Series `kc6_360_M` on Small Grid, BeamNG 0.39.4, ambient 15 C. Summary: `t009a-tireprobe.json` (the raw file stays outside Git).

Structure:
- Every wheel has 32 tread nodes on the two tread edges only: 16 at about -0.066 m and 16 at about +0.154 m from the hub midpoint. There is no middle row, so the model reads inner and outer edges and uses the wheel average for the middle.
- Raw tread node temperatures run far above `getWheelAvgTemperature` (99 C edge vs 53 C average after a launch) and cool faster, so zone temperatures are anchored on the average: zone = average + (zone mean - tread mean).
- Tuning variables `$tirepressure_F` 30 and `$tirepressure_R` 28 psi (defaults), `$camber_FR` and `$camber_RR`; jbeam `pressurePSI` matches. Measured cold pressure at 15 C was 28.4 / 26.6 psi.

Native rolling (strain) heat, right wheels probed, left wheels at strain 0 as control, 45 s at 25 m/s:

| Strain | FR minus FL at the end |
|---:|---:|
| 0.001 | 0.00 C |
| 0.01 | 0.01 C |
| 0.1 | 0.09 C |
| 1 | 0.95 C |

- Strain heat is roughly linear in the coefficient and small: strain 1 settles near +1 C. Road-appropriate rolling warm-up would need strain of order 10 to 25. That is not measured, so ACNG keeps strain 0 until a follow-up probe.
- The rear tires heated from launch wheelspin, not from strain.
- Left tires 8 psi low (RL 19.3, FL 20.9 psi) ran slightly hotter after the launch (RL 52.1 vs RR 49.8 C).

Circle (steer 0.5 at 10 m/s, 60 s), after 60 s:

| Tire | Average | Inner edge | Outer edge |
|---|---:|---:|---:|
| FL (hot, loaded) | 117 C | 215 C | 221 C |
| FR | 39 C | 56 C | 69 C |
| RL | 65 C | 138 C | 91 C |
| RR | 37 C | 64 C | 52 C |

- Native node temperatures do split across the tread in a corner, so zone grip has a real signal to read. The driven rears show a hot inner edge (negative camber plus wheelspin).

## Status
T009b passed 28/28 in game on 2026-10-10 and the model is installed behind `tire_temperature` (OFF by default). The ideal hot pressure is the car's cold tuning pressure warmed to each compound's `idealCore` (Road 30, Sport 60, Race 75 C), the core temperature native pressure follows; run 1 of T009b showed the old mid-window ideal was unreachable. See [T009b](T009b-tirephys.md). Dirt and rolling strain heat are not covered in game yet.
