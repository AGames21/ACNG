# P002 Spa pit lane

Setup:
- 2026-10-08, BeamNG 0.39.4
- the user's own Spa 2026 download (`Gheo_Spa_2026`), placed only in a fresh isolated lab profile by `scripts/launch-lab.ps1 -ExtraMod`
- harness `tests/beamng-spalab` (GE extension `acng_spalab`), master OFF at start (checked)

The harness loads Spa at its `SpawnSphere_Pit` spawn and puts a stock ETK K-Series (`kc6_360_M`) there. It switches ACNG on through the real control panel and turns on Road tire heat. It creeps straight down the pit lane at about 9 km/h for 5 s, then runs the P001 pit service through the real panel buttons.

**Result: 18 of 18 checks passed. No ACNG errors in the lab log.**

| Item | Value |
|---|---|
| Spa load time | 8.96 s |
| Car at pit spawn, resting on the ground | yes |
| Pit-lane creep | 10.8 m, peak 2.39 m/s, 0 damage, 166 fps |
| Tires on Spa | Road profile, all values finite |
| Pit box marked in the Spa pit lane | yes, car stopped in the box |
| Fuel | 5 L to 50 L (full) |
| Tread after service | 1.0 on all four |
| Service message | "Service complete; damage and tire heat preserved" |
| Master OFF | pits and tires unloaded, zero physics writes |

Earlier attempts (not counted) hit the pit wall. Driving straight from the spawn meets a wall after about 18 m because the lane curves, and Spa's AI road graph has no road within 8 m of the spawn. The harness therefore only does a short straight creep. Driving the full pit lane is left to a user playtest.

Not tested: Spa racing, AI, lap timing on Spa, or a pit box placed automatically from the map. The map is never copied into the repository or the ACNG zip; its author prohibits reuploads and edits.

Raw summary: `P002-spa-pit-lane.json`.
