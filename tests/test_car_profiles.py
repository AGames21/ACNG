import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import build_ac_car  # noqa: E402
import car_details  # noqa: E402
import car_sounds  # noqa: E402
import car_upgrades  # noqa: E402
import cars  # noqa: E402
import export_kn5  # noqa: E402
from cars import bmw_m3_e92 as m3  # noqa: E402

MODULES = {'BUILD_AC_CAR': build_ac_car, 'EXPORT_KN5': export_kn5, 'CAR_UPGRADES': car_upgrades,
           'CAR_DETAILS': car_details, 'CAR_SOUNDS': car_sounds}


class ProfileLoading(unittest.TestCase):
    """cars.load sets module globals; every test puts the 1M defaults back."""

    def setUp(self):
        self.saved = {key: {k: getattr(mod, k) for k in getattr(m3, key, {})} for key, mod in MODULES.items()}

    def tearDown(self):
        for key, mod in MODULES.items():
            for k, v in self.saved[key].items():
                setattr(mod, k, v)

    def test_m3_profile_sets_every_module(self):
        self.assertEqual(build_ac_car.VEHICLE, 'acng_bmw1m')
        cars.load('bmw_m3_e92')
        self.assertEqual(build_ac_car.VEHICLE, 'acng_bmw_m3e92')
        self.assertEqual(car_sounds.PREFIX, 'acng_m3_')
        self.assertEqual(car_details.BRAKE_CALIPER, 'brake_caliper_standard_plain')
        self.assertIsNone(car_upgrades.SHIFTER_NODE)
        self.assertEqual(export_kn5.MIRROR_MATERIAL, 'CAR_mirror')

    def test_bad_and_missing_profiles_fail_loudly(self):
        for name in ('../bmw_1m', 'BMW', ''):
            with self.assertRaisesRegex(ValueError, 'Bad car profile'):
                cars.load(name)
        with self.assertRaisesRegex(ValueError, 'No car profile'):
            cars.load('no_such_car')

    def test_every_profile_key_exists_in_its_module(self):
        for key, mod in MODULES.items():
            for k in getattr(m3, key, {}):
                self.assertTrue(hasattr(mod, k), f'{key}.{k}')


class M3Specs(unittest.TestCase):
    def test_base_torque_cancels_friction_and_exhaust(self):
        rows = m3.base_torque()
        self.assertEqual(rows[0], [0, 0])
        table = dict((r[0], r[1]) for r in rows[1:])
        # Reported = base - friction - dynamic friction * rad/s + exhaust mod (mult 1) = TARGET.
        for rpm, nm in m3.TARGET:
            reported = table[rpm] - m3.FRICTION - m3.DYN_FRICTION * rpm * math.pi / 30 + m3._lerp(m3.EXHAUST_MOD, rpm)
            self.assertAlmostEqual(reported, nm, delta=0.01)
        self.assertEqual(max(m3.TARGET, key=lambda r: r[1]), (4000, 400))

    def test_config_swaps_the_i6_for_the_native_v8_dct(self):
        pc = {'parts': {'etk_engine': 'acng_1m_engine', 'etk_engine_i6_3.0_petrol_ecu': 'x', 'etk_oilpan_i6': 'y',
                        'tire_F_19x9': 'z', 'etkc_body': 'etkc_body'}}
        out = m3.spec_config(pc)
        self.assertEqual(pc['parts']['etk_engine'], 'acng_1m_engine')  # input untouched
        parts = out['parts']
        for key in ('etk_engine_i6_3.0_petrol_ecu', 'etk_oilpan_i6', 'tire_F_19x9'):
            self.assertNotIn(key, parts)
        self.assertEqual(parts['etk_engine'], 'acng_m3_engine')
        self.assertEqual(parts['etk_transmission'], 'acng_m3_transmission')
        self.assertEqual(parts['etk_engine_ecu_speedlimit'], 'etk_engine_ecu_speedlimit_250')
        self.assertEqual(parts['etkc_body'], 'etkc_body')
        self.assertEqual(out['vars']['$fuel'], 56.7)

    def test_gearing_matches_lab_targets(self):
        t = m3.BUILD_AC_CAR['LAB_TARGETS']
        forward = [r for r in m3.GEAR_RATIOS if r > 0]
        self.assertEqual((len(forward), forward[0], forward[-1]), (t['gears'], t['ratio_first'], t['ratio_last']))
        self.assertEqual(m3.CAR_UPGRADES['FINAL_DRIVE'], t['final_drive'])
        self.assertEqual(t['curve']['4000'], t['torque_nm'])
        self.assertNotIn('events', t)  # written from CAR_SOUNDS.EVENT_HOOKS at build time

    def test_idle_matches_the_ac_idle_recordings(self):
        # The V8 idle loops were recorded near 1170 rpm; a 750 rpm idle played them 36 % flat.
        for tag in m3.CAR_SOUNDS['IDLE_TAGS'].values():
            self.assertLess(abs(tag - 1164) / 1164, 0.02)
        self.assertGreaterEqual(m3.IDLE_RPM, 900)


class ConverterHooks(unittest.TestCase):
    def mesh(self, name, material='m', ys=(0.5, 0.5, 0.5, 1.2, 1.2, 1.2), **extra):
        return dict({'name': name, 'path': ['ROOT', name], 'material': material, 'active': True, 'visible': True,
                     'positions': [(0, y, 0) for y in ys], 'normals': [(0, 0, 1)] * 6, 'uvs': [(0, 0)] * 6,
                     'indices': [0, 1, 2, 3, 4, 5]}, **extra)

    def test_interior_glass_is_skipped_even_when_grouped(self):
        mats = {'INT_Vetro_interno': {'shader': 'ksWindscreen'}, 'm': {'shader': 'ksPerPixel'}}
        glass = self.mesh('polymsh', 'INT_Vetro_interno', acng_group='dash')
        self.assertEqual(export_kn5.route(glass, mats), export_kn5.SKIP)
        self.assertEqual(export_kn5.route(self.mesh('polymsh', acng_group='dash'), mats), 'dash')

    def test_lamp_moves_split_by_height_and_keep_their_glow(self):
        saved = car_upgrades.LAMP_MOVES
        try:
            car_upgrades.LAMP_MOVES = (('REAR_LIGHT_STOP', 1.0, 'body'),)
            model = {'meshes': [self.mesh('REAR_LIGHT_STOP'), self.mesh('OTHER')]}
            out = car_upgrades.move_lamp_parts(model, 0.0)['meshes']
        finally:
            car_upgrades.LAMP_MOVES = saved
        names = [m['name'] for m in out]
        self.assertEqual(names, ['REAR_LIGHT_STOP', 'REAR_LIGHT_STOP_body', 'OTHER'])
        low, high = out[0], out[1]
        self.assertNotIn('acng_group', low)
        self.assertEqual((high['acng_group'], high['acng_glow']), ('body', True))
        self.assertEqual(len(low['indices']) + len(high['indices']), 6)
        self.assertTrue(all(p[1] > 1.0 for p in high['positions']))

    def test_shift_controller_hook_gets_lengths_and_the_controller(self):
        import tempfile
        import wave
        saved = car_sounds.EVENT_HOOKS, car_sounds.PREFIX
        try:
            car_sounds.EVENT_HOOKS, car_sounds.PREFIX = m3.CAR_SOUNDS['EVENT_HOOKS'], 'acng_m3_'
            with tempfile.TemporaryDirectory() as temp:
                vdir = Path(temp) / 'acng_bmw_m3e92'; (vdir / 'sounds').mkdir(parents=True)
                files = {}
                for name, frames in (('gearup', 13450), ('geardn', 9834)):
                    with wave.open(str(vdir / 'sounds' / f'acng_m3_{name}.wav'), 'wb') as w:
                        w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100); w.writeframes(bytes(2 * frames))
                    files[name] = f'vehicles/acng_bmw_m3e92/sounds/acng_m3_{name}.wav'
                parts = {'acng_m3_shifter': {'acng_shiftSound': {'volume': 0.5}}}
                car_sounds.apply_events(parts, files, vdir)
                data = parts['acng_m3_shifter']['acng_shiftSound']
                self.assertEqual((data['upSample'], data['downSample']), (files['gearup'], files['geardn']))
                self.assertEqual((data['upSeconds'], data['downSeconds']), (0.305, 0.223))
                self.assertTrue((vdir / 'lua' / 'controller' / 'acng_shiftSound.lua').is_file())
        finally:
            car_sounds.EVENT_HOOKS, car_sounds.PREFIX = saved

    def test_m3_shifter_uses_the_acng_controller(self):
        hooks = m3.CAR_SOUNDS['EVENT_HOOKS']
        self.assertEqual({h[1] for h in hooks}, {car_sounds.SHIFT_SECTION})
        self.assertNotIn('geardn', m3.BUILD_AC_CAR['UNMAPPED_EVENTS'])

    def test_no_lamp_moves_by_default(self):
        self.assertEqual(car_upgrades.LAMP_MOVES, ())
        model = {'meshes': [self.mesh('REAR_LIGHT_STOP')]}
        self.assertEqual(car_upgrades.move_lamp_parts(model, 0.0), model)


if __name__ == '__main__':
    unittest.main()
