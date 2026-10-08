import unittest
from scripts.analyze_roadlab import summarize


class RoadReport(unittest.TestCase):
    def test_missing_pressure_is_unavailable_not_zero(self):
        data={'sets':[{'name':'x','samples':[{'stage':'idle','speed':0,'w':{'FL':{'s':15,'c':15,'psi':None}}}]}]}
        self.assertIsNone(summarize(data)['summary'][0]['tires']['FL']['pressure_rise_psi'])

    def test_uses_each_tires_own_initial_pressure_and_peak(self):
        samples=[]
        for s,c,p in ((15,15,26),(70,25,28),(20,22,27)):
            samples.append({'stage':'cruise','speed':22,'w':{'FL':{'s':s,'c':c,'psi':p}}})
        row=summarize({'completed':True,'sets':[{'name':'x','samples':samples}]})['summary'][0]
        self.assertEqual(row['tires']['FL']['pressure_rise_psi'],2)
        self.assertEqual(row['tires']['FL']['peak_surface_c'],70)
        self.assertEqual(row['tires']['FL']['last_surface_c'],20)
        self.assertEqual(row['stages']['cruise']['mean_speed_m_s'],22)

    def test_empty_run_rejected(self):
        with self.assertRaises(ValueError):
            summarize({'sets':[{'name':'bad','samples':[]}]})
