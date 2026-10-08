# Optional Spa and pit services

The user requested Spa and an Assetto Corsa car investigation on 2026-10-08.
Freeroam remains the default; this is an optional track workflow with native
BeamNG AI and no automatic opponents.

Spa should be installed as a separate author-distributed map, not bundled with
ACNG. The older Kunos Spa port has reported failures after BeamNG 0.34. The
newer author release is being evaluated:
https://www.beamng.com/threads/spa-francorchamps-2026-free.111407/
Its author prohibits reuploading and modifying map parts without permission.
ACNG pit functionality must therefore be an independent overlay.

Pit service contract: explicit opt-in, marked service location, stopped vehicle,
simulation-time service duration, cancellation on departure, vehicle switch or
master OFF. Refueling must use native fuel storage. Tire service must preserve
broken wheels, punctures and chassis damage. Never reset/respawn a vehicle to
simulate a pit stop. Unsupported service reports unavailable.

Car investigation: the installed AC BMW 1M is a candidate reference. An AC mesh
alone is not a BeamNG vehicle. A driveable conversion also requires original
JBeam structure, mechanical systems, materials, collision and damage validation.
Extracted assets stay outside Git and outside ACNG distribution packages.

## Implemented pit services (P001 passed in an isolated lab)

`lua/vehicle/extensions/acng/pits.lua`, core lifecycle wiring and the existing
control panel's Advanced > Pits tab implement a session-local 4 m service box.
Mark it while stopped in a garage, choose services and start the countdown.
Refueling takes 20 simulation seconds; tread-only service takes 8. Combined
service takes 20. Moving above 0.2 m/s, leaving the box, vehicle switch/reset,
cancel or master OFF cancels remaining work. No automatic AI, repairs or respawns.

Fresh tread resets ACNG's accounting on intact tires only; it does not physically
replace wheels, set tire temperature or inflate punctures. Broken, deflated or
unavailable wheels refuse tread service. Refueling fills supported liquid fuel
tanks through native `setRemainingVolume`; leaking/unknown tanks and batteries
are refused. Native APIs and wheel flags were checked against local BeamNG
0.39.4 source. Sources stay in the game installation, not ACNG.

Offline evidence: 140 Python/Lua tests and existing six Node app suites passed
2026-10-08. New contracts cover timing, cancellation, master lifecycle, damage,
leaks, unsupported vehicles, tread/heat preservation and callback-safe commands.
Mocks do not prove game behavior. The P001 native harness lives under
`tests/beamng-pitlab`, not distributed; run only in a fresh isolated profile:
`scripts/launch-lab.ps1 -Experiment PitLab -LabUser <fresh>/ACNG-pit-NNN/current`.
It refuses to launch while normal BeamNG is running.

In game, P001b passed 13 of 13 on 2026-10-08 (see
`docs/test-results/P001-pit-service.md`): real panel clicks, native tank 5 to
50 L, tread 0.867 to 1.0, a native puncture refuses tread service and stays flat,
and master OFF unloads pits and tires without repairing anything. Spa-specific box positioning and presentation
also require the map download and a live load.

## External dependency

The author-linked [Spa 2026 download](https://buymeacoffee.com/gheolei/e/570029)
is free, but its zero-price checkout requires the user's name and email. No
contact details were transmitted, no purchase was made and no map downloaded.
User handoff is pending. The author permits download/use, while prohibiting
reuploads/map editing without permission; never include this map in ACNG's ZIP.

## AC BMW 1M feasibility evidence

`converters/inspect_kn5.py` is an original read-only bounded inventory tool based
on the community format documented by
[RaduMC](https://github.com/RaduMC/kn5-converter). It validates header/version,
texture lengths, material indices, hierarchy, triangle indices and complete
consumption. It fails unknown/encrypted layouts rather than bypassing protection.

Observed: the locally installed BMW 1M KN5 v6 was read completely (42,192,644
bytes): 166 meshes, 109,079 triangles, 74 embedded textures. Inventory/hash is
ignored `.local/bmw-1m-mesh-inventory.json`. No meshes/textures were exported and
no car was installed. Geometry readability has high confidence; a working
BeamNG car remains unproven. Original JBeam, conversion to BeamNG mesh/material
formats, drivetrain/suspension, interior/LOD alignment, crash and performance
checks remain. Any extracted assets must stay outside this repository and its
packages. The inspected Blender add-on's header/layout did not match this local
file; do not call its empty fallback output a successful conversion.
