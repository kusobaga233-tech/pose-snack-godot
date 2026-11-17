# Camera live (`setCameraLiveOnScreen`) — evidence and decision

Read-only investigation, 2026-11-12. Sources are the SDK checkout
(`D:\CODEX-PROJ\yoodou\sdk`), the project plugin, and a decompile of the device
service `Tools~\Android\DeviceDependencies\com.sdt.game.service-1.0.14.apk`
(installed on the test device is 1.0.15, same AIDL surface).

## 1. AIDL surface

`javap` of `YoudooAndroidLibrary-release.aar` → `classes.jar`:

```
com.sdt.game.service.IGameServiceV1_0_3:
  void setCameraLiveOnScreen(int, boolean, float, float, float, float,
                            float, float, float, float, int)
  void clearAllCameraLiveOnScreen()
```

The generated proxy uses transaction codes 6 and 7 (`bipush 6` / `bipush 7`).
The 11 arguments are, in wire order:

| # | type | meaning (inferred, see §3) |
|---|---|---|
| 0 | int | view/camera id; reference app uses `0` |
| 1 | boolean | on/off |
| 2–5 | float | normalized rect A: `x1,y1,x2,y2` |
| 6–9 | float | normalized rect B: `x1,y1,x2,y2` |
| 10 | int | mode (passed straight to the native renderer; reference app uses `0`) |

There is **no Surface / SurfaceControl / window token argument**. The service
creates and owns whatever it needs, so a plain Godot app can call this.

## 2. SDK reference implementation (the intended usage)

`Tools~\Android\SkeletonBridge\app\src\main\java\com\youdoo\skeletonbridge\SdtGameServiceClient.java:157-170`

```java
void setCameraLiveOnScreen(boolean enabled) throws RemoteException {
    service.setCameraLiveOnScreen(0, enabled, 0f, 0f, 1f, 1f, 0f, 0f, 1f, 1f, 0);
}
void clearAllCameraLiveOnScreen() throws RemoteException {
    service.clearAllCameraLiveOnScreen();
}
```

`SkeletonBridgeService.java:320-330` sends it from `onGameServiceReady()` when
the `enable_camera_live` extra is set; `:142-143` reads that extra;
`:270-280` clears it when the service stops; `:245` also clears in `onDestroy`.
The RPC variant (`BridgeRpcServer.java:639-653`) simply forwards 11 args;
validation (`:1319-1338`) requires exactly `int, boolean, 8 numbers, int`.

Conclusion: the supported call pattern is full-screen (`0,0,1,1` twice, mode 0),
made as soon as the V1_0_3 binder is ready, and `clearAll` on teardown.

## 3. What the device service actually does (decompile)

`dexdump -d` of the 1.0.14 APK (class/method names shrunk, strings intact):

* `com.sdt.game.service.l.onTransact` (the V1_0_3 stub) reads exactly
  `int, int(bool), 8 × float, int` for the camera transaction and calls
  `Lv/d;.f:(IZFFFFFFFFI)V`.
* `v/d.f` stores the request in a `HashMap<Integer, x/j>` held by
  `com.sdt.game.service.view.d`:

  ```java
  x.j e = map.get(id);
  if (e == null) map.put(id, new x.j(enabled, new RectF(x1,y1,x2,y2),
                                             new RectF(x3,y3,x4,y4), mode));
  else { e.a = enabled; e.b.set(...); e.c.set(...); e.d = mode; }
  ```

  So the 8 floats are **two normalized `RectF`s**, and `id` is a per-view key
  (`clearAllCameraLiveOnScreen` clears the whole map). This is not a person id;
  the cutout/person-target API is a different method (`setTrackSegment`).
* `com.sdt.game.service.tools.HardwareBufferRenderer.c` filters entries with
  `a == true`, flattens rect `b` and rect `c` into two `float[]` plus the modes
  into an `int[]`, and calls `nativeSubmit(...)` with the camera
  `HardwareBuffer`. Which pair is the source crop and which is the destination
  rect on screen is decided in native code; the only known-good call (the SDK
  reference app) passes `0,0,1,1` for **both** pairs, so that is what this
  project sends by default. Values are normalized (0..1), not pixels.
* The preview view is `com.sdt.game.service.view.OverlaySurfaceView`:

  ```java
  class OverlaySurfaceView extends SurfaceView implements SurfaceHolder.Callback {
      OverlaySurfaceView(...) {
          super(...);
          getHolder().addCallback(this);
          setZOrderOnTop(true);        // above its window's other surfaces
          getHolder().setFormat(-3);   // PixelFormat.TRANSLUCENT
          ...
      }
      void a(Integer x, Integer y, Integer w, Integer h) {
          WindowManager wm = (WindowManager) context.getSystemService("window");
          int type = isSystemUid ? 2006 /* TYPE_SYSTEM_OVERLAY */
                                 : 2038 /* TYPE_APPLICATION_OVERLAY */;
          WindowManager.LayoutParams lp =
              new WindowManager.LayoutParams(w, h, type, 0x18 /* NOT_FOCUSABLE|NOT_TOUCHABLE */, -3);
          lp.gravity = 0x33 /* TOP|START */;
          lp.x = x; lp.y = y;
          new Handler(Looper.getMainLooper()).post(() -> wm.addView(this, lp));
      }
  }
  ```

  When the caller passes `null` bounds (the path used by the camera live
  requests) `w = h = -1` (MATCH_PARENT). **The camera is a translucent
  WindowManager overlay window drawn ABOVE the foreground app**, not a layer
  behind it. It is not focusable/touchable, so input still reaches the game.

## 4. The frame-buffer alternative

`IGameServiceV1_0_3.getFrameBuffer(long frameTimeMs)` returns the camera
`HardwareBuffer` for a pose frame:

* `CutoutFrameStore.java:157` calls `service.getFrameBuffer(frame.getFrameTimeMs())`,
  then `:159-172` reads it through **native** code (`readRgbaNative`, and it
  first runs `YoudooPlugin.mapSeg`).
* `HardwareBufferJpegEncoder.java:48` uses
  `convertYuv420ToNv21Native(...)`; `JniHardwareBuffer` exposes
  `getY8Cb8Cr8420` / `getR8G8B8A8Unorm`, i.e. the camera buffer is YUV420.
* Java has no `HardwareBuffer` lock API, and `Bitmap.wrapHardwareBuffer` does
  not accept YUV. A Godot texture path therefore needs NDK code to lock the
  buffer, convert YUV→RGBA and hand pixels to GDScript. This project has no
  NDK/CMake build step, so that is a separate workstream, not a plugin method.

## 5. Decision

Implement the **system-composited path** (no texture upload, no native code,
works from a plain Godot app), but:

* it is an **on-top overlay**, so full screen would cover the arena. The shipped
  default is therefore a bounded bottom-right picture-in-picture, armed at boot;
  `--camera-live` restores the full-screen SDK reference call. The game places
  it with two normalized rects (`camera_live_start(source_rect, dest_rect,
  mode)`).
* the game keeps the existing pose path untouched; camera live is driven only
  from READY/COUNTDOWN/PLAY/PAUSE and is cleared in SELECT/SETTLE/teardown.
* the true "camera behind the arena" look still needs the frame-buffer + NDK
  path from §4; this change is the cheap half of the product gap and gives the
  device verifier a way to measure the overlay's real z-order.

## 6. How the game uses it

`src/youdoo_bridge.gd` exposes `camera_live_supported()`,
`camera_live_start(source_rect, dest_rect, mode)`, `camera_live_stop()` and
`camera_live_active()`. `source_rect`/`dest_rect` are the two AIDL pairs A/B in
wire order; which one native code treats as the crop and which as the on-screen
destination is not proven, so `src/main.gd` keeps a mode table and sends the
shipped default A=full frame, B=PiP destination. It turns the preview on in
READY / COUNTDOWN / PLAY / PAUSE and clears it in MODE_SELECT / MODE_SETTLE /
teardown. Pause keeps it on because the round is still alive and resume needs no
re-init.

On device the verifier can re-shape it without rebuilding:

* **F4** (`adb shell input keyevent 134`) = camera live on/off (arm/disarm)
* **F5** (`adb shell input keyevent 135`) = move the PiP: bottom-right (shipped)
  → top-left → full screen → back. The selected rect is the "pip" side of the
  active F6 mode, and the call is re-sent immediately.
* **F6** (`adb shell input keyevent 136`) = cycle the two rect pairs and re-send
  immediately (the active mode is logged under `[camera]`):
  1. `A=full, B=pip` — shipped default (best guess: crop the whole frame, show
     it in the bottom-right)
  2. `A=pip, B=full` — swapped order (tests the opposite interpretation)
  3. `A=full, B=full` — full screen, the previously proven-good SDK call
  4. `A=pip, B=pip` — the old broken call (crop bottom-right, show bottom-right)
* **F3** (`adb shell input keyevent 133`) = debug overlay, which shows
  `camera supported/on/armed`, the F6 mode label, both A/B rects, the PiP rect
  and the on-top warning

## 7. Device verification recipe

Device: `YDG01010000063`, adb `D:\platform-tools\adb.exe`, package
`com.youdoo.posesnake`, launcher
`com.youdoo.posesnake/com.godot.game.GodotAppLauncher`.

```powershell
$adb = "D:\platform-tools\adb.exe"
& $adb -s YDG01010000063 install -r build\PoseSnake.apk
& $adb -s YDG01010000063 shell am force-stop com.youdoo.posesnake
& $adb -s YDG01010000063 logcat -b all -c
& $adb -s YDG01010000063 shell am start -n com.youdoo.posesnake/com.godot.game.GodotAppLauncher
# wait for mode select, then focus 双人模式 and confirm (READY / 2P):
& $adb -s YDG01010000063 shell input keyevent 22
& $adb -s YDG01010000063 shell input keyevent 23
# camera live is already ON in READY (bottom-right PiP, mode 1/4). F4 toggles it
# off/on, F5 moves the PiP, F6 cycles the two rect pairs; each logs `[camera]`.
# keep the log:
& $adb -s YDG01010000063 logcat -b all -d | Select-String -Pattern "cameraLive|\[camera\]|YoudooBridge"
```

Expected logcat (tag `YoudooSkeleton` for the Java side; Godot stdout for
`[camera]` / `[YoudooBridge]`):

```
I YoudooSkeleton: cameraLive(True): supported=true binder=IGameServiceV1_0_3 rect=[0.0,0.0,1.0,1.0][0.76,0.74,0.98,0.96] mode=0
I YoudooSkeleton: cameraLive ON: id=0 rect=[0.0,0.0,1.0,1.0][0.76,0.74,0.98,0.96] mode=0 (system overlay above the app) [cameraLive(on)]
[YoudooBridge] camera_live_start(A=[P: (0.0, 0.0), S: (1.0, 1.0)], B=[P: (0.76, 0.74), S: (0.22, 0.22)], mode=0) -> true
[camera] t=... ON camera mode 1/4 A=full,B=pip A=[0.000,0.000,1.000,1.000] B=[0.760,0.740,0.980,0.960] aidl=0 applied=true (ready)
[camera] F6: camera mode 2/4 A=pip,B=full A=[0.760,0.740,0.980,0.960] B=[0.000,0.000,1.000,1.000] wanted=true on=true
```

`supported=false` / `cameraLive ON failed` / `device SDT only exposes
IGameServiceV1_0_2` means the call was not made (logcat would show why).

Expected visual:

1. **Plain launch, then 双人模式 (READY):** a small preview in the lower-right
   showing the player and the whole camera frame (mode 1/4). If it shows a
   zoomed/cropped sliver instead, the pair order is wrong → press **F6**.
2. **F6:** modes 2/4 and 3/4 are the alternatives; 3/4 (`A=full,B=full`) is the
   previously proven-good full-screen call. Record which mode gives a complete,
   correctly placed PiP. Mode 4/4 reproduces the broken old call for comparison.
3. **F5:** moves the PiP to the top-left, then full screen, then back; the
   debug overlay (F3) shows the exact A/B rects that were sent.
4. **Nothing visible while the log says ON:** the service accepted the call but
   the overlay is below the app's opaque GL surface, or SurfaceFlinger rejected
   the add. Capture `adb shell dumpsys window windows | findstr /I
   "com.sdt.game.service"` and `adb shell dumpsys SurfaceFlinger --list` and
   report it; that would contradict the §3 decompile.

Turn it off: F4, or BACK to MODE_SELECT (the game clears it), or
`am force-stop` (plugin `onMainDestroy` clears it). If the screen is covered and
keys do not arrive, `adb shell am force-stop com.youdoo.posesnake` is the
fallback.

## 8. What is still unknown without a device

* Real z-order and whether `mode` changes it (we only know the type is
  `TYPE_APPLICATION_OVERLAY`/`TYPE_SYSTEM_OVERLAY`).
* Whether the two rect pairs are source/destination and whether both must be
  full-screen for correct aspect; only `0,0,1,1` twice is proven.
* Whether the preview survives our app's pause/resume (the service owns it; the
  game only re-sends after a binder reconnect).
* Whether the device SDT 1.0.15 behaves exactly like the 1.0.14 APK decompiled
  here.

## 9. Update 2026-11-12 — A/B rect fix + F6 runtime cycle

Device observation: with the same rect sent for both pairs the PiP showed a
cropped, wrong part of the image, which matches "A is the source crop, B is the
destination". The shipped call is now A=`0,0,1,1` (full frame) and
B=`0.76,0.74,0.98,0.96` (bottom-right PiP), and **F6** cycles the four orders
(§6) at runtime so the owner can confirm or refute the A/B order by hand. A
plain launch uses mode 1/4. No Java/plugin change was needed: `cameraLiveRect`
already takes the 8 floats; `camera_live_start` now takes both rects instead of
duplicating one.

## 10. Update 2026-11-12 — SDK-derived mirror + per-player views

Device observation with §9: A=source / B=destination is confirmed (complete,
correctly placed PiP), but **the picture is left-right reversed relative to the
player's real body**. The SDK explains why and supplies the mirror mechanism.

**The SDK's camera video is mirrored, and its tracked space is mirrored too:**

* `MatchSessionConfig.mirrorPlayerTrackingHorizontally` (default `true`; both
  `MatchSessionConfig_FULL.asset` and `_SPLIT.asset` store `1`) is documented as
  "horizontally mirror the player x before the matching-area calculation, **to
  adapt to a mirrored video**" (`Documentation~/Configuration/catalog.json:6258-6269`;
  `Documentation~/sdk-framework-integration.zh-CN.md:376`).
* `CameraImageView.trackingCoordinatesAreMirrored` defaults to `true`: the
  built-in YouDoo provider reports **mirrored tracking coordinates**
  (`Documentation~/sdk-framework-integration.zh-CN.md:497`;
  `Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageView.cs:29-34`).
  The transform is `x' = 1 - x`
  (`CameraImageTrackingProjectionUtility.cs:75-83`), which is exactly what
  `src/present/ps_pose_input.gd` already does.
* The display flip is a **negative UV width**, never a mode int:
  `source.x += source.width; source.width = -source.width;`
  (`CameraImageUvRegionUtility.cs:183-202`). `mode` is 0 at every SDK call site.
  The Android texture orientation is `BottomLeftFlippedBoth`
  (`YouDooCameraImageOrientationPolicy.cs:47-50`), corrected by the same UV
  projection; `mirrorHorizontally` is `0` in the SDK reference prefab because
  the provider frame is already the mirror.

**Our native overlay** (`setCameraLiveOnScreen`) renders the raw, unmirrored
sensor frame. Since the game's pose space is the SDK's mirrored space (`1-x`),
the overlay must be flipped to agree with the controls. The only lever is the
signed source rect, so the shipped variant is:

* A = full frame with **x inverted** (`x1=1, y1=0, x2=0, y2=1`), B = PiP, mode 0.

**Per-player views (2P):** `setCameraLiveOnScreen` takes a per-view `int id` and
the service keeps a `HashMap<Integer, ...>` (§3), so 2P uses id 0 and id 1.
Slot order is `LeftToRight` (`PlayerTracking.cs:25-61`), slot 0 = left half of
the mirrored frame. Our pose layer assigns slot 0 when `1 - x < 0.5`, i.e. the
raw **right** half, so the mirrored view puts it back on the left. 1P keeps
id 0 at the bottom-right PiP; 2P sends:

| id | slot | raw source crop (A) | mirrored A | dest (B) |
|---|---|---|---|---|
| 0 | P1 / left | `0.5,0,1,1` (raw right half) | `1,0,0.5,1` | `0.02,0.70,0.17,0.98` bottom-left |
| 1 | P2 / right | `0,0,0.5,1` (raw left half) | `0.5,0,0,1` | `0.83,0.70,0.98,0.98` bottom-right |

The SDK's optional `CameraImageSplitLayoutProfile` slot regions are narrower
(2P: `0.325..0.45` / `0.55..0.675`); they are the per-slot *focus windows* of
the SPLIT template, not the base partition used here (a narrow strip would be
badly stretched in a small corner PiP). The split partition itself is the equal
vertical strip (`CameraImageUvRegionUtility.CalculateHorizontalSplitRegion:30-48`,
`CameraImageSplitLayout.TryGetSlotRegion` fallback `CalculateEqualRegion:684-700`).

**Runtime keys (no keyboard on the box):** `GodotApp.canonicalKeyCode` maps
remote **MENU (82)** to Android `KEYCODE_F6` (camera-variant cycle) and remote
**INFO (165)** to `KEYCODE_F7` (pose-mirror toggle). `KEYCODE_F6`/`F7`
themselves are intentionally left unmapped so adb-injected F6/F7 pass through
to Godot. The camera cycle is: mirror H (default) -> mirror H+V -> raw frame;
the pose toggle is independent and live (`[pose] mirror=on|off`). The plugin API
is per-view: `cameraLiveView(id, on, src x4, dst x4, mode)`
plus `cameraLiveClear()`; `cameraLive` / `cameraLiveRect` / `cameraLiveMode`
remain as the legacy id-0 forms, and `cameraLive(false)` keeps its
clear-everything teardown semantics.

