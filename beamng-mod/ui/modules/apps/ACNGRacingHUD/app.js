/* Original ACNG dashboard; consumes native streams, never applies forces. */
(function () {
  'use strict';
  var DASH = '\u2014';
  function number(value) { return typeof value === 'number' && Number.isFinite(value) ? value : null; }
  function pedal(value) { value = number(value); return value === null ? null : Math.max(0, Math.min(1, value)); }
  function model(streams, metric) {
    const e = streams.electrics || {}, engine = streams.engineInfo || [];
    const speed = number(e.wheelspeed), rpm = number(engine[4]), limit = number(engine[1]);
    const ratio = rpm !== null && limit > 0 ? Math.max(0, Math.min(1, rpm / limit)) : null;
    return {
      speed: speed === null ? DASH : Math.round(Math.abs(speed) * (metric ? 3.6 : 2.2369362921)),
      rpm: rpm === null ? DASH : Math.round(Math.max(0, rpm)).toLocaleString('en-US'),
      gear: typeof e.gear === 'string' || typeof e.gear === 'number' ? (e.gear === -1 ? 'R' : e.gear === 0 ? 'N' : String(e.gear).toUpperCase()) : DASH,
      ratio: ratio, shift: ratio !== null && ratio >= 0.93,
      pedals: ['throttle', 'brake', 'clutch'].map(function (key) { const value = pedal(e[key]); return {name:key.toUpperCase(), value:value, percent:value === null ? DASH : Math.round(value * 100)}; })
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = model;
  if (typeof angular === 'undefined') return;
  angular.module('beamng.apps').directive('acngRacingHud', ['$interval', function ($interval) {
    return {restrict:'EA', replace:true, scope:true,
      template: `<section class="acng-hud">
        <style>
          .acng-hud{box-sizing:border-box;width:100%;height:100%;font:13px 'Segoe UI',sans-serif;color:#f5f6f8;background:rgba(13,17,24,.94);border:1px solid #414650;border-top:3px solid #ef554c;border-radius:12px;padding:12px 16px;box-shadow:0 8px 26px #0006;font-variant-numeric:tabular-nums;user-select:none}
          .acng-hud *{box-sizing:border-box}.acng-hud header{display:flex;align-items:center;gap:8px;height:24px}.acng-hud .brand{font-weight:800;letter-spacing:3px;margin-right:auto}.acng-hud button{font:600 10px 'Segoe UI',sans-serif;letter-spacing:.8px;border:1px solid #58606c;border-radius:5px;padding:4px 7px;color:#cad0da;background:#252c36;cursor:pointer}.acng-hud button.active{color:#8ceac7;border-color:#44806c}.acng-hud .dash{display:flex;align-items:center;gap:18px;height:87px}.acng-hud .gear{font-size:62px;font-weight:750;color:#fff;line-height:1;width:61px;text-align:center;border-right:1px solid #414650;padding-right:12px}.acng-hud .speed{font-size:46px;font-weight:650;line-height:1}.acng-hud .unit{font-size:11px;color:#9ca7b8;letter-spacing:1px;margin-left:5px}.acng-hud .rev{flex:1;text-align:right}.acng-hud .rpm{font-size:21px;font-weight:600}.acng-hud .label{color:#9ca7b8;font-size:10px;letter-spacing:1px}.acng-hud .lights{display:flex;gap:3px;margin:7px 0}.acng-hud .light{flex:1;height:7px;border-radius:2px;background:#303846}.acng-hud .light.lit{background:#50d6b0}.acng-hud .light.warning.lit{background:#f9c859}.acng-hud .light.red.lit{background:#ff6158}.acng-hud .shift{color:#ff8179}.acng-hud .pedals{display:flex;gap:12px;border-top:1px solid #333c48;padding-top:8px}.acng-hud .pedal{flex:1}.acng-hud .pedal-label{display:flex;justify-content:space-between;font-size:9px;letter-spacing:.5px;color:#bfc8d5}.acng-hud .track{height:5px;background:#313946;border-radius:3px;margin-top:5px;overflow:hidden}.acng-hud .fill{height:100%;background:#55dcb0}.acng-hud .pedal:nth-child(2) .fill{background:#f46d64}.acng-hud .pedal:nth-child(3) .fill{background:#74adfa}.acng-hud .idle{color:#aeb8c6;text-align:center;padding:33px 0;font-size:13px}
        </style>
        <header><span class="brand">ACNG</span><button ng-click="hud.metric=!hud.metric" aria-label="Change speed units">{{hud.metric?'KM/H':'MPH'}}</button><button ng-click="hud.showPedals=!hud.showPedals" ng-class="{active:hud.showPedals}" aria-label="Toggle pedal bars">PEDALS</button><button ng-click="hud.toggle()" ng-class="{active:hud.enabled}" aria-label="Toggle ACNG master">{{hud.enabled?'ON':'OFF'}}</button></header>
        <div ng-if="!hud.enabled" class="idle">{{hud.available?'Enable ACNG to show live driving data.':'Waiting for ACNG\u2026'}}</div>
        <div ng-if="hud.enabled"><div class="dash"><div class="gear">{{hud.data.gear}}</div><div><span class="speed">{{hud.data.speed}}</span><span class="unit">{{hud.metric?'km/h':'mph'}}</span></div><div class="rev"><span class="rpm" ng-class="{shift:hud.data.shift}">{{hud.data.rpm}}</span><span class="unit">RPM</span><div class="lights"><span ng-repeat="n in hud.lights track by $index" class="light" ng-class="{lit:hud.data.ratio!==null && hud.data.ratio>=n,warning:n>=.8,red:n>=.93}"></span></div><span class="label">{{hud.data.shift?'NEAR REDLINE':'ENGINE SPEED'}}</span></div></div>
        <div class="pedals" ng-if="hud.showPedals"><div class="pedal" ng-repeat="p in hud.data.pedals track by p.name"><div class="pedal-label"><span>{{p.name}}</span><span>{{p.percent}}{{p.value===null?'':'%'}}</span></div><div class="track"><div class="fill" ng-style="{width:(p.value===null?0:p.value*100)+'%'}"></div></div></div></div>
        </div>
      </section>`,
      link:function (scope) {
        const streams = ['electrics','engineInfo'];
        let alive = true, latest = {}, lastUpdate = 0;
        const hud = scope.hud = {enabled:false, available:false, metric:false, showPedals:true, lights:[.1,.2,.3,.4,.5,.6,.7,.8,.87,.93, .97,1],data:model({},false)};
        StreamsManager.add(streams);
        function status() {
          bngApi.engineLua('extensions.acng_core and extensions.acng_core.getStatus() or nil', function (value) {
            if (!alive) return;
            scope.$evalAsync(function () { hud.available=!!value; hud.enabled=!!(value && value.enabled); });
          });
        }
        hud.toggle=function () { if (!hud.available) return; bngApi.engineLua('extensions.acng_core.setEnabled('+(!hud.enabled ? 'true':'false')+')',status); };
        scope.$on('streamsUpdate',function (_,value) { latest=value || {}; lastUpdate=Date.now(); scope.$evalAsync(function () {hud.data=model(latest,hud.metric);}); });
        scope.$watch('hud.metric',function () {hud.data=model(latest,hud.metric);});
        const timer=$interval(function () {status(); if(Date.now()-lastUpdate>1500){latest={};hud.data=model({},hud.metric);}},1000);
        scope.$on('$destroy',function () {alive=false;$interval.cancel(timer);StreamsManager.remove(streams);});
        status();
      }
    };
  }]);
})();
