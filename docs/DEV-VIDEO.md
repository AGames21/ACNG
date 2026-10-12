# Dev video v2

Lab-only workflow, stock vehicles/maps only. Warn the maintainer before every film
run. Refuse an active BeamNG instance. Never update the normal profile, delete
files, publish a release or push without the required authorization.

Tire app default/film layout: 220x210 px, bottom 60 px. Status tags wrap on their
own line; all four pressure lines and wear bars need fresh-frame inspection.

1440p: `film_lab.py --size 2560x1440` uses fullscreen in a fresh lab profile.
Pass `--obs-portable <external-portable-OBS-root>` to record the native game
surface plus `wasapi_process_output_capture`, bound to the game executable.
Only game audio is routed to the recording; no microphone/desktop mix. Portable
OBS config is backed up on startup; user's OBS config is never touched.
Install `obsws-python` in the developer venv. Existing OBS bin/data/obs-plugins
can be copied outside the repository, with a portable_mode.txt marker.
Add `.acng-film-obs-owned` containing `acng-video-tool-only` to that dedicated copy;
the recorder refuses to configure an unowned OBS directory.

TireCam T009e follows the car frame in onPreRender: door/front-wheel and low
quarter views. Its checks prove camera updates; footage must separately prove
framing. TireBurn T009f uses stock Barstow 423m_sport with lab WEAR x10, explicitly
labelled. It never sets tread directly or forces deflation: wear must reach zero,
then native pressure loss must be measured. Keep the post-puncture shot.

`cut_short.py tools/shorts/tires-v2.json --size 2560x1440 --audio ...` keeps game
sound in a separate AAC stream; cards get silence. Speed changes chain valid
atempo factors. Raw clips and final videos must stay outside the repo.

Runtime results and accepted screenshot paths are recorded in the v2 test report
and the private engineering notebook. A build or offline test is not film proof.
