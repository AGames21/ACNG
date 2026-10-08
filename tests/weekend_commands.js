const fs=require('fs'),vm=require('vm'),path=require('path');
let factory,scope,commands=[];
const interval=()=>1;interval.cancel=()=>{};
const context={angular:{module:()=>({directive:(name,arr)=>{factory=arr[arr.length-1];}})},
  bngApi:{engineLua:(code,cb)=>{commands.push(code);if(cb)cb({phase:'off',standings:[]});}}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../beamng-mod/ui/modules/apps/ACNGWeekend/app.js'),'utf8'),context);
scope={$on:()=>{},$evalAsync:fn=>fn()};factory(interval).link(scope);commands=[];
for(const action of ['prepare','practice','qualifying','race','endSession','cancel'])scope.act(action);
process.stdout.write(JSON.stringify(commands));
