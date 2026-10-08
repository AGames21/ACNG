# ACNG roadmap

1. Foundation: inspect tools, isolate profiles, establish reproducible deployment, load skeleton in real BeamNG, validate master behavior and stock baseline capture, document evidence, commit.
2. Oracle/baselines: validate AC SDK shared-memory ABI after installation; compare units, coordinate frames and timing; select one matched pair; run repeated straight-line, skidpad, tire and damage baselines. No tuning before valid data.
3. Tire behavior: investigate one behavior at a time (slip curves, load sensitivity, combined grip, transient response), inspect existing BeamNG mechanisms, prototype minimal reversible influences, compare identical tests.
4. Thermal: assess BeamNG's existing temperature APIs before adding surface/core heating/cooling and pressure behavior; do not double-count native systems.
5. Wear: degradation and possible flat spotting with damage compatibility.
6. FFB: measured steering/road forces, aligning torque, understeer/oversteer communication; targeted wheel-driver feedback.
7. Assists: factory/off/ACNG ABS and TC with validated intervention levels.
8. Racing: timing/sectors, sessions/grids, pits and penalties.
9. Environment: feasible temperature, surface grip, rubber/wetness behavior.
10. Generalize: capability-driven support beyond the initial vehicle, polished settings/UI, profiling and regression matrix.

Each milestone requires source tests, real-game evidence, stock/OFF restoration checks, repeatable results, performance measurements, damage checks where applicable, status updates and a meaningful Git checkpoint. Native RE requires an explicit narrow question first.

## Freeroam-first priority (2026-10-07)
Unified ACNG master/Advanced app is complete with GUI001 evidence. Next milestone is road-driving calibration and compatibility, not race systems. Test stock-versus-ACNG cold/warm tires in city stops, cruising and winding-road runs; tune pressure rise using recorded data. Then expand vehicle reset/switch/puncture/bent-geometry coverage and physical-wheel FFB. Optional roadside service and compounds follow reliable road behavior. Track work stays deferred in Obsidian Track Later.

## Optional Spa workflow requested 2026-10-08
Acquire author-distributed Spa 2026 separately; native 0.39.4 load/collision check; P001 pit service validation; garage location and map overlay polish; normal-profile deployment after native success. Later: pit limiter, visual marked box, fuel targeting, tire compound selection/blankets and session rules. AC BMW 1M geometry feasibility established, but full original JBeam conversion is a separate major milestone. Freeroam remains primary.
