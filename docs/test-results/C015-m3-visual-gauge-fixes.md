# C015 - M3 E92 visual fixes and rigid gauge needles

Date: 2026-10-10. Prepared against BeamNG 0.39.4 and source checkpoint 068e45d.
Builds: `bmwm3e92-fix-004` and `bmw1m-fix-015`, local only. No converted assets are in Git.
CarLab checks are unchanged (C014 evidence).

## Player report (M3, build fix-003)

Plate clipping into the boot lid; white round dots front and rear (four small and one big
on each bumper); seats and interior very white; gauge needles bouncing; a worn seatbelt
lying over the seat; the roof white and not paintable.

## Causes and changes

- **Gauge needles (diagnosis by Codex, GPT-6.1 Sol).** Each needle hung on its own
  0.15 kg sprung triangle (spring 40000, damping 24) tied to dash nodes, so engine and road
  vibration shook it. Needles now use the vanilla ETK reference nodes `f1l`/`f1r`/`f6l`
  with `baseTranslationGlobalRigid` and `baseRotationGlobal`, so they move with the body
  rigidly. Steering wheel and pedals keep their sprung mounts. Both cars.
- **White seats and trim.** AC multimap colour is diffuse x lerp(detail, 1, diffuse alpha).
  `INT_carbon` and `INT_skin_color` have a near-white diffuse whose alpha is below 0.5
  everywhere, so the tiled detail map (carbon weave, leather) is what AC shows. Such
  materials now export the detail map as base colour, with the UVs scaled by
  `detailUVMultiplier` (2.0 and 0.75).
- **White dots.** `CAR_stencil` meshes are real disc geometry (parking sensors and the
  tow-hook cover) whose diffuse is the paint's detail texture (flake noise only).
  Stencils that use the paint material's detail map as diffuse now become paint and keep
  their normal map.
- **Seatbelt.** `CINTURE_ON` (belt worn) meshes were inside the cabin group and slipped
  past the skip rule; they are now skipped first. The 1M already skipped its belt.
- **Plate.** The AC plate sits in a recess that is part of the body mesh, but it was bound
  to the boot lid group and settled into the recess at spawn, showing only its top half.
  New per-car `PLATE_GROUP` (M3: `etkc_body`) and plate y 2.193.
- **Roof.** Not a converter bug: the real E92 M3 has a bare carbon roof, and the AC model
  paints it with a carbon material. It now renders dark carbon instead of white (same
  multimap fix). A paintable roof would be a deliberate option.

## Verified offline

- 250 Python tests pass (new: rigid gauge props, detail-only multimap, stencil paint,
  belt skip); all Node suites pass.
- fix-004 contents: four gauge props on `f1l`/`f1r`/`f6l` with no gauge mount nodes;
  `INT_carbon` uses the carbon weave and `INT_skin_color` the leather; `CAR_stencil` is
  paint; no `CINTURE_ON` meshes; the plate flexbody is in `etkc_body`.
- M3 build SHA256: `52c86ecf65b3fda24011df60ca7654d9844698d52e28b8e1e3a6400a9c98d8af`.

## Native runs (M3)

- **ACNG-car-035: 53/53.** Plate fully visible; rear and front sensor discs in body
  colour; dash, seats and roof dark; no belt over the seat; needles stay on their pivots
  and the tachometer rises when revved. Idle jitter worst part 0.0015 mm
  (`pedal_throttle_x`) against 0.153 mm on `gauge_rpm_y` in ACNG-car-032; drive jitter
  worst 0.083 mm (`steer_y`) against 0.288 mm. No prop or jbeam errors in the log.

Installed in the normal profile; the installed hash matches the tested ZIP (52c86ecf...).

## Native runs (1M)

- **ACNG-car-036: 54/54** (`bmw1m-fix-015`, gauge change only). Needles move with the
  body; the gauges are no longer the worst jitter part (idle worst 0.0017 mm and drive
  worst 0.111 mm, both `steer_x`; ACNG-car-033 had `gauge_fuel_x` worst while driving).
  No prop or jbeam errors in the log. SHA256
  `0d83239588bd0f11e5538033020ff60b311708f84eec5a262c2d0cd454ee7937`.

Installed in the normal profile; the installed hash matches the tested ZIP (0d832395...).

## Open

The player's look at both cars in their own drive.
