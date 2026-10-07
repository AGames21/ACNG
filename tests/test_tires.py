import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIRES = ROOT / "beamng-mod/lua/vehicle/extensions/acng/tires.lua"
CORE = ROOT / "beamng-mod/lua/ge/extensions/acng/core.lua"

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    LuaRuntime = None

# Fake vehicle VM: two tired wheels (one with jbeam thermal fields), one hub without
# a tire, and a wheel whose object is gone (broken off).
VEHICLE = '''
calls={}; sent={}
log=function() end
guihooks={trigger=function(name,data) sent[#sent+1]={name=name,data=data} end}
tableSizeC=function(t) local n=0 while t[n]~=nil do n=n+1 end return n end
local function wheel(id)
  return {setThermal=function(self,...) calls[#calls+1]={id=id,kind='thermal',args={...}} end,
    setFrictionThermalSensitivity=function(self,...) calls[#calls+1]={id=id,kind='curve',args={...}} end}
end
v={data={pressureGroups={pg1=11},
  wheels={[0]={name='FL',wheelID=0,pressureGroup='pg1'},
    [1]={name='FR',wheelID=1,heatCoefFriction=0.02,smokingTemp=500,meltingTemp=600,
         heatAffectsPressure=true,frictionLowTemp=300,frictionCoefLow=0.9},
    [2]={name='HUB',wheelID=2,hasTire=false},
    [3]={name='GONE',wheelID=3}}}}
temps={[0]=363.15,[1]=288.15,[2]=288.15}
obj={getWheel=function(self,id) if id<=2 then return wheel(id) end end,
  getWheelAvgTemperature=function(self,id) return temps[id] end,
  getWheelCoreTemperature=function(self,id) return 300.15 end,
  getGroupPressure=function(self,g) return 26*6894.757+101325 end}
'''


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class TireContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(VEHICLE)
        self.mod = self.lua.execute(TIRES.read_text())
        self.g = self.lua.globals()

    def calls(self):
        out = []
        for i in range(1, len(self.g.calls) + 1):
            c = self.g.calls[i]
            out.append((c.id, c.kind, [c.args[j] for j in range(1, len(c.args) + 1)]))
        return out

    def test_stock_arguments_match_stage2_defaults(self):
        empty = self.lua.eval("{}")
        self.assertEqual(list(self.mod.stockThermal(empty).values()),
                         [0, 0.4, 20, 0, 0, 0, 0, 0, 0, 1e18, 1e19, False])
        self.assertEqual(list(self.mod.stockCurve(empty).values()),
                         [-300, 1e7, 1e-10, 1e-10, 10, 1, 1, 1])
        fr = self.g.v.data.wheels[1]
        thermal = list(self.mod.stockThermal(fr).values())
        self.assertEqual(thermal[6], 0.02)
        self.assertEqual(thermal[9:], [500, 600, True])
        self.assertEqual(list(self.mod.stockCurve(fr).values())[0], 300)

    def test_load_applies_acng_only_to_tires_and_unload_restores_stock(self):
        self.mod.onExtensionLoaded()
        loaded = self.calls()
        self.assertEqual(sorted({c[0] for c in loaded}), [0, 1])  # no hub, no missing wheel
        thermal = {c[0]: c[2] for c in loaded if c[1] == "thermal"}
        curve = {c[0]: c[2] for c in loaded if c[1] == "curve"}
        self.assertEqual(thermal[0][6], 0.05)           # friction heat on
        self.assertGreater(thermal[0][0], 0)            # environment cooling on
        self.assertEqual(thermal[1][9:11], [500, 600])  # wheel keeps its own smoke/melt temps
        # Flat curve: native thresholds out of reach, all three coefficients the ramp value.
        self.assertEqual(curve[0][:5], [-300, 1e7, 1e-10, 1e-10, 10])
        self.assertEqual(curve[0][5:], [1, 1, 1])          # FL at 90 C, inside the window
        self.assertEqual(curve[1][5:], [0.85, 0.85, 0.85])  # FR at 15 C, fully cold
        self.assertEqual(self.g.sent[len(self.g.sent)].data.mode, "on")

        self.g.calls = self.lua.eval("{}")
        self.mod.onExtensionUnloaded()
        restored = self.calls()
        thermal = {c[0]: c[2] for c in restored if c[1] == "thermal"}
        curve = {c[0]: c[2] for c in restored if c[1] == "curve"}
        self.assertEqual(thermal[0], [0, 0.4, 20, 0, 0, 0, 0, 0, 0, 1e18, 1e19, False])
        self.assertEqual(curve[0], [-300, 1e7, 1e-10, 1e-10, 10, 1, 1, 1])
        self.assertEqual(thermal[1][6], 0.02)
        self.assertEqual(curve[1][0], 300)
        self.assertEqual(curve[1][5], 0.9)
        self.assertEqual(self.g.sent[len(self.g.sent)].data.mode, "off")

    def test_snapshot_reports_celsius_psi_and_window(self):
        self.mod.onExtensionLoaded()
        snap = self.mod.snapshot()
        fl, fr = snap.tires[1], snap.tires[2]
        self.assertEqual(fl.name, "FL")
        self.assertAlmostEqual(fl.surface_c, 90.0)
        self.assertAlmostEqual(fl.core_c, 27.0)
        self.assertAlmostEqual(fl.psi, 26.0)
        self.assertEqual(fl.state, "window")
        self.assertEqual(fl.grip, 1)
        self.assertEqual(fr.state, "cold")
        self.assertIsNone(fr.psi)  # no pressure group
        self.assertLess(fr.grip, 1)
        self.assertEqual(len(snap.tires), 2)

    def test_window_state_and_grip_shape(self):
        m = self.mod
        self.assertEqual(m.windowState(20), "cold")
        self.assertEqual(m.windowState(90), "window")
        self.assertEqual(m.windowState(130), "hot")
        self.assertIsNone(m.windowState(None))
        self.assertEqual(m.gripAt(90), 1)
        self.assertEqual(m.gripAt(75), 1)
        self.assertEqual(m.gripAt(105), 1)
        self.assertEqual(m.gripAt(-40), m.COLD_GRIP)
        self.assertLess(m.gripAt(60), 1)
        self.assertGreater(m.gripAt(60), m.gripAt(20))
        self.assertAlmostEqual(m.gripAt(74), 1 - 0.15 / 60)  # no step at the window edge
        self.assertEqual(m.gripAt(300), m.HOT_GRIP)
        self.assertLess(m.gripAt(120), 1)
        self.assertIsNone(m.gripAt(float("nan")))

    def test_grip_follows_temperature_in_steps(self):
        self.mod.onExtensionLoaded()
        self.g.calls = self.lua.eval("{}")
        self.mod.updateGFX(0.05)
        self.assertEqual(self.calls(), [])                  # not due yet
        self.mod.updateGFX(0.06)
        self.assertEqual(self.calls(), [])                  # no temperature change, no write
        self.g.temps[1] = 273.15 + 45                       # FR warms to 45 C
        self.g.temps[0] = 363.15 + 0.1                      # FL moves a hair inside the window
        self.mod.updateGFX(0.1)
        writes = self.calls()
        self.assertEqual([c[0] for c in writes], [1])
        self.assertEqual(writes[0][1], "curve")
        self.assertAlmostEqual(writes[0][2][5], 1 - 0.15 * 30 / 60)
        self.assertAlmostEqual(self.mod.snapshot().tires[2].grip, 0.925)
        self.g.temps[1] = 273.15 + 45.1                     # below the write step
        self.g.calls = self.lua.eval("{}")
        self.mod.updateGFX(0.1)
        self.assertEqual(self.calls(), [])
        self.mod.onExtensionUnloaded()
        self.g.calls = self.lua.eval("{}")
        self.g.temps[1] = 273.15 + 80
        self.mod.updateGFX(0.2)
        self.assertEqual(self.calls(), [])                  # nothing written while OFF

    def test_reset_reapplies_while_active(self):
        self.mod.onExtensionLoaded()
        self.g.calls = self.lua.eval("{}")
        self.mod.onReset()
        self.assertEqual(len(self.calls()), 4)

    def test_no_vehicle_input_or_force_writes(self):
        source = TIRES.read_text()
        for write in ("input.event", "applyForce", "queueLuaCommand", "setGroupPressure", "setGearboxMode"):
            self.assertNotIn(write, source)


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class CoreTireFeature(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        log=function() end
        commands={}; current=5
        local function vehicle(id) return {getID=function() return id end,
          queueLuaCommand=function(self,cmd) commands[#commands+1]=id..':'..cmd end} end
        be={getPlayerVehicle=function() return vehicle(current) end,getObjectByID=function(self,id) return vehicle(id) end}
        saved=nil
        jsonReadFile=function(path)
          if path:find('defaults') then return {schema_version=1,enabled=false,features={tire_temperature=false,abs=false},
            telemetry={enabled=false,rate_hz=50,port=44443}} end
          return saved
        end
        ''')
        self.g = self.lua.globals()

    def load(self):
        mod = self.lua.execute(CORE.read_text())
        mod.onExtensionLoaded()
        return mod

    def cmds(self):
        return [self.g.commands[i] for i in range(1, len(self.g.commands) + 1)]

    def test_tires_need_master_and_feature(self):
        mod = self.load()
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        self.assertTrue(mod.setFeature("tire_temperature", True))
        mod.onUpdate(1)
        self.assertEqual(self.cmds(), [])  # master still OFF
        mod.setEnabled(True)
        mod.onUpdate(1)
        self.assertIn("5:extensions.load('acng_tires')", self.cmds())
        self.assertEqual(mod.getStatus()["physics_writes"], 1)
        self.assertEqual(mod.getStatus()["tires_vehicle_id"], 5)
        mod.setFeature("tire_temperature", False)
        self.assertEqual(self.cmds()[-1], "5:extensions.unload('acng_tires')")
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        mod.setFeature("tire_temperature", True)
        mod.onUpdate(1)
        mod.setEnabled(False)
        self.assertIn("5:extensions.unload('acng_tires')", self.cmds()[-2:])
        self.assertEqual(mod.getStatus()["physics_writes"], 0)

    def test_reserved_features_cannot_be_enabled(self):
        mod = self.load()
        self.assertFalse(mod.setFeature("abs", True))
        self.assertFalse(mod.setFeature("nonsense", True))
        self.assertFalse(mod.getStatus()["features"]["tire_temperature"])

    def test_tires_follow_vehicle_switch_and_respawn(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("tire_temperature", True)
        mod.onUpdate(1)
        self.g.current = 7
        mod.onUpdate(1)
        self.assertIn("5:extensions.unload('acng_tires')", self.cmds())
        self.assertIn("7:extensions.load('acng_tires')", self.cmds())
        n = len(self.cmds())
        mod.onVehicleSpawned(7)
        mod.onUpdate(0.01)
        self.assertIn("7:extensions.load('acng_tires')", self.cmds()[n:])

    def test_runtime_file_only_restores_implemented_features(self):
        self.lua.execute("saved={schema_version=1,enabled=true,features={tire_temperature=true,abs=true}}")
        mod = self.load()
        status = mod.getStatus()
        self.assertTrue(status["enabled"])
        self.assertTrue(status["features"]["tire_temperature"])
        mod.onUpdate(1)
        self.assertIn("5:extensions.load('acng_tires')", self.cmds())

    def test_defaults_keep_tires_off(self):
        import json
        defaults = json.loads((ROOT / "beamng-mod/settings/acng/defaults.json").read_text())
        self.assertFalse(defaults["enabled"])
        self.assertFalse(defaults["features"]["tire_temperature"])


if __name__ == "__main__":
    unittest.main()
