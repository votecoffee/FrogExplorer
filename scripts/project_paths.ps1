$FrogRoot=Split-Path -Parent $PSScriptRoot
$FrogSettings=@{}
$SettingsPath=Join-Path $FrogRoot '.local\settings.json'
if (Test-Path -LiteralPath $SettingsPath) {
 $LoadedSettings=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
 foreach ($SettingProperty in $LoadedSettings.PSObject.Properties) { $FrogSettings[$SettingProperty.Name]=$SettingProperty.Value }
}
function Resolve-FrogGodot {
 if ($env:GODOT_BIN) { return $env:GODOT_BIN }
 if ($FrogSettings['godot']) { return $FrogSettings['godot'] }
 $FromPath=Get-Command godot4,godot -ErrorAction SilentlyContinue | Select-Object -First 1
 if ($FromPath) { return $FromPath.Source }
 throw 'Run scripts/install_windows.ps1 first, or set GODOT_BIN to your Godot 4.7+ executable.'
}
function Resolve-FrogRosWorkspace {
 param([string]$Workspace=$FrogSettings['ros_workspace'])
 if (!$Workspace) { $Workspace='ros2_ws' }
 if (![IO.Path]::IsPathRooted($Workspace)) { $Workspace=Join-Path $FrogRoot $Workspace }
 return [IO.Path]::GetFullPath($Workspace)
}
