# Personal AC car conversion (BMW 1M)

The user asked on 2026-10-08 for their own Assetto Corsa BMW 1M as a drivable
BeamNG car that keeps BeamNG damage. This is a personal, local build. The output
contains the user's AC meshes and textures plus copies of their own BeamNG ETK
mesh files, so it **never goes into Git, the ACNG zip or any upload**. Both
converters refuse to write inside this repository.

## How it works

The physics stay BeamNG's own. The car is the stock ETK K-Series (`etkc`,
`kc6_360_M` config) with every node, beam, suspension, powertrain and damage
part kept. Only the visible skin changes:

1. `converters/kn5_model.py` reads the KN5 (v6) completely, with bounds checks,
   and puts every mesh in world space. Encrypted or unknown layouts are
   refused, not bypassed. `data.acd` is not touched.
2. `converters/export_kn5.py` routes each AC mesh to an ETK damage group
   (body, doors, hood, trunk, bumpers, front/rear lights, interior, steering
   wheel). It skips the AC wheels, suspension, brake discs, damage glass and
   the LOD cockpit. It converts the frame to BeamNG's, writes one Collada
   file and a BeamNG 1.5 materials file. Textures are written as DDS when
   BeamNG can read the format; AC's 24-bit, 16-bit and luminance-alpha DDS
   files become PNG. The body paint is BeamNG's colour picker under the AC
   decal/trim texture.
3. `converters/build_ac_car.py` copies the etkc JBeam, stretches it to the 1M
   wheelbase (2.588 to 2.660 m) and raises the roof by about 7 cm. Width is
   unchanged. It removes the ETK body and interior meshes and keeps the
   mechanical ones you can see in wheel wells and crashes. It binds the 11 AC
   meshes to the same damage groups as the parts they replace. So the AC hood
   deforms and detaches with the ETK hood's nodes, and so on. Paint colours
   come from the AC skins.

Run, with the output folder outside the repository:

```
python converters/build_ac_car.py --ac-car <assettocorsa>/content/cars/bmw_1m --beamng <BeamNG.drive install> --out <folder outside the repo>
```

That writes `<out>/acng_bmw1m.zip` (about 11 MB) and `build_report.json`. To
play it, copy the zip into the user's own `%LOCALAPPDATA%/BeamNG/BeamNG.drive/current/mods/`.
It appears as "BMW 1M (local)".

## Evidence

C001 (`docs/test-results/C001-ac-car.md`) ran in an isolated lab. It covered
spawn, AC meshes bound, driving, a crash into a parked pickup, a puncture, a
lost wheel, master OFF/ON and reset. Unit contracts are in
`tests/test_ac_car_converters.py` and use only synthetic data.

## Known limits

- Handling, weight and power are the ETK K-Series 360 M, not the real 1M or
  the AC car's data.
- The steering wheel mesh is static; there is no animated wheel yet.
- The wheels and rims are the ETK's, not the 1M's.
- Windows don't shatter (AC damage glass is skipped).
- The AC body sits on ETK nodes from a fitted transform. Panel gaps and
  wheel-arch fit are close, not exact.
