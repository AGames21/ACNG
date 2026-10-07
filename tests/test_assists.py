import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSISTS = ROOT / "beamng-mod/lua/vehicle/extensions/acng/assists.lua"
CORE = ROOT / "beamng-mod/lua/ge/extensions/acng/core.lua"

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    LuaRuntime = None

# Fake vehicle VM shaped like A001: two braked wheels with native ABS (front 0.2, rear
# 0.13), a rotator with no brake functions, and CMU traction control components that
# apply setParameters to their own state the way CMU.applyParameter does.
VEHICLE = r'''
log=function() end
sent={}; refreshes=0
guihooks={trigger=function(name,data) sent[#sent+1]={name=name,data=data} end}
settings={getValue=function(k) return 'realistic' end}
electrics={values={airspeed=0,hasABS=1}}
local function noabs() end
local function yesabs() end
wheels={wheelRotatorCount=3, wheelRotators={
  [0]={name='FL',hasABS=true,slipRatioTarget=0.2,updateBrakeNoABS=noabs,updateBrakeABS=yesabs,isPropulsed=false,radius=0.3,angularVelocity=0},
  [1]={name='RL',hasABS=true,slipRatioTarget=0.13,updateBrakeNoABS=noabs,updateBrakeABS=yesabs,isPropulsed=true,radius=0.3,angularVelocity=0},
  [2]={name='SHAFT',hasABS=false,slipRatioTarget=0.18,hasTire=false,isPropulsed=true,radius=0.1,angularVelocity=900}},
  setWheelBrakeUpdate=function(name,a,b) refreshes=refreshes+1 end}
function makeComp(threshold)
  local state={isEnabled=true,groups={mainEngine={slipThreshold=threshold}}}
  local c={state=state}
  c.getConfig=function()
    return {isEnabled=state.isEnabled,tractionControl={isEnabled=true,
      wheelGroupSettings={mainEngine={slipThreshold=state.groups.mainEngine.slipThreshold}}}}
  end
  c.setParameters=function(p)
    for k,v in pairs(p) do
      if k=='isEnabled' then state.isEnabled=v
      else
        local g=k:match('^tractionControl%.wheelGroupSettings%.(.-)%.slipThreshold$')
        if g then state.groups[g].slipThreshold=v end
      end
    end
  end
  return c
end
cmu={tc=makeComp(nil),motor=makeComp(0.12),brake=makeComp(0.1)}
hasCMU=true; hasESC=false
controller={getControllersByType=function(t)
  if hasCMU then
    if t=='drivingDynamics/supervisors/tractionControl' then return {cmu.tc} end
    if t=='drivingDynamics/supervisors/components/motorTorqueControl' then return {cmu.motor} end
    if t=='drivingDynamics/supervisors/components/brakeControl' then return {cmu.brake} end
  end
  if hasESC and t=='esc' then return {{}} end
  return {}
end}
'''


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class AssistContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(VEHICLE)
        self.mod = self.lua.execute(ASSISTS.read_text())
        self.g = self.lua.globals()

    def tf(self):
        return self.lua.eval("electrics.values.throttleFactor")

    def rot(self, i):
        wd = self.g.wheels.wheelRotators[i]
        return wd.hasABS, wd.slipRatioTarget

    def tc_state(self):
        return (self.g.cmu.tc.state.isEnabled, self.g.cmu.motor.state.groups.mainEngine.slipThreshold,
                self.g.cmu.brake.state.groups.mainEngine.slipThreshold)

    def load(self, abs_level=None, tc_level=None):
        self.mod.onExtensionLoaded()
        self.mod.configure(abs_level, tc_level)

    def test_level_parsing(self):
        self.assertEqual([self.mod.level(x) for x in (0, 1, 2, 3, 2.7)], [0, 1, 2, 3, 2])
        for bad in (None, -1, 4, "2", float("nan")):
            self.assertIsNone(self.mod.level(bad))

    def test_factory_levels_change_nothing(self):
        self.load()
        self.assertEqual(self.rot(0), (True, 0.2))
        self.assertEqual(self.rot(1), (True, 0.13))
        self.assertEqual(self.tc_state(), (True, 0.12, 0.1))
        self.assertIsNone(self.tf())

    def test_abs_levels_and_restore(self):
        self.load(0)
        self.assertEqual(self.rot(0), (False, 0.2))
        self.assertEqual(self.rot(1), (False, 0.13))
        self.assertGreater(self.g.refreshes, 0)        # brake functions re-picked
        self.mod.configure(3, None)
        self.assertEqual(self.rot(0), (True, 0.12))
        self.assertEqual(self.rot(1), (True, 0.12))
        self.assertEqual(self.rot(2), (False, 0.18))   # no brake functions: untouched
        self.mod.configure(1, None)
        self.assertEqual(self.rot(0), (True, 0.25))
        self.mod.configure(None, None)
        self.assertEqual((self.rot(0), self.rot(1)), ((True, 0.2), (True, 0.13)))
        self.mod.configure(2, None)
        self.mod.onExtensionUnloaded()
        self.assertEqual((self.rot(0), self.rot(1), self.rot(2)), ((True, 0.2), (True, 0.13), (False, 0.18)))
        self.assertEqual(self.g.sent[len(self.g.sent)].data.mode, "off")

    def test_abs_can_be_added_to_a_car_without_it(self):
        self.lua.execute("wheels.wheelRotators[0].hasABS=false; wheels.wheelRotators[1].hasABS=false")
        self.load(2)
        self.assertEqual(self.rot(0), (True, 0.18))
        self.mod.onExtensionUnloaded()
        self.assertEqual(self.rot(0), (False, 0.2))
        self.assertEqual(self.rot(1), (False, 0.13))

    def test_bare_rotator_keeps_stock_abs(self):
        self.lua.execute("local w=wheels.wheelRotators; w[2].hasABS=true; w[2].updateBrakeABS=w[0].updateBrakeABS; w[2].updateBrakeNoABS=w[0].updateBrakeNoABS")
        for level in (0, 3, 1):
            self.load(level) if level == 0 else self.mod.configure(level, None)
            self.assertEqual(self.rot(2), (True, 0.18))
        self.assertEqual(self.rot(0), (True, 0.25))

    def test_cmu_tc_levels_and_restore(self):
        self.load(None, 0)
        self.assertEqual(self.mod.getTCMode(), "cmu")
        self.assertEqual(self.tc_state()[0], False)
        self.mod.configure(None, 3)
        enabled, motor, brake = self.tc_state()
        self.assertTrue(enabled)
        self.assertAlmostEqual(motor, 0.08)
        self.assertAlmostEqual(brake, 0.064)
        self.mod.configure(None, 1)
        self.assertAlmostEqual(self.tc_state()[1], 0.25)
        self.mod.onExtensionUnloaded()
        self.assertEqual(self.tc_state(), (True, 0.12, 0.1))
        self.assertIsNone(self.tf())  # CMU cars never get the electric

    def test_cmu_restore_keeps_a_stock_tc_that_was_off(self):
        self.lua.execute("cmu.tc.state.isEnabled=false")
        self.load(None, 2)
        self.assertTrue(self.tc_state()[0])
        self.mod.configure(None, None)
        self.assertEqual(self.tc_state(), (False, 0.12, 0.1))

    def test_esc_car_is_left_alone(self):
        self.lua.execute("hasCMU=false; hasESC=true")
        self.load(None, 3)
        self.assertEqual(self.mod.getTCMode(), "none")
        self.lua.execute("electrics.values.airspeed=10; wheels.wheelRotators[1].angularVelocity=60")
        self.mod.updateGFX(0.05)
        self.assertIsNone(self.tf())

    def test_own_tc_cuts_and_recovers(self):
        self.lua.execute("hasCMU=false")
        self.load(None, 2)
        self.assertEqual(self.mod.getTCMode(), "acng")
        # Driven rear at 13.5 m/s surface speed, undriven front at 10 m/s: slip 0.35, over
        # 0.15 by 0.2. The undriven wheels are the road speed, so airspeed does not count.
        self.lua.execute("electrics.values.airspeed=20; wheels.wheelRotators[1].angularVelocity=45;"
                         "wheels.wheelRotators[0].angularVelocity=10/0.3")
        self.assertAlmostEqual(self.mod.drivenSlip(), 0.35)
        self.mod.updateGFX(0.016)
        self.assertAlmostEqual(self.tf(), 1)     # one frame is filtered: 0.35*0.32 is under 0.15
        self.mod.updateGFX(0.1)
        self.assertAlmostEqual(self.tf(), 0.4)   # held for the filter time: 1 - 3*0.2
        self.lua.execute("wheels.wheelRotators[1].angularVelocity=60")
        self.mod.updateGFX(0.1)
        self.assertAlmostEqual(self.tf(), 0.2)   # slip 0.8: floor
        self.lua.execute("wheels.wheelRotators[1].angularVelocity=10/0.3")
        self.mod.updateGFX(0.1)
        self.assertAlmostEqual(self.tf(), 0.5)   # recovers 3 per second
        for _ in range(10):
            self.mod.updateGFX(0.1)
        self.assertEqual(self.tf(), 1)
        self.mod.configure(None, None)
        self.assertIsNone(self.tf())

    def test_all_wheel_drive_slip_uses_airspeed(self):
        self.lua.execute("wheels.wheelRotators[0].isPropulsed=true; electrics.values.airspeed=10;"
                         "wheels.wheelRotators[0].angularVelocity=10/0.3; wheels.wheelRotators[1].angularVelocity=40")
        self.load(None, None)
        self.assertAlmostEqual(self.mod.drivenSlip(), 0.2)
        self.lua.execute("wheels.wheelRotators[1].angularVelocity=30")   # slower than the road
        self.assertAlmostEqual(self.mod.drivenSlip(), 0)

    def test_own_tc_standing_start_uses_minimum_speed(self):
        self.lua.execute("hasCMU=false; electrics.values.airspeed=0; wheels.wheelRotators[1].angularVelocity=3")
        self.load(None, 1)
        self.assertAlmostEqual(self.mod.drivenSlip(), 0.3)   # 0.9 m/s over a 3 m/s floor
        self.mod.updateGFX(0.1)
        self.assertAlmostEqual(self.tf(), 1 - 3 * (0.3 - 0.25))

    def test_own_tc_off_and_factory_never_write(self):
        self.lua.execute("hasCMU=false; electrics.values.airspeed=10; wheels.wheelRotators[1].angularVelocity=60")
        for tc in (None, 0):
            self.load(None, tc)
            self.mod.updateGFX(0.05)
            self.assertIsNone(self.tf())
            self.mod.onExtensionUnloaded()

    def test_reset_reapplies_levels(self):
        self.load(3, 3)
        # A controller reset that reloads its jbeam values.
        self.lua.execute("cmu.motor.state.groups.mainEngine.slipThreshold=0.12; wheels.wheelRotators[0].slipRatioTarget=0.2")
        self.mod.onReset()
        self.mod.updateGFX(0.1)
        self.assertEqual(self.tc_state()[1], 0.12)              # not yet
        self.mod.updateGFX(0.2)
        self.assertAlmostEqual(self.tc_state()[1], 0.08)
        self.assertEqual(self.rot(0), (True, 0.12))

    def test_snapshot_reports_levels(self):
        self.load(1, 0)
        self.mod.updateGFX(0.2)
        s = self.g.sent[len(self.g.sent)]
        self.assertEqual(s.name, "ACNGAssists")
        d = s.data
        self.assertEqual((d.mode, d.abs_level, d.tc_level, d.tc_mode), ("on", 1, 0, "cmu"))
        self.assertEqual((d.abs_slip, d.abs_setting, d.abs_available), (0.25, "realistic", True))
        self.assertIsNone(d.tc_slip)
        # electrics.lua turns boolean electrics into 1/0, so both forms count as on.
        for value, expected in (("1", True), ("true", True), ("0", False), ("false", False)):
            self.lua.execute("electrics.values.absActive=%s; electrics.values.tcsActive=%s" % (value, value))
            d = self.mod.snapshot()
            self.assertEqual((d.abs_active, d.tc_active), (expected, expected))

    def test_no_input_or_force_writes(self):
        source = ASSISTS.read_text()
        for write in ("input.event", "applyForce", "queueLuaCommand", "setABSBehavior", "scaleBrakeTorque", "setGearboxMode"):
            self.assertNotIn(write, source)


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class CoreAssistFeature(unittest.TestCase):
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
          if path:find('defaults') then return {schema_version=1,enabled=false,features={abs=false,tc=false},
            assist_levels={abs=2,tc=2},telemetry={enabled=false,rate_hz=50,port=44443}} end
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
    def configure(vid, abs_level, tc_level):
        return (f"{vid}:if extensions.isExtensionLoaded('acng_assists') "
                f"then extensions.acng_assists.configure({abs_level},{tc_level}) end")

    @staticmethod
    def load_cmd(vid, abs_level, tc_level):
        return f"{vid}:extensions.load('acng_assists'); " + CoreAssistFeature.configure(vid, abs_level, tc_level)[len(f"{vid}:"):]

    def test_assists_need_master_and_flag(self):
        mod = self.load()
        self.assertTrue(mod.setFeature("abs", True))
        mod.onUpdate(1)
        self.assertEqual(self.cmds(), [])
        mod.setEnabled(True)
        mod.onUpdate(1)
        self.assertIn(self.load_cmd(5, 2, "nil"), self.cmds())
        status = mod.getStatus()
        self.assertEqual(status["assists_vehicle_id"], 5)
        self.assertEqual(status["physics_writes"], 1)
        self.assertTrue(status["features"]["abs"])
        self.assertFalse(status["features"]["tc"])
        mod.setFeature("abs", False)
        self.assertEqual(self.cmds()[-1], "5:extensions.unload('acng_assists')")
        self.assertEqual(mod.getStatus()["physics_writes"], 0)

    def test_levels_and_second_flag_reconfigure_without_reload(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("tc", True)
        mod.onUpdate(1)
        n = len(self.cmds())
        self.assertEqual(mod.setAssistLevel("tc", 0), 0)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[n:], [self.configure(5, "nil", 0)])
        mod.setFeature("abs", True)
        mod.setAssistLevel("abs", 3)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.configure(5, 3, 0))
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.configure(5, 3, 0))
        self.assertEqual(len(self.cmds()), n + 2)                # sent once per change
        self.assertEqual(dict(mod.getStatus()["assist_levels"]), {"abs": 3, "tc": 0})

    def test_bad_levels_are_rejected(self):
        mod = self.load()
        for name, value in (("abs", 4), ("tc", -1), ("tc", 1.5), ("ffb", 1), ("abs", "2")):
            self.assertFalse(mod.setAssistLevel(name, value))
        self.assertEqual(dict(mod.getStatus()["assist_levels"]), {"abs": 2, "tc": 2})

    def test_master_off_and_vehicle_switch(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("tc", True)
        mod.onUpdate(1)
        self.g.current = 7
        mod.onUpdate(1)
        self.assertIn("5:extensions.unload('acng_assists')", self.cmds())
        self.assertIn(self.load_cmd(7, "nil", 2), self.cmds())
        n = len(self.cmds())
        mod.onVehicleSpawned(7)
        mod.onUpdate(0.01)
        self.assertIn(self.load_cmd(7, "nil", 2), self.cmds()[n:])
        mod.setEnabled(False)
        self.assertIn("7:extensions.unload('acng_assists')", self.cmds()[-3:])
        self.assertEqual(mod.getStatus()["physics_writes"], 0)

    def test_assists_and_tires_count_separately(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("abs", True)
        mod.setFeature("tire_wear", True)
        mod.onUpdate(1)
        self.assertEqual(mod.getStatus()["physics_writes"], 2)
        mod.setFeature("tire_wear", False)
        self.assertEqual(mod.getStatus()["physics_writes"], 1)
        self.assertNotIn("5:extensions.unload('acng_assists')", self.cmds())

    def test_runtime_file_restores_flags_and_levels(self):
        self.lua.execute("saved={schema_version=1,enabled=true,features={tc=true},assist_levels={tc=3}}")
        mod = self.load()
        mod.onUpdate(1)
        self.assertIn(self.load_cmd(5, "nil", 3), self.cmds())

    def test_defaults_keep_assists_factory(self):
        defaults = json.loads((ROOT / "beamng-mod/settings/acng/defaults.json").read_text())
        self.assertFalse(defaults["enabled"])
        self.assertFalse(defaults["features"]["abs"])
        self.assertFalse(defaults["features"]["tc"])
        self.assertEqual(defaults["assist_levels"], {"abs": 2, "tc": 2})


if __name__ == "__main__":
    unittest.main()
