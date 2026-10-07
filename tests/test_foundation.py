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
        self.assertEqual(len(self.lua.globals().commands), 0)
        self.assertEqual(mod.getStatus()["physics_writes"], 0)
        mod.setTelemetryEnabled(True)
        mod.onUpdate(1)
        self.assertEqual(len(self.lua.globals().commands), 1)
        mod.setTelemetryEnabled(False)
        self.assertIn("stop()", self.lua.globals().commands[2])

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


if __name__ == "__main__":
    unittest.main()
