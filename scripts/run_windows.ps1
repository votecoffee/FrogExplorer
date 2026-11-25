param([switch]$WithoutRos,[switch]$WithRos,[switch]$Editor,[switch]$Smoke,[switch]$TravelSmoke,[switch]$SizeSmoke,[switch]$RideSmoke,[string]$Place="",[switch]$HostLan,[string]$JoinLan="",[int]$LanPort=24970,[int]$DomainId=79,[string]$RosPrefix="",[switch]$ImportAssets)
$ErrorActionPreference="Stop"
. "$PSScriptRoot\project_paths.ps1"
$Godot=Resolve-FrogGodot
$EnginePython=(Get-Command python -ErrorAction Stop).Source
$UseRos=(!$WithoutRos -and ($WithRos -or $FrogSettings['use_ros']))
if ($WithRos -and $WithoutRos) { throw "Choose WithRos or WithoutRos." }
$Bridge=$null
New-Item -ItemType Directory -Path "$FrogRoot\state" -Force | Out-Null
if (!(Test-Path -LiteralPath $Godot)) { throw "Set GODOT_BIN to a Godot 4 executable." }
if ($HostLan -and $JoinLan) { throw "Choose HostLan or JoinLan." }
if (($HostLan -or $JoinLan) -and ($Smoke -or $SizeSmoke -or $TravelSmoke -or $RideSmoke)) { throw "Run acceptance checks without HostLan or JoinLan." }
if ($LanPort -lt 1024 -or $LanPort -gt 65535) { throw "LanPort must be 1024-65535." }
$RunSmoke=$Smoke -or $TravelSmoke -or $SizeSmoke -or $RideSmoke
if ($Place -and !$RunSmoke -and $Place -notmatch '^[a-z][a-z0-9_]{0,79}$') { throw "Use an installed place ID for -Place." }
$GamePath=Join-Path $FrogRoot 'game'
$RosOverlay=""
if ($FrogSettings['ros_workspace'] -and !$Editor) {
 $RosOverlay=Join-Path (Resolve-FrogRosWorkspace) 'install'
 $GamePath=Join-Path $RosOverlay 'share\frog_explorer\game'
 if (!(Test-Path -LiteralPath (Join-Path $GamePath 'project.godot') -PathType Leaf)) {
  throw "Build the configured ROS workspace before launching its installed game: $RosOverlay"
 }
 New-Item -ItemType Directory -Path (Join-Path (Split-Path -Parent $GamePath) 'state') -Force | Out-Null
}
$StatePath=Join-Path $FrogRoot 'state'
Write-Host "Checking FrogExplorer assets..."
$PrepareArgs=@($Godot,$GamePath,(Join-Path $StatePath 'import.log'))
if ($ImportAssets) { $PrepareArgs+='--import-assets' }
& $EnginePython "$PSScriptRoot\prepare_windows_game.py" @PrepareArgs
if ($LASTEXITCODE -ne 0) { throw "Game asset import failed. See $StatePath\import.log" }
try {
 if ($UseRos -and !$JoinLan) {
  if (Get-NetUDPEndpoint -LocalPort 17776 -ErrorAction SilentlyContinue | Where-Object { $_.LocalAddress -in '127.0.0.1','0.0.0.0' }) {
   throw "ROS bridge port 17776 is already in use. Close the other FrogExplorer session or use -WithoutRos."
  }
  Write-Host "Starting the ROS bridge..."
  . "$PSScriptRoot\environment.ps1" -DomainId $DomainId -RosPrefix $RosPrefix -RosOverlay $RosOverlay
  $BridgeOutput=Join-Path $StatePath 'bridge.log'
  $BridgeErrors=Join-Path $StatePath 'bridge_errors.log'
  $Bridge=Start-Process -FilePath $RosPython -ArgumentList @('-u','-m','frog_explorer.bridge') -WorkingDirectory $FrogRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $BridgeOutput -RedirectStandardError $BridgeErrors
  $Waiting=[Diagnostics.Stopwatch]::StartNew()
  do {
   if ($Bridge.HasExited) { throw "ROS bridge stopped during startup. See $BridgeErrors" }
   if ($Waiting.Elapsed.TotalSeconds -ge 95) { throw "ROS bridge startup timed out. See $BridgeErrors" }
   $Ready=Select-String -LiteralPath $BridgeErrors,$BridgeOutput -SimpleMatch 'FrogExplorer bridge ready' -Quiet
   if (!$Ready) { Start-Sleep -Milliseconds 200 }
  } until ($Ready)
 }
 $GameArgs=@('--path',$GamePath)
 $UserArgs=@()
 if ($Editor) { $GameArgs+=@('--editor') }
 if ($RunSmoke) {
  $CheckMode=if ($RideSmoke) { '--ride-smoke' } elseif ($SizeSmoke) { '--size-smoke' } elseif ($TravelSmoke) { '--travel-smoke' } else { '--smoke' }
  $GameArgs+=@('--headless');$UserArgs+=@($CheckMode,'--test-session')
  if ($UseRos) { $UserArgs+=@('--require-ros') }
 }
 if ($Place -and !$RunSmoke) {
  $UserArgs+="--place=$Place"
 }
 if ($HostLan) { $UserArgs+="--host=$LanPort" }
 if ($JoinLan) { $UserArgs+=@("--join=$JoinLan",'--no-ros') }
 if (!$UseRos -or $JoinLan) { $UserArgs+='--no-ros' }
 if ($UserArgs.Count) { $GameArgs+=@('--')+$UserArgs }
 Write-Host "Starting FrogExplorer."
 $GameLog=Join-Path $StatePath 'game.log'
 & $EnginePython "$PSScriptRoot\wait_engine.py" --log $GameLog -- $Godot @GameArgs
 if ($LASTEXITCODE -ne 0) { throw "Game exited with an error. See $GameLog" }
} finally {
 if ($Bridge -and !$Bridge.HasExited) { Stop-Process -Id $Bridge.Id -ErrorAction SilentlyContinue }
}
