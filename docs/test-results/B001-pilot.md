# B001 pilot result

Stock BeamNG ETK K-Series `kc6_360_M`, Small Grid, ACNG master OFF, factory assists, arcade automatic shifting for acceleration and realistic gearbox behavior while braking. Full throttle to >46 m/s, then full brake. One pilot validates the automation/capture/analysis path; it is not the five-repeat benchmark and not an Assetto Corsa comparison.

| Measurement | Pilot result |
|---|---:|
| 0.1 m/s–60 mph | 4.6674 s |
| 0.1 m/s–100 mph | 9.9496 s |
| 60 mph–0.1 m/s braking | 2.2722 s / 30.1371 m |
| 100 mph–0.1 m/s braking | 3.7779 s / 84.1943 m |

792 valid packets; no sequence gaps/malformed/out-of-order packets; max sample interval 33.5 ms. Linear threshold interpolation and trapezoidal speed integration. Initial movement/stop threshold is 0.1 m/s, explicitly not standardized rollout. Position X varied 2.30 m over the run and Z varied 0.020 m; this is a flat straight-line pilot with small lateral drift, not exact path conformity. Repeats must constrain and quantify that drift.

Limitations: car engine was off after braking (screenshot); realistic braking/controller clutch configuration needs to be frozen to avoid stall differences. Temperature getters remained constant. Launch/shift logic differs from a human manual launch. Game logs also contain light-manager, achievement and ETK gauge UI errors outside ACNG; their cause is not established. No ACNG Lua exception appears in the checked log. Damage, AI and FFB regressions remain untested. Primary settings backup diff shows no added, removed or changed files after testing.
