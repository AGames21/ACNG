(function () {
  'use strict';
  var FEATURES=['tire_temperature','tire_wear','ffb','abs','tc'];
  function command(action,status,key,value){
    if(action==='profile' && ['auto','road','sport','race'].indexOf(value)>=0)return "extensions.acng_core.setTireProfile('"+value+"')";
    if(action==='master') return 'extensions.acng_core.setControlEnabled('+(!status.enabled)+')';
    if(action==='pit' && ['mark','cancel','service'].indexOf(key)>=0)return "extensions.acng_core.pitCommand('"+key+"', "+(value && value.refuel===true)+", "+(value && value.tread===true)+")";
    if(action==='feature' && (FEATURES.indexOf(key)>=0||key==='pits')) return "extensions.acng_core.setFeature('"+key+"', "+(value===true)+')';
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
          .acng-control{box-sizing:border-box;width:100%;max-height:100%;overflow:auto;color:#e6edf4;background:rgba(16,21,28,.92);border:1px solid #ffffff24;border-radius:8px;padding:6px 8px;font:12px 'Segoe UI',sans-serif;user-select:none}
          .acng-control *{box-sizing:border-box}.acng-control header{display:flex;align-items:center;gap:8px;height:28px}.acng-control .brand{flex:1;font-size:13px;font-weight:700;letter-spacing:1.5px}
          .acng-control button,.acng-control select{font:inherit;border:1px solid #ffffff25;border-radius:5px;background:#202a35;color:#e6edf4;cursor:pointer}.acng-control button:focus-visible,.acng-control select:focus-visible,.acng-control input:focus-visible{outline:2px solid #82baff;outline-offset:2px}.acng-control button:disabled{opacity:.4;cursor:default}
          .acng-control .master{min-width:48px;height:26px;padding:0 10px;font-size:11px;font-weight:700}.acng-control .master.on{background:#244b3b;border-color:#569d78;color:#9de7bd}.acng-control .advanced{height:26px;min-width:30px;padding:0 7px;background:transparent;color:#a8b8c9;font-size:16px}.acng-control .note{font-size:11px;line-height:1.4;color:#b2bfd1;margin-top:6px}
          .acng-control fieldset{border:0;margin:10px 0 0;padding:0}.acng-control legend{display:none}.acng-control .row{display:flex;align-items:center;justify-content:space-between;gap:8px;margin:9px 0}.acng-control .row label{flex:1}.acng-control input[type=checkbox]{width:16px;height:16px;accent-color:#80ceaa;cursor:pointer}.acng-control select{padding:4px;max-width:145px}.acng-control input[type=range]{width:95px;accent-color:#80ceaa}.acng-control small{display:block;color:#97a8ba;font-size:10px;line-height:1.4}.acng-control .value{font-variant-numeric:tabular-nums;min-width:32px;text-align:right}
          .acng-control .tabs{display:flex;gap:3px;margin:10px 0 12px}.acng-control .tabs button{flex:1;padding:5px 2px;font-size:10px;background:transparent;border-color:transparent}.acng-control .tabs button.on{border-bottom-color:#80ceaa;color:#9de7bd}.acng-control .footer{margin-top:10px;font-size:10px;color:#8295ad}
        </style>
        <header><span class="brand">ACNG</span>
          <button class="master" ng-class="{on:p.view.on}" ng-click="p.send('master')" ng-disabled="!p.view.available || p.busy" aria-label="Toggle ACNG master" ng-attr-aria-pressed="{{p.view.on}}">{{p.view.on?'ON':'OFF'}}</button>
          <button class="advanced" ng-click="p.toggleAdvanced()" ng-attr-aria-expanded="{{p.advanced}}" aria-label="Show advanced ACNG settings" title="Advanced settings">{{p.advanced?'▴':'▾'}}</button>
        </header>
        <div class="note" role="status" ng-if="p.error || !p.view.available">{{p.error || p.view.note}}</div>
        <div ng-if="p.advanced"><small>{{p.view.note}}</small><small ng-if="p.view.first">First ON enables heat and wear. Assists and steering are optional.</small>
          <nav class="tabs"><button aria-label="ACNG tires tab" ng-click="p.tab='tires'" ng-class="{on:p.tab==='tires'}">Tires</button><button aria-label="ACNG assists tab" ng-click="p.tab='assists'" ng-class="{on:p.tab==='assists'}">Assists</button><button aria-label="ACNG steering tab" ng-click="p.tab='steering'" ng-class="{on:p.tab==='steering'}">Wheel</button><button aria-label="ACNG pits tab" ng-click="p.tab='pits'" ng-class="{on:p.tab==='pits'}">Pits</button><button aria-label="ACNG diagnostics tab" ng-click="p.tab='diagnostics'" ng-class="{on:p.tab==='diagnostics'}">Debug</button></nav>
          <fieldset ng-if="p.tab==='tires'"><legend>TIRES</legend>
            <div class="row"><label>Tire preset</label><select aria-label="ACNG tire preset" ng-model="p.profile" ng-change="p.send('profile',null,p.profile)" ng-disabled="p.busy"><option value="auto">Auto — fitted tires</option><option value="road">Road</option><option value="sport">Sport</option><option value="race">Race</option></select></div>
            <small>Auto follows fitted front/rear tires. Native peak grip stays in place; unknown tires use Road. Thermal presets are experimental.</small>
            <div class="row"><label for="acng-heat">Temperature &amp; grip</label><input id="acng-heat" aria-label="ACNG tire temperature" type="checkbox" ng-model="p.heat" ng-change="p.send('feature','tire_temperature',p.heat)" ng-disabled="p.busy"></div>
            <small>Cold / warm grip and heat-driven pressure. No separate pressure switch yet.</small>
            <div class="row"><label for="acng-wear">Tire wear &amp; failure</label><input id="acng-wear" aria-label="ACNG tire wear" type="checkbox" ng-model="p.wear" ng-change="p.send('feature','tire_wear',p.wear)" ng-disabled="p.busy"></div><small>Worn-through tires puncture. Switching OFF does not repair damage.</small>
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
          <fieldset ng-if="p.tab==='pits'"><legend>PIT SERVICES</legend>
            <div class="row"><label for="acng-pits">Enable pit services</label><input id="acng-pits" type="checkbox" ng-model="p.pits" ng-change="p.send('feature','pits',p.pits)" ng-disabled="p.busy" aria-label="ACNG pit services"></div>
            <small>Park in a pit garage and mark your box. Box clears on vehicle reset/switch. No AI spawned.</small>
            <div ng-if="p.pits && p.view.on"><div class="row"><button aria-label="ACNG mark pit box" ng-click="p.send('pit','mark')" ng-disabled="p.busy || p.pit.servicing">Mark box here</button><span>{{p.pit.in_box?'Inside box':'Outside box'}}</span></div>
              <div class="row"><label>Refuel (20 s)</label><input type="checkbox" ng-model="p.refuel" aria-label="ACNG pit refuel"></div>
              <div class="row"><label>Fresh ACNG tread (8 s)</label><input type="checkbox" ng-model="p.newTread" aria-label="ACNG pit fresh tread"></div>
              <small>Tread service requires intact tires and ACNG wear ON. Heat, punctures and crash damage stay unchanged. Leaking tanks cannot refuel.</small>
              <div class="row"><button aria-label="ACNG start pit service" ng-click="p.send('pit','service',{refuel:p.refuel,tread:p.newTread})" ng-disabled="p.busy || !p.pit.in_box || !p.pit.stopped || p.pit.servicing">Start service</button><button aria-label="ACNG cancel pit service" ng-click="p.send('pit','cancel')" ng-disabled="!p.pit.servicing">Cancel</button></div>
              <div role="status">{{p.pit.message || 'Waiting for vehicle'}} <span ng-if="p.pit.servicing">{{p.pit.remaining_s | number:1}} s</span></div>
            </div>
          </fieldset>
          <fieldset ng-if="p.tab==='diagnostics'"><legend>DIAGNOSTICS</legend><div class="row"><label for="acng-logging">Telemetry stream</label><input id="acng-logging" aria-label="ACNG telemetry stream" type="checkbox" ng-model="p.telemetry" ng-change="p.send('telemetry',null,p.telemetry)" ng-disabled="!p.view.on || p.busy"></div><small>Requires the local developer collector. Master OFF stops streaming too.</small></fieldset>
        </div>
        <div class="footer" ng-if="p.advanced">Choices saved · Startup OFF</div>
      </section>`,link:function(scope,element){
        var alive=true,latest=null,sentAt=0;var p=scope.p={advanced:false,tab:'tires',busy:false,refuel:true,newTread:false,pit:{},view:view(null)};
        function resizePanel(){
          // BeamNG 0.39 wraps legacy apps in .overlay-item sized in em units; older
          // builds use an absolutely placed element with pixel sizes.
          var host=element[0].closest&&element[0].closest('.overlay-item');
          if(!host)host=element[0].parentElement;
          while(host && host!==document.body && !host.classList.contains('overlay-item')){
            if(/^[0-9.]+px$/.test(host.style.width) && /^[0-9.]+px$/.test(host.style.height) && getComputedStyle(host).position==='absolute')break;
            host=host.parentElement;
          }
          if(host && host!==document.body){
            host.setAttribute('data-acng-control-host','true');
            host.style.height=p.advanced?'410px':'44px';host.style.width=p.advanced?'290px':'220px';
          }
        }
        p.toggleAdvanced=function(){p.advanced=!p.advanced;resizePanel();};
        requestAnimationFrame(resizePanel);
        function render(s){
          latest=s;p.view=view(s);if(!s)return;p.profile=s.tire_profile||'auto';
          var f=s.features||{},v=s.ffb_settings||{};p.heat=f.tire_temperature===true;p.wear=f.tire_wear===true;p.ffb=f.ffb===true;p.pits=f.pits===true;p.telemetry=s.telemetry_enabled===true;
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
        scope.$on('ACNGPit',function(_,s){if(alive)scope.$evalAsync(function(){p.pit=s||{};});});
        scope.$on('$destroy',function(){alive=false;$interval.cancel(poll);});refresh();
      }};
  }]);
})();
