const c=require('../beamng-mod/ui/modules/apps/ACNGControl/app.js'),assert=require('assert');
const s={enabled:true,features:{tire_temperature:true},ffb_settings:{car_model:'etkc'}};
assert(c.view(s).on);assert.equal(c.view(null).available,false);assert.equal(c.command('feature',s,'notreal',true),null);
assert.equal(c.command('assist',s,'abs',4),null);assert.equal(c.command('ffb',s,'min_force',31),null);
assert.equal(c.command('telemetry',{enabled:false},null,true),null);
assert.equal(c.command('profile',s,null,'invalid'),null);
assert.equal(c.command('profile',s,null,'road'),"extensions.acng_core.setTireProfile('road')");
const commands=[c.command('master',s),c.command('master',{enabled:false}),c.command('feature',s,'tire_wear',false),c.command('assist',s,'abs','0'),c.command('assist',s,'tc','factory'),c.command('ffb',s,'gain',125),c.command('ffb',s,'filter','stock'),c.command('ffb',s,'road',0),c.command('telemetry',s,null,false)];
process.stdout.write(JSON.stringify(commands));
