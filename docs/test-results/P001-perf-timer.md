# P001/P002 performance timer in game

Stock BeamNG ETK K-Series `kc6_360_M`, Small Grid, BeamNG 0.39.4, fresh isolated lab profiles (`ACNG-p001`, `ACNG-p002`). Master OFF at start. Arcade shifting at full throttle until both the quarter mile and 100 mph were reached, then realistic gearbox and full brake to a stop. Harness: `tests/beamng-timer`. Raw results: `p001-perf-timer.json`, `p002-perf-timer.json`; screenshot `p001-perf-timer.png`.

The harness kept its own reference in the GE VM (GE-frame samples of native ground speed over simulation time, same thresholds) to compare with the vehicle-VM timer.

| Measurement | P001 timer | P001 reference | P002 timer | P002 reference |
|---|---:|---:|---:|---:|
| 0-60 mph | 4.6772 s | 4.6761 s | 4.6580 s | 4.6580 s |
| 0-100 km/h | 4.8688 s | 4.8679 s | 4.8483 s | 4.8484 s |
| 0-100 mph | 9.9078 s | 9.9059 s | 9.8947 s | 9.8924 s |
| 1/4 mile | 12.9584 s @ 51.33 m/s | 12.9574 s @ 51.32 m/s | 12.9448 s @ 51.31 m/s | 12.9437 s @ 51.30 m/s |
| 60-0 mph | 30.40 m (2.28 s) | n/a | 30.26 m (2.26 s) | n/a |
| 100-0 km/h | 32.50 m (2.36 s) | n/a | 32.34 m (2.34 s) | n/a |

Largest timer-vs-reference difference: 2.3 ms. Codex's earlier B001 telemetry pilot on the same car measured 0.1 m/s-60 mph as 4.6674 s and 60 mph-0.1 m/s as 30.14 m. Different start/stop thresholds account for the small gap. Braking has no independent reference in this harness.

Checks (P002, all true): master OFF by default; timer absent while OFF; timer attached to the player vehicle when ON; results received; the app's exact RESET command clears results; master OFF detaches the timer; the RESET command does not reload the timer after OFF.

**Bug found and fixed between P001 and P002:** BeamNG's `extensions` table loads any unknown name on access (`lua/common/extensions.lua`, `__index` calls `load`). So `if extensions.acng_perf then` loaded the timer just to test for it. P001's after-OFF probe got a fresh timer back. The same pattern was in the RESET button and in the existing telemetry stop command. All three now use `extensions.isExtensionLoaded(...)`, and a source-scan test rejects the old pattern. P002 confirms the timer stays unloaded.

Limits: one car, one map, two runs. No rollout correction. A mouse click on the app buttons was not performed: the screen tool could not be granted the game window, so the commands were sent by the harness instead.
