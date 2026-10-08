/* Original ACNG force feedback app: AC-style gain, minimum force, filter, kerb/road/slip feel and per-car strength, with a live clipping meter. */
(function () {
  'use strict';
  // key: label, step, min, max, how the value is shown.
  var ROWS = [
    {key: 'gain', label: 'GAIN', step: 0.05, min: 0, max: 2, fmt: 'pct'},
    {key: 'car_gain', label: 'CAR', step: 0.05, min: 0, max: 2, fmt: 'pct'},
    {key: 'min_force', label: 'MIN FORCE', step: 0.01, min: 0, max: 0.3, fmt: 'pct'},
    {key: 'filter', label: 'FILTER', step: 0.1, min: 0, max: 1, fmt: 'pct', stock: true},
    {key: 'kerb', label: 'KERB', step: 0.1, min: 0, max: 2, fmt: 'pct'},
    {key: 'road', label: 'ROAD', step: 0.1, min: 0, max: 2, fmt: 'pct'},
    {key: 'slip', label: 'SLIP', step: 0.1, min: 0, max: 2, fmt: 'pct'}];
  // BeamNG's default smoothing (150) is filter 0.5; the first press from STOCK starts there.
  var FILTER_START = 0.5;
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function pct(value) { var v = number(value); return v === null ? '' : Math.round(v * 100) + '%'; }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
  function snap(v, step) { return Math.round(v / step) * step; }
  function tidy(v) { return Math.round(v * 1000) / 1000; }
  function isOn(status) { var s = status || {}; return !!(s.enabled && s.features && s.features.ffb === true); }
  function settingsOf(status) { return (status && status.ffb_settings) || {}; }
  // The next value for a row after a minus (-1) or plus (+1) press; null when it would not change.
  function stepValue(row, current, dir) {
    var v = number(current);
    if (row.stock && v === null) return dir > 0 ? FILTER_START : null;
    if (v === null) v = 0;
    var next = tidy(clamp(snap(v + dir * row.step, row.step), row.min, row.max));
    return next === tidy(v) ? null : next;
  }
  function meter(snapshot) {
    var s = snapshot && snapshot.mode === 'on' ? snapshot : null;
    if (!s) return null;
    var limit = number(s.limit), force = number(s.force);
    var fill = limit && limit > 0 && force !== null ? clamp(Math.abs(force) / limit, 0, 1) : 0;
    var clip = number(s.clip) || 0;
    return {wheel: s.wheel === true, fill: Math.round(fill * 100), clip: Math.round(clip * 100),
      clipping: clip >= 0.05, hook: s.hook, kerb: s.kerb_on === true, slip: number(s.front_slip)};
  }
  function note(status, m) {
    if (!isOn(status)) return 'Off: BeamNG force feedback exactly as set in Options';
    if (!m) return 'Starting...';
    if (!m.wheel) return 'No FFB wheel detected: settings apply when one is bound';
    if (m.hook === 'busy') return 'Another tool is using the FFB hook: min force and effects are off';
    if (m.clipping) return 'Clipping ' + m.clip + '% of the time: lower GAIN or CAR';
    return 'Clipping ' + m.clip + '%';
  }
  function view(status, snapshot) {
    var on = isOn(status), s = settingsOf(status), m = on ? meter(snapshot) : null;
    var rows = ROWS.map(function (r) {
      var value = s[r.key];
      return {key: r.key, label: r.label, text: r.stock && number(value) === null ? 'STOCK' : pct(value),
        stock: !!r.stock, canStock: !!r.stock && number(value) !== null,
        canDown: stepValue(r, value, -1) !== null, canUp: stepValue(r, value, 1) !== null};
    });
    return {available: !!status, on: on, rows: rows, meter: m, note: note(status, m),
      car: s.car_model || ''};
  }
  // GE Lua for a press. engineLua with a callback wraps the code as guihooks.trigger(...,
  // <code>), so it must be one expression: several statements go in a called function.
  function command(action, status, key, dir) {
    if (action === 'on') return "(function() extensions.acng_core.setEnabled(true); return extensions.acng_core.setFeature('ffb', true) end)()";
    if (action === 'off') return "extensions.acng_core.setFeature('ffb', false)";
    var row = null;
    ROWS.forEach(function (r) { if (r.key === key) row = r; });
    if (!row) return null;
    if (action === 'stock') return row.stock ? "extensions.acng_core.setFFBSetting('filter', false)" : null;
    if (action !== 'step' || (dir !== 1 && dir !== -1)) return null;
    var next = stepValue(row, settingsOf(status)[key], dir);
    if (next === null) return null;
    if (key === 'car_gain') return 'extensions.acng_core.setCarGain(nil, ' + next + ')';
    return "extensions.acng_core.setFFBSetting('" + key + "', " + next + ')';
  }
  view.command = command;
  view.stepValue = stepValue;
  view.ROWS = ROWS;
  if (typeof module !== 'undefined' && module.exports) module.exports = view;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngFfb', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-ffb">
        <style>
          .acng-ffb{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #6fb0ff;border-radius:12px;padding:10px 14px;box-shadow:0 8px 26px #0006;user-select:none}
          .acng-ffb *{box-sizing:border-box}.acng-ffb header{display:flex;align-items:center;justify-content:space-between;height:24px}
          .acng-ffb .brand{font-weight:800;letter-spacing:3px}.acng-ffb .brand small{font-weight:600;letter-spacing:1.5px;color:#9ca7b8;margin-left:6px}
          .acng-ffb button{font:600 10px 'Segoe UI',sans-serif;letter-spacing:.6px;border:1px solid #58606c;border-radius:5px;padding:3px 8px;color:#cad0da;background:#252c36;cursor:pointer}
          .acng-ffb button[disabled]{opacity:.35;cursor:default}.acng-ffb button.on{color:#0d1118;background:#8ceac7;border-color:#8ceac7}
          .acng-ffb .row{display:grid;grid-template-columns:76px 26px 1fr 26px 44px;gap:5px;align-items:center;margin-top:5px}
          .acng-ffb .name{font-weight:700;letter-spacing:1px;font-size:11px;color:#c7cfdb}.acng-ffb .val{text-align:center;font-weight:700;font-variant-numeric:tabular-nums}
          .acng-ffb .row button{padding:2px 0}
          .acng-ffb .bar{position:relative;height:10px;border-radius:5px;background:#252c36;margin-top:9px;overflow:hidden}
          .acng-ffb .fill{position:absolute;left:0;top:0;bottom:0;background:#6fb0ff}.acng-ffb .fill.clip{background:#ff6b5a}
          .acng-ffb .note{font-size:10.5px;color:#9ca7b8;letter-spacing:.3px;margin-top:5px}
          .acng-ffb .idle{color:#aeb8c6;text-align:center;padding:30px 12px}
        </style>
        <header><span class="brand">ACNG<small>FFB</small></span>
          <span ng-if="ffb.view.available"><button ng-class="{on:ffb.view.on}" ng-click="ffb.press(ffb.view.on?'off':'on')" aria-label="FFB {{ffb.view.on?'OFF':'ON'}}">{{ffb.view.on?'ON':'OFF'}}</button></span></header>
        <div ng-if="!ffb.view.available" class="idle">Waiting for ACNG...</div>
        <div ng-if="ffb.view.available">
          <div class="row" ng-repeat="r in ffb.view.rows track by r.key">
            <span class="name">{{r.label}}</span>
            <button ng-disabled="!r.canDown" ng-click="ffb.press('step',r.key,-1)" aria-label="{{r.label}} down">&minus;</button>
            <span class="val">{{r.text}}</span>
            <button ng-disabled="!r.canUp" ng-click="ffb.press('step',r.key,1)" aria-label="{{r.label}} up">+</button>
            <button ng-if="r.stock" ng-disabled="!r.canStock" ng-click="ffb.press('stock',r.key)" aria-label="{{r.label}} stock">STOCK</button>
            <span ng-if="!r.stock"></span>
          </div>
          <div class="bar" title="Steering force against the wheel's limit"><div class="fill" ng-class="{clip:ffb.view.meter.clipping}" ng-style="{width:(ffb.view.meter?ffb.view.meter.fill:0)+'%'}"></div></div>
          <div class="note">{{ffb.view.note}}</div>
        </div>
      </section>`,
      link:function (scope) {
        var alive = true, status = null, latest = null, lastUpdate = 0;
        var ffb = scope.ffb = {view:view(null, null)};
        function render() { ffb.view = view(status, latest); }
        function poll() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            status = value || null;
            scope.$evalAsync(render);
          });
        }
        ffb.press = function (action, key, dir) {
          var cmd = status ? command(action, status, key, dir) : null;
          if (cmd) bngApi.engineLua(cmd, poll);
        };
        scope.$on('ACNGFFB', function (_, value) { latest = value && value.mode === 'on' ? value : null; lastUpdate = Date.now(); scope.$evalAsync(render); });
        var timer = $interval(function () { poll(); if (latest && Date.now() - lastUpdate > 2000) { latest = null; render(); } }, 1000);
        scope.$on('$destroy', function () { alive = false; $interval.cancel(timer); });
        poll();
      }
    };
  }]);
})();
