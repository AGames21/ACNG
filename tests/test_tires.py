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
  wheels={[0]={name='FL',wheelID=0,cid=0,pressureGroup='pg1'},
    [1]={name='FR',wheelID=1,cid=1,heatCoefFriction=0.02,smokingTemp=500,meltingTemp=600,
         heatAffectsPressure=true,frictionLowTemp=300,frictionCoefLow=0.9},
    [2]={name='HUB',wheelID=2,cid=2,hasTire=false},
    [3]={name='GONE',wheelID=3,cid=3}}}}
-- The runtime wheel table (wheels.lua), keyed by cid, with this frame's slip energy.
wheels={wheels={[0]={slipEnergy=0},[1]={slipEnergy=0},[2]={slipEnergy=5e6}}}
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

    def test_auto_compound_is_per_axle_and_unknown_falls_back_safely(self):
        self.lua.execute("v.config={parts={tire_F_19x9='tire_F_sport',tire_R_19x10='tire_R_race'}};v.data.wheels[1].name='RR'")
        self.mod.onExtensionLoaded();self.mod.configure(True, True, 'auto')
        snap=self.mod.snapshot()
        self.assertEqual(snap.tires[1].compound,'sport')
        self.assertEqual(snap.tires[2].compound,'race')
        self.assertAlmostEqual(self.mod.gripAt(15,self.g.v.data.wheels[1]),.70)
        self.assertEqual(self.mod.gripAt(90,self.g.v.data.wheels[1]),1)
        self.lua.execute("v.config.parts={tire_F_19x9='custom_unclassified'}")
        self.mod.onReset()
        self.assertEqual(self.mod.snapshot().tires[1].compound,'road')

    def test_compound_detection_by_name_then_physics(self):
        m = self.mod
        for part, want in (("tire_F_17x8_sport", "sport"), ("tire_R_semislick", "sport"), ("tire_F_race", "race"),
                           ("tire_R_slick_19x11", "race"), ("tire_F_asphalt_rally", "race"), ("tire_R_drag", "race"),
                           ("tire_F_17x8_standard", "road"), ("tire_F_eco", "road"), ("tire_R_offroad", "road")):
            self.assertEqual(m.compoundFromName(part), want, part)
        for part in ("tire_F_15x7_14_redline", "tire_R_16_ww", "tire_F_14_mixed", "modded_tire_F"):
            self.assertIsNone(m.compoundFromName(part), part)   # no type in the name: physics decides
        wd = self.lua.eval("function(a,b) return {noLoadCoef=a,treadCoef=b} end")
        self.assertEqual(m.compoundFromPhysics(wd(1.95, 0)), "race")
        self.assertEqual(m.compoundFromPhysics(wd(1.95, 0.6)), "sport")   # grippy but treaded
        self.assertEqual(m.compoundFromPhysics(wd(1.6, 0.5)), "sport")
        self.assertEqual(m.compoundFromPhysics(wd(1.2, 0.6)), "road")
        self.assertIsNone(m.compoundFromPhysics(self.lua.eval("{}")))

    def test_auto_uses_native_physics_when_the_part_name_is_unclear(self):
        self.lua.execute("v.config={parts={tire_F_19x9='modded_tire_F'}};v.data.wheels[0].noLoadCoef=1.9;v.data.wheels[0].treadCoef=0")
        self.mod.onExtensionLoaded();self.mod.configure(True, True, 'auto')
        self.assertEqual(self.mod.snapshot().tires[1].compound, 'race')

    def test_compound_sets_wear_rate(self):
        self.mod.onExtensionLoaded()
        rates = {}
        for name in ("road", "sport", "race"):
            self.mod.configure(True, True, name)
            rates[name] = self.mod.compoundWear(self.g.v.data.wheels[0])
        self.assertLess(rates["road"], rates["sport"])
        self.assertLess(rates["sport"], rates["race"])
        self.assertEqual(rates["sport"], 1)                 # the calibrated T007 setup

    def test_heat_fades_to_a_ceiling_instead_of_climbing_forever(self):
        m = self.mod
        self.assertEqual(m.heatFade(150), 1)
        self.assertEqual(m.heatFade(m.HEAT_FADE_C), 1)
        self.assertEqual(m.heatFade(225), 0.5)
        self.assertEqual(m.heatFade(m.HEAT_LIMIT_C), 0)
        self.assertEqual(m.heatFade(400), 0)
        self.assertEqual(m.heatFade(None), 1)
        self.assertEqual(m.heatFade(float("nan")), 1)
        self.assertLess(m.HEAT_LIMIT_C, 300)                 # burnouts no longer read 300+

    def test_burnout_heat_rewrites_native_friction_heat(self):
        self.mod.onExtensionLoaded();self.mod.configure(True, False, 'sport')
        def friction():
            return [c for c in self.calls() if c[0] == 0 and c[1] == 'thermal'][-1][2][6]
        self.mod.updateGFX(.5)
        cool = friction()
        self.assertGreater(cool, 0)
        self.g.temps[0] = 273.15 + 260
        self.mod.updateGFX(.5)
        self.assertEqual(friction(), 0)                      # no more friction heat at the ceiling
        self.g.temps[0] = 273.15 + 90
        self.mod.updateGFX(.5)
        self.assertAlmostEqual(friction(), cool)             # full heat again once it cools
        self.mod.onExtensionUnloaded()
        self.assertEqual(friction(), 0)                      # stock again: no ACNG friction heat

    def test_zero_tread_calls_native_puncture_once_and_off_does_not_repair(self):
        self.lua.execute("punctures={};beamstate={deflateTire=function(id) punctures[#punctures+1]=id;wheels.wheels[id].isTireDeflated=true end}")
        self.mod.onExtensionLoaded();self.mod.configure(False,True)
        self.g.wheels.wheels[0].slipEnergy=1e9
        self.mod.updateGFX(.1);self.mod.updateGFX(.1)
        self.assertEqual(len(self.g.punctures),1)
        self.assertEqual(self.g.punctures[1],0)
        self.assertEqual(self.tread()['FL'][0],0)
        self.mod.onExtensionUnloaded()
        self.assertTrue(self.g.wheels.wheels[0].isTireDeflated)

    def test_wear_disabled_and_broken_wheels_never_trigger_puncture(self):
        self.lua.execute("punctures={};beamstate={deflateTire=function(id) punctures[#punctures+1]=id end}")
        self.mod.onExtensionLoaded();self.mod.configure(True,False)
        self.g.wheels.wheels[0].slipEnergy=1e9
        self.mod.updateGFX(.1)
        self.mod.configure(True,True);self.g.wheels.wheels[0].isBroken=True
        self.mod.updateGFX(.1)
        self.assertEqual(len(self.g.punctures),0)
        self.assertEqual(self.tread()['FL'][0],1)

    def test_road_preset_switch_retains_wear_and_restores_stock(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True, 'road')
        self.assertEqual(self.mod.snapshot().profile, 'road')
        self.assertEqual(self.mod.WINDOW_LOW_C, 35)
        self.assertEqual(self.mod.WINDOW_HIGH_C, 75)
        self.assertAlmostEqual(self.mod.gripAt(15), 0.98)
        self.assertEqual(self.mod.gripAt(50), 1)
        self.assertEqual(self.mod.HEAT.friction, 0.03)
        self.g.wheels.wheels[0].slipEnergy = 1e6
        self.mod.updateGFX(0.1)
        worn=self.mod.wearState()[1].tread
        self.assertTrue(self.mod.setProfile('sport'))
        self.assertEqual(self.mod.wearState()[1].tread, worn)
        self.assertEqual(self.mod.HEAT.friction, 0.06)
        self.assertFalse(self.mod.setProfile('invalid'))
        self.g.calls=self.lua.eval('{}')
        self.mod.onExtensionUnloaded()
        thermal={c[0]:c[2] for c in self.calls() if c[1]=='thermal'}
        self.assertEqual(thermal[0], [0,0.4,20,0,0,0,0,0,0,1e18,1e19,False])

    def test_load_applies_acng_only_to_tires_and_unload_restores_stock(self):
        self.mod.onExtensionLoaded()
        loaded = self.calls()
        self.assertEqual(sorted({c[0] for c in loaded}), [0, 1])  # no hub, no missing wheel
        thermal = {c[0]: c[2] for c in loaded if c[1] == "thermal"}
        curve = {c[0]: c[2] for c in loaded if c[1] == "curve"}
        self.assertEqual(thermal[0][6], 0.06)           # friction heat on
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

    def tread(self):
        state = self.mod.wearState()
        return {state[i].name: (state[i].tread, state[i].slip_work) for i in range(1, len(state) + 1)}

    def drive(self, seconds, step=0.1):
        for _ in range(round(seconds / step)):
            self.mod.updateGFX(step)

    def test_wear_off_by_default(self):
        self.mod.onExtensionLoaded()
        self.g.wheels.wheels[0].slipEnergy = 1e6
        self.drive(1)
        self.assertEqual(self.tread()["FL"], (1, 0))
        snap = self.mod.snapshot()
        self.assertFalse(snap.wear)
        self.assertIsNone(snap.tires[1].tread)
        self.assertEqual(snap.tires[1].grip, 1)

    def test_slip_energy_wears_tread_and_costs_grip(self):
        self.mod.onExtensionLoaded()
        self.assertEqual(self.mod.configure(True, True), (True, True))
        self.g.wheels.wheels[0].slipEnergy = 1e6           # FL sliding, FR rolling
        self.g.calls = self.lua.eval("{}")
        self.drive(1)
        fl, fr = self.tread()["FL"], self.tread()["FR"]
        self.assertAlmostEqual(fl[1], 1e6)                 # slip work integrated over 1 s
        self.assertAlmostEqual(fl[0], 1 - 1e6 / self.mod.WEAR_ENERGY)
        self.assertEqual(fr, (1, 0))
        curve = [c for c in self.calls() if c[1] == "curve" and c[0] == 0]
        self.assertTrue(curve)                             # grip followed the tread
        self.assertAlmostEqual(curve[-1][2][5], self.mod.wearGrip(fl[0]), delta=self.mod.GRIP_STEP)
        snap = self.mod.snapshot()
        self.assertTrue(snap.wear)
        self.assertEqual(snap.wear_rate, 1)
        self.assertAlmostEqual(snap.tires[1].tread, round(fl[0], 3))
        self.assertEqual(snap.tires[2].tread, 1)
        self.assertEqual(len(snap.tires), 2)               # the hub never wears or reports

    def test_wear_grip_and_heat_multiplier_shape(self):
        m = self.mod
        self.assertEqual(m.wearGrip(1), 1)
        self.assertAlmostEqual(m.wearGrip(0), 1 - m.WEAR_GRIP_LOSS)
        self.assertAlmostEqual(m.wearGrip(0.5), 1 - m.WEAR_GRIP_LOSS / 2)
        self.assertAlmostEqual(m.wearGrip(-1), m.wearGrip(0))
        self.assertEqual(m.wearGrip(None), 1)
        self.assertEqual(m.wearGrip(float("nan")), 1)
        self.assertEqual(m.wearHeatMult(90), 1)
        self.assertEqual(m.wearHeatMult(105), 1)
        self.assertAlmostEqual(m.wearHeatMult(125), 1.5)
        self.assertEqual(m.wearHeatMult(145), m.WEAR_HOT_MULT)
        # Past the hot ramp a burnout keeps raising wear, up to WEAR_BURN_MULT at the ceiling.
        self.assertAlmostEqual(m.wearHeatMult(145 + (m.HEAT_LIMIT_C - 145) / 2), (m.WEAR_HOT_MULT + m.WEAR_BURN_MULT) / 2)
        self.assertEqual(m.wearHeatMult(m.HEAT_LIMIT_C), m.WEAR_BURN_MULT)
        self.assertEqual(m.wearHeatMult(400), m.WEAR_BURN_MULT)
        self.assertEqual(m.wearHeatMult(None), 1)
        m.configure(False, True)
        self.assertEqual(m.wearHeatMult(140), 1)           # no heat model, no heat penalty

    def test_hot_tires_wear_faster(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        self.g.temps[0] = 273.15 + 125
        self.mod.updateGFX(0.1)                            # grip update reads 125 C
        start = self.tread()["FL"][0]
        self.g.wheels.wheels[0].slipEnergy = 1e6
        self.drive(1)
        self.assertAlmostEqual(start - self.tread()["FL"][0], 1.5 * 1e6 / self.mod.WEAR_ENERGY)

    def test_bad_slip_energy_and_rate(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        for bad in (float("nan"), float("inf"), -5, None):
            self.g.wheels.wheels[0].slipEnergy = bad
            self.drive(0.2)
        self.assertEqual(self.tread()["FL"], (1, 0))
        self.g.wheels = None                               # runtime table missing
        self.drive(0.2)
        self.assertEqual(self.mod.setWearRate(1000), 100)
        self.assertEqual(self.mod.setWearRate(-1), 0)
        self.assertEqual(self.mod.setWearRate(float("nan")), 0)
        self.assertEqual(self.mod.setWearRate(4), 4)

    def test_wear_rate_multiplies_wear(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        self.mod.setWearRate(10)
        self.g.wheels.wheels[0].slipEnergy = 1e5
        self.drive(1)
        self.assertAlmostEqual(self.tread()["FL"][0], 1 - 10 * 1e5 / self.mod.WEAR_ENERGY)
        self.assertAlmostEqual(self.tread()["FL"][1], 1e5)   # slip work itself is unscaled
        self.assertEqual(self.mod.snapshot().wear_rate, 10)

    def test_tread_never_goes_below_zero(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        self.g.wheels.wheels[0].slipEnergy = 1e9
        self.drive(1)
        self.assertEqual(self.tread()["FL"][0], 0)
        self.assertAlmostEqual(self.mod.snapshot().tires[1].grip, 1 - self.mod.WEAR_GRIP_LOSS, delta=0.002)

    def test_reset_gives_fresh_tires(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        self.g.wheels.wheels[0].slipEnergy = 1e6
        self.drive(1)
        self.assertLess(self.tread()["FL"][0], 1)
        self.g.wheels.wheels[0].slipEnergy = 0
        self.g.calls = self.lua.eval("{}")
        self.mod.onReset()
        self.assertEqual(self.tread()["FL"], (1, 0))
        curve = {c[0]: c[2] for c in self.calls() if c[1] == "curve"}
        self.assertEqual(curve[0][5], 1)                   # FL back to full grip at 90 C

    def test_toggling_wear_keeps_tread(self):
        self.mod.onExtensionLoaded()
        self.mod.configure(True, True)
        self.g.wheels.wheels[0].slipEnergy = 1e6
        self.drive(1)
        worn = self.tread()["FL"][0]
        self.g.calls = self.lua.eval("{}")
        self.mod.configure(True, False)
        curve = {c[0]: c[2] for c in self.calls() if c[1] == "curve"}
        self.assertEqual(curve[0][5], 1)                   # wear off: heat grip only
        self.drive(1)
        self.assertEqual(self.tread()["FL"][0], worn)      # no wear while off
        self.mod.configure(True, True)
        self.assertEqual(self.tread()["FL"][0], worn)      # no free tires from a toggle

    def test_wear_without_heat_keeps_stock_thermal(self):
        self.mod.onExtensionLoaded()
        self.g.calls = self.lua.eval("{}")
        self.mod.configure(False, True)
        loaded = self.calls()
        thermal = {c[0]: c[2] for c in loaded if c[1] == "thermal"}
        curve = {c[0]: c[2] for c in loaded if c[1] == "curve"}
        self.assertEqual(thermal[0], [0, 0.4, 20, 0, 0, 0, 0, 0, 0, 1e18, 1e19, False])
        self.assertEqual(thermal[1][6], 0.02)              # FR keeps its own jbeam heat
        self.assertEqual(curve[1][5:], [1, 1, 1])          # cold FR, but no heat window
        snap = self.mod.snapshot()
        self.assertFalse(snap.heat)
        self.assertIsNone(snap.window_low_c)
        self.assertIsNone(snap.tires[2].state)
        self.g.calls = self.lua.eval("{}")
        self.mod.onExtensionUnloaded()
        curve = {c[0]: c[2] for c in self.calls() if c[1] == "curve"}
        self.assertEqual(curve[0], [-300, 1e7, 1e-10, 1e-10, 10, 1, 1, 1])
        self.assertEqual(curve[1][0], 300)                 # stock curve back exactly

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

    @staticmethod
    def load_cmd(vid, heat=True, wear=False):
        return (f"{vid}:extensions.load('acng_tires'); if extensions.isExtensionLoaded('acng_tires') "
                f'then extensions.acng_tires.configure({str(heat).lower()},{str(wear).lower()},"auto") end')

    @staticmethod
    def configure_cmd(vid, heat, wear):
        return (f"{vid}:if extensions.isExtensionLoaded('acng_tires') "
                f'then extensions.acng_tires.configure({str(heat).lower()},{str(wear).lower()},"auto") end')

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
        self.assertIn(self.load_cmd(5), self.cmds())
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
        self.assertFalse(mod.setFeature("aero", True))
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
        self.assertIn(self.load_cmd(7), self.cmds())
        n = len(self.cmds())
        mod.onVehicleSpawned(7)
        mod.onUpdate(0.01)
        self.assertIn(self.load_cmd(7), self.cmds()[n:])

    def test_runtime_file_only_restores_implemented_features(self):
        self.lua.execute("saved={schema_version=1,enabled=true,features={tire_temperature=true,aero=true}}")
        mod = self.load()
        status = mod.getStatus()
        self.assertTrue(status["enabled"])
        self.assertTrue(status["features"]["tire_temperature"])
        self.assertFalse(status["features"]["tire_wear"])
        mod.onUpdate(1)
        self.assertIn(self.load_cmd(5), self.cmds())

    def test_wear_alone_loads_tires_with_heat_off(self):
        mod = self.load()
        mod.setEnabled(True)
        self.assertTrue(mod.setFeature("tire_wear", True))
        mod.onUpdate(1)
        self.assertIn(self.load_cmd(5, heat=False, wear=True), self.cmds())
        status = mod.getStatus()
        self.assertTrue(status["features"]["tire_wear"])
        self.assertFalse(status["features"]["tire_temperature"])
        self.assertEqual(list(status["implemented_physics_features"].values()), ["tire_temperature", "tire_wear", "abs", "tc", "ffb"])
        self.assertEqual(status["physics_writes"], 1)

    def test_flag_change_reconfigures_without_reload(self):
        mod = self.load()
        mod.setEnabled(True)
        mod.setFeature("tire_temperature", True)
        mod.onUpdate(1)
        n = len(self.cmds())
        mod.setFeature("tire_wear", True)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[n:], [self.configure_cmd(5, True, True)])
        mod.onUpdate(1)
        self.assertEqual(len(self.cmds()), n + 1)          # sent once, not every poll
        mod.setFeature("tire_temperature", False)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.configure_cmd(5, False, True))
        mod.setFeature("tire_wear", False)
        self.assertEqual(self.cmds()[-1], "5:extensions.unload('acng_tires')")
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        mod.setFeature("tire_wear", True)
        mod.onUpdate(1)
        self.assertEqual(self.cmds()[-1], self.load_cmd(5, heat=False, wear=True))  # fresh load after unload

    def test_runtime_file_restores_wear(self):
        self.lua.execute("saved={schema_version=1,enabled=true,features={tire_wear=true}}")
        mod = self.load()
        mod.onUpdate(1)
        self.assertIn(self.load_cmd(5, heat=False, wear=True), self.cmds())

    def test_defaults_keep_tires_off(self):
        import json
        defaults = json.loads((ROOT / "beamng-mod/settings/acng/defaults.json").read_text())
        self.assertFalse(defaults["enabled"])
        self.assertFalse(defaults["features"]["tire_temperature"])
        self.assertFalse(defaults["features"]["tire_wear"])


if __name__ == "__main__":
    unittest.main()
