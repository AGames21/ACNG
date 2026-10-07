# R003 — Can stock AC benchmark provide an unattended physics oracle?

Question: can AC's native performance benchmark produce moving live physics without OS input takeover?

Build: AC1.16.4 / Steam14923034. Local stock launcher UI was inspected narrowly: its benchmark action sets the race configuration `BENCHMARK/ACTIVE` switch. Original offline launcher overlaid that switch with REMOTE inactive; cfg backed up/restored, no stock install edits or injected input.

Observed: requested BMW1M/Magione was superseded by native benchmark Mercedes SLS GT3/Spa. Graphics shared memory reported status1 (replay). Screenshot showed cockpit playback; no live status2 ever appeared within the60-second observation window. Collector did not accept replay as a live run. Full cfg backup diff after restoration was clean.

Conclusion: this installed built-in benchmark is unsuitable for the live physics oracle. It is not an equivalent BMW1M test or a validated source of dynamic tire forces. Evidence: `docs/test-results/ac-native-benchmark-001.json`; private screenshot in workspace `work/ac-benchmark-001.png`. Auto HDR was enabled, so screenshot color is not a presentation-quality reference.

Confidence: high for observed identity/status/replay rejection and config restoration. No claim about all alternative AC automation methods. Next investigate a narrowly controlled offline live session; avoid focus/input while the user is active. BeamNG scripted tests can proceed independently.
