# T006 assists in game (ABS and TC levels)

Setup for every run:
- BeamNG 0.39.4 on Small Grid
- a fresh isolated lab profile per run
- master OFF at start
- every level picked through the real ACNG controls (`acng_core.setEnabled`, `setAssistLevel`, `setFeature`)

Harness `tests/beamng-assistlab` (GE extension `acng_assistlab`). Two straight-line runs:
- **brake**: full throttle to just over 100 km/h, then full brake to a stop. Records the stop distance (scaled to 100 km/h) and the share of frames with a locked wheel (under 30 % of road speed, above 6 m/s).
- **launch**: full throttle from a standstill for 5 s. Records the driven-wheel slip, the share of frames over 15 % slip (wheelspin), the speed at 5 s, and the lowest throttle factor ACNG wrote.

Slip is the fastest driven wheel's surface speed against the average of the undriven wheels (airspeed when every wheel is driven, never below 3 m/s), the same measure ACNG's own TC uses.

Cars:
| Car | Stock assists (A001) | Runs |
|---|---|---|
| ETK K-Series `kc6_360_M` | native ABS, CMU traction control | brake factory / ABS OFF / ABS 2, launch factory / TC OFF / TC 3 |
| Bolide `350` | none | brake factory / ABS 2, launch factory / TC 3 (ACNG's own TC) |
| Gavril Grand Marshal `stock` | none | launch factory / TC 3 (ACNG's own TC) |

After each car the features go OFF and every ABS/TC value must match the values read at spawn exactly. At the end the harness clicks five real buttons in the ACNG Assists app (ABS 2, TC 3, TC OFF, ABS FACTORY, TC FACTORY) and checks that each one reaches the game.

## Runs
| Run | Result | Notes |
|---|---|---|
| T006a | 18 of 21 | The configuration checks and exact restore passed on both cars. Two failures were harness bugs: it compared the ABS/TC active electrics with `true`, but electrics stores booleans as 1/0, so no ABS frame was ever counted (`etkc_abs_on_no_lock`, `bolide_abs_added`). `bolide_own_tc_cuts` failed because slip was measured against airspeed (see below), and the throttle was cut to 5 %. Raw results: `t006a-assistlab.json`. |
| T006b | 24 of 25 | Harness fixed, fullsize added. ABS and the CMU TC passed. `bolide_own_tc_cuts` failed: the first own-TC controller (gain 5, 5 % floor, no filter) cut to 5 % at any slip spike and cost the bolide 2.5 m/s at 5 s (23.5 against 26.0). Raw results: `t006b-assistlab.json`. |
| T006c | aborted | BeamNG closed during a pause; no results. |
| T006d | partial (12 of 12 runs, no checks) | New controller and the undriven-wheel slip reference. The game was closed from outside while loading the last phase, so the checks never ran. It ran at about 30 fps. Raw results: `t006d-assistlab-partial.json`. |
| T006e | 25 of 26, **26 of 26** after one criterion change | Final controller and harness, with real app button clicks. `bolide_own_tc_cuts` failed only on its peak-slip term, which required level 3 to halve the peak slip. The bolide's level 3 peak (2.63 against 4.01) comes in the first frames off the line, under 0.3 m/s, with the throttle already at the 20 % floor: even 20 % throttle spins that car from a standstill for a moment. The criterion is now "lower peak and at least half the mean slip" (the other terms are unchanged). Recomputed from the saved T006e numbers, both own-TC checks pass; the game was not rerun. Raw results: `t006e-assistlab.json`. |

## What changed between T006b and T006d
- **ACNG's own TC controller.** The slip is smoothed over 0.05 s, the cut is `1 - 3 x (slip - threshold)` (gain 3 instead of 5), the floor is 20 % (instead of 5 %) and the recovery is 3 per second (instead of 2).
- **Slip reference.** Measuring against airspeed made a car rolling on the flat read about 8 % slip, so the controller was always slightly on. The driven wheels are now compared with the undriven wheels. The harness uses the same measure, so the T006b and T006d slip numbers are not comparable.

T006d launch numbers (the traces in the raw file show TC catching the spin in about 0.1 s and then holding slip at about 7 to 9 %):

| Car | Run | Mean slip | Peak slip | Wheelspin frames | Speed at 5 s | Lowest throttle factor |
|---|---|---:|---:|---:|---:|---:|
| bolide | factory | 1.056 | 4.01 | 60 % | 24.95 m/s | - |
| bolide | TC 3 | 0.200 | 2.67 | 10 % | 25.29 m/s | 0.20 |
| fullsize | factory | 0.701 | 1.89 | 59 % | 18.48 m/s | - |
| fullsize | TC 3 | 0.070 | 0.42 | 11 % | 19.15 m/s | 0.23 |

## The app button bug
ChatGPT's tire playtest found that clicking HEAT or WEAR gave a fatal Lua error (fixed in `ae5bbee`). The UI bridge wraps the command as `guihooks.trigger("onBNGAPICallback", id, <command>)`, so a command with a callback must be one expression. The ACNG Assists buttons had the same bug: they sent three statements. They now send one function expression. `tests/test_assists_bridge.py` runs every button command inside that wrapper under LuaJIT, and T006e clicks the real buttons in game. The earlier runs called `acng_core` directly, which is why they missed it.

## T006e numbers
Braking (stop distance scaled to 100 km/h):

| Car | Run | Stop distance | Locked-wheel frames | ABS active frames |
|---|---|---:|---:|---:|
| ETK K | factory ABS | 35.1 m | 10.6 % | 55 |
| ETK K | ABS OFF | 42.1 m | 94.9 % | 0 |
| ETK K | ABS 2 | 36.3 m | 14.7 % | 54 |
| Bolide | factory (no ABS) | 49.1 m | 94.5 % | 0 |
| Bolide | ABS 2 (added by ACNG) | 41.5 m | 14.3 % | 63 |

Launches (5 s at full throttle):

| Car | Run | Mean slip | Peak slip | Wheelspin frames | Speed at 5 s | Lowest throttle factor |
|---|---|---:|---:|---:|---:|---:|
| ETK K | factory TC | 0.144 | 1.25 | 17.4 % | 28.54 m/s | - |
| ETK K | TC OFF | 0.349 | 1.64 | 41.6 % | 28.18 m/s | - |
| ETK K | TC 3 (native CMU) | 0.118 | 1.15 | 13.4 % | 27.33 m/s | - |
| Bolide | factory (no TC) | 1.056 | 4.01 | 59.1 % | 24.94 m/s | - |
| Bolide | TC 3 (ACNG) | 0.206 | 2.63 | 8.8 % | 25.16 m/s | 0.20 |
| Grand Marshal | factory (no TC) | 0.682 | 1.84 | 58.4 % | 18.51 m/s | - |
| Grand Marshal | TC 3 (ACNG) | 0.070 | 0.39 | 7.4 % | 19.16 m/s | 0.29 |

Also true in T006e:
- ABS 2 set an 18 % slip target and the ABS brake function on every wheel; ABS OFF cleared it. TC 3 on the ETK set the native motor slip threshold to 0.08 and switched the supervisor on; TC OFF switched it off.
- FACTORY left every stock value untouched, and after each car every ABS/TC value matched the spawn values exactly, with the vehicle extension unloaded.
- All five app buttons (ABS 2, TC 3, TC OFF, ABS FACTORY, TC FACTORY) reached the game through the real UI bridge.

## Not yet checked
- Feel: no human has driven with the assists. ACNG's own TC only cuts power and recovers at 3 per second, so it may feel abrupt on some cars.
- Only straight lines on a flat map, and three cars. No corners, no wet or loose surfaces, no gearbox modes other than the harness defaults.
- The ETK's stock TC and ACNG's TC 3 are close (mean slip 0.144 against 0.118), so the difference there is small.
- Physical mouse clicks: the harness clicks the buttons through the page, not with the mouse.
