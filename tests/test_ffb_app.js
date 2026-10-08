// Contract tests for the ACNG FFB app view (no BeamNG needed): node tests/test_ffb_app.js
const assert = require('assert');
const view = require('../beamng-mod/ui/modules/apps/ACNGFFB/app.js');

const settings = {gain: 1, car_gain: 1, min_force: 0, filter: null, kerb: 0.3, road: 0.5, slip: 0.3, car_model: 'etk800'};
assert.strictEqual(view(null, null).available, false);
let v = view({enabled: false, features: {ffb: true}, ffb_settings: settings}, null);
assert.strictEqual(v.on, false);                              // master OFF = off
assert.strictEqual(v.note, 'Off: BeamNG force feedback exactly as set in Options');
assert.deepStrictEqual(v.rows.map(r => r.label), ['GAIN', 'CAR', 'MIN FORCE', 'FILTER', 'KERB', 'ROAD', 'SLIP']);
assert.deepStrictEqual(v.rows.map(r => r.text), ['100%', '100%', '0%', 'STOCK', '30%', '50%', '30%']);
const filter = v.rows[3];
assert.strictEqual(filter.canStock, false);
assert.strictEqual(filter.canDown, false);
assert.strictEqual(filter.canUp, true);
assert.strictEqual(v.rows[2].canDown, false);                 // min force already 0
assert.strictEqual(v.car, 'etk800');

const on = {enabled: true, features: {ffb: true}, ffb_settings: settings};
v = view(on, null);
assert.strictEqual(v.on, true);
assert.strictEqual(v.note, 'Starting...');
v = view(on, {mode: 'on', wheel: false, force: 0, limit: 1});
assert.strictEqual(v.note, 'No FFB wheel detected: settings apply when one is bound');
v = view(on, {mode: 'on', wheel: true, force: -0.5, limit: 1, clip: 0.01, hook: 'acng'});
assert.strictEqual(v.meter.fill, 50);
assert.strictEqual(v.meter.clipping, false);
assert.strictEqual(v.note, 'Clipping 1%');
v = view(on, {mode: 'on', wheel: true, force: 1, limit: 1, clip: 0.2, hook: 'acng'});
assert.strictEqual(v.meter.fill, 100);
assert.strictEqual(v.note, 'Clipping 20% of the time: lower GAIN or CAR');
v = view(on, {mode: 'on', wheel: true, force: 0, limit: 1, clip: 0, hook: 'busy'});
assert.strictEqual(v.note, 'Another tool is using the FFB hook: min force and effects are off');
v = view(on, {mode: 'off'});
assert.strictEqual(v.meter, null);

// Steps snap, clamp and stop at the ends.
const rows = {};
view.ROWS.forEach(r => { rows[r.key] = r; });
assert.strictEqual(view.stepValue(rows.gain, 1, 1), 1.05);
assert.strictEqual(view.stepValue(rows.gain, 2, 1), null);
assert.strictEqual(view.stepValue(rows.min_force, 0.29, 1), 0.3);
assert.strictEqual(view.stepValue(rows.filter, null, 1), 0.5);  // first press from STOCK
assert.strictEqual(view.stepValue(rows.filter, null, -1), null);
assert.strictEqual(view.stepValue(rows.filter, 0.5, -1), 0.4);
assert.strictEqual(view.stepValue(rows.kerb, 0.3, -1), 0.2);

// Commands are single Lua expressions.
assert.strictEqual(view.command('on', on), "(function() extensions.acng_core.setEnabled(true); return extensions.acng_core.setFeature('ffb', true) end)()");
assert.strictEqual(view.command('off', on), "extensions.acng_core.setFeature('ffb', false)");
assert.strictEqual(view.command('step', on, 'gain', 1), "extensions.acng_core.setFFBSetting('gain', 1.05)");
assert.strictEqual(view.command('step', on, 'car_gain', -1), 'extensions.acng_core.setCarGain(nil, 0.95)');
assert.strictEqual(view.command('step', on, 'filter', 1), "extensions.acng_core.setFFBSetting('filter', 0.5)");
assert.strictEqual(view.command('stock', on, 'filter'), "extensions.acng_core.setFFBSetting('filter', false)");
assert.strictEqual(view.command('stock', on, 'gain'), null);
assert.strictEqual(view.command('step', on, 'min_force', -1), null);
assert.strictEqual(view.command('step', on, 'nonsense', 1), null);
assert.strictEqual(view.command('step', on, 'gain', 2), null);
console.log('test_ffb_app: all passed');
