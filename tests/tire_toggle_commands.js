// Capture commands emitted by the actual Angular click handler.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
let factory;const commands=[];
const scope={$on:()=>{},$evalAsync:fn=>fn()};
function interval(){} interval.cancel=()=>{};
vm.runInNewContext(fs.readFileSync('beamng-mod/ui/modules/apps/ACNGTires/app.js','utf8'),{
 angular:{module:()=>({directive:(_,a)=>factory=a[a.length-1]})},
 bngApi:{engineLua:(code,cb)=>{if(code.includes('setFeature'))commands.push(code);if(cb)cb({enabled:false,features:{}});}},Date,Number,Math,Array});
factory(interval).link(scope);
for(const [name,on] of [['tire_temperature',false],['tire_wear',false],['tire_temperature',true],['tire_wear',true]]){
 scope.tires.heat=name==='tire_temperature'&&on;scope.tires.wear=name==='tire_wear'&&on;scope.tires.toggle(name);
}
assert.equal(commands.length,4);process.stdout.write(JSON.stringify(commands));
