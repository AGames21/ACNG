# GUI005 - taller tire HUD for dev video v2

2026-10-12. Stock ETK K-Series, fresh TireHeat lab, BeamNG 0.39.4.

The player reported rear pressure and GRAIN text clipping. Tire app and film
layout now use 220x210 px, bottom 60 px. Tags get a separate wrapping line.
Wear ON also shows an explicit TREAD percentage above its bar; wear OFF hides both.
Normal player settings/install were not modified.

## Native evidence

Accepted external profile: `ACNG-film-tireheat-20261012-073445/current`.
Frame `../film/hud-check.png`: all four pressure lines and GRAIN labels visible.
Recording probe: 2560x1440, 60 fps, independent 48 kHz AAC audio stream.
Heat-clip audio: mean -39.4 dBFS, peak -18.6 dBFS (non-silent).
TireHeat result and burnout-specific wear frame are checked in the final film
report; do not infer wear/puncture proof from this heat frame.

## Recording findings

The first 1080p TireHeat lab passed 15/15, but its window resized after recording
started and the capture region missed the HUD. That footage is rejected.
Lab-only fullscreen settings and portable OBS game capture follow the game's
actual surface. OBS captures only the game process audio, never desktop/mic.
Portable first-launch wizard can block recording despite a working websocket;
the recorder dismisses only its own wizard and verifies outputActive.

The native UI scales from its 1080p canvas at 1440p; the video inset accounts for
this rather than treating HUD dimensions as fixed output pixels.
