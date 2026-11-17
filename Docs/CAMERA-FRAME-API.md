# Camera frames inside Godot: the RGBA path

Status: **plugin + bridge API implemented, JNI reader built and packaged.**
Deliberately **not** wired into the HUD / camera box - another workstream owns
`src/main.gd`, `src/present/**` and `scenes/**` and will call this API.

Everything here is inert off-device: without a bound `IGameServiceV1_0_3` the pump
does not start, `camera_frames_supported()` is false and `camera_frame_poll()` is `{}`.

---

## 0. TL;DR

| Question | Answer |
|---|---|
| Can we call the SDK's `CopyHardwareBufferToMemory*` from the Java plugin? | **No.** Plain C exports, no JNI binding, and Java has no FFI. |
| Can we get the `long` pointer the Unity sample uses? | It is a **native out-param**, and the vendor marks it dead since SDK 4.0. Our AAR is **4.8.0**. |
| Does reflection on `HardwareBuffer.mNativeObject` help? | It may return a `long`, but there is nothing in Java to pass it to. Kept only as a logcat probe. |
| What actually works? | Our own ~200-line JNI shim (`android/native/camframe.c`) using `AHardwareBuffer_fromHardwareBuffer` + `AHardwareBuffer_lockPlanes`, exactly like the vendor's own non-Unity bridge. |
| How is it shipped? | `libcamframe.so` inside `android/plugins/youdoo/youdoo_camframe-release.aar`, added to the plugin gdap's local dependencies. **No Gradle template change, no CMake.** |

Default capture: **15 fps at scale 0.3** (a 1280x720 device frame becomes 384x216 RGBA).

---

## 1. Route (a) is dead: the Unity `CopyHardwareBufferToMemory` trick

The reference implementation is real, but it is a **C# P/Invoke** path and its pointer
never comes from Java.

Evidence:

| Claim | Evidence |
|---|---|
| The `long aHardwareBufferPtr` is an out-param of a native call | `1024-xiexie/game_1024/Assets/Third Party/Youdoo/Scripts/AndroidServerInfo/AndroidParseData.cs:72-74` (`GetFrameInfoBasicByType(frameInfoPtr, ..., out long aHardwareBufferPtr, ...)`), filled at `:195-196` |
| The vendor says the pointer is meaningless since SDK 4.0 | same file `:68-70` and `:210-212`: "SDK 4.0 及之后的版本 ... aHardwareBufferPtr ... 已经作废，返回的值已经没有意义" |
| Our AAR is 4.8.0, not pre-4.0 | `javap -c com.youdoo.androidLibrary.DataTransferBaseHandler` constructor: `ldc "4.8.0"` |
| `CopyHardwareBufferToMemory*` have no JNI binding | `libyoudoo_plugin.so` exports `CopyHardwareBufferToMemory`, `CopyHardwareBufferToMemoryWithScale`, `GetHardwareBufferInfo` as plain names, and `Java_com_youdoo_jni_YoudooPlugin_setHardwareBufferForGraphics` - but **no** `Java_..._CopyHardwareBufferToMemory` |
| No Java class declares them | `javap com.youdoo.jni.YoudooPlugin` lists only `setHardwareBufferForGraphics(HardwareBuffer,long)`, `clearHardwareBufferQueueForGraphics`, `createHwBuffer`, `mapSeg`, `getY8Cb8Cr8420Format`, `getR8G8B8A8UnormFormat`; a constant-pool scan of every class in `classes.jar` for `CopyHardwareBufferToMemory` / `GetHardwareBufferInfo` returns **0 hits** |
| Java cannot call them even with a pointer | Java has no FFI. A `native` method needs `Java_<pkg>_<Class>_<method>` or `RegisterNatives`; neither exists for these symbols. |
| The vendor hit the same wall | `sdk/Tools~/Android/SkeletonBridge/app/src/main/cpp/youdoo_plugin_rpc.cpp:19-25` uses `AHardwareBuffer_fromHardwareBuffer` + `AHardwareBuffer_lock`, called from `CutoutFrameStore.java:169` |

`android.hardware.HardwareBuffer` also has no Java pixel API, `Bitmap.wrapHardwareBuffer`
rejects YUV420 (it requires `RGBA_8888`/`RGBA_F16` plus `GPU_SAMPLED_IMAGE`), and
`FrameInfo` carries no `byte[]`/JPEG. **Do not retry route (a).**

## 2. Route (b): reflection on `mNativeObject`

`HardwareBuffer.mNativeObject` is a hidden field; on Android 11+ (targetSdk 28+) the
hidden-API lists apply, so `getDeclaredField`/`setAccessible` may throw. Even when it
works it only produces a `long` that Java cannot hand to the C exports. It is therefore
**diagnostic only**: the pump probes it once per session and logs

```
[cam] pointer probe: mNativeObject=0x...        (or)  mNativeObject blocked: NoSuchFieldException...
```

so a device log answers the hidden-API question without affecting behaviour.

## 3. Route (c): the shim we build and ship

```
android/native/camframe.c                     # ~200 lines, no C++ runtime, no libc++_shared
android/native/build_camframe.ps1             # cross-compile + package the AAR
android/plugins/youdoo/youdoo_camframe-release.aar
```

JNI entry point (`javap`-able in the jar, `llvm-nm -D`-able in the `.so`):

```
Java_com_youdoo_godot_CameraFrameNative_readRgba(
    JNIEnv*, jclass, jobject hwBuffer, jint srcW, jint srcH,
    jint outW, jint outH, jboolean flipX, jbyteArray out) -> jint bytesWritten | -1
```

Implementation: `AHardwareBuffer_fromHardwareBuffer` -> `AHardwareBuffer_describe` ->
`AHardwareBuffer_lockPlanes(CPU_READ_OFTEN)` -> stride-aware 3-plane read ->
**BT.601 limited-range integer** YUV->RGBA (the vendor's own constants:
`298/409/100/208/516`, `>>8`, clamped) -> nearest-neighbour scale to `outW x outH` ->
optional horizontal flip -> `AHardwareBuffer_unlock` -> `SetByteArrayRegion`.
Alpha is forced to `0xFF`. A direct `RGBA_8888` buffer is copied instead of converted.
Any other format is rejected with a log rather than guessed at.

Build (arm64-v8a, API 30, ~4 s):

```powershell
powershell -NoProfile -File android\native\build_camframe.ps1
# ndk:   D:\tuanjie_editor\2022.3.61t9\...\AndroidPlayer\NDK (api 30, arm64-v8a)
# built: android\native\build\libcamframe.so (8264 bytes)
# symbol OK: Java_com_youdoo_godot_CameraFrameNative_readRgba
# aar:   android\plugins\youdoo\youdoo_camframe-release.aar
```

API 30 is required (not 21): `AHardwareBuffer` and `hardware_buffer_jni.h` are API 26+,
and the app's `minSdk` is already 30 (`export_presets.cfg`, `gradle_build/min_sdk="30"`).

The AAR carries `jni/arm64-v8a/libcamframe.so`, a manifest (`minSdkVersion 30`), an empty
`classes.jar`/`R.txt`/`proguard.txt` and `aar-metadata.properties`, mirroring the vendor
AARs. It reaches `jniLibs` through the existing gdap mechanism:

```
[dependencies] local=[... , "res://android/plugins/youdoo/youdoo_camframe-release.aar"]
```

**`libcamframe.so` depends only on `libandroid`, `liblog`, `libdl`, `libc`** - no
`libc++_shared.so`, so no extra packaging.

We deliberately do **not** `System.loadLibrary("youdoo_plugin")`. That library only offers
the unreachable `Copy*` exports plus a Unity-native-plugin ABI (`UnityPluginLoad`,
`GetRenderEventFunc*`), so loading it would add crash surface for no callable benefit. The
shim reads the buffer directly. If the obsolete route is ever revisited, the shim itself
can `dlopen` it on the native side.

## 4. Java plugin API (all `@UsedByGodot`, `com.youdoo.godot.YoudooSkeletonPlugin`)

| Method | Meaning |
|---|---|
| `boolean cameraFramesStart()` | starts the worker; false (and no thread) without a bound V1_0_3 |
| `void cameraFramesStop()` | stops the worker, drops the held frame |
| `boolean cameraFramesRunning()` | worker alive |
| `boolean cameraFramesSupported()` | V1_0_3 bound **and** `libcamframe.so` loaded |
| `boolean cameraFramesRate(int fps)` | 1..30, default 15 |
| `boolean cameraFramesScale(float s)` | 0.05..1.0, default 0.3 |
| `long cameraFrameSeq()` | newest published frame number (0 = none) |
| `int cameraFrameWidth()` / `cameraFrameHeight()` | size of that frame |
| `byte[] cameraFrameBytes()` | newest RGBA8 bytes (pump-owned; copy) or null |
| `String cameraFrameBytesBase64()` | same frame, base64 (only for bridges without `byte[]`) |
| `String cameraFrameInfoJson()` | `{running,reader,fps,scale,frames,drops,missing,errors,seq,size,src,format[,readerError][,probe][,error]}` |

Worker design: one thread (`YoudooCameraFrames`), sleeps to the fps period, asks the host
for the newest **pose** timestamp and skips the binder call when it has not changed (the
service is a lookup by frame time, so re-fetching the same stamp is wasted work),
`getFrameBuffer(t)` -> convert -> publish, `close()` in a `finally`. Exactly **one** frame
is held: a newer frame overwrites it and increments `drops` when the previous one was
never read, so a slow consumer misses frames instead of growing a queue. The RGBA
`byte[]` is reused while the scaled size is unchanged, so steady state allocates 0 B per
frame. A pose frame older than 2 s is not offered to the pump.

Logging (tag `YoudooSkeleton`, `libcamframe` logs under `camframe`):

```
[cam] start fps=15 scale=0.3 reader=ok|MISSING: ...
[cam] first frame 1280x720 format=0x23 Y8Cb8Cr8_420
[cam] frames=15 drops=0 size=1280x720
[cam] stop frames=312 drops=4 missing=0 errors=0
```

## 5. GDScript API (`src/youdoo_bridge.gd`, autoload `YoudooBridge`)

```gdscript
func camera_frames_supported() -> bool                       # pixels possible?
func camera_frames_start(rate: int = 0, scale: float = 0.0) -> bool   # 0 = plugin defaults
func camera_frames_stop() -> void                            # also called by stop()
func camera_frames_running() -> bool
func camera_frame_info() -> Dictionary                       # diagnostics, stable keys
func camera_frame_poll() -> Dictionary                       # {} or {seq,w,h,bytes}
func camera_frame_to_texture(frame: Dictionary, flip_x := false, flip_y := false) -> ImageTexture
```

```gdscript
YoudooBridge.start()
YoudooBridge.camera_frames_start()          # 15 fps, scale 0.3
# ... every frame / on a timer:
var frame: Dictionary = YoudooBridge.camera_frame_poll()
if not frame.is_empty():
    var texture := YoudooBridge.camera_frame_to_texture(frame)   # caller owns it
    $CameraRect.texture = texture
```

`camera_frame_poll()` returns each sequence number **once**; `{}` means "nothing new".
`bytes` is exactly `w*h*4` RGBA8, top-left origin, alpha 255, already scaled.
`camera_frame_to_texture()` builds a fresh `ImageTexture` from
`Image.create_from_data(w, h, false, FORMAT_RGBA8, bytes)`; mirroring is **ours**
(`Image.flip_x()` / `flip_y()`), never the SDK's signed-UV trick, so it is deterministic
and identical for both camera paths. It returns `null` on a malformed frame.

Transport: the fast path is `byte[]` -> `PackedByteArray`. If this Godot build cannot
marshal `byte[]`, the bridge logs one line, permanently switches that session to the
base64 accessor and keeps working (slower, one string per frame). Registering the method
is safe either way: `GodotPlugin.onRegisterPluginWithGodotNative()` collects
`@UsedByGodot` methods into a `HashSet` with no return-type filtering (verified with
`javap -c` on the 4.6.3 template), so an unsupported type could only affect a call, never
plugin registration.

## 6. One-time device checks (owner approval required - this task never runs adb)

Package `com.youdoo.posesnake`, `minSdk 30`. Shipped lifecycle
(`src/main.gd::_camera_pump_sync`): the pump runs **only while a screen has a
camera box** — READY slot cards, COUNTDOWN, PLAY, PAUSE — and is stopped on
MODE_SELECT / MODE_SETTLE, so it never decodes unseen (the plugin's `drops`
counter used to climb on the menu). Do **not** start it at boot or next to
`YoudooBridge.start()`: that is the bug this lifecycle replaced. The on-device
debug hooks are F4 (camera-live overlay) and F5 (1P PiP rect).

```powershell
# 1. install the coordinator's fresh export, then clear and capture logs
adb -s <serial> install -r build\PoseSnake.apk
adb -s <serial> logcat -c
adb -s <serial> shell am force-stop com.youdoo.posesnake
adb -s <serial> shell monkey -p com.youdoo.posesnake -c android.intent.category.LAUNCHER 1
adb -s <serial> logcat -s YoudooSkeleton:I camframe:I AndroidRuntime:E
```

Expected, in order:

```
I YoudooSkeleton: [cam] start fps=15 scale=0.3 reader=ok
I camframe:      (nothing on the happy path; errors only)
I YoudooSkeleton: [cam] first frame 1280x720 format=0x23 Y8Cb8Cr8_420
I YoudooSkeleton: [cam] pointer probe: mNativeObject=0x... | blocked: <exception>
I YoudooSkeleton: [cam] frames=15 drops=0 size=1280x720     # once per second
```

Second check, in Godot itself (temporary print in `src/main.gd`, its owner's call):

```gdscript
print("[camtest] supported=%s info=%s" % [
    YoudooBridge.camera_frames_supported(), YoudooBridge.camera_frame_info()])
```

Expected: `supported=true` and `"reader":true,"frames":>0,"size":"384x216"`.

What each failure means:

| logcat | meaning |
|---|---|
| `[cam] pixel reader libcamframe.so unavailable` | AAR not packaged / wrong ABI (device must be arm64-v8a) |
| `[cam] start refused: IGameServiceV1_0_3 not bound` | call `YoudooBridge.start()` first / binder not bound |
| `[cam] getFrameBuffer(...) returned null` | frame time already gone; check `missing` growth |
| `camframe: unsupported format 0x..` | service returned a format other than YUV420/RGBA8 - report the value |
| `camframe: YUV420 lockPlanes failed` | buffer not CPU-readable - report it, no fallback exists |

## 7. Risks

1. **Format drift.** We accept `Y8Cb8Cr8_420` (0x23, proven by the vendor's own NDK
   reader) and `RGBA_8888`; anything else is rejected and logged. Fallback: none, report
   the hex value.
2. **Lock failure / `CPU_READ` unsupported.** Some vendor buffers are GPU-only. If
   `lockPlanes` fails, the pump logs and counts errors; the overlay path
   (`camera_live_*`) remains the fallback.
3. **Cost at scale 1.0.** 0.3 keeps a 720p frame at 384x216 (331 KB, ~5 MB/s at 15 fps).
   At 1.0 it is 3.7 MB/frame - measure before raising it on this Amlogic box.
4. **Base64 fallback** if Godot cannot marshal `byte[]`: correct but string-heavy; the
   log line names it, and `camera_frame_info()["reader"]` stays true.
5. **ABI.** Only `arm64-v8a` is built. On armv7/x86 the `.so` fails to load (caught) and
   the pump degrades to a frame probe. Add ABIs in `build_camframe.ps1` if ever needed.
6. **16 KB page devices.** The `.so` is built with 4 KB segment alignment
   (`LOAD ... 0x1000`) and `targetSdk 35`; Android 15 devices with 16 KB pages would
   refuse it. Not an issue on this box; add `-Wl,-z,max-page-size=16384` when the NDK is
   new enough if that changes.
7. **Orientation.** The shim does **not** mirror (flipX is false; GDScript owns
   mirroring). Whether the raw buffer is already selfie-mirrored is a device property -
   `Docs/SDK-CAMERA-PIPELINE.md` section 4 explains the SDK's convention; verify with one
   screenshot and use `flip_x` in `camera_frame_to_texture()`.

## 8. Maintenance

Rebuild after editing `android/native/camframe.c`:

```powershell
powershell -NoProfile -File android\native\build_camframe.ps1     # .so + AAR, ~4 s
powershell -NoProfile -File tools\build_plugin.ps1 -Jdk C:\jdkcopy # Java plugin jar
```

Keep the JNI signature in `CameraFrameNative.java` and `camframe.c` in lock-step; the
symbol name is checked by `build_camframe.ps1`, but the argument list is not.
