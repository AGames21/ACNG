# ACNG Assists (ABS and traction control levels)

ACNG Assists lets you pick ABS and traction control (TC) levels separately, the way Assetto Corsa does. Both are **OFF by default**, which means FACTORY: the car stays exactly as BeamNG built it.

| Choice | ABS | TC |
|---|---|---|
| FACTORY | the car's own ABS, untouched | the car's own TC, untouched |
| OFF | no ABS: the wheels can lock | no TC: the driven wheels can spin |
| 1 | ABS on, slip target 25 % (late, least intervention) | TC on, cuts above 25 % slip |
| 2 | ABS on, slip target 18 % | TC on, cuts above 15 % slip |
| 3 | ABS on, slip target 12 % (early, most intervention) | TC on, cuts above 8 % slip |

For comparison, stock cars use ABS slip targets of 12 to 20 % and TC thresholds of 12 to 30 % (A001).

Brakes, tires, suspension, deformation and damage stay BeamNG's own. Going back to FACTORY puts every stock value back exactly.

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG Assists**.
3. Click a level on the ABS or TC row. Picking a level also turns on the ACNG master switch. FACTORY turns only that assist back off.

The light at the end of each row glows while that assist is working. The line under each row shows the slip target, or a note when something overrides the level (see Limits).

From GE Lua: `extensions.acng_core.setEnabled(true); extensions.acng_core.setAssistLevel('abs', 2); extensions.acng_core.setFeature('abs', true)`, or `'tc'` for traction control. `setFeature('abs', false)` goes back to FACTORY, and `setEnabled(false)` turns everything off. Levels are 0 (OFF) to 3, and the default level is 2.

## How it works
- `acng_core` (GE) loads the vehicle extension `acng_assists` into the player vehicle while the master is ON and `abs` or `tc` is ON. It unloads the extension when both are OFF or the master goes OFF, and it follows vehicle switches. A level or flag change calls `acng_assists.configure(abs, tc)` instead of reloading. The chosen levels are saved with the other ACNG settings.
- On load, `acng_assists` saves the stock values: each wheel's `hasABS` and `slipRatioTarget`, and, on cars with a drivingDynamics CMU, the TC switch and the slip threshold of each wheel group.
- **ABS** uses the native per-wheel ABS in `wheels.lua`. A level sets `hasABS` and `slipRatioTarget` on every wheel that has a tire. OFF clears `hasABS`. Then `wheels.setWheelBrakeUpdate` re-picks each wheel's brake function, the same call BeamNG makes on spawn. The game ABS setting is never changed. ABS levels also work on cars that were built without ABS, because every wheel carries BeamNG's ABS brake function.
- **TC on CMU cars** (A001: etkc, vivace, scintilla, etk800) uses the native traction control. A level sets the `motorTorqueControl` slip threshold, sets the `brakeControl` threshold to 0.8 of it (the stock ratio), and turns the `tractionControl` supervisor on. OFF turns the supervisor off.
- **TC on cars without one** (A001: covet, pickup, bx, bolide, fullsize) runs a small ACNG controller. Every frame it measures the driven-wheel slip: the fastest driven wheel's surface speed against the average of the undriven wheels (against airspeed when every wheel is driven, and never below 3 m/s). It smooths that over 0.05 s and sets the engine's own `throttleFactor` electric to `1 - 3 x (slip - threshold)`. The value never goes below 20 %, drops at once and recovers at 3 per second. BeamNG's engines multiply the throttle by that electric. It is nil on stock cars, and ACNG sets it back to nil when it stops.
- Cars that use the older `esc` controller keep their own TC. ACNG does not touch it.
- The app sends each button as one Lua expression, because BeamNG's UI bridge wraps commands that have a callback as `guihooks.trigger("onBNGAPICallback", id, <command>)`. Several statements there give a fatal Lua error.
- After a vehicle reset the levels are put back 0.25 s later, in case a controller reloaded its settings.

## Verification
Offline: `tests/test_assists.py` (23 LuaJIT tests of the vehicle extension), `tests/test_assists_app.js` (the app), and `tests/test_assists_bridge.py`, which runs every app command inside BeamNG's UI callback wrapper.

In game (T006e, BeamNG 0.39.4, isolated lab profile, 26 of 26 after one criterion change; see `docs/test-results/T006-assists.md`):
- ETK K-Series: ABS OFF locked the wheels in 95 % of braking frames and stopped from 100 km/h in 42.1 m; ABS 2 stopped in 36.3 m (factory 35.1 m). TC OFF spun the wheels in 42 % of launch frames; TC 3 in 13 % (factory 17 %).
- Bolide (no stock ABS or TC): ABS 2 cut the stop from 49.1 to 41.5 m. ACNG's TC 3 cut the mean launch slip from 1.06 to 0.21 and wheelspin from 59 % to 9 %, and the car was slightly faster at 5 s.
- Gavril Grand Marshal (no stock TC): TC 3 cut wheelspin from 58 % to 7 %.
- FACTORY and OFF put every stock value back exactly on all three cars, and five real app buttons reached the game.

Not yet checked: how it feels to drive, corners, other surfaces, and physical mouse clicks.

## Limits
- The game ABS setting (Options > Gameplay) decides first. With it at **Off**, no level can switch ABS on; with it at **Arcade**, ABS stays on every wheel even at OFF. The app shows a note for both. Use **Realistic** (the default).
- Changing a CMU car's drive mode can rewrite its TC settings until the next level change or reset.
- Yaw control (ESC) and the other CMU stability systems stay stock.
- ACNG's own TC only cuts power; it does not brake a spinning wheel.
- Bare rotators without a tire keep their stock ABS values.
