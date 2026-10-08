import unittest
import subprocess
import json
from pathlib import Path
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

class WeekendContracts(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''deepcopy=function(x) return x end; be={getObjectByID=function() return nil end};
          extensions={isExtensionLoaded=function() return false end}; guihooks={trigger=function() end}''')
        self.m=self.lua.execute((ROOT/'beamng-mod/lua/ge/extensions/acng/weekend.lua').read_text(encoding='utf-8'))

    def test_off_by_default_and_master_required(self):
        self.assertEqual(self.m.getSnapshot()['phase'],'off')
        self.assertEqual(self.m.getSnapshot()['options']['opponents'],0)
        self.assertFalse(self.m.prepare())
        self.assertFalse(self.m.begin('race'))

    def test_settings_reject_invalid_values(self):
        for key,value in [('opponents',4),('opponents',1.5),('laps',0),('minutes',float('nan')),('aggression',2),('bad',1)]:
            self.assertFalse(self.m.setOption(key,value))
        self.assertTrue(self.m.setOption('laps',5))
        self.assertEqual(self.m.getSnapshot()['options']['laps'],5)

    def test_qualifying_grid_missing_laps_and_ties(self):
        entries=self.lua.eval('{{id=11,seed=1},{id=22,seed=2},{id=33,seed=3},{id=44,seed=4}}')
        times=self.lua.eval('{[11]=62,[22]=59,[33]=59}')
        order=self.m.qualificationOrder(entries,times)
        self.assertEqual([order[i]['id'] for i in range(1,5)],[22,33,11,44])
        self.assertEqual(entries[1]['id'],11)

    def test_cancel_is_idempotent(self):
        self.assertTrue(self.m.cancel());self.assertTrue(self.m.cancel())
        self.assertEqual(self.m.getSnapshot()['phase'],'off')

    def test_no_session_no_end(self):
        self.assertFalse(self.m.endSession())

    def test_native_completed_laps_supply_best_not_placeholder(self):
        state=self.lua.eval('{bestLapTime={},historicTimes={{duration=62.5},{duration=60.1},{duration=61.4}}}')
        self.assertAlmostEqual(self.m.bestLap(state),60.1)
        self.assertIsNone(self.m.bestLap(self.lua.eval('{bestLapTime={},historicTimes={}}')))

    def test_actual_ui_commands_are_native_callback_expressions(self):
        commands=json.loads(subprocess.check_output(['node',str(ROOT/'tests/weekend_commands.js')],text=True))
        self.lua.execute('''guihooks={trigger=function() end}; extensions={isExtensionLoaded=function() return true end,
          acng_core={setEnabled=function() end,setFeature=function() end},acng_weekend={
          setOption=function() return true end, getSnapshot=function() return {} end,
          prepare=function() return true end,begin=function() return true end,
          cancel=function() return true end,endSession=function() return true end}}''')
        self.assertEqual(len(commands),12)  # each action plus its refresh callback
        for command in commands:
            self.lua.execute('guihooks.trigger("onBNGAPICallback",1,'+command+')')

    def test_core_master_and_feature_off_cancel_immediately(self):
        self.lua.execute('''log=function() end; stopped=0;
          be={getPlayerVehicle=function() return nil end};
          jsonReadFile=function(p) if p:find('defaults') then return {enabled=false,features={race_sessions=false},telemetry={enabled=false}} end end;
          extensions={isExtensionLoaded=function(n) return n=='acng_weekend' end,
          acng_weekend={cancel=function() stopped=stopped+1 end}}''')
        core=self.lua.execute((ROOT/'beamng-mod/lua/ge/extensions/acng/core.lua').read_text(encoding='utf-8'))
        core.onExtensionLoaded()
        self.assertFalse(core.getStatus()['features']['race_sessions'])
        core.setEnabled(True);self.assertTrue(core.setFeature('race_sessions',True))
        core.setEnabled(False);self.assertEqual(self.lua.globals().stopped,1)
        core.setFeature('race_sessions',False);self.assertEqual(self.lua.globals().stopped,2)
        core.onExtensionUnloaded();self.assertEqual(self.lua.globals().stopped,3)

if __name__=='__main__': unittest.main()
