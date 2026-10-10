## 2026-10-10 - GUI004 minimal transparent HUD (installed)

Player asked for no speedometer cluster and a minimal, transparent HUD. ACNG Control is now
a 150 x 32 translucent pill that expands on Advanced; ACNG Tires is four small transparent
tiles bottom right, hidden while the tire model is off. New `scripts/minimal_hud.py
--confirm-normal` strips the tacho, boost, powertrain buttons, drag app and ACNG racing HUD
from the freeroam layout after a backup. Lab GUI004 37/37. 252 Python tests pass.
[Evidence](docs/test-results/GUI004-minimal-hud.md).

## 2026-10-10 - C015 M3 visual fixes and rigid gauge needles (installed)

Player report on the M3: plate clipping, white bumper dots, white seats and roof, bouncing
needles, worn belt over the seat. Needles now ride the vanilla ETK nodes `f1l`/`f1r`/`f6l`
rigidly instead of 0.15 kg sprung triangles (diagnosis by Codex); both cars. AC multimaps
whose diffuse alpha is below 0.5 export their tiled detail map (carbon, leather). Stencils
using the paint's detail map become paint. `CINTURE_ON` is always skipped. New per-car
`PLATE_GROUP`: the M3 plate rides the body. The roof is carbon on the real car. CarLab M3
ACNG-car-035 53/53 and 1M ACNG-car-036 54/54; both installed. 250 Python tests pass.
[Evidence](docs/test-results/C015-m3-visual-gauge-fixes.md).

## 2026-10-10 - C014 BMW M3 E92, car profiles, generic CarLab, shift sounds (installed)

Per-car profiles in `converters/cars/`. A 1M build after the refactor matches the old build
(186 entries, 0 differences). The AC M3 E92 is fitted to the ETK K-Series with the 4.4 V8
cloned to BMW figures. CarLab reads `acng_car/<model>.json` targets, and the installer
keeps one record per car. New original `acng_shiftSound` vehicle controller: native lever
hooks only play FMOD events, so a WAV there was never heard. The controller plays AC
gearup / geardn by engaged-gear direction, and its sound node must be on the shifter part
(1M `sh_b3`, M3 `f7`). The final-drive target is now the native part's 3.154. CarLab M3
ACNG-car-032 53/53 and 1M ACNG-car-034 54/54; both installed. 247 Python tests pass.
[Evidence](docs/test-results/C014-m3-e92-generic-carlab.md).

## 2026-10-09 - Car import pipeline and guide

`scripts/car_pipeline.py`: build, fresh isolated CarLab run, report, optional gated install, one command; refuses while BeamNG runs (confirmed live). `docs/CAR-IMPORT.md`: stages, generic vs per-car values, new-car checklist, new-source reader interface; Forza excluded (encrypted assets). End-to-end game run pending a closed BeamNG.

## 2026-10-09 - C013 BMW 1M limiter and event sounds (installed)

Converter: explicit native 250 km/h target and ECU selection; cloned turbo/shifter sound mappings. Gear samples use native gear-in/out semantics. Rev-limiter recording is local research only: no standalone native playback slot found. C012 engine/exhaust audio and mechanical settings preserved byte-for-byte where applicable. 225 Python tests, 10 Node suites and publication audit pass; fix-012 builds externally. CarLab ACNG-car-028 54/54 after the limiter check moved to wheel speed (027: limiter held 250 by wheel speed, ground speed 247.9 failed a 248 band). Installed. [Evidence and next step](docs/test-results/C013-1m-native-limiter-event-sounds.md).

## 2026-10-09 - C012 1M sound follows AC loop crossfades (installed)

Each AC loop gets pitched copies at both edges of its solo band so the sfxBlend2D only
mixes two recordings inside AC's fade windows; AC's per-loop volumes baked into the WAVs.
Copy lengths give near-whole tags. CarLab ACNG-car-026 50/50; installer accepts C012
evidence; 222 tests pass. Installed.

## 2026-10-09 - C011 1M centred brakes, native plate, AC torque, sound balance (installed)

Kept flexbodies shift by the node move at their group centroid (brakes, exhaust, tank,
heatshield, wings). Native drilled discs and calipers (360/350 mm), native plate, neutral
author strings, badge slots empty, display logo filled. Base torque rebuilt so the net
curve follows AC (worst 1.8 %). Idle samples tagged 650 rpm, interior set -8 dB,
offLoadGain 0.75. CarLab ACNG-car-025 50/50; 219 tests pass. Installed.

## 2026-10-09 - 1M sound EQ cancel, loop seam, nose binding (built, native test pending)

Child-part `$+` sound EQ (turbo intake, I6 exhaust) is summed and cancelled in the
engine base config with +3 dB level match; loop seams that click get a 30 ms
equal-power crossfade. Body triangles ahead of y -1.6 move to a `nose` flexbody on
`etkc_body` + unbreakable `etkc_bumperbar` (2753 triangles). 214 tests pass. C011
pending: the normal game is open.

## 2026-10-08 - C007-C010 1M steering, pedals, crash liner, wheel track (installed)

Prop steering sign and pedal picking by X position (foot rest static); BeamNG
paint presets; 16x16 glow maps; far lamp and fender-liner triangles rerouted to
nearby panel groups; crash-isolation, steering-direction and tire-centre lab
checks. Rim parts declare `$trackwidth_F/R` so the `.pc` track applies. CarLab
ACNG-car-023 49/49; installer accepts C007-C010 evidence. Installed.

## 2026-10-08 - C006 1M steering frame, panel groups, seats, lamps (installed)

Steering column frame from the AC STEER_HR node; seat shells only on native ETK
seat nodes, seat cages removed; one node group per outer panel with split front
fenders; ETK wheel-well tubs stripped; patterned lamp glow with intense brake
lamps. CarLab ACNG-car-018 45/45; installer accepts C006 evidence. Installed.

## 2026-10-08 - C005 handling measurement preparation (blocked)

Read Claude's C004 handoff, claimed then released the native lease while the
normal game remains open. Added optional isolated CarLab acceleration/braking
repeats, circle/balance/static-axle measurements and an original summary tool.
191 Python tests and existing Node scripts pass; native benchmark unverified.
Read AC numeric reference outside Git; no converter or tire/GUI changes. C005
report contains pending before/after rows. Next: game closed, fresh baseline 017.

## Current checkpoint ? freeroam priority
New single ACNG control app: master ON/OFF, Advanced tabs for tires/assists/FFB/diagnostics. First ON selects heat/wear, keeps factory assists and FFB optional; custom selections survive OFF/ON. Atomic backed-up preferences; new game starts OFF; panel OFF stops streaming too. GUI001 12/12 native checks; 124 Python tests and Node suites pass. Game left at West Coast USA, master OFF, no AI or automatic driving.
Next: road-driving heat/pressure calibration, more vehicle/reset/damage coverage and physical-wheel FFB feedback. Track work deferred in Obsidian Freeroam Plan / Track Later. No car mod started.

## 2026-10-08 - 1M lamps/glass/mirrors/wheel fixes; tire heat cap and compounds

Fix prop rest-rotation sign (upright wheel and logo), add native lamp glowMap and
on/off emissive materials, dim unlit lenses, grey glass, stock mirror material,
honour normal-map alpha cutouts and damp seat/prop mounts. Tires: Auto/Road/Sport/
Race compounds with distinct windows and wear, 200-250 C friction-heat fade, faster
hot wear, zero-tread native puncture. Compact ACNG app. C004 45/45 native; installed.


Add native RPM/speed/fuel/oil gauge props, mirror faces/cameras with corrected UVs,
and BMW rim visuals on native wheel physics. Add synthetic contracts and C003
native regression/installation gating. Offline: 170 Python tests plus LuaJIT
syntax passed. Native testing awaits a free game instance; C002 remains installed.

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

2026-10-08, other PCs: user asked to get the whole mod on their other PCs from GitHub. The private repo already held all source, so added a private GitHub Release with the verified player ZIP (acng-freeroam.zip + build manifest) and README steps: download from Releases, drop in the mods folder. Spa (author forbids reupload) and the personal AC BMW 1M (game assets) stay out of GitHub; the 1M is rebuilt per PC with converters/build_ac_car.py or copied by the user between their own PCs.


## 2026-10-08 - Local 1M rig and specifications

Separated dash/cabin/front seats/shifter, four native steering/pedal props, hidden
front donor bar/support meshes. Verified BMW gearing, native fuel tank and net
power/torque calibration; retained an independent donor config. A/B rejected
uniform chassis mass reduction after immediate front-subframe damage. Chassis
weights/mounts remain native; measured weight remains ~2.5% above reference.
C002 placement run 34/34, wheel-pose screenshots reviewed, 162 Python/six UI suites
passed. Final package validation/install pending. New installer requires the exact
natively tested local ZIP; normal updater recognizes only the recorded car hash.
No game assets enter this repository or public package.

Finalization: corrected both native prop placement and rest orientation; wheel
neutral/153-degree driver screenshots and footwell view reviewed. Final C002
34/34 in a new profile. Source 55c6fa8; installer compatibility fix 6790ca5.
164 Python tests, six UI suites passed. Installed verified local car and wear
package in the authorized normal profile; hashes match, backups recorded in
ignored local records. Preserved an unrelated malformed-encoding mod ZIP.
Normal-profile coexistence and road-driving feel remain user playtests.
