# ACNG engineering journal

2026-10-06: user authorized independent BeamNG mod setup and autonomous evidence-driven work. Inspected Steam manifests, tool versions and local Lua APIs. AC still installing to second Steam library. BeamNG existing user profile has BeamMP, so test using isolated profile. Chosen route: Game Engine/Vehicle Lua extensions with no stock overrides. Universal Modder CLI installed locally and KB/scan executed; generic native hook suggestion rejected in favor of verified host extension APIs. Authored first control plane, passive telemetry reader, collector and analyzer. Runtime status is recorded separately in docs/test-results.

2026-10-06, foundation validation: real isolated BeamNG smoke passed seven checks; stock ETK K-Series pilot captured 792 packets without reported loss and produced crossing/distance analysis and reviewed chart. Native temperatures stayed constant; no thermal-model claim. Fixed launch recipe by removing failing `-windowed` and using an unquoted no-space profile path. Primary settings unchanged. Checkpoint `e807e2e`.

2026-10-06, tooling: isolated Universal Modder, REA4.1, Ghidra12.1.4/JDK21, GhidraMCP7, LuaJIT, plotting and portable native compiler verified. REA analyzed original compiled C++ fixture, not a proprietary game. MCP protocol handshake/list-tools passed; registered tools need client reconnect. Checkpoint `9b04f29`.

2026-10-06, AC oracle: installation completed; two offline BMW1M/Magione stationary shared-memory captures accepted 733 samples each, AC1.16.4/shared-memory1.7. Initial backup diff exposed AC rewriting acos.ini/user_ff.ini; restored these and expanded launcher to snapshot all cfg. Second run restored six changed files automatically; full diff clean. Channel semantics/moving/reset tests remain incomplete. Checkpoint `2a73fbe`.

2026-10-06, persistent memory: located existing open Obsidian vault, created only ACNG notes, added resume/update rules to repository AGENTS.md and read-only vault health checker. Existing notes are read and backed up before updates. M2 calibration/repeated baselines next; all dynamics/FFB/racing models remain unimplemented.
