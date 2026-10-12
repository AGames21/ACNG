# T009f - real wear and native puncture footage

2026-10-12, BeamNG0.39.4, stock Barstow423m_sport, Small Grid.
Final fresh lab `ACNG-film-tireburn-v2-20261012-02`: **4/4** checks pass.

The lab enables normal ACNG heat/wear, selects Road, holds first gear and partial
brake, then applies throttle. **Wear x10** is explicitly labelled in the video;
this is an accelerated demonstration, not a stock-rate lifetime claim. No tire
physics settings changed; the harness never writes tread or calls deflateTire.

First native wear puncture: 9.547 s after burnout start,
RL. Both rear tires reach zero tread and native isTireDeflated=true. Engine
pressure loss: RL 86.26%,
RR 88.4% of initial gauge pressure.
Raw numbers/checks: [film evidence](v2-video-evidence.json).

Initial run01:3/4 because the check demanded pressure near ambient. Actual native
deflation retains residual pressure (~4psi RL,3.5psi RR), with the native flag
true and a visibly flattened tire. The corrected check requires the engine flag
plus >=75% gauge loss. It passed a fresh run; the rejected criterion is not
silently relabelled as a success.

The footage shows tread decreasing, TREAD0%, PUNCTURED and a visibly flattened
rear tire. Normal settings/profile, private vehicles and Spa were not used.
