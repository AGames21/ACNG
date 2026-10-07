const assert=require('node:assert/strict');
const view=require('../beamng-mod/ui/modules/apps/ACNGTires/app.js');
const D='\u2014', DEG='\u00b0';
let v=view(null);
assert.equal(v.on,false);assert.deepEqual(v.tires,[]);assert.equal(v.window,'');
assert.equal(view({mode:'off'}).on,false);
// Tires arrive in vehicle order; the app shows front row first, left before right.
const snap={mode:'on',window_low_c:75,window_high_c:105,tires:[
 {name:'RR',surface_c:40.4,core_c:20,psi:27.06,state:'cold',grip:0.934},
 {name:'FL',surface_c:90,core_c:60.6,psi:29,state:'window',grip:1},
 {name:'FR',surface_c:130,core_c:80,psi:31,state:'hot',grip:0.9},
 {name:'RL',surface_c:null,core_c:NaN,state:'melted'}]};
v=view(snap);
assert.equal(v.on,true);
assert.equal(v.window,'Grip window 75\u2013105'+DEG+'C');
assert.deepEqual(v.tires.map(t=>t.name),['FL','FR','RL','RR']);
assert.deepEqual(v.tires.map(t=>t.surface),['90'+DEG,'130'+DEG,D,'40'+DEG]);
assert.deepEqual(v.tires.map(t=>t.core),['61'+DEG,'80'+DEG,D,'20'+DEG]);
assert.deepEqual(v.tires.map(t=>t.psi),['29.0','31.0',D,'27.1']);
assert.deepEqual(v.tires.map(t=>t.state),['window','hot','','cold']);  // unknown states are dropped
assert.deepEqual(v.tires.map(t=>t.grip),['100%','90%',D,'93%']);
// Colours: blue cold, green in the window, amber then red when hot, grey without data.
const c=view.tempColor;
assert.equal(c(-10,75,105),'rgb(70,140,255)');
assert.equal(c(90,75,105),'rgb(80,220,130)');
assert.equal(c(75,75,105),'rgb(80,220,130)');
assert.equal(c(120,75,105),'rgb(250,200,80)');
assert.equal(c(200,75,105),'rgb(255,80,70)');
assert.equal(c(null,75,105),'#3a414c');
assert.equal(view({mode:'on',tires:[{name:'FL',surface_c:90}]}).tires[0].color,'#3a414c');  // no window known
// Lua tables that arrive as keyed objects instead of arrays; more than four wheels.
v=view({mode:'on',window_low_c:75,window_high_c:105,tires:{1:{name:'RR1',surface_c:80},2:{name:'FR',surface_c:80},3:{name:'RL1',surface_c:80},4:{name:'FL',surface_c:80},5:{name:'XX',surface_c:80}}});
assert.deepEqual(v.tires.map(t=>t.name),['FL','FR','RL1','RR1','XX']);
// Wear: tread %, bar width and colour; the header line names wear and a non-default rate.
v=view({mode:'on',heat:true,wear:true,wear_rate:1,window_low_c:75,window_high_c:105,tires:[
 {name:'FL',surface_c:90,tread:0.873},{name:'FR',surface_c:90,tread:1.2},{name:'RL',surface_c:90,tread:-0.1},{name:'RR',surface_c:90}]});
assert.equal(v.wear,true);
assert.deepEqual(v.tires.map(t=>t.tread),['87%','100%','0%',D]);
assert.deepEqual(v.tires.map(t=>t.treadWidth),['87.3%','100.0%','0.0%','0%']);
assert.equal(v.window,'Grip window 75\u2013105'+DEG+'C \u00b7 Wear on');
assert.equal(view.treadColor(1),'rgb(80,220,130)');
assert.equal(view.treadColor(0.5),'rgb(250,200,80)');
assert.equal(view.treadColor(0),'rgb(255,80,70)');
assert.equal(view.treadColor(null),'#3a414c');
// Wear without heat: no window, wear rate shown when not 1.
v=view({mode:'on',heat:false,wear:true,wear_rate:10,tires:[{name:'FL',surface_c:15,tread:0.5}]});
assert.equal(v.window,'Wear x10');
assert.equal(view({mode:'on',wear:true,wear_rate:11.27,tires:[]}).window,'Wear x11.3');
assert.equal(v.tires[0].color,'#3a414c');
assert.equal(view({mode:'on',wear:false,window_low_c:75,window_high_c:105,tires:[]}).wear,false);
assert.equal(view({mode:'off',wear:true}).wear,false);
console.log('Tire view checks passed: idle/off, front-first order, rounding, unknown states, grip %, temperature colours, missing data, object tables, extra wheels, tread and wear line.');
