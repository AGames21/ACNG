# ACNG Race Weekend

Independent practice, qualifying and lap-limited races with up to three BeamNG AI opponents on **Hirochi Raceway Short**. Uses native ordered-checkpoint tracking and native AI path following; BeamNG owns suspension, chassis, collisions and damage. OFF by default; zero opponents by default. Native BeamNG AI is optional, never replaced.

## Playtest
1. Enter Hirochi Raceway in freeroam. Start with a stock ETK K-Series.
2. Add **ACNG Race Weekend** in UI Apps. Select AI count, lap count and practice/qualifying minutes.
3. PREPARE builds the grid and enables master plus `race_sessions`. Choose PRACTICE, QUALIFY or RACE. There is a five-second simulation-time countdown.
4. Drive complete laps through the circuit checkpoints. Practice/qualifying end on the timer or END SESSION. Best actual qualifying laps determine race grid; drivers with no completed lap start last. You can skip qualifying.
5. Race ends when every entrant finishes or retires. Standings mark the finish and DNFs; results display CHEQUERED FLAG.
6. CANCEL removes only ACNG-spawned opponents, releases your controls and preserves your car. Master OFF cancels immediately.

Resetting during qualifying/race retires that entrant. Changing player vehicles cancels the weekend. An AI stationary below 0.5 m/s for 45 seconds during a race is retired after the initial 15-second start window; damaged cars are never silently repaired. Grid movement uses native start-position placement with `repair=false`.

## Architecture
`acng_weekend` runs in GE Lua. It creates its own native race/path instances, never takes over stock traffic or a live scenario, and updates the UI at 5 Hz. `core` owns the independent default-OFF `race_sessions` flag and immediate cancellation. The Angular app uses expression-safe callbacks, including PREPARE and CANCEL.

Native 0.39.4 race `bestLapTime` is an unused placeholder; original ACNG code calculates best time from actual `historicTimes[].duration`. Native checkpoint gap milliseconds are converted to seconds. No proprietary track or code is packaged: named waypoints are resolved from the user's installed game at runtime.

## Verification
Seven offline LuaJIT/real-JavaScript bridge contracts plus the existing regression suite. Isolated native harness: `tests/beamng-weekendlab`; repeat via `scripts/run-weekend-lab.ps1`. Seven early native checks passed; testing stopped on user report of AI collisions. Finish/reset/damage checks remain pending. See docs/test-results/RW001-race-weekend.md.

## Limits
Only the forward Hirochi short circuit is supported. Opponents use stock configurations; matching the player's custom tuning is not implemented. Ordered checkpoints stop finish-line farming but do not constitute a corner-cut penalty system. Native AI can crash; no enhanced race strategy, pit lane, weather, fuel management or AC-calibrated AI pace is claimed. Three concurrent vehicles cost more CPU than solo driving. Physical player handling/visual usability feedback and broader AI/damage/performance coverage remain required.

Next playtest: run a one-lap race with two AI. Check the countdown, grid direction, readable standings and finish; report if an opponent blocks the grid or the route seems wrong.

User steering: no AC AI system. Stop automatic AI experiments. Default zero opponents; use BeamNG native AI. Opponents run stock physics. Solo practice/qualifying are the useful direction.
