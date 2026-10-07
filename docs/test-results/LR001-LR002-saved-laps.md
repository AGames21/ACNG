# LR001 / LR002 - Saved lap references

BeamNG 0.39.4, isolated profile, stock ETK K-Series kc6_360_M, Small Grid. **9/9 native checks passed.** No primary user profile or stock game files changed.

LR001 drove a real lap (10.64619860656 s, 125.10803357199 m), received a native save acknowledgement, verified the JSON archive, reloaded the GE/vehicle modules, and verified the reference returned. CLEAR persisted across a second reload. Five checks passed.

LR002 closed the first game process (PID 9752) and started another (PID 22412). Because LR001 intentionally cleared the primary record, its real-lap `.previous` backup was restored in the isolated profile; the cleared archive was preserved separately. No synthetic lap was seeded. The new game restored the identical best time, all three sector values and reference length, with the line present, zero session laps and master OFF before enabling. Four checks passed. Both owned game processes were closed after completion.

Evidence: `lr001-lap-records.json`, `lr002-lap-restart.json`. Original archive hash is embedded in LR002. Local profiles and source manifests are recorded in ignored `.local/lap-records-*.json`.

Limits: one car/map; map/tuning isolation remains covered offline only. No physical mouse-click test or competitive route validation. Restored line presence is proven by `out_lap`; precise crossing position and live-delta accuracy after a full restart were not remeasured. Existing lap-math tests cover the restored trace logic. This does not validate unrelated assists, FFB or race sessions.
