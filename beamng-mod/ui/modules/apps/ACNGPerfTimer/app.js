/* Original ACNG performance timer; displays results measured by the read-only acng_perf vehicle extension. */
(function () {
  'use strict';
  var DASH = '\u2014';
  var MPH = 2.2369362921, KMH = 3.6, FEET = 3.2808399;
  var ROWS = {
    mph: [
      {key:'mph_0_60', label:'0\u201360 mph', kind:'time'},
      {key:'mph_0_100', label:'0\u2013100 mph', kind:'time'},
      {key:'quarter_mile', label:'1/4 mile', kind:'quarter'},
      {key:'mph_60_0', label:'60\u20130 mph', kind:'distance'}],
    kmh: [
      {key:'kmh_0_100', label:'0\u2013100 km/h', kind:'time'},
      {key:'kmh_0_200', label:'0\u2013200 km/h', kind:'time'},
      {key:'quarter_mile', label:'1/4 mile', kind:'quarter'},
      {key:'kmh_100_0', label:'100\u20130 km/h', kind:'distance'}]
  };
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function format(result, kind, metric) {
    if (!result) return DASH;
    var time = number(result.time_s);
    if (kind === 'distance') {
      var distance = number(result.distance_m);
      if (distance === null) return DASH;
      return metric ? distance.toFixed(1) + ' m' : Math.round(distance * FEET) + ' ft';
    }
    if (time === null) return DASH;
    if (kind === 'quarter') {
      var trap = number(result.trap_speed_m_s);
      return time.toFixed(2) + ' s' + (trap === null ? '' : ' @ ' + Math.round(trap * (metric ? KMH : MPH)));
    }
    return time.toFixed(2) + ' s';
  }
  function view(snapshot, metric) {
    var s = snapshot || {}, last = s.last || {}, best = s.best || {};
    var mode = typeof s.mode === 'string' ? s.mode : null;
    var runTime = number(s.run_time_s), runDistance = number(s.run_distance_m);
    var status = mode === 'armed' ? 'READY \u2014 launch from a stop'
      : mode === 'launch' ? 'TIMING ' + (runTime === null ? DASH : runTime.toFixed(1) + ' s') +
        (runDistance === null ? '' : ' \u00b7 ' + (metric ? Math.round(runDistance) + ' m' : Math.round(runDistance * FEET) + ' ft'))
      : mode === 'rolling' ? 'ROLLING \u2014 stop to arm a launch'
      : 'Waiting for vehicle timer\u2026';
    return {
      mode: mode, status: status, timing: mode === 'launch',
      rows: ROWS[metric ? 'kmh' : 'mph'].map(function (row) {
        var fresh = !!(last[row.key] && last[row.key].run_id && last[row.key].run_id === s.run_id && mode === 'launch');
        return {key:row.key, label:row.label, last:format(last[row.key], row.kind, metric), best:format(best[row.key], row.kind, metric), fresh:fresh};
      })
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = view;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngPerfTimer', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-timer">
        <style>
          .acng-timer{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #f9c859;border-radius:12px;padding:10px 14px;box-shadow:0 8px 26px #0006;font-variant-numeric:tabular-nums;user-select:none}
          .acng-timer *{box-sizing:border-box}.acng-timer header{display:flex;align-items:center;gap:8px;height:24px}.acng-timer .brand{font-weight:800;letter-spacing:3px;margin-right:auto}.acng-timer .brand small{font-weight:600;letter-spacing:1.5px;color:#9ca7b8;margin-left:6px}.acng-timer button{font:600 10px 'Segoe UI',sans-serif;letter-spacing:.8px;border:1px solid #58606c;border-radius:5px;padding:4px 7px;color:#cad0da;background:#252c36;cursor:pointer}.acng-timer button.active{color:#8ceac7;border-color:#44806c}
          .acng-timer .status{margin:6px 0 4px;font-size:11px;letter-spacing:1px;color:#9ca7b8}.acng-timer .status.timing{color:#f9c859}
          .acng-timer table{width:100%;border-collapse:collapse}.acng-timer th{font-size:9px;letter-spacing:1px;color:#7f8a9b;font-weight:600;text-align:right;padding:2px 0}.acng-timer th:first-child,.acng-timer td:first-child{text-align:left}.acng-timer td{padding:3px 0;border-top:1px solid #2a313c;text-align:right;font-size:13px}.acng-timer td:first-child{color:#bfc8d5;font-size:12px}.acng-timer td.best{color:#8ceac7}.acng-timer tr.fresh td.last{color:#f9c859}.acng-timer .idle{color:#aeb8c6;text-align:center;padding:40px 0;font-size:13px}
        </style>
        <header><span class="brand">ACNG<small>TIMER</small></span><button ng-click="timer.metric=!timer.metric" aria-label="Change units">{{timer.metric?'KM/H':'MPH'}}</button><button ng-click="timer.clear()" ng-disabled="!timer.enabled" aria-label="Clear timer results">RESET</button><button ng-click="timer.toggle()" ng-class="{active:timer.enabled}" aria-label="Toggle ACNG master">{{timer.enabled?'ON':'OFF'}}</button></header>
        <div ng-if="!timer.enabled" class="idle">{{timer.available?'Enable ACNG to time launches and stops.':'Waiting for ACNG\u2026'}}</div>
        <div ng-if="timer.enabled"><div class="status" ng-class="{timing:timer.view.timing}">{{timer.view.status}}</div>
        <table><tr><th></th><th>LAST</th><th>BEST</th></tr><tr ng-repeat="row in timer.view.rows track by row.key" ng-class="{fresh:row.fresh}"><td>{{row.label}}</td><td class="last">{{row.last}}</td><td class="best">{{row.best}}</td></tr></table></div>
      </section>`,
      link:function (scope) {
        var alive = true, latest = null, lastUpdate = 0;
        var timer = scope.timer = {enabled:false, available:false, metric:false, view:view(null,false)};
        function render() { timer.view = view(latest, timer.metric); }
        function status() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            scope.$evalAsync(function () { timer.available=!!value; timer.enabled=!!(value && value.enabled); });
          });
        }
        timer.toggle=function () { if (!timer.available) return; bngApi.engineLua('extensions.acng_core.setEnabled('+(!timer.enabled ? 'true':'false')+')',status); };
        timer.clear=function () { bngApi.activeObjectLua("if extensions.isExtensionLoaded('acng_perf') then extensions.acng_perf.clear() end"); };
        scope.$on('ACNGPerf',function (_,value) { latest=value && value.mode !== 'off' ? value : null; lastUpdate=Date.now(); scope.$evalAsync(render); });
        scope.$watch('timer.metric',render);
        var poll=$interval(function () { status(); if(latest && Date.now()-lastUpdate>2000){latest=null;render();} },1000);
        scope.$on('$destroy',function () {alive=false;$interval.cancel(poll);});
        status();
      }
    };
  }]);
})();
