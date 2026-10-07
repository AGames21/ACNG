# B002 — Five stock ETK acceleration/braking repeats

Build: BeamNG0.39.4.0.20972; ETK `kc6_360_M`, SmallGrid, master OFF, factory assists unchanged. Arcade acceleration/autoshifts; realistic braking with clutch depressed. Native safe teleport explicitly establishes the same spawn after vehicle initialization; eight simulation seconds settle, then three seconds held-brake/clutch before launch. No tire/force/structural parameters are changed.

First set (`001`) completed but is provisional: replaceVehicle retained previous positions despite requested transform; starts spanned about1495m. Do not use it as an identical-start comparison. Fixed set (`002`) passed the actual-position gate: largest start spread0.0001083m (about0.11mm),4019 received packets,0 malformed/lost/out-of-order;45second post-sample idle termination worked. Engine remained running after each stop.

| Metric | Median | Five-run min–max |
|---|---:|---:|
| 0–60 mph | 4.6639s | 4.6581–4.7047s |
| 0–100 mph | 9.9346s | 9.8910–9.9847s |
| 60–0 mph time | 2.2509s | 2.2317–2.6366s |
| 60–0 mph distance | 29.9170m | 29.7361–30.1872m |
| 100–0 mph time | 3.7869s | 3.7843–4.1722s |
| 100–0 mph distance | 85.3955m | 85.2640–85.8395m |

Movement/stop threshold0.1m/s; distances integrate sampled speed. Maneuvers are explicitly delimited by the recorded B002 launch/brake controls, including the preceding sample for crossings. This avoids an earlier warm-up stopping crossing becoming the braking endpoint. Reporter rejects incomplete runs, missing captures, damaged wheel flags, loss and start spread over0.05m.

Interpretation: acceleration repeatability is tight within this control protocol. Braking time is sensitive near the0.1m/s stop threshold; distance spread is much smaller proportionally. Do not attribute the time spread to tire grip without a stop-tail experiment. This is a stock BeamNG protocol baseline, not AC equivalence or a standardized manufacturer performance claim.

Open calibration: actual running mass/fuel, tire setup/pressure scale, alignment/gearing/aero, sensor filtering/signs, physical path distance, damage regression and profiling. Native temperature getters stayed constant in the earlier pilot; active thermal behavior remains unresolved. No new tire/FFB/assist model is implemented.

Evidence: `b002-stock-five-002.json` (per-run/aggregate/raw hash/receiver counts), `b002-stock-five-002.events.json`, screenshot. Ignored raw `telemetry/runs/b002-stock-five-002.jsonl`; first provisional set retained. Original logs stay workspace-local. Twenty-one automated contracts pass. Source/protocol verification does not substitute for missing damage/AI/FFB/performance tests.
