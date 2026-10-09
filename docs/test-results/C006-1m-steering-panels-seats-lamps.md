# C006 - 1M steering frame, panel groups, seats and patterned lamps

Date: 2026-10-08. BeamNG 0.39.4, isolated lab profile ACNG-car-018. Local build, not released.

## User-reported faults (C004 playtest) and causes found

| Fault | Cause | Fix |
|---|---|---|
| Steering wheel moves strangely while turning | Column frame assumed 20 degrees up; the AC `STEER_HR` node is 22 degrees down, so the turning axis was about 42 degrees off | Pivot and axis taken from the AC node (rest rotation 112) |
| Front seats, belts, sill trim and rear side fabric jiggle | Seat classification caught sill trims, belts, B-pillar plastics and rear fabric and hung them on light spring cages | Only seat shells ride the native ETK seat nodes; cages removed (about 4.8 kg) |
| Crash mesh stretches, overlaps and tears | Body and door flexbodies spanned several panel node groups | One node group per outer panel; front fenders split onto the ETK fender groups |
| Black part at the front wheel well | Native ETK wheel-well tubs stayed visible | Tubs stripped |
| Brake lamps look flat | One flat emissive level | Glow follows the lens texture pattern; tail 8000, brake 30000 nits |

## Native result (fresh profile ACNG-car-018)

45/45 checks passed. The user touched the lab window during the run; the drive,
crash and reset checks still passed and the numbers match a clean run.

- Mass 1,529.9 kg, 2.3% above the 1,495 kg reference (C004: 1,534.7 kg).
- Interior movement against the dash: idle 0.96 mm worst, driving 0.15 mm worst
  (C004: 0.71 / 1.37 mm).

Shots reviewed: wheel upright with logo while steered, no dark lip in the front
wheel well, patterned brake and tail lamps, fender and hood crumple in the crash
with no stretched or torn polygons (new close-up `crash_side_FL`).

Installed in the normal profile after a backup; installed hash matches the tested ZIP.

## Decided with the user

- No roadside assistance.
- No tire pressure/puncture warning (offered as a dash lamp; declined).
