# ACNG

An original modular BeamNG.drive mod aiming for Assetto Corsa-like driving and motorsport systems while retaining BeamNG's deformation and damage physics.

**Foundation prototype, not a new tire model.** Master and all physics features default OFF. Current code is a harmless control plane plus an explicitly enabled passive telemetry reader. Assetto Corsa is a local behavioral reference, never redistributed.

Start with the existing Obsidian vault's `ACNG/ACNG Dashboard.md` and `ACNG/Current Status.md`, then Git status/history and mirrored `docs/STATUS.md`. The original Home dashboard was renamed during setup; preserve its current name. Read AGENTS.md for durable-memory and safety rules. Architecture, roadmap, testing and first benchmark are in `docs/`; verified setup is summarized in `docs/milestones/SETUP.md`. Game paths are local-only. External tools are pinned and installed in workspace `work/`; no administrator or global runtime changes are needed for the foundation.

Deploy: `python scripts/deploy.py --user <isolated-user/current>`. Package: `python scripts/deploy.py --package` (ZIP roots are lua/scripts/settings, not an extra beamng-mod directory). Existing ACNG deployments are backed up; unrelated mods are untouched. Disable via `extensions.acng_core.setEnabled(false)` in GE Lua; capture is independently stopped with `setTelemetryEnabled(false)`. Current physics feature flags are reserved until implemented and validated.

Offline only. No proprietary assets/code, no stock file overrides. Remove/disable this mod using BeamNG's mod manager to restore the unmodified deployment. See `docs/TESTING.md` for capture/analysis and evidence limitations.
