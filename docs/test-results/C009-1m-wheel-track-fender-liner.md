# C009 - 1M wheel track, fender liner and steering direction

Date: 2026-10-08. BeamNG 0.39.4, fresh lab profile ACNG-car-022. Build fix-006
(ZIP SHA256 8e29a470...), local, not released.

## Changes tested

| User fault | Cause | Fix |
|---|---|---|
| Panels stretch into spikes | The fender mesh includes the inner arch liner, up to 0.51 m from the 12 fender nodes | Far fender triangles (374 per side) move to the body group |
| Tires stick out past the rear arches | Track narrowed through `$trackwidth_*` in the `.pc` | Did not work, see below |

## Result

48/49 checks passed. New checks:

- `front_wheels_steer_right`: **pass**. Input +0.3 turned the left front axle from
  0.0 to -9.0 degrees.
- `tires_centred_on_ac_wheels`: **fail**. Tire centres were still |x| 0.770 front
  and 0.805 rear, the same as C008.

Crash isolation after the second crash:

- The fender on its own no longer shows the sawtooth liner. The liner now moves
  with the body and stays a smooth panel.
- The full-car shots look like a normal BeamNG wreck.
- The mip-chain warnings seen in C008 did not appear in this fresh profile.

Interior movement: 0.001 mm at idle and 0.13 mm while driving. Peak speeds: crash
21.6 m/s, second crash 20.4 m/s.

## Why the track did not change

Our ETK suspension sets the wheel slot to
`case($trackwidth == nil, $trackoffset + 0.26/0.305, $trackwidth)`. BeamNG only
applies a `.pc` variable that some part declares, and none declared
`$trackwidth_*`. So the `.pc` value was ignored, and has been since C003. Tires and
rims both sat at offset + 0.51/0.50, which is 16 mm (front) and 51 mm (rear)
outboard of the AC pivots at 0.754. `$trackoffset_*` could not be used instead:
it is clamped to -0.02...0.05, and the rear needs -0.051.

Fix for C010: our rim parts declare `$trackwidth_F/R` (Alignment, 0.20-0.32 m),
and the original 0.2438/0.254 now apply.
