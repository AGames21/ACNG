# D001 — native damage observer

BeamNG 0.39.4.0.20972, isolated `ACNG-d001-fixed/current`, stock ETK `kc6_360_M`, SmallGrid, ACNG master and passive telemetry ON. A stock parked pickup is the sacrificial collision obstacle. Test-only code invokes native repair, tire deflation and the verified `wheel_FL` break group; production ACNG writes no physics state.

Run002: **14 checks passed**, 2,487 accepted packets, zero reported malformed/gap/out-of-order packets, three native reset generations in one vehicle/capture. Maximum pre-impact speed21.5724m/s. Native damage scalar92,571.5234 and seven deformation-event groups appeared after impact, including lights, radiator and engine plumbing. That scalar is native energy/damage accounting, not a damage percentage.

After repair, native damage and wheel flags returned clean. Native FL deflation appeared in both snapshots and telemetry. Measured absolute pressure ranged108,147–125,592Pa while deflated but still attached; minimum was36.39% of the initial FL pressure. Native wheel break appeared in the acknowledged snapshot and persisted7.9785 simulation seconds in telemetry. Final native reset cleared damage/broken/deflated state; the observer continued into generation3, then master and telemetry switched OFF.

The first harness queued a snapshot then reset in the same GE frame, allowing the cross-VM snapshot to observe repaired state. Run001 nevertheless captured actual broken-wheel packets. Run002 explicitly waits for snapshot acknowledgement before repair and completion. Keep that ordering for future damage tests.

The initial pressure check incorrectly required every deflated sample below110kPa. Local `lua/vehicle/beamstate.lua:deflateTire` sets initial pressure near atmosphere on the first native puncture; subsequent measured pressure varies with the physical tire state. Observed pressure exceeded that bound despite native deflation. The corrected test requires a large measured reduction from the same wheel's baseline and reports the absolute range; it does not invent an atmosphere clamp or override BeamNG.

Reproduce: receiver `python -m telemetry.collect_udp <fresh.jsonl> --duration 300 --idle-timeout 45`; launch `scripts/launch-lab.ps1 -Experiment Damage -LabUser <fresh-no-space-profile/current>`; after completion run `python -m telemetry.damage_report <profile/acng-damage.json> <raw.jsonl> <raw.summary.json> --output <report.json>`.

Evidence hashes and all checks: [machine-readable report](d001-native-damage-002.json). Raw samples/events stay local. This establishes native collision damage, puncture, wheel-break flags and repair with the passive observer. Quantitative body-node deformation, bent alignment, detached-wheel dynamics, future tire-force interactions, AI and performance are still untested. No claim of complete damage compatibility.
