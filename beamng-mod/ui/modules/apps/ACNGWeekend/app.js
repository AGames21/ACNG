(function () {
  'use strict';
  angular.module('beamng.apps').directive('acngWeekend', ['$interval', function ($interval) {
    return { restrict:'E', replace:true, template:
      '<section class="acng-weekend" style="box-sizing:border-box;background:rgba(13,17,23,.94);color:#ecf2fa;padding:14px;font:14px Arial;border-top:3px solid #ee383f;height:100%;overflow:auto">' +
      '<b style="letter-spacing:2px">ACNG · RACE WEEKEND</b><div style="color:#aeb8c9;margin:8px 0">{{w.track || "Hirochi Raceway Short"}}</div>' +
      '<div style="font-size:20px;color:#6ff2aa">{{w.phase | uppercase}} · {{w.message}}</div>' +
      '<div style="margin:10px 0">AI <select ng-model="ai" ng-disabled="w.phase !== \'off\'"><option ng-value="0">0</option><option ng-value="1">1</option><option ng-value="2">2</option><option ng-value="3">3</option></select> ' +
      'Laps <select aria-label="Race laps" ng-model="laps"><option ng-value="1">1</option><option ng-value="3">3</option><option ng-value="5">5</option></select> ' +
      'Minutes <select ng-model="minutes"><option ng-value="1">1</option><option ng-value="3">3</option><option ng-value="5">5</option></select></div>' +
      '<div style="display:flex;flex-wrap:wrap;gap:6px"><button aria-label="Prepare race weekend" ng-click="act(\'prepare\')" ng-disabled="busy || w.phase !== \'off\'">PREPARE</button>' +
      '<button aria-label="Start practice" ng-click="act(\'practice\')" ng-disabled="busy || !ready()">PRACTICE</button>' +
      '<button aria-label="Start qualifying" ng-click="act(\'qualifying\')" ng-disabled="busy || !ready()">QUALIFY</button>' +
      '<button aria-label="Start race" ng-click="act(\'race\')" ng-disabled="busy || !ready()">RACE</button>' +
      '<button aria-label="End current session" ng-click="act(\'endSession\')" ng-disabled="busy || !running()">END SESSION</button>' +
      '<button aria-label="Cancel race weekend" ng-click="act(\'cancel\')" ng-disabled="busy || w.phase === \'off\'">CANCEL</button></div>' +
      '<div style="margin:10px 0">{{time(w.clock_s)}} <span ng-if="w.session !== \'race\'"> / {{time(w.remaining_s)}} remaining</span></div>' +
      '<table style="width:100%;text-align:left"><tr style="color:#aeb8c9"><th>POS</th><th>DRIVER</th><th>LAP</th><th>BEST</th></tr>' +
      '<tr ng-repeat="r in w.standings track by r.id" ng-style="{color:r.player ? \'#6ff2aa\' : \'#ecf2fa\'}"><td>{{$index+1}}</td><td>{{r.name}} {{r.retired ? \'DNF\' : r.finished ? \'🏁\' : \'\'}}</td><td>{{r.lap}}/{{w.options.laps}}</td><td>{{time(r.best_s)}}</td></tr></table>' +
      '<small style="display:block;color:#aeb8c9;margin-top:10px">Reset in qualifying or racing = DNF. CANCEL keeps your car and its damage.</small></section>',
      link:function(scope) {
        var alive=true; scope.w={phase:'off',standings:[]};scope.ai=0;scope.laps=3;scope.minutes=3;scope.busy=false;
        scope.time=function(x){ if(typeof x!=='number' || !isFinite(x)) return '—'; return Math.floor(x/60)+':'+('0'+(x%60).toFixed(2)).slice(-5); };
        scope.ready=function(){return scope.w.phase==='ready'||scope.w.phase==='results';};
        scope.running=function(){return ['practice','qualifying','race'].indexOf(scope.w.phase)>=0;};
        function refresh(){ bngApi.engineLua("(function() if extensions.isExtensionLoaded('acng_weekend') then return extensions.acng_weekend.getSnapshot() end return {phase='off'} end)()",function(s){if(alive&&s)scope.$evalAsync(function(){scope.w=s;});}); }
        scope.act=function(action){
          if(scope.busy || ['prepare','practice','qualifying','race','endSession','cancel'].indexOf(action)<0) return;
          var code="(function() ";
          if(['prepare','practice','qualifying','race'].indexOf(action)>=0) code+="extensions.acng_core.setEnabled(true); extensions.acng_core.setFeature('race_sessions',true); ";
          code+="if not extensions.isExtensionLoaded('acng_weekend') then extensions.load('acng_weekend') end; local w=extensions.acng_weekend; ";
          if(action==='prepare') code+="w.setOption('opponents',"+Number(scope.ai)+"); ";
          code+="w.setOption('laps',"+Number(scope.laps)+"); w.setOption('minutes',"+Number(scope.minutes)+"); return ";
          code+=(['practice','qualifying','race'].indexOf(action)>=0 ? "w.begin('"+action+"')" : action==='cancel' ? "(function() w.cancel(); extensions.acng_core.setFeature('race_sessions',false); return true end)()" : 'w.'+action+'()')+" end)()";
          scope.busy=true; bngApi.engineLua(code,function(){if(alive)scope.$evalAsync(function(){scope.busy=false;refresh();});});
        };
        scope.$on('ACNGWeekend',function(_,s){if(alive)scope.$evalAsync(function(){scope.w=s;});});
        var poll=$interval(refresh,1000);scope.$on('$destroy',function(){alive=false;$interval.cancel(poll);});refresh();
      }
    };
  }]);
})();
