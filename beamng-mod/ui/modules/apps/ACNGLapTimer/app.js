/* Original ACNG lap timer; displays laps measured by the read-only acng_laps vehicle extension. */
(function () {
  'use strict';
  var DASH = '\u2014';
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function lapTime(value) {
    var t = number(value);
    if (t === null || t < 0) return DASH;
    var ms = Math.round(t * 1000), minutes = Math.floor(ms / 60000), rest = (ms % 60000) / 1000;
    return minutes + ':' + (rest < 10 ? '0' : '') + rest.toFixed(3);
  }
  // Lua sequences arrive as JSON arrays (0-based); tolerate {"1":...} objects too.
  function nth(list, k) { return list ? number(Array.isArray(list) ? list[k - 1] : list[k]) : null; }
  function seconds(value) { var t = number(value); return t === null ? DASH : t.toFixed(3); }
  function delta(value) {
    var d = number(value);
    if (d === null) return {text: DASH, cls: ''};
    var r = Math.round(d * 1000) / 1000;
    return {text: (r > 0 ? '+' : r < 0 ? '\u2212' : '\u00b1') + Math.abs(r).toFixed(3), cls: r > 0 ? 'behind' : r < 0 ? 'ahead' : ''};
  }
  var NOTES = {
    reset: 'Reset \u2014 lap abandoned. Cross the line to start a new one.',
    teleport: 'Car moved \u2014 lap abandoned. Cross the line to start a new one.',
    reversed: 'Crossed the line backwards \u2014 lap abandoned.'
  };
  function view(snapshot) {
    var s = snapshot || {}, mode = typeof s.mode === 'string' ? s.mode : null;
    var last = s.last || {}, best = s.best || {}, bestSectors = s.best_sectors;
    var live = mode === 'lap' ? s.sectors_live : null, lastSectors = last.sectors;
    var status = mode === 'no_line' ? 'Drive to your start/finish line and press SET LINE'
      : mode === 'out_lap' ? (NOTES[s.note] || 'Out lap \u2014 cross the line to start timing')
      : mode === 'lap' ? 'LAP ' + (number(s.lap_number) || DASH)
      : 'Waiting for vehicle timer\u2026';
    var sectors = [];
    for (var k = 1; k <= 3; k++) {
      var current = nth(live, k), previous = nth(lastSectors, k), bestK = nth(bestSectors, k);
      var value = current !== null ? current : previous;
      var cls = value === null ? '' : current === null ? 'prev'
        : bestK === null || value <= bestK + 1e-9 ? 'best' : 'slower';
      sectors.push({label: 'S' + k, text: seconds(value), cls: cls});
    }
    return {
      mode: mode, status: status, timing: mode === 'lap',
      current: mode === 'lap' ? lapTime(s.current_s) : lapTime(last.time_s),
      delta: mode === 'lap' ? delta(s.delta_s) : {text: '', cls: ''},
      sectors: sectors, hasSectors: number(s.ref_length_m) !== null,
      last: lapTime(last.time_s), best: lapTime(best.time_s), optimal: lapTime(s.optimal_s),
      laps: number(s.laps) || 0
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = view;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngLapTimer', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-laps">
        <style>
          .acng-laps{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #c58cff;border-radius:12px;padding:10px 14px;box-shadow:0 8px 26px #0006;font-variant-numeric:tabular-nums;user-select:none}
          .acng-laps *{box-sizing:border-box}.acng-laps header{display:flex;align-items:center;gap:6px;height:24px}.acng-laps .brand{font-weight:800;letter-spacing:3px;margin-right:auto}.acng-laps .brand small{font-weight:600;letter-spacing:1.5px;color:#9ca7b8;margin-left:6px}.acng-laps button{font:600 10px 'Segoe UI',sans-serif;letter-spacing:.8px;border:1px solid #58606c;border-radius:5px;padding:4px 7px;color:#cad0da;background:#252c36;cursor:pointer}.acng-laps button.active{color:#8ceac7;border-color:#44806c}
          .acng-laps .status{margin:5px 0 2px;font-size:11px;letter-spacing:1px;color:#9ca7b8;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.acng-laps .status.timing{color:#c58cff}
          .acng-laps .main{display:flex;align-items:baseline;gap:12px}.acng-laps .time{font-size:30px;font-weight:700;letter-spacing:.5px}.acng-laps .delta{font-size:18px;font-weight:700;color:#aeb8c6}.acng-laps .delta.ahead{color:#5fe39a}.acng-laps .delta.behind{color:#ff7a7a}
          .acng-laps .sectors{display:flex;gap:6px;margin:6px 0}.acng-laps .sector{flex:1;border-radius:6px;background:#1d232c;padding:3px 6px;text-align:center}.acng-laps .sector small{display:block;font-size:9px;letter-spacing:1px;color:#7f8a9b}.acng-laps .sector span{font-size:13px}.acng-laps .sector.best span{color:#c58cff}.acng-laps .sector.slower span{color:#f9c859}.acng-laps .sector.prev span{color:#6f7a8b}
          .acng-laps .totals{display:flex;justify-content:space-between;font-size:12px;color:#bfc8d5}.acng-laps .totals b{display:block;font-size:9px;letter-spacing:1px;color:#7f8a9b;font-weight:600}.acng-laps .totals .best{color:#c58cff}
          .acng-laps .idle{color:#aeb8c6;text-align:center;padding:44px 0;font-size:13px}
        </style>
        <header><span class="brand">ACNG<small>LAPS</small></span><button ng-click="laps.setLine()" ng-disabled="!laps.enabled" aria-label="Set start finish line here">SET LINE</button><button ng-click="laps.clear()" ng-disabled="!laps.enabled" aria-label="Clear lap times">CLEAR</button><button ng-click="laps.toggle()" ng-class="{active:laps.enabled}" aria-label="Toggle ACNG master">{{laps.enabled?'ON':'OFF'}}</button></header>
        <div ng-if="!laps.enabled" class="idle">{{laps.available?'Enable ACNG to time laps.':'Waiting for ACNG\u2026'}}</div>
        <div ng-if="laps.enabled"><div class="status" ng-class="{timing:laps.view.timing}">{{laps.view.status}}</div>
        <div class="main"><span class="time">{{laps.view.current}}</span><span class="delta" ng-class="laps.view.delta.cls">{{laps.view.delta.text}}</span></div>
        <div class="sectors"><div class="sector" ng-repeat="sec in laps.view.sectors track by sec.label" ng-class="sec.cls"><small>{{sec.label}}</small><span>{{sec.text}}</span></div></div>
        <div class="totals"><div><b>LAST</b>{{laps.view.last}}</div><div class="best"><b>BEST</b>{{laps.view.best}}</div><div><b>OPTIMAL</b>{{laps.view.optimal}}</div><div><b>LAPS</b>{{laps.view.laps}}</div></div></div>
      </section>`,
      link:function (scope) {
        var alive = true, latest = null, lastUpdate = 0;
        var laps = scope.laps = {enabled:false, available:false, view:view(null)};
        function render() { laps.view = view(latest); }
        function status() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            scope.$evalAsync(function () { laps.available=!!value; laps.enabled=!!(value && value.enabled); });
          });
        }
        function vehicle(call) { bngApi.activeObjectLua("if extensions.isExtensionLoaded('acng_laps') then extensions.acng_laps." + call + "() end"); }
        laps.toggle=function () { if (!laps.available) return; bngApi.engineLua('extensions.acng_core.setEnabled('+(!laps.enabled ? 'true':'false')+')',status); };
        laps.setLine=function () { vehicle('setLineHere'); };
        laps.clear=function () { vehicle('clear'); };
        scope.$on('ACNGLaps',function (_,value) { latest=value && value.mode !== 'off' ? value : null; lastUpdate=Date.now(); scope.$evalAsync(render); });
        var poll=$interval(function () { status(); if(latest && Date.now()-lastUpdate>2000){latest=null;render();} },1000);
        scope.$on('$destroy',function () {alive=false;$interval.cancel(poll);});
        status();
      }
    };
  }]);
})();
