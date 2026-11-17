# Cross-compiles android/native/camframe.c for arm64-v8a and packages it as a
# local AAR the Godot gradle export already consumes through the plugin gdap.
#
# No CMake and no Gradle: the NDK's clang wrapper is invoked directly, so the
# only integration point is `[dependencies] local` in
# android/plugins/youdoo_skeleton.gdap (same mechanism as the six SDK AARs).
#
# Usage:
#   powershell -NoProfile -File android\native\build_camframe.ps1
#   powershell -NoProfile -File android\native\build_camframe.ps1 -Ndk <ndk-root> -Api 30
#
# The default NDK is the Unity/Tuanjie-bundled r23.1.7779620 that is present on
# this machine. API 30 is required (not 21): AHardwareBuffer and its JNI bridge
# are API 26+, and the app's minSdk is 30.

param(
    [string] $Ndk = 'D:\tuanjie_editor\2022.3.61t9\Editor\Data\PlaybackEngines\AndroidPlayer\NDK',
    [string] $Api = '30',
    [string] $Abi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$here = $PSScriptRoot
$root = Split-Path -Parent (Split-Path -Parent $here)   # repo root
$source = Join-Path $here 'camframe.c'
$buildDir = Join-Path $here 'build'
$stage = Join-Path $buildDir 'aar'
$soPath = Join-Path $buildDir 'libcamframe.so'
$aarPath = Join-Path $root 'android\plugins\youdoo\youdoo_camframe-release.aar'

$bin = Join-Path $Ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$clangName = 'aarch64-linux-android{0}-clang.cmd' -f $Api
$clang = Join-Path $bin $clangName
$llvmNm = Join-Path $bin 'llvm-nm.exe'

if (-not (Test-Path -LiteralPath $source)) { throw "Missing source: $source" }
if (-not (Test-Path -LiteralPath $clang)) { throw "Missing NDK clang wrapper: $clang" }
if (-not (Test-Path -LiteralPath $llvmNm)) { throw "Missing llvm-nm: $llvmNm" }

Write-Host "ndk:   $Ndk (api $Api, $Abi)"
Write-Host "clang: $clang"

if (Test-Path -LiteralPath $buildDir) { Remove-Item -LiteralPath $buildDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

# --- compile ---------------------------------------------------------------
& $clang -shared -fPIC -O2 -Wall -Wextra -Werror `
    -DANDROID -DNDEBUG `
    -o $soPath $source -landroid -llog
if ($LASTEXITCODE -ne 0) { throw "clang failed with exit code $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $soPath)) { throw "clang produced no $soPath" }
Write-Host "built: $soPath ($((Get-Item -LiteralPath $soPath).Length) bytes)"

# --- verify the JNI entry point is exported --------------------------------
$symbols = & $llvmNm -D --defined-only $soPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "llvm-nm failed with exit code $LASTEXITCODE" }
$expected = 'Java_com_youdoo_godot_CameraFrameNative_readRgba'
if ($symbols -notmatch [regex]::Escape($expected)) {
    Write-Host $symbols
    throw "libcamframe.so does not export $expected"
}
Write-Host "symbol OK: $expected"

# --- stage the AAR (mirrors the layout of the vendor AARs) -----------------
$jniDir = Join-Path (Join-Path $stage 'jni') $Abi
New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
Copy-Item -LiteralPath $soPath -Destination (Join-Path $jniDir 'libcamframe.so') -Force

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.youdoo.camframe">

    <uses-sdk android:minSdkVersion="30" />

</manifest>
'@
[System.IO.File]::WriteAllText((Join-Path $stage 'AndroidManifest.xml'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

# Empty R.txt / proguard.txt, exactly like the SDK AARs.
[System.IO.File]::WriteAllText((Join-Path $stage 'R.txt'), '', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $stage 'proguard.txt'), '', (New-Object System.Text.UTF8Encoding($false)))

$metadataDir = Join-Path $stage 'META-INF\com\android\build\gradle'
New-Item -ItemType Directory -Force -Path $metadataDir | Out-Null
$metadata = "aarFormatVersion=1.0`naarMetadataVersion=1.0`nminCompileSdk=1`nminCompileSdkExtension=0`nminAndroidGradlePluginVersion=1.0.0`n"
[System.IO.File]::WriteAllText((Join-Path $metadataDir 'aar-metadata.properties'), $metadata, (New-Object System.Text.UTF8Encoding($false)))

# A zero-entry classes.jar keeps the AAR shaped like every other dependency.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$classesJar = Join-Path $stage 'classes.jar'
$zip = [System.IO.Compression.ZipFile]::Open($classesJar, [System.IO.Compression.ZipArchiveMode]::Create)
$zip.Dispose()

# --- write the AAR ---------------------------------------------------------
# Built entry by entry on purpose: ZipFile.CreateFromDirectory on Windows
# PowerShell 5.1 writes backslash separators, and Gradle only looks for
# jni/<abi>/libxxx.so with forward slashes. Silent, and the AAR would just
# ship no native library.
if (Test-Path -LiteralPath $aarPath) { Remove-Item -LiteralPath $aarPath -Force }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $aarPath) | Out-Null

$entriesToAdd = @(
    @{ name = 'AndroidManifest.xml'; path = (Join-Path $stage 'AndroidManifest.xml') },
    @{ name = 'classes.jar'; path = $classesJar },
    @{ name = 'R.txt'; path = (Join-Path $stage 'R.txt') },
    @{ name = 'proguard.txt'; path = (Join-Path $stage 'proguard.txt') },
    @{ name = "jni/$Abi/libcamframe.so"; path = $soPath },
    @{ name = 'META-INF/com/android/build/gradle/aar-metadata.properties'; path = (Join-Path $metadataDir 'aar-metadata.properties') }
)

$zip = [System.IO.Compression.ZipFile]::Open($aarPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($entry in $entriesToAdd) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $entry.path, $entry.name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
}

if (-not (Test-Path -LiteralPath $aarPath)) { throw "AAR was not written: $aarPath" }
Write-Host "aar:   $aarPath ($((Get-Item -LiteralPath $aarPath).Length) bytes)"

$zip = [System.IO.Compression.ZipFile]::OpenRead($aarPath)
$entries = @($zip.Entries | ForEach-Object { $_.FullName })
$zip.Dispose()
Write-Host 'entries:'
$entries | ForEach-Object { Write-Host "  $_" }
if ($entries -notcontains "jni/$Abi/libcamframe.so") { throw "AAR is missing jni/$Abi/libcamframe.so" }
if ($entries -notcontains 'AndroidManifest.xml') { throw "AAR is missing AndroidManifest.xml" }
if ($entries -notcontains 'classes.jar') { throw "AAR is missing classes.jar" }

Write-Host 'OK'
