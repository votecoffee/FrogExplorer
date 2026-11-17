param([int]$DomainId=79,[string]$RosPrefix="",[string]$RosPython="")
$ErrorActionPreference="Stop"
. "$PSScriptRoot\project_paths.ps1"
if (!$RosPrefix) { $RosPrefix=if ($env:ROS_PREFIX) { $env:ROS_PREFIX } else { $FrogSettings['ros_prefix'] } }
if (!$RosPrefix -or !(Test-Path -LiteralPath (Join-Path $RosPrefix 'local_setup.ps1'))) { throw 'Set -RosPrefix or configure an existing ROS 2 Lyrical underlay with the installer.' }
if (!$RosPython) { $RosPython=if ($env:ROS_PYTHON) { $env:ROS_PYTHON } else { $FrogSettings['ros_python'] } }
if (!$RosPython) {
 $Candidates=@((Join-Path $RosPrefix '.pixi\envs\default\python.exe'),(Join-Path $RosPrefix 'python.exe'))
 $RosPython=$Candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$RosPython) { $ActivePython=Get-Command python -ErrorAction SilentlyContinue; if ($ActivePython) { $RosPython=$ActivePython.Source } }
if (!$RosPython -or !(Test-Path -LiteralPath $RosPython)) { throw 'Set -RosPython to the Python interpreter belonging to the ROS installation.' }
$RosEnvironment=Split-Path -Parent $RosPython
$env:PATH="$RosEnvironment;$RosEnvironment\Scripts;$RosEnvironment\Library\bin;$env:PATH"
$env:COLCON_PYTHON_EXECUTABLE=$RosPython
$env:ROS_DOMAIN_ID="$DomainId"
$env:ROS_AUTOMATIC_DISCOVERY_RANGE="LOCALHOST"
$env:ROS_HOME=Join-Path $FrogRoot 'state\ros'
$env:ROS_LOG_DIR=Join-Path $FrogRoot 'state\ros\log'
New-Item -ItemType Directory -Path $env:ROS_LOG_DIR -Force | Out-Null
. (Join-Path $RosPrefix 'local_setup.ps1')
& $RosPython -c 'import rclpy' 2>$null
if ($LASTEXITCODE -ne 0) { throw 'The configured Python cannot import rclpy. Configure the ROS interpreter with -RosPython.' }
$env:PYTHONPATH="$(Join-Path $FrogRoot 'ros2_ws\src\frog_explorer');$env:PYTHONPATH"
$Godot=Resolve-FrogGodot
$env:GODOT_BIN=$Godot
