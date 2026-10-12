# V002 - tire dev showcase v2

2026-10-12. Stock vehicles only; isolated profiles; video files outside Git.

Sequence: title, heat circle, cool-down, door/low-quarter front-wheel shots,
dirt pickup, Barstow burnout, native wear puncture, end card. WEAR x10 is plainly
labelled. No music yet: maintainer selects a properly licensed track.

Native runs pass: TireHeat15/15, TireCam16/16, TireDirt19/19, TireBurn4/4.
See [machine-readable evidence](v2-video-evidence.json), [HUD](GUI005-v2-video-hud.md),
[camera](T009e-v2-tire-camera.md), [burnout](T009f-v2-burnout.md).

OBS portable copy lives outside repo. It records the game surface and only that
process's audio, with desktop/microphone inputs removed. Encoded capture has
2560x1440,60fps and an independent AAC stream. The final cut keeps that stream,
with atempo on accelerated footage and silence on title/end cards. Generated
intermediates/backups are retained outside Git; nothing deleted.

Rejected runs: first1080p resized during loading and missed HUD; initial camera
framing was inside the cabin; initial burnout pressure criterion was too strict.
Each finding was corrected and recorded with separate real evidence.

Final review: 57.854s,2560x1440,60fps, H.264 + independent
AAC stereo48kHz track named BeamNG game audio. Full file decoded without errors;
heat/door/puncture frames inspected, all HUD lines fit. Audio mean-31.0dBFS,
peak-9.4dBFS, non-silent and unclipped. File SHA256:fec78006faa82e19c13a3475dcc304850c7896c762503d1ea047aadae81f0584.
External output:`<workspace>/work/ACNG-shorts/acng-tires-v2.mp4`.
Music remains the maintainer's choice. Only stock ETK/Barstow and stock maps used.
Normal-profile installation, release and push are not part of this delivery.
