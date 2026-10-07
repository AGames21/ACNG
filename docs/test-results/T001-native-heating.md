# T001 native tire-heating probe

Stock BeamNG ETK K-Series `kc6_360_M`, Small Grid, isolated lab profile, BeamNG 0.39.4. Three runs of accelerate-then-full-brake with the native wheel heating factor set to 0, 0.0001 and 0.01 (grip and pressure effects held off), then factory values restored. Harness: `tests/beamng-thermal`. Raw result: `t001-native-heating.json`.

**Observation:** all 36 wheel snapshots (4 wheels x configured/after-braking/restored x 3 runs) read exactly 288.14246 K for both average and core temperature. No wheel broke or deflated. The configured and restored acknowledgements were received for every run.

**Not concluded:** this does not show that BeamNG has no tire heating, nor that the factor is ignored. Alternative explanations: the getter may read a cached/ambient value, heating may need longer or harder sliding, or the factor may be applied somewhere the probe does not read. No grip or pressure inference is made. Confidence that the readout is constant under this maneuver: high. Confidence about why: low.

Harness fixes kept with this record: the GE side now checks the configured/restored acknowledgements explicitly, and the vehicle probe uses an explicit nil check so a legitimate `false`/`0` factory value is not replaced by the fallback.

Next: before any original thermal model, read the native thermal code path (read-only) to find which value the getter returns, then repeat with a sustained slide.
