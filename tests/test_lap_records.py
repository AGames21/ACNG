"""Offline LuaJIT tests; do not launch BeamNG or claim live verification."""
import json
import math
import unittest
from pathlib import Path
from lupa.luajit21 import LuaRuntime, lua_type

ROOT=Path(__file__).resolve().parents[1]
STORE=ROOT/'beamng-mod/lua/ge/extensions/acng/lapRecords.lua'
LAPS=ROOT/'beamng-mod/lua/vehicle/extensions/acng/laps.lua'

def plain(value):
    if lua_type(value)!='table': return value
    keys=list(value.keys())
    if keys and all(isinstance(k,(int,float)) for k in keys) and set(keys)==set(range(1,len(keys)+1)):
        return [plain(value[i]) for i in range(1,len(keys)+1)]
    return {k:plain(v) for k,v in value.items()}

class SavedLapContracts(unittest.TestCase):
    def boot(self,files=None):
        self.files=files if files is not None else {}
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        g=self.lua.globals()
        g.jsonEncode=lambda value:json.dumps(plain(value),separators=(',',':'))
        g.jsonDecode=lambda text:self.lua.table_from(json.loads(text),recursive=True) if json.loads(text) is not None else None
        g.jsonReadFile=lambda path:g.jsonDecode(self.files[path]) if path in self.files else None
        def write(path,data,*args):
            if g.failWrite: return False
            self.files[path]=g.jsonEncode(data);return True
        g.jsonWriteFile=write
        g.fileExists=lambda path:path in self.files
        self.lua.execute("""
          FS={fileExists=function(_,p) return fileExists(p) end}
          log=function() end; guihooks={trigger=function() end}
          map='smallgrid'; activeID=42; config={parts={engine='stock'},vars={boost=1}}
          getMissionFilename=function() return map end
          core_vehicle_manager={getVehicleData=function() return {config=config} end}
          reply=nil
          car={getID=function() return activeID end,getJBeamFilename=function() return 'etkc' end,
            queueLuaCommand=function(_,code) reply=code end}
          be={getPlayerVehicle=function() return car end}
          extensions={isExtensionLoaded=function(name) return extensions[name]~=nil end,load=function() end}
        """)
        self.store=self.lua.execute(STORE.read_text())
        g.extensions.acng_lapRecords=self.store
        self.record=self.lua.eval("{line={x=50,y=0,nx=0,ny=1},best={time_s=10,distance_m=100},best_trace={d={0,50,100},t={0,5,10}},ref_length_m=100,best_sectors={3,3,4}}")
        return g

    def save(self,token='one'):
        return self.store.save(42,token,self.lua.globals().jsonEncode(self.record))

    def test_restart_keeps_reference_and_config_isolates(self):
        g=self.boot();self.assertTrue(self.store.request(42,'one'));self.assertTrue(self.save())
        self.assertIn('saved',g.reply)
        files=dict(self.files);g=self.boot(files)
        self.assertTrue(self.store.request(42,'two'));self.assertIn('loaded',g.reply)
        g.config.parts.engine='race';self.store.request(42,'three');self.assertIn('ready',g.reply)
        g.config.parts.engine='stock';g.map='west_coast';self.store.request(42,'four');self.assertIn('ready',g.reply)

    def test_stale_vehicle_or_request_cannot_overwrite(self):
        g=self.boot();self.store.request(42,'one');self.store.request(42,'new')
        self.assertFalse(self.save());self.assertEqual(self.files,{})
        g.config.vars.boost=2;self.assertFalse(self.save('new'))
        g.activeID=43;self.assertFalse(self.store.request(42,'one'))

    def test_validation_and_failed_write_preserve_history(self):
        g=self.boot();self.store.request(42,'one');self.assertTrue(self.save())
        old=dict(self.files);self.record.best_trace.d[2]=0
        self.assertFalse(self.save());self.assertEqual(self.files,old)
        self.record.best_trace.d[2]=50;g.failWrite=True
        self.assertFalse(self.save());self.assertEqual(self.files,old);self.assertIn('not_saved',g.reply)

    def test_corrupt_primary_uses_backup_without_overwrite(self):
        g=self.boot();self.store.request(42,'one');self.save();self.save()
        self.files['/settings/acng/lap-records.json']='broken json'
        files=dict(self.files);g=self.boot(files);self.store.request(42,'one')
        self.assertIn('read_only',g.reply);self.assertIn('best_trace',g.reply)
        self.assertFalse(self.save());self.assertEqual(files,self.files)

    def test_key_order_stability_and_invalid_trace(self):
        self.boot()
        a=self.lua.eval('{parts={a="x",b="y"},vars={boost=1}}')
        b=self.lua.eval('{vars={boost=1},parts={b="y",a="x"}}')
        self.assertEqual(self.store.canonical(a),self.store.canonical(b))
        self.assertTrue(self.store.validate(self.record))
        self.record.best.time_s=float('nan');self.assertFalse(self.store.validate(self.record))
        self.record.best.time_s=10;self.record.line.ny=2;self.assertFalse(self.store.validate(self.record))

    def test_corrupt_line_only_sectors_and_sparse_trace_are_rejected(self):
        g=self.boot()
        malformed=self.lua.eval('{line={x=0,y=0,nx=0,ny=1},best_sectors="bad"}')
        self.assertFalse(self.store.validate(malformed))
        malformed.best_sectors=self.lua.table_from({1:3,3:4})
        self.assertFalse(self.store.validate(malformed))
        malformed.best_sectors=self.lua.table();malformed.best=False
        self.assertFalse(self.store.validate(malformed))
        self.record.best_trace.d.extra=12
        self.assertFalse(self.store.validate(self.record))

    def test_native_harness_refuses_primary_profile_and_existing_archive(self):
        g=self.boot()
        self.lua.execute("""
          started=false; core_modmanager={isReady=function() return true end}
          freeroam_freeroam={startFreeroam=function() started=true end}
          FS.getUserPath=function() return 'C:/BeamNG/normal/current/' end
        """)
        source=(ROOT/'tests/beamng-laprecords/lua/ge/extensions/acng/laparchive.lua').read_text(encoding='utf-8')
        harness=self.lua.execute(source);harness.onUpdate(11,11)
        self.assertFalse(g.started)
        result=json.loads(self.files['/acng-lap-records-test.json'])
        self.assertFalse(result['completed']);self.assertIn('Dedicated',result['failure'])
        self.lua.execute("FS.getUserPath=function() return 'C:/ACNG-laprecords-test/current/' end")
        self.files['/settings/acng/lap-records.json']='existing'
        harness=self.lua.execute(source);harness.onUpdate(11,11)
        self.assertFalse(g.started)
        self.assertIn('Fresh',json.loads(self.files['/acng-lap-records-test.json'])['failure'])

    def test_completed_lap_is_saved_automatically(self):
        g=self.boot()
        self.lua.execute("""
          px,py=50,-1
          obj={getID=function() return 42 end,getPosition=function() return {x=px,y=py,z=0} end,
            getDirectionVector=function() return {x=0,y=1,z=0} end,
            queueGameEngineLua=function(_,code) assert(loadstring(code))() end}
          car.queueLuaCommand=function(_,code) assert(loadstring(code))() end
        """)
        laps=self.lua.execute(LAPS.read_text());g.extensions.acng_laps=laps
        laps.onExtensionLoaded();g.py=0;laps.setLineHere()
        arc=-1
        for _ in range(1100):
            arc+=20/60;g.px=50*math.cos(arc/50);g.py=50*math.sin(arc/50);laps.updateGFX(1/60)
        self.assertEqual(laps.getSnapshot().laps,1)
        saved=json.loads(self.files['/settings/acng/lap-records.json'])['records'][0]['value']
        self.assertAlmostEqual(saved['best']['time_s'],2*math.pi*50/20,places=4)
        self.assertEqual(saved['best_trace']['d'][0],0)
        self.assertEqual(len(saved['best_sectors']),3)

    def test_readback_mismatch_does_not_claim_saved(self):
        g=self.boot();self.store.request(42,'one')
        g.jsonReadFile=lambda path:self.lua.eval('{schema_version=1,records={}}')
        self.assertFalse(self.save());self.assertIn('not_saved',g.reply)

    def test_vehicle_reload_and_clear_without_physics_writes(self):
        g=self.boot();self.store.request(42,'one');self.save()
        self.lua.execute("""
          obj={getID=function() return 42 end,getPosition=function() return {x=50,y=-1,z=0} end,
            getDirectionVector=function() return {x=0,y=1,z=0} end,
            queueGameEngineLua=function(_,code) assert(loadstring(code))() end}
          car.queueLuaCommand=function(_,code) assert(loadstring(code))() end
        """)
        laps=self.lua.execute(LAPS.read_text());g.extensions.acng_laps=laps
        laps.onExtensionLoaded()
        self.assertEqual(laps.getSnapshot().mode,'out_lap')
        self.assertEqual(laps.getSnapshot().best.time_s,10)
        self.assertEqual(laps.getSnapshot().archive_status,'loaded')
        self.assertEqual(laps.getSnapshot().laps,0)
        self.assertIsNone(laps.getSnapshot().last)
        self.assertFalse(laps.receiveArchive('stale','null','saved'))
        laps.clear();self.assertIsNone(laps.getSnapshot().best)
        laps=self.lua.execute(LAPS.read_text());g.extensions.acng_laps=laps; laps.onExtensionLoaded()
        self.assertEqual(laps.getSnapshot().mode,'out_lap');self.assertIsNone(laps.getSnapshot().best)
        for source in (STORE.read_text(),LAPS.read_text()):
            for forbidden in ('input.event','applyForce','setFriction','requestReset'):
                self.assertNotIn(forbidden,source)

if __name__=='__main__': unittest.main()
