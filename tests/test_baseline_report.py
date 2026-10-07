import unittest
from telemetry.baseline_report import report


class ReportTests(unittest.TestCase):
    def test_completed_harness_without_capture_is_rejected(self):
        with self.assertRaises(ValueError):
            report([],{'completed':True,'requested_runs':1,'runs':[{'run':1,'capture_id':'missing'}]})

    def test_incomplete_or_missing_repeats_are_not_success(self):
        for completed,runs in [(False,[]),(True,[])]:
            with self.assertRaises(ValueError):report([],{'completed':completed,'requested_runs':5,'runs':runs})

    def test_damage_in_trace_is_not_valid_stock_baseline(self):
        row={'capture_id':'one','vehicle_model':'etkc','wheels':[{'broken':True}]}
        with self.assertRaises(ValueError):report([row],{'completed':True,'requested_runs':1,
            'runs':[{'run':1,'capture_id':'one'}],'model':'etkc'})

    def test_warmup_stop_does_not_become_braking_endpoint(self):
        speeds=[0.2,0,0,0,10,30,50,40,20,0,0]
        rows=[{'capture_id':'one','vehicle_model':'etkc','vehicle_id':5,'generation':1,
            'sim_time_s':i,'speed_m_s':speed,'position_m':[0,i,0],
            'velocity_world_m_s':[0,speed,0],'forward_world_native':[0,1,0],
            'throttle':1 if 3<=i<=6 else 0,'brake':1 if i>=7 else 0,'rpm':700,
            'wheels':[{'broken':False,'deflated':False}]} for i,speed in enumerate(speeds)]
        result=report(rows,{'test':'B002 synthetic boundary','model':'etkc',
            'completed':True,'requested_runs':1,'runs':[{'run':1,'capture_id':'one'}],
            'controls':'known test controls','assists':'factory','spawn':{}})
        metric=result['runs'][0]['metrics']['100-0']
        self.assertGreater(metric['start_time_s'],6)
        self.assertGreater(metric['end_time_s'],8)


if __name__=='__main__':unittest.main()
