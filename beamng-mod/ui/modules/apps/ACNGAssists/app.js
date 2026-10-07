/* Original ACNG assists app; picks the ABS and TC levels that the acng_assists vehicle extension applies. */
(function () {
  'use strict';
  var CHOICES = ['factory', 0, 1, 2, 3];
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function level(value) { var v = number(value); return v !== null && v === Math.floor(v) && v >= 0 && v <= 3 ? v : null; }
  function pct(value) { var v = number(value); return v === null ? '' : Math.round(v * 100) + '%'; }
  function label(choice) { return choice === 'factory' ? 'FACTORY' : choice === 0 ? 'OFF' : String(choice); }
  // What each row has selected: factory unless the master and that flag are ON.
  function selected(status, key) {
    var s = status || {}, f = s.enabled && s.features || {};
    if (f[key] !== true) return 'factory';
    var l = level((s.assist_levels || {})[key]);
    return l === null ? 2 : l;
  }
  function absNote(choice, snap) {
    var setting = snap && snap.abs_setting;
    if (choice === 'factory') return "Car's own ABS";
    if (setting === 'off' && choice !== 0) return 'Game ABS setting is Off; set it to Realistic';
    if (setting === 'arcade') return 'Game ABS setting is Arcade; ABS stays on';
    if (choice === 0) return 'ABS off: wheels can lock';
    var slip = snap && snap.abs_slip;
    return 'Slip target ' + (pct(slip) || '—');
  }
  function tcNote(choice, snap) {
    var mode = snap && snap.tc_mode;
    if (choice === 'factory') return "Car's own TC";
    if (mode === 'none') return "This car's ESC is not changed";
    if (choice === 0) return 'TC off: wheels can spin';
    var slip = pct(snap && snap.tc_slip) || '—';
    if (mode === 'acng') {
      var factor = number(snap && snap.tc_factor);
      return 'ACNG TC (car has none) · slip ' + slip + (factor !== null && factor < 0.98 ? ' · power ' + pct(factor) : '');
    }
    return 'Native TC · slip ' + slip;
  }
  function view(status, snapshot) {
    var snap = snapshot && snapshot.mode === 'on' ? snapshot : null;
    var rows = [['abs', 'ABS', absNote], ['tc', 'TC', tcNote]].map(function (r) {
      var choice = selected(status, r[0]);
      return {key: r[0], label: r[1], choice: choice, note: r[2](choice, snap),
        active: !!(snap && choice !== 'factory' && (r[0] === 'abs' ? snap.abs_active : snap.tc_active) === true),
        buttons: CHOICES.map(function (c) { return {value: c, text: label(c), on: c === choice}; })};
    });
    return {available: !!status, rows: rows};
  }
  // The GE Lua command for picking a choice; null for anything unknown. engineLua with a
  // callback wraps the code as guihooks.trigger(..., <code>), so it must be one expression:
  // several statements go in a function that is called at once.
  function command(key, choice) {
    if (key !== 'abs' && key !== 'tc') return null;
    if (choice === 'factory') return "extensions.acng_core.setFeature('" + key + "', false)";
    if (level(choice) === null) return null;
    return "(function() extensions.acng_core.setEnabled(true); extensions.acng_core.setAssistLevel('" + key + "', " + choice +
      "); return extensions.acng_core.setFeature('" + key + "', true) end)()";
  }
  view.command = command;
  view.selected = selected;
  if (typeof module !== 'undefined' && module.exports) module.exports = view;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngAssists', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-assists">
        <style>
          .acng-assists{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #6fb0ff;border-radius:12px;padding:10px 14px;box-shadow:0 8px 26px #0006;user-select:none}
          .acng-assists *{box-sizing:border-box}.acng-assists header{height:22px}.acng-assists .brand{font-weight:800;letter-spacing:3px}.acng-assists .brand small{font-weight:600;letter-spacing:1.5px;color:#9ca7b8;margin-left:6px}
          .acng-assists .row{display:grid;grid-template-columns:34px 1fr 12px;gap:6px;align-items:center;margin-top:7px}
          .acng-assists .name{font-weight:700;letter-spacing:1px;font-size:12px}
          .acng-assists .choices{display:flex;gap:4px}
          .acng-assists button{flex:1;font:600 10px 'Segoe UI',sans-serif;letter-spacing:.6px;border:1px solid #58606c;border-radius:5px;padding:4px 0;color:#cad0da;background:#252c36;cursor:pointer}
          .acng-assists button.factory{flex:1.9}.acng-assists button.on{color:#0d1118;background:#8ceac7;border-color:#8ceac7}
          .acng-assists .light{width:10px;height:10px;border-radius:50%;background:#2c343f}.acng-assists .light.active{background:#ffb347;box-shadow:0 0 8px #ffb347}
          .acng-assists .note{grid-column:2 / 4;font-size:10.5px;color:#9ca7b8;letter-spacing:.3px;margin-top:-2px}
          .acng-assists .idle{color:#aeb8c6;text-align:center;padding:30px 12px}
        </style>
        <header><span class="brand">ACNG<small>ASSISTS</small></span></header>
        <div ng-if="!assists.view.available" class="idle">Waiting for ACNG…</div>
        <div ng-if="assists.view.available"><div class="row" ng-repeat-start="r in assists.view.rows track by r.key">
          <span class="name">{{r.label}}</span>
          <span class="choices"><button ng-repeat="b in r.buttons track by $index" ng-class="{on:b.on,factory:b.value==='factory'}" ng-click="assists.pick(r.key,b.value)" aria-label="{{r.label}} {{b.text}}">{{b.text}}</button></span>
          <span class="light" ng-class="{active:r.active}" title="Working now"></span></div>
          <div class="row" ng-repeat-end><span></span><span class="note">{{r.note}}</span></div></div>
      </section>`,
      link:function (scope) {
        var alive = true, status = null, latest = null, lastUpdate = 0;
        var assists = scope.assists = {view:view(null, null)};
        function render() { assists.view = view(status, latest); }
        function poll() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            status = value || null;
            scope.$evalAsync(render);
          });
        }
        // Picking a level turns that assist's flag and the ACNG master on; FACTORY turns only the flag off.
        assists.pick = function (key, choice) {
          var cmd = status ? command(key, choice) : null;
          if (cmd) bngApi.engineLua(cmd, poll);
        };
        scope.$on('ACNGAssists', function (_, value) { latest = value && value.mode === 'on' ? value : null; lastUpdate = Date.now(); scope.$evalAsync(render); });
        var timer = $interval(function () { poll(); if (latest && Date.now() - lastUpdate > 2000) { latest = null; render(); } }, 1000);
        scope.$on('$destroy', function () { alive = false; $interval.cancel(timer); });
        poll();
      }
    };
  }]);
})();
