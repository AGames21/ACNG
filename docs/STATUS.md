# ACNG status

Updated: 2026-10-06 (America/Chicago).

Current milestone: M1 foundation in progress; M2 passive telemetry starts immediately after smoke validation.

Current working features: repository scaffold; master/feature configuration concept; passive telemetry implementation and collector/analyzer authored. Runtime verification pending.

Current experiment: isolated BeamNG skeleton load and stock telemetry sanity. No tire-force changes.

Known issues: AC installing; exact comparable vehicle specification pending. REA/Ghidra tooling undergoing configuration. Native slip/temperature/acceleration units/signs require runtime calibration. Lua syntax and game smoke still pending.

Important discoveries: installed BeamNG 0.39.4.0.20972 (Steam build 24617469); active profile is `%LOCALAPPDATA%/BeamNG/BeamNG.drive/current`. Existing profile contains BeamMP and many mods. Native Lua extension/modScript loader is present; no DLL loader needed. Wheel thermal/pressure/load/slip readers exist. Universal Modder scan misses BeamNG's extension route; KB has no BeamNG/AC field notes.

Next actions: validate source contracts, launch isolated profile and check VFS/user path, validate telemetry and lifecycle, finish toolchain checks, inspect AC SDK after install, freeze vehicle pair/config and run B001. See updated test records before assuming any task complete.
