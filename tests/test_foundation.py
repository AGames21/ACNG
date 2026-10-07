import json
import tempfile
import threading
import time
import socket
import unittest
from pathlib import Path

from telemetry.analyze import analyze, MPH_TO_MS
from telemetry.collect_udp import collect

ROOT = Path(__file__).resolve().parents[1]


class AnalysisTests(unittest.TestCase):
    def rows(self, speeds):
        return [{"sim_time_s": i, "speed_m_s": speed, "vehicle_id": 1, "generation": 1}
                for i, speed in enumerate(speeds)]

    def test_linear_acceleration(self):
        result = analyze(self.rows([0, 10, 20, 30]), "acceleration", 60)
        end = 60 * MPH_TO_MS / 10
        self.assertAlmostEqual(result["elapsed_s"], end - 0.01)
        self.assertAlmostEqual(result["distance_m"], 5 * (end**2 - 0.01**2))

    def test_linear_braking(self):
        result = analyze(self.rows([30, 20, 10, 0]), "braking", 60)
        self.assertAlmostEqual(result["distance_m"], ((60 * MPH_TO_MS)**2 - 0.1**2) / 20)

    def test_rejects_incomplete_and_resets(self):
        with self.assertRaises(ValueError):
            analyze(self.rows([0, 2]), "acceleration", 60)
        rows = self.rows([0, 10, 30])
        rows[2]["generation"] = 2
        with self.assertRaises(ValueError):
            analyze(rows, "acceleration", 60)

    def test_rejects_nonmonotonic(self):
        rows = self.rows([0, 30])
        rows[1]["sim_time_s"] = 0
        with self.assertRaises(ValueError):
            analyze(rows, "acceleration", 60)

    def test_rejects_new_vm_even_when_object_id_and_generation_repeat(self):
        rows = self.rows([0,10,30])
        rows[0]['capture_id']=rows[1]['capture_id']='first'
        rows[2]['capture_id']='replacement'
        with self.assertRaises(ValueError):analyze(rows,'acceleration',60)


class ReceiverTests(unittest.TestCase):
    def test_idle_timeout_starts_only_after_accepted_sample(self):
        with tempfile.TemporaryDirectory() as folder:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
                probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
            started=time.monotonic()
            result={}
            worker=threading.Thread(target=lambda:result.update(collect(Path(folder)/'idle.jsonl',3,port,0.1)))
            worker.start();time.sleep(0.2)
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sender:
                sender.sendto(json.dumps({'schema_version':1,'source':'beamng','sequence':1,
                    'vehicle_id':1,'generation':1}).encode(),('127.0.0.1',port))
            worker.join(2)
            self.assertFalse(worker.is_alive())
            self.assertEqual(result['accepted'],1)
            self.assertEqual(result['finish_reason'],'idle_after_samples')
            self.assertGreater(time.monotonic()-started,0.2)

    def test_reused_object_id_has_independent_sequence_history(self):
        with tempfile.TemporaryDirectory() as folder:
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
                probe.bind(('127.0.0.1',0))
                port=probe.getsockname()[1]
            result={}
            worker=threading.Thread(target=lambda:result.update(collect(Path(folder)/'test.jsonl',0.6,port)))
            worker.start()
            time.sleep(0.1)
            with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sender:
                for capture,seq in [('first',10),('replacement',1),('replacement',3)]:
                    sender.sendto(json.dumps({'schema_version':1,'source':'beamng','sequence':seq,
                        'capture_id':capture,'vehicle_id':5,'generation':1}).encode(),('127.0.0.1',port))
            worker.join(3)
            self.assertFalse(worker.is_alive())
            self.assertEqual(result['accepted'],3)
            self.assertEqual(result['out_of_order'],0)
            self.assertEqual(result['sequence_gaps'],1)

    def test_real_loopback_loss_and_bad_payload(self):
        with tempfile.TemporaryDirectory() as folder:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.bind(("127.0.0.1", 0))
                port = probe.getsockname()[1]
            out = Path(folder) / "test.jsonl"
            result = {}
            worker = threading.Thread(target=lambda: result.update(collect(out, 0.8, port)))
            worker.start()
            time.sleep(0.15)
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                for seq in [1, 3, 2]:
                    sender.sendto(json.dumps({"schema_version":1,"source":"beamng", "sequence":seq,
                        "vehicle_id":1,"generation":1}).encode(), ("127.0.0.1", port))
                sender.sendto(b"not JSON", ("127.0.0.1", port))
            worker.join(3)
            self.assertFalse(worker.is_alive())
            self.assertEqual(result["accepted"], 3)
            self.assertEqual(result["malformed"], 1)
            self.assertEqual(result["sequence_gaps"], 1)
            self.assertEqual(result["out_of_order"], 1)


try:
    from lupa.luajit21 import LuaRuntime
except ImportError:
    LuaRuntime = None


@unittest.skipIf(LuaRuntime is None, "Install Lupa in isolated toolchain for LuaJIT contracts")
class LuaContracts(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("log=function() end")

    def test_all_files_compile_as_lua51(self):
        compiler = self.lua.eval("function(s) local f,e=loadstring(s); if not f then error(e) end; return true end")
        for path in (ROOT / "beamng-mod").rglob("*.lua"):
            self.assertTrue(compiler(path.read_text(encoding="utf-8")), str(path))

    def test_master_and_telemetry_lifecycle(self):
        self.lua.execute('''
        commands={}
        vehicle={getID=function() return 5 end,
          queueLuaCommand=function(self,cmd) commands[#commands+1]=cmd end}
        be={getPlayerVehicle=function() return vehicle end,getObjectByID=function() return vehicle end}
        jsonReadFile=function(path)
          if path:find('defaults') then return {enabled=false,telemetry={enabled=false,rate_hz=50,port=44443}} end
        end
        ''')
        mod = self.lua.execute((ROOT / "beamng-mod/lua/ge/extensions/acng/core.lua").read_text())
        mod.onExtensionLoaded()
        mod.onUpdate(1)
        self.assertEqual(len(self.lua.globals().commands), 0)
        mod.setEnabled(True)
        mod.onUpdate(1)
        # Master ON attaches only the read-only performance timer.
        self.assertEqual(len(self.lua.globals().commands), 1)
        self.assertIn("extensions.load('acng_perf')", self.lua.globals().commands[1])
        self.assertIn("extensions.load('acng_laps')", self.lua.globals().commands[1])
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        mod.setTelemetryEnabled(True)
        mod.onUpdate(1)
        self.assertEqual(len(self.lua.globals().commands), 2)
        self.assertIn("acng_telemetry.start", self.lua.globals().commands[2])
        mod.setTelemetryEnabled(False)
        self.assertIn("stop()", self.lua.globals().commands[3])
        mod.setEnabled(False)
        self.assertIn("extensions.unload('acng_perf')", self.lua.globals().commands[4])
        self.assertIn("extensions.unload('acng_laps')", self.lua.globals().commands[4])
        mod.onUpdate(1)
        self.assertEqual(len(self.lua.globals().commands), 4)

    def test_reader_no_catchup_and_reset_boundary(self):
        self.lua.execute('''
        sent=0; closed=0
        package.preload.socket=function() return {udp=function() return {
          settimeout=function() end,setpeername=function() return true end,
          send=function(self,p) sent=sent+1 end,close=function() closed=closed+1 end} end} end
        jsonEncode=function(r) row=r; return '{}' end
        local vector={x=0,y=0,z=0,length=function() return 0 end}
        obj={getVelocity=function() return vector end,getPosition=function() return vector end,
          getId=function() return 5 end}
        electrics={values={}}; sensors={}; wheels={wheels={}}; v={data={}}
        ''')
        mod = self.lua.execute((ROOT / "beamng-mod/lua/vehicle/extensions/acng/telemetry.lua").read_text())
        mod.updateGFX(1)
        self.assertEqual(self.lua.globals().sent, 0)
        self.assertTrue(mod.start(50, 44443))
        mod.updateGFX(0.2)
        self.assertEqual(self.lua.globals().sent, 1)
        generation = self.lua.globals().row["generation"]
        mod.onReset()
        mod.updateGFX(0.02)
        self.assertEqual(self.lua.globals().row["generation"], generation + 1)
        mod.stop()
        mod.updateGFX(1)
        self.assertEqual(self.lua.globals().sent, 2)

    def test_same_id_spawn_reattaches_with_new_capture_identity(self):
        self.lua.execute('''
        commands={}
        vehicle={getID=function() return 5 end,getJBeamFilename=function() return 'etkc' end,
          queueLuaCommand=function(self,cmd) commands[#commands+1]=cmd end}
        be={getPlayerVehicle=function() return vehicle end,getObjectByID=function() return vehicle end}
        jsonReadFile=function() return {schema_version=1,enabled=false,
          telemetry={enabled=false,rate_hz=50,port=44443}} end
        ''')
        mod=self.lua.execute((ROOT/'beamng-mod/lua/ge/extensions/acng/core.lua').read_text())
        mod.onExtensionLoaded()
        mod.setTelemetryEnabled(True)
        mod.onUpdate(0.3)
        first=mod.getStatus()['attached_capture_id']
        mod.onVehicleSpawned(5)
        mod.onUpdate(0.01)
        self.assertEqual(len(self.lua.globals().commands),2)
        self.assertNotEqual(first,mod.getStatus()['attached_capture_id'])
        self.assertEqual(mod.getStatus()['physics_writes'],0)


    def load_perf(self):
        self.lua.execute("guihooks={trigger=function() end}")
        return self.lua.execute((ROOT / "beamng-mod/lua/vehicle/extensions/acng/perf.lua").read_text())

    def drive(self, mod, state, speed0, accel, seconds, brake=0, throttle=0):
        # Constant acceleration with deliberately uneven frame times.
        dts, t, speed = (1 / 60, 1 / 45, 1 / 75), 0.0, speed0
        i = 0
        while t < seconds:
            dt = dts[i % 3]; i += 1
            speed = max(0.0, speed + accel * dt); t += dt
            mod.step(state, dt, speed, brake, throttle)
        return speed

    def test_perf_timer_launch_targets_and_quarter_mile(self):
        mod = self.load_perf()
        state = mod.newState()
        mod.step(state, 1 / 60, 0, 0, 0)
        self.assertEqual(state.mode, "armed")
        self.drive(mod, state, 0.0, 5.0, 20)
        start, a = 0.15, 5.0
        for key, target in (("mph_0_60", 60 * 0.44704), ("kmh_0_100", 100 / 3.6),
                            ("mph_0_100", 100 * 0.44704), ("kmh_0_200", 200 / 3.6)):
            self.assertAlmostEqual(state.last[key].time_s, (target - start) / a, places=6, msg=key)
        t = (-start + (start ** 2 + 2 * a * 402.336) ** 0.5) / a
        self.assertAlmostEqual(state.last.quarter_mile.time_s, t, places=6)
        self.assertAlmostEqual(state.last.quarter_mile.trap_speed_m_s, start + a * t, places=6)
        self.assertEqual(state.mode, "rolling")  # all targets done; no stale run left open

    def test_perf_braking_distance_and_rejections(self):
        mod = self.load_perf()
        state = mod.newState()
        mod.step(state, 1 / 60, 33.0, 0, 0)
        self.drive(mod, state, 33.0, -8.0, 6, brake=1)
        for key, target in (("mph_60_0", 60 * 0.44704), ("kmh_100_0", 100 / 3.6)):
            self.assertAlmostEqual(state.last[key].distance_m, (target ** 2 - 0.3 ** 2) / 16, places=6, msg=key)
            self.assertAlmostEqual(state.last[key].time_s, (target - 0.3) / 8, places=6, msg=key)
        self.assertEqual(state.mode, "armed")
        best = state.best.mph_60_0.distance_m
        # Coasting through the threshold without braking is not a braking run.
        fresh = mod.newState()
        mod.step(fresh, 1 / 60, 33.0, 0, 0)
        self.drive(mod, fresh, 33.0, -8.0, 6, brake=0)
        self.assertIsNone(fresh.last.mph_60_0)
        # A worse stop updates last but keeps the best.
        mod.step(state, 1 / 60, 33.0, 0, 0)
        self.drive(mod, state, 33.0, -6.0, 7, brake=1)
        self.assertGreater(state.last.mph_60_0.distance_m, best)
        self.assertAlmostEqual(state.best.mph_60_0.distance_m, best, places=9)

    def test_perf_pause_reset_and_no_writes(self):
        self.lua.execute('''
        sent={}
        speed=0
        obj={getVelocity=function() return {length=function() return speed end} end}
        electrics={values={brake=0,throttle=0}}
        ''')
        mod = self.load_perf()
        self.lua.execute("guihooks={trigger=function(name,data) sent[#sent+1]=data end}")
        g = self.lua.globals()
        mod.updateGFX(1 / 60)
        g.speed = 3.0
        mod.updateGFX(0.5)
        self.assertEqual(mod.getSnapshot().mode, "launch")
        run_time = mod.getSnapshot().run_time_s
        mod.updateGFX(0)  # paused simulation: time must not advance
        self.assertEqual(mod.getSnapshot().run_time_s, run_time)
        mod.onReset()
        self.assertIsNone(mod.getSnapshot().run_time_s)
        g.speed = 0
        mod.updateGFX(1 / 60)
        self.assertEqual(mod.getSnapshot().mode, "armed")
        self.assertGreater(len(g.sent), 0)
        source = (ROOT / "beamng-mod/lua/vehicle/extensions/acng/perf.lua").read_text()
        for write in ("input.event", "applyForce", "setFriction", "queueLuaCommand", "setGearboxMode"):
            self.assertNotIn(write, source)

    def test_vehicle_guards_do_not_autoload_extensions(self):
        # BeamNG's extensions table loads unknown names on access, so
        # "if extensions.x then" would load x just to test for it.
        import re
        for path in list((ROOT / "beamng-mod").rglob("*.lua")) + list((ROOT / "beamng-mod").rglob("*.js")):
            text = path.read_text(encoding="utf-8")
            for match in re.finditer(r"(?:if|and|not)\s+extensions\.(acng_\w+)", text):
                self.assertEqual(match.group(1), "acng_core", f"{path.name}: guard on {match.group(1)}")

    def test_extension_file_names_resolve(self):
        # BeamNG maps "acng_a_b" to acng/a/b.lua, so an underscore in a file
        # name makes the extension unloadable by its natural name.
        for path in list((ROOT / "beamng-mod").rglob("extensions/**/*.lua")) + list((ROOT / "tests").rglob("extensions/**/*.lua")):
            self.assertNotIn("_", path.stem, str(path))

    def test_perf_follows_vehicle_switch_and_respawn(self):
        self.lua.execute('''
        commands={}; current=5
        local function vehicle(id) return {getID=function() return id end,
          queueLuaCommand=function(self,cmd) commands[#commands+1]=id..':'..cmd end} end
        be={getPlayerVehicle=function() return vehicle(current) end,getObjectByID=function(self,id) return vehicle(id) end}
        jsonReadFile=function() return {schema_version=1,enabled=false,telemetry={enabled=false,rate_hz=50,port=44443}} end
        ''')
        mod = self.lua.execute((ROOT / "beamng-mod/lua/ge/extensions/acng/core.lua").read_text())
        mod.onExtensionLoaded()
        mod.setEnabled(True)
        mod.onUpdate(0.01)
        g = self.lua.globals()
        self.assertEqual(g.commands[1], "5:extensions.load('acng_perf'); extensions.load('acng_laps')")
        g.current = 7
        mod.onUpdate(0.3)
        self.assertEqual(g.commands[2], "5:extensions.unload('acng_perf'); extensions.unload('acng_laps')")
        self.assertEqual(g.commands[3], "7:extensions.load('acng_perf'); extensions.load('acng_laps')")
        mod.onVehicleSpawned(7)  # same object, new vehicle VM
        mod.onUpdate(0.01)
        self.assertEqual(g.commands[4], "7:extensions.load('acng_perf'); extensions.load('acng_laps')")
        self.assertEqual(mod.getStatus()["performance_timer_vehicle_id"], 7)
        self.assertEqual(mod.getStatus()["lap_timer_vehicle_id"], 7)

if __name__ == "__main__":
    unittest.main()
