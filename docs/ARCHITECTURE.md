# ACNG architecture

BeamNG.drive is the host. Assetto Corsa is a behavioral oracle. ACNG never merges executables or replaces BeamNG's solver, collision system, beams, mechanical damage, or vehicle structure.

## Foundation

`beamng-mod/scripts/acng/modScript.lua` loads `acng_core` in Game Engine Lua. `lua/ge/extensions/acng/core.lua` owns configuration, lifecycle and eventual module orchestration. `lua/vehicle/extensions/acng/telemetry.lua` reads vehicle state in Vehicle Lua. Python tools collect loopback UDP into JSONL and analyze explicit runs. No network control server or arbitrary-code endpoint is introduced.

The master defaults OFF. Every future physics feature has its own toggle and a capability/rollback contract. The current feature flags are reserved, unimplemented settings; setting one true must never imply that a model exists. Telemetry is independent of master so stock baselines can be measured. Only explicit telemetry enable attaches the reader to the player vehicle. Master changes currently perform zero physics writes.

## Future module contract

Each dynamics module must declare supported vehicles, dependencies, update cadence, captured stock state, enable/disable behavior, damage response, and whether a reset is required. Apply only narrowly supported influence APIs after investigation. On disable, restore only ACNG-owned changes or require reset. If stock state cannot be restored reliably, refuse an in-motion toggle. Broken wheels/suspension remain authoritative; a detached tire cannot produce fabricated force.

## Scheduling

Control plane polls player identity at 4 Hz only during capture. Telemetry observes `updateGFX` at up to 50 Hz (actual rate bounded by graphics cadence), sending at most one datagram per observed frame. It never fabricates physics-step samples or writes to disk in the vehicle VM. Thermal/wear/race/UI rates will be chosen from measured cost; no blanket 2000 Hz Lua loop. Receiver reports sequence gaps. Simulation and host time remain distinct.

## Data and clean implementation

Schema version 1 retains native values when signs/units remain uncertain. Absence means unavailable, never zero. Wheel rows carry identity and damage flags; per-contact slip angle and ratio are NOT inferred from native slip velocities. Cross-game coordinate normalization needs a calibrated experiment first. Proprietary sources/assets stay outside Git. Research records separate observation, inference, uncertainty, and proposed original implementation.

## Repository

`docs/` contains status, architecture, milestones, research, reverse-engineering decisions and checked test summaries. `telemetry/` contains adapters and analysis; raw runs are ignored. `benchmarks/` defines repeatable procedures. `tools/` documents pinned external utilities; binaries/checkouts reside in workspace `work/`. `scripts/` manages safe deploy/package/launch. `tests/` verifies contracts and calculations. `converters/` is reserved for local bring-your-own-asset converters. Empty vehicle/UI folders are intentional until justified.

## Isolation

Use workspace `work/beamng-user/current` as the experiment profile. Launch with its parent as `-userpath`; verify the resolved VFS user path in the fresh log each run. Do not install ACNG into stock game content, disable existing user mods, or copy their binaries into ACNG. The standard profile can be deployed later after the isolated smoke passes and a backup.
