# R006 - Clearer tire HUD release

2026-10-12: the maintainer explicitly requested a push and real downloadable release.

- Published [v0.3.1-beta](https://github.com/AGames21/ACNG/releases/tag/v0.3.1-beta), not a draft. Beta naming preserves the maintainer's existing policy.
- Source: `7b35e2da7238a6acce88886f7635b7c66b4acda9`.
- ZIP SHA256: `26ccb3cdd2d61e7937c0943cd62b13714ecc19da817088a3a29080946404d0de`.
- Downloaded both assets from GitHub into a fresh external verification folder; downloaded ZIP hash matches downloaded manifest.
- ZIP integrity passed. Inspected the packaged tire app: height 210px, bottom 60px, explicit TREAD row. Only 26 committed original player files; no lab harnesses, footage, private cars or maps.
- Native HUD/tire evidence from V002: heat 15/15, camera 16/16, dirt 19/19, wear/puncture 4/4. Release-source suite: 283 Python checks and 10 Node suites. Current cinematic tooling adds three safety tests (286 total); these do not change player physics.
- Publication audit before push: 370 tracked files / 763 historical blobs passed. Remote main advanced to the exact release-source commit without force-push.

Normal profile and installed mod were not changed. Existing custom UI layouts retain their saved dimensions; users may need to resize their tire app after installing the new ZIP.

Later cinematic-only source commits do not alter this release's source hash or player ZIP.
