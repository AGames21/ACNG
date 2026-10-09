import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import car_pipeline  # noqa: E402


class NextFolderTests(unittest.TestCase):
    def test_numbers_above_highest_and_ignores_other_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ('ACNG-car-001', 'ACNG-car-028', 'ACNG-car-016', 'ACNG-car', 'ACNG-control-003', 'ACNG-car-02x'):
                (Path(tmp) / name).mkdir()
            self.assertEqual(car_pipeline.next_folder(tmp, 'ACNG-car').name, 'ACNG-car-029')

    def test_missing_parent_starts_at_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(car_pipeline.next_folder(Path(tmp) / 'none', 'bmw1m-fix').name, 'bmw1m-fix-001')


class SummarizeTests(unittest.TestCase):
    def test_all_passed(self):
        s = car_pipeline.summarize({'test': 'C013 x', 'completed': True, 'stage': 'done', 'checks': {'a': True, 'b': True}})
        self.assertTrue(s['ok'])
        self.assertEqual((s['passed'], s['total'], s['failed']), (2, 2, []))

    def test_failed_check_blocks(self):
        s = car_pipeline.summarize({'completed': True, 'checks': {'a': True, 'b': False}})
        self.assertFalse(s['ok'])
        self.assertEqual(s['failed'], ['b'])

    def test_incomplete_error_or_empty_blocks(self):
        self.assertFalse(car_pipeline.summarize({'completed': False, 'checks': {'a': True}})['ok'])
        self.assertFalse(car_pipeline.summarize({'completed': True, 'error': 'timeout', 'checks': {'a': True}})['ok'])
        self.assertFalse(car_pipeline.summarize({'completed': True, 'checks': {}})['ok'])
        self.assertFalse(car_pipeline.summarize({})['ok'])


if __name__ == '__main__':
    unittest.main()
