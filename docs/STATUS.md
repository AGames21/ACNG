# ACNG status

Updated: 2026-10-06 (America/Chicago).

Current milestone: M1 foundation smoke validated; M2 telemetry/oracle active. No physics tuning.

Current working features: real BeamNG independent-mod load, default-OFF master lifecycle, passive wheel/vehicle telemetry, UDP collection, crossing/distance analysis, chart generation, isolated deployment/launch, offline AC read-only shared-memory capture, full cfg backup/restoration. Durable Obsidian ACNG memory includes linked status, decisions, research, vehicles, test interpretations and session handoff; updates are backed up.

Last successful tests: seven real BeamNG smoke checks; stock ETK pilot with 792 packets and no reported UDP loss; two AC BMW 1M/Magione stationary captures with 733 samples each; second run automatically restored all six changed cfg files and full backup diff was clean. Thirteen automated contracts passed. Original native fixture compiled/executed and analyzed by REA/Ghidra; both MCP handshakes/list-tools passed.

Known issues: native channel calibration, actual matched vehicle/setup specification, repeated driving baselines, damaged-wheel/reset/switch/AI coverage and performance profiling remain incomplete. ETK pilot stalled the engine at stop; choose stable shift/clutch method. All dynamics/FFB/racing/UI feature toggles are reserved and unimplemented. MCP registration works but tools require reconnect before appearing in this chat. No subjective wheel feedback yet.

Important discoveries: BeamNG 0.39.4.0.20972/build24617469 native extension route needs no DLL hooks. Primary profile has BeamMP/many mods and was left intact. ETK wheel temperatures stayed constant through the pilot; dynamic thermal support is not proved. Avoid the failing `-windowed` launch flag and quoted user-path pattern; unquoted no-space lab paths worked. AC 1.16.4/build14923034 exposes shared memory1.7. AC's prior race preset was online/modded; temporary offline stock overlays are mandatory. AC itself rewrites additional cfg files; back up the full cfg tree. Current Obsidian vault was verified from its open registration and `.obsidian`; no existing unrelated notes were changed.

Next actions: calibrate channels/coordinates/time and reset boundaries, freeze ETK `kc6_360_M` vs AC `bmw_1m` setup/controls, run five valid straight-line repeats then skidpad/thermal/damage tests. Investigate native temperature path before adding a model. Read Obsidian ACNG Dashboard/Current Status/recent session and check Git/runtime state on resume. See SETUP, R001/R002 and test summaries for proof/limits. No current user-dependent blocker; subjective FFB comes later.
