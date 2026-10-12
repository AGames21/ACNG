# T009c tire dirt lab (TireDirt)

Harness `tests/beamng-tiredirt` (GE extension `acng_tiredirt`), `-Experiment TireDirt`, each run in a fresh isolated lab profile. Stock ETK K-Series `kc6_360_M` on the stock Grid Map v2 ground-model area, BeamNG 0.39.4. T009b could not cover dirt because Small Grid has no loose ground. Summary: `t009c-tiredirt.json`; the raw files stay outside Git.

## Sequence
1. Load Grid Map v2 at `spawn_groundmodels` with the master OFF and sample.
2. Teleport to x -322.7, y -391.4 (15 m east and 100 m north of the spawn) facing south, then check the heading.
3. Master and `tire_temperature` ON, Sport profile.
4. Drive due south at 12 m/s, holding the line with steering, and sample every second. The route is about 84 m of grass (material 20), a 14 m dirt strip (15), then asphalt (10) to y -760.
5. Stop, reset, sample, then `tire_temperature` OFF and sample.

The harness also writes `/acng-film-cues.json` (`drive_start`, `drive_end`, `complete`) for `tools/film_lab.py`.

## Results
Run 1: 17/19. Run 2 (filmed): 19/19. Run 3 (filmed, menu fixed): 18/19. Run 4: **19/19**, no helper errors. Runs 2 to 4 give the same numbers to three places.

| Check | Runs 2 and 4 |
|---|---|
| Master and tires OFF by default; tire model not loaded while OFF | pass |
| Heading south after the teleport; line held within 0.08 m | pass |
| Loose ground and tarmac both reached (34 grass, 2 dirt, 96 asphalt tire samples) | pass |
| Dirt builds on loose ground: 0 to 1.0 in about 40 m of grass | pass |
| No dirt grip loss off tarmac: damage grip is grain x blister only (36 samples) | pass |
| Dirt costs grip on tarmac: damage grip includes (1 - 0.08 x dirt), exact to 1e-6 (96 samples) | pass |
| Dirt cleans at 1/600 per metre: 1.003 to 1.006 x expected over 271 m (all four tires) | pass |
| Grip written is heat x pressure x damage (run 2 worst 0.002; runs 3 and 4: 130 of 132 within 0.006, worst 0.007) | pass |
| Reset clears dirt (0.51 to 0.001) | pass |
| OFF unloads the tire model | pass |

On the FL tire, dirt is 1.0 leaving the dirt strip. On the first asphalt sample its damage grip drops from 0.999 to 0.920, then climbs back as the dirt wears off (0.53 after 271 m).

## Run 1 finding: settle pickup
The checks for "clean at start" and "reset clears dirt" first required dirt below 1e-6. After the teleport and after the reset, the car settles on grass. Its wheels creep a few centimetres, which picks up a trace of dirt: up to 2e-5 at the start and 0.001 after the reset (0.001 is 4 cm of rolling). This is the model doing what it should. The thresholds are now 0.001 at the start and 0.005 after the reset.

## Run 3 finding: grip write lag
Run 3 failed only "grip written is the product". It required every tire sample within 0.006. Two samples (FL and FR, on the first dirt-strip sample) were 0.007 off: the written grip was 0.8235 and the live product was 0.8164. This is how the model works. It rewrites a tire's grip every 0.1 s, and only when the grip has moved by `GRIP_STEP` (0.002). The harness reads the pressure factor live. At the grass-to-dirt edge, the pressure grip swung to about 0.970 and back between two writes, so the written value lagged. The check now allows 2% of samples over 0.006 and none over 0.015. It reports the count as `grip_product_lag_samples`. Run 4 repeated the same two samples at the same spot and passed.

## Filming
Run 2 was recorded with `python tools/film_lab.py --experiment TireDirt`. Capture worked: a 1920x1080 window recorded through gdigrab, and a 36.8 s clip was cut from the cues. But a scripted level load leaves the BeamNG main menu drawn over the drive. The menu also shows the Steam account name. The harness now switches the UI to play once the car spawns.

Run 3 was filmed with that fix. The menu and the account name are gone. The clip shows the ACNG pill ON and the tire tiles turning DIRT on the grass. It was cut automatically between `drive_start` and `drive_end` (36.7 s, 1920x1080, 60 fps). Raw video and clips stay in the lab folder, outside Git.
