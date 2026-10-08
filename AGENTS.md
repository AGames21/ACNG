# ACNG persistent engineering instructions

Before work, read the existing Obsidian vault's `ACNG/ACNG Dashboard.md` (the Home dashboard was renamed during setup), `ACNG/Current Status.md` and relevant recent session, then check Git status/history and repository status/architecture/testing records. Preserve the current dashboard name; do not recreate a duplicate Home note. Current registered vault is `H:/Obsidian Vault/AI VAULT`; confirm against `%APPDATA%/obsidian/obsidian.json` and `.obsidian` if it moves. Private `.local/paths.json` also stores memory paths. Follow vault AGENTS.md, back up existing notes before updating, preserve human additions, and never alter unrelated notes or `.obsidian`. Continue autonomously through the next logical task; ask the user only for a real external dependency, credentials/license, admin approval, subjective wheel feedback or important irreversible decision.

Goal: Assetto Corsa-like driving/racing in BeamNG.drive while preserving soft-body deformation, collision, damage and vehicle structure. BeamNG is the host; AC is a behavioral oracle. Never merge executables, replace the physics engine, permanently edit game installations, bypass DRM/anti-cheat or touch official multiplayer. Work offline in the isolated profile. User's primary profile has BeamMP and other mods; leave it intact.

Use native Lua extensions and independent mod paths. Master OFF and all future features OFF by default. Telemetry is a separate passive observer for stock baselines. No physics module ships until measured baseline, rollback/reset contract, damage response and performance evidence exist. Never claim runtime success from compilation or mocks.

Original readable Lua/Python, module tables, guarded optional APIs, SI fields where verified; suffix unresolved native units/signs honestly. JSON/JSONL/CSV evidence with schema/version and separate host/simulation times. Missing data is unavailable, never fabricated. Keep observations separate from inference, rate confidence and log alternative explanations. Avoid excessive per-step work/logging.

Game/tool paths belong in ignored `.local/paths.json`. Public docs use `%LOCALAPPDATA%`, `<SteamLibrary>`, `<workspace>`; omit account IDs, secrets and personal configs. Proprietary code, extracted assets, decompiled dumps, binaries and game logs stay outside Git. Commit original tools and concise original findings only. External tools/checkouts are in workspace `work/`, not this repository.

Back up before any save/config experiment. Deploy only `mods/unpacked/acng` with ownership marker and backups; never delete/overwrite unrelated files. Inspect absolute resolved paths before recursive operations, refuse links and use native PowerShell file operations. Check no active game process before launching another.

Tests: unit contracts and real isolated game smoke; master OFF baseline/restoration, reset/switch lifecycle, bounded telemetry, loss reporting, damage and profiling. Meaningful commits per milestone and before major experiments. Update STATUS, MODLOG and research/test records immediately after discoveries. User authorized setup/configuration and autonomous repeatable testing; avoid needless permission prompts. Do not publish or message external people without explicit user instruction.

Repository owns source/scripts/config/tests/raw telemetry/build artifacts; Obsidian owns engineering reasoning, status, decisions, discoveries, hypotheses, interpretations and plans. Mirror important guidance in repository docs. Update ACNG Current Status and related research/problems/decisions/session after meaningful work or before milestone transitions; record the actual commit and exact next action. Never rely on chat history as durable project memory.

Current milestone: M2 telemetry/oracle. Completed work and known blockers live in Obsidian Current Status and mirrored docs/STATUS.md. Next agent must refresh installation state and fresh logs; old logs are not current proof.

User preference (2026-10-07): keep Astra Medium to conserve credits. Use Capsule/batched compact evidence when useful; avoid needless rereads, model escalation or agent fan-out. Current priority is one or two noticeable features before deeper research. Racing HUD/pedal preview exists; see docs/RACING-HUD.md and Obsidian status for verification limits.

Background-use constraint (2026-10-07): the user is playing Roblox and watching Chrome. User explicitly released the gameplay interruption constraint in this chat and requested continued work. Isolated BeamNG experiments are authorized again; do not interact with unrelated Roblox/Chrome apps. Preserve Claude's assists work; saved-lap archive work is separate.

User direction (2026-10-07): FREEROAM FIRST. Single ACNG master/Advanced app is primary. Track/AI racing work is deferred; no automatic opponent spawning or driving. Read Obsidian ACNG/Freeroam Plan and Track Later. Prioritize road-appropriate thermal/pressure calibration, broader vehicle/damage validation and physical FFB. Car-mod capability was discussed only; do not start a car without a request. See docs/FREEROAM.md and GUI001 evidence.

2026-10-08: Road/Sport presets and GUI002/FR002 compatibility passed; FR001/FR001b
record short road-speed thermal effects, not AC or real-compound calibration.
Stock ETK/Bolide/pickup reset/switch plus ETK puncture/wheel-break checked natively.
User authorized a private GitHub repository and push; github.com/AGames21/ACNG
now exists and origin/main is connected. CLI login is verified.
See docs/PUBLISHING.md and tools/publication_audit.py. No force-push or public
visibility change authorized. Respect the parked road playtest handoff; do not
take controls while the user drives. Physical FFB still requires a real wheel.
