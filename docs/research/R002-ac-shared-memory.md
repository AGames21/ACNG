# R002 — AC read-only shared-memory oracle

Question: can installed AC expose useful stock wheel/vehicle telemetry through an external, noninvasive reader?

Build: AC 1.16.4 (Steam build 14923034), reported shared-memory version 1.7. Two explicitly offline stock `bmw_1m` / `magione` practice sessions. No control inputs were sent. Four original configuration overlays selected session/video/assists/Python-app enablement; original game installation was untouched.

Examined: shared-memory documentation PDF mirror for prefix layout, installed changelog/config structure, existing `Local\\acpmf_static`, `physics`, `graphics` pages. Original implementation uses OpenFileMappingW/FILE_MAP_READ with explicit packed fixed-width ctypes fields. No mmap page creation, process attach/injection or proprietary binary analysis.

Observed: both sessions reported expected live status/car/track/version and accepted 733 samples over approximately 15 host seconds at a requested 50 Hz. First trace speed ranged 0.0000177–0.0009598 m/s, RPM 900–902, throttle 0, brake 1, gear neutral. Wheel core temperature read 20, pressure 34.0400 and wear 100; loads/camber/suspension varied slightly as the stationary car settled. Acceleration-g fields were zero at rest, unlike BeamNG's gravity-including stationary native acceleration reading. Native slip values were small but nonzero at rest; they cannot simply be equated to BeamNG slip velocities or an established slip ratio.

Evidence: original JSONL traces are in ignored `telemetry/runs/ac-idle-001.jsonl` and `ac-idle-002.jsonl`; sanitized summaries/hashes are `docs/test-results/ac-smoke-001.json` and `ac-smoke-002.json`. Original private config backups/manifests remain workspace `work/ac-offline-smoke-*`. Initial explicit overlays restored byte-for-byte, but full Universal Modder backup diff discovered AC-generated changes to `acos.ini` and `user_ff.ini`; both were restored from the pre-test backup. Improved launcher snapshots all existing cfg files. Second run automatically restored six changed files; final full backup diff had zero added/removed/changed files.

Confidence: high for live identity, stationary prefix readability, no reader writes, and exact cfg restoration. Medium for documented native channel interpretation. No moving/thermal/grip/FFB behavior is established by this smoke.

Uncertainty: pressure gauge/absolute and unit calibration, tire wear scale semantics, wheel-order verification under asymmetric loading, acceleration axes/steering conventions, packet cadence versus simulated time, session/reset boundaries and channels outside the 200-byte physics prefix. Native physics packet IDs intentionally advance many times between external polls; skipped native IDs are not UDP packet loss. Packet-ID equality is only a partial torn-read check and pages are not atomic together.

Conclusion/ACNG implementation: external read-only AC observation works for this stationary installed-build session. Keep unresolved native fields labeled honestly and maintain separate host observation/lap times; do not use lap time as an uninterrupted simulation clock. Next use controlled motion and setup changes to calibrate semantics before cross-game analysis. No need for Ghidra to answer this question. No physics model has been implemented or tuned.
