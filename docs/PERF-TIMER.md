# ACNG Performance Timer

A drag-strip style timer app, original to ACNG. Stop the car, launch, and it times:

- **0-60 mph and 0-100 mph** (km/h mode: **0-100 and 0-200 km/h**)
- **1/4 mile** time with trap speed
- **60-0 mph / 100-0 km/h** stopping distance (feet in mph mode, metres in km/h mode)

Each row shows **LAST** and **BEST** for this vehicle this session. A row lights up yellow while it belongs to the run in progress.

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG Performance Timer**.
3. Click **OFF** so it turns **ON**. This is the ACNG master switch, which still defaults to OFF every session.
4. Come to a complete stop. The status line reads **READY**. Launch: timing starts the moment the car moves.
5. Braking distance is recorded whenever you are braking as you pass 60 mph (or 100 km/h) and come to a stop. Pressing the throttle cancels that stop.

**MPH/KM/H** switches units. **RESET** clears this vehicle's results. **ON/OFF** is the master switch.

## How it measures
- The timer runs inside the vehicle's own Lua and reads only BeamNG's native ground speed, brake and throttle values. It writes no controls, forces or physics (`physics_writes=0`).
- It uses simulation time, so pausing or slow motion does not distort results. Crossings are interpolated within a physics step, so results do not depend on frame rate.
- A launch starts when the car moves above 0.15 m/s from rest (below 0.05 m/s arms it). No 1-foot rollout is subtracted, so results can read slightly slower than magazine figures that use rollout.
- A braking run ends at 0.3 m/s to avoid the slow creep tail at the end of a stop.
- Switching vehicle or turning the master OFF unloads the timer from the vehicle. Respawning or resetting ends the run in progress but keeps results.

## Verification
- `python -m unittest discover -s tests`: exact launch/quarter-mile/braking maths under uneven frame times, coast-through rejection, best-vs-last, pause, reset, no-write source check, vehicle switch/respawn lifecycle, and a guard against auto-loading extensions.
- `node tests/test_perf_timer.js`: rows, units, trap speed, fresh highlight, status text, invalid numbers, and the master/reset/unload bridge.
- In-game P001/P002 (`docs/test-results/P001-perf-timer.md`): the vehicle timer agreed with an independent GE-side reference to within 2.3 ms.
- Not yet checked: a physical mouse click on the app's buttons. The RESET command itself was verified in game.
