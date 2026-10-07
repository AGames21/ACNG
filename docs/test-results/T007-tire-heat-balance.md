# T007 tire heat balance on lap-like cycles

Why: in the first hands-on playtest (Hirochi Raceway, etkc) the user reported that once the tires got hot they kept getting hotter or stayed hot. AC tires heat in a corner, come back down on a straight and settle; they do not creep up lap after lap.

Setup:
- stock ETK K-Series `kc6_360_M` on Small Grid
- BeamNG 0.39.4
- a fresh isolated lab profile per run
- master OFF at start, then master and `tire_temperature` ON through `acng_core`

Harness `tests/beamng-tirecool` (GE extension `acng_tirecool`). Each cycle is:
1. a limit corner (steer 0.5, held at 10 m/s) for 20 s
2. a straight (steer 0, held at 38 m/s; the mean was about 31 m/s) for 15 s
3. braking to 12 m/s

Each candidate `acng_tires.HEAT` set is written into the running extension, then a physics reset brings fresh ambient tires with that set. Every tire is sampled once a second, and after the cycles the car is parked for 30 s. `scripts/analyze_tirecool.py` makes the summaries.

## T007a: five sets, 6 cycles
Summary: `t007a-tirecool-sweep.json` (the per-second raw file stays outside Git).

| Set | Air cooling (parked x, full at) | Core coupling | Friction | Hot-tire core at end | Straight end, cycles 1 -> 5 | Pressure rise | Parked 30 s |
|---|---|---:|---:|---:|---|---:|---|
| A (shipped) | 0.04 (x0.4, 20 m/s) | 0.01 | 0.05 | 74 C | 47 -> 65 C | +8.2 psi | 105 -> 74 C |
| B | 0.12 (x0.25, 40 m/s) | 0.01 | 0.066 | 68 C | 29 -> 36 C | +7.3 psi | 105 -> 57 C |
| C | 0.12 (x0.25, 40 m/s) | 0.005 | 0.066 | 52 C | 30 -> 36 C | +5.2 psi | 106 -> 57 C |
| D | 0.09 (x0.3, 40 m/s) | 0.01 | 0.055 | 67 C | 33 -> 44 C | +7.2 psi | 102 -> 59 C |
| E | B plus surface (road) heat 0.03 | 0.01 | 0.066 | 44 C | erratic | +3.8 psi | 48 -> 32 C |

- Set A, the one that shipped, matches the user's report: the core gains about 10 K a cycle, so every straight ends hotter than the last, and a parked tire stays hot.
- The road-contact heat setting (E) moved the hottest tire to a different wheel and gave one 142 C spike. It is not understood, so it is not used.

## T007b: shipped set against the new set, 12 cycles
Summary: `t007b-tirecool-confirm.json`. The new set F is between C and D: air cooling 0.10 (x0.3 parked, full at 40 m/s), core coupling 0.005 both ways, friction 0.06.

Hot tire (outer front):

| Cycle | Old corner peak | Old straight end | Old core | New corner peak | New straight end | New core |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 72 C | 47 C | 26 C | 73 C | 33 C | 20 C |
| 4 | 103 C | 67 C | 64 C | 104 C | 39 C | 42 C |
| 8 | 109 C | 69 C | 85 C | 103 C | 41 C | 62 C |
| 11 | 110 C | 72 C | 89 C | 105 C | 42 C | 69 C |
| 12 | 109 C | - | 91 C | 105 C | - | 71 C |

| End of 12 cycles | Old | New |
|---|---:|---:|
| Highest surface | 116 C | 107 C |
| Mean of the last two cycles | 94 C | 85 C |
| Core | 91 C | 71 C (still rising, by 2 K a cycle and slowing) |
| Pressure rise | +10.3 psi | +7.8 psi |
| Parked 30 s | 109 -> 82 C | 105 -> 57 C |

- Old: corner peaks went past the window (105 C) from cycle 6 and stayed there, so the hot tire lost grip every corner. The straights stopped cooling it below 70 C.
- New: corner peaks settle at 103-105 C from cycle 4 and stay there. The straights bring the surface back to about 41 C each time, and that floor no longer climbs.

## Limits
- One car and one fixed cycle, driven by a script, not a human lap.
- The new set cools the surface hard on a straight. The next corner starts at about 41 C, which gives about 91 % grip for the first seconds of the corner. Whether that feels right needs the user's playtest.
- Pressure still rises about 8 psi on the hottest tire, more than a real road tire. The core, which sets the pressure, had not fully settled after 12 cycles.
- The grip window is still read from the tire's average node temperature (surface), as before.
