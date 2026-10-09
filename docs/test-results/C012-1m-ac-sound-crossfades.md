# C012 - 1M sound follows AC's loop crossfades (built, game test pending)

Date: 2026-10-09. Build fix-011 (ZIP SHA256 e3ede788...), local, not released, not yet
run in a lab profile or installed.

## Fault

C011 playtest: around 2500 rpm the sound "switches to a different sound".

## Cause

A BeamNG `sfxBlend2D` crossfades linearly between neighbouring entries. With one entry
per AC loop, two different recordings played together across the whole gap between
them, and the idle loop was pitched up to 3.8x (650 to 2500 rpm) on its way there.
AC plays each loop alone over a wide band and fades to the next one over 400 rpm
(1200 rpm for the off-throttle idle).

## Fix

The fade windows and per-loop volumes were read from the user's own 1M bank metadata
(each loop instrument's fade curves and volume). Each loop now gets pitched copies at
both edges of the band where AC plays it alone, so BeamNG only mixes two recordings
inside AC's windows. Copy lengths are chosen so the tags are near-whole rpm and copies
of one loop stay in step. AC's volumes (0 to -4.5 dB) are baked into the WAVs.

| Set | Load | Crossfades (rpm) |
|---|---|---|
| Engine | off | idle-2000: 1200-2400, 2000-4000: 2600-3000, 4000-6000: 4000-4400, 6000-8000: 5600-6000 |
| Engine | on | idle-2800: 1600-2000, 2800-4000: 2800-3200, 4000-6000: 4000-4400, 6000-8000: 6000-6400 |
| Exhaust | off | idle-2500: 1800-2200, 2500-4500: 2600-3000, 4500-6000: 4400-4800, 6000-8000: 5600-6000 |
| Exhaust | on | idle-2500: 1600-2000, 2500-4000: 2600-3000, 4000-5500: 4000-4400, 5500-8000: 5600-6000 |

## Result

- Build output: 40 mono WAVs, 22.6 MB; blend tags within 0.3 % of AC's window edges.
- 222 Python tests pass.
- Not yet checked in game; how it sounds needs a player to listen.
