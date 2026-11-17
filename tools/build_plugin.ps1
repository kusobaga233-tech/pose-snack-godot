# Compiles the YoudooSkeleton Godot Android plugin against the Godot 4.6 template
# and the YoudooGame SDK AIDL classes, then packages it as a jar for the gdap.
#
# Usage:  powershell -NoProfile -File tools\build_plugin.ps1 [-Jdk C:\jdkcopy]
#
# -Jdk must point at a JDK whose bin\javac.exe can write files on this machine.
# It defaults to $env:YOUDOO_JAVA_HOME, then to D:\android_tc\jdk. On this host
# the security policy denies file creation to JVMs launched from the default
# path, so pass a JDK copy (see android\README.md).

param(
    [string] $Jdk = $(if ($env:YOUDOO_JAVA_HOME) { $env:YOUDOO_JAVA_HOME } else { 'D:\android_tc\jdk' })
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$jdk = Join-Path $Jdk 'bin'
if (-not (Test-Path (Join-Path $jdk 'javac.exe'))) { throw "No javac.exe under $jdk" }
Write-Host "jdk: $Jdk"
$androidJar = 'D:\android_tc\sdk\platforms\android-35\android.jar'

$work = Join-Path $root 'android\_work'
$classes = Join-Path $work 'classes'
$srcDir = Join-Path $root 'android\src'
$pluginsDir = Join-Path $root 'android\plugins\youdoo'
$outJar = Join-Path $pluginsDir 'godot-youdoo-skeleton.jar'

$godotAar = Join-Path $work 'godot-lib.template_debug.aar'
$sdkAar = Join-Path $pluginsDir 'YoudooAndroidLibrary-release.aar'

New-Item -ItemType Directory -Force -Path $work, $pluginsDir | Out-Null

function Expand-Aar($aarPath, $targetDir) {
    $zipCopy = "$targetDir.zip"
    Copy-Item $aarPath $zipCopy -Force
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    Expand-Archive -Path $zipCopy -DestinationPath $targetDir -Force
    Remove-Item $zipCopy -Force
}

# --- resolve godot-lib classes.jar (from the installed export template) --------
$godotClasses = Join-Path $work 'godot-classes.jar'
if (-not (Test-Path $godotClasses)) {
    if (-not (Test-Path $godotAar)) {
        $androidSourceZip = Join-Path $env:APPDATA 'Godot\export_templates\4.6.3.stable\android_source.zip'
        if (-not (Test-Path $androidSourceZip)) { throw "Missing export template: $androidSourceZip" }
        $tmpl = Join-Path $work 'tmpl'
        if (Test-Path $tmpl) { Remove-Item $tmpl -Recurse -Force }
        Copy-Item $androidSourceZip "$work\tmpl.zip" -Force
        Expand-Archive -Path "$work\tmpl.zip" -DestinationPath $tmpl -Force
        Copy-Item (Join-Path $tmpl 'libs\debug\godot-lib.template_debug.aar') $godotAar -Force
    }
    Expand-Aar $godotAar (Join-Path $work 'godot-aar')
    Copy-Item (Join-Path $work 'godot-aar\classes.jar') $godotClasses -Force
}

# --- resolve SDK classes.jar --------------------------------------------------
$sdkClasses = Join-Path $work 'sdk-classes.jar'
if (-not (Test-Path $sdkClasses)) {
    if (-not (Test-Path $sdkAar)) { throw "Missing SDK aar: $sdkAar" }
    Expand-Aar $sdkAar (Join-Path $work 'sdk-aar')
    Copy-Item (Join-Path $work 'sdk-aar\classes.jar') $sdkClasses -Force
}

# --- compile ------------------------------------------------------------------
if (Test-Path $classes) { Remove-Item $classes -Recurse -Force }
New-Item -ItemType Directory -Force -Path $classes | Out-Null

$sources = Get-ChildItem -Path $srcDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
if (-not $sources) { throw "No Java sources under $srcDir" }

$classpath = @($androidJar, $godotClasses, $sdkClasses) -join ';'
Write-Host "javac: $($sources.Count) source file(s)"
& "$jdk\javac.exe" -encoding UTF-8 -source 11 -target 11 -Xlint:-options `
    -classpath $classpath -d $classes $sources
if ($LASTEXITCODE -ne 0) { throw "javac failed with exit code $LASTEXITCODE" }

# --- package ------------------------------------------------------------------
if (Test-Path $outJar) { Remove-Item $outJar -Force }
& "$jdk\jar.exe" --create --file $outJar -C $classes .
if ($LASTEXITCODE -ne 0) { throw "jar failed with exit code $LASTEXITCODE" }

Write-Host "built $outJar ($((Get-Item $outJar).Length) bytes)"
