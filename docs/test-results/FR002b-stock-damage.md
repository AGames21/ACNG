# FR002b stock vehicle crash, puncture and lost-wheel coverage

The run's raw lab file calls it FR004; renumbered to fit the FR001 (heat) and FR002 (damage) series in TESTING.md, which keeps FR003 for the physical wheel.

Setup:
- 2026-10-08, BeamNG 0.39.4, Small Grid
- a fresh isolated lab profile, master OFF at start (checked)
- harness `tests/beamng-stocklab` (GE extension `acng_stocklab`)

Master ON with Road tire heat, tire wear, ABS and TC all on. The harness ran the same sequence on six stock models in their default configs:

1. Spawn.
2. Full throttle for 7 s, then a hard stop.
3. Crash at full throttle into a parked stock pickup 45 m ahead.
4. On the wrecked car, a native puncture (`beamstate.deflateTire`) and a native wheel break (`beamstate.breakBreakGroup`, `wheel_FL` or the Pigeon's `wheel_F`).
5. Drive the wreck at half throttle.
6. Master OFF, then ON again.
7. A native reset.

Every check read the vehicle's own Lua state.

**Result: 110 of 110 checks passed. All six vehicles completed. No ACNG errors in the lab log.**

| Vehicle | Type | Tires tracked | Top speed | Crash speed | Native damage after crash |
|---|---|---:|---:|---:|---:|
| Ibishu Covet | small FWD | 4 of 4 | 21.2 m/s | 16.2 m/s | 15,902 |
| Gavril Barstow | old RWD | 4 of 4 | 24.1 m/s | 18.1 m/s | 17,410 |
| Hirochi Sunburst | compact sedan | 4 of 4 | 35.7 m/s | 23.4 m/s | 42,701 |
| Ibishu Pigeon | 3 wheels | 3 of 3 | 14.9 m/s | 13.2 m/s | 9,483 |
| Gavril H-Series | van | 4 of 4 | 20.8 m/s | 16.4 m/s | 17,510 |
| Gavril T-Series | semi, dual rears | 10 of 10 | 9.7 m/s | 10.1 m/s | 3,220 |

The damage number is BeamNG's own damage total, not a percentage.

## Checks for each vehicle
- Core attaches ACNG tires and assists to the new car on Road, and every native tire is tracked.
- Temperatures and grip stay valid numbers through hard driving, the crash, the puncture, the lost wheel and driving the wreck.
- The crash produces real native damage (every car above 1,000).
- The native puncture and the broken-off wheel both appear (front left, or the Pigeon's single front wheel).
- Master OFF unloads tires and assists, makes no physics writes, and **keeps all the damage**: the damage total, the flat tire and the missing wheel all stay.
- Master ON again re-attaches to the wrecked car with valid numbers.
- A native reset repairs everything (damage 0, no flat, wheel back) and ACNG gives fresh tread on every tire.

## Limits
- Crash damage is checked as BeamNG's damage total and wheel flags. Bent suspension geometry (toe and camber after the hit) was not measured.
- Driving the wreck mostly shows ACNG keeps running. Most wrecks barely moved (0.3 to 6.5 m/s) with a wheel missing.
- Default configs only, flat map, scripted inputs, no traffic, no physical wheel.
- No mod or third-party vehicles.

Machine-readable summary: `FR002b-stock-damage.json`. Re-run with `scripts/launch-lab.ps1 -Experiment StockLab -LabUser <fresh>/ACNG-stock-NNN/current`.
