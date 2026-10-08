# C001 personal BMW 1M conversion

Setup:
- 2026-10-08, BeamNG 0.39.4, Small Grid
- the user's own AC BMW 1M built with `converters/build_ac_car.py` (output outside the repo), placed only in a fresh isolated lab profile by `scripts/launch-lab.ps1 -ExtraMod`
- harness `tests/beamng-carlab` (GE extension `acng_carlab`), master OFF at start (checked)

The harness follows the FR002b damage path:
1. Spawn `acng_bmw1m` and confirm the AC meshes replaced the ETK skin.
2. Take in-engine screenshots.
3. Switch ACNG on (Road tire heat, wear, ABS, TC).
4. Full throttle for 7 s, then a hard stop.
5. Crash into a parked stock pickup.
6. Apply a native puncture and a native wheel break, then drive the wreck.
7. Master OFF, then ON.
8. Native reset.

**Result: 24 of 24 checks passed on all three runs.** The numbers below are from run 3, the build with the texture fixes.

| Item | Value |
|---|---|
| AC meshes bound as flexbodies | 11 of 11 (body, doors, hood, trunk, bumpers, front/rear lights, interior, steering wheel) |
| ETK body/door/hood/dash meshes left | 0 |
| Flexbodies on the car | 70 (11 AC plus kept ETK mechanical parts) |
| Spawn | at rest, 0 damage |
| ACNG tires | Road profile, 4 of 4 tracked |
| Full-throttle peak | 35.5 m/s, 0 self-damage |
| Crash into pickup | 21.7 m/s, native damage 0 to 41,294 |
| Puncture / wheel break | FL deflated, RL broken (native) |
| Master OFF | tires unloaded, zero physics writes, damage, puncture and lost wheel kept |
| Master ON on the wreck | reattached, values finite |
| Reset | damage 0, wheels repaired, fresh tread, AC meshes still bound |

The screenshots show the AC body deforming on BeamNG's soft-body structure. The hood buckles and lifts, and the front crumples on the ETK nodes. The screenshots live in the lab profile and are not committed.

What changed between runs:
- **Run 1.** The seats rendered green and yellow, and the log had 453 errors. BeamNG rejects AC's uncompressed DDS formats (32-bit ARGB, 24-bit, 16-bit, luminance-alpha). The leather's luminance and alpha were read as red and green. Fix: the exporter now writes those textures as PNG.
- **Run 2.** Two PNGs failed with "stream doesn't contain a PNG". Both were deflated zip entries whose compressed size equalled their size. Fix: the builder now stores entries that don't compress.
- **Run 3.** The log had 12 errors and none were material errors. One 8×8 opacity texture is skipped for cooking (a harmless notice). The rest are BeamNG screenshot-job and level-list messages.

Observed side notes:
- Tread reads 1.0 after `safeTeleport` and after master ON. Both re-create ACNG's tire accounting. That is existing behaviour, not specific to this car.
- The wreck barely moved on a broken wheel (0.65 m/s peak), as expected.

Not tested: handling versus the real 1M (it is ETK K-Series 360 M physics), glass breakage, an animated steering wheel, or the user's normal profile.

Raw summary: `C001-ac-car.json`.
