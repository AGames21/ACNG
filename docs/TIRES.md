# ACNG Tire Model (heat and grip window)

The first ACNG physics feature. It switches on BeamNG's own tire heat model and adds an Assetto Corsa-style **grip window**:

- Cold tires slide. A tire at 15 C has 85 % grip.
- Grip climbs as the tire warms and is full (100 %) from **75 to 105 C** surface temperature.
- Overheated tires fade back toward 85 % by about 145 C.
- Tire pressure rises with heat, and parked tires cool down.

BeamNG suspension, deformation, damage, punctures and flats are untouched. The feature is **OFF by default**, and turning it off restores the stock tire values exactly.

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG Tires**.
3. Click **OFF** so it turns **ON**. This turns on the ACNG master switch and the tire model. Clicking **ON** again turns only the tire model off.

Each tire tile shows the surface temperature (big number), its grip, the core temperature and the pressure. The colour bar is blue when cold, green in the window, and amber to red when hot.

From GE Lua: `extensions.acng_core.setEnabled(true); extensions.acng_core.setFeature('tire_temperature', true)`. Turn it off with `setFeature('tire_temperature', false)` or `setEnabled(false)`.

## How it works
- `acng_core` (GE) loads the vehicle extension `acng_tires` into the player vehicle only while the master and `tire_temperature` are both ON. It unloads the extension when either goes OFF, and it follows vehicle switches.
- On load, `acng_tires` reads each tire's stock thermal settings and grip curve, then writes the ACNG heat settings through the native `setThermal`:

  | Setting | Value |
  |---|---|
  | friction heat | 0.05 |
  | node to env | 0.04 (x0.4 when stationary, full at 20 m/s) |
  | node to core | 0.01 |
  | core to nodes | 0.01 |
  | strain, flash and surface heat | 0 |
  | heat affects pressure | yes |

  On unload it writes the saved stock values back.
- **Grip.** The native grip curve steps to its low or high value within a few kelvin of its limits, whatever slope you ask for (test T003c). ACNG therefore keeps the native curve flat and sets that one value per tire from Lua every 0.1 s, from the tire's surface temperature. A new value is written only when it moved by 0.002 or more.
- **Grip ramp** (`gripAt`):
  - full grip from 75 to 105 C
  - below 75 C, a straight line down to 0.85 at 15 C
  - above 105 C, a straight line down to 0.85 at 145 C
  - never below 0.85
- **Scale.** The native grip value scales cornering grip almost one to one: a value of 0.9 gave 96 % and 0.8 gave 89 % of stock lateral grip on an ETK K-Series.
- **Reset.** A vehicle reset returns tires to the 15 C ambient, so they are cold again after a reset.

## Verification
- `python -m unittest discover -s tests` covers:
  - stock settings saved and restored exactly
  - ACNG heat values and the flat grip curve
  - grip follows temperature in 0.002 steps, only every 0.1 s
  - no writes after unload
  - window states, the ramp ends, NaN and missing data
  - the core load/unload lifecycle
- `node tests/test_tires_app.js` covers the app view: order, rounding, grip %, colours, missing data and Lua tables as objects.
- In-game T004: see `docs/test-results/T004-tire-model.md`. All 16 checks pass on a stock ETK K-Series, including OFF matching stock to 0.01 % and a flat tire still deflating.

## Limits
- Tested on one car on one flat map, on a constant-radius circle at the limit. Heat settings are not tuned per car or compound.
- On that circle the outer front tire levels off near 143 C surface and 101 C core, and its pressure rises from 28.5 to 40 psi. That pressure rise is larger than a real road tire. Real laps with straights should run cooler, but this is unchecked.
- No tire wear yet (next feature). There are no compounds, blankets or per-car windows.
- A physical mouse click on the app button is unverified. The harness sent the button's exact commands.
