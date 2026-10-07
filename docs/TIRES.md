# ACNG Tire Model (heat, grip window and wear)

ACNG's tire model has two parts. Each has its own switch, and both are **OFF by default**.

**Heat and grip window** (`tire_temperature`) switches on BeamNG's own tire heat model and adds an Assetto Corsa-style grip window:

- Cold tires slide. A tire at 15 C has 85 % grip.
- Grip climbs as the tire warms and is full (100 %) from **75 to 105 C** surface temperature.
- Overheated tires fade back toward 85 % by about 145 C.
- Tire pressure rises with heat, and parked tires cool down.

**Wear** (`tire_wear`) wears the tread as the tire slides:

- Every tire starts with 100 % tread.
- Tread wears in proportion to the tire's slip power, so hard cornering, wheelspin and lockups wear it and gentle driving barely does.
- Grip falls in a straight line with tread, down to 85 % on a bald tire.
- With heat also on, a tire above the grip window wears faster, up to twice as fast at 145 C.
- A vehicle reset fits fresh tires.

BeamNG suspension, deformation, damage, punctures and flats are untouched. Turning both parts off restores the stock tire values exactly.

## Use it
1. Install `dist/acng-foundation.zip` the same way as the Racing HUD (see `docs/RACING-HUD.md`).
2. Open **UI Apps**, edit the layout, and add **ACNG Tires**.
3. Click **HEAT OFF** or **WEAR OFF** to turn that part on. Turning a part on also turns on the ACNG master switch. Clicking it again turns only that part off.

Each tire tile shows the surface temperature (big number), its grip, the core temperature and the pressure. The colour bar is blue when cold, green in the window, and amber to red when hot. With wear on, a tread bar shows what is left: green when fresh, amber at half and red when bald. The line under the header shows the grip window and the wear rate.

From GE Lua: `extensions.acng_core.setEnabled(true); extensions.acng_core.setFeature('tire_temperature', true)`, or `'tire_wear'` for wear. Turn a part off with `setFeature('<name>', false)`, or everything with `setEnabled(false)`.

## How it works
- `acng_core` (GE) loads the vehicle extension `acng_tires` into the player vehicle while the master is ON and at least one of `tire_temperature` and `tire_wear` is ON. It unloads the extension when the master goes OFF or both parts are OFF, and it follows vehicle switches. Switching one part while the other stays on calls `acng_tires.configure(heat, wear)` instead of reloading, so the tread carries over.
- With heat on, `acng_tires` reads each tire's stock thermal settings and grip curve, then writes the ACNG heat settings through the native `setThermal`:

  | Setting | Value |
  |---|---|
  | friction heat | 0.05 |
  | node to env | 0.04 (x0.4 when stationary, full at 20 m/s) |
  | node to core | 0.01 |
  | core to nodes | 0.01 |
  | strain, flash and surface heat | 0 |
  | heat affects pressure | yes |

  With heat off (wear only), the stock thermal values stay in place, so the tires stay at ambient temperature as in stock BeamNG. On unload it writes the saved stock values back.
- **Grip.** The native grip curve steps to its low or high value within a few kelvin of its limits, whatever slope you ask for (test T003c). ACNG therefore keeps the native curve flat and sets that one value per tire from Lua every 0.1 s. A new value is written only when it moved by 0.002 or more. The value is the heat grip times the wear grip; a part that is off counts as 1.
- **Grip ramp** (`gripAt`):
  - full grip from 75 to 105 C
  - below 75 C, a straight line down to 0.85 at 15 C
  - above 105 C, a straight line down to 0.85 at 145 C
  - never below 0.85
- **Scale.** The native grip value scales cornering grip almost one to one: a value of 0.9 gave 96 % and 0.8 gave 89 % of stock lateral grip on an ETK K-Series.
- **Reset.** A vehicle reset returns tires to the 15 C ambient and to full tread.

## How wear works
- BeamNG's vehicle wheel table already computes each wheel's slip power every frame (`slipEnergy`; it behaves like watts). ACNG reads it and does not change it.
- Each frame, for each tire: `tread -= slipEnergy * dt * WEAR_RATE * heatMult / WEAR_ENERGY`, and tread never goes below 0. Bad values (NaN, infinite, zero or negative) are skipped.
- `heatMult` is 1 up to 105 C and rises in a straight line to 2 at 145 C. It is always 1 while heat is off.
- Wear grip is `1 - 0.15 * (1 - tread)`: 100 % on a new tire, 85 % when bald.

| Constant | Value | Meaning |
|---|---|---|
| `WEAR_ENERGY` | 7.5e6 | slip energy (J) that takes a tire from new to bald at rate 1 |
| `WEAR_GRIP_LOSS` | 0.15 | grip lost on a bald tire |
| `WEAR_HOT_MULT` | 2 | wear multiplier at 145 C |
| `WEAR_RATE` | 1 | overall speed-up; `setWearRate(r)` in vehicle Lua sets 0 to 100 |

- **Calibration.** In T005 the outer front tire of a stock ETK K-Series cornering at the limit made about 5.7 kW of slip power, and the other three made 1.0 to 2.8 kW. At rate 1 that outer front goes bald after about 22 minutes of nonstop limit cornering inside the grip window, or about 11 minutes when it is overheated. Normal laps with straights wear much more slowly.

## Verification
- `python -m unittest discover -s tests` covers:
  - stock settings saved and restored exactly
  - ACNG heat values and the flat grip curve
  - grip follows temperature in 0.002 steps, only every 0.1 s
  - no writes after unload
  - window states, the ramp ends, NaN and missing data
  - wear off by default, slip power wears tread and costs grip, hot tires wear faster, bad slip power and bad rates, tread floor at 0, reset gives fresh tires, toggling a part keeps the tread, wear without heat keeps the stock thermal values
  - the core load/unload/configure lifecycle for both flags
- `node tests/test_tires_app.js` covers the app view: order, rounding, grip %, colours, tread %, tread bar width and colour, the header line, missing data and Lua tables as objects.
- In-game T004: see `docs/test-results/T004-tire-model.md`. All 16 checks pass on a stock ETK K-Series, including OFF matching stock to 0.01 % and a flat tire still deflating.
- In-game T005: see `docs/test-results/T005-tire-wear.md`. All 19 checks pass: tread falls and lateral grip falls with it (r = 0.995), temperatures do not move while only wear is on, a reset fits fresh tires, both parts run together, a flat still deflates, and OFF again matches stock to 0.02 %.

## Limits
- Tested on one car on one flat map, on a constant-radius circle at the limit. Heat and wear settings are not tuned per car or compound.
- On that circle the outer front tire levels off near 143 C surface and 101 C core, and its pressure rises from 28.5 to 40 psi. That pressure rise is larger than a real road tire. Real laps with straights should run cooler, but this is unchecked.
- Wear rate is checked only on that circle. Wear on real laps, on loose surfaces and during long wheelspin is unchecked.
- The wear rate is not in the app. It can only be changed with `setWearRate` in vehicle Lua, and a reload resets it to 1.
- Worn tread only changes grip. It does not change pressure, heat, rolling resistance or puncture risk, and tread is not kept between sessions.
- There are no compounds, blankets or per-car windows.
- A physical mouse click on the app buttons is unverified. The harnesses sent the buttons' exact commands.
