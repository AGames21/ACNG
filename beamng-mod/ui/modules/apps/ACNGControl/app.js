(function () {
  'use strict';
  var FEATURES=['tire_temperature','tire_wear','ffb','abs','tc'];
  function command(action,status,key,value){
    if(action==='master') return 'extensions.acng_core.setControlEnabled('+(!status.enabled)+')';
    if(action==='feature' && FEATURES.indexOf(key)>=0) return "extensions.acng_core.setFeature('"+key+"', "+(value===true)+')';
    if(action==='assist' && ['abs','tc'].indexOf(key)>=0){
      if(value==='factory') return "extensions.acng_core.setFeature('"+key+"', false)";
      var n=Number(value);if(!Number.isInteger(n)||n<0||n>3)return null;
      return "(function() extensions.acng_core.setAssistLevel('"+key+"', "+n+"); return extensions.acng_core.setFeature('"+key+"', true) end)()";
    }
    if(action==='ffb'){
      if(key==='filter' && value==='stock')return "extensions.acng_core.setFFBSetting('filter', false)";
      var limits={gain:200,car_gain:200,min_force:30,filter:100,kerb:200,road:200,slip:200};
      var p=Number(value);if(!Object.prototype.hasOwnProperty.call(limits,key)||!Number.isFinite(p)||p<0||p>limits[key])return null;
      return key==='car_gain' ? 'extensions.acng_core.setCarGain(nil, '+p/100+')' : "extensions.acng_core.setFFBSetting('"+key+"', "+p/100+')';
    }
    if(action==='telemetry' && status.enabled)return 'extensions.acng_core.setTelemetryEnabled('+(value===true)+')';
    return null;
  }
  function view(s){
    var f=s&&s.features||{},n=FEATURES.filter(function(k){return f[k]===true;}).length;
    return {available:!!s,on:!!(s&&s.enabled),selected:n,
      note:!s?'Waiting for ACNG':s.settings_error || (!s.enabled?'Your selected effects are paused':!n?'No effects selected — open Advanced':!(s.ffb_settings&&s.ffb_settings.car_model)?'Spawn a vehicle to apply effects':n+' driving effects selected'),
      first:!!s&&!s.control_panel_initialized};
  }
  if(typeof module!=='undefined'&&module.exports)module.exports={command:command,view:view};
  if(typeof angular==='undefined')return;
  angular.module('beamng.apps').directive('acngControl',['$interval',function($interval){
    return {restrict:'E',replace:true,scope:true,template:`
      <section class="acng-control">
        <style>
          .acng-control{box-sizing:border-box;max-height:100%;overflow:auto;color:#eef3fa;background:rgba(15,19,27,.96);border:1px solid #3a4352;border-radius:14px;padding:16px;font:13px 'Segoe UI',sans-serif;box-shadow:0 10px 28px #0006;user-select:none}
          .acng-control *{box-sizing:border-box}.acng-control header{display:flex;justify-content:space-between;align-items:center}.acng-control .brand{font-size:22px;font-weight:800;letter-spacing:3px}.acng-control .tag{font-size:10px;letter-spacing:1.5px;color:#a4b2c7}.acng-control .pill{font-size:10px;letter-spacing:1px;border:1px solid #495568;padding:4px 8px;border-radius:20px;color:#a4b2c7}.acng-control .pill.on{color:#77edb6;border-color:#377858}
          .acng-control button,.acng-control select{font:inherit;border:1px solid #475469;border-radius:8px;background:#232d3d;color:#eef3fa;cursor:pointer}.acng-control button:focus-visible,.acng-control select:focus-visible,.acng-control input:focus-visible{outline:2px solid #8dbbff;outline-offset:3px}.acng-control button:disabled{opacity:.4;cursor:default}
          .acng-control .master{width:100%;padding:15px 10px;margin:14px 0 8px;font-size:16px;font-weight:700;letter-spacing:1px;background:#273347}.acng-control .master.on{background:#77edb6;border-color:#77edb6;color:#101c17}.acng-control .note{font-size:11px;line-height:1.5;color:#b2bfd1;min-height:18px}.acng-control .advanced{width:100%;margin-top:12px;padding:8px;background:transparent;font-size:12px;color:#c0cee1}
          .acng-control fieldset{border:0;border-top:1px solid #354255;margin:16px 0 0;padding:12px 0 0}.acng-control legend{color:#8dbbff;font-weight:700;font-size:11px;letter-spacing:1px}.acng-control .row{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:10px 0}.acng-control .row label{flex:1}.acng-control input[type=checkbox]{width:18px;height:18px;accent-color:#77edb6;cursor:pointer}.acng-control select{padding:5px;max-width:150px}.acng-control input[type=range]{width:130px;accent-color:#77edb6}.acng-control small{display:block;color:#9cacc3;font-size:10px;line-height:1.5}.acng-control .value{font-variant-numeric:tabular-nums;min-width:38px;text-align:right}.acng-control .footer{margin-top:14px;font-size:10px;color:#8295ad}
          .acng-control .tabs{display:flex;gap:5px;margin-top:12px}.acng-control .tabs button{flex:1;padding:6px 3px;font-size:11px}.acng-control .tabs button.on{border-color:#77edb6;color:#77edb6}
        </style>
        <header><div><div class="brand">ACNG</div><span class="tag">FREEROAM · DRIVING</span></div><span class="pill" ng-class="{on:p.view.on}">{{p.view.on?'ENABLED':'OFF'}}</span></header>
        <button class="master" ng-class="{on:p.view.on}" ng-click="p.send('master')" ng-disabled="!p.view.available || p.busy" aria-label="Toggle ACNG master">{{p.view.on?'ACNG ON':'ACNG OFF'}}</button>
        <div class="note" role="status">{{p.error || p.view.note}}</div>
        <small ng-if="p.view.first">First ON enables tire heat and wear. Steering and assists are optional.</small>
        <button class="advanced" ng-click="p.advanced=!p.advanced" ng-attr-aria-expanded="{{p.advanced}}" aria-label="Show advanced ACNG settings">{{p.advanced?'Hide advanced ↑':'Advanced ↓'}}</button>
        <div ng-if="p.advanced"><small>Choose effects here. They only run while the master is ON.</small>
          <nav class="tabs"><button aria-label="ACNG tires tab" ng-click="p.tab='tires'" ng-class="{on:p.tab==='tires'}">Tires</button><button aria-label="ACNG assists tab" ng-click="p.tab='assists'" ng-class="{on:p.tab==='assists'}">Assists</button><button aria-label="ACNG steering tab" ng-click="p.tab='steering'" ng-class="{on:p.tab==='steering'}">Wheel</button><button aria-label="ACNG diagnostics tab" ng-click="p.tab='diagnostics'" ng-class="{on:p.tab==='diagnostics'}">Debug</button></nav>
          <fieldset ng-if="p.tab==='tires'"><legend>TIRES</legend>
            <div class="row"><label for="acng-heat">Temperature &amp; grip</label><input id="acng-heat" aria-label="ACNG tire temperature" type="checkbox" ng-model="p.heat" ng-change="p.send('feature','tire_temperature',p.heat)" ng-disabled="p.busy"></div>
            <small>Cold / warm grip and heat-driven pressure. No separate pressure switch yet.</small>
            <div class="row"><label for="acng-wear">Tire wear</label><input id="acng-wear" aria-label="ACNG tire wear" type="checkbox" ng-model="p.wear" ng-change="p.send('feature','tire_wear',p.wear)" ng-disabled="p.busy"></div>
          </fieldset>
          <fieldset ng-if="p.tab==='assists'"><legend>ASSISTS</legend><small>Factory keeps the car’s native assist settings.</small>
            <div class="row" ng-repeat="a in p.assists"><label>{{a.label}}</label><select ng-model="a.value" ng-change="p.send('assist',a.key,a.value)" ng-disabled="p.busy" aria-label="ACNG {{a.label}}"><option value="factory">Factory</option><option value="0">Off</option><option value="1">Level 1</option><option value="2">Level 2</option><option value="3">Level 3</option></select></div>
          </fieldset>
          <fieldset ng-if="p.tab==='steering'"><legend>STEERING</legend>
            <div class="row"><label for="acng-steering">ACNG force feedback</label><input id="acng-steering" type="checkbox" aria-label="ACNG force feedback" ng-model="p.ffb" ng-change="p.send('feature','ffb',p.ffb)" ng-disabled="p.busy"></div>
            <small>For an FFB wheel; physical wheel feel remains to be tested.</small>
            <small ng-if="p.ffb && p.wheel===false">No bound FFB wheel. These settings do not change keyboard steering.</small>
            <small ng-if="p.ffb && p.wheel && p.clip>=5">Clipping {{p.clip}}% of the time — lower Strength.</small>
            <div ng-if="p.ffb"><div class="row" ng-repeat="r in p.sliders track by r.key"><label>{{r.label}}</label><input type="range" min="0" max="{{r.max}}" step="{{r.step}}" ng-model="r.value" ng-model-options="{updateOn:'change'}" ng-change="p.send('ffb',r.key,r.value)" ng-disabled="p.busy" aria-label="ACNG {{r.label}}"><span class="value">{{r.value}}%</span></div>
            <div class="row"><label>Filter</label><select aria-label="ACNG FFB filter" ng-model="p.filter" ng-change="p.send('ffb','filter',p.filter)" ng-disabled="p.busy"><option ng-repeat="r in p.filterOptions" value="{{r}}">{{r==='stock'?'Stock':r+'%'}}</option></select></div></div>
          </fieldset>
          <fieldset ng-if="p.tab==='diagnostics'"><legend>DIAGNOSTICS</legend><div class="row"><label for="acng-logging">Telemetry stream</label><input id="acng-logging" aria-label="ACNG telemetry stream" type="checkbox" ng-model="p.telemetry" ng-change="p.send('telemetry',null,p.telemetry)" ng-disabled="!p.view.on || p.busy"></div><small>Requires the local developer collector. Master OFF stops streaming too.</small></fieldset>
        </div>
        <div class="footer">Native BeamNG suspension, damage and AI. Choices saved; startup stays OFF.</div>
      </section>`,link:function(scope){
        var alive=true,latest=null,sentAt=0;var p=scope.p={advanced:false,tab:'tires',busy:false,view:view(null)};
        function render(s){
          latest=s;p.view=view(s);if(!s)return;
          var f=s.features||{},v=s.ffb_settings||{};p.heat=f.tire_temperature===true;p.wear=f.tire_wear===true;p.ffb=f.ffb===true;p.telemetry=s.telemetry_enabled===true;
          p.assists=[{key:'abs',label:'ABS',value:f.abs?String(s.assist_levels.abs):'factory'},{key:'tc',label:'Traction control',value:f.tc?String(s.assist_levels.tc):'factory'}];
          p.filter=typeof v.filter==='number'?String(Math.round(v.filter*100)):'stock';
          p.filterOptions=['stock'];for(var i=0;i<=100;i+=5)p.filterOptions.push(String(i));if(p.filterOptions.indexOf(p.filter)<0)p.filterOptions.push(p.filter);
          p.sliders=[['gain','Strength',200,5],['car_gain','This car',200,5],['min_force','Minimum force',30,1],['kerb','Kerb effect',200,10],['road','Road effect',200,10],['slip','Slip effect',200,10]].map(function(r){return {key:r[0],label:r[1],max:r[2],step:r[3],value:Math.round((v[r[0]]||0)*100)};});
        }
        function refresh(force){bngApi.engineLua("extensions.isExtensionLoaded('acng_core') and extensions.acng_core.getStatus() or nil",function(s){if(alive)scope.$evalAsync(function(){var e=typeof document!=='undefined'&&document.activeElement;var editing=e&&e.closest&&e.closest('.acng-control')&&['INPUT','SELECT'].indexOf(e.tagName)>=0;if(force||!editing)render(s);else{latest=s;p.view=view(s);}});});}
        p.send=function(action,key,value){
          if(p.busy||!latest)return;var code=command(action,latest,key,value);if(!code)return;
          p.busy=true;p.error=null;sentAt=Date.now();bngApi.engineLua(code,function(){if(alive)scope.$evalAsync(function(){p.busy=false;refresh(true);});});
        };
        var poll=$interval(function(){if(p.busy&&Date.now()-sentAt>3000){p.busy=false;p.error='No response — check the game Lua log';}if(!p.busy)refresh();},1000);
        scope.$on('ACNGFFB',function(_,s){if(alive)scope.$evalAsync(function(){p.wheel=s&&s.mode==='on'?s.wheel===true:null;p.clip=s&&Number.isFinite(s.clip)?Math.round(s.clip*100):0;});});
        scope.$on('$destroy',function(){alive=false;$interval.cancel(poll);});refresh();
      }};
  }]);
})();
