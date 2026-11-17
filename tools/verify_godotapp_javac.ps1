# Standalone javac check for the generated Android build template's GodotApp.java.
#
# This does NOT run Gradle. It compiles the exact source that Gradle would compile
# (`android/build/src/main/java/com/godot/game/GodotApp.java`) against:
#   * android.jar (compileSdk 35)
#   * the Godot 4.6.3 export template's classes.jar (android/_work/godot-classes.jar)
#   * the androidx AARs Gradle resolved, unpacked to android/_work/javac-libs/*.jar
#   * the generated BuildConfig.java (standard/debug)
#
# Usage:
#   powershell -NoProfile -File tools\verify_godotapp_javac.ps1
#   powershell -NoProfile -File tools\verify_godotapp_javac.ps1 -Jdk C:\jdkcopy
#
# On this host use a JDK copy that can write files (C:\jdkcopy), not D:\android_tc\jdk.

param(
    [string] $Jdk = $(if ($env:YOUDOO_JAVA_HOME) { $env:YOUDOO_JAVA_HOME } else { 'C:\jdkcopy' }),
    [string] $AndroidJar = 'D:\android_tc\sdk\platforms\android-35\android.jar'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$appJava = Join-Path $root 'android\build\src\main\java\com\godot\game\GodotApp.java'
$godotClasses = Join-Path $root 'android\_work\godot-classes.jar'
$libDir = Join-Path $root 'android\_work\javac-libs'
$outDir = Join-Path $root 'android\_work\javac-out'
$javac = Join-Path $Jdk 'bin\javac.exe'

if (-not (Test-Path $javac)) { throw "No javac.exe under $Jdk\bin" }
if (-not (Test-Path $AndroidJar)) { throw "Missing android.jar: $AndroidJar" }
if (-not (Test-Path $appJava)) { throw "Missing generated GodotApp.java: $appJava" }
if (-not (Test-Path $godotClasses)) {
    throw "Missing Godot classes.jar: $godotClasses (run tools\build_plugin.ps1 once)"
}
if (-not (Select-String -LiteralPath $appJava -Pattern 'GodotRemoteInput' -Quiet)) {
    throw "GodotApp.java does not contain the GodotRemoteInput hook; run tools\setup_android_build.ps1"
}

# --- unpack the androidx AARs Gradle resolved (once) --------------------------
function Expand-AarToJar([string] $aar, [string] $destJar) {
    $tmp = Join-Path $env:TEMP ('aarx-' + [guid]::NewGuid().ToString('N'))
    $zip = $tmp + '.zip'
    Copy-Item -LiteralPath $aar -Destination $zip -Force
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $classes = Join-Path $tmp 'classes.jar'
    if (Test-Path $classes) { Copy-Item -LiteralPath $classes -Destination $destJar -Force }
    Remove-Item $tmp -Recurse -Force
    Remove-Item $zip -Force
}

if (-not (Test-Path $libDir) -or -not (Get-ChildItem $libDir -Filter *.jar -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Force -Path $libDir | Out-Null
    $gradleBase = Join-Path $env:USERPROFILE '.gradle\caches\modules-2\files-2.1'
    $aarGlobs = @(
        'androidx.fragment\fragment\*\*\*.aar',
        'androidx.activity\activity\*\*\*.aar',
        'androidx.core\core\*\*\*.aar',
        'androidx.core\core-splashscreen\*\*\*.aar',
        'androidx.lifecycle\*\*\*\*.aar',
        'androidx.savedstate\savedstate\*\*\*.aar',
        'androidx.collection\collection\*\*\*.aar',
        'androidx.arch.core\core-runtime\*\*\*.aar',
        'androidx.loader\loader\*\*\*.aar',
        'androidx.viewpager\viewpager\*\*\*.aar',
        'androidx.customview\customview\*\*\*.aar',
        'androidx.profileinstaller\profileinstaller\*\*\*.aar',
        'androidx.startup\startup-runtime\*\*\*.aar',
        'androidx.tracing\tracing\*\*\*.aar',
        'androidx.versionedparcelable\versionedparcelable\*\*\*.aar',
        'androidx.concurrent\concurrent-futures\*\*\*.aar',
        'androidx.documentfile\documentfile\*\*\*.aar',
        'androidx.annotation\annotation-experimental\*\*\*.aar'
    )
    foreach ($glob in $aarGlobs) {
        Get-ChildItem (Join-Path $gradleBase $glob) -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $libDir ($_.BaseName + '.jar')
            if (-not (Test-Path $dest)) { Expand-AarToJar $_.FullName $dest }
        }
    }
    # Plain jars (annotation / collection / lifecycle-common / kotlin-stdlib).
    $jarGlobs = @(
        'androidx.annotation\annotation-jvm\*\*\*.jar',
        'androidx.collection\collection\*\*\*.jar',
        'androidx.lifecycle\lifecycle-common\*\*\*.jar',
        'org.jetbrains.kotlin\kotlin-stdlib\2.1.21\*\*.jar'
    )
    foreach ($glob in $jarGlobs) {
        Get-ChildItem (Join-Path $gradleBase $glob) -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $libDir $_.Name) -Force
        }
    }
}
if (-not (Get-ChildItem $libDir -Filter *.jar -ErrorAction SilentlyContinue)) {
    throw "No androidx jars under $libDir; run a Gradle build once so ~/.gradle has the AARs."
}

# --- generated BuildConfig.java (flavor standard, build type debug) -----------
$buildConfig = Get-ChildItem (Join-Path $root 'android\build\build\generated\source\buildConfig') `
    -Recurse -Filter 'BuildConfig.java' -ErrorAction SilentlyContinue | Select-Object -First 1
$sources = @($appJava)
if ($buildConfig) {
    $sources += $buildConfig.FullName
} else {
    # A clean tree has no generated BuildConfig yet; the class only needs FLAVOR.
    $stubDir = Join-Path $env:TEMP ('godotapp-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
    $stub = Join-Path $stubDir 'BuildConfig.java'
    Set-Content -Path $stub -Encoding ASCII -Value @'
package com.godot.game;
public final class BuildConfig {
    public static final String FLAVOR = "standard";
}
'@
    $sources += $stub
    Write-Host "BuildConfig.java not generated yet; using a FLAVOR stub"
}

if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$classpath = @(
    $AndroidJar,
    $godotClasses,
    (Join-Path $libDir '*')
) -join ';'

$cmd = @(
    '-encoding', 'UTF-8',
    '-source', '17',
    '-target', '17',
    '-Xlint:-options',
    '-classpath', $classpath,
    '-d', $outDir
) + $sources

Write-Host "javac: $($sources.Count) source file(s)"
Write-Host ("& `"{0}`" -encoding UTF-8 -source 17 -target 17 -Xlint:-options -classpath `"{1}`" -d `"{2}`" {3}" -f `
    $javac, $classpath, $outDir, (($sources | ForEach-Object { "`"$_`"" }) -join ' '))

& $javac @cmd 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "javac failed with exit code $LASTEXITCODE" }

$classFile = Join-Path $outDir 'com\godot\game\GodotApp.class'
if (-not (Test-Path $classFile)) { throw "javac produced no GodotApp.class" }
Write-Host "OK: $classFile ($((Get-Item $classFile).Length) bytes)"
