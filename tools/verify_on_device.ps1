# Installs the exported APK on the Youdoo device, launches it, and captures the
# evidence required for workstream A (logcat + screenshot + granted permissions).
#
# Usage:
#   powershell -NoProfile -File tools\verify_on_device.ps1 -Serial YDG01010000063
#
# Notes from the environment brief:
#  * the device screen sleeps, so screen-on and wake are forced first;
#  * the com.youdoo.settings overlay ("主遥控器失去连接") steals focus and pauses
#    the app, so it is stopped before the run;
#  * adb's server is not persistent here (it is re-created per shell), so the
#    server is started and TCP transports reconnected on every run.

param(
    [string] $Serial = '172.28.252.150:5555',
    [string] $Apk = '',
    [string] $EvidenceDir = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adb = 'D:\platform-tools\adb.exe'
if ($Apk -eq '') { $Apk = Join-Path $root 'build\PoseSnake.apk' }
if ($EvidenceDir -eq '') { $EvidenceDir = Join-Path $root 'evidence' }
if (-not (Test-Path $Apk)) { throw "Missing apk: $Apk" }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

# adb writes progress/banners to stderr; with $ErrorActionPreference='Stop' that
# would abort on harmless output, so every adb call runs with 'Continue' and its
# exit code is checked by the caller when it matters.
function Invoke-Adb {
    param([string[]] $Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $adb @Arguments 2>&1
        $script:adbExitCode = $LASTEXITCODE
        return $output
    } finally {
        $ErrorActionPreference = $previous
    }
}

function AdbShell {
    param([string] $Command)
    return Invoke-Adb @('-s', $Serial, 'shell', $Command)
}

Write-Host "== device $Serial =="
Invoke-Adb @('start-server') | Out-Null
if ($Serial -match ':') {
    Invoke-Adb @('connect', $Serial) | Out-Null
    Start-Sleep -Seconds 2
}
$state = (Invoke-Adb @('-s', $Serial, 'get-state')) -join ' '
if ($state -notmatch 'device') { throw "Device $Serial not reachable: $state" }

AdbShell 'svc power stayon true' | Out-Null
AdbShell 'input keyevent KEYCODE_WAKEUP' | Out-Null
AdbShell 'am force-stop com.youdoo.settings' | Out-Null
Start-Sleep -Seconds 1

Write-Host "== install =="
$install = Invoke-Adb @('-s', $Serial, 'install', '-r', '-t', $Apk)
$install | ForEach-Object { Write-Host $_ }
if (($install -join ' ') -notmatch 'Success') { throw "Install failed: $($install -join ' ')" }

Write-Host "== launcher component =="
$component = (AdbShell 'cmd package resolve-activity --brief com.youdoo.posesnake' | Select-Object -Last 1).Trim()
Write-Host $component
if ($component -notmatch '/') { throw "Could not resolve launcher: $component" }

Write-Host "== granted SDK permission =="
AdbShell 'dumpsys package com.youdoo.posesnake' |
    Select-String -Pattern 'com.sdt.game.service.ACCESS|versionName' |
    ForEach-Object { Write-Host $_ }

Write-Host "== start app =="
Invoke-Adb @('-s', $Serial, 'logcat', '-c') | Out-Null
AdbShell "am start -n $component" | Out-Null

Write-Host "== waiting for frames =="
Start-Sleep -Seconds 15

$logcatPath = Join-Path $EvidenceDir 'device-logcat.txt'
# GodotRemoteInput is the native RCU hook (android/build-overrides/.../GodotApp.java);
# without it a physical-remote press looks identical to "no input at all".
(Invoke-Adb @('-s', $Serial, 'logcat', '-d', '-s', 'GodotRemoteInput', 'YoudooSkeleton', 'godot')) |
    Set-Content -Path $logcatPath
Write-Host "logcat -> $logcatPath"

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$shotPath = Join-Path $EvidenceDir ("screenshot-$stamp.png")
# cmd handles the binary redirect; PowerShell would re-encode the stream.
cmd /c "`"$adb`" -s $Serial exec-out screencap -p > `"$shotPath`""
Write-Host "screenshot -> $shotPath"

Write-Host "== logcat tail =="
Get-Content $logcatPath | Select-Object -Last 25
