param([switch]$CloseOwned,[switch]$RoadOnly)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$paths=Get-Content (Join-Path $repo '.local/paths.json') -Raw | ConvertFrom-Json
$record=Join-Path $repo '.local/road-lab.json'
if($CloseOwned){
  foreach($previous in @($record,(Join-Path $repo '.local/control-lab.json'))){
  if(Test-Path $previous){
    $old=Get-Content $previous -Raw|ConvertFrom-Json
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId = $($old.pid)"
    $parent=Split-Path $old.profile -Parent
    if($proc){
      if($proc.Name -ne 'BeamNG.drive.x64.exe' -or !$proc.CommandLine -or !$proc.CommandLine.Replace('\','/').ToLowerInvariant().Contains($parent.Replace('\','/').ToLowerInvariant())){throw 'Cannot verify owned process'}
      $p=Get-Process -Id $old.pid;$null=$p.CloseMainWindow()
      if(!$p.WaitForExit(10000)){Stop-Process -Id $old.pid;if(!$p.WaitForExit(10000)){throw 'Owned process still running'}}
    }
  }
  }
}
if(Get-Process -Name 'BeamNG.drive.x64' -ErrorAction SilentlyContinue){throw 'Another game instance is running'}
$profile=Join-Path (Split-Path (Split-Path $paths.lab_user -Parent) -Parent) ('ACNG-road-'+(Get-Date -Format 'yyyyMMddHHmmss')+'/current')
& (Join-Path $paths.toolchain 'Scripts/python.exe') (Join-Path $repo 'scripts/deploy.py') --user $profile
if($LASTEXITCODE -ne 0){throw 'Deploy failed'}
$harness=Join-Path $profile 'mods/unpacked/acng_roadlab';New-Item -ItemType Directory $harness -Force|Out-Null
Copy-Item -Path (Join-Path $repo 'tests/beamng-roadlab/*') -Destination $harness -Recurse
if($RoadOnly){[IO.File]::WriteAllText((Join-Path $harness 'scripts/acng_roadlab/modScript.lua'), "rawset(_G,'ACNG_ROAD_ONLY',true)`nextensions.load('acng_roadlab')`n",(New-Object Text.UTF8Encoding($false)))}
$env:SteamAppId='284160'
$p=Start-Process (Join-Path $paths.beamng 'Bin64/BeamNG.drive.x64.exe') -ArgumentList @('-userpath',(Split-Path $profile -Parent)) -WorkingDirectory $paths.beamng -WindowStyle Hidden -PassThru
@{profile=$profile;pid=$p.Id;start=$p.StartTime.ToString('o')}|ConvertTo-Json|Set-Content $record -Encoding utf8
Write-Output ('FR001 PID '+$p.Id+' '+$profile)
