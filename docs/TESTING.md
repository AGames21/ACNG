# Testing and evidence

Run `python -m unittest discover -s tests -v` from repository root. Lua contracts use the workspace toolchain's Lupa LuaJIT 2.1 runtime when available. Syntax/contract tests are not real-game load proof.

Real-game smoke: fresh isolated user folder, deploy only ACNG, confirm VFS user path and `FOUNDATION_LOADED ... master=false physics_writes=0` in the fresh log, load a stock vehicle/map, exercise master on/off, enable/disable telemetry, change/reset vehicle, confirm no ACNG exceptions. Observe screenshot and log. Retain machine-readable results and hashes. Never describe a mock run as a driving benchmark.

Capture: start `python -m telemetry.collect_udp telemetry/runs/<unique>.jsonl --duration 30`, then enable telemetry using `extensions.acng_core.setTelemetryEnabled(true)` in GE Lua. Stop with false. Master may stay OFF. Data loss and timing gaps invalidate high-frequency comparisons. Review native channels before normalizing.

Analyze only trimmed single-maneuver/single-vehicle/single-generation runs: `python -m telemetry.analyze <run.jsonl> --mode acceleration --target-mph 60 --output <result.json>`. Current movement/stop threshold is 0.1 m/s, reported explicitly; this is not a standardized drag-strip rollout claim. Braking distance integrates speed and requires a verified straight/level road. No implicit cross-game comparability.

Freeze game builds, car config/parts, fuel/mass, tire spec/pressure, track, weather/grip, assists, transmission/control method, physics time scale, spawn position/orientation and warm-up. Record five repeats; report median/spread and rejected runs. Alternate OFF/ON order to detect drift. No subjective-only tuning.

For every dynamics change: baseline, original implementation, same maneuver, comparison, performance check, damage regression, documented conclusion. Cover AI, controls, powertrain, soft-body deformation, bent suspension, deflated/missing wheel and unrelated stock vehicles. Require reset if restore cannot be proven.
