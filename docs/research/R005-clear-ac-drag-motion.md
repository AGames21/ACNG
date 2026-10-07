# R005 — clear AC straight-line oracle

Question: can an offline stock AC route provide real acceleration/braking data without the pit barrier or replay-only native benchmark?

Observed on AC1.16.4/build14923034, shared memory1.7: the installed `ks_drag/drag2000` stock UI declares2000m and two pitboxes. An original temporary offline single-car race overlay (`TYPE=3`, `SPAWN_SET=START`, `LAPS=1`) starts BMW1M on the clear drag lane. Native memory confirmed BMW1M/ks_drag/LIVE; layout is supported by the temporary config and screenshot, not the current200-byte static prefix. Stock launcher session constants were inspected locally; no native decompilation was needed.

Unattended Universal Modder input: measured Drive button client48,164; DirectInput scan mode; hold Up14s then Down7s. Native physics channels, rather than key durations, delimit the maneuvers.120s capture accepted5,881 samples, no reported duplicate/incoherent/inactive polls, max110.0936mph. Screenshots before/after show the straight lane; peak native acceleration-vector magnitude1.4045g. No pit-barrier event was observed. The current prefix lacks a damage channel, so this is not proof of zero damage in every subsystem.

Single-run measurements using host monotonic time:0–60=4.8562s,0–100=11.0401s;60–0=2.9403s/37.4613m;100–0=4.6138s/97.2050m. **Not an accepted full-brake reference:** native brake values at the60/100mph descending crossings were0.8053/0.8798 despite a held brake key. Whether these are pedal filtering, keyboard behavior, ABS output or another native convention remains unresolved. Do not infer tire friction from differences against BeamNG. The reporter deliberately fails that full-brake quality gate and retains the measured values.

For this motion window, native lap elapsed / host elapsed=1.0001575; max lap/host residual17ms. This supports near-real-time behavior for this run, not a universal physics clock identity. Sample median gap16ms/max32ms reflects Windows polling cadence; requested50Hz is not a fixed physics-step sample rate.

Observed native core temperatures: FL20→23.0943, FR20→23.0835, RL20→24.0213, RR20→24.0157; pressures34.0400→34.5351/34.5334/34.6834/34.6825 respectively; wear remained100. These are measured native values; pressure/wear semantics and heating/grip relationships still require evidence. First motion trace's temperature change had collision contamination; this trace supports heat evolution during clear straight driving/braking, without identifying individual heat sources.

The launcher closed only its owned PID and restored all original cfg bytes; manifest verification found no new files. Machine-readable measurements and evidence hashes: `docs/test-results/ac-grid-straight-001.json`; raw/config backups/input record remain private under workspace `work/ac-grid-001`. Production ACNG still performs zero physics writes.

Confidence: high for live identity/crossings/config restoration; medium for route cleanliness/lap-clock agreement within this trace; low for brake channel interpretation. Next: targeted ABS/keyboard channel experiment, extended SDK-documented damage/assist fields if available, controlled repeat starts, matched running setup/assists/tires and mass before cross-game tuning.
