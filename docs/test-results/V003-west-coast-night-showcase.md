# V003 - West Coast evening showcase

Scope: original lab-only recording tools, stock ETK and Barstow on stock West Coast USA. No private cars/map, no normal-profile changes. Native AI drives only the isolated stock car; no opponents are spawned. Native wear remains authoritative; burnout uses labelled WEAR x10.

Initial run: NightDrive 6/6 native checks, but rejected after visual review: plain-string level start ignored the named spawn, lighting was too dark and the close camera entered the cabin. Changed to the verified by-name spawn API, time 0.30 (subsequently corrected to 0.38), current world bounding-box centre and a wider front-tire camera. Native checks alone did not prove usable footage.

The 02/03 ETK runs also passed 6/6 native checks but remained visually unusable: missing/transparent body surfaces. Root cause is unconfirmed; forcing mesh alpha and opaque paint did not resolve it. These recordings are rejected. Switched to stock Barstow for a fresh attempt. Final native and visual outcomes are recorded below.

Publication: user explicitly authorized pushing and a downloadable release. Keep beta pre-release naming under the existing policy. Player ZIP contains only committed original mod files; no footage or lab harnesses.

## Loading failure and correction

The user closed NightBurn 01 after a UI loading error. Its log records `CEF.MainGEUI ... Error: Timed out while waiting for readiness checks`; no native result JSON exists. Recording was cancelled, with no accepted burn/pop clips. The cancelled recorder cue is explicitly labelled and is not a test pass.

The harnesses had requested map loading while the UI was still initialising. They now defer map loading through BeamNG's native loading-screen callback. A fresh hidden Barstow NightDrive run (`ACNG-night-ui-smoke-20261012-01`) passed 6/6 with no readiness timeout, actual speed 15.224 m/s and headlights on. This supports the startup change, but does not establish a cause for the ETK body-rendering issue.

`film_lab.py` now checks the owned game PID every two seconds and cancels if the game closes. The next fresh NightBurn run combines four stock Barstow cruising angles and the wear burnout, avoiding a second map startup. Acceptance still requires native checks plus visual review.

## Final native and visual outcomes

Fresh NightBurn 03, 04 and 05 each passed 8/8 native checks using a windowed 1440p lab and Windows Graphics Capture. The last run recorded 960 camera updates, 12.036 m/s peak cruising speed and native wear-driven pressure loss at simulation time 54.672 s. All four pressures and tread rows are visible in the reviewed HUD frame. Game-process audio is recorded separately; no desktop or microphone input is used.

Moving-car frames still omit body/wheel flexbodies even with the native orbit camera and explicit graphics quality. The cause remains unconfirmed. All moving night views are rejected; native test passes alone do not establish visual success. The stationary night burnout shows the complete stock Barstow and is accepted. The final cut uses this night burnout plus the previously accepted v2 heat, cooling, tire-camera, dirt and native puncture clips. No AT THE LIMIT banner remains; the steering/suspension caption stays.

Evidence outside Git: `ACNG-film-nightburn-20261012-05/current/acng-nightburn-test.json`, `film/film-cues.json`, reviewed `burn-quality-check.png` and rejected `*-quality-check.png`. Public `docs/assets/night-showcase.png` is from the accepted stationary clip. Raw footage, portable OBS configuration and profiles remain outside the repository.

No normal player profile was changed. v0.3.1-beta was published from 7b35e2d and independently downloaded/hash-verified (R006). Later recording/docs changes do not change its player ZIP. Music is awaiting the maintainer's selection.

## Final cut verification

`acng-tires-v3-night.mp4` remains outside Git. FFprobe: 52.854333 s, 2560x1440 H.264, 60 encoded fps, separate AAC 48 kHz game-audio stream. Full audio/video decode passed; reviewed night-burnout and native-puncture frames show intact car geometry and readable pressure/tread/status rows. Encoded frame rate does not measure native rendering performance. SHA256: `C2CB2B67C4AD6FD39D73DACFAAE2B6A1C567C0873A63E0972DA23E1D734EE059`.

Final offline verification: 287 Python tests, all 10 Node suites, Git whitespace check, README local links and SVG XML passed. The new original banner/overview were rendered headlessly and visually reviewed. No game remains running.
