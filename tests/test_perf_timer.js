const assert=require('node:assert/strict');
const view=require('../beamng-mod/ui/modules/apps/ACNGPerfTimer/app.js');
const D='\u2014';
let v=view(null,false);
assert.equal(v.mode,null);assert.equal(v.status,'Waiting for vehicle timer\u2026');assert.deepEqual(v.rows.map(r=>r.last),[D,D,D,D]);
const snap={mode:'launch',run_id:3,run_time_s:4.27,run_distance_m:61,
 last:{mph_0_60:{time_s:3.912,run_id:3},kmh_0_100:{time_s:4.1,run_id:2},quarter_mile:{time_s:11.876,trap_speed_m_s:53.6448,run_id:3},
       mph_60_0:{distance_m:33.53,time_s:2.9},kmh_100_0:{distance_m:38.04,time_s:3.1}},
 best:{mph_0_60:{time_s:3.85},quarter_mile:{time_s:11.8,trap_speed_m_s:54},mph_60_0:{distance_m:32}}};
v=view(snap,false);
assert.deepEqual(v.rows.map(r=>r.label),['0\u201360 mph','0\u2013100 mph','1/4 mile','60\u20130 mph']);
assert.deepEqual(v.rows.map(r=>r.last),['3.91 s',D,'11.88 s @ 120','110 ft']);
assert.deepEqual(v.rows.map(r=>r.best),['3.85 s',D,'11.80 s @ 121','105 ft']);
assert.deepEqual(v.rows.map(r=>r.fresh),[true,false,true,false]);
assert.equal(v.status,'TIMING 4.3 s \u00b7 200 ft');assert.equal(v.timing,true);
v=view(snap,true);
assert.deepEqual(v.rows.map(r=>r.key),['kmh_0_100','kmh_0_200','quarter_mile','kmh_100_0']);
assert.deepEqual(v.rows.map(r=>r.last),['4.10 s',D,'11.88 s @ 193','38.0 m']);
assert.equal(v.rows[0].fresh,false);assert.equal(v.status,'TIMING 4.3 s \u00b7 61 m');
assert.equal(view({mode:'armed'},false).status,'READY \u2014 launch from a stop');
assert.equal(view({mode:'rolling'},true).status,'ROLLING \u2014 stop to arm a launch');
v=view({mode:'rolling',run_id:3,last:{mph_0_60:{time_s:NaN,run_id:3},mph_60_0:{distance_m:Infinity}}},false);
assert.equal(v.rows[0].last,D);assert.equal(v.rows[0].fresh,false);assert.equal(v.rows[3].last,D);
console.log('Timer view checks passed: idle, mph/km/h rows, trap speed, distance units, fresh highlight, status text, invalid numbers.');

// Exercise the real directive callbacks with a deterministic engine bridge.
const vm=require('node:vm'),fs=require('node:fs');let factory,enabled=false,cancelled=false;const lua=[],objLua=[];
const events={},watchers=[],scope={$on:(name,fn)=>events[name]=fn,$evalAsync:fn=>fn(),$watch:(_,fn)=>{watchers.push(fn);fn();}};
let tick;function interval(fn){tick=fn;return 1;}interval.cancel=()=>cancelled=true;
vm.runInNewContext(fs.readFileSync(require.resolve('../beamng-mod/ui/modules/apps/ACNGPerfTimer/app.js'),'utf8'),{
 angular:{module:()=>({directive:(_,arr)=>factory=arr[arr.length-1]})},
 bngApi:{engineLua:(code,cb)=>{lua.push(code);if(code.includes('setEnabled'))enabled=code.includes('(true)');if(cb)cb({enabled});},activeObjectLua:code=>objLua.push(code)},
 Date,Number,Math
});
const directive=factory(interval);directive.link(scope);const t=scope.timer;
assert.equal(t.available,true);assert.equal(t.enabled,false);
t.toggle();assert.equal(enabled,true);assert.equal(t.enabled,true);
events.ACNGPerf({}, snap);assert.equal(t.view.rows[0].last,'3.91 s');
t.metric=true;watchers.forEach(fn=>fn());assert.equal(t.view.rows[3].last,'38.0 m');
t.clear();assert.match(objLua[0],/isExtensionLoaded\('acng_perf'\) then extensions\.acng_perf\.clear\(\)/);
events.ACNGPerf({}, {schema_version:1,mode:'off'});assert.equal(t.view.mode,null);
t.toggle();assert.equal(enabled,false);
events.$destroy();assert.equal(cancelled,true);
console.log('Timer bridge checks passed: master toggle, stream event, unit switch, reset command, unload and cleanup. Actual mouse click still needs runtime confirmation.');
