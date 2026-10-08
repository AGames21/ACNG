import unittest,json,subprocess
from pathlib import Path
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class ControlContracts(unittest.TestCase):
    def setUp(self):
        self.l=LuaRuntime(unpack_returned_tuples=True)
        self.l.execute('''deepcopy=function(t) local out={} for k,v in pairs(t) do out[k]=type(v)=='table' and deepcopy(v) or v end return out end;
          log=function() end; files={}; writes=0;FS={directoryCreate=function() end};
          jsonReadFile=function(p) if p:find('defaults') then return {schema_version=1,enabled=false,features={},telemetry={enabled=false},assist_levels={abs=2,tc=2},ffb_settings={gain=1}} end return files[p] end;
          jsonWriteFile=function(p,v) files[p]=deepcopy(v);writes=writes+1;return true end;
          be={getPlayerVehicle=function() return nil end,getObjectByID=function() return nil end};
          extensions={isExtensionLoaded=function() return false end}''')
        self.core=self.l.execute((ROOT/'beamng-mod/lua/ge/extensions/acng/core.lua').read_text(encoding='utf-8'));self.core.onExtensionLoaded()

    def test_first_click_meaningful_and_optional_assists_stay_factory(self):
        self.assertTrue(self.core.setControlEnabled(True));s=self.core.getStatus()
        self.assertTrue(s['features']['tire_temperature']);self.assertTrue(s['features']['tire_wear'])
        self.assertFalse(s['features']['abs']);self.assertFalse(s['features']['tc']);self.assertFalse(s['features']['ffb'])

    def test_tire_profile_default_validation_and_saved_selection(self):
        self.assertEqual(self.core.getStatus()['tire_profile'], 'auto')
        self.assertFalse(self.core.setTireProfile('slick; injected()'))
        self.assertTrue(self.core.setTireProfile('sport'))
        self.core.saveSettings();self.core.onExtensionLoaded()
        self.assertEqual(self.core.getStatus()['tire_profile'], 'sport')

    def test_old_default_road_moves_to_auto_but_a_chosen_road_stays(self):
        self.l.execute("files['/settings/acng/runtime.json']={schema_version=1,tire_profile='road'}")
        self.core.onExtensionLoaded();self.assertEqual(self.core.getStatus()['tire_profile'],'auto')
        self.assertTrue(self.core.setTireProfile('road'));self.core.saveSettings();self.core.onExtensionLoaded()
        self.assertEqual(self.core.getStatus()['tire_profile'],'road')

    def test_off_stops_developer_stream_and_preserves_choices(self):
        self.core.setControlEnabled(True);self.core.setTelemetryEnabled(True);self.core.setControlEnabled(False)
        s=self.core.getStatus();self.assertFalse(s['enabled']);self.assertFalse(s['telemetry_enabled']);self.assertTrue(s['features']['tire_wear'])

    def test_deliberately_empty_choices_are_not_overridden(self):
        self.core.setFeature('tire_wear',False);self.core.setControlEnabled(True)
        self.assertFalse(self.core.getStatus()['features']['tire_temperature'])

    def test_preferences_survive_reload_but_master_and_capture_start_off(self):
        self.core.setControlEnabled(True);self.core.setFeature('tire_wear',False);self.core.setFFBSetting('gain',1.2)
        self.core.setTelemetryEnabled(True);self.assertTrue(self.core.saveSettings())
        self.core.onExtensionLoaded();s=self.core.getStatus();self.assertFalse(s['enabled']);self.assertFalse(s['telemetry_enabled'])
        self.assertTrue(s['features']['tire_temperature']);self.assertFalse(s['features']['tire_wear']);self.assertEqual(s['ffb_settings']['gain'],1.2)

    def test_debounce_backup_and_write_error_visible(self):
        self.core.setControlEnabled(True);self.core.onUpdate(0.2);self.assertEqual(self.l.globals().writes,0)
        self.core.onUpdate(0.3);self.assertEqual(self.l.globals().writes,1);self.assertIsNone(self.core.getStatus()['settings_error'])
        self.core.setFeature('tire_wear',False);self.core.saveSettings();self.assertIsNotNone(self.l.globals().files['/settings/acng/runtime.previous.json'])
        self.l.execute('jsonWriteFile=function() return false end');self.assertFalse(self.core.saveSettings());self.assertIsNotNone(self.core.getStatus()['settings_error'])

    def test_actual_commands_in_native_callback_wrapper(self):
        commands=json.loads(subprocess.check_output(['node',str(ROOT/'tests/control_commands.js')],text=True))
        self.l.globals().extensions.acng_core=self.core
        self.l.execute('guihooks={trigger=function() end}')
        for cmd in commands:self.l.execute('guihooks.trigger("onBNGAPICallback",1,'+cmd+')')

    def test_pits_follow_vehicle_and_master_off_unloads(self):
        self.l.execute('''commands={};car={getID=function() return 42 end,
          queueLuaCommand=function(self,s) commands[#commands+1]=s end};
          be.getPlayerVehicle=function() return car end;be.getObjectByID=function() return car end''')
        self.assertFalse(self.core.pitCommand('mark',True,True))
        self.core.setControlEnabled(True);self.core.setFeature('pits',True)
        self.core.onUpdate(0.3)
        self.assertTrue(self.core.pitCommand('mark',False,False))
        self.assertFalse(self.core.pitCommand('injected()',True,True))
        self.core.onVehicleSwitched()
        self.assertFalse(self.core.pitCommand('service',True,True))
        self.core.onUpdate(0.3)
        self.assertTrue(self.core.pitCommand('mark',False,False))
        self.core.setControlEnabled(False)
        self.assertIn("extensions.unload('acng_pits')",list(self.l.globals().commands.values()))
        self.assertFalse(self.core.pitCommand('service',True,True))

if __name__=='__main__':unittest.main()
