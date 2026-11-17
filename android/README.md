# YoudooSkeleton — Godot Android plugin for YoudooGame body tracking (workstream A)

Binds the YoudooGame SDK AIDL service (`com.sdt.game.service`) from a Godot 4.6
Android build and exposes the newest body-tracking frame to GDScript as JSON.
Gameplay lives in another workstream and only consumes `YoudooBridge`.

## Layout

```
android/
  plugins/youdoo_skeleton.gdap          # plugin descriptor (binary + dependencies)
  plugins/youdoo/godot-youdoo-skeleton.jar   # compiled plugin (git-ignored, built by tools/)
  plugins/youdoo/*.aar                  # the 6 SDK aars, copied verbatim from the SDK
  plugins/youdoo/youdoo_camframe-release.aar  # libcamframe.so, built here (not from the SDK)
  native/camframe.c                     # JNI YUV420->RGBA reader for the camera-frame path
  native/build_camframe.ps1             # cross-compile + repackage that AAR (arm64-v8a)
  src/com/youdoo/godot/YoudooSkeletonPlugin.java
  src/com/youdoo/godot/CameraFramePump.java    # 15 fps RGBA pump, single-slot holder
  src/com/youdoo/godot/CameraFrameNative.java  # the one native method the shim exports
  build-overrides/                      # canonical files copied into build/ by setup_android_build.ps1
    src/main/java/com/godot/game/GodotApp.java   # native RCU key hook (GodotRemoteInput)
  build/                                # Godot gradle build template (generated, see below)
  .gdignore                             # keep Godot's importer out of this tree
src/youdoo_bridge.gd                    # autoload `YoudooBridge`
src/main.gd, scenes/main.tscn           # acceptance probe UI
tools/setup_android_build.ps1           # installs + patches the build template (idempotent)
tools/build_plugin.ps1                  # javac + jar for the plugin
tools/verify_godotapp_javac.ps1         # standalone javac check for the RCU hook
tools/export_apk.ps1                    # godot --export-debug wrapper
```

## How the pieces fit (Godot 4.6 specifics)

* **Plugin discovery is by manifest meta-data, not by `.gdap`.** Since Godot 4.2
  the runtime registry (`GodotPluginRegistry`) enumerates
  `org.godotengine.plugin.v2.*` meta-data entries in the merged manifest and
  instantiates the class named by the value with `ClassName(Godot)`. The
  `[plugin] name` key in the gdap is legacy (v1) and is ignored by 4.6, so
  `tools/setup_android_build.ps1` adds the meta-data to
  `android/build/src/main/AndroidManifest.xml`.
* **The gdap is still what wires native dependencies into gradle.** Godot passes
  `[config] binary` + `[dependencies] local` as `-Pplugins_local_binaries` and
  `[dependencies] remote` as `-Pplugins_remote_binaries`, which the template's
  `build.gradle` turns into `implementation files(...)` / `implementation dep`.
  Paths in the gdap are written as `res://...` absolute paths so Godot
  globalizes them; bare relative paths stay `res://` and would be handed to
  gradle unresolved.
* **The plugin config must be enabled in the preset**: `plugins/YoudooSkeleton=true`
  in `export_presets.cfg`, otherwise `get_enabled_plugins()` filters it out.
* **Kotlin runtime is required.** `FrameInfo`/`DetectBox`/`KeyPoint` are Kotlin
  classes and the SDK aar ships no `kotlin/*` classes, so the plugin declares
  `org.jetbrains.kotlin:kotlin-stdlib:2.1.21` (matches the template's Kotlin
  version) as a remote dependency.
* **Manifest requirements for the bind:**
  * `<uses-permission android:name="com.sdt.game.service.ACCESS"/>` — the service
    is declared with `permission=com.sdt.game.service.ACCESS`, declared
    `prot=normal`, so it is granted at install time.
  * `<queries><package android:name="com.sdt.game.service"/></queries>` — without
    it Android 11+ package-visibility makes `bindService()` return `false`
    silently.
* **Binding**: explicit `ComponentName("com.sdt.game.service",
  "com.sdt.game.service.SdtGameService")` with action
  `com.sdt.game.service.IGameServiceV1_0_3`, then
  `IGameServiceV1_0_3.Stub.asInterface()`. If the binder descriptor is the
  V1_0_2 one, the plugin registers through `IGameServiceV1_0_2` instead.

## Remote-control native hook (`GodotRemoteInput`)

The HP52S0 RCU enumerates as a gamepad (`source=1793`, includes
`SOURCE_GAMEPAD`), so Godot's `GodotInputHandler` sends its keys down the joypad
path: DPAD_* become `JOY_BUTTON_DPAD_*`, and `KEYCODE_DPAD_CENTER` (23) maps to
an invalid button (`p_button = -102`) and is dropped. The GDScript router only
sees `InputEventKey`, which is why a physical press produced zero `[key]` lines.

`android/build-overrides/src/main/java/com/godot/game/GodotApp.java` fixes this
at the Activity level:

* `dispatchKeyEvent` logs every key as
  `GodotRemoteInput: key=<code> action=<down|up> name=... source=...`.
* Every remote key (DPAD 19–22, OK 23/66/96/160/85/62, BACK 4/111) is consumed
  and re-dispatched as a **pure-keyboard** `KeyEvent` (`deviceId=-1`,
  `scanCode=0`, `source=0`). Godot then translates it through
  `android_keys_utils.h` and the existing router sees a normal `InputEventKey`.
* `KEYCODE_BUTTON_A` (96) has no Godot keyboard mapping, so it is canonicalised
  to `KEYCODE_ENTER` (66) before injection. The original event is consumed, so
  it cannot also fire through the joypad path.
* The platform broadcast `com.youdoo.assistant.SendHotKey` is a fallback channel
  for keys that never reach `dispatchKeyEvent`; it is de-duplicated against a
  recent `dispatchKeyEvent` of the same key.

`android/build/` is generated. `tools/setup_android_build.ps1` re-applies
everything under `android/build-overrides/` on every run and fails if the
generated `GodotApp.java` lost the hook, so reinstalling the template cannot
silently drop it. Edit the override copy, not `android/build/...`.

Verify the Java alone (no Gradle, no APK):

```powershell
powershell -NoProfile -File tools\verify_godotapp_javac.ps1 -Jdk C:\jdkcopy
```

See `Docs/REMOTE-INPUT.md` for the device test and key table.

## Build

```powershell
# 1. install + patch the gradle build template (safe to re-run)
powershell -NoProfile -File tools\setup_android_build.ps1

# 2. compile android/src into android/plugins/youdoo/godot-youdoo-skeleton.jar
powershell -NoProfile -File tools\build_plugin.ps1 -Jdk C:\jdkcopy

# 2b. only after editing android/native/camframe.c: rebuild the RGBA reader + its AAR
powershell -NoProfile -File android\native\build_camframe.ps1

# 3. godot export (gradle build; needs network on first run)
powershell -NoProfile -File tools\export_apk.ps1 -Jdk C:\jdkcopy
# equivalent:
#   $env:YOUDOO_JAVA_HOME='C:\jdkcopy'
#   Godot_v4.6.3-stable_win64.exe --headless --path <repo> --export-debug "Android" build/PoseSnake.apk
```

### Host caveat: `-Jdk` / `YOUDOO_JAVA_HOME`

On this machine the security policy denies **file creation to any JVM launched
from `D:\android_tc\jdk`**, including the exact same binary:

```
java.nio.file.AccessDeniedException: C:\dsh-jtest\from-original-java.txt
        at java.base/sun.nio.fs.WindowsException...
# identical jar/class, JDK copied to C:\jdkcopy, writes fine
```

`javac` fails the same way (`error while writing Plain: ...Plain.class`), and
that is also why `keytool` cannot create keystores here. Godot exports
`JAVA_HOME` from Editor Settings `export/android/java_sdk_path`
(`D:/android_tc/jdk`) right before invoking `gradlew.bat`, so
`tools/setup_android_build.ps1` adds this hook to `android/build/gradlew.bat`:

```bat
if defined YOUDOO_JAVA_HOME set "JAVA_HOME=%YOUDOO_JAVA_HOME%"
```

With `YOUDOO_JAVA_HOME` unset the stock behaviour is unchanged. Use a copy of the
same JDK (tested: `robocopy D:\android_tc\jdk C:\jdkcopy /E`, JDK 17.0.20.1).

## Runtime

`YoudooBridge` (autoload) polls `frameCount()` at 20 Hz and only parses
`latestFrameJson()` when it changed, emits `frame_received`, and reports
`status()`/`is_tracking()`. On desktop/editor it is inert (`is_available()`
returns false) — nothing crashes.

Logcat tags: `YoudooSkeleton` (one line per second while frames arrive, one idle
heartbeat every 5 s while bound but silent) and `GodotRemoteInput` (one line per
physical RCU key, plus the synthetic injection result).

## Camera live (multi-view `cameraLiveView` / `cameraLiveClear`)

The plugin can ask the device service to show camera previews through
`IGameServiceV1_0_3.setCameraLiveOnScreen(id, on, x1,y1,x2,y2, x3,y3,x4,y4, mode)`
and `clearAllCameraLiveOnScreen()`. **No texture enters Godot**: the service
owns a `SurfaceView` inside a `WindowManager` overlay window, so this costs one
Binder call. That also means the preview is drawn **above** the app, not behind
it (decompiled from `com.sdt.game.service` 1.0.14; see
`Docs/CAMERA-LIVE-EVIDENCE.md`).

The service keys views by `id`, so the plugin stores one wanted `CameraView`
per id and re-sends all of them after a bind reconnect:

| method | use |
|---|---|
| `cameraLiveView(id, on, src x1..y2, dst x1..y2, mode)` | drive any id (2P uses 0 and 1) |
| `cameraLiveClear()` | mark every id off + `clearAllCameraLiveOnScreen()` (teardown) |
| `cameraLive(on)` / `cameraLiveRect(...)` / `cameraLiveMode(mode)` | legacy single-view id 0 (still supported) |
| `cameraLiveActive()` / `cameraLiveSupported()` | state read-outs |

`src` may be **inverted** (`x1 > x2` or `y1 > y2`) to ask the native renderer
for a mirror. That is the SDK's own display-mirror mechanism: Unity's
`CameraImageUvRegionUtility.CalculateUvRect` flips by making the UV width
negative. `mode` stays 0 — the SDK never sends another value.

GDScript (`YoudooBridge` autoload):

```gdscript
YoudooBridge.camera_live_supported()
YoudooBridge.camera_live_view(0, true,                     # id, on
    [1.0, 0.0, 0.0, 1.0],                                  # A = source crop (inverted = mirror)
    [0.76, 0.74, 0.98, 0.96],                              # B = destination on screen
    0)                                                     # opaque AIDL mode
YoudooBridge.camera_live_clear()                           # all ids
# legacy single-view form, still supported:
YoudooBridge.camera_live_start(Rect2(1,0,-1,1), Rect2(0.76,0.74,0.22,0.22), 0)
```

The SDK's camera video is mirrored (`MatchSessionConfig.mirrorPlayerTrackingHorizontally`
exists "to adapt to mirrored video"; the provider's tracking coordinates are
documented as mirrored), and the game's pose layer lives in that mirrored space
(`ps_pose_input.gd` uses `1 - x`). The shipped camera variant therefore inverts
A.x; the source crop stays the right half for slot 0 in 2P because the mirrored
view puts it back on the left. 2P sends two views: id 0 = raw right half ->
bottom-left, id 1 = raw left half -> bottom-right.

On device: **F4** toggles camera live, **F5** moves the 1P PiP, and
**F6 / remote MENU (82)** cycle the three camera variants:

1. `1/3 SDK mirror H` — A.x inverted, pose `1-x` (shipped default)
2. `2/3 mirror H+V` — both axes inverted (control if the renderer needs both)
3. `3/3 raw frame` — A normal (old behaviour / control)

**F7 / remote INFO (165)** toggles the pose convention independently, live
(`ps_pose_input.mirror_x`, logged as `[pose] mirror=on|off (source=key)`), so
all four preview x pose combinations are reachable without a rebuild.

`GodotApp.canonicalKeyCode` maps MENU -> KEYCODE_F6 and INFO -> KEYCODE_F7;
unmapped keys (including adb's `input keyevent 136`/`137`) fall through to
Godot untouched.
Debug overrides: `--camera-live` (full screen), `--camera-live-pip`,
`--camera-live-rect=x,y,w,h`, `--camera-live-mode=N`, `--camera-variant=N`,
`--no-pose-mirror`. The game enables it in
READY/COUNTDOWN/PLAY/PAUSE and clears every id in MODE_SELECT/SETTLE.
All calls are logged under `YoudooSkeleton` (`cameraLive ON/OFF/CLEAR ...`) and
`[camera]` (exact A/B edges, mode, variant, pose convention).

## Camera frames (RGBA texture path)

The overlay above cannot sit behind the game UI, so the plugin also has a **texture**
path: `cameraFramesStart()` runs a worker at a configurable rate (default **15 fps**) that
calls `getFrameBuffer(frameTimeMs)` for the newest pose frame, converts the YUV420
`HardwareBuffer` to RGBA8 at **scale 0.3** (384x216 for a 720p device frame) and keeps
exactly one newest frame for GDScript to pull. `CameraFramePump` reuses one `byte[]` while
the scaled size is unchanged, so steady state allocates nothing per frame.

The conversion lives in `native/camframe.c` -> `libcamframe.so`, shipped inside
`plugins/youdoo/youdoo_camframe-release.aar`. It is **not** the SDK's
`CopyHardwareBufferToMemory*`: those are plain C exports with no JNI binding, and the
pointer their Unity sample uses is a native out-param the vendor marks obsolete since SDK
4.0 (this build is 4.8.0). See `Docs/CAMERA-FRAME-API.md` for the evidence and the exact
`AHardwareBuffer_fromHardwareBuffer` + `lockPlanes` recipe.

GDScript (`YoudooBridge` autoload):

```gdscript
YoudooBridge.camera_frames_supported()          # binder + libcamframe.so ready?
YoudooBridge.camera_frames_start()              # 15 fps, scale 0.3 (or pass rate/scale)
var frame := YoudooBridge.camera_frame_poll()   # {} or {seq,w,h,bytes}
if not frame.is_empty():
    $CameraRect.texture = YoudooBridge.camera_frame_to_texture(frame)   # caller owns it
YoudooBridge.camera_frames_stop()               # also called by stop()
```

Mirroring is applied by the bridge (`flip_x`/`flip_y` on the `Image`), never by the SDK's
signed-UV trick. Off-device every call is inert. Logcat: `[cam] start|first frame|stop`
plus `[cam] frames=N drops=N size=WxH` once per second under `YoudooSkeleton`, and
`camframe` for conversion failures.
