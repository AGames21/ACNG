# R004 — Moving telemetry calibration: first evidence

Question: do the two native readers provide useful changing channels during actual stock motion, and which conventions can be compared?

BeamNG0.39.4.0.20972: B002 first five-repeat ETK capture completed,4995 packets, no reported loss. It is **provisional**, because native vehicle replacement retained prior transform despite requested position/rotation. First positions spanned about1495m longitudinally. Native safe teleport is being tested to enforce identical starts; do not tune against the first aggregate as an approved reference.

Observed: velocity aligned with the native direction vector (moving median cosine0.999925). In1514 full-throttle samples, derivative-of-world-velocity projected onto that direction was negatively correlated with native acceleration sensor index1 (correlation−0.917, fitted slope−0.901). Sensor axes0/2 had near-zero correlation. This suggests negative sensor-Y longitudinal m/s² for this intact straight-line configuration; filtering/time alignment and gravity projections remain unresolved. No universal/damaged-frame normalization is implemented.

AC1.16.4/shared-memory1.7: explicitly offline BMW1M/Magione, original keyboard overlay and FFB gain0. User input was idle for more than60seconds immediately before focus. Universal Modder clicked Drive and sent Up4seconds, Down2.5seconds using DirectInput scan mode, then released keys. The launcher sent no inputs itself; external input provenance is recorded separately.4396 accepted samples in90host seconds, no incoherent/duplicate/inactive polls reported. Speed reached17.6889m/s (39.57mph); gears neutral/first/second observed.

The car hit a pit-exit barrier. Screenshot and native acceleration-vector peak10.2138g provide collision evidence. **This is collision-contaminated motion sanity, not a clean acceleration/braking baseline.** Raw core temperatures changed from20 to20.272/20.277 front and21.018/21.026 rear. These readings demonstrate changing native thermal channels under this combined motion/wheelspin/collision history; they do not identify a grip-vs-temperature law or separate heat sources. Pressure/slip/wear units and wheel ordering still require controlled setup/loading tests.

Evidence: `docs/test-results/ac-keyboard-001.json`; ignored raw `telemetry/runs/ac-keyboard-001.jsonl`; workspace screenshots `work/ac-keyboard-menu.png` and `ac-keyboard-after.png`. AC full cfg and primary BeamNG settings backup diffs both remained clean after restoration. No installed game file was edited, and no reader wrote forces or proprietary code was extracted.

Confidence: high for identity, live motion, temperature changes, collision and recovery. Medium for native BeamNG direction/longitudinal-sensor convention in this experiment; low for uncalibrated cross-game physical semantics. Next choose a clear start/grid area for AC motion and verify identical BeamNG starts, then damage/time/pressure/steering tests.
