# Prepares the in-project Godot Android build template for the YoudooSkeleton plugin.
#
#   1. Installs res://android/build from the 4.6.3 export templates (if missing).
#   2. Adds the manifest entries the YoudooGame SDK bind requires:
#        - <uses-permission android:name="com.sdt.game.service.ACCESS"/>   (normal, install-granted)
#        - <queries><package android:name="com.sdt.game.service"/></queries> (Android 11+ visibility)
#        - <meta-data org.godotengine.plugin.v2.YoudooSkeleton .../>       (Godot 4.2+ plugin discovery)
#   3. Re-applies the project's Java overrides from android/build-overrides/,
#      including GodotApp.java's native remote-key hook (tag GodotRemoteInput).
#      The overrides live outside the generated android/build/ tree, so a
#      template reinstall cannot silently lose them.
#   4. Adds the YOUDOO_JAVA_HOME hook to gradlew.bat.
#
# The script is idempotent: running it twice changes nothing. Edit the override
# file, not the generated android/build/ copy (this script overwrites it).
#
# Usage:  powershell -NoProfile -File tools\setup_android_build.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$buildDir = Join-Path $root 'android\build'
$manifestPath = Join-Path $buildDir 'src\main\AndroidManifest.xml'
$gradlewPath = Join-Path $buildDir 'gradlew.bat'
$androidSourceZip = Join-Path $env:APPDATA 'Godot\export_templates\4.6.3.stable\android_source.zip'

# --- 1. install the build template -------------------------------------------
if (-not (Test-Path (Join-Path $buildDir 'build.gradle'))) {
    if (-not (Test-Path $androidSourceZip)) { throw "Missing export template: $androidSourceZip" }
    Write-Host "Installing Android build template from $androidSourceZip"
    $zipCopy = Join-Path $env:TEMP 'godot_android_source.zip'
    Copy-Item $androidSourceZip $zipCopy -Force
    if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
    Expand-Archive -Path $zipCopy -DestinationPath $buildDir -Force
} else {
    Write-Host "Android build template already present"
}

# Keep Godot's resource importer away from the gradle project and the SDK aars.
$gdignore = Join-Path $root 'android\.gdignore'
if (-not (Test-Path $gdignore)) {
    Set-Content -Path $gdignore -Value '' -NoNewline
}

# Godot refuses to build an in-project template without this marker (written by
# "Install Android Build Template"). For the default template it is the Godot
# version; a custom android_source_template would use "<path> [<md5>]".
$buildVersion = Join-Path $root 'android\.build_version'
if (-not (Test-Path $buildVersion)) {
    Set-Content -Path $buildVersion -Value '4.6.3.stable' -NoNewline
    Write-Host "android/.build_version: created"
}

# --- 2. patch the app manifest ------------------------------------------------
$manifest = Get-Content $manifestPath -Raw

$permissionsBlock = @"
    <!-- YoudooGame SDK body tracking (workstream A). -->
    <uses-permission android:name="com.sdt.game.service.ACCESS" />

    <!-- Android 11+ package visibility: without this bindService() silently returns false. -->
    <queries>
        <package android:name="com.sdt.game.service" />
    </queries>

"@

$metadataBlock = @"
        <!-- Godot 4.2+ Android plugin discovery (v2 meta-data). -->
        <meta-data
            android:name="org.godotengine.plugin.v2.YoudooSkeleton"
            android:value="com.youdoo.godot.YoudooSkeletonPlugin" />

"@

if ($manifest -notmatch 'com\.sdt\.game\.service\.ACCESS') {
    $anchor = '    <supports-screens'
    $index = $manifest.IndexOf($anchor)
    if ($index -lt 0) { throw "Cannot find <supports-screens> in $manifestPath" }
    $manifest = $manifest.Substring(0, $index) + $permissionsBlock + $manifest.Substring($index)
    Write-Host "manifest: added SDK permission + <queries>"
} else {
    Write-Host "manifest: SDK permission already present"
}

if ($manifest -notmatch 'org\.godotengine\.plugin\.v2\.YoudooSkeleton') {
    $appIndex = $manifest.IndexOf('<application')
    if ($appIndex -lt 0) { throw "Cannot find <application> in $manifestPath" }
    $tagEnd = $manifest.IndexOf('>', $appIndex)
    if ($tagEnd -lt 0) { throw "Cannot find end of <application> tag in $manifestPath" }
    $insertAt = $tagEnd + 1
    # Skip the newline so the metadata lands on its own line.
    if ($insertAt -lt $manifest.Length -and $manifest[$insertAt] -eq "`n") { $insertAt++ }
    $manifest = $manifest.Substring(0, $insertAt) + $metadataBlock + $manifest.Substring($insertAt)
    Write-Host "manifest: added plugin v2 meta-data"
} else {
    Write-Host "manifest: plugin meta-data already present"
}

# The hook relies on the stock activity registration; fail loudly instead of
# shipping an APK whose custom GodotApp class is never instantiated.
if ($manifest -notmatch 'android:name="(\.GodotApp|com\.godot\.game\.GodotApp)"') {
    throw "AndroidManifest.xml does not register GodotApp as the activity; the remote-key hook would not run."
}

Set-Content -Path $manifestPath -Value $manifest -NoNewline

# --- 2b. apply project Java overrides ----------------------------------------
# The Godot export template is generated and may be deleted/reinstalled. The
# canonical copy of GodotApp.java (with the GodotRemoteInput hook) lives in
# android/build-overrides/, and every setup run copies it back into the template.
$overridesDir = Join-Path $root 'android\build-overrides'
if (-not (Test-Path $overridesDir)) { throw "Missing override directory: $overridesDir" }

Get-ChildItem -Path $overridesDir -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($overridesDir.Length + 1)
    $target = Join-Path $buildDir $relative
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
}
Write-Host "build overrides: applied from $overridesDir"

$appJava = Join-Path $buildDir 'src\main\java\com\godot\game\GodotApp.java'
if (-not (Select-String -LiteralPath $appJava -Pattern 'GodotRemoteInput' -Quiet)) {
    throw "GodotApp.java override is missing the GodotRemoteInput hook: $appJava"
}
if (-not (Select-String -LiteralPath $appJava -Pattern 'dispatchKeyEvent' -Quiet)) {
    throw "GodotApp.java override is missing dispatchKeyEvent: $appJava"
}
Write-Host "build overrides: GodotApp.java remote-key hook present"

# --- 3. gradlew.bat: honour YOUDOO_JAVA_HOME ----------------------------------
$gradlew = Get-Content $gradlewPath -Raw
if ($gradlew -notmatch 'YOUDOO_JAVA_HOME') {
    $hook = @"
@rem --- PoseSnake host workaround -------------------------------------------
@rem The security policy on this machine denies file creation to JVMs launched
@rem from D:\android_tc\jdk (java.io.IOException: Access denied / AccessDeniedException).
@rem Godot exports JAVA_HOME from 'export/android/java_sdk_path'; when
@rem YOUDOO_JAVA_HOME points at a usable JDK copy, use that instead.
if defined YOUDOO_JAVA_HOME set "JAVA_HOME=%YOUDOO_JAVA_HOME%"
@rem ------------------------------------------------------------------------

"@
    $anchor = 'if defined JAVA_HOME goto findJavaFromJavaHome'
    $index = $gradlew.IndexOf($anchor)
    if ($index -lt 0) { throw "Cannot find JAVA_HOME check in $gradlewPath" }
    $gradlew = $gradlew.Substring(0, $index) + $hook + $gradlew.Substring($index)
    Set-Content -Path $gradlewPath -Value $gradlew -NoNewline
    Write-Host "gradlew.bat: added YOUDOO_JAVA_HOME hook"
} else {
    Write-Host "gradlew.bat: hook already present"
}

Write-Host "Android build template ready at $buildDir"
