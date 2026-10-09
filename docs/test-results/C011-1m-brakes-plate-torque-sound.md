# C011 - 1M centred brakes, native plate, AC torque curve, sound balance (installed)

Date: 2026-10-09. BeamNG 0.39.4, fresh lab profiles ACNG-car-024 (fix-009) and
ACNG-car-025 (fix-010). Build fix-010 (ZIP SHA256 9a843b20...), local, not released.
Includes the sound EQ cancel and nose binding from the previous checkpoint.

## Changes tested

| User fault | Cause | Fix |
|---|---|---|
| Brake discs sit on the wheels, off centre | Meshes whose nodes the converter moves were left where they were authored. Brakes are authored at the origin, so `pos` is their real location and was never moved | Every kept flexbody shifts by the node move at its node-group centroid (or at `pos` when it has no local groups). Also fixes exhaust, fuel tank, heatshield and wings |
| Sound "weird and artificial" | Idle loops tagged 800 rpm but recorded at 630-675 rpm (firing frequency), so idle played 19 % flat. Interior and exterior sets are both full-car recordings at equal level: two engines from two places. Donor `offLoadGain` 0.5 cut the already quieter off-throttle loops another 6 dB | Idle tagged 650 rpm; interior set -8 dB as a cabin layer, exterior set leads; `offLoadGain` 0.75 |
| Specs differ from AC and the real car | Donor ETK torque curve scaled by a few flat factors | Base curve rebuilt so the net (after turbo and friction) curve follows the AC 1M table; 6000 rpm aims at the real 250 kW |
| Branded plate | AC plate mesh | AC plate skipped; native BeamNG `licenseplate-52-11-r2` on the trunk |
| Text names the source game | Author strings, ETK badge slots, a logo on the iDrive screen texture | Neutral author string, badge slots empty, logo area filled from its edges in the local texture |
| Replace with real parts | ETK brakes | Native drilled discs and red single-piston calipers, 360 mm front / 350 mm rear |

## Result

fix-009: 50/50 checks, but the worst torque error was 6.4 % at 5000 rpm. The base
curve was then derived from the turbo gain measured in that run (fix-010).

fix-010: 50/50 checks. Worst torque error 1.8 % (6000 rpm).

| rpm | Nm | kW |
|---|---|---|
| 1000 | 300 | 31.4 |
| 1500 | 387 | 60.7 |
| 2000 | 500 | 104.7 |
| 2500 | 500 | 130.9 |
| 3000 | 500 | 157.1 |
| 3500 | 494 | 181.0 |
| 4000 | 500 | 209.4 |
| 4500 | 481 | 226.6 |
| 5000 | 443 | 231.9 |
| 5500 | 421 | 242.8 |
| 6000 | 399 | 250.5 |
| 6500 | 357 | 242.7 |

- Peak 250.5 kW and 503.7 Nm (real car: 250 kW, 450/500 Nm overboost; AC: 340 bhp, 500 Nm).
- Mass 1529.9 kg, +2.3 % over the 1495 kg reference.
- Brake shots: discs centred in the wheels with red calipers on all four corners.
- Rear shot: native plate sits in the trunk recess.
- No text naming the source game remains in the build output.
- `ac_engine_sound_loaded` passes. How the sound feels still needs a player to listen.
- Not added: the real car's 250 km/h limiter.

Installed in the normal profile after an automatic backup; the installed hash
matches the tested ZIP.
