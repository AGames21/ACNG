"""Protect filming scope and genuine wear evidence, not a substitute for native runs."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class VideoHarnessSafety(unittest.TestCase):
    def test_burnout_never_forces_puncture_or_tread(self):
        source=(ROOT/'tests/beamng-tireburn/lua/ge/extensions/acng/tireburn.lua').read_text()
        executable='\n'.join(x for x in source.splitlines() if not x.lstrip().startswith('--'))
        self.assertNotIn('deflateTire',executable)
        self.assertNotIn('serviceTread',executable)
        self.assertIn('obj:getGroupPressure(pg)',executable)
        self.assertIn('w.deflated==true',executable)
        self.assertIn('(initial.pa-101325)*0.25',executable)
        self.assertNotIn('bmw',executable.lower())
        self.assertNotIn('/levels/spa',executable.lower())

    def test_camera_has_no_vehicle_physics_write(self):
        source=(ROOT/'tests/beamng-tirecam/lua/ge/extensions/acng/tirecam.lua').read_text()
        camera=source.split('local function onPreRender()')[1].split('M.onPreRender')[0]
        for forbidden in ('queueLuaCommand','setFeature','setTire','applyForce','applyImpulse','setPosition'):
            self.assertNotIn(forbidden,camera)
        self.assertIn('getSpawnWorldOOBB',camera)

