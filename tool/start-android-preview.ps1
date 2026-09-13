param(
  [string]$Avd = 'Medium_Phone_API_36.1',
  [string]$Sdk = "$env:LOCALAPPDATA\Android\Sdk",
  [switch]$ShowWindow
)
$ErrorActionPreference = 'Stop'
$emulator = Join-Path $Sdk 'emulator\emulator.exe'
$adb = Join-Path $Sdk 'platform-tools\adb.exe'
if (!(Test-Path -LiteralPath $emulator) -or !(Test-Path -LiteralPath $adb)) {
  throw "Android SDK tools not found in $Sdk"
}
$available = & $emulator -list-avds
if ($LASTEXITCODE -ne 0 -or $Avd -notin $available) { throw "Unknown AVD: $Avd" }
$devices = & $adb devices
if ($devices -match '^emulator-\d+\s') {
  Write-Output 'An emulator is already registered with ADB. Keeping it and its data intact.'
  return
}
$previewRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logs = Join-Path $previewRoot 'output\android'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
# Observed workaround for qemu 0xc0000005 on this Windows GPU setup.
# Keep the data partition; neither load nor save the unstable quick-boot snapshot.
$argsList = @('-avd', $Avd, '-no-snapshot-load', '-no-snapshot-save', '-gpu', 'host', '-feature', '-Vulkan', '-memory', '4096', '-cores', '4', '-no-boot-anim')
$style = if ($ShowWindow) { 'Normal' } else { 'Hidden' }
$process = Start-Process -FilePath $emulator -ArgumentList $argsList -WindowStyle $style -PassThru -RedirectStandardOutput (Join-Path $logs "$stamp-emulator.stdout.log") -RedirectStandardError (Join-Path $logs "$stamp-emulator.stderr.log")
Write-Output "Emulator launcher PID: $($process.Id). Check 'adb devices' before installing the local APK."
