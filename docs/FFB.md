# ACNG Force Feedback (AC-style FFB controls)

ACNG FFB gives BeamNG's steering force the controls Assetto Corsa drivers expect. It is **OFF by default**. OFF means BeamNG force feedback exactly as you set it in Options > Controls.

| Row | What it does | Default |
|---|---|---|
| GAIN | Overall strength, 0-200 %. Scales BeamNG's own FFB strength. | 100 % |
| CAR | Strength for this car model only, saved per model, 0-200 %. Multiplies GAIN. | 100 % |
| MIN FORCE | Lifts small forces so a weak wheel does not feel dead around the centre, 0-30 % of the wheel's limit. | 0 % |
| FILTER | Smoothing, 0-100 %. STOCK keeps your own BeamNG smoothing setting. 50 % equals BeamNG's default (150). | STOCK |
| KERB | A buzz when a front tire is on a kerb (rumble strip). | 30 % |
| ROAD | Quick left-right load changes at the front wheels (bumps, road texture). | 50 % |
| SLIP | A buzz that grows as the front tires slide (understeer warning). | 30 % |

The steering force itself is still BeamNG's: the steering rack's real resistance, its smoothing, compression and limits. Tires, suspension, deformation and damage are untouched. Turning FFB OFF puts every stock value back exactly.

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG FFB**.
3. Click **OFF** so it turns **ON**. This also turns on the ACNG master switch.
4. Use the minus and plus buttons on each row. FILTER's **STOCK** button goes back to your own BeamNG smoothing.

The bar shows the steering force against the wheel's limit and turns red while the force is clipping (95 % of the limit or more). The note under it shows how often the force clipped over the last couple of seconds. At 5 % or more it says to lower GAIN or CAR, the same advice as AC's FFB clipping meter.

From GE Lua: `extensions.acng_core.setEnabled(true); extensions.acng_core.setFeature('ffb', true)`, then `setFFBSetting('gain', 1.2)` (also `min_force`, `filter`, `kerb`, `road`, `slip`; `setFFBSetting('filter', false)` is STOCK) and `setCarGain(nil, 0.8)` for the current car. `setFeature('ffb', false)` turns it off. Settings are saved with the other ACNG settings.

## How it works
- `acng_core` (GE) loads the vehicle extension `acng_ffb` into the player vehicle while the master and `ffb` are ON, unloads it when either goes OFF, and follows vehicle switches. A setting change calls `acng_ffb.configure(...)` with GAIN x CAR already multiplied.
- On load, `acng_ffb` saves BeamNG's FFB state from `hydros.lua`: `wheelFFBForceCoef`, `wheelFFBForceCoefLowSpeed` and `hydros.getFFBConfig()`.
- **GAIN** multiplies `wheelFFBForceCoef` and `wheelFFBForceCoefLowSpeed`, the same two fields BeamNG's own `inputTests.lua` scales, so the low-speed and high-speed force grow together.
- **FILTER** calls `hydros.setFFBConfig` with the stock config and a new smoothing value (filter x 300). STOCK restores the saved config.
- **MIN FORCE, KERB, ROAD and SLIP** go through `hydros.setExternalForce`, set every physics step from `hydros.testHook`. That hook runs just before BeamNG's FFB calculation with the same rack positions the stock force is made from, so ACNG knows the stock force exactly and never feeds back on last frame's output. Min force fades in over the first 0.5 units of stock force, so there is no step at the centre. The kerb and slip buzz run at 6-15 Hz and 10 Hz, slow enough to survive BeamNG's smoothing. The hook is installed only while one of these four is above 0.
- If you change BeamNG's own FFB strength or smoothing in Options while ACNG is ON, ACNG takes the new values as stock and reapplies on top. Turning ACNG OFF then leaves your new Options values in place.
- Unloading removes the hook, clears the external force, and writes the saved coefficients and config back.

## Verification
Offline: `tests/test_ffb.py` (12 LuaJIT tests of the vehicle extension against a fake `hydros`, and 5 of the `acng_core` wiring) and `tests/test_ffb_app.js` (the app view and its commands).

In game (FFB001 / T008, BeamNG 0.39.4, isolated lab profile; see `docs/test-results/T008-ffb.md`). The lab used BeamNG's virtual FFB wheel (`hydros.enableVirtualWheel`), which records the exact force BeamNG sends to a wheel at 200 Hz, on an ETK K-Series held at 15 m/s with a fixed steering angle:
- GAIN 100 % matched OFF within 1 % (force ratio 1.004); GAIN 150 % gave 1.51x the force.
- MIN FORCE 15 % lifted a small centre force from 0.30 to 1.16 units.
- FILTER 80 % set BeamNG smoothing to 240, and STOCK put the old value back.
- In a 20 m/s understeer (front slip about 4 m/s), SLIP 100 % made the force about 2.3x busier than SLIP 0.
- An Options strength change while ON (150, low 15) was followed (225 at GAIN 150 %) and kept on OFF.
- OFF and master OFF put every stock value back exactly, and six real app buttons reached the game.

## Limits
- **Feel needs a real wheel.** The lab measured the force sent to a virtual wheel; how it feels on a given wheel base has not been checked.
- KERB and ROAD are tested offline only. The lab had no kerbs and a flat grid.
- KERB detects BeamNG's rumble strip ground material (29). Kerbs painted as plain asphalt on some maps give no buzz.
- BeamNG's FFB test tool (`inputTests`) also uses `hydros.testHook`. If it holds the hook, ACNG leaves it alone, the app says so, and MIN FORCE and the effects stay off. GAIN and FILTER still work.
- BeamNG.tech's ADAS steering input (`tech/adasInput`) also writes `setExternalForce`. Do not run it together with MIN FORCE or the effects; the two would overwrite each other.
- GAIN scales BeamNG's strength setting before BeamNG's own compression and limit, like AC's gain. Very high GAIN clips; watch the meter.
