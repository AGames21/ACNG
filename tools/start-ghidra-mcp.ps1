param([int]$Port=8089)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$workspace=Split-Path (Split-Path $repoRoot -Parent) -Parent
$paths=Get-Content (Join-Path $repoRoot '.local\paths.json') -Raw | ConvertFrom-Json
$extension=Join-Path $workspace 'work\native-tools\ghidra-mcp-extension\GhidraMCP\lib'
$jars=@(Get-ChildItem $extension -Filter '*.jar' -File | ForEach-Object {$_.FullName})
foreach($part in @('Framework','Features','Processors')){
  $jars+=Get-ChildItem (Join-Path $paths.ghidra ('Ghidra\'+$part+'\*\lib\*.jar')) -File | ForEach-Object {$_.FullName}
}
if(!$jars.Count){throw 'MCP extension and Ghidra jars not located'}
$argsPath=Join-Path $repoRoot '.local\ghidra-server.args'
# Java argfiles require forward slashes to avoid backslash escape interpretation.
@('-Djava.awt.headless=true',('-Dghidra.home='+$paths.ghidra).Replace('\','/'),'-classpath',
  ('"'+(($jars -join ';').Replace('\','/'))+'"'),'com.xebyte.headless.GhidraMCPHeadlessServer',
  '--port',"$Port",'--bind','127.0.0.1') | Set-Content $argsPath -Encoding ASCII
$proc=Start-Process -FilePath (Join-Path $paths.java 'bin\java.exe') -ArgumentList ('@'+$argsPath.Replace('\','/')) -WindowStyle Hidden -PassThru
Write-Output ('Ghidra MCP loopback server PID '+$proc.Id+'; verify /check_connection before importing anything.')
