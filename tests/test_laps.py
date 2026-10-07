import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAPS = ROOT / "beamng-mod/lua/vehicle/extensions/acng/laps.lua"

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    LuaRuntime = None

R = 50.0  # circle radius; the start/finish line point (R, 0) lies on it


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class LapTimerContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("log=function() end; guihooks={trigger=function() end}")
        self.mod = self.lua.execute(LAPS.read_text())

    def circle(self, state, arc, speed, seconds):
        # Counter-clockwise around (0, 0) with deliberately uneven frame times.
        dts, t, i = (1 / 60, 1 / 45, 1 / 75), 0.0, 0
        while t < seconds:
            dt = dts[i % 3]; i += 1
            arc += speed * dt; t += dt
            self.mod.step(state, dt, R * math.cos(arc / R), R * math.sin(arc / R), 0)
        return arc

    def new_circle_state(self):
        state = self.mod.newState()
        self.assertTrue(self.mod.setLine(state, R, 0, 0, 1))
        arc = -10.0  # start 10 m before the line
        self.mod.step(state, 1 / 60, R * math.cos(arc / R), R * math.sin(arc / R), 0)
        return state, arc

    def test_constant_speed_laps_sectors_and_delta(self):
        state, arc = self.new_circle_state()
        lap = 2 * math.pi * R / 20.0
        self.assertEqual(self.mod.snapshot(state).mode, "out_lap")
        arc = self.circle(state, arc, 20.0, 0.25 + 3.5 * lap)
        snap = self.mod.snapshot(state)
        self.assertEqual(snap.mode, "lap")
        self.assertEqual(snap.laps, 3)
        self.assertEqual(snap.lap_number, 4)
        self.assertAlmostEqual(snap.last.time_s, lap, places=5)
        self.assertAlmostEqual(snap.last.distance_m, 2 * math.pi * R, places=2)
        self.assertAlmostEqual(snap.best.time_s, lap, places=5)
        self.assertAlmostEqual(sum(snap.last.sectors.values()), snap.last.time_s, places=9)
        for k in (1, 2, 3):
            self.assertAlmostEqual(snap.last.sectors[k], lap / 3, places=4)
            self.assertAlmostEqual(snap.best_sectors[k], lap / 3, places=4)
        self.assertAlmostEqual(snap.optimal_s, lap, places=4)
        self.assertAlmostEqual(snap.delta_s, 0, places=3)  # same pace as the best lap
        self.assertEqual(len(snap.sectors_live), 1)          # half way: sector 1 done
        self.assertEqual(len(snap.history), 3)

    def test_slower_lap_shows_positive_delta_and_keeps_best(self):
        state, arc = self.new_circle_state()
        fast, slow = 2 * math.pi * R / 20.0, 2 * math.pi * R / 16.0
        arc = self.circle(state, arc, 20.0, 0.5 + fast)        # out lap + lap 1
        arc = self.circle(state, arc, 16.0, slow / 2)           # half of a slower lap
        snap = self.mod.snapshot(state)
        self.assertAlmostEqual(snap.delta_s, (slow - fast) / 2, delta=0.03)
        arc = self.circle(state, arc, 16.0, slow / 2 + 0.2)
        snap = self.mod.snapshot(state)
        self.assertAlmostEqual(snap.last.time_s, slow, delta=0.03)
        self.assertAlmostEqual(snap.best.time_s, fast, places=5)
        self.assertEqual(snap.best.lap, 1)
        self.assertGreater(snap.last.sectors[2], snap.best_sectors[2])

    def test_gate_width_reverse_teleport_and_min_lap(self):
        state = self.mod.newState()
        step, snap = self.mod.step, self.mod.snapshot
        self.assertEqual(snap(state).mode, "no_line")
        self.mod.setLine(state, 0, 0, 0, 1)
        step(state, 0.1, 20, -1); step(state, 0.1, 20, 1)          # 20 m wide of the line point
        self.assertEqual(snap(state).mode, "out_lap")
        step(state, 0.1, 5, -1); self.assertTrue(step(state, 0.1, 5, 1))
        self.assertEqual(snap(state).mode, "lap")
        self.assertTrue(step(state, 0.1, 5, -1))                    # backwards over the line
        self.assertEqual(snap(state).mode, "out_lap")
        self.assertEqual(snap(state).note, "reversed")
        step(state, 0.1, 5, 1)                                      # forward again: new lap
        step(state, 0.1, 5, 10)
        self.assertTrue(step(state, 0.1, 5, 200))                   # 190 m in one step
        self.assertEqual(snap(state).note, "teleport")
        self.assertEqual(snap(state).laps, 0)
        # Loops back over the line (return leg outside the gate) that are too
        # quick (4 s, 63 m) or too short (40 s, 40 m) are wobble, not laps.
        for dt, wide, high in ((1.0, 20, 5), (10.0, 16, 3)):
            step(state, 0.1, 0, -1); step(state, 0.1, 0, 1)         # fresh lap (after any reverse)
            start = snap(state).current_s
            for x, y in ((wide, high), (wide, -high), (0, -1), (0, 1)):
                self.assertFalse(step(state, dt, x, y))
            self.assertEqual(snap(state).mode, "lap")
            self.assertAlmostEqual(snap(state).current_s, start + 4 * dt, places=9)
            if dt == 1.0:
                step(state, 0.1, 0, -1)                             # abandon before the next case
        self.assertEqual(snap(state).laps, 0)
        # The same quick loop after enough time and distance does complete a lap.
        for x, y in ((20, 5), (20, -5), (0, -1)):
            step(state, 1.0, x, y)
        self.assertTrue(step(state, 1.0, 0, 1))
        self.assertEqual(snap(state).laps, 1)

    def test_time_at_trace_interpolation(self):
        trace = self.lua.eval("{d={0,2,4},t={0,1,3}}")
        self.assertEqual(self.mod.timeAt(trace, 3), 2)
        self.assertEqual(self.mod.timeAt(trace, 0), 0)
        self.assertIsNone(self.mod.timeAt(trace, 5))

    def test_wiring_reset_pause_clear_and_no_writes(self):
        lua = self.lua
        lua.execute('''
        sent={}; px,py=50,-10
        obj={getPosition=function() return {x=px,y=py,z=0} end,
          getDirectionVector=function() return {x=0,y=1,z=0} end}
        guihooks={trigger=function(name,data) sent[#sent+1]={name=name,data=data} end}
        ''')
        mod = lua.execute(LAPS.read_text())
        g = lua.globals()
        mod.updateGFX(1 / 60)
        self.assertEqual(mod.getSnapshot().mode, "no_line")
        g.py = 0
        self.assertTrue(mod.setLineHere())
        self.assertEqual(g.sent[len(g.sent)].name, "ACNGLaps")
        g.py = 1; mod.updateGFX(0.1)                     # leaving the line forwards is not a crossing
        self.assertEqual(mod.getSnapshot().mode, "out_lap")
        g.py = -1; mod.updateGFX(0.1); g.py = 1; mod.updateGFX(0.1)
        self.assertEqual(mod.getSnapshot().mode, "lap")
        g.py = 3; mod.updateGFX(0.5)
        t = mod.getSnapshot().current_s
        mod.updateGFX(0)                                 # paused: no time passes
        self.assertEqual(mod.getSnapshot().current_s, t)
        mod.onReset()
        self.assertEqual(mod.getSnapshot().mode, "out_lap")
        self.assertEqual(mod.getSnapshot().note, "reset")
        mod.clear()
        self.assertEqual(mod.getSnapshot().mode, "out_lap")  # clear keeps the line
        source = LAPS.read_text()
        for write in ("input.event", "applyForce", "setFriction", "queueLuaCommand", "setGearboxMode", "requestReset"):
            self.assertNotIn(write, source)


if __name__ == "__main__":
    unittest.main()
