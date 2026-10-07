# First driving playtest: tire heat and grip

This is the first driving-feature feedback gate. Stop adding side features until the user has tried it. BeamNG remains responsible for suspension, deformation and damage. The current heat/grip settings are a prototype, not AC-calibrated.

Prepared scene: stock ETK K-Series kc6_360_M, Hirochi Raceway, ACNG Tires and Racing HUD visible. Master, HEAT and WEAR start OFF. The scene sets up once and never drives or tunes the car for you. It lives in a separate profile and leaves the normal UI/mod setup alone; bindings may differ in this fresh profile.

1. Drive a stock lap, choose one medium-speed corner and note your entry speed.
2. Click HEAT OFF to enable heat (this also enables master), leave WEAR OFF, and reset to the same start.
3. Try the same corner at roughly the same entry speed while the tires are blue/cold. Continue until the relevant tire surfaces approach green (75-105 C), then compare again. Ease off if they turn hot/red.
4. Report: **cold tires too slippery / about right / barely different? Warm tires stable or suddenly snappy?** If temperatures never reach green during normal laps, report that instead.

Master OFF restores factory settings. For a fresh stock A/B run also reset the vehicle; disabling settings does not establish that the accumulated heat/pressure state instantly equals a fresh car. Wear is deliberately excluded from this first test.

Prior evidence: T004 16 checks and T005 19 checks, stock ETK on Small Grid. This is the first human road-course evaluation, not a verified handling match to AC. Known limitation: pressure rose about 11.5 psi on the sustained limit-circle test, and needs calibration. FFB, compounds, assists and complete race sessions are not being claimed here.

Next: adjust this feature using the user's feedback and telemetry, then move to the native ABS/TC feature after reconciling Claude's unfinished work. No more lap-timer work unless a blocker appears.
