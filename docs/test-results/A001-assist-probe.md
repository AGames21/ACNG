# A001 native assist probe

Read-only probe that shows what ABS and traction control stock BeamNG cars really have, before ACNG Assists was written. Nothing is changed.

Setup:
- BeamNG 0.39.4 on Small Grid
- a fresh isolated lab profile
- game ABS setting (`absBehavior`): `realistic`

Harness `tests/beamng-assistprobe` (GE extension `acng_assistprobe`). It spawns ten stock cars in turn and reads, from the vehicle Lua:
- each wheel rotator's ABS fields
- the drivingDynamics controllers (CMU) and their configs
- any `esc` controller
- the engine's throttle factor electric name

Raw results: `a001-assist-probe.json`.

## Results
| Car | ABS (front / rear slip target) | Traction control | CMU TC slip (motor / brake) |
|---|---|---|---|
| etkc `kc6_360_M` | native, 0.2 / 0.13 | CMU | 0.12 / 0.10 |
| vivace `S_410q_DCT` | native, 0.2 / 0.15 | CMU | 0.30 / 0.20 |
| scintilla `gts` | native, 0.2 / 0.14 | CMU | 0.15 / 0.12 |
| etk800 `854_190d_A` | native, 0.2 / 0.12 | CMU | 0.12 / 0.10 |
| pickup `d15_4wd_A` | native, 0.18 all round | none | - |
| bx `200bx_type_l_M` | native, 0.2 / 0.13 | none | - |
| fullsize `stock` | native, 0.2 / 0.15 | none | - |
| covet `DXi_M` | **none** | none | - |
| bolide `350` | **none** | none | - |
| sunburst | did not spawn (wrong model name in the probe) | | |

What this means:
- **ABS is always the per-wheel ABS in `wheels.lua`**: `hasABS` and `slipRatioTarget` on each wheel rotator. The CMU's own ABS list (`absControl.wheelSettings`) was empty on every car.
- **Traction control is the drivingDynamics CMU**: the `tractionControl` supervisor (`isEnabled` true, `velocityOffsetThreshold` 10) plus the `motorTorqueControl` and `brakeControl` components, each with a slip threshold per wheel group. The brake threshold is about 0.8 of the motor one.
- **Five of the nine cars have no traction control at all**, and none of them has an `esc` controller.
- Every engine is `mainEngine`, a `combustionEngine` that multiplies throttle by the electric named `throttleFactor`. That electric is nil on every car, so ACNG can use it for its own traction control on cars that have none.

## Limits found
- The game ABS setting decides first. `off` disables every wheel's ABS whatever the car has; `arcade` forces ABS on every wheel.
- Changing a CMU car's drive mode can rewrite the TC settings.
- Yaw control (ESC) is part of the same CMU and is left stock by ACNG.
