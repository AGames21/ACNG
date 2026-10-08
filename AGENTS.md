# ACNG engineering instructions

These rules apply to anyone, human or AI agent, changing this repository.

Before work, if `.local/AGENTS.local.md` exists, read it first. It is ignored by Git and holds the maintainer's private workspace notes (engineering notebook location, machine paths, current handoff and local constraints). Then check Git status/history and the status, architecture and testing records in `docs/`. Continue through the next logical task; ask the maintainer only for a real external dependency, credentials/license, admin approval, subjective wheel feedback or an important irreversible decision.

Goal: Assetto Corsa-like driving/racing in BeamNG.drive while preserving soft-body deformation, collision, damage and vehicle structure. BeamNG is the host; AC is a behavioral oracle. Never merge executables, replace the physics engine, permanently edit game installations, bypass DRM/anti-cheat or touch official multiplayer. Work offline in an isolated profile.

Use native Lua extensions and independent mod paths. Master OFF and all future features OFF by default. Telemetry is a separate passive observer for stock baselines. No physics module ships until measured baseline, rollback/reset contract, damage response and performance evidence exist. Never claim runtime success from compilation or mocks.

Original readable Lua/Python, module tables, guarded optional APIs, SI fields where verified; suffix unresolved native units/signs honestly. JSON/JSONL/CSV evidence with schema/version and separate host/simulation times. Missing data is unavailable, never fabricated. Keep observations separate from inference, rate confidence and log alternative explanations. Avoid excessive per-step work/logging.

Game/tool paths belong in ignored `.local/paths.json`. Public docs use `%LOCALAPPDATA%`, `<SteamLibrary>`, `<workspace>`; omit account IDs, secrets, personal paths and personal configs. Proprietary code, extracted assets, decompiled dumps, binaries and game logs stay outside Git. No map or car assets are committed or attached to releases; the AC car converter writes only outside the repository. Commit original tools and concise original findings only. External tools/checkouts are in workspace `work/`, not this repository.

Back up before any save/config experiment. Deploy only `mods/unpacked/acng` with ownership marker and backups; never delete/overwrite unrelated files. Inspect absolute resolved paths before recursive operations, refuse links and use native PowerShell file operations. Check no active game process before launching another. Never automate a player's ongoing drive; experiments run in isolated lab profiles unless the maintainer authorizes otherwise.

Tests: unit contracts and real isolated game smoke; master OFF baseline/restoration, reset/switch lifecycle, bounded telemetry, loss reporting, damage and profiling. Meaningful commits per milestone and before major experiments. Update docs/STATUS.md, MODLOG.md and research/test records immediately after discoveries.

Direction: FREEROAM FIRST. The single ACNG master/Advanced app is primary. Track/AI racing work is deferred; no automatic opponent spawning or driving. Prioritize road-appropriate thermal/pressure calibration, broader vehicle/damage validation and physical FFB. Spa/pit services and the personal AC car converter are optional side workflows (docs/SPA-AND-PITS.md, docs/AC-CAR-CONVERSION.md).

Publishing: run `python tools/publication_audit.py` before every push. Never force-push, change repository visibility or publish a release without a maintainer request. See docs/PUBLISHING.md.
