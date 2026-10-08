# GUI002 / FR002 Road preset compatibility

Fresh isolated BeamNG 0.39.4, West Coast USA. 27 native checks passed, including
all previous unified-app checks plus real Road/Sport DOM selectors, saved Road
selection across native module reload, three stock-vehicle replacements and resets,
and ETK tire damage. Source callbacks ran through BeamNG's actual UI/vehicle VMs.

ETK kc6_360_M, default Bolide and default pickup attached Road heat/wear, then reset
with full tread. These were stationary lifecycle checks, not handling or compound
calibration of each vehicle. Initial tire snapshots are retained in the JSON summary.

With Road active on the ETK: native FL puncture was detected; gauge pressure stayed
below 5 psi; native reset repaired it. Breaking native wheel_FL produced a broken
wheel flag which survived ACNG operation and master OFF. OFF unloaded the tire
extension without repairing damage. Final state had no active physics modules.

Limits: deliberate puncture/break-group injection, not crash-induced bent geometry;
no AI, automated driving, physical FFB or physical mouse input in this test.
Full game-process preference restart and performance/frame-time profiling remain
unverified. The test switched native models, not custom third-party vehicles.
