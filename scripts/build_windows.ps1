param([int]$DomainId=79,[string]$RosPrefix="",[switch]$Test)
. "$PSScriptRoot\environment.ps1" -DomainId $DomainId -RosPrefix $RosPrefix
$Workspace=Resolve-FrogRosWorkspace
$Arguments=@("$PSScriptRoot\build_ros_windows.py",$Workspace)
if ($Test) { $Arguments+='--test' }
& $RosPython @Arguments
if ($LASTEXITCODE -ne 0) { throw 'ROS workspace build or tests failed.' }
