# T005 tire wear in game

Setup for every run:
- stock BeamNG ETK K-Series `kc6_360_M` on Small Grid
- BeamNG 0.39.4
- a fresh isolated lab profile per run
- master OFF at start

Harness `tests/beamng-tirewear` (GE extension `acng_tirewear`). The car drives a constant-radius circle at the limit (10 m/s, steer 0.5). Each phase is split into 5 s windows, and the mean lateral acceleration, tire temperatures, tread, grip and slip power are recorded per window.

## Phases
1. **Off.** Master OFF, 20 s baseline.
2. **Wear only.** Master and `tire_wear` ON, `tire_temperature` OFF, then reset and drive 150 s. After window 3 the harness raises the wear rate so the busiest tire would lose 60 % of its tread in the phase (clamped 1 to 100). Screenshot at 60 s.
3. **Reset.** Sample the worn tires, reset the car, sample again.
4. **Both parts.** Rate back to 1, `tire_temperature` ON as well, drive 60 s.
5. **Flat.** Deflate the front-left tire with BeamNG's own `deflateTire`.
6. **Off again.** Both parts OFF, 20 s.

## Results
| Run | Result | Notes |
|---|---|---|
| T005a | 18 of 19 | `reset_gives_fresh_tires` required zero slip work after the reset, but the car settling on its springs made 0.4 J. Check changed to under 100 J. Raw results: `t005a-tirewear-strict-reset-check.json`. |
| T005b | **19 of 19** | Raw results: `t005b-tirewear.json`, screenshot `t005b-tirewear.png`. |

T005b numbers:

| Measure | Value |
|---|---:|
| OFF lateral | 9.349 m/s2 |
| wear rate set by the harness | x11.34 |
| wear-only lateral, window 3 | 9.348 m/s2 |
| wear-only lateral, last window | 8.868 m/s2 (-5.1 %) |
| grip vs lateral, correlation | r = 0.995 |
| worst temperature change while only wear was on | 0.002 K |
| mean tread at the end | 0.48 (outer front 0) |
| mean grip at the end | 0.924 |
| after reset: tread, grip | 1.000, 1.000 |
| both parts, 60 s at rate 1: outer front | 123 C, tread 0.952, grip 0.927 |
| flat front-left | 28.4 to 2.8 psi |
| OFF again lateral | 9.351 m/s2 (+0.014 % vs OFF) |

Steady slip power on the circle (windows 2 to end):

| Tire | Slip power |
|---|---:|
| FL (outer front) | 5.70 kW |
| RL | 2.78 kW |
| FR | 1.37 kW |
| RR | 1.02 kW |

Lateral per 5 s window, wear only: 9.35, 9.34, 9.33, ... 8.92, 8.89, then flat at 8.87 from window 27. The outer front reached 0 tread around window 26. The flat part shows the tread stops at 0 and grip stops at 85 %.

## Checks (T005b, all pass)
- `default_master_off`, `default_wear_off`: both default OFF.
- `tires_not_loaded_while_off`, `off_temps_flat`: no extension and no heat while OFF.
- `core_reports_wear_only`, `core_reports_both`, `core_reports_tires_off`: `acng_core.getStatus()` reports each flag combination.
- `wear_loaded_heat_off`: wear alone loads the extension with heat off.
- `rate_raised`, `tread_falls`, `grip_falls_with_tread`: tread and grip fall, and lateral grip falls with them.
- `temperature_unchanged_during_wear`: wear alone keeps stock thermal behaviour.
- `reset_gives_fresh_tires`: worn minimum tread under 0.5, after reset over 0.9999, slip work under 100 J.
- `both_loaded_without_reload`, `both_heat_and_wear`: turning heat on beside wear reconfigures without a reload; the outer front heats and wears.
- `flat_still_deflates`: BeamNG punctures still work.
- `tires_unloaded_after_disable`, `off_again_temps_flat`, `off_again_grip_matches_baseline`: OFF restores stock.

## What went wrong
- **T005a reset check too strict.** See the table above. Fixed in the harness, not the mod.
- **Rate tuning picks the rear-left.** The harness picks the tire with the most slip power in window 3, which is still the end of the launch, so it picked RL (2.9 kW) rather than the steady outer front (5.7 kW). The outer front therefore went bald during the phase. This only changes how fast the test wears the tires; the mod itself is unaffected.

## Interpretation
- Grip loss from wear is visible and smooth: about 5 % lateral after 150 s at rate x11, with the outer front bald.
- At rate 1 the outer front would need about 22 minutes of this limit cornering to go bald. This is a first calibration on one car and one manoeuvre; confidence medium. Wear on real laps is unchecked.
