# C007 - 1M wheel fitment and crash visuals (run by Codex)

Date: 2026-10-08. BeamNG 0.39.4, isolated lab profile ACNG-car-020. Build fix-004,
local, not released.

## Result

46/46 JSON checks passed, but the crash visuals were judged a **FAIL**: damaged
panels stretched into long spikes. Steering direction and the clutch/foot-rest
mix-up were not verified in this run.

Log findings:

- The 4x4 lamp glow PNGs were skipped by the texture cooker ("minimum 16x16").
- Mip-chain warning on the interior display glass texture (dash work is paused).
- Global-variable warnings for the lab's own probe helpers (`acngFit`, `acngJ`).
- The lab's fitment probe mixed world and jbeam node positions and reported a
  3.11 m wheelbase. That number was wrong; C008 measures it from jbeam positions.

## Follow-up

All of these were fixed or re-measured in [C008](C008-1m-crash-isolation-steering-pedals.md).
