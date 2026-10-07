# ACNG foundation prototype

Independent native Lua extension with default-OFF master and reserved feature
toggles. Current master changes perform zero physics writes. Explicitly enabled
telemetry is a passive loopback observer; it is independent of master for stock
baselines. No tire/FFB/racing model is implemented yet.

Install/package with the repository's owned deployment tool. No original game
files or proprietary assets are included. Tested on BeamNG 0.39.4.0.20972 in an
isolated profile; see repository docs/test-results for evidence and limitations.

## Racing HUD preview
The original ACNG Racing HUD app adds speed (mph/km/h), gear, RPM and progressive near-redline lights, plus independently hideable throttle/brake/clutch bars. In BeamNG UI Apps, add **ACNG Racing HUD**, then click its OFF button to enable the ACNG master. Missing/stale data displays a dash. No physics settings are changed. Master defaults OFF each session. Install the packaged ZIP in your active user folder mods directory, or use the isolated preview profile; do not extract it into the game installation.
