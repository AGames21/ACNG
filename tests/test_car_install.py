import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from install_car_normal import verify_local_build, contains_model, model_of, record_path_for, GENERIC_REQUIRED


class CarInstallProof(unittest.TestCase):
    def test_unreadable_unrelated_mod_is_preserved_and_skipped(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'other-mod.zip';path.write_bytes(b'not a ZIP')
            self.assertFalse(contains_model(path))
            self.assertEqual(path.read_bytes(),b'not a ZIP')

    def test_unreadable_acng_archive_requires_review(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'acng-unknown.zip';path.write_bytes(b'not a ZIP')
            with self.assertRaisesRegex(RuntimeError,'review'):
                contains_model(path)

    def fixture(self, root):
        package = root / 'acng_bmw1m.zip'
        with zipfile.ZipFile(package, 'w') as archive:
            archive.writestr('vehicles/acng_bmw1m/info.json', '{}')
        lab = root / 'lab'; (lab / 'mods').mkdir(parents=True)
        (lab / 'mods' / package.name).write_bytes(package.read_bytes())
        test = lab / 'acng-car-test.json'
        proof = {'test': 'C002', 'completed': True, 'checks': dict.fromkeys(
            ['spawn_undamaged', 'drive_no_self_damage', 'reset_repairs_native',
             'four_animated_controls', 'native_prop_meshes_created', 'native_shifter_moves'], True)}
        test.write_text(json.dumps(proof))
        return package, test, proof

    def test_only_accepts_exact_tested_zip(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, _ = self.fixture(Path(temp))
            self.assertEqual(verify_local_build(package, test)[1], 6)
            with zipfile.ZipFile(package, 'a') as archive:
                archive.writestr('vehicles/acng_bmw1m/changed.json', '{}')
            with self.assertRaisesRegex(RuntimeError, 'differs'):
                verify_local_build(package, test)

    def test_c003_requires_actual_native_detail_evidence(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp))
            proof['test'] = 'C003'; test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                verify_local_build(package, test)
            proof['checks'].update(dict.fromkeys(['four_native_gauges', 'three_native_mirrors',
                'three_native_mirror_cameras', 'four_bmw_rim_meshes',
                'gauges_receive_native_engine_signals', 'speed_gauge_receives_native_motion'], True))
            test.write_text(json.dumps(proof))
            self.assertEqual(verify_local_build(package, test)[1], 12)

    def test_c004_requires_lamp_and_steadiness_evidence(self):
        for label in ('C004 1M lamps', 'C006 1M steering frame', 'C007 1M fitment', 'C008 1M crash isolation',
                      'C009 1M wheel track', 'C010 1M declared wheel track', 'C011 1M brakes', 'C012 1M sound crossfades', 'C013 1M limiter and sounds'):
          with self.subTest(label), tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp))
            proof['test'] = label
            proof['checks'].update(dict.fromkeys(['four_native_gauges', 'three_native_mirrors',
                'three_native_mirror_cameras', 'four_bmw_rim_meshes',
                'gauges_receive_native_engine_signals', 'speed_gauge_receives_native_motion'], True))
            test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                verify_local_build(package, test)
            proof['checks'].update(dict.fromkeys(['lamp_glow_registered', 'lowbeam_and_brake_signals',
                'interior_steady_at_idle', 'interior_steady_while_driving', 'tires_auto_compound',
                'unladen_mass_within_three_percent'], True))
            test.write_text(json.dumps(proof))
            fitted = ['crash_isolation_groups_found', 'tires_centred_on_ac_wheels', 'front_wheels_steer_right']
            extra = {'C008': ['crash_isolation_groups_found'], 'C009': fitted, 'C010': fitted,
                     'C011': fitted + ['torque_curve_matches_ac', 'ac_engine_sound_loaded'],
                     'C012': fitted + ['torque_curve_matches_ac', 'ac_engine_sound_loaded'],
                     'C013': fitted + ['torque_curve_matches_ac', 'ac_engine_sound_loaded',
                         'native_top_speed_limit_configured', 'native_turbo_samples_loaded',
                         'native_shift_samples_loaded', 'top_speed_limiter_holds_250']}.get(label[:4], [])
            if extra:
                with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                    verify_local_build(package, test)
                proof['checks'].update(dict.fromkeys(extra, True))
                test.write_text(json.dumps(proof))
            self.assertEqual(verify_local_build(package, test)[1], 18+len(extra))

    def test_c013_rejects_each_missing_or_failed_native_feature(self):
        needed=['spawn_undamaged','drive_no_self_damage','reset_repairs_native',
                'four_animated_controls','native_prop_meshes_created','native_shifter_moves',
                'four_native_gauges','three_native_mirrors','three_native_mirror_cameras',
                'four_bmw_rim_meshes','gauges_receive_native_engine_signals','speed_gauge_receives_native_motion',
                'lamp_glow_registered','lowbeam_and_brake_signals','interior_steady_at_idle',
                'interior_steady_while_driving','tires_auto_compound','unladen_mass_within_three_percent',
                'crash_isolation_groups_found','tires_centred_on_ac_wheels','front_wheels_steer_right',
                'torque_curve_matches_ac','ac_engine_sound_loaded']
        features=['native_top_speed_limit_configured','native_turbo_samples_loaded',
                  'native_shift_samples_loaded','top_speed_limiter_holds_250']
        with tempfile.TemporaryDirectory() as temp:
            package,test,proof=self.fixture(Path(temp));proof['test']='C013'
            for name in features:
                for value in (None,False):
                    proof['checks']=dict.fromkeys(needed+features,True)
                    if value is None:del proof['checks'][name]
                    else:proof['checks'][name]=value
                    test.write_text(json.dumps(proof))
                    with self.subTest(name=name,value=value),self.assertRaisesRegex(RuntimeError,'incomplete or failed'):
                        verify_local_build(package,test)

    def test_failed_or_incomplete_native_runs_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp))
            proof['checks']['spawn_undamaged'] = False; test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'failed'):
                verify_local_build(package, test)

    def test_unexpected_archive_paths_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, _ = self.fixture(Path(temp))
            with zipfile.ZipFile(package, 'a') as archive:
                archive.writestr('lua/autorun/unexpected.lua', 'return {}')
            (test.parent / 'mods' / package.name).write_bytes(package.read_bytes())
            with self.assertRaisesRegex(RuntimeError, 'paths'):
                verify_local_build(package, test)


class GenericCarLabProof(unittest.TestCase):
    """C014: any AC car, its targets in acng_car/<model>.json, the counted checks named per car."""

    def fixture(self, root, model='acng_bmw_m3e92', targets=None):
        package = root / (model + '.zip')
        with zipfile.ZipFile(package, 'w') as archive:
            archive.writestr(f'vehicles/{model}/info.json', '{}')
            if targets is not None:
                archive.writestr(f'acng_car/{model}.json', json.dumps(targets))
        lab = root / 'lab'; (lab / 'mods').mkdir(parents=True)
        (lab / 'mods' / package.name).write_bytes(package.read_bytes())
        test = lab / 'acng-car-test.json'
        checks = dict.fromkeys(GENERIC_REQUIRED, True)
        checks.update(dict.fromkeys(['animated_controls_3', 'native_gauges_4', 'top_speed_limiter_holds_250'], True))
        proof = {'test': 'C014 generic car lab', 'model': model, 'completed': True, 'checks': checks}
        test.write_text(json.dumps(proof))
        return package, test, proof

    def test_m3_without_a_shifter_passes_with_its_own_targets(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp), targets={'model': 'acng_bmw_m3e92'})
            self.assertEqual(model_of(package), 'acng_bmw_m3e92')
            self.assertEqual(verify_local_build(package, test)[1], len(proof['checks']))

    def test_shifter_is_required_when_targets_name_one_or_are_missing(self):
        for targets in ({'shifter_node': 'sh_l3'}, None):
            with self.subTest(targets=targets), tempfile.TemporaryDirectory() as temp:
                package, test, proof = self.fixture(Path(temp), targets=targets)
                with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                    verify_local_build(package, test)
                proof['checks']['native_shifter_moves'] = True; test.write_text(json.dumps(proof))
                verify_local_build(package, test)

    def test_counted_checks_and_tested_model_are_enforced(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp), targets={})
            del proof['checks']['native_gauges_4']; test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                verify_local_build(package, test)
            proof['checks']['native_gauges_4'] = True; proof['model'] = 'acng_bmw1m'
            test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'different car'):
                verify_local_build(package, test)

    def test_other_cars_need_the_generic_lab(self):
        with tempfile.TemporaryDirectory() as temp:
            package, test, proof = self.fixture(Path(temp), targets={})
            proof['test'] = 'C013 1M limiter and sounds'; test.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError, 'C014'):
                verify_local_build(package, test)

    def test_records_and_paths_are_per_car(self):
        self.assertEqual(record_path_for('acng_bmw1m').name, 'car-install.json')
        self.assertEqual(record_path_for('acng_bmw_m3e92').name, 'car-install-acng_bmw_m3e92.json')
        with tempfile.TemporaryDirectory() as temp:
            package = Path(temp) / 'two.zip'
            with zipfile.ZipFile(package, 'w') as archive:
                archive.writestr('vehicles/a/info.json', '{}'); archive.writestr('vehicles/b/info.json', '{}')
            with self.assertRaisesRegex(RuntimeError, 'one vehicles'):
                model_of(package)
            self.assertFalse(contains_model(package, 'c'))
            self.assertTrue(contains_model(package, 'b'))
