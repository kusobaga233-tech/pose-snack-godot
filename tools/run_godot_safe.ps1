param(
    [string]$ProjectPath = "D:\CODEX-PROJ\yoodou\pose-snake-godot",
    [string]$Script = "res://tests/run_all.gd",
    [int]$TimeoutSeconds = 240,
    [string]$Label = "godot-run"
)

# Runs a headless Godot script under a hard timeout at idle CPU priority.
#
# Why: Godot's Windows binary is a GUI-subsystem executable, so `& godot ...`
# returns immediately and its output cannot be captured. Several of these left
# running in parallel have frozen this machine before, so every heavyweight
# Godot invocation goes through this runner: one process, idle priority, hard
# timeout, output captured to a file.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$Godot = "D:\godot-proj\Godot_v4.6.3-stable_win64.exe"
if (-not (Test-Path -LiteralPath $Godot)) { throw "godot not found: $Godot" }
if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "project not found: $ProjectPath" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $ProjectPath "evidence"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stdout = Join-Path $logDir "$Label-$stamp.out.txt"
$stderr = Join-Path $logDir "$Label-$stamp.err.txt"

Write-Host "[safe] $Label -> $Script (timeout ${TimeoutSeconds}s, idle priority)"
$process = Start-Process -FilePath $Godot `
    -ArgumentList '--headless', '--path', $ProjectPath, '--script', $Script `
    -PassThru -NoNewWindow `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr

try { $process.PriorityClass = 'Idle' } catch { }

$timedOut = $false
try {
    Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
} catch {
    $timedOut = $true
    Write-Host "[safe] TIMEOUT after ${TimeoutSeconds}s — killing pid $($process.Id)"
    try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { }
    Start-Sleep -Milliseconds 400
}

$exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
Write-Host "[safe] exit=$exitCode  log=$stdout"
Write-Host "----- output tail -----"
Get-Content -LiteralPath $stdout -Tail 40 -ErrorAction SilentlyContinue
$errTail = Get-Content -LiteralPath $stderr -Tail 12 -ErrorAction SilentlyContinue
if ($errTail) { Write-Host "----- stderr tail -----"; $errTail }
exit $exitCode
