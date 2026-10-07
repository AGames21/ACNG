# ACNG status

Updated:2026-10-07 (America/Chicago). M1 independent/default-OFF mod foundation validated; M2 telemetry/oracle active. No physics tuning.

Working: passive BeamNG UDP and AC existing shared memory, original analysis/plot/quality reports, isolated deployment/launch/backups, master lifecycle/reload/reset identity, Obsidian handoff, Universal Modder/REA/Ghidra toolchain smoke. All production physics writes remain0.

Latest evidence: D00100214 checks/2,487 packets/no reported loss, native collision damage/FL puncture/wheel break/repair;23 automated tests pass. B002002 five actual same-start stock ETK repeats remain valid (4019 packets; starts within0.11mm). AC clear BMW1M/ks_drag/drag2000 trace5881 samples/max110.0936mph, full cfg restored; **full-brake acceptance fails** at native brake0.8053/0.8798. Single acceleration/braking measurements and clock/channel ranges saved, not matched reference claims.

Known gaps: native AC brake meaning, controlled repeated AC baselines, running setup/mass/fuel/tires/assists, unit/filter/frame/reset calibration, quantitative body-node/bent-alignment/detached-wheel/AI/performance coverage. All dynamics/FFB/assists/racing/UI models unimplemented. BeamNG native temperatures were constant in earlier traces; thermal activation unknown. Native lap/host ratio1.0001575/max17ms residual only applies to recorded AC maneuver.

Safety: primary BeamNG profile untouched; isolated scene only. AC cfg fully backed/restored after every owned offline session. Current saved AC original preset was online/modded; never launch it for experiments. No proprietary game assets/code committed, no native game binary decompiled, no push. Both games/jobs closed. MCP backend stopped; registered tools require client reconnect.

Next: targeted native AC brake/assist experiment; documented useful fields; five controlled fresh drag starts and matched setup. Then stop-tail calibration, quantitative native deformation and overhead/AI checks, thermal research before original tire-force implementation. No external blocker currently. See D001/R005 and machine reports for evidence/limits. Read Obsidian dashboard/status/latest session and inspect Git/runtime state on resume.

Latest source checkpoints:0f476d0 AC drag quality gates;3ceb4d3 acknowledged native damage/repair;68173c4 D001 harness. Repository and Obsidian status mirrors backed up; latest documentation-only commit may follow these.
