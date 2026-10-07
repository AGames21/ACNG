# ACNG foundation prototype

Independent native Lua extension with default-OFF master and reserved feature
toggles. Current master changes perform zero physics writes. Explicitly enabled
telemetry is a passive loopback observer; it is independent of master for stock
baselines. No tire/FFB/racing model is implemented yet.

Install/package with the repository's owned deployment tool. No original game
files or proprietary assets are included. Tested on BeamNG 0.39.4.0.20972 in an
isolated profile; see repository docs/test-results for evidence and limitations.
