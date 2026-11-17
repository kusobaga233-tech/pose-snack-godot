param(
    [int]$PerSuiteTimeoutSeconds = 60,
    [string[]]$Suites = @(
        "res://tests/suite_config.gd",
        "res://tests/suite_input.gd",
        "res://tests/suite_snake.gd",
        "res://tests/suite_collisions.gd",
        "res://tests/suite_round.gd",
        "res://tests/suite_ai.gd",
        "res://tests/suite_determinism.gd"
    )
)

# Sequentially runs each core suite with a hard per-suite timeout.
# One Godot process at a time, below-normal priority: this machine freezes when
# several headless runs overlap, and one earlier suite had an infinite loop.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$project = "D:\CODEX-PROJ\yoodou\pose-snake-godot"
$godot = "D:\godot-proj\Godot_v4.6.3-stable_win64.exe"
$logDir = Join-Path $project "evidence\suites"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$results = @()
foreach ($suite in $Suites) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($suite)
    $out = Join-Path $logDir "$name.out.txt"
    $err = Join-Path $logDir "$name.err.txt"
    Write-Host "[suite] $name ..." -NoNewline

    $proc = Start-Process -FilePath $godot `
        -ArgumentList '--headless', '--path', $project, '--script', 'res://tests/run_one.gd', '--', $suite `
        -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    try { $proc.PriorityClass = 'BelowNormal' } catch { }

    $timedOut = $false
    try { Wait-Process -Id $proc.Id -Timeout $PerSuiteTimeoutSeconds -ErrorAction Stop }
    catch {
        $timedOut = $true
        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
        Start-Sleep -Milliseconds 300
    }

    $text = Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue
    $resultLine = ""
    if ($text -and $text -match 'RESULT:\s*(PASS|FAIL)[^\r\n]*') { $resultLine = $Matches[0].Trim() }
    $state = if ($timedOut) { "TIMEOUT" }
             elseif ($resultLine -match '^RESULT:\s*FAIL') { "FAIL" }
             elseif ($resultLine -match '^RESULT:\s*PASS') { "PASS" }
             else { "NO-RESULT" }
    Write-Host " $state  $resultLine"
    $results += [pscustomobject]@{ suite = $name; state = $state; detail = $resultLine }
}

Write-Host ""
Write-Host "===== suite summary ====="
$results | Format-Table -AutoSize
if ($results | Where-Object { $_.state -ne "PASS" }) { exit 1 } else { exit 0 }
