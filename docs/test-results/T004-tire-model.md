# T002-T004 tire heat and grip window in game

Setup for every run:
- stock BeamNG ETK K-Series `kc6_360_M` on Small Grid
- BeamNG 0.39.4
- a fresh isolated lab profile per run
- master OFF at start

T002 and T003 were native-API probes. T004 is the end-to-end test of the ACNG tire model (`docs/TIRES.md`).

## T002: what heats a BeamNG tire
Harness `tests/beamng-tires`, raw results `t002a-tire-sweep.json` and `t002b-tire-sweep.json`. One heat source at a time was swept through the native `setThermal`, and the mean tire temperature was measured during a fixed drive and then a park.

| Heat source | Drive rise at 1e-4 | Drive rise at 1e-2 | Drive rise at 1e-1 |
|---|---:|---:|---:|
| friction | 0.05 K | 5.4 K | 56.1 K |
| strain | 0.00 K | 0.00 K | 0.12 K (1.16 K at 1) |
| flashFriction | 0.00 K | 0.00 K | 0.00 K (0.00 K at 1) |

- **Friction heat** is linear in its coefficient, and the stock value is 0, so stock BeamNG cars do not heat their tires at all.
- **Strain heat** barely registers. **flashFriction** does nothing measurable.
- With friction at 0.1, the environment and core couplings shaped the drive rise and the park drop as expected: more cooling meant a smaller rise and a faster drop.

## T003: how the native grip curve behaves
Harness `tests/beamng-grip`, raw results `t003-grip-curve.json`, `t003b-grip-curve-full-lock.json` and `t003c-grip-curve-calibration.json`. The curve's low and high coefficients and temperature limits were set by hand, and steady-state lateral acceleration was measured.

| T003c, 10 m/s, steer 0.5 | Lateral | vs stock |
|---|---:|---:|
| stock | 9.35 m/s2 | 100 % |
| coefMiddle 0.9 | 8.98 m/s2 | 96 % |
| coefMiddle 0.8 | 8.36 m/s2 | 89 % |
| coefMiddle 0.6 | 6.47 m/s2 | 69 % |
| coefLow 0.8, tire just below lowTemp | 8.31-8.34 m/s2 | 89 % |

- The coefficient scales grip almost one to one at the limit.
- **Below lowTemp, grip steps straight to coefLow within a few kelvin, whatever slope is set.** That gives no usable warm-up ramp.
- **Decision:** keep the native curve flat and set the one coefficient per tire from Lua, using ACNG's own ramp.

## T004: the ACNG tire model end to end
Harness `tests/beamng-tiremodel` (GE extension `acng_tiremodel`).

The car holds steer 0.5 at about 10 m/s on a constant-radius circle at the limit, in 5 s windows. The run had these phases:
1. 20 s with the model OFF.
2. Master ON and `setFeature('tire_temperature', true)`, a reset, then 150 s with the model ON.
3. 41 s parked.
4. A deflated front-left tire for 8 s.
5. The feature OFF, a reset, then 20 s OFF again.

Raw results:
- `t004a-tiremodel-harness-bug.json`
- `t004b-tiremodel-friction-0.1.json`
- `t004c-tiremodel.json` (final)

Screenshots: `t004b-tiremodel.png` and `t004c-tiremodel.png` (60 s in, outer front at 124 C and marked HOT).

| T004c (friction heat 0.05) | Lateral | Note |
|---|---:|---|
| OFF | 9.349 m/s2 | stock |
| ON, cold (windows 3-4) | 9.055 m/s2 | tires 25-70 C |
| ON, best (window 5) | 9.19 m/s2 | outer front about 82 C, in the window |
| ON, end (window 30) | 8.49 m/s2 | outer front 143 C, grip 86 % |
| OFF again | 9.350 m/s2 | temperatures back to 15 C |

Per-tire results at the end of the ON drive:

| Tire | Surface | Core | Pressure | Grip |
|---|---:|---:|---:|---:|
| FL (outer front) | 143 C | 101 C | 40.1 psi | 0.86 |
| RL | 72 C | 59 C | 32.3 psi | 0.99 |
| FR | 53 C | 38 C | 31.4 psi | 0.94 |
| RR | 40 C | 36 C | 29.1 psi | 0.91 |

- The correlation between mean grip and lateral acceleration over windows 3-30 is r = 0.94.
- Parked for 40 s, the hottest surface fell from 143 to 87 C and the mean from 77 to 51 C.

Checks (T004c, all 16 true):
1. master OFF by default
2. tire feature OFF by default
3. tire extension absent while OFF
4. temperatures flat while OFF
5. extension loaded after enable
6. core reports tires ON
7. temperatures rise with driving
8. cold tires have less grip than stock
9. grip follows temperature
10. pressure rises with heat
11. parked tires cool
12. a flat tire still deflates (29.3 to 3.0 psi)
13. extension unloaded after disable
14. core reports tires OFF
15. temperatures flat again
16. OFF-again grip within 2 % of baseline (it matched to 0.01 %)

## What went wrong on the way
- **T001 read a constant 288.14 K.** Stock friction heat is 0, so stock cars never heat their tires. T001's highest setting (friction heat 0.01) gives only about 5 K even in T002's sustained slide. T001's straight accelerate-and-brake run has far less slip, which plausibly explains why it read no change. This was not re-tested.
- **T003/T003b looked noisy.** Some trials read 7.34 m/s2 instead of the expected value. That was a bistable slide state at full lock, not a curve effect. T003c moved to steer 0.5, where the car holds a steady limit circle.
- **T004a: the harness reversed while "parked".** In arcade gearbox mode, holding the brake at a standstill selects reverse. That stalled the ON drive and left the OFF-again drive at 6 m/s. It now stops with the realistic gearbox, clutch in and brake on, and drives in arcade with no brake.
- **T004b: too hot.** At friction heat 0.1, the outer front reached 266 C, the core went over 100 C and the pressure reached 41 psi. All 16 checks still passed. Heat is linear in the coefficient, so T004c halved it to 0.05. The hottest tire then levelled off near 143 C.
- **App layout.** In the T004c screenshot, the right-hand tire tiles cut off their grip value. Grip moved next to the big temperature, and the layout now fits 330x210 with no overflow (checked in a static render). The new layout has not been re-shot in game.

## Limits
- One car, one flat map, a constant limit circle, one clean run per setting.
- Pressure on the outer front rose about 11.6 psi, which is more than a real road tire. A real lap with straights is unchecked.
- A physical mouse click on the app button was not performed. The harness sent the button's exact commands.
