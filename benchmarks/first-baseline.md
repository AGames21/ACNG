# B001: first stock baseline plan

Selected candidate pair: BeamNG ETK K-Series `kc6_360_M` and AC stock BMW 1M `bmw_1m`. RWD turbo inline-six manuals offer a closer published mass/power match than the initial ETK-four/GT86 idea. UI/spec masses are 1520/1495 kg; power is 366 in ETK native metadata and 340 bhp in AC UI, torque 465/500 Nm. Actual running mass, output conventions, gearing, geometry, tires and assists still need verification. Native content avoids uncertain third-party ports. No assumption of equivalence.

ETK factory config selects six-speed sport manual, rear active LSD, `_323` final-drive part (numeric ratio still to verify), sport 245/35R19 front on 19×9 wheels and 265/35R19 rear on 19×10. Factory DSE/ABS/TC/ESC/Comfort behavior is a confounder to control. Config SHA256: `7e8bbd8567bfabae4dc62b4bb5fdadab480b09c7d22d34d896abb564582bd0b3`. AC tire/setup/gearing data is pending. The first BeamNG scripted pilot succeeded; see `docs/test-results/B001-pilot.md` for results and limitations. It is not a completed comparison baseline.

1. Idle sanity: 10 seconds stationary, coast straight, gentle left/right circles. Establish speed/acceleration/yaw signs and units, wheel identity, temperature scale, absolute vs gauge pressure, time and reset boundaries.
2. Five 0–60 and 0–100 mph acceleration runs from identical spawn; same launch and shift method. Five 60–0 and 100–0 mph braking runs. Read speed crossing times and integrate distance, reject steering/slope/collision anomalies.
3. Flat constant-radius skidpad at a measured 30 m radius: stabilize for 10 seconds at incremental speeds; record lateral acceleration/yaw/steer/slip/load. Slalom at fixed spacing/speed; lift-off, power-on and trail-brake maneuvers as distinct runs.
4. Cold vs warmed repeats, mild lockup/wheelspin, pressure sweep only using game-supported setup controls. Record native thermal state and whether grip changes are measurable. Avoid attribution without controlled evidence.
5. Suspension: repeat curb/bump path at fixed speeds and intact baseline.
6. Damage: separate sacrificial resettable runs for curb damage, bent suspension, deflation, detached wheel and body collision. Verify passive collector handles missing/broken data and stock deformation remains visible. Never reuse a damaged run as a normal handling baseline.

Metadata: game build, config hash, actual running mass, power reference/method, ratios/final drive, wheel size, tire category and dimensions, suspension architecture/geometry, aero setup, fuel, assists, input device, map/position/surface, temperature/grip/wind, warm-up, sample cadence, rejected samples and screenshot/log evidence. Unsupported channels stay null. Publish a completed comparison specification before tuning.
