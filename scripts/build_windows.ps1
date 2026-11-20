param([int]$DomainId=79,[string]$RosPrefix="",[switch]$Test)
. "$PSScriptRoot\environment.ps1" -DomainId $DomainId -RosPrefix $RosPrefix
$Workspace=Resolve-FrogRosWorkspace
$Source=Join-Path $FrogRoot 'ros2_ws\src'
New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
Push-Location -LiteralPath $Workspace
try {
 & $RosPython -m colcon build --base-paths $Source --merge-install --event-handlers console_direct+
 if ($LASTEXITCODE -ne 0) { throw "ROS workspace build failed" }
 if ($Test) {
  & $RosPython -m colcon test --base-paths $Source --merge-install --event-handlers console_direct+
  if ($LASTEXITCODE -ne 0) { throw "ROS tests failed" }
  & $RosPython -m colcon test-result --verbose
  if ($LASTEXITCODE -ne 0) { throw "ROS test results contain failures" }
 }
} finally { Pop-Location }
