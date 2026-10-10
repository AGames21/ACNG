/* Original ACNG tire app; shows the tire heat, grip window and wear that the acng_tires vehicle extension runs. */
(function () {
  'use strict';
  var DASH = '\u2014';
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function mix(a, b, t) {
    t = Math.max(0, Math.min(1, t));
    return 'rgb(' + [0, 1, 2].map(function (i) { return Math.round(a[i] + (b[i] - a[i]) * t); }).join(',') + ')';
  }
  var BLUE = [70, 140, 255], TEAL = [70, 200, 210], GREEN = [80, 220, 130], AMBER = [250, 200, 80], RED = [255, 80, 70];
  // Blue when cold, green across the grip window, amber to red when overheating.
  function tempColor(c, low, high) {
    if (c === null) return '#3a414c';
    if (c < low) return c < low - 30 ? mix(BLUE, TEAL, (c - (low - 60)) / 30) : mix(TEAL, GREEN, (c - (low - 30)) / 30);
    if (c <= high) return 'rgb(80,220,130)';
    return c < high + 15 ? mix(GREEN, AMBER, (c - high) / 15) : mix(AMBER, RED, (c - high - 15) / 20);
  }
  // Front row first, left before right; unknown names keep their order after those.
  function rank(name) {
    var n = String(name || '').toUpperCase();
    var row = n[0] === 'F' ? 0 : n[0] === 'R' ? 1 : 2, side = n[1] === 'L' ? 0 : n[1] === 'R' ? 1 : 2;
    return row * 3 + side;
  }
  function fixed(value, digits, unit) { var v = number(value); return v === null ? DASH : v.toFixed(digits) + unit; }
  function percent(value) { var v = number(value); return v === null ? DASH : Math.round(v * 100) + '%'; }
  // Tread bar colour: green when fresh, amber at half worn, red at the end.
  function treadColor(t) {
    if (t === null) return '#3a414c';
    return t > 0.5 ? mix(AMBER, GREEN, (t - 0.5) / 0.5) : mix(RED, AMBER, t / 0.5);
  }
  // GRIP shows only with heat on: with wear alone it would just repeat the TREAD readout.
  function view(snapshot) {
    var s = snapshot || {}, on = s.mode === 'on', wear = on && s.wear === true, heat = on && s.heat === true;
    var low = number(s.window_low_c), high = number(s.window_high_c);
    var list = Array.isArray(s.tires) ? s.tires.slice() : s.tires ? Object.keys(s.tires).map(function (k) { return s.tires[k]; }) : [];
    list = list.map(function (t, i) { return {t: t || {}, i: i}; })
      .sort(function (a, b) { return rank(a.t.name) - rank(b.t.name) || a.i - b.i; })
      .map(function (e) {
        var t = e.t, c = number(t.surface_c), tread = number(t.tread);
        if (tread !== null) tread = Math.max(0, Math.min(1, tread));
        return {name: String(t.name || '?'), surface: fixed(c, 0, '\u00b0'), core: fixed(t.core_c, 0, '\u00b0'),
          psi: fixed(t.psi, 1, ''), state: t.state === 'cold' || t.state === 'hot' || t.state === 'window' ? t.state : '',
          color: low === null || high === null ? '#3a414c' : tempColor(c, number(t.window_low_c)===null?low:t.window_low_c, number(t.window_high_c)===null?high:t.window_high_c),
          compound: ['road','sport','race'].indexOf(t.compound)>=0?t.compound:'', failed:t.worn_through===true,
          grip: percent(t.grip), tread: percent(tread), treadWidth: tread === null ? '0%' : (tread * 100).toFixed(1) + '%',
          treadColor: treadColor(tread)};
      });
    var rate = number(s.wear_rate), parts = [];
    if (s.profile==='auto') parts.push('Auto compounds · Temperatures °C');
    else if (low !== null && high !== null) parts.push('Grip window ' + low + '\u2013' + high + '\u00b0C');
    if (wear) parts.push('Wear ' + (rate === null || rate === 1 ? 'on' : 'x' + +rate.toFixed(1)));
    return {on: on, heat: heat, wear: wear, tires: list, window: parts.join(' \u00b7 ')};
  }
  view.tempColor = tempColor;
  view.treadColor = treadColor;
  if (typeof module !== 'undefined' && module.exports) module.exports = view;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngTires', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-tires" ng-class="{off:!tires.on}">
        <style>
          .acng-tires{box-sizing:border-box;width:100%;height:100%;font:12px 'Segoe UI',sans-serif;color:#f2f5f8;font-variant-numeric:tabular-nums;user-select:none;text-shadow:0 1px 2px #000c}
          .acng-tires *{box-sizing:border-box}.acng-tires header{display:flex;align-items:center;gap:4px;height:20px;opacity:.55;transition:opacity .2s}.acng-tires:hover header{opacity:1}
          .acng-tires .brand{font-size:9px;font-weight:700;letter-spacing:2px;color:#c9d2dc;margin-right:auto}
          .acng-tires button{font:700 9px 'Segoe UI',sans-serif;letter-spacing:.8px;border:0;border-radius:9px;padding:2px 7px;color:#aeb8c4;background:rgba(8,11,15,.35);cursor:pointer;text-shadow:none}.acng-tires button.active{color:#a6efc6;background:rgba(40,110,75,.4)}.acng-tires button:disabled{opacity:.4;cursor:default}
          .acng-tires.off header{opacity:.3}.acng-tires.off:hover header{opacity:.9}
          .acng-tires .grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:4px;margin-top:3px}
          .acng-tires .tire{min-width:0;overflow:hidden;background:rgba(8,11,15,.32);border-left:4px solid #3a414c;border-radius:6px;padding:3px 7px 4px;transition:border-color .3s}
          .acng-tires .top{display:flex;justify-content:space-between;align-items:baseline;font-size:9px;letter-spacing:1px;color:#aab4c1}
          .acng-tires .state{text-transform:uppercase}.acng-tires .state.cold{color:#7db8ff}.acng-tires .state.window{color:#6fe8a6}.acng-tires .state.hot{color:#ff9478}.acng-tires .state.failed{color:#ff6b5e}
          .acng-tires .reading{display:flex;justify-content:space-between;align-items:baseline}.acng-tires .surface{font-size:18px;font-weight:700;line-height:1.15}.acng-tires .grip{font-size:11px;font-weight:600;color:#d5dce4}
          .acng-tires .bar{height:3px;border-radius:2px;background:rgba(255,255,255,.12);overflow:hidden;margin-top:2px}.acng-tires .bar i{display:block;height:100%;transition:width .3s}
        </style>
        <header title="{{tires.view.window}}"><span class="brand">TIRES</span><button ng-click="tires.toggle('tire_temperature')" ng-class="{active:tires.heat}" ng-disabled="!tires.available" aria-label="Toggle tire heat and grip window">HEAT</button><button ng-click="tires.toggle('tire_wear')" ng-class="{active:tires.wear}" ng-disabled="!tires.available" aria-label="Toggle tire wear">WEAR</button></header>
        <div ng-if="tires.on" class="grid"><div class="tire" ng-repeat="t in tires.view.tires track by $index" ng-style="{'border-left-color':t.color}" title="{{t.compound}} core {{t.core}} · {{t.psi}} psi · tread {{t.tread}}">
          <div class="top"><span>{{t.name}}</span><span class="state" ng-class="t.failed?'failed':t.state">{{t.failed?'PUNCTURED':t.state}}</span></div>
          <div class="reading"><span class="surface">{{t.surface}}</span><span class="grip" ng-if="tires.view.heat" title="Grip from tire heat and tread">{{t.grip}}</span><span class="grip" ng-if="!tires.view.heat">{{t.psi}}</span></div>
          <div class="bar" ng-if="tires.view.wear"><i ng-style="{width:t.treadWidth,background:t.treadColor}"></i></div>
        </div></div>
      </section>`,
      link:function (scope) {
        var alive = true, latest = null, lastUpdate = 0;
        var tires = scope.tires = {on:false, heat:false, wear:false, available:false, view:view(null)};
        function render() { tires.view = view(latest); }
        function status() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            scope.$evalAsync(function () {
              tires.available = !!value;
              var f = value && value.enabled && value.features || {};
              tires.heat = f.tire_temperature === true;
              tires.wear = f.tire_wear === true;
              tires.on = tires.heat || tires.wear;
            });
          });
        }
        // Turning a part on also turns the ACNG master on; turning it off leaves the master alone.
        tires.toggle=function (name) {
          if (!tires.available || (name !== 'tire_temperature' && name !== 'tire_wear')) return;
          var isOn = name === 'tire_wear' ? tires.wear : tires.heat;
          bngApi.engineLua(isOn ? "extensions.acng_core.setFeature('" + name + "', false)"
            : "(function() extensions.acng_core.setEnabled(true); return extensions.acng_core.setFeature('" + name + "', true) end)()", status);
        };
        scope.$on('ACNGTires',function (_,value) { latest=value && value.mode === 'on' ? value : null; lastUpdate=Date.now(); scope.$evalAsync(render); });
        var poll=$interval(function () { status(); if(latest && Date.now()-lastUpdate>2000){latest=null;render();} },1000);
        scope.$on('$destroy',function () {alive=false;$interval.cancel(poll);});
        status();
      }
    };
  }]);
})();
