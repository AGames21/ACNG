# ACNG foundation — 2026-10-06

## Installed environment

Windows 11 Home x64 10.0.26200. Existing Git 2.56.0.windows.1, Python 3.12.10, Node 24.15.0, npm 11.12.1, FFmpeg 8.1.2, ripgrep and Steam were executed/verified. Blender and BeamFinds 2.1.4 were detected; Blender compatibility has not been tested. A user JDK25 directory was discovered later; it has not been verified and was not used for REA.

BeamNG 0.39.4.0.20972, Steam build 24617469, is installed in `<Steam>/steamapps/common/BeamNG.drive`. Active user profile resolves to `%LOCALAPPDATA%/BeamNG/BeamNG.drive/current`; existing BeamMP/vehicle mods were left intact. AC installation completed during setup in the H: Steam library, build 14923034; installed changelog reports 1.16.4. Its prior Documents configuration contains an online/modded session, so experiments require explicitly offline temporary overlays.

Exact local paths are in ignored `.local/paths.json` and Obsidian ACNG Current Status. The repository is in this chat's `outputs/ACNG`. Source is Git; durable engineering memory is the existing registered/open vault's `ACNG` area. Twenty initial notes passed required-note and wikilink checks.

## Isolated tools installed/configured

| Tool | Version / pinned source | Evidence |
|---|---|---|
| Universal Modder | 0.2.0; source `6c02e77d9088ecb1a7d9970572d8ca5387e7cb9e` | CLI scans, backups and unchanged BeamNG settings diff |
| REA | 4.1.0; source `bc2cd8b874e115eee446860043758a80bd583ad0` | Ghidra-scoped doctor healthy; MCP handshake/list; original PE fixture analysis |
| Ghidra | 12.1.4 | REA native provider analyzed original fixture |
| Ghidra MCP | 7.0.0; source `4c5e9429eddc7100be6b4d6bad561d69ab86938f` | Extension built for 12.1.4; loopback backend health; MCP handshake/list |
| Temurin JDK | 21.0.12.1+1 | Java version; Ghidra extension build and native analysis |
| Zig | 0.17.0 | Original C++ fixture compiled and executed, output 7.0 |
| CMake / Ninja | 4.4.4 / 1.13.2 | Version commands |
| Lupa | 2.8, LuaJIT 2.1 / Lua 5.1 | Actual mod Lua compilation and lifecycle contract tests |
| Matplotlib | 3.11.2 | Pilot chart rendered and visually reviewed |

All binaries/checkouts live in sibling workspace `work/`, not Git or game installs. Python dependencies use `work/toolchain`; REA uses `work/rea-runtime`. Official portable Java/Ghidra/Zig downloads had published checksums verified. No administrator install/global PATH changes were needed. JDK21 is REA's documented Windows provider target; optional commercial Hopper/IDA providers were not installed. Standalone Lua/luacheck and MSVC were not installed; LuaJIT and the proven Zig C++ compiler cover current validation needs.

REA setup and `codex mcp add` registered stdio servers in the existing Codex configuration, with prior configuration backups. Protocol smoke succeeded using explicit local executables. This does not mean these servers' tools are loaded into the current chat: a new/reconnected client session is required. `tools/start-ghidra-mcp.ps1` starts the local backend when needed. Native game binary analysis has not been performed; only an original fixture was imported.

## Game safety and evidence

Universal Modder backups: primary BeamNG settings (574 files), vehicle configs (11), AC cfg (97). Private archive paths/manifests remain workspace-local. Original game installations were not edited. Isolated BeamNG lab profiles are under `<Documents>/Codex/work/ACNG-lab/current` and `ACNG-b001/current`.

Local loader inspection and official mod/extension documentation established a native Lua extension route. The mod packages `lua/`, `scripts/` and `settings/` at ZIP root. Generic reconnaissance suggestions to add native DLL hooks were unnecessary. No copyrighted vehicle/track assets or copied game Lua are committed.

Real smoke: `docs/test-results/smoke-001.json` records seven successful load/master/telemetry/stop checks; screenshot retained. Default OFF/ON/OFF performs zero physics writes. Actual stock ETK pilot captured 792 packets with no reported gaps and generated analysis/plot; see `docs/test-results/B001-pilot.md`. This is one pilot, not a repeated comparative baseline. Thirteen automated tests passed.

Startup failures were documented: avoid BeamNG's failing `-windowed` flag. Quoted user-path attempts failed; an unquoted no-space isolated path worked, with fresh VFS verification. This is a quoting workaround, not proven MAX_PATH diagnosis. Some unrelated stock log errors remain; no claim that all game logs are error-free.

## First vehicle / next milestone

ETK K-Series `kc6_360_M` vs AC `bmw_1m`: stock RWD turbo inline-six manual candidates, published masses 1520/1495 kg and power 366/native-metadata vs 340 bhp. Differences in running mass, tires, assists, alignment/gearing/aero remain to be frozen. The earlier ETK-four/GT86 candidate had a larger mismatch.

M2 is active: two live AC read-only stationary captures succeeded (733 samples each), reporting AC1.16.4/shared-memory1.7, BMW1M/Magione. AC-generated additional cfg writes were identified; improved full-cfg snapshot restored six changed files automatically on the second run. Full backup diff is clean. See R002 and sanitized test summaries.

Next calibrate units/axes/time/reset boundaries, freeze controls/setup, repeat straight-line tests five times, then skidpad/thermal/suspension/damage runs. All tire/thermal/wear/FFB/assist/racing/environment models remain unimplemented. No physics tuning until comparative measurements and rollback/damage/performance contracts are credible.
