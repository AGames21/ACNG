# C010 - 1M declared wheel track (installed)

Date: 2026-10-08. BeamNG 0.39.4, fresh lab profile ACNG-car-023. Build fix-007
(ZIP SHA256 bf6af5de...), local, not released. Includes the C009 fender-liner fix.

## Change tested

| User fault | Cause | Fix |
|---|---|---|
| Wheels stick out past the arches | `.pc` set `$trackwidth_*`, but no part declared it, so BeamNG ignored it (see [C009](C009-1m-wheel-track-fender-liner.md)) | Our rim parts declare `$trackwidth_F/R` (Alignment, 0.20-0.32 m, defaults 0.2438/0.254); rim bindings unchanged at +/-0.51 front, +/-0.50 rear |

## Result

49/49 checks passed.

- `tires_centred_on_ac_wheels`: tire centres |x| 0.7538 front and 0.754 rear,
  matching the AC pivots (0.754). In C009 they were 0.770 and 0.805.
- Rear and wheel-well shots: tires and rims sit flush inside the arches.
- `front_wheels_steer_right`: the left front axle turned from 0.0 to -8.9 degrees
  for steering input +0.3.
- Crash isolation is the same as C009: the fender no longer shows the liner
  sawtooth, and the full-car wreck looks normal.
- Interior movement: 0.002 mm at idle and 0.11 mm while driving. Peak speeds: crash
  21.7 m/s, second crash 20.4 m/s.
- One log warning remains: the mip chain on the interior display glass texture
  (dash work is paused).

Track width is now adjustable in the Tuning menu under Alignment.

Installed in the normal profile after an automatic backup; the installed hash
matches the tested ZIP.
