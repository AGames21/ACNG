# C004 - 1M wheel, lamps, glass, mirrors and steady interior

Date: 2026-10-08. BeamNG 0.39.4, isolated lab profiles only. Local build, not released.

## User-reported faults and causes found

| Fault | Cause (evidence) | Fix |
|---|---|---|
| Steering wheel upside down, logo missing | Prop `baseRotationGlobal` X used the right-hand sign; BeamNG turns the other way (stock md_series -21, sunburst2 -20.8). Wheel sat ~140 degrees off | Negate the rest rotation (-70 for the column) |
| Green glass | AC glass texture is olive (29,31,10) and relied on AC's shader | Neutral grey base colour, AC opacity kept |
| Blue/green square on right rear quarter | AC fuel-door material keeps its cutout in the normal-map alpha; converter ignored it and applied that map as a normal map | Use normal-map alpha as opacity for those materials, drop the bogus normal map |
| Tail lights look lit when off | Bright albedo on red lenses | Unlit lenses dimmed to 45% |
| Headlights/tail lights do nothing | No `glowMap` for the converted lamp materials | Native on/off emissive materials and glowMap entries (head, tail, brake, CHMSL, reverse) |
| Mirrors do not reflect | Custom material instead of the stock reflective one | Stock `mirror` material |
| Seats/interior jiggle | Cosmetic cage beams at about 2% of critical damping | About 15% damping at the original node weight |

## Native result (fresh profile ACNG-car-016)

45/45 checks passed, including spawn without damage, drive without self-damage,
crash, puncture, wheel loss, master OFF/ON on the wreck and reset.

- Lamp glowMap entries registered: 6. Low beam and brake light signals on: yes.
- Interior node movement relative to the dash, per frame: idle 0.71 mm worst
  over 91 frames, driving 1.37 mm worst over 211 frames.
  Chassis reference pair: 0.002 mm idle, 0.09 mm driving.
- Healthy mass 1,534.7 kg, 2.7% above the 1,495 kg reference (limit 3%).
- Auto tire compound picked `sport` for the 1M's stock tires.

Shots reviewed: wheel upright with BMW logo, gauges readable and moving, clear
glass, side and interior mirrors reflecting, plain fuel door, rear lamps visibly
brighter when on. Daylight shots cannot show headlight beams; a night check is
still worth doing.

## Test fixes made during this run

- The jitter probe crashed on nameless nodes and reported 0 mm, so its first two
  "passes" were invalid. The probe now skips nameless nodes, copies coordinates
  before comparing, and the checks fail if nothing was measured.
- Only the first screenshot saved: later `createScreenshot2` jobs were unknown to
  the stock screenshot module. Shots now use `screenshot.createScreenshotTracked`.
- In arcade gearbox mode a held brake at rest selects reverse. The light check now
  switches to realistic mode first.
- Heavier mounts tried first (0.8/0.3 kg nodes) pushed mass to 3.4%; reverted to
  0.3/0.15 kg and raised damping instead.

## Open

- Thin dark lip at the top of the front wheel arch: probably native ETK wheel-well
  tubs at the arch edge. Not confirmed as the reported "black part sticking out".
- Lower-body "jiggle" was not reproduced at idle or while driving at these
  thresholds; needs the user's description of when it happens.
