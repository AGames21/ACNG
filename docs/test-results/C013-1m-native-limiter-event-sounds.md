# C013 - BMW 1M native limiter and event sounds (installed)

Date: 2026-10-09. Prepared against BeamNG 0.39.4 and source checkpoint 7d974ad.
Build: fix-012, local only. No converted assets are in Git.

## Changes

- Make the 250 km/h target explicit on the cloned engine via native `vehicleController.topSpeedLimit` (250 / 3.6 m/s); select stock ETK's 250 ECU limiter in the spec config. Inspection found that C012 already selected that ECU part. This is an explicit default plus regression coverage, not proof of a previously missing limiter.
- Clone the native donor turbo and manual shifter; preserve their mechanical settings. Map the owned `turbo` and `flutter_4` recordings to `whineLoopEvent` and `bovSoundFileName`.
- Map `gearup` / `geardn` to native H-pattern gear-in / gear-out hooks. These are entering/leaving a gear, not directional upshift/downshift detection.
- Export `bmw_6cyl_limiter` locally for investigation. No standalone rev-limiter sample hook was found in the installed combustion-engine, sound or controller Lua. It is **not connected to playback**; no unsupported field or custom production controller was added. Existing native RPM limiting remains unchanged.
- Preserve donor additive EQ compensation after selecting the cloned turbo.

## Verified offline

- 225 Python tests pass; all 10 Node suites pass.
- C013 CarLab harness compiles with LuaJIT. Installer rejects missing/failed C013 feature evidence and still verifies the exact tested ZIP hash.
- External build succeeds: 45 WAVs and the two engine/exhaust blend files.
- Compared to installed C012: all 42 existing audio files are byte-for-byte identical; mainEngine physics and engine/exhaust sound settings are identical.
- Build SHA256: `46362c4d6939f5d706a2f1c8e1e3a873677e5588319b2f36099f18330263c744`.
- Publication audit passes before staging; Git has no converted assets.

## Native runs

C013 keeps the previous 50 checks and adds four: the 250 km/h target is configured, the
turbo and blow-off files and the gear-in/out files are configured and open as native audio
sources, and the car holds 250 under full throttle with the controller cutting throttle.

**ACNG-car-027: 53/54.** The limiter worked (wheel speed 249.9-250.2 km/h, controller
throttle cut to 0.44-0.47 at full pedal), but the check measured ground speed against
248-252, and ground speed settles at 247.9 because the tires slip about 1 % at 250. The
check now holds wheel speed (what the limiter governs and the speedometer shows) to
248-252 and ground speed to at least 245.

**ACNG-car-028: 54/54** with the same ZIP. Final samples: wheel 250.0-250.2 km/h, ground
247.9, controller throttle 0.45-0.52; ground-speed peak 248.3. All four event files
loaded as sound sources. That proves the files open; how they sound in play still needs
a player to listen.

Installed in the normal profile after an automatic backup; the installed hash matches the
tested ZIP (46362c4d...).
