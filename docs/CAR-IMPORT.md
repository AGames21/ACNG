# Importing cars from other games

How ACNG turns a car you own in another game into a drivable local BeamNG car, what
is automated, what changes for a new car, and which games can be sources.
The BMW 1M write-up is [AC-CAR-CONVERSION.md](AC-CAR-CONVERSION.md).

## What an import is

The other game supplies the look and the sound. BeamNG supplies everything physical.

- **Imported:** body, interior and light meshes, textures, paint colours, engine,
  turbo, blow-off and gear sounds, and published specifications such as gearing,
  torque curve and top speed.
- **Native BeamNG:** chassis, suspension, damage, tires, gauges, mirrors, plate,
  brakes and controls. They come from a stock donor car (the ETK K-Series for the 1M)
  that is reshaped to the imported car's wheelbase and roof.

The imported meshes are attached to the donor's damage groups, so doors, hood and
bumpers still dent and fall off natively. The source game's physics are never
converted. They only serve as a reference for specifications.

## Rules (from AGENTS.md)

- Use only a copy you own and have installed. The converter reads the files where
  they are installed.
- Use only readable, unencrypted formats. Encrypted or unknown layouts are refused,
  never decrypted or bypassed. `data.acd` is never touched.
- Output goes outside this repository. It is never committed, attached to a Release
  or uploaded. The converters refuse to write inside the repo.
- Badges, logos and plates that name the source game are removed.
- Nothing is installed in your normal profile until a fresh isolated lab run passes
  every check on the exact ZIP being installed.

## The automated path (one command)

Close BeamNG, then run:

```
python scripts/car_pipeline.py --install
```

The script does four things:

1. **Build:** runs `converters/build_ac_car.py` into the next `ACNG-car/bmw1m-fix-NNN`
   folder in the workspace.
2. **Lab:** starts the CarLab harness in the next fresh `ACNG-car-NNN` profile with
   that exact ZIP.
3. **Wait:** follows the lab stages, then stops only the lab game it started.
4. **Report and install:** prints every check and writes `pipeline_summary.json`
   beside the ZIP. With `--install`, it hands the tested ZIP to
   `scripts/install_car_normal.py`, which backs up and verifies hashes.

Other options:

- Leave out `--install` to only build and test.
- `--zip <file>` tests an existing ZIP instead of building one.
- `--skin <name>` picks the default paint.

The script refuses to start while any BeamNG is running.

Two steps are still manual:

- **Listening and driving.** Lab checks prove that the sounds load and the systems
  work. They cannot judge how the car sounds or feels.
- **Evidence and notes.** Add a `docs/test-results/CNNN-*.md` report and update
  `docs/STATUS.md` and `MODLOG.md`.

## Pipeline stages

| Stage | Code | Generic or per-car |
|---|---|---|
| Read the source model | `converters/kn5_model.py` returns `{textures, materials, nodes, meshes}` in world space | Generic for any AC KN5 v5/v6 |
| Route meshes to panels | `export_kn5.route()` sorts meshes into body, doors, hood, bumpers, lights, interior and so on | Mostly generic. It relies on AC's usual node names (`DOOR_L`, `MOTORHOOD`, `FRONT_BUMPER`, `WHEEL_`...) plus some 1M material and mesh names |
| Fit the donor | `build_ac_car.py` `tf_y`/`tf_z`, `MESH_LIFT` | **Per car:** wheelbase stretch, roof raise, front overhang knee, ground offset |
| Bind to damage | `FLEXBODIES` table, lamp, fender and nose rerouting in `car_upgrades.py` | The table is generic; the zone limits are **per car** |
| Interior and controls | `car_upgrades.prepare_model`, `car_details.prepare` (seats, pedals, steering wheel, gauges, mirrors) | **Per car:** seat box, pedal positions, gauge and mirror frames |
| Specifications | `car_upgrades.py` (gear ratios, final drive, torque table, top speed, fuel tank) | **Per car**, from the maker's spec sheet and the source game's data |
| Wheels, brakes, plate | `car_details.py` (track, brake disc sizes, plate position) | **Per car** |
| Sound | `car_sounds.py` reads the FMOD bank, extracts loops and events, and copies the source game's crossfade windows and volumes | Bank reading is generic; `AC_LAYOUT` and the idle rpm are **per car** |
| Package | ZIP writer in `build_ac_car.py` (stores incompressible files so BeamNG reads them) | Generic |
| Lab | `tests/beamng-carlab` (spawn, drive, crash, puncture, reset, gauges, mirrors, lamps, mass, torque, sound, limiter) | Generic checks; the target numbers are **per car** |
| Install | `scripts/install_car_normal.py` | Generic logic. The model name is currently fixed to `acng_bmw1m` |

## Adding another Assetto Corsa car

Today the per-car values are constants in the converter files, written for the 1M.
For a second car, the plan is to move them into one car profile file per car
(for example `converters/cars/<car>.json`). `build_ac_car.py --car <profile>`
would then build any car that has a profile.

That refactor should happen together with the second real car. Each value has to be
checked against an actual model in the lab, and doing it blind would risk breaking
the working 1M.

For a new car, fill in:

1. **Donor.** Choose a stock BeamNG car with the same layout and similar size
   (front or rear engine, driven wheels, body style). The ETK K-Series suits
   compact rear-drive coupes.
2. **Fit.** Find the wheel centres in both cars, then set the stretch, roof and
   overhang values and the ground offset. Run `converters/inspect_kn5.py` on the KN5
   to read its node tree and sizes.
3. **Routing.** Check the KN5's node names against `route()`. Add the car's light
   materials and any odd names.
4. **Interior.** Set the seat box, pedal x positions, steering column, gauge needle
   names and the mirror meshes.
5. **Specs.** Use the maker's official sheet for gearing, power, torque, mass, tires,
   fuel tank and top speed. Use the source game's engine data to shape the torque curve.
6. **Sound.** Decode the bank's loop rpm tags, crossfade windows and volumes into
   the car's sound layout. Map the turbo, blow-off and gear events.
7. **Identity.** Set the vehicle name, brand, years, default config, paint finish
   per skin and plate position.
8. **Lab targets.** Set the expected mass, torque table and top speed, then run the
   pipeline until every check passes.

Each of the 1M's issues produced a fix the next car inherits. Examples are brake
centring, the loop tagging that caused the 2500 rpm sound jump, panel tearing at
damage-group borders, and the BeamNG ZIP read bug. Expect a new car to take a few
lab cycles, far fewer than the 1M needed.

## Other games, including Forza

A new source game needs two new readers:

- a **model reader** that returns the same `{textures, materials, nodes, meshes}`
  structure as `kn5_model.read()`, and
- optionally a **sound reader** that returns loops with their rpm tags.

Routing, fitting, damage binding, packaging, lab and install are reused unchanged.
A source qualifies only if its files are in a readable format that isn't encrypted.
Examples are community mods released with permission in open formats such as FBX
and OBJ, or games that store cars unprotected the way AC stores KN5.

**Forza (Horizon and Motorsport): not possible under the project rules.** Forza
car models and sounds ship in protected, encrypted game archives. Getting them out
means decrypting or bypassing that protection, and the game's terms forbid it.
ACNG refuses encrypted sources, the same way it never touches AC's `data.acd`, so
there will be no Forza reader. If Forza cars ever become legitimately available in
an open format, adding them would only take a new model reader as described above.
