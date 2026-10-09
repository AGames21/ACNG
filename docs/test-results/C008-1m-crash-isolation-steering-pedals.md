# C008 - 1M crash isolation, steering, pedals, paint and fitment

Date: 2026-10-08. BeamNG 0.39.4, fresh lab profile ACNG-car-021. Build fix-005,
local, not released.

## Changes tested

| User fault | Cause | Fix |
|---|---|---|
| Steering wheel turns the wrong way | Prop rotation sign | Sign fixed |
| Foot rest acts as the clutch | Pedal picker took the leftmost pad, which is the dead pedal | Pads picked by X position; the foot rest is static trim |
| Panels stretch into spikes | Lamp and hood triangles far from their node group | Far lamp triangles rerouted to the nearest panel group; front knee in the Y map |
| Paints look odd | Our own paint setup, not BeamNG's | BeamNG's solid and metallic presets; orange-peel detail normal; baked AO kept; clean paint names |
| Lamp glow missing | 4x4 glow PNGs skipped by the cooker | Glow maps are 16x16 minimum |

## Result

47/47 checks passed. New lab steps:

- **Steering:** steering input +0.3 (right) turned the left front axle from 0.0 to
  -9.0 degrees (clockwise from above, so the car steers right). The cabin wheel
  turned clockwise about 153 degrees.
- **Pedals:** with clutch and brake held, both pads move. The foot rest does not move.
- **Crash isolation:** after the second crash, each panel group was shown on its own.
  Lamps, front bumper and hood are clean. The **fenders** and the front of the
  **body** still show sawtooth spikes on black inner parts: the arch liner and
  engine-bay structure. From outside the car, only a black flap at the front-left
  corner shows. The fender mesh had vertices up to 0.51 m from the fender nodes.
- **Fitment:** tire centres measured |x| 0.770 front and 0.805 rear. The AC wheel
  pivots are at 0.754. The rear tires stuck out about 51 mm per side and the fronts
  about 16 mm. Wheelbase and ride height match AC.
- Interior movement: 0.001 mm at idle, 0.11 mm while driving.
- The 16x16 and global-variable warnings are gone. Two mip-chain warnings remain,
  on a 512x256 tail-glow texture and the 64x64 display glass.

Fixed next in C009: track and fender liner.
