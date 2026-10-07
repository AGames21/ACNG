# B001: first stock baseline plan

Candidate pair: BeamNG ETK K-Series 4-cylinder RWD manual (`etkc`, exact factory configuration to be inspected) and AC Toyota GT86. Selection is provisional until both configuration records are verified. Both offer a modest-power front-engine RWD route without extreme aero; mass/power/tire/geometry differences must be measured, not assumed equivalent. Native BeamNG content is preferred over uncertain third-party ports.

1. Idle sanity: 10 seconds stationary, coast straight, gentle left/right circles. Establish speed/acceleration/yaw signs and units, wheel identity, temperature scale, absolute vs gauge pressure, time and reset boundaries.
2. Five 0–60 and 0–100 mph acceleration runs from identical spawn; same launch and shift method. Five 60–0 and 100–0 mph braking runs. Read speed crossing times and integrate distance, reject steering/slope/collision anomalies.
3. Flat constant-radius skidpad at a measured 30 m radius: stabilize for 10 seconds at incremental speeds; record lateral acceleration/yaw/steer/slip/load. Slalom at fixed spacing/speed; lift-off, power-on and trail-brake maneuvers as distinct runs.
4. Cold vs warmed repeats, mild lockup/wheelspin, pressure sweep only using game-supported setup controls. Record native thermal state and whether grip changes are measurable. Avoid attribution without controlled evidence.
5. Suspension: repeat curb/bump path at fixed speeds and intact baseline.
6. Damage: separate sacrificial resettable runs for curb damage, bent suspension, deflation, detached wheel and body collision. Verify passive collector handles missing/broken data and stock deformation remains visible. Never reuse a damaged run as a normal handling baseline.

Metadata: game build, config hash, actual running mass, power reference/method, ratios/final drive, wheel size, tire category and dimensions, suspension architecture/geometry, aero setup, fuel, assists, input device, map/position/surface, temperature/grip/wind, warm-up, sample cadence, rejected samples and screenshot/log evidence. Unsupported channels stay null. Publish a completed comparison specification before tuning.
