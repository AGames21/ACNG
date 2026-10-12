# T009e - car-mounted front-tire footage

2026-10-12, stock ETK K-Series kc6_360_M on Small Grid, fresh isolated profiles.
No converted/private car, no Spa, no normal player profile changes.

The harness follows the body frame in onPreRender with two camera offsets:
door-mounted looking forward/down, then a lower rear-quarter view of the front
wheel. Each shot has film cues. TireHeat controls and checks are retained.

The first filmed run passed 16/16 but put the camera inside the cabin, so those
shots are rejected. getPosition is the off-centre reference node, not the body
centre. The corrected camera uses getSpawnWorldOOBB():getCenter(), with a height
offset, rather than assuming the reference node is centred.

Accepted external profile: `ACNG-film-tirecam-20261012-074624/current`.
Its `../film/door-live.png` shows the outside door/front-wheel view while
steering, with unclipped pressure and GRAIN text. Door/quarter/straight clips
recorded at 1440p with process audio. Final native check counts and clip probes
are collected in the final v2 film report; mocks and camera callback counts
alone never establish correct framing.
