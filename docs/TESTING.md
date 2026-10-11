# Testing and evidence

Run `python -m unittest discover -s tests -v` from repository root. Lua contracts use the workspace toolchain's Lupa LuaJIT 2.1 runtime when available. Syntax/contract tests are not real-game load proof.

Real-game smoke: fresh isolated user folder, deploy only ACNG, confirm VFS user path and `FOUNDATION_LOADED ... master=false physics_writes=0` in the fresh log, load a stock vehicle/map, exercise master on/off, enable/disable telemetry, change/reset vehicle, confirm no ACNG exceptions. Observe screenshot and log. Retain machine-readable results and hashes. Never describe a mock run as a driving benchmark.

Capture: start `python -m telemetry.collect_udp telemetry/runs/<unique>.jsonl --duration 30`, then enable telemetry using `extensions.acng_core.setTelemetryEnabled(true)` in GE Lua. Stop with false. Master may stay OFF. Data loss and timing gaps invalidate high-frequency comparisons. Review native channels before normalizing.

Analyze only trimmed single-maneuver/single-vehicle/single-generation runs: `python -m telemetry.analyze <run.jsonl> --mode acceleration --target-mph 60 --output <result.json>`. Current movement/stop threshold is 0.1 m/s, reported explicitly; this is not a standardized drag-strip rollout claim. Braking distance integrates speed and requires a verified straight/level road. No implicit cross-game comparability.

Freeze game builds, car config/parts, fuel/mass, tire spec/pressure, track, weather/grip, assists, transmission/control method, physics time scale, spawn position/orientation and warm-up. Record five repeats; report median/spread and rejected runs. Alternate OFF/ON order to detect drift. No subjective-only tuning.

AC stationary smoke: `python scripts/ac-offline-smoke.py --game <AC-install> --user <Documents/Assetto-Corsa> --evidence <private-fresh-work-directory>`. Refuses an existing AC process; launches an explicitly offline stock BMW1M/Magione session without input automation; checks expected live identity and collects existing shared-memory pages. Backs up all existing cfg files and restores after closing only its owned process. If interrupted outside Python cleanup, recover from its manifest/backups; keep these personal configs outside Git. Check full backup diff afterward. The installed AC1.16.4 prefix was runtime-smoked, but moving/reset/thermal/FFB semantics still require validation. AC host time/lap time are not BeamNG simulation time.

Memory check: `python tools/vault_check.py` reads ignored local path configuration, requires an existing `.obsidian`, and validates required ACNG notes/qualified wikilinks without writing notes.

L001: `scripts/launch-lab.ps1 -Experiment Lifecycle -LabUser <fresh-no-space-profile/current>` runs actual reset, same-ID reload and stock model switch. Capture identity + vehicle ID + reset generation delimit streams; reattachment occurs on native onVehicleSpawned. See L001-lifecycle.md for before/after proof.

B002: launch `-Experiment Repeats` in a fresh profile while collecting with `--duration 600 --idle-timeout 45`. Idle timeout begins only after the first accepted sample. Run `python -m telemetry.baseline_report <raw> <events> --output <unique-report.json>` after receiver completion; it enforces clean receiver counters and identical actual starts, not just requested transforms. Native replaceVehicle retained old position; safeTeleport after initialization is required. First set001 is provisional;002 passed. Recorded control edges delimit maneuvers so warm-up motion cannot supply a false stopping crossing.

AC native benchmark mode was replay, not live physics, and was rejected. Keyboard mode supplies original temporary controls with wheel FFB gain0; OS input must be separately authorized/unattended and checked by Universal Modder idle/foreground protection. Record external input provenance separately from the launcher's no-input behavior. First short motion hit a pit barrier; retain as motion/collision sanity only. Choose a clear grid/start area before clean reference benchmarks.

For every dynamics change: baseline, original implementation, same maneuver, comparison, performance check, damage regression, documented conclusion. Cover AI, controls, powertrain, soft-body deformation, bent suspension, deflated/missing wheel and unrelated stock vehicles. Require reset if restore cannot be proven.

D001: `-Experiment Damage` invokes native sacrificial collision, repair, FL puncture and verified break group in a separate lab profile. `telemetry.damage_report` checks actual snapshots/packets/receiver counters, with cross-VM acknowledgement before repair. See D001-native-damage.md for evidence and coverage limits. It does not add damage writes to production ACNG.

AC clean route candidate: `ac-offline-smoke.py --mode keyboard --start grid --track drag2000` requests stock BMW1M/ks_drag/drag2000 in an offline single-car race at START. Native shared memory confirms the base track; layout still requires config/visual evidence because the current prefix does not expose layout identity. Race countdown, input edges, controls/assists, setup, fuel, grip and reset state must be recorded before accepting comparisons.

## Planned freeroam regression runs
- FR001: same stock ETK/config/road route, fresh reset, matched OFF/ON repeats; idle/city stops/cruise/winding road. Log surface/core temperature, pressure, grip, tread and speed; do not assume race-slick temperatures suit road tires.
- FR002: reset and switch among stock drivetrain types while chosen features stay enabled; test punctures, bent suspension and missing wheels. OFF must restore saved native coefficients/assists and stop streams without repairing damage.
- FR003: physical-wheel road/understeer/curb runs with clipping observations. Keep native physical steering as the main force source; no physical-wheel success claimed from virtual-wheel tests.
These are planned, not completed. Existing GUI001 validates native DOM command/state and settings lifecycle, not driving feel or new tire calibration.

P001 prepared: `-Experiment PitLab` in fresh `ACNG-pit-001/current`, normal game closed. Tests actual Advanced Pits controls, stationary box, native fuel refill and ACNG tread refresh, actual puncture rejection/preservation and master OFF unload. Raw result `/acng-pit-test.json` in isolated user profile. This harness has not yet run; 140 offline Python/Lua contracts and six existing Node suites pass. Never distribute test harness or extracted AC meshes.

FR001c done (2026-10-08): `-Experiment RoadHeat`, 16 T007 cycles each for native-only, Road and Sport through the real core preset switch; Road +1.7 psi, Sport +8.5 psi. FR002b done: `-Experiment StockLab`, six stock models crash, puncture, lost wheel, master OFF/ON and reset, 110/110. Real roads, toe/camber after a crash and the physical-wheel FR003 remain open.

P002 done (2026-10-08): `-Experiment SpaLab -ExtraMod <user's Spa zip>` in a fresh `ACNG-spa-NNN/current`; 18/18, see P002-spa-pit-lane.md. C001: build the personal car with `converters/build_ac_car.py` (output outside the repo), then `-Experiment CarLab -ExtraMod <out>/acng_bmw1m.zip` in a fresh `ACNG-car-NNN/current`; result `/acng-car-test.json` plus in-engine screenshots. See C001-ac-car.md and AC-CAR-CONVERSION.md.

T009a done (2026-10-10): `-Experiment TireProbe` in a fresh `ACNG-tireprobe-<stamp>/current`, stock etkc on Small Grid; it records tread node layout, tire pressure variables, native strain heat against a strain-0 control side, a left-side pressure drop and a constant circle. Result `/acng-tireprobe-test.json`; summary `t009a-tireprobe.json`. T009b done (2026-10-10): `-Experiment TirePhys` in a fresh `ACNG-tirephys-<stamp>/current`. It runs an OFF circle, then heat ON with each profile, then left -8 psi, a 60 s circle, a straight and a braking stop, reset, a deflated RR circle, 1200 timed updates, and master OFF with the circle again. Result `/acng-tirephys-test.json`; summary `t009b-tirephys.json`; 28/28. Dirt needs loose ground, which Small Grid lacks. C016: CarLab also shoots `lights_drl` (state 0) and `lights_high` (state 2) and checks the high-beam signal.
