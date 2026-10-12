# T009d tire heat lab (TireHeat)

Harness `tests/beamng-tireheat` (GE extension `acng_tireheat`), `-Experiment TireHeat`, each run in a fresh isolated lab profile. Stock ETK K-Series `kc6_360_M` on Small Grid, BeamNG 0.39.4. T009b proved the heat model on the same circle; T009d checks what the HUD shows (surface temperature and cold, window or hot state) and gives film cues for a tire temperature clip. Summary: `t009d-tireheat.json`; the raw files stay outside Git.

## Sequence
1. Load Small Grid with the master OFF and sample.
2. Master and `tire_temperature` ON, Sport profile (window 75 to 105 C), and sample: every tire cold.
3. Circle right for 55 s at 10 m/s with half steering lock, sampling every second.
4. Drive straight for 20 s at 18 m/s, holding the heading with steering.
5. Stop, then `tire_temperature` OFF and sample.

The harness writes `/acng-film-cues.json` (`drive_start`, `circle_end`, `drive_end`, `complete`) for `tools/film_lab.py`.

## Results
Run 1 (hidden): **15/15**. Run 2 (filmed): **15/15**. No helper errors. Both runs give the same temperatures to 0.1 C except the straight end (44.2 and 43.8 C).

| Check | Runs 1 and 2 |
|---|---|
| Master and tires OFF by default; tire model not loaded while OFF | pass |
| Heat ON with Sport loads the model; every tire starts cold | pass |
| Outer front heats by 30 C or more (FL 15 to 115.7 C) | pass |
| Load side is 20 C or more hotter than the inner front (FR 37.8 C) | pass |
| The outer front reaches the window | pass |
| The straight cools the hot tire (115.7 to 44.2 C in 20 s) | pass |
| HUD state matches the window in all 300 tire samples | pass |
| Grip written is heat x pressure x damage (300 samples, worst 0.002, none lagging) | pass |
| OFF unloads the tire model | pass |

Left front surface temperature and HUD state, by time from the start of the drive:

| t (s) | 5 | 10 | 15 | 20 | 30 | 37 | 45 | 55 | 60 | 65 | 75 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| FL (C) | 27.5 | 48.2 | 66.1 | 79.5 | 97.6 | 105.5 | 111.3 | 115.7 | 90.3 | 69.9 | 44.2 |
| State | cold | cold | cold | window | window | hot | hot | hot | window | cold | cold |

The left front enters the window at 19 s and goes hot at 37 s. The straight starts at 55 s, and the tire is back in the window within 5 s and cold again after 10 s. The other tires stay cold throughout: the inner front reaches 37.8 C, the rears 64.5 C (RL) and 36 C (RR). The circle end matches T009b (FL 116 C).

## Filming
Run 2 was recorded with `python tools/film_lab.py --experiment TireHeat --clip heat=drive_start:circle_end --clip cool=circle_end:drive_end --clip drive=drive_start:drive_end`. It gave three clips at 1920x1080 and 60 fps: `heat` 58.1 s, `cool` 23.0 s and `drive` 78.1 s. The left front tile reads 16 C cold, 110 C HOT, then 68 C cold. There is no menu, no account name and no stock app. The tire tiles are small at full frame, so the showcase edit needs a zoomed inset of the HUD. Video stays in the lab folder, outside Git.

The first TireDirt clip still showed the stock speedometer. BeamNG re-adds any app from its original layout that has an `appVersion` unless the user layout's `removedApps` lists it. `film_lab.py` now reads `<BeamNG>/settings/ui_apps/originalLayouts/default/freeroam.uilayout.json` (lenient JSON) and marks every app in it removed, keeping the original version. This clip was the first with that fix.
