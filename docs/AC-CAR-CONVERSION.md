# Personal AC car conversions (BMW 1M, BMW M3 E92)

The user asked on 2026-10-08 for their own Assetto Corsa BMW 1M as a drivable
BeamNG car that keeps BeamNG damage. This is a personal, local build. The output
contains the user's AC meshes and textures plus copies of their own BeamNG ETK
mesh files, so it **never goes into Git, the ACNG zip or any upload**. Both
converters refuse to write inside this repository.

## How it works

BeamNG remains the chassis, suspension and damage authority. The fitted ETK
K-Series has separate interior flexbodies and native animated controls. Two
configs are supplied: the ETK powertrain baseline and a BMW specification target.
The converter reads the owner's installed assets locally:

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
   mechanical ones you can see in wheel wells and crashes. It binds exterior panels to their donor damage groups; splits the dashboard,
   cabin, front seats, shifter and boot; and adds four native control props.
   Each front seat uses a separate, breakable cosmetic cage. Chassis weights
   and front mechanical mounting positions stay native. So the AC hood
   deforms and detaches with the ETK hood's nodes, and so on. Paint colours
   come from the AC skins.

The one-command build, lab test and install is `python scripts/car_pipeline.py --install`;
see [Importing cars](CAR-IMPORT.md). The manual steps follow.

Run, with the output folder outside the repository:

```
python converters/build_ac_car.py --ac-car <assettocorsa>/content/cars/bmw_1m --beamng <BeamNG.drive install> --out <folder outside the repo>
```

That writes `<out>/acng_bmw1m.zip` (about 11 MB) and `build_report.json`. To
play it, copy the zip into the user's own `%LOCALAPPDATA%/BeamNG/BeamNG.drive/current/mods/`.
It appears as "BMW 1M (local)". For an evidence-gated installation, close BeamNG
and run `python scripts/install_car_normal.py --zip <out>/acng_bmw1m.zip
--test <isolated-profile>/acng-car-test.json --confirm-normal`. This requires a
completed C002 pass and the exact ZIP tested in that profile; backs up an existing
recorded car and mod database; and refuses conflicting copies.

On another PC, clone the repository, then run the same command with that PC's
Assetto Corsa and BeamNG paths (Python 3 and Pillow needed). The car zip is not in
GitHub Releases because it holds game assets; copying your own zip between your own
PCs over USB or your home network works too.

## Evidence

The current build has native RPM/speed/fuel/oil needles, three reflective
mirrors, BMW rim visuals, working lamps and clear glass. C004 passed 45/45 in an
isolated lab and is the installed version. See
[C004](test-results/C004-1m-lamps-glass-mirrors.md) for causes, checks and open items.

C001 (`docs/test-results/C001-ac-car.md`) ran in an isolated lab. It covered
spawn, AC meshes bound, driving, a crash into a parked pickup, a puncture, a
lost wheel, master OFF/ON and reset. Unit contracts are in
`tests/test_ac_car_converters.py` and use only synthetic data.

## Specifications config and evidence

The default `acng_bmw1m_M` config uses an original calibration of the native
powertrain. `acng_etk_baseline` retains donor engine, gearbox and fuel settings.
It shares the visual fit and new controls, so it is not an untouched stock-car baseline.

Targets come from [BMW's official specification sheet](https://www.press.bmwgroup.com/global/article/attachment/T0122670EN/178922):
2.660 m wheelbase, 250 kW, 450 Nm plus 50 Nm overboost, six forward ratios
4.110 / 2.315 / 1.542 / 1.179 / 1.000 / 0.846, reverse 3.727 and final drive 3.154.
The former proposed 4.055-series gearing was rejected because it differs from this sheet.
Front/rear tire sizes remain 245/35 R19 and 265/35 R19. A dedicated native
fuel tank has 53 L capacity and starts at 47.7 L (90%).

Native measurements and current validation are recorded in
[the C002 report](test-results/C002-1m-upgrades.md). This is a specification
approximation, not a reproduction of AC's handling or its complete engine curve.

## Known limits

- Healthy measured mass is about 1,533 kg, roughly 2.5% above BMW's 1,495 kg DIN
  figure. Uniformly reducing chassis weights reached 1,495 kg but immediately
  broke the front subframe. That change was rejected; no unsafe mass control ships.
- Peak output is approximately 249 kW and 507 Nm. The fixed torque curve does
  not simulate BMW's timed overboost or reproduce AC's transient engine behavior.
- Suspension geometry, spring/damper calibration, collision shell, aero and
  steering ratio remain donor approximations. Fitted wheelbase/roof do not make
  this an exact BMW chassis. No comparative acceleration/handling benchmark yet.
- The visible front bar/support is removed; moving the structural bumper
  inward was rejected during investigation. Hidden mechanical overhang can differ
  from the body. Panel and wheel-arch fit still needs a road playtest.
- Front seats are independently damage-attached; cabin trim still deforms with
  the body/floor. This is not a fully authored production-quality JBeam interior.
- Rims remain ETK. Windows do not shatter; mirrors and instruments are static.

## Suggested next features

Working dashboard needles and mirrors; BMW wheel visuals fitted to the existing
native hubs; then a repeatable road benchmark for brakes, steering and suspension.
Keep pressure/puncture warnings and optional roadside service on the freeroam
roadmap. See the maintainer's engineering notebook for prioritization.

## BMW M3 E92 (second car, 2026-10-10)

Built from the `bmw_m3_e92` profile in `converters/cars/` onto the same ETK K-Series donor:

```
python scripts/car_pipeline.py --car bmw_m3_e92 --install
```

- **Fit.** Wheelbase 2.761 m, roof raised to the AC roof line and a shorter nose. Tires
  are centred on the AC wheel pivots (front 0.758 m, rear 0.746 m from the centre line).
- **Powertrain.** The native ETK 4.4 V8 and 7-speed DCT, cloned and set to BMW's public
  figures: 309 kW at 8300 rpm, 400 Nm, 8400 rpm limiter, ratios 4.78 / 2.933 / 2.153 /
  1.678 / 1.39 / 1.203 / 1.000, 63 L tank, 250 km/h governed. The torque table follows the
  AC power curve after BeamNG's friction and exhaust terms are cancelled. Final drive is
  the native 3.154 part (BMW quotes 3.15).
- **Interior.** M3 gauges (rpm, speed, fuel, oil temperature), three native mirrors, steering
  wheel and two pedals. There is no animated gear lever because the car has paddles.
- **Sound.** AC V8 loops with the AC crossfades; idle at 1000 rpm to suit the idle
  recordings; AC gear-up and gear-down recordings through the ACNG shift-sound controller.
- **Look.** Default paint Monte Carlo Blue; solid colours use a non-metallic finish. The
  third brake lamp inside the tail-lamp mesh moves with the body. Floating brake calipers
  are unpainted grey.

C014 passed 53/53 in an isolated lab and is installed as "BMW M3 E92 (local)". See
[C014](test-results/C014-m3-e92-generic-carlab.md).

Known limits are the same kind as the 1M's: donor suspension, collision shell and steering;
measured mass 1,604.5 kg. The AC M3 rims sit on native 18-inch wheels and tires.

