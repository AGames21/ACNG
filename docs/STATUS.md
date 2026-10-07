# ACNG status

Updated: 2026-10-07 (America/Chicago).

Current milestone: M1 foundation smoke validated; M2 telemetry/oracle active. No physics tuning.

Current working features: real BeamNG independent-mod load, default-OFF master lifecycle, passive wheel/vehicle telemetry, UDP collection, crossing/distance analysis, chart generation, isolated deployment/launch, offline AC read-only shared-memory capture, full cfg backup/restoration. Durable Obsidian ACNG memory includes linked status, decisions, research, vehicles, test interpretations and session handoff; updates are backed up.

Last successful tests: real same-ID reset/reload/switch lifecycle now captures all segments (830 packets, no reported loss); corrected five-repeat ETK stock protocol4019 packets, starts within0.11mm, no loss;21 automated contracts pass. Median0–60 is4.6639s,0–1009.9346s,60–0 distance29.9170m,100–0 distance85.3955m. AC keyboard motion4396 samples reached39.57mph and exposed changing core temperatures, but hit a pit barrier; excluded from clean comparison. Both games closed; primary BeamNG settings and AC cfg backup diffs clean.

Known issues: matched setup/running mass, native units/filtering, clean AC benchmark route, handling/damage/AI/performance coverage remain incomplete. Braking time spread is sensitive at the0.1m/s stop threshold; investigate before grip attribution. Earlier B002001 retained old spawn transforms and is provisional;002 verifies native safe teleport. Same-ID observer reload and braking stall are solved by tested reattachment/capture IDs and clutch-depressed test protocol. All dynamics/FFB/racing/UI models remain unimplemented. MCP tools require reconnect; no subjective wheel feedback yet.

Important discoveries: BeamNG 0.39.4.0.20972/build24617469 native extension route needs no DLL hooks. Primary profile has BeamMP/many mods and was left intact. ETK wheel temperatures stayed constant through the pilot; dynamic thermal support is not proved. Avoid the failing `-windowed` launch flag and quoted user-path pattern; unquoted no-space lab paths worked. AC 1.16.4/build14923034 exposes shared memory1.7. AC's prior race preset was online/modded; temporary offline stock overlays are mandatory. AC itself rewrites additional cfg files; back up the full cfg tree. Current Obsidian vault was verified from its open registration and `.obsidian`; no existing unrelated notes were changed.

Next actions: calibrate channels/coordinates/time and reset boundaries, freeze ETK `kc6_360_M` vs AC `bmw_1m` setup/controls, run five valid straight-line repeats then skidpad/thermal/damage tests. Investigate native temperature path before adding a model. Read Obsidian ACNG Dashboard/Current Status/recent session and check Git/runtime state on resume. See SETUP, R001/R002 and test summaries for proof/limits. No current user-dependent blocker; subjective FFB comes later.
