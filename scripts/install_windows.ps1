param([string]$GodotPath="",[switch]$SkipDownload,[string]$AssetSource="",[string]$RosPrefix="",[string]$RosPython="",[switch]$WithRos,[switch]$BuildRos,[switch]$Test)
$ErrorActionPreference="Stop"
$PythonCommand=Get-Command python -ErrorAction SilentlyContinue
if (!$PythonCommand) { throw "Install Python 3.10+ and make python available on PATH." }
$Arguments=@((Join-Path $PSScriptRoot 'bootstrap.py'))
if ($GodotPath) { $Arguments+=@('--godot',$GodotPath) }
if ($SkipDownload) { $Arguments+='--skip-download' }
if ($AssetSource) { $Arguments+=@('--asset-source',$AssetSource) }
if ($RosPrefix) { $Arguments+=@('--ros-prefix',$RosPrefix) }
if ($RosPython) { $Arguments+=@('--ros-python',$RosPython) }
if ($WithRos) { $Arguments+='--with-ros' }
if ($BuildRos) { $Arguments+='--build-ros' }
if ($Test) { $Arguments+='--test' }
& $PythonCommand.Source @Arguments
if ($LASTEXITCODE -ne 0) { throw "Installation failed. See the error above and state/ logs." }
