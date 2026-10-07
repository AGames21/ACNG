"""Every ACNG Assists button command must run inside BeamNG's engineLua callback wrapper.

bngApi.engineLua(code, callback) runs guihooks.trigger("onBNGAPICallback", id, <code>), so a
command with several statements is a Lua syntax error there (the tire buttons' fatal error).
"""
import json, subprocess, unittest
from pathlib import Path
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class AssistsButtonBridge(unittest.TestCase):
    def test_every_command_runs_in_the_native_callback_wrapper(self):
        commands = json.loads(subprocess.check_output(["node", "tests/assists_app_commands.js"], cwd=ROOT, text=True))
        self.assertEqual(len(commands), 10)
        for key, choice, command in commands:
            lua = LuaRuntime()
            lua.execute("enabled=false; features={}; levels={}; callbacks=0;"
                        "extensions={acng_core={setEnabled=function(v) enabled=v; return v end,"
                        "setAssistLevel=function(k,n) levels[k]=n; return true end,"
                        "setFeature=function(k,v) features[k]=v; return v end}};"
                        "guihooks={trigger=function() callbacks=callbacks+1 end}")
            lua.execute('guihooks.trigger("onBNGAPICallback", 1, ' + command + ')')
            g = lua.globals()
            self.assertEqual(g.callbacks, 1, command)
            if choice == "factory":
                self.assertEqual((g.enabled, g.features[key]), (False, False))
            else:
                self.assertEqual((g.enabled, g.levels[key], g.features[key]), (True, choice, True))


if __name__ == "__main__":
    unittest.main()
