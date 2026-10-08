param([switch]$CloseOwned,[switch]$Play)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$paths=Get-Content (Join-Path $repo '.local/paths.json') -Raw | ConvertFrom-Json
$record=Join-Path $repo '.local/weekend-lab.json'
if($CloseOwned -and (Test-Path $record)){
  $old=Get-Content $record -Raw | ConvertFrom-Json
  $proc=Get-CimInstance Win32_Process -Filter "ProcessId = $($old.pid)"
  $parent=Split-Path $old.profile -Parent
  if($proc){
    if($proc.Name -ne 'BeamNG.drive.x64.exe' -or !$proc.CommandLine -or !$proc.CommandLine.Replace('\','/').ToLowerInvariant().Contains($parent.Replace('\','/').ToLowerInvariant())){throw 'Unable to verify owned game process.'}
    $gameProc=Get-Process -Id $old.pid
    $null=$gameProc.CloseMainWindow()
    if(!$gameProc.WaitForExit(10000)){Stop-Process -Id $old.pid;if(!$gameProc.WaitForExit(10000)){throw 'Owned process did not exit.'}}
  }
}
if(Get-Process -Name 'BeamNG.drive.x64' -ErrorAction SilentlyContinue){throw 'Another BeamNG instance is running.'}
$profile=Join-Path (Split-Path (Split-Path $paths.lab_user -Parent) -Parent) ('ACNG-weekend-'+(Get-Date -Format 'yyyyMMddHHmmss')+'/current')
$python=Join-Path $paths.toolchain 'Scripts/python.exe'
& $python (Join-Path $repo 'scripts/deploy.py') --user $profile
if($LASTEXITCODE -ne 0){throw 'Deploy failed'}
$experiment=if($Play){'weekendplay'}else{'weekendlab'}
$harness=Join-Path $profile ('mods/unpacked/acng_'+$experiment)
New-Item -ItemType Directory -Path $harness -Force | Out-Null
Copy-Item -Path (Join-Path $repo ('tests/beamng-'+$experiment+'/*')) -Destination $harness -Recurse
$env:SteamAppId='284160'
$proc=Start-Process -FilePath (Join-Path $paths.beamng 'Bin64/BeamNG.drive.x64.exe') -ArgumentList @('-userpath',(Split-Path $profile -Parent)) -WorkingDirectory $paths.beamng -WindowStyle Hidden -PassThru
@{profile=$profile;pid=$proc.Id;start=$proc.StartTime.ToString('o')} | ConvertTo-Json | Set-Content $record -Encoding utf8
Write-Output ('RW001 PID '+$proc.Id+' '+$profile)
