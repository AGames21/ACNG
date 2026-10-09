import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from install_car_normal import verify_local_build, contains_model


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
        for label in ('C004 1M lamps', 'C006 1M steering frame'):
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
            self.assertEqual(verify_local_build(package, test)[1], 18)

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
