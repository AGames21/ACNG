# L001 — Passive observer reset/reload/switch

Build: BeamNG0.39.4.0.20972. Isolated SmallGrid; stock ETK `kc6_360_M`, then stock pickup. Master OFF, no dynamics changes. Test harness performs actual `be:resetVehicle(0)` and native vehicle replacements; no synthetic reset hook stands in for the game.

Before fix:354 received packets, only original ETK generation1 and normal-reset generation2. Same-model reload and pickup switch reused GE object18051, while replacing Vehicle Lua. Capture disappeared because the control plane polled only the unchanged object ID. Fresh log showed only one telemetry start; harness completed all operations.

Fix: handle native `onVehicleSpawned(id)` to reattach when an attached object is respawned. Issue a new GE capture identifier per attachment and include vehicle model in packets. Collector/analyzer include capture identity, object ID and reset generation, avoiding collisions when a new VM restarts its generation/sequence. Older packets without capture IDs remain readable. Capture IDs are scoped to the running GE session (wall-clock-second prefix + serial); they are not cryptographic/global UUIDs.

After fix:830 packets,0 malformed,0 sequence gaps,0 out-of-order. One GE object ID remained18051 while the trace contained:

| Segment | Model | Capture serial | Reset generation | Samples |
|---|---|---:|---:|---:|
| Initial | ETK | 1 | 1 | 174 |
| Normal reset | ETK | 1 | 2 | 180 |
| Same-model reload | ETK | 2 | 1 | 238 |
| Different-model switch | Pickup | 3 | 1 | 238 |

Exact group counts/hashes are in `l001-summary.json` (authoritative if early live previews differed). All three reader starts appear in the fresh log. Stop/detach ends capture; master remained OFF and no physics parameters were written. Sixteen automated tests passed, including sequence isolation and analyzer refusal to combine same-ID/new-VM streams.

Evidence: `l001-before-fix.events.json`, `l001-after-fix.events.json`; ignored raw traces `telemetry/runs/l001-before-fix.jsonl`, `l001-after-fix.jsonl`; original logs and screenshots remain workspace-local. Harness `real_time_s` is the sum of GE callback dtReal, not guaranteed uninterrupted host wall time across loading. Raw host monotonic timestamps are separate. Body/wheel damage, AI behavior, full performance profiling and cross-game calibration remain untested by L001.
