// Contract tests for the ACNG Assists app view (no BeamNG needed): node tests/test_assists_app.js
const assert = require('assert');
const view = require('../beamng-mod/ui/modules/apps/ACNGAssists/app.js');

const off = view({enabled: false, features: {abs: true, tc: true}, assist_levels: {abs: 3, tc: 1}}, null);
assert.strictEqual(off.available, true);
assert.deepStrictEqual(off.rows.map(r => r.choice), ['factory', 'factory']);  // master OFF = factory
assert.deepStrictEqual(off.rows[0].buttons.map(b => b.text), ['FACTORY', 'OFF', '1', '2', '3']);
assert.strictEqual(off.rows[0].note, "Car's own ABS");
assert.strictEqual(off.rows[1].note, "Car's own TC");
assert.strictEqual(view(null, null).available, false);

const status = {enabled: true, features: {abs: true, tc: true}, assist_levels: {abs: 1, tc: 0}};
let v = view(status, {mode: 'on', abs_slip: 0.25, abs_setting: 'realistic', abs_active: true, tc_mode: 'cmu', tc_active: true});
assert.deepStrictEqual(v.rows.map(r => r.choice), [1, 0]);
assert.deepStrictEqual(v.rows[0].buttons.filter(b => b.on).map(b => b.text), ['1']);
assert.strictEqual(v.rows[0].note, 'Slip target 25%');
assert.strictEqual(v.rows[0].active, true);
assert.strictEqual(v.rows[1].note, 'TC off: wheels can spin');

v = view({enabled: true, features: {abs: false, tc: true}, assist_levels: {tc: 3}},
  {mode: 'on', tc_mode: 'acng', tc_slip: 0.08, tc_factor: 0.4, tc_active: true, abs_active: true});
assert.strictEqual(v.rows[0].choice, 'factory');
assert.strictEqual(v.rows[0].active, false);            // factory never lights
assert.strictEqual(v.rows[1].note, 'ACNG TC (car has none) · slip 8% · power 40%');
v = view({enabled: true, features: {tc: true}, assist_levels: {tc: 2}}, {mode: 'on', tc_mode: 'acng', tc_slip: 0.15, tc_factor: 1});
assert.strictEqual(v.rows[1].note, 'ACNG TC (car has none) · slip 15%');
v = view({enabled: true, features: {tc: true}, assist_levels: {tc: 2}}, {mode: 'on', tc_mode: 'cmu', tc_slip: 0.15});
assert.strictEqual(v.rows[1].note, 'Native TC · slip 15%');
v = view({enabled: true, features: {tc: true}, assist_levels: {tc: 2}}, {mode: 'on', tc_mode: 'none'});
assert.strictEqual(v.rows[1].note, "This car's ESC is not changed");

// The game's own ABS setting overrides the levels.
v = view({enabled: true, features: {abs: true}, assist_levels: {abs: 2}}, {mode: 'on', abs_setting: 'off'});
assert.strictEqual(v.rows[0].note, 'Game ABS setting is Off; set it to Realistic');
v = view({enabled: true, features: {abs: true}, assist_levels: {abs: 0}}, {mode: 'on', abs_setting: 'arcade'});
assert.strictEqual(v.rows[0].note, 'Game ABS setting is Arcade; ABS stays on');

// A snapshot that is not 'on' is ignored; a missing or bad level shows 2.
v = view({enabled: true, features: {abs: true}, assist_levels: {abs: 7}}, {mode: 'off', abs_active: true});
assert.strictEqual(v.rows[0].choice, 2);
assert.strictEqual(v.rows[0].active, false);
assert.strictEqual(v.rows[0].note, 'Slip target —');

// Commands.
assert.strictEqual(view.command('abs', 'factory'), "extensions.acng_core.setFeature('abs', false)");
assert.strictEqual(view.command('tc', 3), "(function() extensions.acng_core.setEnabled(true); extensions.acng_core.setAssistLevel('tc', 3); return extensions.acng_core.setFeature('tc', true) end)()");
assert.strictEqual(view.command('tc', 0), "(function() extensions.acng_core.setEnabled(true); extensions.acng_core.setAssistLevel('tc', 0); return extensions.acng_core.setFeature('tc', true) end)()");
for (const bad of [['ffb', 1], ['abs', 4], ['abs', '2'], ['tc', 1.5], ['abs', null]]) assert.strictEqual(view.command(bad[0], bad[1]), null);
console.log('test_assists_app: all passed');
