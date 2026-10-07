# LT001-LT003 lap timer in game

Stock BeamNG ETK K-Series `kc6_360_M`, Small Grid, BeamNG 0.39.4, fresh isolated lab profiles per run. Master OFF at start. The harness (`tests/beamng-laps`, GE extension `acng_lapgate`) holds constant steering in arcade mode with a throttle controller at about 12 m/s, so the car laps a steady circle of about 125 m. After 20 s it sends the app's exact SET LINE command. Next come three laps, one slower lap at about 9 m/s and two more laps at 12 m/s. Then it resets the car, sends the CLEAR command and turns the master OFF. Raw results: `lt002-lap-timer.json` (run 2), `lt003-lap-timer.json` (final run); screenshot `lt003-lap-timer.png`, taken 4.4 s into the lap after the slow one.

The harness kept its own reference in the GE VM. It used the same line point and direction, and found forward crossings between GE frames over simulation time, interpolated linearly. The vehicle timer runs separately in the vehicle VM.

| Lap | Timer | Reference | Sectors (timer) |
|---:|---:|---:|---|
| 1 | 10.6465 s | 10.6465 s | 3.549 / 3.549 / 3.549 |
| 2 | 10.6463 s | 10.6463 s | 3.549 / 3.549 / 3.549 |
| 3 | 10.6462 s | 10.6467 s | 3.549 / 3.549 / 3.548 |
| 4 (slow) | 12.7738 s | 12.7723 s | 4.181 / 4.736 / 3.856 |
| 5 (speeding back up) | 10.8186 s | 10.8201 s | 3.690 / 3.563 / 3.565 |
| 6 | 10.6456 s | 10.6460 s | 3.549 / 3.549 / 3.547 |

Lap 1 comes from the `after_three_laps` snapshot; the history keeps the last five laps. Largest timer-vs-reference difference: 1.5 ms. Lap length 125.11 m. Halfway through the slow lap the live delta read +1.185 s. Best stayed on a fast lap, and optimal (the sum of best sectors) was 10.6447 s.

Checks (LT003, all 15 true): master OFF by default; timer absent while OFF; timer attached when ON; `no_line` before SET LINE; three laps recorded; lap count matches the reference; all five history laps within 20 ms of the reference; slow lap recorded as lap 4; sectors sum to the lap time; positive delta during the slow lap; best kept after the slow lap; reset abandons the lap in progress and keeps lap times; CLEAR removes times but keeps the line; master OFF detaches the timer; CLEAR does not reload the timer after OFF.

## What went wrong on the way
- **LT001: the harness never started.** Its file was `acng/laps_lab.lua`, loaded as `acng_laps_lab`. BeamNG's `lua/common/extensions.lua` maps every `_` in an extension name to `/` (a literal underscore is written `__`). So it looked for `acng/laps/lab.lua`, and the game sat on the main menu. Renamed to `acng/lapgate.lua`. A new test fails on any extension file name containing `_`.
- **LT002: two checks failed because of the harness, not the timer.** The harness asked for a vehicle snapshot on the same GE frame its reference saw a crossing, before the vehicle VM had logged that lap, so the counts were one lap behind. Where laps lined up, the timer matched to 0.5 ms. LT003 waits 1 s before asking and compares every lap in the history.

Limits: one car, one flat map, a constant-radius circle, one clean run. A mouse click on the app buttons was not performed (the screen tool cannot be granted the game window), so the harness sent the buttons' exact commands.
