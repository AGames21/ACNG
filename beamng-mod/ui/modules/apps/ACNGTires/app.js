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
      template: `<section class="acng-tires">
        <style>
          .acng-tires{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #5fe39a;border-radius:12px;padding:10px 14px;box-shadow:0 8px 26px #0006;font-variant-numeric:tabular-nums;user-select:none}
          .acng-tires *{box-sizing:border-box}.acng-tires header{display:flex;align-items:center;gap:6px;height:24px}.acng-tires .brand{font-weight:800;letter-spacing:3px;margin-right:auto}.acng-tires .brand small{font-weight:600;letter-spacing:1.5px;color:#9ca7b8;margin-left:6px}
          .acng-tires button{font:600 10px 'Segoe UI',sans-serif;letter-spacing:.8px;border:1px solid #58606c;border-radius:5px;padding:4px 7px;color:#cad0da;background:#252c36;cursor:pointer}.acng-tires button.active{color:#8ceac7;border-color:#44806c}
          .acng-tires .window{margin:4px 0 6px;font-size:11px;letter-spacing:1px;color:#9ca7b8}
          .acng-tires .grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:8px}
          .acng-tires .tire{display:flex;gap:8px;align-items:stretch;background:#1d232c;border-radius:8px;padding:6px;min-width:0;overflow:hidden}
          .acng-tires .swatch{width:18px;border-radius:6px;transition:background .3s}
          .acng-tires .info{flex:1;min-width:0}.acng-tires .top{display:flex;justify-content:space-between;align-items:baseline}
          .acng-tires .name{font-size:10px;letter-spacing:1px;color:#7f8a9b}.acng-tires .state{font-size:9px;letter-spacing:1px;color:#7f8a9b;text-transform:uppercase}
          .acng-tires .state.cold{color:#6fb0ff}.acng-tires .state.window{color:#5fe39a}.acng-tires .state.hot{color:#ff8a6a}
          .acng-tires .reading{display:flex;justify-content:space-between;align-items:baseline}.acng-tires .surface{font-size:22px;font-weight:700;line-height:1.1}.acng-tires .grip{font-size:13px;font-weight:700;color:#cad0da}.acng-tires .grip b{font-weight:600;color:#7f8a9b;font-size:9px;letter-spacing:.8px;margin-right:3px}
          .acng-tires .meta{display:flex;justify-content:space-between;font-size:11px;color:#aeb8c6}.acng-tires .meta b{font-weight:600;color:#7f8a9b;font-size:9px;letter-spacing:.8px;margin-right:3px}
          .acng-tires .tread{display:flex;align-items:center;gap:5px;font-size:11px;color:#aeb8c6;margin-top:2px}.acng-tires .tread b{font-weight:600;color:#7f8a9b;font-size:9px;letter-spacing:.8px}
          .acng-tires .bar{flex:1;height:5px;border-radius:3px;background:#2c343f;overflow:hidden}.acng-tires .bar i{display:block;height:100%;transition:width .3s}
          .acng-tires .idle{color:#aeb8c6;text-align:center;padding:40px 12px;font-size:13px;line-height:1.5}
        </style>
        <header><span class="brand">ACNG<small>TIRES</small></span><button ng-click="tires.toggle('tire_temperature')" ng-class="{active:tires.heat}" ng-disabled="!tires.available" aria-label="Toggle tire heat and grip window">HEAT {{tires.heat?'ON':'OFF'}}</button><button ng-click="tires.toggle('tire_wear')" ng-class="{active:tires.wear}" ng-disabled="!tires.available" aria-label="Toggle tire wear">WEAR {{tires.wear?'ON':'OFF'}}</button></header>
        <div ng-if="!tires.on" class="idle"><span ng-if="tires.available">Tire model OFF \u2014 stock BeamNG tires.<br>HEAT adds tire heat and a grip window.<br>WEAR wears the tread as you slide.</span><span ng-if="!tires.available">Waiting for ACNG\u2026</span></div>
        <div ng-if="tires.on"><div class="window">{{tires.view.window}}</div>
        <div class="grid"><div class="tire" ng-repeat="t in tires.view.tires track by $index">
          <div class="swatch" ng-style="{background:t.color}"></div>
          <div class="info"><div class="top"><span class="name">{{t.name}} {{t.compound}}</span><span class="state" ng-class="t.state">{{t.failed?'PUNCTURED':t.state}}</span></div>
          <div class="reading"><span class="surface">{{t.surface}}</span><span class="grip" ng-if="tires.view.heat" title="Grip from tire heat and tread"><b>GRIP</b>{{t.grip}}</span></div>
          <div class="meta"><span><b>CORE</b>{{t.core}}</span><span><b>PSI</b>{{t.psi}}</span></div>
          <div class="tread" ng-if="tires.view.wear"><b>TREAD</b><span class="bar"><i ng-style="{width:t.treadWidth,background:t.treadColor}"></i></span><span>{{t.tread}}</span></div></div>
        </div></div></div>
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
