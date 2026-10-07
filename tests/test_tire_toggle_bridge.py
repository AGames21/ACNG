import json,subprocess,unittest
from pathlib import Path
from lupa.luajit21 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
class TireButtonBridge(unittest.TestCase):
 def test_actual_click_commands_inside_native_callback_wrapper(self):
  commands=json.loads(subprocess.check_output(['node','tests/tire_toggle_commands.js'],cwd=ROOT,text=True))
  lua=LuaRuntime();lua.execute("enabled=false;features={};callbacks=0;extensions={acng_core={setEnabled=function(v) enabled=v;return v end,setFeature=function(k,v) features[k]=v;return v end}};guihooks={trigger=function() callbacks=callbacks+1 end}")
  states=[(True,True,None),(True,True,True),(True,False,True),(True,False,False)]
  for command,want in zip(commands,states):
   lua.execute('guihooks.trigger("onBNGAPICallback",1,'+command+')')
   g=lua.globals();self.assertEqual((g.enabled,g.features.tire_temperature,g.features.tire_wear),want)
  self.assertEqual(lua.globals().callbacks,4)
if __name__=='__main__':unittest.main()
