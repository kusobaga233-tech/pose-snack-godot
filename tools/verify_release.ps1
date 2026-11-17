# tools/verify_release.ps1
#
# POSE SNAKE - release verification gate (Godot port).
#
# One command, no arguments:
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_release.ps1
#
# BUILD ONLY. This script never runs adb and never touches the Android box. It
# verifies, on this PC, everything that can be verified on this PC:
#
#   1 parse/compile every *.gd under src/, scenes/, tests/
#   2 headless boot: exit 0, stderr 0 bytes, no ERROR/WARNING/SCRIPT ERROR
#   3 logic suite: res://tests/run_all.gd -> RESULT: PASS, 0 failures
#   4 resource integrity: character folders/atlases/imports, the generated skin
#     table, the boot [skin] line, and "no load error" across every run
#   5 render coverage: 1P flow + 2P split at 1920x1080, non-flat frames
#   6 perf budget: 1P play draw calls <= 200 (2P reported)
#   7 determinism: two fixed-fps 1P captures are byte-identical (SHA256)
#   8 skin coverage: >=2 distinct character skins visible in one play frame
#   9 stress guard: the 2P worst-case capture (8 snakes x 240 segments, food cap,
#     FX pools at cap, perf panel on) must stay under 300 draw calls and over
#     45 fps, and the 1P worst case under 200 draw / over 50 fps
#
# It prints a PASS/FAIL table, writes the full log to
# evidence\release-gate-<timestamp>.txt, and exits non-zero if anything fails.
#
# PowerShell 5.1 safe; ASCII only; it never rewrites project sources (no
# Get-Content/Set-Content round trip). Godot is ASCII-invoked one process at a
# time with a hard timeout; a timed-out run is killed.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Drawing

$Project = Split-Path -Parent $PSScriptRoot
$EvidenceDir = Join-Path $Project 'evidence'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $EvidenceDir "release-gate-$Stamp.txt"
$TempDir = Join-Path $env:TEMP "pose-snake-gate-$Stamp"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
}
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$script:LogWriter = New-Object System.IO.StreamWriter($LogPath, $false, $Utf8NoBom)
$script:LogWriter.AutoFlush = $true
$script:Checks = @{}
$script:Failed = 9

function Log {
    param([string]$Text = '')
    Write-Host $Text
    if ($null -ne $script:LogWriter) { $script:LogWriter.WriteLine($Text) }
}

function Fmt {
    param([double]$Value, [string]$Format = '0.00')
    return $Value.ToString($Format, $Inv)
}

function Set-Check {
    param(
        [int]$Id,
        [string]$Name,
        [bool]$Ok,
        [string]$Reason,
        [string]$Evidence
    )
    $script:Checks[$Id] = [pscustomobject]@{
        Id = $Id; Name = $Name; Ok = $Ok; Reason = $Reason; Evidence = $Evidence
    }
}

# Defaults: if the script dies early the table still reports what did not run.
Set-Check 1 'Parse/compile'     $false 'not run' 'n/a'
Set-Check 2 'Headless boot'     $false 'not run' 'n/a'
Set-Check 3 'Logic suite'       $false 'not run' 'n/a'
Set-Check 4 'Resource integrity' $false 'not run' 'n/a'
Set-Check 5 'Render coverage'   $false 'not run' 'n/a'
Set-Check 6 'Perf budget'       $false 'not run' 'n/a'
Set-Check 7 'Determinism'       $false 'not run' 'n/a'
Set-Check 8 'Skin coverage'     $false 'not run' 'n/a'
Set-Check 9 'Stress guard'      $false 'not run' 'n/a'

# --------------------------------------------------------------------- Godot

function Find-Godot {
    $candidates = New-Object System.Collections.ArrayList
    if ($env:GODOT_BIN) { [void]$candidates.Add($env:GODOT_BIN) }
    [void]$candidates.Add('D:\godot-proj\Godot_v4.6.3-stable_win64.exe')
    if (Test-Path -LiteralPath 'D:\godot-proj') {
        $found = @(Get-ChildItem -LiteralPath 'D:\godot-proj' -Filter 'Godot*_win64.exe' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending)
        foreach ($f in $found) { [void]$candidates.Add($f.FullName) }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Quote-Arg {
    param([string]$Arg)
    if ($Arg -match '[\s"]') {
        return '"' + ($Arg -replace '"', '\"') + '"'
    }
    return $Arg
}

function Invoke-GodotRun {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$EngineArgs,
        [string[]]$UserArgs = @(),
        [int]$TimeoutSec = 180,
        [string]$OutDir = $EvidenceDir
    )

    $safe = $Label -replace '[^A-Za-z0-9._-]', '_'
    $outPath = Join-Path $OutDir ("release-gate-$Stamp-$safe.out.txt")
    $errPath = Join-Path $OutDir ("release-gate-$Stamp-$safe.err.txt")

    $parts = New-Object System.Collections.ArrayList
    foreach ($a in $EngineArgs) { [void]$parts.Add((Quote-Arg $a)) }
    if ($UserArgs.Count -gt 0) {
        [void]$parts.Add('--')
        foreach ($a in $UserArgs) { [void]$parts.Add((Quote-Arg $a)) }
    }
    $argLine = $parts -join ' '

    Log "[run] $Label : $Godot $argLine"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Godot
    $psi.Arguments = $argLine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Project

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        [System.IO.File]::WriteAllText($outPath, '', $Utf8NoBom)
        [System.IO.File]::WriteAllText($errPath, "START FAILED: $($_.Exception.Message)", $Utf8NoBom)
        return [pscustomobject]@{
            Label = $Label; Exit = -1; TimedOut = $false; Out = ''; Err = "START FAILED"
            OutPath = $outPath; ErrPath = $errPath; Seconds = 0.0
        }
    }

    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        $timedOut = $true
        Log "[run] TIMEOUT after ${TimeoutSec}s - killing pid $($proc.Id)"
        try { $proc.Kill() } catch { }
        try { [void]$proc.WaitForExit(5000) } catch { }
    }
    $sw.Stop()

    $outText = ''
    $errText = ''
    try { $outText = $outTask.Result } catch { }
    try { $errText = $errTask.Result } catch { }
    if ($null -eq $outText) { $outText = '' }
    if ($null -eq $errText) { $errText = '' }

    [System.IO.File]::WriteAllText($outPath, $outText, $Utf8NoBom)
    [System.IO.File]::WriteAllText($errPath, $errText, $Utf8NoBom)

    $exit = 124
    if (-not $timedOut) {
        try { $exit = $proc.ExitCode } catch { $exit = -2 }
    }
    try { $proc.Dispose() } catch { }

    Log ("[run] $Label done: exit=$exit stderr=" + $errText.Length + "B elapsed=" +
        (Fmt $sw.Elapsed.TotalSeconds '0.0') + "s")

    return [pscustomobject]@{
        Label = $Label; Exit = $exit; TimedOut = $timedOut; Out = $outText; Err = $errText
        OutPath = $outPath; ErrPath = $errPath; Seconds = $sw.Elapsed.TotalSeconds
    }
}

# ----------------------------------------------------------------------- PNG

function Get-PngSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $len = (Get-Item -LiteralPath $Path).Length
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 24
        $read = $fs.Read($buf, 0, 24)
    } finally {
        $fs.Dispose()
    }
    if ($read -lt 24) {
        return [pscustomobject]@{ Width = 0; Height = 0; Length = $len; SigOk = $false }
    }
    $sigOk = ($buf[0] -eq 0x89 -and $buf[1] -eq 0x50 -and $buf[2] -eq 0x4E -and $buf[3] -eq 0x47)
    if (-not $sigOk) {
        return [pscustomobject]@{ Width = 0; Height = 0; Length = $len; SigOk = $false }
    }
    $w = ([int]$buf[16] -shl 24) -bor ([int]$buf[17] -shl 16) -bor ([int]$buf[18] -shl 8) -bor [int]$buf[19]
    $h = ([int]$buf[20] -shl 24) -bor ([int]$buf[21] -shl 16) -bor ([int]$buf[22] -shl 8) -bor [int]$buf[23]
    return [pscustomobject]@{ Width = $w; Height = $h; Length = $len; SigOk = $true }
}

## Distinct sampled colour count. A uniform frame has 1; a real screen has
## thousands (anti-aliasing alone produces hundreds). Sampling every 4th pixel
## keeps this fast enough for PowerShell 5.1 while still covering the frame.
function Get-ImageStats {
    param([string]$Path)
    $bmp = $null
    try { $bmp = [System.Drawing.Bitmap]::FromFile($Path) } catch { return $null }
    $w = $bmp.Width
    $h = $bmp.Height
    $stride = 0
    $bytes = $null
    try {
        $rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $w, $h
        $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $stride = $data.Stride
            $bytes = New-Object byte[] ($stride * $h)
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        } finally {
            $bmp.UnlockBits($data)
        }
    } finally {
        $bmp.Dispose()
    }
    if ($null -eq $bytes) { return $null }
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    $step = 4
    $y = 0
    while ($y -lt $h) {
        $row = $y * $stride
        $x = 0
        while ($x -lt $w) {
            $i = $row + ($x * 4)
            $packed = ([int]$bytes[$i + 2] -shl 16) -bor ([int]$bytes[$i + 1] -shl 8) -bor [int]$bytes[$i]
            [void]$set.Add($packed)
            $x += $step
        }
        $y += $step
    }
    return [pscustomobject]@{ Width = $w; Height = $h; Distinct = $set.Count }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# ------------------------------------------------------------------- header

Log '================================================================================'
Log 'POSE SNAKE - RELEASE VERIFICATION GATE'
Log '================================================================================'
Log ("time     : " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Log ("project  : " + $Project)
Log ("log      : " + $LogPath)
Log 'mode     : build only - no adb, no Android device'
Log '================================================================================'

$Godot = Find-Godot
if (-not $Godot) {
    Log 'FATAL: no Godot 4.6 executable found (looked at $env:GODOT_BIN, D:\godot-proj).'
    $script:LogWriter.Dispose()
    exit 1
}
$godotVersion = ''
try {
    $vi = New-Object System.Diagnostics.ProcessStartInfo
    $vi.FileName = $Godot
    $vi.Arguments = '--version'
    $vi.UseShellExecute = $false
    $vi.RedirectStandardOutput = $true
    $vi.RedirectStandardError = $true
    $vi.CreateNoWindow = $true
    $vp = [System.Diagnostics.Process]::Start($vi)
    $godotVersion = $vp.StandardOutput.ReadToEnd().Trim()
    $vp.WaitForExit(15000) | Out-Null
    $vp.Dispose()
} catch { }
Log ("godot    : " + $Godot + " (" + $godotVersion + ")")
Log ''

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' })
if ($running.Count -gt 0) {
    Log ("[warn] $($running.Count) Godot process(es) already running; the gate runs its own one at a time.")
}

try {
    # ------------------------------------------------------------------ 1/8
    Log '--------------------------------------------------------------------------------'
    Log '[1/9] Parse/compile every *.gd under src/, scenes/, tests/'
    $scriptFiles = @(Get-ChildItem -Path @(
        (Join-Path $Project 'src'), (Join-Path $Project 'scenes'), (Join-Path $Project 'tests')
    ) -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue | Sort-Object FullName)
    $parseFail = New-Object System.Collections.ArrayList
    $parseDetails = New-Object System.Collections.ArrayList
    $parseDir = Join-Path $TempDir 'parse'
    New-Item -ItemType Directory -Force -Path $parseDir | Out-Null
    $pi = 0
    foreach ($f in $scriptFiles) {
        $pi++
        $rel = $f.FullName.Substring($Project.Length + 1).Replace('\', '/')
        $r = Invoke-GodotRun -Label ("parse-" + ($rel -replace '[^A-Za-z0-9._-]', '_')) `
            -EngineArgs @('--headless', '--path', $Project, '--check-only', '--script', "res://$rel") `
            -TimeoutSec 60 -OutDir $parseDir
        $errHit = ($r.Err -match '(?m)^(SCRIPT ERROR|ERROR):' -or $r.Err -match 'Parse Error')
        if ($r.TimedOut -or $r.Exit -ne 0 -or $errHit) {
            $first = ($r.Err -split '\r?\n' | Where-Object { $_.Trim() -ne '' } | Select-Object -First 2) -join ' | '
            [void]$parseFail.Add([pscustomobject]@{ Rel = $rel; Exit = $r.Exit; Err = $first })
            [void]$parseDetails.Add("FAIL $rel (exit=$($r.Exit)): $first")
        }
    }
    $parseOk = ($scriptFiles.Count -gt 0 -and $parseFail.Count -eq 0)
    if ($parseFail.Count -gt 0) {
        foreach ($d in $parseDetails) { Log $d }
        $parseEvidence = Join-Path $EvidenceDir "release-gate-$Stamp-parse-failures.txt"
        [System.IO.File]::WriteAllText($parseEvidence, ($parseDetails -join "`r`n"), $Utf8NoBom)
    } else {
        $parseEvidence = $LogPath
    }
    $parseReason = "$($scriptFiles.Count)/$($scriptFiles.Count) *.gd parse, 0 failures"
    if (-not $parseOk) {
        $parseReason = "$($parseFail.Count)/$($scriptFiles.Count) failed: " + ($parseFail[0].Rel) + " (" + $parseFail[0].Err + ")"
    }
    Set-Check 1 'Parse/compile' $parseOk $parseReason $parseEvidence
    Log ("[1/9] " + ($(if ($parseOk) { 'PASS' } else { 'FAIL' })) + " - " + $parseReason)
    Log ''

    # ------------------------------------------------------------------ 2/8
    Log '--------------------------------------------------------------------------------'
    Log '[2/9] Headless boot: --headless --quit-after 300'
    $boot = Invoke-GodotRun -Label 'boot' `
        -EngineArgs @('--headless', '--path', $Project, '--quit-after', '300') -TimeoutSec 150
    $bootErrBytes = 0
    if (Test-Path -LiteralPath $boot.ErrPath) { $bootErrBytes = (Get-Item -LiteralPath $boot.ErrPath).Length }
    $bootBadLines = @($boot.Out -split '\r?\n' | Where-Object { $_ -match '^\s*(ERROR|WARNING|SCRIPT ERROR)\b' })
    $bootOk = (-not $boot.TimedOut -and $boot.Exit -eq 0 -and $bootErrBytes -eq 0 -and $bootBadLines.Count -eq 0)
    $bootReason = "exit=$($boot.Exit) stderr=${bootErrBytes}B ERROR/WARNING lines=$($bootBadLines.Count)"
    if ($boot.TimedOut) { $bootReason = "TIMEOUT after 150s; process killed" }
    elseif ($bootOk) { $bootReason = "exit=0, stderr=0B, no ERROR/WARNING/SCRIPT ERROR lines" }
    Set-Check 2 'Headless boot' $bootOk $bootReason ($boot.OutPath + '; ' + $boot.ErrPath)
    Log ("[2/9] " + ($(if ($bootOk) { 'PASS' } else { 'FAIL' })) + " - " + $bootReason)
    Log ''

    # ------------------------------------------------------------------ 3/8
    Log '--------------------------------------------------------------------------------'
    Log '[3/9] Logic suite: res://tests/run_all.gd'
    $suite = Invoke-GodotRun -Label 'suite' `
        -EngineArgs @('--headless', '--path', $Project, '--script', 'res://tests/run_all.gd') -TimeoutSec 240
    $suiteMatch = [regex]::Match($suite.Out, 'RESULT:\s*(PASS|FAIL)\s*-\s*(\d+)\s+assertions?,\s*(\d+)\s+failures?')
    $assertions = 0
    $failures = -1
    $suiteStatus = ''
    if ($suiteMatch.Success) {
        $suiteStatus = $suiteMatch.Groups[1].Value
        $assertions = [int]$suiteMatch.Groups[2].Value
        $failures = [int]$suiteMatch.Groups[3].Value
    } else {
        # The FAIL branch of tests/pstest.gd prints "N passed, M failed" instead
        # of "N assertions, M failures": still report the numbers, never pass it.
        $suiteFail = [regex]::Match($suite.Out, 'RESULT:\s*FAIL\s*-\s*(\d+)\s+passed,\s*(\d+)\s+failed')
        if ($suiteFail.Success) {
            $suiteStatus = 'FAIL'
            $assertions = [int]$suiteFail.Groups[1].Value + [int]$suiteFail.Groups[2].Value
            $failures = [int]$suiteFail.Groups[2].Value
        }
    }
    $suiteOk = (-not $suite.TimedOut -and $suite.Exit -eq 0 -and $suiteStatus -eq 'PASS' -and
        $failures -eq 0)
    if ($suiteStatus -ne '') {
        $suiteReason = "$assertions assertions, $failures failures"
        if ($assertions -ne 444) { $suiteReason += " (expected 444 today; reported, not forced)" }
        if ($failures -gt 0) {
            $firstFail = @([regex]::Matches($suite.Out, '(?m)^\s+FAILED\s+(.+)$') |
                ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 3)
            if ($firstFail.Count -gt 0) { $suiteReason += '; first: ' + ($firstFail -join ' | ') }
        }
    } else {
        $suiteReason = "no RESULT line (exit=$($suite.Exit))"
    }
    if ($suite.TimedOut) { $suiteReason = 'TIMEOUT after 240s; process killed' }
    Set-Check 3 'Logic suite' $suiteOk $suiteReason $suite.OutPath
    Log ("[3/9] " + ($(if ($suiteOk) { 'PASS' } else { 'FAIL' })) + " - " + $suiteReason)
    Log ''

    # ------------------------------------------------------------------ 5/8
    Log '--------------------------------------------------------------------------------'
    Log '[5/9] Render coverage: 1P --capture-flow at 1920x1080 --fixed-fps 60'
    $oneP = Invoke-GodotRun -Label 'capture-1p-run1' `
        -EngineArgs @('--path', $Project, '--resolution', '1920x1080', '--fixed-fps', '60') `
        -UserArgs @('--capture-flow') -TimeoutSec 180
    $onePPlay = [regex]::Match($oneP.Out,
        '\[capture\]\s+play\s+fps_avg=([\d.]+)\s+fps_min=([\d.]+)\s+draw=(\d+)\s+prim=(\d+)\s+frames=(\d+)\s+players=(\d+)')
    $onePDone = ($oneP.Out -match '\[capture\]\s+done')
    Log ("[5/9] 1P run exit=$($oneP.Exit) stderr=$($oneP.Err.Length)B done=$onePDone play-line=$($onePPlay.Success)")

    $expected1p = @(
        'flow-01-mode-select.png', 'flow-02-ready.png', 'flow-03-go.png', 'flow-04-play.png',
        'b2-pause-1920.png', 'b2-settle-1920.png', 'flow-02b-ready-done.png',
        'b2-play-1920.png', 'b2-play-nosnake-1920.png', 'b2-title-1920.png'
    )
    $run1Dir = Join-Path $TempDir 'run1'
    New-Item -ItemType Directory -Force -Path $run1Dir | Out-Null
    foreach ($n in $expected1p) {
        $src = Join-Path $EvidenceDir $n
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $run1Dir $n) -Force }
    }

    # ------------------------------------------------------------------ 7/8
    Log '--------------------------------------------------------------------------------'
    Log '[7/9] Determinism: second identical 1P capture'
    $oneP2 = Invoke-GodotRun -Label 'capture-1p-run2' `
        -EngineArgs @('--path', $Project, '--resolution', '1920x1080', '--fixed-fps', '60') `
        -UserArgs @('--capture-flow') -TimeoutSec 180
    $detDiffs = New-Object System.Collections.ArrayList
    $detCompared = 0
    foreach ($n in $expected1p) {
        $a = Join-Path $run1Dir $n
        $b = Join-Path $EvidenceDir $n
        if (-not (Test-Path -LiteralPath $a)) { [void]$detDiffs.Add("$n (run1 missing)"); continue }
        if (-not (Test-Path -LiteralPath $b)) { [void]$detDiffs.Add("$n (run2 missing)"); continue }
        $detCompared++
        $ha = Get-Sha256 $a
        $hb = Get-Sha256 $b
        if ($ha -ne $hb) { [void]$detDiffs.Add("$n ($($ha.Substring(0,12)) != $($hb.Substring(0,12)))") }
    }
    $detOk = ($oneP2.Exit -eq 0 -and -not $oneP2.TimedOut -and $detCompared -eq $expected1p.Count -and $detDiffs.Count -eq 0)
    if ($detDiffs.Count -gt 0) {
        foreach ($d in $detDiffs) { Log ("[7/9] DIFF " + $d) }
        $detReason = "$($detDiffs.Count) of $($expected1p.Count) screens differ: " + (($detDiffs | Select-Object -First 3) -join ', ')
    } else {
        $detReason = "$detCompared/$($expected1p.Count) 1P screens SHA256-identical (no animated exclusions needed)"
    }
    Set-Check 7 'Determinism' $detOk $detReason ($oneP2.OutPath + '; ' + $LogPath)
    Log ("[7/9] " + ($(if ($detOk) { 'PASS' } else { 'FAIL' })) + " - " + $detReason)
    Log ''

    # ------------------------------------------------------------------ 5/8 b
    Log '--------------------------------------------------------------------------------'
    Log '[5/9] Render coverage: 2P --capture-flow --capture2p'
    $twoP = Invoke-GodotRun -Label 'capture-2p' `
        -EngineArgs @('--path', $Project, '--resolution', '1920x1080', '--fixed-fps', '60') `
        -UserArgs @('--capture-flow', '--capture2p') -TimeoutSec 180
    $twoPPlay = [regex]::Match($twoP.Out,
        '\[capture\]\s+play\s+fps_avg=([\d.]+)\s+fps_min=([\d.]+)\s+draw=(\d+)\s+prim=(\d+)\s+frames=(\d+)\s+players=(\d+)')
    $twoPDone = ($twoP.Out -match '\[capture\]\s+done')
    Log ("[5/9] 2P run exit=$($twoP.Exit) stderr=$($twoP.Err.Length)B done=$twoPDone play-line=$($twoPPlay.Success)")

    # ------------------------------------------------------------------ 8/8 b
    Log '--------------------------------------------------------------------------------'
    Log '[8/8] NPC skin deal probe: 7 AI distinct (pool = count-1), 2P P2 distinct'
    $assignProbe = Invoke-GodotRun -Label 'skin-assign' `
        -EngineArgs @('--headless', '--path', $Project, '--script', 'res://tools/probe_skin_assign.gd') `
        -TimeoutSec 120
    $assignPass = (-not $assignProbe.TimedOut -and $assignProbe.Exit -eq 0 -and
        $assignProbe.Out -match '\[skin-assign\] no-duplicate-visible=PASS' -and
        $assignProbe.Out -match '(?m)^\[skin-assign\] PASS\s*$')
    $assignCount = 0
    $assignPool = 0
    $assignLine = [regex]::Match($assignProbe.Out, '\[skin-assign\] count=(\d+) pool=(\d+)')
    if ($assignLine.Success) {
        $assignCount = [int]$assignLine.Groups[1].Value
        $assignPool = [int]$assignLine.Groups[2].Value
    }
    Log ("[8/9] assign probe exit=$($assignProbe.Exit) stderr=$($assignProbe.Err.Length)B " +
        "count=$assignCount pool=$assignPool no-duplicate=$assignPass")

    # ------------------------------------------------------------------ 4/8
    Log '--------------------------------------------------------------------------------'
    Log '[4/9] Resource integrity'

    $problems = New-Object System.Collections.ArrayList
    $charRoot = Join-Path $Project 'assets\characters'
    $charDirs = @(Get-ChildItem -LiteralPath $charRoot -Directory -ErrorAction SilentlyContinue)
    $pngCount = 0
    $importCount = 0
    $ctexCount = 0
    $charBytes = 0.0
    $ctexBytes = 0.0
    foreach ($d in $charDirs) {
        foreach ($pngName in @('atlas.png', 'body.png')) {
            $p = Join-Path $d.FullName $pngName
            if (-not (Test-Path -LiteralPath $p)) {
                [void]$problems.Add("$($d.Name): missing $pngName")
                continue
            }
            $info = Get-PngSize $p
            if ($null -eq $info -or -not $info.SigOk -or $info.Width -le 0 -or $info.Height -le 0 -or $info.Length -le 0) {
                [void]$problems.Add("$($d.Name)/${pngName}: not a valid PNG")
            } else {
                $pngCount++
            }
        }
        foreach ($impName in @('atlas.png.import', 'body.png.import')) {
            $ip = Join-Path $d.FullName $impName
            if (-not (Test-Path -LiteralPath $ip)) {
                [void]$problems.Add("$($d.Name): missing $impName")
                continue
            }
            $importCount++
            $impText = [System.IO.File]::ReadAllText($ip, [System.Text.Encoding]::UTF8)
            $dm = [regex]::Match($impText, 'dest_files=\["res://([^"]+)"\]')
            if (-not $dm.Success) {
                [void]$problems.Add("$($d.Name)/${impName}: no dest_files")
                continue
            }
            $ctexPath = Join-Path $Project ($dm.Groups[1].Value.Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $ctexPath)) {
                [void]$problems.Add("$($d.Name)/${impName}: imported .ctex missing")
            } elseif ((Get-Item -LiteralPath $ctexPath).Length -le 0) {
                [void]$problems.Add("$($d.Name)/${impName}: imported .ctex empty")
            } else {
                $ctexBytes += (Get-Item -LiteralPath $ctexPath).Length
                $ctexCount++
            }
        }
        $fs = @(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -ErrorAction SilentlyContinue)
        if ($fs.Count -gt 0) { $charBytes += ($fs | Measure-Object -Property Length -Sum).Sum }
    }

    # ---- generated skin table ----
    # The expected character count is **counted**, never hard-coded: it is the
    # number of folders under assets/characters, and the table, the folders and
    # the boot line must all agree.  Adding a character needs no gate edit.
    $charCount = $charDirs.Count
    $regionKeys = @('head', 'decor', 'eyes_open', 'eyes_half', 'eyes_closed',
        'mouth_open', 'mouth_closed', 'mouth_tongue')
    $skinPath = Join-Path $Project 'src\present\ps_skin_data.gd'
    $skinSlugs = @{}
    $skinEntries = 0
    $skinRegions = 0
    $skinOutside = 0
    if (-not (Test-Path -LiteralPath $skinPath)) {
        [void]$problems.Add('ps_skin_data.gd missing')
    } else {
        $skinText = ''
        try {
            $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
            $skinText = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($skinPath))
        } catch {
            [void]$problems.Add('ps_skin_data.gd is not valid UTF-8')
        }
        $listIdx = $skinText.IndexOf('const LIST := [')
        if ($listIdx -lt 0) {
            [void]$problems.Add('ps_skin_data.gd: LIST not found')
        } else {
            $entryPattern = '(?s)\{\s*"slug":\s*"([^"]+)".*?"atlas_size":\s*Vector2i\((\d+),\s*(\d+)\)(.*?)\n\t\},'
            $entryMatches = [regex]::Matches($skinText.Substring($listIdx), $entryPattern)
            $skinEntries = $entryMatches.Count
            if ($skinEntries -ne $charCount) {
                [void]$problems.Add("skin table has $skinEntries entries but there are $charCount character folders")
            }
            foreach ($em in $entryMatches) {
                $slug = $em.Groups[1].Value
                $aw = [int]$em.Groups[2].Value
                $ah = [int]$em.Groups[3].Value
                $skinSlugs[$slug] = $true
                if (-not (Test-Path -LiteralPath (Join-Path $charRoot $slug))) {
                    [void]$problems.Add("${slug}: skin-table entry has no assets/characters folder")
                }
                $atlasPath = Join-Path $charRoot "$slug\atlas.png"
                $ai = Get-PngSize $atlasPath
                if ($null -eq $ai) {
                    [void]$problems.Add("${slug}: atlas.png missing for the skin table")
                } elseif ($ai.Width -ne $aw -or $ai.Height -ne $ah) {
                    [void]$problems.Add("${slug}: table atlas_size ${aw}x${ah} != png $($ai.Width)x$($ai.Height)")
                }
                $regKeys = @{}
                $regMatches = [regex]::Matches($em.Groups[4].Value, '"(\w+)":\s*\[([^\]]+)\]')
                foreach ($rm in $regMatches) {
                    $key = $rm.Groups[1].Value
                    $regKeys[$key] = $true
                    $vals = @($rm.Groups[2].Value.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                    if ($vals.Count -lt 4) {
                        [void]$problems.Add("${slug}/${key}: region needs 4 numbers")
                        continue
                    }
                    $skinRegions++
                    $x = [double]$vals[0]
                    $y = [double]$vals[1]
                    $rw = [double]$vals[2]
                    $rh = [double]$vals[3]
                    if ($x -lt 0 -or $y -lt 0 -or ($x + $rw) -gt $aw -or ($y + $rh) -gt $ah) {
                        $skinOutside++
                        [void]$problems.Add("${slug}/${key}: rect ($x,$y,$rw,$rh) outside ${aw}x${ah}")
                    }
                }
                foreach ($need in $regionKeys) {
                    if (-not $regKeys.ContainsKey($need)) {
                        [void]$problems.Add("${slug}: skin-table entry is missing region '$need'")
                    }
                }
            }
            foreach ($d in $charDirs) {
                if (-not $skinSlugs.ContainsKey($d.Name)) {
                    [void]$problems.Add("$($d.Name): character folder has no skin-table entry")
                }
            }
        }
    }

    # ---- boot skin line / fallback lines ----
    $skinLine = [regex]::Match($boot.Out, '\[skin\]\s+(\d+)\s+characters,\s+player=(.+?),\s+missing=(\d+)')
    $skinLineText = 'missing'
    if ($skinLine.Success) {
        $skinLineText = "[skin] $($skinLine.Groups[1].Value) characters, player=$($skinLine.Groups[2].Value), missing=$($skinLine.Groups[3].Value)"
        if ([int]$skinLine.Groups[1].Value -ne $charCount) {
            [void]$problems.Add("boot [skin] count $($skinLine.Groups[1].Value) != $charCount character folders")
        }
        if ([int]$skinLine.Groups[3].Value -ne 0) { [void]$problems.Add("boot [skin] missing=$($skinLine.Groups[3].Value) != 0") }
    } else {
        [void]$problems.Add("boot log has no [skin] <count> characters ... missing=0 line (expected $charCount)")
    }
    $allRunText = @($boot.Out, $boot.Err, $suite.Out, $suite.Err, $oneP.Out, $oneP.Err, $oneP2.Out, $oneP2.Err, $twoP.Out, $twoP.Err, $assignProbe.Out, $assignProbe.Err) -join "`n"
    $fallbackHits = [regex]::Matches($allRunText, 'asset missing/corrupt|falls back to the procedural|missing=[1-9]\d*')
    if ($fallbackHits.Count -gt 0) {
        [void]$problems.Add("$($fallbackHits.Count) skin fallback/missing-asset line(s)")
    }

    # ---- forbidden load-error lines across every run ----
    $loadPatterns = @('Failed to load', 'Cannot open', 'No loader found', 'res://[^\s"'']+ not found')
    $loadHits = New-Object System.Collections.ArrayList
    foreach ($pat in $loadPatterns) {
        foreach ($m in [regex]::Matches($allRunText, $pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $lineStart = $m.Index
            while ($lineStart -gt 0 -and $allRunText[$lineStart - 1] -ne [char]10) { $lineStart-- }
            $lineEnd = $m.Index
            while ($lineEnd -lt $allRunText.Length -and $allRunText[$lineEnd] -ne [char]10) { $lineEnd++ }
            $line = $allRunText.Substring($lineStart, $lineEnd - $lineStart).Trim()
            if (-not $loadHits.Contains($line)) { [void]$loadHits.Add($line) }
        }
    }
    if ($loadHits.Count -gt 0) {
        foreach ($h in ($loadHits | Select-Object -First 4)) { [void]$problems.Add("load error: $h") }
    }

    # ---- global imported .ctex inventory ----
    $allImportedCtex = 0.0
    $impDir = Join-Path $Project '.godot\imported'
    if (Test-Path -LiteralPath $impDir) {
        $ctexFiles = @(Get-ChildItem -LiteralPath $impDir -Filter '*.ctex' -File -ErrorAction SilentlyContinue)
        if ($ctexFiles.Count -gt 0) {
            $allImportedCtex = ($ctexFiles | Measure-Object -Property Length -Sum).Sum
        }
    }

    $resOk = ($problems.Count -eq 0 -and $charCount -gt 0 -and $skinEntries -eq $charCount)
    $resReason = ("$charCount chars (counted), $pngCount PNG, $importCount .import/$ctexCount .ctex; " +
        "$skinEntries skins/$skinRegions regions ($skinOutside outside); missing=0; $($loadHits.Count) load errors")
    if ($problems.Count -gt 0) {
        $resReason = "$($problems.Count) issue(s): " + (($problems | Select-Object -First 2) -join '; ')
    }
    $resEvidence = $LogPath + '; ' + $boot.OutPath + '; src\present\ps_skin_data.gd'
    Set-Check 4 'Resource integrity' $resOk $resReason $resEvidence
    Log ("[4/9] " + ($(if ($resOk) { 'PASS' } else { 'FAIL' })) + " - " + $resReason)
    if ($problems.Count -gt 0) {
        foreach ($p in ($problems | Select-Object -First 8)) { Log ("       - " + $p) }
    }
    Log ("[resources] character count=$charCount folders (dynamic), png=$pngCount imports=$importCount ctex=$ctexCount")
    Log ("[resources] assets/characters=" + (Fmt ($charBytes / 1MB) '0.00') + " MB; character .ctex=" +
        (Fmt ($ctexBytes / 1MB) '0.00') + " MB; all imported .ctex=" + (Fmt ($allImportedCtex / 1MB) '0.00') + " MB")
    Log ("[resources] skin table=$skinEntries entries (expected $charCount), $skinRegions region rects, $skinOutside outside the atlas")
    Log ("[resources] boot line: " + $skinLineText)
    Log ''

    # ------------------------------------------------------------------ 5/8 c
    # Put the 1P run-1 frames back: the 2P walk rewrites flow-01/flow-03, and the
    # 1P screens must be judged on the 1P walk that actually produced them.
    foreach ($n in $expected1p) {
        $a = Join-Path $run1Dir $n
        if (Test-Path -LiteralPath $a) {
            Copy-Item -LiteralPath $a -Destination (Join-Path $EvidenceDir $n) -Force
        }
    }

    $renderSpecs = @(
        [pscustomobject]@{ Name = '1P mode select'; File = 'flow-01-mode-select.png'; Source = '1P' },
        [pscustomobject]@{ Name = '1P ready';       File = 'flow-02-ready.png';       Source = '1P' },
        [pscustomobject]@{ Name = '1P countdown';   File = 'flow-03-go.png';          Source = '1P' },
        [pscustomobject]@{ Name = '1P play';        File = 'flow-04-play.png';        Source = '1P' },
        [pscustomobject]@{ Name = '1P pause';       File = 'b2-pause-1920.png';       Source = '1P' },
        [pscustomobject]@{ Name = '1P settle';      File = 'b2-settle-1920.png';      Source = '1P' },
        [pscustomobject]@{ Name = '2P split play';  File = 'flow-04-play-2p.png';     Source = '2P' }
    )
    $renderFails = New-Object System.Collections.ArrayList
    $minSize = [double]::MaxValue
    $minDistinct = [int]::MaxValue
    foreach ($spec in $renderSpecs) {
        $p = Join-Path $EvidenceDir $spec.File
        $srcLog = if ($spec.Source -eq '2P') { $twoP.Out } else { $oneP.Out }
        $savedPattern = '\[capture\] saved .*' + [regex]::Escape($spec.File) + ' \(1920x1080\) err=0'
        if ($spec.Source -eq '2P') {
            $runDone = ($twoPDone -and $twoP.Exit -eq 0 -and $twoPPlay.Success -and
                [int]$twoPPlay.Groups[6].Value -eq 2)
        } else {
            $runDone = ($onePDone -and $oneP.Exit -eq 0 -and $onePPlay.Success -and
                [int]$onePPlay.Groups[6].Value -eq 1)
        }
        if (-not (Test-Path -LiteralPath $p)) {
            [void]$renderFails.Add("$($spec.Name): missing $($spec.File)")
            continue
        }
        $info = Get-PngSize $p
        $stats = $null
        if ($null -ne $info -and $info.SigOk) { $stats = Get-ImageStats $p }
        $why = @()
        if (-not $runDone) { $why += 'capture run did not finish (exit/done)' }
        if (-not [regex]::IsMatch($srcLog, $savedPattern)) { $why += 'no saved/err=0 line this run' }
        if ($null -eq $info -or -not $info.SigOk) { $why += 'not a PNG' }
        if ($null -ne $info -and $info.Length -lt 40960) { $why += "only $($info.Length)B (<40KB)" }
        if ($null -ne $info -and ($info.Width -ne 1920 -or $info.Height -ne 1080)) {
            $why += "size $($info.Width)x$($info.Height) != 1920x1080"
        }
        $distinct = 0
        if ($null -ne $stats) { $distinct = $stats.Distinct }
        if ($null -eq $stats) { $why += 'cannot decode' }
        elseif ($distinct -lt 500) { $why += "flat frame (distinct=$distinct)" }
        if ($why.Count -gt 0) {
            [void]$renderFails.Add("$($spec.Name): " + ($why -join ', '))
            Log ("       FAIL " + $spec.Name + " " + $spec.File + ": " + ($why -join ', '))
        } else {
            if ($info.Length -lt $minSize) { $minSize = $info.Length }
            if ($distinct -lt $minDistinct) { $minDistinct = $distinct }
            Log ("       PASS " + $spec.Name.PadRight(14) + " " + $spec.File.PadRight(26) +
                ([string]([math]::Round($info.Length / 1KB)) + "KB").PadLeft(8) + "  $($info.Width)x$($info.Height) distinct=" + $distinct)
        }
    }
    $renderOk = ($renderFails.Count -eq 0)
    if ($renderOk) {
        $renderReason = "$($renderSpecs.Count)/$($renderSpecs.Count) screens 1920x1080, >=40KB, non-flat (min " +
            ([math]::Round($minSize / 1KB)) + "KB, min distinct=$minDistinct)"
    } else {
        $renderReason = "$($renderFails.Count)/$($renderSpecs.Count) failed: " + ($renderFails[0])
    }
    Set-Check 5 'Render coverage' $renderOk $renderReason ($EvidenceDir + '\flow-*.png, b2-*.png; ' + $LogPath)
    Log ("[5/9] " + ($(if ($renderOk) { 'PASS' } else { 'FAIL' })) + " - " + $renderReason)
    Log ''

    # ------------------------------------------------------------------ 6/8
    Log '--------------------------------------------------------------------------------'
    Log '[6/9] Perf budget: 1P play draw calls <= 200 (2P reported)'
    $perfOk = $false
    $perfOneDraw = -1
    $perfTwoDraw = -1
    $perfReason = 'no [capture] play line'
    if ($onePPlay.Success) {
        $perfOneDraw = [int]$onePPlay.Groups[3].Value
        $perfOnePrim = [int]$onePPlay.Groups[4].Value
        $perfOneFps = [double]$onePPlay.Groups[1].Value
        $perfOneMin = [double]$onePPlay.Groups[2].Value
        $perfOneFrames = [int]$onePPlay.Groups[5].Value
        $perfOnePlayers = [int]$onePPlay.Groups[6].Value
        $perfOk = ($onePPlay.Success -and $perfOneDraw -le 200 -and $perfOnePrim -gt 0 -and
            $perfOnePlayers -eq 1 -and $onePDone)
        $perfReason = "1P draw=$perfOneDraw (<=200), prim=$perfOnePrim, fps_avg=" + (Fmt $perfOneFps '0.0') +
            "/min=" + (Fmt $perfOneMin '0.0') + ", frames=$perfOneFrames"
        if ($twoPPlay.Success) {
            $perfTwoDraw = [int]$twoPPlay.Groups[3].Value
            $twoPPrim = [int]$twoPPlay.Groups[4].Value
            $perfReason += "; 2P draw=$perfTwoDraw prim=$twoPPrim"
        } else {
            $perfReason += '; 2P play line missing'
        }
        if (-not $onePDone) { $perfReason += '; 1P capture did not finish' }
        if ($perfOneDraw -gt 200) { $perfReason = "1P draw=$perfOneDraw > 200; " + $perfReason }
    }
    Set-Check 6 'Perf budget' $perfOk $perfReason $oneP.OutPath
    Log ("[6/9] " + ($(if ($perfOk) { 'PASS' } else { 'FAIL' })) + " - " + $perfReason)
    Log ''

    # ------------------------------------------------------------------ 8/8
    Log '--------------------------------------------------------------------------------'
    Log '[8/8] Skin coverage: >=2 distinct character skins visible in one frame'
    $lineUp = [regex]::Match($oneP.Out, '\[skin\]\s+round=(\d+)\s+line-up:\s*(.*)')
    $visible = [regex]::Match($oneP.Out, '\[skin\]\s+visible-in-frame=(\d+)\s+distinct=(\d+):\s*(.*)')
    $lineUpDistinct = 0
    $lineUpText = ''
    if ($lineUp.Success) {
        $lineUpText = $lineUp.Groups[2].Value.Trim()
        $lineUpDistinct = @($lineUpText -split '\s+' | Where-Object { $_ -ne '' } | Sort-Object -Unique).Count
    }
    $visibleCount = 0
    $visibleDistinct = 0
    $visibleText = ''
    if ($visible.Success) {
        $visibleCount = [int]$visible.Groups[1].Value
        $visibleDistinct = [int]$visible.Groups[2].Value
        $visibleText = $visible.Groups[3].Value.Trim()
    }
    $unknownVisible = @()
    if ($visibleDistinct -gt 0) {
        foreach ($slug in ($visibleText -split '\s+' | Where-Object { $_ -ne '' })) {
            if (-not $skinSlugs.ContainsKey($slug)) { $unknownVisible += $slug }
        }
    }
    $skinOk = ($lineUp.Success -and $lineUpDistinct -ge 2 -and $visible.Success -and
        $visibleDistinct -ge 2 -and $visibleCount -ge $visibleDistinct -and
        $unknownVisible.Count -eq 0 -and $assignPass)
    if ($lineUp.Success) {
        $skinReason = "$lineUpDistinct distinct dealt; $visibleDistinct distinct visible in the captured play frame" +
            " (" + $visibleText + ")"
    } else {
        $skinReason = 'no [skin] line-up line in the 1P capture'
    }
    if ($visible.Success -and $visibleDistinct -lt 2) {
        $skinReason = "only $visibleDistinct distinct skin(s) visible in the play frame ($visibleText)"
    }
    if ($unknownVisible.Count -gt 0) {
        $skinReason += "; unknown slug(s): " + ($unknownVisible -join ',')
    }
    if ($assignPass) {
        $skinReason += "; NPC deal: count=$assignCount pool=$assignPool, 7 AI + 2P P2 all distinct"
    } else {
        $skinReason += "; NPC deal probe FAILED (duplicate/out-of-range/player pick dealt)"
    }
    Set-Check 8 'Skin coverage' $skinOk $skinReason ($oneP.OutPath + '; ' + $assignProbe.OutPath)
    Log ("[8/9] " + ($(if ($skinOk) { 'PASS' } else { 'FAIL' })) + " - " + $skinReason)
    Log ("[skins] line-up=" + $lineUpDistinct + " distinct: " + $lineUpText)
    Log ("[skins] method: the world view reports the skins its last drawn frame rendered" +
        " (visible_skins()); cross-checked against the [skin] line-up log and the NPC deal probe.")
    Log ("[skins] NPC deal: characters=$assignCount pool=$assignPool " +
        "no-duplicate-visible=" + $(if ($assignPass) { 'PASS' } else { 'FAIL' }))
    Log ''

    # ------------------------------------------------------------------ 9/9
    # Stress guard (Docs/WRAPUP-AUDIT.md, Phase B): the WORST-CASE frame, real
    # time (NO --fixed-fps), 1920x1080:
    #   8 snakes x 240 segments weaving through the view, 265 pellets (the spawner's
    #   own trim cap), 7 powerups, the FX pools at their caps, boost aura on every
    #   snake, the always-on perf panel ON (shipped default), the staged camera.
    # Thresholds: 2P draw <= 300 and fps >= 45, 1P draw <= 200 and fps >= 50.
    # Measured on the dev PC: 1P 169 draw / 60.0 fps, 2P 280 draw / 53.0 fps. The
    # 45 fps floor leaves ~15% noise headroom for a busy machine while still
    # failing the pre-optimisation build (2P 41 fps).
    Log '--------------------------------------------------------------------------------'
    Log '[9/9] Stress guard: 2P worst case draw <= 300 / fps >= 45 (1P draw <= 200 / fps >= 50)'
    $stress1 = Invoke-GodotRun -Label 'stress-1p' `
        -EngineArgs @('--path', $Project, '--resolution', '1920x1080') `
        -UserArgs @('--capture-stress') -TimeoutSec 120
    $stress2 = Invoke-GodotRun -Label 'stress-2p' `
        -EngineArgs @('--path', $Project, '--resolution', '1920x1080') `
        -UserArgs @('--capture-stress', '--capture2p') -TimeoutSec 120
    $stressDone = (($stress1.Out -match '\[capture\]\s+done') -and
        ($stress2.Out -match '\[capture\]\s+done'))
    $stressLine = '(?m)^\[stress\] leg=(\d)p cap=(240) players=(\d) snakes=(\d) food=(\d+) pwr=(\d+) ' +
        'fx=(\d+)/(\d+)/(\d+) buffs=(\d+) zoom=([\d.]+) draw=(\d+) prim=(\d+) ' +
        'fps_avg=([\d.]+) fps_min=([\d.]+) ms=([\d.]+) p95=([\d.]+) slow=(\d+) ' +
        'bodies=(\d+)/(\d+) dropped=(\d+)'
    $s1 = [regex]::Match($stress1.Out, $stressLine)
    $s2 = [regex]::Match($stress2.Out, $stressLine)
    $stressOk = $false
    $stressReason = 'no [stress] leg=...cap=240 line'
    if ($s1.Success -and $s2.Success) {
        $s1Draw = [int]$s1.Groups[12].Value
        $s1Prim = [int]$s1.Groups[13].Value
        $s1Fps = [double]$s1.Groups[14].Value
        $s1P95 = [double]$s1.Groups[17].Value
        $s2Draw = [int]$s2.Groups[12].Value
        $s2Prim = [int]$s2.Groups[13].Value
        $s2Fps = [double]$s2.Groups[14].Value
        $s2P95 = [double]$s2.Groups[17].Value
        $stressOk = ($stressDone -and -not $stress1.TimedOut -and -not $stress2.TimedOut -and
            $stress1.Err.Length -eq 0 -and $stress2.Err.Length -eq 0 -and
            $s1Draw -le 200 -and $s1Fps -ge 50 -and
            $s2Draw -le 300 -and $s2Fps -ge 45)
        $stressReason = "1P draw=$s1Draw (<=200) fps=" + (Fmt $s1Fps '0.0') + " (>=50) p95=" +
            (Fmt $s1P95 '0.0') + "ms prim=$s1Prim; 2P draw=$s2Draw (<=300) fps=" +
            (Fmt $s2Fps '0.0') + " (>=45) p95=" + (Fmt $s2P95 '0.0') + "ms prim=$s2Prim"
        if (-not $stressDone) { $stressReason += '; a stress run did not finish' }
        if ($s1Draw -gt 200) { $stressReason = "1P draw=$s1Draw > 200; " + $stressReason }
        if ($s1Fps -lt 50) { $stressReason = "1P fps=" + (Fmt $s1Fps '0.0') + " < 50; " + $stressReason }
        if ($s2Draw -gt 300) { $stressReason = "2P draw=$s2Draw > 300; " + $stressReason }
        if ($s2Fps -lt 45) { $stressReason = "2P fps=" + (Fmt $s2Fps '0.0') + " < 45; " + $stressReason }
    } elseif ($stress1.TimedOut -or $stress2.TimedOut) {
        $stressReason = 'stress run TIMEOUT (killed)'
    }
    Set-Check 9 'Stress guard' $stressOk $stressReason ($stress1.OutPath + '; ' + $stress2.OutPath)
    Log ("[9/9] " + ($(if ($stressOk) { 'PASS' } else { 'FAIL' })) + " - " + $stressReason)
    Log ("[stress] scenario: 8 snakes x 240 seg, 265 pellets, 7 powerups, FX pools at cap, " +
        "boost aura on all, perf panel ON, real time (no --fixed-fps)")
    Log ''

} catch {
    Log ('FATAL: ' + $_.Exception.Message)
    Log ($_.ScriptStackTrace)
} finally {
    # ------------------------------------------------------------- summary
    Log '================================================================================'
    Log 'PASS/FAIL TABLE'
    Log '================================================================================'
    Log ('{0,-3} {1,-22} {2,-6} {3}' -f '#', 'CHECK', 'RESULT', 'REASON')
    $failed = 0
    for ($i = 1; $i -le 9; $i++) {
        $c = $script:Checks[$i]
        if ($null -eq $c) {
            $c = [pscustomobject]@{ Id = $i; Name = 'check'; Ok = $false; Reason = 'not run'; Evidence = 'n/a' }
        }
        if (-not $c.Ok) { $failed++ }
        $tag = if ($c.Ok) { 'PASS' } else { 'FAIL' }
        Log ('{0,-3} {1,-22} {2,-6} {3}' -f $c.Id, $c.Name, $tag, $c.Reason)
    }
    Log ''
    Log 'EVIDENCE'
    for ($i = 1; $i -le 9; $i++) {
        $c = $script:Checks[$i]
        if ($null -ne $c) { Log ("[$($c.Id)] " + $c.Evidence) }
    }
    Log '================================================================================'
    if ($failed -eq 0) {
        Log 'RESULT: PASS - safe to package'
    } else {
        Log "RESULT: FAIL - $failed check(s) failed; DO NOT PACKAGE"
    }
    Log '================================================================================'
    $script:Failed = $failed
    $script:LogWriter.Flush()
    $script:LogWriter.Dispose()

    if ((Test-Path -LiteralPath $TempDir) -and $TempDir -like (Join-Path $env:TEMP 'pose-snake-gate-*')) {
        try { Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
