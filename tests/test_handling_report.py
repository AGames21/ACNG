import copy
import math
import unittest
from tools.handling_report import summarize


def fixture(gradient=2):
    return {'completed': True, 'checks': {'straight': True, 'circle': True},
            'acceleration': [{'time_s': v} for v in (5, 5.1, 4.9, 5.05, 5.2)],
            'braking': [{'distance_m': v} for v in (36, 35, 37, 36.1, 35.9)],
            'circles': [{'input': 0.12, 'lateral_g': g, 'radius_m': 30,
                         'steer_rad': math.atan(2.660/30)+math.radians(gradient*g), 'valid_steady': True}
                        for g in (0.2, 0.5, 0.8)]}


class HandlingReport(unittest.TestCase):
    def test_medians_and_known_understeer_gradient(self):
        r = summarize(fixture())
        self.assertEqual(r['accel_0_100_kmh_s']['median'], 5.05)
        self.assertEqual(r['brake_100_0_kmh_m']['median'], 36)
        self.assertAlmostEqual(r['balance'][0]['gradient_deg_per_g'], 2)
        self.assertEqual(r['balance'][0]['classification'], 'understeer')

    def test_oversteer_and_neutral(self):
        for slope, name in ((-2, 'oversteer'), (0, 'near neutral')):
            self.assertEqual(summarize(fixture(slope))['balance'][0]['classification'], name)

    def test_rejects_transient_peak(self):
        raw = fixture()
        raw['circles'].append(dict(raw['circles'][0], lateral_g=3, valid_steady=False))
        self.assertEqual(summarize(raw)['max_accepted_steady_lateral_g'], 0.8)

    def test_missing_failed_or_nonfinite_evidence_refused(self):
        original = fixture()
        variants = [dict(original, completed=False), dict(original, checks={'bad': False}),
                    dict(original, acceleration=original['acceleration'][:4]), dict(original, circles=[])]
        nan = copy.deepcopy(original)
        nan['braking'][0]['distance_m'] = float('nan')
        variants.append(nan)
        for raw in variants:
            with self.assertRaises(ValueError):
                summarize(raw)
