# T008 force feedback in game (FFB001)

Setup:
- BeamNG 0.39.4 on Small Grid, ETK K-Series `kc6_360_M`
- a fresh isolated lab profile per run, master OFF at start
- every setting changed through the real ACNG controls (`acng_core.setEnabled`, `setFeature`, `setFFBSetting`), then six real app button clicks

Harness `tests/beamng-ffblab` (GE extension `acng_ffblab`). No FFB wheel is attached, so the harness turns on BeamNG's virtual wheel (`hydros.enableVirtualWheel`). BeamNG then runs its full FFB calculation and hands each force it would send to a wheel to the harness, at 200 Hz. A GE speed controller holds the car at a target speed while the steering angle is fixed. Each window settles for 3 s and records for 3 s: mean force, standard deviation, and "jitter" (RMS of the change between successive samples, which rises with vibration).

## Runs
| Run | Result | Notes |
|---|---|---|
| T008a | 19 of 21 | Every force check passed. `off_restores_exact` and `final_restores_exact` failed on a harness bug: hydros' `wheelFFBDampLimit` is `math.huge`, and the harness compared numbers as `abs(a-b) <= tol`, which is NaN for infinity. The recorded stock and restored states are identical. Raw results: `t008a-ffblab-inf-compare.json`. |
| T008b | **21 of 21** | Comparison fixed (`a == b` first). Fresh profile, full rerun. Raw results: `t008b-ffblab.json`. |

## T008b numbers
Force is in BeamNG's wheel units (the virtual wheel's limit is 10).

| Window | Steering | Speed | Mean force | Std | Jitter |
|---|---:|---:|---:|---:|---:|
| OFF | 0.05 | 15.6 m/s | 1.476 | 0.046 | 0.039 |
| OFF, small angle | 0.01 | 15.6 m/s | 0.302 | 0.017 | 0.018 |
| ON, GAIN 100 % | 0.05 | 15.6 m/s | 1.482 | 0.034 | 0.036 |
| ON, GAIN 150 % | 0.05 | 15.6 m/s | 2.227 | 0.058 | 0.057 |
| ON, GAIN 100 %, small angle | 0.01 | 15.6 m/s | 0.302 | 0.019 | 0.018 |
| ON, MIN FORCE 15 %, small angle | 0.01 | 15.6 m/s | 1.161 | 0.073 | 0.063 |
| ON, SLIP 0, understeer | 0.35 | 20.2 m/s | 1.138 | 0.103 | 0.043 |
| ON, SLIP 100 %, understeer | 0.35 | 20.2 m/s | 1.176 | 0.228 | 0.099 |
| OFF again (restored) | 0.05 | 15.6 m/s | 1.470 | 0.050 | 0.035 |

- GAIN 100 % / OFF force ratio 1.004 (limit +-5 %). GAIN 150 % / 100 % ratio 1.509 (limit 1.5 +- 0.225).
- MIN FORCE 15 % lifted the small-angle force by 0.86 units; the hook was installed only while an effect or MIN FORCE was above 0.
- FILTER 80 % set BeamNG's smoothing to 240 exactly; STOCK restored the original config.
- Understeer: front tire slip about 3.8 m/s. SLIP 100 % drove the buzz to 0.39 units and raised jitter 2.3x and the standard deviation 2.2x against SLIP 0 (limits: amplitude above 0.05, jitter ratio above 1.3).
- Options change while ON: the vehicle's strength was set to 150 (low speed 15) as BeamNG's Options would. ACNG followed it (225 / 22.5 at GAIN 150 %) and left 150 / 15 in place on OFF.
- OFF and master OFF: extension unloaded, `testHook` nil, coefficients and every `getFFBConfig()` field equal to the values read at spawn.
- App: FFB ON, GAIN up, FILTER up, FILTER stock, GAIN down, FFB OFF were clicked in the real ACNG FFB app and each reached the game.

## Not checked
- How it feels on a real wheel (no FFB wheel in the lab).
- KERB (no rumble-strip material on Small Grid) and ROAD (flat grid) in game; both are covered by the offline tests only.
- Physical mouse clicks (the harness clicked the app's buttons through the page).
