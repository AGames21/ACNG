# GUI004 minimal transparent HUD

BeamNG 0.39.4, isolated lab profile, West Coast USA, stock ETK K-Series plus the Bolide and
pickup checks carried over from GUI002. No driving inputs. **37/37 native checks passed.**

Player request: drop the speedometer cluster and make the HUD minimal, out of the way and
transparent.

- ACNG Control collapses to a 150 x 32 translucent pill (`ACNG` plus an ON/OFF status dot,
  background alpha 0.32). It fades to 70% until hovered. Advanced opens a 290 x 410 panel
  with a darker background (alpha 0.84) so the controls stay readable.
- ACNG Tires is a transparent panel (no background) with four small tiles, 210 x 130, in
  the bottom-right corner. Each tile has a coloured left edge for temperature, the surface
  temperature, grip (heat on) or psi, and a thin tread bar (wear on). While the tire model
  is off only a faint `TIRES  HEAT  WEAR` header shows; no tiles.
- `scripts/minimal_hud.py --confirm-normal` removes the native tacho, boost gauge,
  powertrain buttons, drag-race app and the ACNG racing HUD from the player's freeroam
  layout and places the two ACNG apps. It refuses while BeamNG runs, checks the profile
  identity, backs up the layout first and prints the restore path. The damage app, input
  hints and message apps stay.

New checks: `compact_collapsed_size`, `collapsed_pill_translucent`,
`tires_hidden_while_off`, `tire_tiles_show_four`, `tire_tiles_compact`,
`tire_panel_transparent`. All GUI001/GUI002 control, puncture and road-compatibility checks
still pass. 252 Python tests and the Node suites pass.

Screenshot review (collapsed, master ON, expanded) confirms a clear screen with the pill top
right and the tiles bottom right. Screenshots stay in the private lab profile. Untested:
physical mouse input, the player's own layout after the script runs (applied after this
record), and readability at other resolutions.
