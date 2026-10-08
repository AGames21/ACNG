# C002 - Local BMW 1M controls and specification target

Date: 2026-10-08. Host: BeamNG.drive 0.39.4; source car: the owner's local AC BMW 1M.
All content and raw evidence remain outside Git; isolated profiles only.

## Investigation

Independent dash/cabin/front-seat/shifter/boot flexbodies replace the whole-interior
binding. Four native props animate steering, throttle, brake and clutch. The
shifter mesh follows the existing ETK manual shifter's deformable nodes.

Initial configurations caused hundreds of thousands of native damage units at
rest. A controlled A/B isolated the uniform chassis node-weight reduction:
new controls plus donor config: zero damage; new engine/gearbox/fuel with native
chassis mass: zero damage; stock engine with reduced chassis mass: ~349,541 damage.
Reducing mass for the numerical target was rejected. Front bumper node shortening
was also rolled back. The native front bar/radiator-support *meshes* are hidden.

The first healthy run passed all 34 checks, but screenshot review exposed misplaced
control meshes: local-origin Collada props need explicit baseTranslation at the
reference node. Added that setting using [BeamNG's props documentation](https://documentation.beamng.com/modding/vehicle/sections/props/).
The steering screenshot input was changed from nearly one full revolution to
153 degrees so visual movement is distinguishable. Placement build passed all 34 native checks: healthy spawn/drive, native damage,
control inputs and shifter motion, master OFF preservation, reset repair.
Driver-view neutral/153-degree wheel screenshots show distinct poses; footwell
view confirms three separate pedals. A metadata-only Custom config label is
receiving its final exact-ZIP validation before installation.

## Latest healthy numerical measurement

- Mass: 1,532.884 kg at 47.7 L initial fuel; donor config 1,534.609 kg at 50 L.
- Native peak power: 333.712 imperial hp = 248.86 kW.
- Native peak torque: 506.910 Nm; fixed peak approximation, no timed overboost.
- Gear ratios: 4.110 / 2.315 / 1.542 / 1.179 / 1.000 / 0.846, final 3.154.
- Fresh spawn damage: zero. Native control meshes created: four.
- Native shifter position changes between first and second gears.

## Validation contract

Donor/spec config spawn health; 15 panel/interior flexbodies; four actual native
prop IDs; control inputs; shifter motion; power/torque and 53 L fuel capacity;
measured mass within 3% of the published reference; drive without self-damage;
crash damage; puncture/lost wheel; drive wreck; master OFF preserves damage;
ON reattaches; reset repairs structure and resets tread.

Offline: 162 Python tests and six Node UI suites passed. Those do not prove
rendering or driving feel. Screenshots/native lab evidence are checked separately.

Pending: exact final ZIP check and normal-profile installation; user road
playtest; BMW/AC handling comparison; rim/glass/mirror/instrument completion.
