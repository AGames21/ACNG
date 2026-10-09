# C005 - BMW 1M handling calibration

2026-10-08. **Preparation only: native baseline blocked by an open normal BeamNG
session. No handling tune, new in-game pass or before/after improvement claimed.**

## Reference evidence

Read the owner's installed stock BMW 1M data archive locally using external
[acd.py 1.0.0](https://github.com/philippkosarev/acd.py). Original archive and local
unpacked configuration remain outside Git. Only selected numerical findings are
recorded here; no AC implementation or configuration files are redistributed.
Archive SHA256: `9b9e870010e459116dd76a5e10eeb0cb0e78d78f4173d7caaea9c85c3bd638d9`.

| Quantity | AC local reference | Current conversion evidence |
|---|---|---|
| Advertised output | UI 340 bhp / 500 Nm | C004 ~249 kW / ~507 Nm |
| Mass | UI 1,495 kg; physics TOTALMASS 1,570 kg | C004 1,534.7 kg |
| Front weight fraction | 0.5178 (local field comment identifies front share) | Not measured yet |
| Wheelbase | 2.660 m | Geometry stretched; dynamic wheelbase needs measurement |
| Gears 1-6 | 4.110 / 2.315 / 1.542 / 1.179 / 1.000 / 0.846 | Already configured; C004 verifies first/sixth |
| Final drive | 3.154 | C004 native match |
| Tires | Street; 245 mm front / 265 mm rear; static 35 psi | Native Sport 245/35R19, 265/35R19 |
| Lateral reference friction | DY_REF 1.23 both axles; reference loads 3,117 / 3,229 N | No one-to-one mapping to BeamNG friction |
| Springs F/R | 22,760 / 31,500 N/m | Donor beam spring values 33,000 / 28,000 N/m |
| Slow bump/rebound F | 4,023 / 5,003 N·s/m | Donor 6,000 / 9,500 |
| Slow bump/rebound R | 3,900 / 5,303 N·s/m | Donor 4,400 / 7,000 |
| Anti-roll reference F/R | 20,000 / 8,000 | Beam topology has different leverage; raw constants cannot be copied directly |
| Brake front share | 0.70 | Donor peak torque ratio 2,800/(2,800+1,500) ≈0.651; rear input nonlinear |
| Differential power/coast/preload | 0.40 / 0.60 / 10 | Donor native LSD, not calibrated |
| Factory assists | ABS and TC present and active | Native donor defaults in baseline |

The 75 kg AC mass difference is consistent with an occupant allowance, but that
cause is **inferred**, not measured here. Honor the requested 1,495 kg ±3% native
mass requirement. C004 is inside it; do not weaken chassis nodes to match mass.
AC UI 4.9 s acceleration is an advertised figure, not a captured AC benchmark.
DY_REF does not establish vehicle skidpad g; aero, load sensitivity, surface,
temperature and combined slip matter. Suspension motion ratios also differ.

## Repeatable protocol (implemented, awaiting native validation)

`scripts/launch-lab.ps1 -Experiment CarLab -Handling -LabUser
<fresh ACNG-car-0NN/current> -ExtraMod <C004 local car ZIP>`.
The launcher rejects running BeamNG and an existing handling profile. Never
close or operate a player's session. The optional handling module runs before
the unchanged 45 CarLab regression checks; no test harness ships to players.

- Small Grid, default surface/environment, ACNG master OFF; fresh reset and same
  actual settled start for each maneuver. Native factory assists, native arcade
  shift strategy; this measures the controlled proxy, not a human clutch launch.
- Five 0-100 km/h and 100-0 km/h repeats, interpolated crossings, explicit 0.1 m/s
  movement/stop thresholds; native braking and clutch commands. Median/min/max.
- Two fixed steering inputs (0.12/0.25), each at 6/10/14/18/22 m/s. Native throttle
  and brake speed control only. Discard 12 s settling; measure 10 s windows.
- Reject windows with >0.5 m/s speed variation/error, >8 degrees body sideslip,
  insufficient duration, or native damage. Report highest **accepted sampled**
  lateral g, not an exhaustive peak. Raw yaw-speed proxy requires live scrutiny.
- Balance proxy: wheel-axis steer minus atan(wheelbase/radius), fitted against g
  per steering input. Positive gradient indicates understeer, negative oversteer.
  Inspect native wheel-frame validity before accepting these results.
- Raw evidence `/acng-handling-test.json`; summary through
  `python tools/handling_report.py <raw> --output <local summary>`.
- Baseline uses the exact C004 ZIP hash
  `6ec90b2739ea513ce6b033e96ac942367fad458f9e703913977a8dfc59dbe6d8`.

## Before and after

| Metric | C004 before | C005 tuned after |
|---|---|---|
| 0-100 km/h median / range | Pending native baseline | Pending |
| 100-0 km/h distance median / range | Pending native baseline | Pending |
| Maximum accepted steady lateral g | Pending native baseline | Pending |
| Balance gradient deg/g | Pending native baseline | Pending |
| Mass | Previous C004 1,534.7 kg; must remeasure | Pending; limit 1,450.15-1,539.85 kg |
| CarLab damage/visual regression | Previous C004 45/45; not rerun | Pending; require 45/45 |

## Verification and next action

191 Python tests pass, including synthetic crossing-summary rejection and known
understeer/oversteer gradients; all existing Node scripts pass; both CarLab Lua
files compile with LuaJIT. These **do not prove native benchmark behavior**.
Tire compound/heat-limit/GUI production files unchanged; converter tuning has
not started. Close normal BeamNG, claim the lease again, run fresh profile 017,
validate channels/crossings, then tune original converter parameters one change
group at a time and repeat identical tests. Do not deploy an untested tune.
