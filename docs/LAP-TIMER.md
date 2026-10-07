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

**CLEAR** deletes this setup's session and saved reference but keeps the line. **SET LINE** again replaces the saved line and clears its reference. **ON/OFF** is the master switch.

## How it measures
- The timer runs inside the vehicle's own Lua and reads only the vehicle's position and direction. It writes no controls, forces or physics (`physics_writes=0`).
- The line is a 30 m wide gate (15 m each side of where you set it) at right angles to the direction the car faced. Crossings are interpolated between physics frames, and simulation time is used, so pausing and slow motion do not distort laps.
- Sectors split the lap into three equal distances, based on the length of your first timed lap.
- The live delta compares the current lap with the best lap's time at the same distance (sampled every 2 m).
- A lap is abandoned (shown on the status line) if you reset or recover the car, cross the line backwards, or the car jumps more than 30 m in one frame. Loops shorter than 5 s or 50 m are ignored, so wobbling over the line does not count.
- Completed best-lap traces, best sectors and the start line are saved under the active user profile's `settings/acng/lap-records.json`. Returning to the same map, vehicle model, parts and tuning variables restores the reference; the current lap and session count start fresh. No automatic vehicle reset or physics changes.
- The archive keeps the 32 most recently saved setups and a `.previous` recovery file. A corrupt primary uses the previous file read-only; it never silently overwrites the damaged archive. BEST's asterisk has a save-status tooltip.
- Only one start line is retained per map/setup. Changing SET LINE replaces it. References are local practice aids: route shortcuts, weather, damage, fuel, tire heat/wear and assists are not homologated or separated into competitive categories. Only vehicle parts/tuning/map/model form the key.
- Limits: laps up to 20 km, 24 hours and 10,000 trace points. Unsupported records are rejected with a save-status message; session timing continues.
- Saving runs only when a lap completes or CLEAR/SET LINE is used, not every frame. Master OFF unloads the timer, preserving completed records without writing vehicle state.

## Verification
- `python -m unittest discover -s tests`: lap, sector and delta maths on a constant-speed circle with uneven frame times, slower-lap delta and best kept, gate width, backwards crossing, teleport, minimum lap, pause, reset, clear, the no-write source check and the master lifecycle.
- `node tests/test_lap_timer.js`: status text, time formats, delta sign and colour, sector colours, Lua tables arriving as arrays or objects, and the SET LINE/CLEAR/master bridge.
- In-game LT001-LT003: see `docs/test-results/LT003-lap-timer.md`. All 15 checks passed; every lap within 1.5 ms of an independent reference.
- Not yet checked: a physical mouse click on the app's buttons (the harness sent the buttons' exact commands), a real track with elevation, and other cars.

## Saved reference verification (2026-10-07)
Offline LuaJIT tests exercise the actual vehicle-to-GE command strings, a simulated completed lap, reload/clear, map and tuning separation, invalid data, stale vehicle/request rejection, write failure, failed readback and corrupt-file recovery. Node checks cover save-status text and the existing app bridge. These are **offline contracts**, not proof of native filesystem/VM behavior. No game was launched because the user is playing Roblox and watching Chrome.

Next quiet-time live test: complete a lap in a fresh isolated profile; toggle master OFF/ON and confirm the exact best time, line and delta reference return; restart BeamNG and repeat; change vehicle tuning/map and confirm isolation; CLEAR and reload to confirm deletion. Compare JSON before/after. Do not run this while the user requests uninterrupted foreground use.

### Prepared native check (LR001)
`scripts/prepare-lap-records-lab.py --parent <whitespace-free-work-directory>` creates a new isolated profile from the **committed** Git tree only. It does not launch BeamNG or touch a current profile. The test harness is excluded from the player mod and refuses both a normal profile path and an existing lap archive.

When the user's no-interruption constraint is explicitly released, use the existing isolated launch procedure with `-userpath <new-lab-parent>` (not `current`). The harness drives a stock ETK circle, waits for a saved lap acknowledgement, stops the car, unloads/reloads both archive and lap VMs, checks restoration, clears the record, reloads again and checks that CLEAR persisted. Read `current/acng-lap-records-test.json`: require `completed: true`, `passed: true`, and all checks true. Failure/watchdog stops the car. VM reload is not a full game-process restart; that and actual app clicks remain separate checks.

Offline follow-up: rejected malformed line-only sector data and sparse traces before they can reach the display. Archive status is now exposed through the same snapshot used by the native harness. LuaJIT also checks that the harness refuses a primary profile or pre-existing archive before starting freeroam.
