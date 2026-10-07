# ACNG Racing HUD preview

Two visible features: an original compact racing dashboard (gear, speed, RPM and progressive near-redline lights), and an independently hideable live throttle/brake/clutch monitor. Click MPH/KM/H to switch units. Click ON/OFF to control the ACNG master. Master defaults OFF each session; this version changes no driving physics.

Install the ZIP from `dist/acng-foundation.zip` into the **mods** directory of your active BeamNG user folder. Keep it zipped. Use BeamNG's user-folder shortcut to locate that directory; never copy it over the game installation. Avoid installing both unpacked and zipped ACNG copies in the same profile.

Open **UI Apps**, edit the layout, add **ACNG Racing HUD**, and leave editing mode. Click the HUD's OFF button to enable ACNG. Resize/reposition using BeamNG's normal app editor. PEDALS hides/shows the pedal monitor. An unavailable channel displays a dash; stale streams clear rather than showing old speed indefinitely.

Only the isolated lab profile was used for runtime tests. The primary profile/layout remains untouched. Removing the app from a layout removes its stream subscriptions; disabling/uninstalling the ACNG mod restores the ordinary UI experience.

Shift lights indicate the fraction of the engine's native maximum-RPM value. They are not a vehicle-specific optimum-shift calculator. No tire thermal model, lap timing or FFB changes are included yet. Pedal bars show BeamNG's native electrics values, which can differ from a controller's raw input.

Verification: `node tests/test_hud.js` covers conversion, reverse/neutral display, missing channels, invalid RPM limits and pedal clamping. Existing Python regression suite:23 passed. Live HUD001 rendered native streams/shift lights/pedal bars in BeamNG0.39.4; corrected numeric reverse label before final HUD002. Test-only harness under `tests/beamng-hud` is excluded from the distributable ZIP.

Reproduce the isolated scene with `scripts/launch-lab.ps1 -Experiment HUD -LabUser <fresh-no-space-profile/current>`. This harness briefly applies test controls; it is for development verification, not the normal mod installation.

HUD002: live rendering confirmed in the isolated game (neutral gear, native RPM, changing brake percentage, clutch and shift lights); native route closes the menu automatically. The actual mouse-button interaction check was blocked by foreground remoting_desktop. Directive/engine-bridge toggle and cleanup checks passed locally; a physical click check remains. No input was sent to the remote-desktop window.
