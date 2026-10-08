# P001 pit service in game

Setup:
- 2026-10-08, BeamNG 0.39.4, Small Grid, ETK K-Series `kc6_360_M`
- a fresh isolated lab profile, master OFF at start
- harness `tests/beamng-pitlab` (GE extension `acng_pitlab`)

The ACNG control panel was opened through a temporary lab layout. Every main step went through the panel's real buttons: master ON, Advanced, the Pits tab, Enable pit services, Fresh tread, Mark box here and Start service. The harness then emptied the tank to 5 L and wore every tire to 0.867 tread before the service started.

## Runs
| Run | Result | Notes |
|---|---|---|
| P001 (Codex) | 1 of 13 | Stopped at the first vehicle probe ("Native wait timeout"). |
| P001a | 1 of 13 | Same stop, now with stage tracking. App clicks were confirmed to reach the page. Cause: the probe sent `code..';local r=...'`. With an empty `code` the chunk starts with `;`, which LuaJIT rejects as a syntax error, so the probe never answered. Harness bug, not a pit bug. |
| P001b | **13 of 13** | Probe joined with a newline. Fresh profile. Raw results: `P001-pit-service.json`. |
| P001c | **13 of 13** | Same harness against the shipped `dist/acng-freeroam.zip` (source `1fc97d8`) instead of the source folder; the ZIP is the one now in the normal profile. Raw results: `P001c-pit-service-zip.json`. |

## P001b results
| Check | Result |
|---|---|
| Startup with master OFF | pass |
| Real panel clicks load `acng_pits` in the car | pass |
| Marked box contains the stopped car | pass |
| Start service begins the countdown | pass |
| Service finishes after the 20 s refuel | pass, "Service complete; damage and tire heat preserved" |
| Native fuel tank filled | pass, 5.00 L to 50.00 L of 50 (native `setRemainingVolume`, leak 0) |
| ACNG tread fresh | pass, 0.867 to 1.000 on all four tires; grip 0.96 to 0.98 (Road cold grip) |
| Native puncture created (`beamstate.deflateTire`) | pass, FL 28.4 to 2.8 psi |
| Tread service refused with a punctured tire | pass, "Damaged or unavailable wheel: tread service refused" |
| Puncture stays after the refusal | pass |
| Fuel-only service still starts with the puncture | pass |
| Master OFF unloads pit service and tires | pass |
| Puncture stays after master OFF | pass |

The click log shows `disabled` after some buttons. The harness reads the state just after clicking, and the panel disables its buttons while a command is in flight, so `disabled` there means the click was taken.

## Not checked
- A real driver parking in a box by hand, and leaving during a service (cancel on movement is covered offline).
- Spa or any real pit lane. Spa needs the user to download the map first.
- Physical mouse clicks (the harness clicked the panel's buttons through the page).
