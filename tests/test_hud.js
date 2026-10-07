const assert=require('node:assert/strict');
const model=require('../beamng-mod/ui/modules/apps/ACNGRacingHUD/app.js');
let m=model({electrics:{wheelspeed:26.8224,gear:'R',throttle:2,brake:-1},engineInfo:[0,7000,0,0,6800]},false);
assert.equal(m.speed,60);assert.equal(m.gear,'R');assert.equal(m.shift,true);assert.equal(m.pedals[0].percent,100);assert.equal(m.pedals[1].percent,0);assert.equal(m.pedals[2].value,null);
m=model({},true);assert.equal(m.speed,'\u2014');assert.equal(m.ratio,null);assert.equal(m.gear,'\u2014');assert.equal(m.shift,false);
m=model({electrics:{wheelspeed:10,gear:'N',brake:NaN},engineInfo:[0,0,0,0,500]},true);assert.equal(m.speed,36);assert.equal(m.ratio,null);assert.equal(m.pedals[1].value,null);
console.log('HUD data checks passed: unit conversion, reverse/neutral, missing data, invalid limits and pedal clamping.');

assert.equal(model({electrics:{gear:-1}},false).gear,'R');assert.equal(model({electrics:{gear:0}},false).gear,'N');

// Exercise the real directive callbacks with a deterministic engine bridge.
const vm=require('node:vm'),fs=require('node:fs');let factory,enabled=false,removed=false,cancelled=false;
const events={},scope={$on:(name,fn)=>events[name]=fn,$evalAsync:fn=>fn(),$watch:(_,fn)=>fn()};
function interval(){return 1;}interval.cancel=()=>cancelled=true;
vm.runInNewContext(fs.readFileSync(require.resolve('../beamng-mod/ui/modules/apps/ACNGRacingHUD/app.js'),'utf8'),{
 angular:{module:()=>({directive:(_,arr)=>factory=arr[arr.length-1]})},
 StreamsManager:{add:()=>{},remove:()=>removed=true},
 bngApi:{engineLua:(code,callback)=>{if(code.includes('setEnabled'))enabled=code.includes('(true)');callback({enabled});}},
 Date,Number,Math
});
factory(interval).link(scope);assert.equal(scope.hud.enabled,false);scope.hud.toggle();assert.equal(scope.hud.enabled,true);
events.streamsUpdate(null,{electrics:{wheelspeed:26.8224,gear:2,brake:.7},engineInfo:[0,7000,0,0,3000]});
assert.equal(scope.hud.data.speed,60);assert.equal(scope.hud.data.pedals[1].percent,70);
scope.hud.toggle();assert.equal(scope.hud.enabled,false);events.$destroy();assert.equal(removed,true);assert.equal(cancelled,true);
console.log('HUD bridge checks passed: master off/on/off, native stream update and cleanup. Actual mouse click still needs runtime confirmation.');
