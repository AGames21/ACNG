# C014 - BMW M3 E92, car profiles, generic CarLab and shift sounds

Date: 2026-10-10. Prepared against BeamNG 0.39.4 and source checkpoint 54c1b0b.
Builds: `bmwm3e92-fix-003` and `bmw1m-fix-014`, local only. No converted assets are in Git.

## Changes

- **Car profiles.** Per-car values moved out of the converter modules into
  `converters/cars/<car>.py` (see [CAR-IMPORT.md](../CAR-IMPORT.md)). The 1M profile is
  empty because the module defaults are the 1M. A 1M build after the refactor was compared
  with the pre-refactor build: 186 ZIP entries, 0 differences.
- **Second car: BMW M3 E92 (DCT).** AC `bmw_m3_e92` fitted to the ETK K-Series (wheelbase
  2.761 m, roof and short nose), with the native ETK 4.4 V8 cloned to public BMW figures:
  309 kW at 8300 rpm, 400 Nm, 8400 rpm limiter, 7-speed M DCT ratios 4.78 to 1.000,
  63 L tank, 245/40 and 255/40 R18 native sport tires, 250 km/h governed. Idle is 1000 rpm
  because the AC idle loops were recorded near 1170 rpm.
- **Generic CarLab.** The build writes the car's targets to `acng_car/<model>.json` in the
  ZIP; CarLab reads them (the 1M without one keeps its built-in table). Mass, power,
  torque table, gearing, final drive, fuel, top speed, wheel track, control and gauge
  counts are checked per car. The installer accepts C014 for any car whose model matches
  the tested ZIP and keeps one install record per car.
- **Shift sounds.** BeamNG's native lever controllers play shift sounds with
  `playSFXOnceCT`, which accepts only FMOD events or profiles. A WAV path there is never
  heard; the 1M's C013 runs logged "unable to create sfx source as the profile was not
  found" on every shift (45-51 lines in labs 027 and 028). New original controller
  `converters/vehicle_lua/acng_shiftSound.lua` plays the AC `gearup` / `geardn`
  recordings through a file source (`createSFXSource2`, then cut, play, and stop after the
  recording's length). It compares each engaged gear with the last engaged one, so an
  H-pattern 3-N-2 counts as a downshift. The build copies it to
  `vehicles/<model>/lua/controller/`. New check `shift_sounds_play_on_gear_changes`:
  during the top-speed run, the controller must fire at least once per gear change.
- **CarLab fix.** A vehicle-Lua long string closed early on `]]`; it now uses `[=[ ]=]`.

## Verified offline

- 247 Python tests pass (new: `tests/test_car_profiles.py`, generic install proof); all
  Node suites pass. Lua syntax was checked with a Lua 5.1 parser for CarLab and the
  controller, including the vehicle-Lua strings embedded in CarLab.
- Build SHA256: `27c32eb0c4b96ae6c55a042d08286a601978e6d4e4a9da0c101447ebd229752a`.

## Native runs (M3)

- **ACNG-car-029:** stalled; CarLab failed to load because of the long-string bug above.
- **ACNG-car-030: 51/52.** Everything passed except `verified_final_drive`: the native
  `etk_finaldrive_R_315` part measures 3.154, and the target said BMW's 3.15. The target
  is now the part actually used (0.1 % apart; the 1M uses the same part).
- **ACNG-car-031: 52/53** with the shift controller. `shift_sounds_play_on_gear_changes`
  passed (6 plays up to 6th gear, no "profile was not found" lines in the log); final
  drive failed again because that ZIP still carried 3.15.
- **ACNG-car-032: 53/53.** Measured: 1,604.5 kg (target 1,605), 309.0 kW and 400.0 Nm at
  4000 rpm, worst torque-curve error 0.001 Nm, ratios 4.78 / 1.000, final drive 3.154,
  63 L. Limiter: wheel speed 250.0 km/h with controller throttle cut to 0.37-0.39, ground
  speed 248.5. Both shift recordings opened as sound sources. Front and rear tires centred
  on the AC wheels; crash, isolation, puncture, reset and master OFF/ON checks passed.

Installed in the normal profile; the installed hash matches the tested ZIP (27c32eb0...).

## Native runs (1M)

- **ACNG-car-033: 54/54** (`bmw1m-fix-013`). The controller fired 5 times up to 5th gear,
  and the native lever still moved. The log had one warning: `link target not found:
  acng_shiftSound/soundNode: > nodes/f7 ... DATA DISCARDED`. The 1M's manual lever part
  has no node `f7` (on the M3 it belongs to the automatic selector), so the sound played
  from node 0. The 1M now uses `sh_b3`, the manual lever's own sound node.
- **ACNG-car-034: 54/54** (`bmw1m-fix-014`, SHA256
  `6bd56bbe74d7afe7f1dcfd09fad8250634e03d11cf52e9876ccce16001ce88f9`). There were no link
  warnings and no "profile was not found" lines. The controller fired 5 times up to 5th
  gear. Limiter peak was 248.4 km/h (ground) and the worst torque-curve error 0.018 Nm.
  The native FMOD gear-in / gear-out clicks are kept.

Installed in the normal profile, replacing the C013 build; the installed hash matches the
tested ZIP (6bd56bbe...).

Lab checks prove the sounds load and fire. How the car sounds and drives still needs a
player to listen and drive.
