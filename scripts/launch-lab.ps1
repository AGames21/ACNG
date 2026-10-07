param([ValidateSet('Smoke','Benchmark','Lifecycle','Repeats')][string]$Experiment='Smoke',[string]$LabUser)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$paths=Get-Content (Join-Path $repoRoot '.local\paths.json') -Raw | ConvertFrom-Json
if(Get-Process -Name 'BeamNG.drive.x64' -ErrorAction SilentlyContinue){throw 'Close the running BeamNG instance before starting another experiment.'}
$labCurrent=[IO.Path]::GetFullPath($(if($LabUser){$LabUser}else{$paths.lab_user}))
$labParent=Split-Path $labCurrent -Parent
if($labCurrent -eq [IO.Path]::GetFullPath($paths.beamng_user)){throw 'Experiment profile must differ from stock user profile.'}
& python (Join-Path $PSScriptRoot 'deploy.py') --user $labCurrent
if($LASTEXITCODE -ne 0){throw 'ACNG deployment failed'}
$experimentKey=$Experiment.ToLowerInvariant()
$testName='beamng-'+$experimentKey
$modName='acng_'+$experimentKey
$target=Join-Path $labCurrent ('mods\unpacked\'+$modName)
$source=Join-Path $repoRoot ('tests\'+$testName)
New-Item -ItemType Directory -Force $target | Out-Null
Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
  $relative=$_.FullName.Substring($source.Length+1)
  $destination=Join-Path $target $relative
  New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
  Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
}
# Reject conflicting test mods rather than deleting user content.
foreach($other in @('acng_smoke','acng_benchmark','acng_lifecycle','acng_repeats')){
  if($other -ne $modName -and (Test-Path (Join-Path $labCurrent ('mods\unpacked\'+$other)))){throw 'Use a fresh lab profile per experiment; conflicting test harness present.'}
}
$exe=Join-Path $paths.beamng 'Bin64\BeamNG.drive.x64.exe'
$env:SteamAppId='284160'
# Avoid -windowed: local BeamNG 0.39.4 handler calls an unavailable setFullScreen global.
if($labParent -match '\s'){throw 'Use a whitespace-free isolated profile path for this local launch parser.'}
$proc=Start-Process -FilePath $exe -ArgumentList @('-userpath',$labParent) -WorkingDirectory $paths.beamng -WindowStyle Hidden -PassThru
Write-Output ('Started '+$Experiment+' in isolated profile, PID '+$proc.Id)
