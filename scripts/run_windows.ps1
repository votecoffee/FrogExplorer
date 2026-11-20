param([switch]$WithoutRos,[switch]$WithRos,[switch]$Editor,[switch]$Smoke,[switch]$TravelSmoke,[switch]$SizeSmoke,[switch]$RideSmoke,[string]$Place="",[switch]$HostLan,[string]$JoinLan="",[int]$LanPort=24970,[int]$DomainId=79,[string]$RosPrefix="")
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
try {
 if ($UseRos -and !$JoinLan) {
  . "$PSScriptRoot\environment.ps1" -DomainId $DomainId -RosPrefix $RosPrefix -RosOverlay $RosOverlay
  $Bridge=Start-Process -FilePath $RosPython -ArgumentList @('-m','frog_explorer.bridge') -WorkingDirectory $FrogRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput "$FrogRoot\state\bridge.log" -RedirectStandardError "$FrogRoot\state\bridge_errors.log"
 }
 & $EnginePython "$PSScriptRoot\wait_engine.py" --log "$FrogRoot\state\import.log" -- $Godot --headless --editor --path $GamePath --import
 if ($LASTEXITCODE -ne 0) { throw "Game asset import failed; see state/import.log" }
 if ($Bridge -and $Bridge.HasExited) { throw "ROS bridge stopped; see state/bridge_errors.log" }
 $GameArgs=@('--path',$GamePath)
 $UserArgs=@()
 if ($Editor) { $GameArgs+=@('--editor') }
 if ($Smoke -or $TravelSmoke -or $SizeSmoke -or $RideSmoke) {
  $CheckMode=if ($RideSmoke) { '--ride-smoke' } elseif ($SizeSmoke) { '--size-smoke' } elseif ($TravelSmoke) { '--travel-smoke' } else { '--smoke' }
  $GameArgs+=@('--headless');$UserArgs+=$CheckMode
  if ($UseRos) { $UserArgs+=@('--require-ros') }
 }
 if ($Place -and !($Smoke -or $TravelSmoke -or $SizeSmoke -or $RideSmoke)) {
  if ($Place -notmatch '^[a-z][a-z0-9_]{0,79}$') { throw "Use an installed place ID for -Place." }
  $UserArgs+="--place=$Place"
 }
 if ($HostLan) { $UserArgs+="--host=$LanPort" }
 if ($JoinLan) { $UserArgs+=@("--join=$JoinLan",'--no-ros') }
 if (!$UseRos -or $JoinLan) { $UserArgs+='--no-ros' }
 if ($UserArgs.Count) { $GameArgs+=@('--')+$UserArgs }
 Write-Host "Starting FrogExplorer. Close the game window to stop its ROS bridge."
 & $EnginePython "$PSScriptRoot\wait_engine.py" --log "$FrogRoot\state\game.log" -- $Godot @GameArgs
 if ($LASTEXITCODE -ne 0) { throw "Game exited with an error; see state/game.log" }
} finally {
 if ($Bridge -and !$Bridge.HasExited) { Stop-Process -Id $Bridge.Id -ErrorAction SilentlyContinue }
}
