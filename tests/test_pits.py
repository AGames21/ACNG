import unittest
from pathlib import Path
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class PitContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
          pos={x=1,y=2,z=3};vel={x=0,y=0,z=0};fuel=10;writes=0;treadWrites=0;damage=false
          obj={getPosition=function() return pos end,getVelocity=function() return vel end}
          tank={type='fuelTank',capacity=60,currentLeakRate=0,
            setRemainingVolume=function(self,n) fuel=n;writes=writes+1 end}
          energyStorage={getStorages=function() return {mainTank=tank} end}
          extensions={isExtensionLoaded=function(name) return name=='acng_tires' end, acng_tires={canServiceTread=function()
            return not damage, damage and 'damaged wheel' or nil end,
            serviceTread=function() treadWrites=treadWrites+1;return true end}}
          guihooks={trigger=function() end};log=function() end
        ''')
        self.m = self.lua.execute((ROOT / 'beamng-mod/lua/vehicle/extensions/acng/pits.lua').read_text())
        self.g = self.lua.globals()

    def ready(self):
        self.m.configure(True)
        self.assertTrue(self.m.markHere())

    def test_default_off_and_no_box_no_writes(self):
        self.assertFalse(self.m.markHere())
        self.assertFalse(self.m.request(True, True))
        self.m.updateGFX(100)
        self.assertEqual(self.g.writes, 0)
        self.m.configure(True)
        self.assertFalse(self.m.request(True, False))

    def test_timed_fuel_and_tread_service(self):
        self.ready()
        self.assertTrue(self.m.request(True, True))
        self.m.updateGFX(19)
        self.assertEqual(self.g.fuel, 10)
        self.m.updateGFX(1)
        self.assertEqual(self.g.fuel, 60)
        self.assertEqual(self.g.treadWrites, 1)
        self.assertFalse(self.m.getSnapshot()['servicing'])

    def test_moving_cancels_and_paused_time_does_not_progress(self):
        self.ready()
        self.m.request(True, False)
        self.m.updateGFX(0)
        self.assertEqual(self.m.getSnapshot()['remaining_s'], 20)
        self.g.vel.x = 1
        self.m.updateGFX(1)
        self.assertFalse(self.m.getSnapshot()['servicing'])
        self.m.updateGFX(100)
        self.assertEqual(self.g.writes, 0)

    def test_departure_master_off_reset_and_cancel(self):
        for action in ('depart', 'off', 'reset', 'cancel'):
            self.setUp()
            self.ready()
            self.m.request(True, False)
            if action == 'depart':
                self.g.pos.z = 9
            elif action == 'off':
                self.m.configure(False)
            elif action == 'reset':
                self.m.onReset()
                self.assertFalse(self.m.getSnapshot()['box_marked'])
            else:
                self.m.cancel()
            self.m.updateGFX(25)
            self.assertEqual(self.g.writes, 0, action)

    def test_damage_and_leaks_rechecked_before_completion(self):
        self.ready()
        self.assertTrue(self.m.request(True, True))
        self.g.damage = True
        self.m.updateGFX(20)
        self.assertEqual(self.g.writes, 0)
        self.assertEqual(self.g.treadWrites, 0)
        self.g.damage = False
        self.m.request(True, True)
        self.g.tank.currentLeakRate = 0.1
        self.m.updateGFX(20)
        self.assertEqual(self.g.writes, 0)
        self.assertFalse(self.m.request(True, False))

    def test_unsupported_electric_vehicle_and_missing_tires(self):
        self.ready()
        self.g.tank.type = 'electricBattery'
        self.assertFalse(self.m.request(True, False))
        self.g.extensions.acng_tires = None
        self.assertFalse(self.m.request(False, True))

    def test_invalid_inputs_and_duplicate_request(self):
        self.ready()
        self.assertFalse(self.m.request(False, False))
        self.assertTrue(self.m.request(False, True))
        self.assertFalse(self.m.request(True, True))
        self.assertFalse(self.m.markHere())
        self.m.updateGFX(float('nan'))
        self.m.updateGFX(-1)
        self.assertEqual(self.m.getSnapshot()['remaining_s'], 8)
        self.m.updateGFX(8)
        self.assertEqual(self.g.treadWrites, 1)
        self.assertEqual(self.g.writes, 0)


class TreadServiceContracts(unittest.TestCase):
    def test_existing_tire_accounting_damage_and_heat_preservation(self):
        from test_tires import VEHICLE
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(VEHICLE + '\nv.data.wheels[3]=nil\n')
        m = lua.execute((ROOT / 'beamng-mod/lua/vehicle/extensions/acng/tires.lua').read_text())
        m.onExtensionLoaded()
        m.configure(True, True, 'road')
        lua.globals().wheels.wheels[0].slipEnergy = 1e6
        m.updateGFX(1)
        heat = lua.globals().temps[0]
        self.assertTrue(m.serviceTread())
        self.assertEqual(lua.globals().temps[0], heat)
        for flag in ('isBroken', 'isTireDeflated'):
            lua.globals().wheels.wheels[0][flag] = True
            self.assertFalse(m.serviceTread())
            self.assertTrue(lua.globals().wheels.wheels[0][flag])
            lua.globals().wheels.wheels[0][flag] = False
        m.configure(True, False, 'road')
        self.assertFalse(m.serviceTread())


if __name__ == '__main__':
    unittest.main()
