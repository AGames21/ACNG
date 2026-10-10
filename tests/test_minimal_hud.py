import importlib.util
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('minimal_hud',Path(__file__).resolve().parents[1]/'scripts/minimal_hud.py')
minimal_hud=importlib.util.module_from_spec(spec);spec.loader.exec_module(minimal_hud)


class MinimalHudLayout(unittest.TestCase):
    def test_removes_clutter_keeps_the_rest(self):
        data={'title':'Freeroam','version':0.54,'apps':[
            {'appName':'tacho2','placement':{}},{'appName':'damageApp','placement':{'left':'0px'}},
            {'appName':'forcedInduction'},{'appName':'simplePowertrainControl'},{'appName':'dragRace'},
            {'appName':'acngControl','placement':{'width':'360px','height':'480px'}},
            {'appName':'acngRacingHud'},{'appName':'inputHints','settings':{'x':1}}]}
        out=minimal_hud.minimal_layout(data)
        self.assertEqual([a['appName'] for a in out['apps']],['damageApp','acngControl','inputHints','acngTires'])
        self.assertEqual(out['apps'][0],data['apps'][1])
        self.assertEqual(out['apps'][1]['placement']['height'],'32px')
        self.assertEqual(out['apps'][3]['placement']['bottom'],'16px')
        self.assertEqual(out['title'],'Freeroam')
        self.assertEqual(len(data['apps']),8)  # input untouched

    def test_idempotent(self):
        once=minimal_hud.minimal_layout({'apps':[{'appName':'tacho2'}]})
        self.assertEqual(minimal_hud.minimal_layout(once),once)


if __name__=='__main__':
    unittest.main()
