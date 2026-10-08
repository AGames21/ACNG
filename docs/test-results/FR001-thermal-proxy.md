# FR001 controlled road-speed thermal comparison

BeamNG 0.39.4, isolated Small Grid, ETK K-Series kc6_360_M. Native tire heating,
cooling and pressure remain authoritative; no custom pressure writes. Each set
starts with a physics reset: 10 seconds idle, 40 seconds at a target 22 m/s,
30 seconds turning at target 15 m/s/steer 0.12, 30 seconds cruising, 30 seconds parked.
This is a flat-map road-speed proxy, not a matched city route or AC handling benchmark.

| Setup | Peak surface | Largest pressure rise |
|---|---:|---:|
| Stock/OFF | 15.00 C | 0.30 psi |
| Previous T007 heat | 51.75 C | 0.64 psi |
| Gentler candidate heat | 33.23 C | 0.27 psi |

279 samples per set; all three native startup/OFF completion checks passed.
Machine-readable temperatures, per-wheel pressure changes and achieved speeds:
FR001-thermal-proxy.json. Raw capture stays in the ignored isolated profile.

Observed: halving friction heat (0.06 to 0.03) and reducing core coupling (0.005
to 0.001) lowered heat and pressure rise in this maneuver. Pressure changes include
native rolling/deformation effects: stock rose 0.30 psi without added heat.
Do not attribute every pressure change solely to temperature.

The candidate was sampled with the previous grip window; the shipped Road preset
also uses a milder cold penalty (minimum 98%) and a 35-75 C full-grip window. Those
grip settings are an experimental usability choice, not measured real-tire or AC
constants. Sport preserves the previous heat and 75-105 C grip behavior.

Limits: one configuration, one repetition, short moderate corner. This does not
prove the old +7.8 psi sustained-limit issue is solved, general pressure accuracy,
or a realistic rolling-temperature rise. Native strain heat stays disabled because
its contribution has not been measured. Next: repeat the maneuver through the
final Road preset, sustained-load testing and actual city/twisty-road playtesting.

## FR001b final Road repeat

A fresh isolated profile repeated the same target-speed sequence through the real
core Road preset, with its final grip window, rather than directly swapping thermal
constants. Completed with 267 samples and all three native OFF/lifecycle checks.
Peak surface: **33.87 C**; largest pressure rise: **0.29 psi**. This supports the
direction of the gentler short-run thermal response. It remains a single moderate
repeat, not proof of long-run pressure accuracy or real compound fidelity. See
FR001b-road-final.json for actual achieved speeds and per-wheel measurements.
