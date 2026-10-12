"""Protect filming scope and genuine wear evidence, not a substitute for native runs."""
import unittest
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class VideoHarnessSafety(unittest.TestCase):
    def test_night_films_wait_for_native_ui_loading_callback(self):
        for name in ('nightdrive','nightburn'):
            source=(ROOT/f'tests/beamng-{name}/lua/ge/extensions/acng/{name}.lua').read_text()
            request=source.index("requestEnterLoadingScreen('acng_nightfilm',function()")
            start=source.index("startFreeroamByName('west_coast_usa'")
            release=source.index("requestExitLoadingScreen('acng_nightfilm')")
            self.assertLess(request,start)
            self.assertLess(start,release)

    def test_revised_cut_has_no_rejected_banner(self):
        plan=json.loads((ROOT/'tools/shorts/tires-v2.json').read_text())
        v3=json.loads((ROOT/'tools/shorts/tires-v3.json').read_text())
        self.assertNotIn('AT THE LIMIT',json.dumps(v3))
        self.assertNotIn('BeamNG remains in charge of the car',json.dumps(v3))
        text=json.dumps(plan)
        self.assertNotIn('AT THE LIMIT',text)
        self.assertNotIn('BeamNG remains in charge of the car',text)
        door=next(s for s in plan['segments'] if s.get('clip')=='door')
        quarter=next(s for s in plan['segments'] if s.get('clip')=='quarter')
        self.assertEqual((door['head'],door['sub']),(quarter['head'],quarter['sub']))

    def test_night_burnout_is_genuine_wear_on_stock_map(self):
        source=(ROOT/'tests/beamng-nightburn/lua/ge/extensions/acng/nightburn.lua').read_text()
        executable='\n'.join(x for x in source.splitlines() if not x.lstrip().startswith('--'))
        for forbidden in ('deflateTire','serviceTread','bmw','/levels/spa'):
            self.assertNotIn(forbidden,executable)
        self.assertIn("startFreeroamByName('west_coast_usa','spawns_chinatown')",executable)
        self.assertIn('setWearRate(10)',executable)
        self.assertIn('obj:getGroupPressure(pg)',executable)

    def test_cinematic_ai_is_lab_only(self):
        source=(ROOT/'tests/beamng-nightdrive/lua/ge/extensions/acng/nightdrive.lua').read_text()
        self.assertIn("ai.setMode('span')",source)
        self.assertIn("ai.setMode('disabled')",source)
        self.assertIn('max>5 and #result.samples>=30',source)
        for p in (ROOT/'beamng-mod').rglob('*'):
            self.assertNotIn('nightdrive',p.name)

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

