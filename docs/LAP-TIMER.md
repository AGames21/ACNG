# ACNG Lap Timer

A circuit lap timer app, original to ACNG, that works on any map. Set a start/finish line wherever you are, then drive laps. It shows:

- **Current lap time** with a live **delta to your best lap** (green = ahead, red = behind), compared at the same distance into the lap
- **Three sectors** (S1-S3): purple = your best sector, yellow = slower than your best, grey = from your last lap
- **LAST**, **BEST**, **OPTIMAL** (the sum of your best sectors) and the number of **LAPS**

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG Lap Timer**.
3. Click **OFF** so it turns **ON**. This is the ACNG master switch, which still defaults to OFF every session.
4. Stop on (or drive over) the spot you want as the start/finish line, facing the direction of the lap, and click **SET LINE**.
5. Drive away. The first crossing starts lap 1; every crossing after that finishes a lap and starts the next.

**CLEAR** deletes this vehicle's lap times but keeps the line. **SET LINE** again moves the line and clears the times. **ON/OFF** is the master switch.

## How it measures
- The timer runs inside the vehicle's own Lua and reads only the vehicle's position and direction. It writes no controls, forces or physics (`physics_writes=0`).
- The line is a 30 m wide gate (15 m each side of where you set it) at right angles to the direction the car faced. Crossings are interpolated between physics frames, and simulation time is used, so pausing and slow motion do not distort laps.
- Sectors split the lap into three equal distances, based on the length of your first timed lap.
- The live delta compares the current lap with the best lap's time at the same distance (sampled every 2 m).
- A lap is abandoned (shown on the status line) if you reset or recover the car, cross the line backwards, or the car jumps more than 30 m in one frame. Loops shorter than 5 s or 50 m are ignored, so wobbling over the line does not count.
- Switching vehicle or turning the master OFF unloads the timer and its laps. Lap times are kept for this session only.

## Verification
- `python -m unittest discover -s tests`: lap, sector and delta maths on a constant-speed circle with uneven frame times, slower-lap delta and best kept, gate width, backwards crossing, teleport, minimum lap, pause, reset, clear, the no-write source check and the master lifecycle.
- `node tests/test_lap_timer.js`: status text, time formats, delta sign and colour, sector colours, Lua tables arriving as arrays or objects, and the SET LINE/CLEAR/master bridge.
- In-game LT001-LT003: see `docs/test-results/LT003-lap-timer.md`. All 15 checks passed; every lap within 1.5 ms of an independent reference.
- Not yet checked: a physical mouse click on the app's buttons (the harness sent the buttons' exact commands), a real track with elevation, and other cars.
