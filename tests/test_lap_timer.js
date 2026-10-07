const assert=require('node:assert/strict');
const view=require('../beamng-mod/ui/modules/apps/ACNGLapTimer/app.js');
const D='—';
let v=view(null);
assert.equal(v.mode,null);assert.equal(v.status,'Waiting for vehicle timer…');assert.equal(v.current,D);
assert.deepEqual(v.sectors.map(s=>s.text),[D,D,D]);
assert.equal(view({mode:'no_line'}).status,'Drive to your start/finish line and press SET LINE');
assert.equal(view({mode:'out_lap'}).status,'Out lap — cross the line to start timing');
assert.match(view({mode:'out_lap',note:'reset'}).status,/^Reset/);
assert.match(view({mode:'out_lap',note:'reversed'}).status,/backwards/);
// Mid-lap: sector 1 done and faster than best (purple), others show last lap dimmed.
const snap={mode:'lap',lap_number:4,current_s:65.4321,delta_s:-0.1234,sectors_live:[20.1],laps:3,ref_length_m:1200,
 last:{lap:3,time_s:62.5,sectors:[20.5,21,21]},best:{lap:2,time_s:61.987},best_sectors:[20.2,20.8,20.9],optimal_s:61.9};
v=view(snap);
assert.equal(v.status,'LAP 4');assert.equal(v.timing,true);
assert.equal(v.current,'1:05.432');assert.deepEqual(v.delta,{text:'−0.123',cls:'ahead'});
assert.deepEqual(v.sectors.map(s=>s.text),['20.100','21.000','21.000']);
assert.deepEqual(v.sectors.map(s=>s.cls),['best','prev','prev']);
assert.equal(v.last,'1:02.500');assert.equal(v.best,'1:01.987');assert.equal(v.optimal,'1:01.900');assert.equal(v.laps,3);
v=view(Object.assign({},snap,{delta_s:0.25,sectors_live:[20.1,21.5]}));
assert.deepEqual(v.delta,{text:'+0.250',cls:'behind'});assert.deepEqual(v.sectors.map(s=>s.cls),['best','slower','prev']);
assert.equal(view(Object.assign({},snap,{delta_s:0.0004})).delta.text,'±0.000');
// Lua tables that arrive as keyed objects instead of arrays.
v=view({mode:'out_lap',last:{time_s:9.5,sectors:{1:3,2:3.2,3:3.3}},best_sectors:{1:3,2:3,3:3}});
assert.equal(v.current,'0:09.500');assert.deepEqual(v.sectors.map(s=>s.text),['3.000','3.200','3.300']);
assert.deepEqual(v.sectors.map(s=>s.cls),['prev','prev','prev']);assert.equal(v.delta.text,'');
v=view({mode:'lap',current_s:NaN,delta_s:Infinity,sectors_live:[null]});
assert.equal(v.current,D);assert.equal(v.delta.text,D);assert.equal(v.sectors[0].text,D);
console.log('Lap view checks passed: idle/status notes, m:ss.mmm, delta sign/colour, live vs previous sectors, best/slower, array or object tables, invalid numbers.');

const vm=require('node:vm'),fs=require('node:fs');let factory,enabled=false,cancelled=false;const lua=[],objLua=[];
const events={},scope={$on:(name,fn)=>events[name]=fn,$evalAsync:fn=>fn(),$watch:()=>{}};
let tick;function interval(fn){tick=fn;return 1;}interval.cancel=()=>cancelled=true;
vm.runInNewContext(fs.readFileSync(require.resolve('../beamng-mod/ui/modules/apps/ACNGLapTimer/app.js'),'utf8'),{
 angular:{module:()=>({directive:(_,arr)=>factory=arr[arr.length-1]})},
 bngApi:{engineLua:(code,cb)=>{lua.push(code);if(code.includes('setEnabled'))enabled=code.includes('(true)');if(cb)cb({enabled});},activeObjectLua:code=>objLua.push(code)},
 Date,Number,Math,Array
});
const directive=factory(interval);directive.link(scope);const l=scope.laps;
assert.equal(l.available,true);assert.equal(l.enabled,false);
l.toggle();assert.equal(enabled,true);assert.equal(l.enabled,true);
events.ACNGLaps({},snap);assert.equal(l.view.current,'1:05.432');
l.setLine();assert.equal(objLua[0],"if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.setLineHere() end");
l.clear();assert.equal(objLua[1],"if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps.clear() end");
events.ACNGLaps({},{schema_version:1,mode:'off'});assert.equal(l.view.mode,null);
const t0=Date.now;events.ACNGLaps({},snap);Date.now=()=>t0()+5000;tick();assert.equal(l.view.mode,null);Date.now=t0;
l.toggle();assert.equal(enabled,false);
events.$destroy();assert.equal(cancelled,true);
console.log('Lap bridge checks passed: master toggle, stream event, SET LINE/CLEAR commands, unload, stale clear and cleanup. Actual mouse click still needs runtime confirmation.');
