# C016 - 1M headlamp functions (DRL, low beam, high beam)

Date: 2026-10-10. BeamNG 0.39.4. Build `bmw1m-fix-016`, local only. No converted assets are in Git.

## Player report

Daytime running lights never showed on the 1M, while on the M3 they work. On the 1M the light
modes did not show on the headlamps: high beam just made everything brighter.

## Cause

Cross-referencing the two build reports: the M3 profile maps its three AC front lamp meshes to
three BeamNG functions (`FRONT_LIGHT_LOW` headlight, `FRONT_LIGHT_HIGH` highbeam,
`FRONT_LIGHT_POSITION` position, which glows on `drl` and `lowhighbeam`). The 1M module default
mapped every `front_light*` mesh to `headlight` (glow on low beam at 0.49, high beam at 1). So
the 1M had no DRL glow at all, and high beam only raised the brightness of the whole lamp.

The 1M headlamp has three meshes:
- `front_light_1` (Dettaglio_Faro): the corona rings and accents, now `position` (DRL and
  low/high beam)
- `front_light_2` (FANALI_Anteriori): the outer projector lens, now `headlight` (low beam,
  brighter on high)
- `front_light_3` (Dettaglio_Faro): the inner lamp, now `highbeam`

Glow materials are keyed per material and function, so the meshes that share Dettaglio_Faro
still get separate lit copies.

Everything else that differs between the two build reports is car-specific (gauges, sounds,
clutch pedal, detail bakes, nose triangle rerouting), not a missing feature on the 1M.

## Lab

CarLab `ACNG-car-037`: 55/55. It is one check more than C015 because of the new high-beam
signal check. CarLab now also takes a `lights_drl` shot (lights state 0, DRL on) and a
`lights_high` shot (state 2) beside the low-beam shot.

- DRL: only the rings light.
- Low beam: the rings and the outer projector.
- High beam: the inner lamp lights too.

Daylight screenshots, so the difference is visible but subtle. Installed in the normal profile;
the installed hash matches the tested ZIP.

Open: the player's look at night.
