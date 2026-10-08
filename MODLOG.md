## Current checkpoint ? freeroam priority
New single ACNG control app: master ON/OFF, Advanced tabs for tires/assists/FFB/diagnostics. First ON selects heat/wear, keeps factory assists and FFB optional; custom selections survive OFF/ON. Atomic backed-up preferences; new game starts OFF; panel OFF stops streaming too. GUI001 12/12 native checks; 124 Python tests and Node suites pass. Game left at West Coast USA, master OFF, no AI or automatic driving.
Next: road-driving heat/pressure calibration, more vehicle/reset/damage coverage and physical-wheel FFB feedback. Track work deferred in Obsidian Freeroam Plan / Track Later. No car mod started.

# ACNG engineering journal

2026-10-06: user authorized independent BeamNG mod setup and autonomous evidence-driven work. Inspected Steam manifests, tool versions and local Lua APIs. AC still installing to second Steam library. BeamNG existing user profile has BeamMP, so test using isolated profile. Chosen route: Game Engine/Vehicle Lua extensions with no stock overrides. Universal Modder CLI installed locally and KB/scan executed; generic native hook suggestion rejected in favor of verified host extension APIs. Authored first control plane, passive telemetry reader, collector and analyzer. Runtime status is recorded separately in docs/test-results.

2026-10-06, foundation validation: real isolated BeamNG smoke passed seven checks; stock ETK K-Series pilot captured 792 packets without reported loss and produced crossing/distance analysis and reviewed chart. Native temperatures stayed constant; no thermal-model claim. Fixed launch recipe by removing failing `-windowed` and using an unquoted no-space profile path. Primary settings unchanged. Checkpoint `e807e2e`.

2026-10-06, tooling: isolated Universal Modder, REA4.1, Ghidra12.1.4/JDK21, GhidraMCP7, LuaJIT, plotting and portable native compiler verified. REA analyzed original compiled C++ fixture, not a proprietary game. MCP protocol handshake/list-tools passed; registered tools need client reconnect. Checkpoint `9b04f29`.

2026-10-06, AC oracle: installation completed; two offline BMW1M/Magione stationary shared-memory captures accepted 733 samples each, AC1.16.4/shared-memory1.7. Initial backup diff exposed AC rewriting acos.ini/user_ff.ini; restored these and expanded launcher to snapshot all cfg. Second run restored six changed files automatically; full diff clean. Channel semantics/moving/reset tests remain incomplete. Checkpoint `2a73fbe`.

2026-10-06, persistent memory: located existing open Obsidian vault, created only ACNG notes, added resume/update rules to repository AGENTS.md and read-only vault health checker. Existing notes are read and backed up before updates. M2 calibration/repeated baselines next; all dynamics/FFB/racing models remain unimplemented.

2026-10-07: observed same-ID vehicle reload losing the telemetry reader; fixed native respawn reattachment and capture epochs, with actual reset/reload/pickup-switch proof (830 packets, no loss), checkpoint a1076aa. AC native performance benchmark was replay and rejected. First five-repeat ETK set retained old spawn transforms and is provisional; fixed with native safe teleport and validated actual start spread0.11mm. Corrected set4019 packets/no loss, repeat medians documented. Controls delimit maneuver windows to avoid settling-stop ambiguity; receiver can terminate after post-sample silence.21 tests pass. Brief unattended AC keyboard motion captured thermal changes but hit a pit barrier, so it is not a clean reference baseline. Primary settings/config diffs clean; games closed. No physics feature implementation.

## 2026-10-07 — Native damage and clear AC drag oracle
D001 native damage14 checks passed (2,487 packets); fix cross-VM acknowledgement before repair, retain native pressure variation. Original report/scene only; production physics writes0. AC stock drag2000 offline START captured5,881 samples/110.09mph, exact cfg restore; native brake0.81–0.88 rejects full-brake comparison. Original analysis stores clock/control limits.23 automated tests pass. Commits68173c4,3ceb4d3,0f476d0. Obsidian updated/backed; both games/jobs closed. Next native-brake channel experiment and matched repeated references.

## 2026-10-07 - Visible racing HUD and pedal monitor
Commit344a8ff adds the original native UI app, unit/pedal/master controls and isolated HUD scene. Actual game rendering verified;23 Python and Node display/bridge checks pass. Mouse click check blocked by foreground remote desktop. Packaged ZIP and screenshot under dist; primary profile unchanged. Astra Medium/Capsule preference and handoff backed up in Obsidian.

## 2026-10-07 - Performance timer (Claude takes over from Codex)
Codex ran out of usage; Claude continued. T001 recorded native tire temperature constant at 288.14 K under three heating factors (commit 5b4afab, no thermal conclusion). Added original read-only vehicle-VM performance timer (0-60/0-100 mph, 0-100/0-200 km/h, 1/4 mile with trap speed, 60-0 mph/100-0 km/h braking distance) and UI app with units/reset/master. Sim-time, sub-step interpolated, physics writes 0. In-game P001/P002 on stock ETK: 0-60 4.66 s, 1/4 mile 12.94 s @ 51.3 m/s, 60-0 30.3 m; vehicle timer within 2.3 ms of independent GE reference. Found and fixed BeamNG `extensions.__index` auto-load: `if extensions.acng_x then` loads the extension; existing telemetry stop and new reset now use `isExtensionLoaded`, guarded by a source-scan test. 28 Python tests and both Node suites pass. Physical mouse clicks on app buttons still unverified. Primary profile untouched; lab closed.

## 2026-10-07 - Lap timer with live delta
Added an original read-only vehicle-VM lap timer (`acng_laps`) and the ACNG Lap Timer UI app. SET LINE makes a 30 m gate where the car is. The app shows the current lap with a live delta to the best lap at equal distance, three distance sectors, and last, best, optimal and laps. Reset, backwards crossings and jumps over 30 m abandon the lap; loops under 5 s or 50 m are ignored. Sim time, interpolated crossings, physics writes 0. Master ON/OFF loads/unloads it with the perf timer. In-game LT003 (stock ETK circles on Small Grid): 15/15 checks, six laps within 1.5 ms of an independent GE reference, slow lap 12.77 s vs 10.65 s with a +1.18 s mid-lap delta. LT001 exposed BeamNG's `_` to `/` extension-name mapping (harness never loaded); LT002 exposed a harness snapshot race. Both fixed, and a new test rejects underscores in extension file names. 34 Python tests and the Node suites pass. Mouse clicks are still unverified. Primary profile untouched; lab closed.

## 2026-10-07 - Tire heat and grip window (first physics feature)
Added `tire_temperature`, the first physics feature, OFF by default. While ON, the vehicle extension `acng_tires` turns on BeamNG's native tire heat and drives a Lua grip window: full grip from 75 to 105 C, 85 % when cold or overheated. Stock values are saved and restored exactly. `acng_core` gained `setFeature` and loads/unloads the extension with the master and feature flag. Added the ACNG Tires UI app. T002 showed stock friction heat is 0 (linear in the coefficient; strain and flash heat negligible). T003c showed the native grip curve steps at its limits, which led to the flat-curve-plus-Lua-ramp design. T004a exposed the arcade brake-to-reverse trap in the harness. T004b passed at friction heat 0.1 but reached 266 C, so T004c used 0.05: all 16 checks pass and the hottest tire levels off near 143 C. 46 Python tests and the Node suites pass. Primary profile untouched; lab closed.

## 2026-10-07 - Tire wear
Added `tire_wear`, the second physics feature, OFF by default and separate from `tire_temperature`. `acng_tires` wears each tire's tread from BeamNG's own per-wheel slip power (`wheels.wheels[cid].slipEnergy`, read only): `tread -= slipEnergy*dt*rate*heatMult/7.5e6`, heatMult 1 up to 105 C rising to 2 at 145 C (heat on only), and wear grip `1 - 0.15*(1 - tread)`. Grip written is heat grip x wear grip. With wear only, the stock thermal values stay in place. `acng_core` loads the extension when either flag is on and calls `configure(heat, wear)` when only the flags change, so tread survives a part toggle; reset fits fresh tires. The ACNG Tires app gained HEAT/WEAR buttons, tread bars and the wear rate in its header line. T005a failed only its strict reset check (car settling made 0.4 J of slip work); threshold set to 100 J. T005b: 19/19 checks, wear-only lateral -5.1 % at rate x11.3, grip/lateral r=0.995, temperatures unchanged within 0.002 K, OFF again within 0.014 %. 59 Python tests and the Node suites pass. Primary profile untouched; lab closed.

## 2026-10-07 - Saved lap references (offline verified)
- Separate GE archive and lap-timer bridge retain the line and completed best reference per map/car configuration. No force/control writes.
- Bounded history, previous-file recovery, failed-write/readback reporting and stale-request rejection. CLEAR/SET LINE update the saved reference.
- 13 LuaJIT lap/archive tests and Node lap-app checks passed; in-game verification pending. Preserved Claude's unfinished assists changes; no game/UI interaction.

2026-10-07, saved-lap follow-up: reject malformed sector/trace arrays; expose archive status in snapshots. Added LR001 automated native round-trip harness, primary/existing-profile refusal checks and a committed-only isolated-profile preparer. 15 offline LuaJIT tests plus Node lap-app checks pass. Runtime test remains unrun.

2026-10-07, saved-lap runtime validation: LR001 5/5 native save/reload/CLEAR checks; LR002 4/4 full process restart checks, actual 10.64619860656 s reference restored. Owned instances closed, stock profile untouched. Original JSON evidence retained; committed-only player ZIP prepared separately from unfinished assists.


## 2026-10-07 - Assists (ABS and TC levels)
Added `abs` and `tc` flags, OFF by default, with levels OFF/1/2/3 (`setAssistLevel`) and FACTORY when the flag is off. Vehicle extension `acng_assists` saves the stock ABS/TC values on load and writes them back exactly. ABS: native per-wheel `hasABS`/`slipRatioTarget` plus `wheels.setWheelBrakeUpdate`; works on cars built without ABS. TC: native CMU `tractionControl` supervisor and thresholds (brake threshold 0.8 x motor, the stock ratio); cars without CMU TC get an ACNG controller on the `throttleFactor` electric (slip of the fastest driven wheel vs the undriven wheels, 0.05 s filter, gain 3, 20 % floor, 3/s recovery). A001 probed stock ABS/TC across nine cars. T006a: harness compared electrics with `true` (electrics stores 1/0). T006b 24/25: the first own-TC controller (gain 5, 5 % floor, airspeed reference) slowed the Bolide. T006c aborted; T006d partial (game closed externally). The ACNG Assists buttons sent several statements through BeamNG's callback wrapper, the same fatal Lua error as the tire buttons; now one function expression, covered by `tests/test_assists_bridge.py` and an in-game click phase. T006e 25/26; the own-TC peak-slip term was changed to "lower peak, half the mean slip" and recomputed from saved numbers to 26/26 (game not rerun). 93 Python tests and the Node suites pass. Primary profile untouched; lab closed.

## 2026-10-07 - Tire heat balance (T007)
User reported hot tires staying hot. T007a swept five heat sets over 6 lap-like cycles, T007b ran the shipped set against the chosen one over 12 cycles. Old set: core 91 C and rising, corner peaks past the window, parked tire stays hot. New set (air 0.10 to 40 m/s, core 0.005, friction 0.06): peaks settle at 103-105 C, straights cool to about 41 C, core 71 C. Road-contact heat (nodeToSurface) behaved erratically and is not used. Harness tests/beamng-tirecool, analysis scripts/analyze_tirecool.py.

## 2026-10-07 - Force feedback (T008)
Added `acng_ffb` (vehicle), FFB settings in `acng_core` (gain, min_force, filter, kerb, road, slip, per-model car_gain; saved in runtime.json), and the ACNG FFB app. Min force and effects use hydros' testHook so the exact stock force is known each physics step; the hook is only taken when free and only while an effect is above 0. T008a 19/21: harness compared math.huge with abs(a-b) (NaN); fixed, T008b 21/21 on a fresh profile with BeamNG's virtual wheel. Harness tests/beamng-ffblab. Primary profile untouched; lab closed.

## Native race prototype / solo default
User reported AI collisions; automatic test stopped. Native BeamNG AI only; zero opponents by default. RW001 partial: seven native checks, completion/damage checks pending. 118 Python tests pass.
# 2026-10-08 - Road tire preset and compatibility

Added Road/Sport selection to the unified control app. Road has gentler heat and
core coupling, 35-75 C window and minimum 98% cold grip; Sport preserves T007.
Presets retain existing heat/tread and save with preferences; master stays OFF at
startup. Road grip constants remain experimental. FR001 controlled thermal proxy,
GUI002/FR002 native selectors, three vehicle/reset checks and ETK damage checks.
GitHub publication audit added; CLI authentication remains user-required.

## 2026-10-08 ? Optional pit prototype and Spa/car investigation
Added guarded session-local service box, timed native refueling and intact-tire ACNG tread refresh, Advanced Pits controls, cancellation on master OFF/reset/switch/movement, isolated P001 harness, and original read-only KN5 inventory tool. 140 offline contracts passed; no live pit/track success yet. Normal install unchanged. AC BMW 1M file readable; actual car conversion not complete. See docs/SPA-AND-PITS.md.

## 2026-10-08 - P001 pit service live (Claude)
P001 (Codex) and P001a stopped at the first vehicle probe: `code..';local r=...'` with an empty command starts the chunk with `;`, a LuaJIT syntax error, so the probe never replied. Joined with a newline; added stage tracking and a click log to the harness. P001b 13/13 on a fresh isolated profile. No production code changed.

## 2026-10-08 - FR001c sustained heat and FR002b stock damage (Claude)
New isolated harnesses `tests/beamng-roadheat` (RoadHeat) and `tests/beamng-stocklab` (StockLab), registered in scripts/launch-lab.ps1. `scripts/analyze_tirecool.py` now also reads RoadHeat output. FR001c: Road +1.7 psi and flat 50 C corner peaks over 16 limit cycles; Sport +8.5 psi; native-only +0.4 psi. FR002b: 110/110 across six stock models including a 3-wheeler and a 10-tire semi. No production code changed.

## 2026-10-08 - P002 Spa pit lane and personal BMW 1M conversion (Claude)
`scripts/launch-lab.ps1`: `-ExtraMod` path join fixed (the missing backslash hid the map); `CarLab` added. New `tests/beamng-spalab` (P002, 18/18 on Spa) and `tests/beamng-carlab` (C001). New original converters `converters/kn5_model.py`, `jbeam_io.py`, `export_kn5.py`, `build_ac_car.py`: AC BMW 1M skin bound as flexbodies to the stock ETK K-Series damage groups, output refused inside the repo. Uncompressed AC DDS converted to PNG and incompressible zip entries stored, after C001 showed BeamNG rejecting both. `tests/test_ac_car_converters.py` uses synthetic data only. No ACNG runtime code changed.
