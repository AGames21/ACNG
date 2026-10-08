import json
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FFB = ROOT / "beamng-mod/lua/vehicle/extensions/acng/ffb.lua"
CORE = ROOT / "beamng-mod/lua/ge/extensions/acng/core.lua"
DEFAULTS = ROOT / "beamng-mod/settings/acng/defaults.json"

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    LuaRuntime = None

# Fake vehicle VM shaped like hydros.lua: strength 200, low-speed strength 20, a 10-unit
# force limit and an FFB config whose setFFBConfig writes the strength back (as
# hydros.onFFBConfigChanged does).
VEHICLE = r'''
log=function() end
sent={}; ext={}
guihooks={trigger=function(name,data) sent[#sent+1]={name=name,data=data} end}
electrics={values={wheelspeed=0,airspeed=0}}
v={data={input={FFBcoef=1}}}
tableSizeC=function(t) local n=0 while t[n]~=nil do n=n+1 end return n end
wheels={wheels={[0]={name='FL',lastSlip=0,downForceRaw=3000},[1]={name='FR',lastSlip=0,downForceRaw=3000},
  [2]={name='RL',lastSlip=0,downForceRaw=3000}}}
cfg={forceCoef=200,smoothing=150,smoothing2=0,lowspeedCoef=true,responseCorrected=false}
hydros={wheelFFBForceCoef=200,wheelFFBForceCoefLowSpeed=20,wheelFFBForceCoefCurrent=200,
  wheelFFBForceLimit=10,wheelPowerSteeringCoef=1,curForceLimit=10,forceAtDriver=0,testHook=nil}
hydros.getFFBConfig=function() local c={} for k,x in pairs(cfg) do c[k]=x end return c end
hydros.setFFBConfig=function(p)
  cfg={} for k,x in pairs(p) do cfg[k]=x end
  hydros.wheelFFBForceCoef=cfg.forceCoef
  hydros.wheelFFBForceCoefLowSpeed=cfg.lowspeedCoef and cfg.forceCoef/10 or cfg.forceCoef
end
hydros.setExternalForce=function(f) ext[#ext+1]=f end
hydros.getFFBID=function() return -1 end
'''


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class FFBExtension(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(VEHICLE)
        self.g = self.lua.globals()
        self.mod = self.lua.execute(FFB.read_text())

    def hydros(self, key):
        return self.g.hydros[key]

    def test_pure_helpers(self):
        m = self.mod
        self.assertEqual(m.minForceExtra(0, 0.2, 10, 0.5), 0)
        self.assertEqual(m.minForceExtra(3, 0, 10, 0.5), 0)
        self.assertEqual(m.minForceExtra(10, 0.2, 10, 0.5), 0)          # at the limit: nothing
        self.assertAlmostEqual(m.minForceExtra(1, 0.2, 10, 0.5), 0.2 * 9)
        self.assertAlmostEqual(m.minForceExtra(-1, 0.2, 10, 0.5), -0.2 * 9)
        self.assertAlmostEqual(m.minForceExtra(0.25, 0.2, 10, 0.5), 0.5 * 0.2 * 9.75)  # ramp
        self.assertEqual(m.minForceExtra(float("nan"), 0.2, 10, 0.5), 0)
        self.assertEqual(m.kerbHz(0), m.KERB_MIN_HZ)
        self.assertAlmostEqual(m.kerbHz(15), 10)
        self.assertEqual(m.kerbHz(100), m.KERB_MAX_HZ)
        self.assertEqual(m.slipAmount(0), 0)
        self.assertEqual(m.slipAmount(m.SLIP_FULL + 1), 1)
        self.assertAlmostEqual(m.slipAmount((m.SLIP_START + m.SLIP_FULL) / 2), 0.5)

    def test_road_high_pass_forgets_steady_load(self):
        state = self.lua.eval("{}")
        self.assertEqual(self.mod.roadStep(state, 500, 0.01), 0)
        y = self.mod.roadStep(state, 1500, 0.01)
        self.assertGreater(y, 800)
        for _ in range(200):
            y = self.mod.roadStep(state, 1500, 0.01)
        self.assertLess(abs(y), 1)

    def test_sanitize_neutral_and_clamped(self):
        s = self.mod.sanitize()
        self.assertEqual((s.gain, s.min_force, s.filter, s.kerb, s.road, s.slip), (1, 0, None, 0, 0, 0))
        s = self.mod.sanitize(9, 9, 9, 9, 9, -1)
        self.assertEqual((s.gain, s.min_force, s.filter, s.kerb, s.road, s.slip), (2, 0.3, 1, 2, 2, 0))
        self.assertEqual(self.mod.sanitize(float("nan")).gain, 1)

    def test_gain_scales_both_coefficients_and_restores(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1.5, 0, None, 0, 0, 0)
        self.assertEqual(self.hydros("wheelFFBForceCoef"), 300)
        self.assertEqual(self.hydros("wheelFFBForceCoefLowSpeed"), 30)
        self.assertIsNone(self.hydros("testHook"))                       # no effects: no hook
        self.mod.onExtensionUnloaded()
        self.assertEqual(self.hydros("wheelFFBForceCoef"), 200)
        self.assertEqual(self.hydros("wheelFFBForceCoefLowSpeed"), 20)
        self.assertEqual(self.g.sent[len(self.g.sent)].data.mode, "off")

    def test_filter_sets_smoothing_and_restores_config(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1.5, 0, 0.8, 0, 0, 0)
        self.assertEqual(self.g.cfg.smoothing, 240)
        self.assertEqual(self.g.cfg.forceCoef, 200)                      # config keeps stock strength
        self.assertEqual(self.hydros("wheelFFBForceCoef"), 300)          # gain on top
        self.mod.configure(1.5, 0, None, 0, 0, 0)
        self.assertEqual(self.g.cfg.smoothing, 150)
        self.mod.configure(1, 0, 0.2, 0, 0, 0)
        self.mod.onExtensionUnloaded()
        self.assertEqual(self.g.cfg.smoothing, 150)
        self.assertEqual(self.hydros("wheelFFBForceCoef"), 200)

    def test_min_force_hook_adds_force_from_exact_stock_force(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1, 0.1, None, 0, 0, 0)
        hook = self.hydros("testHook")
        self.assertIsNotNone(hook)
        run, pos = hook(0.0005, 0.002, 0)      # stock force 200*1.2*0.002 = 0.48
        self.assertTrue(run)
        self.assertEqual(pos, 0)
        fs = 200 * 1.2 * 0.002
        want = min(1, fs / 0.5) * 0.1 * (10 - fs)
        self.assertAlmostEqual(self.g.ext[len(self.g.ext)] * 200, want, places=9)
        self.mod.onExtensionUnloaded()
        self.assertIsNone(self.hydros("testHook"))
        self.assertEqual(self.g.ext[len(self.g.ext)], 0)

    def test_hook_left_alone_when_someone_else_owns_it(self):
        self.lua.execute("other=function(dt,a,b) return true,b end; hydros.testHook=other")
        self.mod.onExtensionLoaded()
        self.mod.configure(1, 0.1, None, 0.3, 0, 0)
        self.assertTrue(self.lua.eval("hydros.testHook==other"))
        self.assertEqual(self.mod.snapshot().hook, "busy")
        self.mod.onExtensionUnloaded()
        self.assertTrue(self.lua.eval("hydros.testHook==other"))

    def test_slip_buzz_follows_front_slip(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1, 0, None, 0, 0, 1)
        self.mod.updateGFX(0.05)
        self.assertEqual(self.mod.labState().eff.slipA, 0)
        self.g.wheels.wheels[0].lastSlip = 8
        self.mod.updateGFX(0.05)
        self.assertAlmostEqual(self.mod.labState().eff.slipA, self.mod.SLIP_AMP)

    def test_kerb_buzz_needs_rumble_strip_and_speed(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1, 0, None, 1, 0, 0)
        self.g.wheels.wheels[1].contactMaterialID1 = 29
        self.mod.updateGFX(0.05)
        self.assertEqual(self.mod.labState().eff.kerbA, 0)              # parked
        self.lua.execute("electrics.values.wheelspeed=15")
        self.mod.updateGFX(0.05)
        self.assertAlmostEqual(self.mod.labState().eff.kerbA, self.mod.KERB_AMP)
        self.assertAlmostEqual(self.mod.labState().eff.kerbHz, 10)

    def test_player_changes_in_options_become_new_stock(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1.5, 0, None, 0, 0, 0)
        self.lua.execute("hydros.wheelFFBForceCoef=150; hydros.wheelFFBForceCoefLowSpeed=15")
        self.mod.updateGFX(0.3)
        self.assertAlmostEqual(self.hydros("wheelFFBForceCoef"), 225)
        self.mod.onExtensionUnloaded()
        self.assertEqual(self.hydros("wheelFFBForceCoef"), 150)
        self.assertEqual(self.hydros("wheelFFBForceCoefLowSpeed"), 15)

    def test_reset_clears_effects(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(1, 0, None, 0, 0, 1)
        self.g.wheels.wheels[0].lastSlip = 8
        self.mod.updateGFX(0.05)
        self.mod.onReset()
        self.assertEqual(self.mod.labState().eff.slipA, 0)

    def test_source_rules(self):
        source = FFB.read_text()
        self.assertTrue(all(ord(c) < 128 for c in source))
        for write in ("input.event", "applyForce", "setGroupPressure", "obj:set", "queueGameEngineLua"):
            self.assertNotIn(write, source)


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class CoreFFBFeature(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
        log=function() end
        commands={}; current=5; models={[5]='etk800',[7]='pickup'}
        local function vehicle(id) return {getID=function() return id end,
          getJBeamFilename=function() return models[id] end,
          queueLuaCommand=function(self,cmd) commands[#commands+1]=id..':'..cmd end} end
        be={getPlayerVehicle=function() return vehicle(current) end,getObjectByID=function(self,id) return vehicle(id) end}
        saved=nil
        jsonReadFile=function(path)
          if path:find('defaults') then return {schema_version=1,enabled=false,features={ffb=false},
            ffb_settings={gain=1,min_force=0,kerb=0.3,road=0.5,slip=0.3,car_gain={}},
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

    @staticmethod
    def configure(vid, args):
        return f"{vid}:if extensions.isExtensionLoaded('acng_ffb') then extensions.acng_ffb.configure({args}) end"

    def test_ffb_needs_master_and_feature(self):
        mod = self.load()
        self.assertTrue(mod.setFeature("ffb", True))
        mod.onUpdate(1)
        self.assertEqual(self.cmds(), [])
        mod.setEnabled(True)
        mod.onUpdate(1)
        self.assertIn("5:extensions.load('acng_ffb'); " + self.configure(5, "1,0,nil,0.3,0.5,0.3")[2:], self.cmds())
        self.assertEqual(mod.getStatus()["ffb_vehicle_id"], 5)
        self.assertEqual(mod.getStatus()["physics_writes"], 1)
        mod.setFeature("ffb", False)
        self.assertEqual(self.cmds()[-1], "5:extensions.unload('acng_ffb')")
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        mod.setFeature("ffb", True)
        mod.onUpdate(1)
        mod.setEnabled(False)
        self.assertIn("5:extensions.unload('acng_ffb')", self.cmds()[-2:])

    def test_settings_validate_and_reconfigure(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("ffb", True)
        mod.onUpdate(1)
        self.assertEqual(mod.setFFBSetting("gain", 1.5), 1.5)
        self.assertFalse(mod.setFFBSetting("gain", 3))
        self.assertFalse(mod.setFFBSetting("min_force", 0.5))
        self.assertFalse(mod.setFFBSetting("nonsense", 1))
        self.assertEqual(mod.setFFBSetting("filter", 0.8), 0.8)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.configure(5, "1.5,0,0.8,0.3,0.5,0.3"))
        self.assertEqual(mod.setFFBSetting("filter", False), "stock")
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.configure(5, "1.5,0,nil,0.3,0.5,0.3"))

    def test_car_gain_multiplies_gain_per_model(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("ffb", True)
        mod.setFFBSetting("gain", 1.2)
        self.assertEqual(mod.setCarGain(None, 0.5), 0.5)                 # player's car: etk800
        self.assertFalse(mod.setCarGain(None, 5))
        mod.onUpdate(1)
        self.assertIn(self.configure(5, "0.6,0,nil,0.3,0.5,0.3")[2:], self.cmds()[-1])
        status = mod.getStatus()["ffb_settings"]
        self.assertEqual((status["car_model"], status["car_gain"]), ("etk800", 0.5))
        self.g.current = 7
        mod.onUpdate(1)
        self.assertIn("5:extensions.unload('acng_ffb')", self.cmds())
        self.assertIn(self.configure(7, "1.2,0,nil,0.3,0.5,0.3")[2:], self.cmds()[-1])

    def test_runtime_file_restores_settings(self):
        self.lua.execute("saved={schema_version=1,enabled=true,features={ffb=true},"
                         "ffb_settings={gain=0.8,filter=0.4,car_gain={etk800=1.1}}}")
        mod = self.load()
        status = mod.getStatus()
        self.assertTrue(status["features"]["ffb"])
        self.assertEqual(status["ffb_settings"]["gain"], 0.8)
        self.assertEqual(status["ffb_settings"]["filter"], 0.4)
        self.assertEqual(status["ffb_settings"]["car_gain"], 1.1)

    def test_defaults_off_and_neutral_filter(self):
        d = json.loads(DEFAULTS.read_text())
        self.assertFalse(d["enabled"])
        self.assertFalse(d["features"]["ffb"])
        self.assertEqual(d["ffb_settings"]["gain"], 1)
        self.assertEqual(d["ffb_settings"]["min_force"], 0)
        self.assertIsNone(d["ffb_settings"]["filter"])


if __name__ == "__main__":
    unittest.main()
