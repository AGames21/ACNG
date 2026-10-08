$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$paths=Get-Content (Join-Path $repo '.local/paths.json') -Raw|ConvertFrom-Json
$old=Get-Content (Join-Path $repo '.local/road-lab.json') -Raw|ConvertFrom-Json
$proc=Get-CimInstance Win32_Process -Filter "ProcessId = $($old.pid)"
$parent=Split-Path $old.profile -Parent
if($proc){
  if($proc.Name -ne 'BeamNG.drive.x64.exe' -or !$proc.CommandLine.Contains($parent)){throw 'Cannot verify owned lab'}
  $p=Get-Process -Id $old.pid;$null=$p.CloseMainWindow()
  if(!$p.WaitForExit(10000)){Stop-Process -Id $old.pid;$null=$p.WaitForExit(10000)}
}
if(Get-Process -Name 'BeamNG.drive.x64' -ErrorAction SilentlyContinue){throw 'Another game instance is running'}
$profile=Join-Path (Split-Path (Split-Path $paths.lab_user -Parent) -Parent) ('ACNG-roadplay-'+(Get-Date -Format 'yyyyMMddHHmmss')+'/current')
& (Join-Path $paths.toolchain 'Scripts/python.exe') (Join-Path $repo 'scripts/deploy.py') --user $profile
if($LASTEXITCODE -ne 0){throw 'Deployment failed'}
$harness=Join-Path $profile 'mods/unpacked/acng_roadplay';New-Item -ItemType Directory $harness -Force|Out-Null
Copy-Item -Path (Join-Path $repo 'tests/beamng-roadplay/*') -Destination $harness -Recurse
$env:SteamAppId='284160'
$p=Start-Process (Join-Path $paths.beamng 'Bin64/BeamNG.drive.x64.exe') -ArgumentList @('-userpath',(Split-Path $profile -Parent)) -WorkingDirectory $paths.beamng -WindowStyle Hidden -PassThru
@{profile=$profile;pid=$p.Id;start=$p.StartTime.ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $repo '.local/road-playtest.json') -Encoding utf8
Write-Output ('Road playtest PID '+$p.Id+' '+$profile)
