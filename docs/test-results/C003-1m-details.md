# C003 - Native 1M instruments, mirrors and rims

Status: **offline checks passed; native validation pending**. The normal profile
still has the previously verified C002 car. Do not install a C003 build without
its complete, passing native result and an exact package hash match.

## Changes under test

- Four native props: RPM, road speed, fuel and oil temperature. Needle origins
  come from the local model's transform nodes, not their bounding boxes.
- Three native mirror cameras and independently bound mirror surfaces. Material
  names begin with `mirror_`; atlas UVs are normalized per face. Detailed Mirrors
  is enabled only in the isolated lab, leaving player graphics settings alone.
- Four BMW rim meshes on cloned native rim parts. The tire, pressure-wheel,
  braking, suspension, wheel-breaking and node-weight tables stay native.
- Explicit front/rear wheel offsets align the new visual rim centers to the
  local model. Both configurations use these wheels; powertrain remains separate.

## Verification

170 Python tests pass. Synthetic tests cover pivot conversion, active routing,
mirror UV range, native damage attachments, unmodified rim physics tables and
the installer's C003 evidence gate. Local build completes outside the repository.

The C003 lab checks the eight native props, their live electrics, three actual
mirror camera objects and four bound rims, then repeats spawn, driving, crash,
puncture, wheel loss, master OFF/ON and reset checks. It records instrument
screenshots at idle, revved and driving states. Inspect these before installation.

## Limits and research confidence

The gauge mapping is an original approximation of the visible dial markings:
256 degrees for 0-8,000 RPM and 0-300 km/h, 100 degrees for fuel, and Celsius
input mapped to the oil dial's 160/250/340 Fahrenheit markings. It has not been
validated against an AC instrument sweep. The digital LCD and warning lamps
remain static. Native mirror aim and rim placement still need visual verification.

The car's chassis/collision-shell and suspension approximations documented in
[C002](C002-1m-upgrades.md) remain. This work does not establish matched handling.

References: [BeamNG props](https://documentation.beamng.com/modding/vehicle/sections/props/),
[mirrors](https://documentation.beamng.com/modding/vehicle/sections/mirrors/) and
[mirror workflow](https://documentation.beamng.com/modding/vehicle/vehicle-art/materials/mirror-workflow/).
