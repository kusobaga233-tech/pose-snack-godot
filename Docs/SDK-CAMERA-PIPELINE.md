# How the YoudooGame Unity SDK handles the camera image

Read-only investigation for the Godot port. No device, no adb, no build.

## 0. What was read, and from where

| Source | Version | How |
|---|---|---|
| Local checkout `D:\CODEX-PROJ\yoodou\sdk` | **v1.0.7**, `HEAD = 07c7f7f938d8a2cea4ccab577bbb4507ab63cfbb` ("feat(vip): add subscription state and payment callbacks") | `read`, `git grep` |
| `origin/dev` | **v1.0.11** | `git show origin/dev:<path>` / `git diff HEAD origin/dev` |
| `Modules/sdk-adapter.youdoo/Runtime/Plugins/Android/YoudooAndroidLibrary-release.aar` | shipped binary | zip read in memory, `classes.jar` class list + constant-pool strings, `libyoudoo_plugin.so` symbol strings |
| `.../AndroidCutoutLibrary-release.aar` | shipped binary | same method |

Everything below is cited as `path:line` relative to `D:\CODEX-PROJ\yoodou\sdk\`. Binary evidence is cited as
`<aar>!/<entry>` plus the exact symbol/string that was found in it.

**Version note.** The camera pipeline is unchanged between v1.0.7 and v1.0.11. The only diffs in these files are
lifecycle hardening (`SetSuspended`, binding generation, "first RGB write" readiness gating) — see
`git diff HEAD origin/dev -- Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCameraImageBridge.cs`. Orientation,
mirroring, UV maths, cutout and layout are identical in intent.

---

## 1. Pipeline (one picture)

```text
device (com.sdt.game.service, system/OEM APK)
  camera  -->  IGameServiceV1_0_3.getFrameBuffer(long frameTimeMs)  -->  HardwareBuffer
               (AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420 = 0x23, 3 planes: Y / Cb / Cr)
        |
        v  binder callback thread (IFrameInfoCallback)
  FrameInfoHandler.processFrameAsync(FrameInfo, IGameServiceV1_0_3)      [Java, inside the AAR]
        |-- frameInfo.getFrameTimeMs() -> getFrameBuffer(t)
        `-- YoudooPlugin.setHardwareBufferForGraphics(hb, t)  [JNI]  ->  GraphicsHardwareBufferQueuePush
        |
        v  Unity main thread, <= 30 Hz
  AndroidTextureBridge{OpenglES,Vulkan}.Update()  ->  GL.IssuePluginEvent(renderEventFunc, 1)
        |
        v  render thread, GL/VK context current                [libyoudoo_plugin.so]
  AcquireLatest(queue)
        |-- GLES3:  eglGetNativeClientBufferANDROID -> eglCreateImageKHR -> glEGLImageTargetTexture2DOES
        |           fullscreen quad, samplerExternalOES -> glFramebufferTexture2D(<Unity RT>)
        |           frag: gl_FragColor = vec4(clamp(rgb, 0, 1), 1.0)   <- GPU YCbCr->RGB, alpha opaque
        `-- Vulkan: vkCreateSamplerYcbcrConversion + compute (vkCmdDispatch) -> storage image = <Unity RT>
        |
        v
  Unity RenderTexture (RGBA)  ->  CameraImageFrame  ->  CameraImageView.Update
        |                                                rawImage.texture = RT
        |                                                rawImage.uvRect  = signed UV
        v
  Canvas  ->  Full Camera View (full screen)   or   Split Player 1..4 (400x600 panels)
        |
        v
  CP Product UI (later sibling) draws on top  ->  screen
```

The C# layer never sees YUV and never sees a `HardwareBuffer`. It sees one engine-owned `RenderTexture`
that the native library paints into with the GPU.

---

## 2. Q1 — Frame source: where frames enter, format, conversion, thread

### Answer

Frames enter **inside the native library / its Java half**, not in C#:

1. The Java façade `com.youdoo.androidLibrary.FrameInfoHandler` (inside the AAR) receives
   `IFrameInfoCallback.onFrameInfoEvent(FrameInfo)` from the bound SDT game service, takes
   `frameInfo.getFrameTimeMs()`, calls `IGameServiceV1_0_3.getFrameBuffer(frameTimeMs)` and gets an
   `android.hardware.HardwareBuffer` back.
2. It immediately hands the buffer to JNI: `YoudooPlugin.setHardwareBufferForGraphics(buffer, frameTimeMs)`
   → `GraphicsHardwareBufferQueuePush`. The `FrameInfo` is separately `addFrameInfo(...)`-ed for tracking data.
3. The Unity render event (issued from `Update`) pops the newest buffer on the **render thread** and converts
   YUV420 → RGB **on the GPU**: `samplerExternalOES`/EGLImage on GLES, `VkSamplerYcbcrConversion` + compute on
   Vulkan. Output alpha is forced to `1.0`.
4. The C# bridge only publishes the resulting texture:
   `_provider.SetFrame(texture, texture.width, texture.height, ...)`.

So: **YUV420 3-plane in, RGBA out, conversion in native GPU code on the render thread; C# is a pure consumer.**
The 30 fps cap is C#-side (`TargetDispatchFps = 30`), enforced by skipping `GL.IssuePluginEvent` calls, not by
the service.

### Evidence

- AIDL declaration, exactly: `HardwareBuffer getFrameBuffer(long)` — descriptor `(J)Landroid/hardware/HardwareBuffer;`
  `Modules/sdk-adapter.youdoo/Runtime/Plugins/Android/YoudooAndroidLibrary-release.aar!/classes.jar!/com/sdt/game/service/IGameServiceV1_0_3.class`.
- Same call from plain Java (SDK's own editor bridge, no Unity):
  `Tools~/Android/SkeletonBridge/app/src/main/java/com/youdoo/skeletonbridge/SdtGameServiceClient.java:137-140`,
  registered via `:59`, with cutout use at `Tools~/Android/SkeletonBridge/app/src/main/java/com/youdoo/skeletonbridge/CutoutFrameStore.java:77,164`.
- Java producer that feeds JNI — method strings in
  `YoudooAndroidLibrary-release.aar!/classes.jar!/com/youdoo/androidLibrary/FrameInfoHandler.class`:
  `getFrameTimeMs`, `getFrameBuffer`, `setHardwareBufferForGraphics`, `processFrameAsync`, `addFrameInfo`,
  `clearHardwareBufferQueueForGraphics`.
- JNI target — `YoudooAndroidLibrary-release.aar!/classes.jar!/com/youdoo/jni/YoudooPlugin.class`:
  `setHardwareBufferForGraphics(HardwareBuffer, long)`, `clearHardwareBufferQueueForGraphics()`,
  `getY8Cb8Cr8420Format()`, `getR8G8B8A8UnormFormat()`, `loadLibrary("youdoo_plugin")` + `loadLibrary("AndroidCutoutLibrary")`.
- C# never calls `getFrameBuffer`; it only has legacy CPU copies:
  `Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooNativeMethods.cs:63-65`, and the vendor comment saying the
  hardware-buffer pointer is meaningless since SDK 4.0:
  `Modules/sdk-adapter.youdoo/Runtime/Native/AndroidServerInfo/AndroidParseData.cs:64-70,206-212`.
- Pixel format is YUV420 3-plane, proven by the SDK's own NDK reader:
  `Tools~/Android/SkeletonBridge/app/src/main/cpp/youdoo_plugin_rpc.cpp:62-63`
  (`description.format != AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420 → reject`), `:67-82` (`lockPlanes`, 3 planes),
  `:84-123` (Y/Cb/Cr with `rowStride`/`pixelStride`).
- GPU conversion, from symbol strings in
  `YoudooAndroidLibrary-release.aar!/jni/arm64-v8a/libyoudoo_plugin.so`:
  `eglGetNativeClientBufferANDROID`, `eglCreateImageKHR`, `glEGLImageTargetTexture2DOES`,
  `vkCreateSamplerYcbcrConversion`, `vkCmdDispatch`, and this literal fragment shader embedded in the `.so`:
  ```
  #extension GL_OES_EGL_image_external : require
  uniform samplerExternalOES sTexture;
  gl_FragColor = vec4(clamp(color.rgb, 0.0, 1.0), 1.0);
  ```
  The cutout build of the same shader passes `color.a` through instead.
- Render event ids and the 30 fps gate:
  `Modules/sdk-adapter.youdoo/Runtime/Native/AndroidServerInfo/CameraView/AndroidTextureBridgeBase.cs:13-14`
  (30 fps constants), `:116-152` (`Update` → `DispatchFrame`), `:348-352` (`GL.IssuePluginEvent(renderEventFunc, 1)`),
  `:288` (event `0` = warm-up), `:245-251` and `:571-579` (fps clamp 1..30).
- Output texture is engine-created and handed to native by pointer:
  `.../CameraView/AndroidTextureBridgeOpenglES.cs:55-78` (`new RenderTexture(w,h,0,ARGB32)` +
  `SetUnityTextureSizeOpenglES` + `SetUnityTexturePtrOpenglES(rt.GetNativeTexturePtr())`),
  `.../CameraView/AndroidTextureBridgeVulkan.cs:54-79` (`R8G8B8A8_UNorm`, `enableRandomWrite`, same pointer handoff).
- Texture is then published as a frame: `Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCameraImageBridge.cs:81-103`
  (`_provider.SetFrame(texture, texture.width, texture.height, ++_frameId, ...)`).

### What Godot must do to match

Bind `IGameServiceV1_0_3` (already on the plugin classpath —
`android/src/com/youdoo/godot/YoudooSkeletonPlugin.java:21-26,135-140`), call `getFrameBuffer(frameInfo.getFrameTimeMs())`
from the existing `onFrame(FrameInfo)` callback, and convert the YUV420 `HardwareBuffer` yourself (NDK) into an
RGBA buffer that becomes a Godot `ImageTexture`; the conversion cannot stay on the GPU unless Godot can sample an
external OES / YCbCr image, which the GL-Compatibility renderer does not expose.

---

## 3. Q2 — Composition: background texture, not an overlay

### Answer

The SDK draws the camera as a **full-screen `RawImage` inside the project's own Canvas, in the same draw order as
UI, behind the product UI**. There is no `Camera` component, no material, no blit, no render-texture indirection and
no native `SurfaceControl`: the `RenderTexture` produced by the bridge is assigned directly to `RawImage.texture`, and
a signed `Rect` is assigned to `RawImage.uvRect`. The camera panel is the **first** child of the product UI root and
`CP Product UI` is the **second**, so every gameplay element draws on top. Inside the camera panel a dark UI `Image`
(`Camera Surface`) is painted first as a backdrop/letterbox plate, then the FULL view, then the SPLIT views.

The `setCameraLiveOnScreen` AIDL call (which the Godot port currently uses) exists on the platform, but **no runtime
C# calls it** — only the Editor RPC bridge exposes it. It is not the SDK's rendering path.

### Evidence

- `[RequireComponent(typeof(RawImage))]` on the camera view:
  `Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageView.cs:22-23`.
- Per-frame assignment of texture + UV rect on that RawImage, no material touched:
  `CameraImageView.cs:343-344` (`output.texture = frame.Texture; output.color = Color.white;`),
  `:374` (`output.uvRect = _currentRegion;`).
- Reference hierarchy, parsed from the YAML of
  `Modules/framework.templates/Templates/Reference/FrameworkProductUi.prefab`:
  ```
  FrameworkProductUi                     (RectTransform 1920×1080, root; no Canvas inside the prefab)
  ├─ CP Camera Panel                     (stretch 0,0–1,1)            prefab:2143508172199446238
  │  ├─ Camera Surface                   (CanvasRenderer + UI Image: dark plate r0.015/g0.025/b0.04/a0.96,
  │  │                                    m_Sprite null — painted backdrop/letterbox, NOT the camera)
  │  ├─ Full Camera View                 (stretch; RawImage + CameraImageView)   prefab:8551854953731587557 / line 9109
  │  └─ Split Camera Views               (1920×1080; CameraImageSplitLayout)     prefab:6220781628125392646 / line 6337
  │     ├─ Split Player 1..4             (400×600 at x = −720/−240/+240/+720)    prefab:1731007517929252345 …
  └─ CP Product UI                       (stretch 0,0–1,1)  ← later sibling, drawn on top
  ```
  Child order is explicit in the YAML: `FrameworkProductUi` → `[CP Camera Panel, CP Product UI]`, and
  `CP Camera Panel` → `[Camera Surface, Full Camera View, Split Camera Views]` (the `m_Children` lists of
  `&8104006095979343868` and `&4276361508745536253`). So the camera views sit behind the product UI and above a dark
  backdrop plate.
- Component list of `Full Camera View` (parsed): `RectTransform`, `CanvasRenderer`, `RawImage`
  (`guid 1344c3c82d62a2a41a3576d8abb8e3ea`), `CameraImageView` (`guid 479485374d5d4a94a8754212995a0bd1`, at line 9109).
- Full/split switching is just `SetActive` on those two siblings:
  `Runtime/FrameworkCameraImagePresentation.cs:746-786` (`fullView.gameObject.SetActive(presentationVisible && !splitMode)`
  / `splitViews[i].gameObject.SetActive(presentationVisible && splitMode && i < playerCount)`).
- No `Canvas` component anywhere in the prefab (scan of all `!u!223` documents returns none); the prefab is authored
  to be dropped under a project Canvas.
- `setCameraLiveOnScreen` is *not* used at runtime: `git grep setCameraLiveOnScreen -- *.cs` yields only
  `Modules/sdk-adapter.youdoo/Editor/SdkBridgeEditor/YoudooSdkBridgeGameService.cs:344-370` (RPC surface) plus the
  Java bridge.

### What Godot must do to match

Put the camera on a `TextureRect` (or a `CanvasItem` with a `ShaderMaterial`) that is **below** the game
`CanvasLayer`/`Node2D` tree and covers the window — i.e. a real in-engine background, not a separate Android window.
Because the pixels are inside Godot's compositor, the arena can draw over the camera, the image can be clipped/masked
by gameplay UI, and it is captured by screenshots/recording.

---

## 4. Q3 — Mirroring: which layer flips, and what the default is

### Answer

Three separate things, frequently conflated:

1. **Texture memory orientation** — the native bridge stores the frame **180° rotated** (both axes reversed). The
   provider declares this once, as `CameraImageOrientation.BottomLeftFlippedBoth`.
2. **The flip itself is the UV rect**, not the texture bridge and not a shader. `CameraImageUvRegionUtility.CalculateUvRect`
   converts the orientation and the `mirror` flag into a **signed** rectangle: a horizontal flip is a **negative
   width** (`x += w; w = -w`), a vertical flip is a negative height. `CameraImageView` then assigns that rect to
   `RawImage.uvRect`. The legacy path used a negative Transform scale; the current path forbids adding one.
3. **The `mirror` input** is `CameraImageView.mirrorHorizontally`, serialized default **`false`**, and in every shipped
   prefab/profile it is `0`. `MatchSessionConfig.mirrorPlayerTrackingHorizontally` (default **`true`**) is **not** a
   display flag — it mirrors *tracking coordinates* (`x' = 1 − x`) before match-area math, compensated against the
   provider's own convention.

Net effect with the defaults (`mirrorHorizontally = false`, provider `BottomLeftFlippedBoth`): the XOR rule
`if (mirror ^ providerMirrored)` fires, so the UV width is negative, and the vertical flip fires too. That pair of
flips **undoes the stored 180° rotation** and leaves the picture exactly as the camera captured it — one horizontal
flip relative to texture memory, zero flips relative to the captured image. Setting `mirrorHorizontally = true`
removes the negative-width flip, which adds exactly **one** horizontal flip on top of the captured image (a selfie
toggle).

Whether "as captured" looks mirrored is a property of the device pipeline, not of the SDK. On this device the raw
frame is left-right reversed relative to the player's body (measured, `Docs/CAMERA-LIVE-EVIDENCE.md` §9–10), so the
SDK's default preview is selfie-mirrored, and the tracking space is mirrored once more for slot math — which is
exactly why `trackingCoordinatesAreMirrored` defaults to `true`.

### Evidence

- Signed-UV flip, verbatim (`Modules/camera-match-flow/Runtime/CameraImage/CameraImageUvRegionUtility.cs:183-202`):
  ```csharp
  if (providerMirrored)
  {
      // Source regions are expressed in canonical image space. A
      // horizontally mirrored provider stores that region in the
      // opposite texture half, so map the bounds before applying
      // the signed UV direction.
      source.x = 1f - source.xMax;
  }

  if (mirror ^ providerMirrored)
  {
      source.x += source.width;
      source.width = -source.width;
  }

  if (providerFlippedVertically)
  {
      source.y += source.height;
      source.height = -source.height;
  }
  ```
  (plus `:144-150` for how `TopLeft*` / `*Mirrored` / `*Flipped*` map onto those three booleans, and `:151-154` for
  the top-left→bottom-left Y conversion.)
- Provider orientation contract (`Modules/sdk-adapter.youdoo/Runtime/ModelSelection/YouDooCameraImageOrientationPolicy.cs:34-50`):
  > "The native camera bridge writes its output with both axes reversed. Keep that fact at the provider boundary…"
  ```csharp
  internal static CameraImageOrientation ResolveAndroidOrientation()
  {
      return CameraImageOrientation.BottomLeftFlippedBoth;
  }
  ```
- Display-mirror field and its default: `CameraImageView.cs:28` (`[SerializeField] private bool mirrorHorizontally;`),
  `:124` (public setter), `:199-211` (fed into `CalculateUvRect`), `:386` (published in the presentation context).
  Serialized `0` at `FrameworkProductUi.prefab:6773, 6890, 8417, 9120, 9378`; profile asset default false at
  `Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageViewProfileAsset.cs:20,34,55`.
- Tracking mirror default and plumbing:
  `CameraImageView.cs:29-34` (`trackingCoordinatesAreMirrored = true`; comment: the built-in provider reports a
  horizontally mirrored coordinate convention), `:125-129`;
  `Runtime/FrameworkCameraImagePresentation.cs:74` (`sessionMirrorHorizontally = true`), `:158,180`,
  `:274-284` (`SetMirrorState` → `view.MirrorTrackedPlayerCoordinates = …`);
  config field `Modules/camera-match-flow/Runtime/MatchFlow/MatchSessionConfigAsset.cs:301`
  (`private bool mirrorPlayerTrackingHorizontally = true;`); serialized `mirrorPlayerTrackingHorizontally: 1` in
  `Modules/framework.templates/Profiles/MatchFlow/MatchSessionConfig_FULL.asset:26` and `…_SPLIT.asset:26`;
  applied at `Modules/camera-match-flow/Runtime/MatchFlow/MatchSessionCoordinator.cs:1479-1485`:
  ```csharp
  bool mirrorCoordinates = _config.MirrorPlayerTrackingHorizontally
      && !currentFrame.Metadata.MirrorAlreadyApplied;
  ```
- The coordinate transform itself: `Modules/camera-match-flow/Runtime/CameraImage/CameraImageTrackingProjectionUtility.cs:66-71`
  (`left = mirrorHorizontally ? 1f - bounds.xMax : bounds.xMin; …`).
- Editor-vs-device orientation difference (confirms the two contracts are separate):
  `Documentation~/SdkAdapterYoudoo/SdkBridgeEditor/editor-real-device-bridge.md:41-45`.

### What Godot must do to match

Keep mirroring **out of the texture and out of the shader**: sample with a signed UV (or flip in the shader's UV
math) derived from `(region, fit mode, orientation, mirror)`. Reproduce `CalculateUvRect` once, in GDScript, and
expose a single `mirror` bool that is *added* to the device's convention. If the NDK converter already produces
top-left, upright RGBA, then `orientation` collapses to `TopLeft` and the formula reduces to: negative-width UV when
`mirror`, nothing otherwise.

---

## 5. Q4 — Cutout: how the player is separated, and what happens without it

### Answer

Cutout is an **optional, separate texture stream**, not a mode of `CameraImage`. It is entirely opt-in:

- Nothing is segmented until the app submits a person whitelist. `YouDooCutoutTargets.Tick` explicitly bails out
  when no target was ever requested ("Do not touch segmentation in games that never requested cutout").
- The app calls `YouDooCutout.SetTargets(sessionToken, personId…)`; the adapter diffs/queues the command and applies
  it through the Java bridge (`setTrackSegmentNoReturnValue(int[])` → AIDL `int setTrackSegment(int[])`).
- The device then produces a mask for those person ids; `YoudooPlugin.mapSeg(srcHb, dstHb, segBuffer)` (OpenCV 5.0.0
  inside `libAndroidCutoutLibrary.so`) writes **RGBA with alpha** into an `R8G8B8A8_UNORM` `HardwareBuffer`.
- A *second* native renderer (`…Cutout` export set) composites that RGBA image into a second engine `RenderTexture`,
  with the alpha-carrying fragment shader (`gl_FragColor = vec4(clamp(color.rgb,0,1), color.a)`), and the app reads it
  via `YouDooCutout.GetLatestFrame()`. The SDK never touches the project's RawImage/material; the project binds the
  texture itself and must hide its UI when no valid cutout frame exists.

**Without cutout** the app sees the plain `CameraImage` texture: the full frame, everyone in it, no alpha. The cutout
API fails rather than falling back ("没有有效帧时返回错误，不回退到普通相机图像"). Cutout also requires
`IGameServiceV1_0_3`; on a device that only exposes `V1_0_2` the capability reports unsupported.

### Evidence

- Public API, texture ownership, no fallback:
  `Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCutout.cs:15-62` (`IsSupported`, `SetTargets`, `ClearTargets`,
  `GetLatestFrame` returning `Fail(...)` when targets/texture are not ready at `:43-56`).
- Opt-in gating: `Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCutoutTargets.cs:86-112`, especially `:92-93`
  ("Do not touch segmentation in games that never requested cutout.") and `:114-122` (Dispose clears + flushes).
- Target plumbing to Java: `Modules/sdk-adapter.youdoo/Runtime/Native/AndroidServerInfo/AndroidServerInfoConfig/AndroidServerInfo.FrameInfo.cs:103-110`
  (`_pluginInstance.Call("setTrackSegmentNoReturnValue", cutoutPlayerIds)`); AIDL `int setTrackSegment(int[])` in
  `IGameServiceV1_0_3.class`; the same call from plain Java at
  `Tools~/Android/SkeletonBridge/app/src/main/java/com/youdoo/skeletonbridge/CutoutFrameStore.java:77`.
- Segmentation + RGBA format: `AndroidCutoutLibrary-release.aar!/classes.jar!/com/youdoo/cutout/JniOpenCV.class`
  (`mapSeg(HardwareBuffer, HardwareBuffer, ByteBuffer) → int`), `…/JniHardwareBuffer.class`
  (`getR8G8B8A8Unorm`, `getY8Cb8Cr8420`, `createHwBuffer(int,int,int)`), and the RGBA check in the bridge's reader
  `Tools~/Android/SkeletonBridge/app/src/main/cpp/youdoo_plugin_rpc.cpp:23`
  (`desc.format != AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM → reject`), `CutoutFrameStore.java:164` (`YoudooPlugin.mapSeg`).
- Alpha-preserving shader in `AndroidCutoutLibrary-release.aar!/jni/arm64-v8a/libAndroidCutoutLibrary.so`
  (`gl_FragColor = vec4(clamp(color.rgb, 0.0, 1.0), color.a);`), versus the opaque camera shader in
  `libyoudoo_plugin.so` (`…, 1.0);`).
- Texture lifecycle only, no UI: `Modules/sdk-adapter.youdoo/Runtime/Native/AndroidServerInfo/CameraView/Cutout/AndroidCutoutTextureBridge.cs:14-30,66-88`;
  concrete backend `…/Cutout/AndroidTextureBridgeOpenglESCutout.cs:14-39`.
- Documentation: `Documentation~/cutout.zh-CN.md:4-6` ("抠像不是普通 `ICameraImageProvider` 的替代品，也不会自动把
  CameraImage RGB 当作抠像输出"), `:14-18` (texture owned by the SDK, the project renders its own UI), `:42-48`
  (Editor path uses `setTrackSegment` + `mapSeg`, 640×360 cap, ≤10 fps), `:62-63` (`V1_0_2` fallback has no cutout).

### What Godot must do to match

Do nothing, unless per-person compositing is a product requirement. Cutout is orthogonal to "camera behind the
arena": it needs the same frame buffer plus a target list, an OpenCV pass, and a second texture. For pose-snake the
camera is a backdrop, so skip it and use the plain frame.

---

## 6. Q5 — Per-player layout: FULL vs SPLIT rect maths

### Answer

There are two independent layout layers:

**FULL** — one view, one crop, no per-player rects. The view's `Region` (normalized, top-left origin) is either fixed
(optionally constrained to `[fullFrameSlotMinX, fullFrameSlotMaxX] × [0,1]`) or driven by the bound players' bounding
box (FOLLOW). `fitMode` is `Cover` in every shipped template. The final UV is
`region → orientation → fit(Cover/Contain/Stretch) → mirror`.

**SPLIT** — N views, each with its own source region, and each view is a separate UI rectangle:

- Source partition per slot, in priority order: session override → configured profile for the player count →
  gap-aware partition from the authored slot geometry → plain equal split `1/count`.
- The profile stores normalized `XMin/XMax/YMin/YMax` per player count 1–4; `MapRelativeRegion` maps it through the
  layout's `sourceRegion`.
- The visual slot positions are authored (`Split Player 1..4`, 400×600 at x = −720/−240/+240/+720 on 1920×1080), and
  the layout only re-centers/activates them for the active count; it does not change their size.
- On top of the base partition, a bound slot may additionally *focus* (crop tighter around its player) via the split
  follow calculator, constrained to the base partition.

Concrete numbers shipped in the reference prefab (embedded profile, `FrameworkProductUi.prefab:6359-6410`):

| players | slot source regions (xMin–xMax, y 0–0.9) |
|---|---|
| 1 | 0.400–0.600 |
| 2 | 0.250–0.450, 0.550–0.750 |
| 3 | 0.150–0.350, 0.400–0.600, 0.650–0.850 |
| 4 | 0.150–0.300, 0.350–0.475, 0.525–0.650, 0.700–0.850 |

The standalone profile asset uses narrower "focus window" strips instead
(`Modules/framework.templates/Profiles/CameraImage/CameraImageSplitLayoutProfile.asset:17-64`):
1P 0.425–0.575; 2P 0.325–0.45 / 0.55–0.675; 3P 0.25–0.375 / 0.425–0.575 / 0.625–0.75;
4P 0.20–0.325 / 0.35–0.475 / 0.525–0.65 / 0.675–0.80 (all `y 0–1`).
Note all strips are 12.5–20 % wide and vertically full/tall: SPLIT takes a narrow vertical slice per player, not a
quarter of the frame. Each slice is then stretched/cover-fitted into a 400×600 portrait panel.

### Evidence

- Equal fallback (`Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageSplitLayout.cs:684-700`):
  ```csharp
  private Rect CalculateEqualRegion(int index, float equalSize)
  {
      if (axis == CameraImageSplitAxis.Horizontal)
      {
          return CameraImageView.ClampRegion(new Rect(
              sourceRegion.x + sourceRegion.width * index * equalSize,
              sourceRegion.y,
              sourceRegion.width * equalSize,
              sourceRegion.height));
      }
      …
  }
  ```
  called as `CalculateEqualRegion(viewIndex, 1f / count)` at `:438`.
- Gap-aware partition from authored UI geometry: `CameraImageSplitLayout.cs:702-721` (`Mathf.InverseLerp(rangeMin,
  rangeMax, bounds.Min/Max)`), bounds captured from `RectTransform.GetWorldCorners` at `:742-760`.
- Profile mapping: `CameraImageSplitLayout.cs:723-730` (`MapRelativeRegion`) and lookup order at `:386-443`.
- Applied to the views: `CameraImageSplitLayout.cs:487-498`
  (`view.SetPartitionUvBounds(region); view.SetRegion(region); …SetPartition(region)`).
- Profile data model: `Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageSplitLayoutProfile.cs:132-155`
  (per-count lookup), `:196-211` (`CreateEqualRegions` — the legacy equal fallback), `:218-251`
  (`CreateReferencePartitionProfile`, the "PlayerMatchView SpecPartition4Relative" table: 0.40/0.25/0.15 widths with
  `y 0–0.9`).
- Cover/Contain maths (the part that prevents distortion):
  `Modules/camera-match-flow/Runtime/CameraImage/CameraImageUvRegionUtility.cs:156-181`
  (desired UV aspect `= targetAspect / textureAspect`, expand the short side around the region centre, then
  `ShiftInsideUnit`).
- FULL is a single view with no partition:
  `Runtime/FrameworkCameraImagePresentation.cs:973-987` (`ApplyFullFrameFixedRegion` → `fullView.SetRegion(region)`),
  `:906-931` (`SetFullFrameSourceConstraint`), `:459-487` (FOLLOW attempt → hold → fixed fallback).
- `CalculateHorizontalSplitRegion` (`CameraImageUvRegionUtility.cs:30-82`) is the **FULL equal-slot guide/lock-area**
  helper (UI bands), not the SPLIT texture partition — do not confuse the two.

### What Godot must do to match

Represent each slot as a `TextureRect` whose `texture` is the camera `ImageTexture` and whose visible crop is a
normalized sub-rect of that texture (a `ShaderMaterial` with a `region` uniform, or `AtlasTexture.region`). Compute
the slot region with the same three-level fallback, and keep the physical panel size fixed while only the crop
changes. For 1 player, either full-frame FOLLOW (crop around the player with cover aspect) or the 0.40–0.60 centre
strip.

---

## 7. Q6 — Lifecycle: pause / resume / focus loss / session end

### Answer

| Event | SDK behaviour | Stops the camera? |
|---|---|---|
| View enabled | `CameraImage.Start()` → provider `Begin()` → create bridge GameObject + `RenderTexture` | starts |
| App pause | bridge `OnApplicationPause(true)`: unbind native pointer, run native cleanup **but keep the `RenderTexture`**; C# dispatch stops | **no** (suspends) |
| App resume | `OnApplicationPause(false)` → `InitializeRuntime()` → new warm-up event, re-resolve size, re-bind (size may have changed) | resumes |
| Focus loss | cutout bridge suspends; camera bridge `OnApplicationFocus` re-initialises on regain if paused/null | suspends |
| View disabled (`SetVisible(false)`, scene swap) | `CameraImageView.OnDisable` drops the presentation context; **does not call `CameraImage.Stop()`** | **no** |
| Manual pause | `CameraImage.Pause()` → bridge `Suspend()` (`enabled = false` on the bridge component) | suspends |
| Session end | `MatchSessionHost` pauses matching; nothing in the session layer calls `CameraImage.Stop()` | **no** |
| Explicit stop | `YoudooAPI.StopCameraImage()` → `CameraImage.Stop()` → `bridge.End()` → destroy bridge, unbind pointer | **yes** |
| App quit / object destroy | `OnDestroy` (non-final cleanup, keeps the native global alive across scene switches), `OnApplicationQuit` (final cleanup) | yes |
| Cutout | suspends on `OnDisable`/pause/focus loss; `ClearTargets()` on teardown; targets are re-sent after reconnect | yes (that stream) |

Two practical consequences: (a) the camera texture survives scene loads (the bridge object is `DontDestroyOnLoad`) —
the next scene just re-binds its `RawImage`; (b) after a match ends the camera keeps streaming at 30 fps unless the
app explicitly stops it, so a Godot port must stop it or it will burn power through the settlement screen.

### Evidence

- Pause/resume/cleanup, with the explicit comment that the Unity `RenderTexture` must survive background:
  `Modules/sdk-adapter.youdoo/Runtime/Native/AndroidServerInfo/CameraView/AndroidTextureBridgeBase.cs:157-177`
  (pause → `CleanupRuntime(true,false,false)`), `:182-199` (focus), `:205-220` (destroy / quit),
  `:520-541` (`CleanupRuntime`, `releaseUnityTexture` flag), `:487-513` (RT create-or-reuse).
- Manual suspend/resume at provider level: `Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCameraImageBridge.cs:29-79`
  (`Begin`/`End`/`Suspend`/`Continue`), `:131-139` (`ReleaseCameraTextureImageBridge`), `:153-157` (`OnDestroy`).
- DontDestroyOnLoad bridge object: `Modules/sdk-adapter.youdoo/Runtime/Adapter/YouDooCameraImageProvider.cs:33-44`.
- v1.0.11 additionally suspends on app pause/focus and gates frames on "first RGB write":
  `git show origin/dev:Modules/sdk-adapter.youdoo/Runtime/Bridge/YouDooCameraImageBridge.cs`
  (`OnApplicationPause`, `OnApplicationFocus`, `SynchronizeSuspension`, `_readiness.Poll(...)`), and
  `origin/dev:.../AndroidTextureBridgeBase.cs` (`SetSuspended`, `BindingGeneration`, `BoundFrameDispatchCount`).
- Start on view enable: `Modules/camera-match-flow/Runtime/CameraImage/Components/CameraImageView.cs:279-284`
  (`if (startOnEnable) CameraImage.Start();`); background snapshot kept across pause/focus loss: `:295-309`.
- Stop path: `Modules/camera-match-flow/Runtime/CameraImage/Services/CameraImageService.cs:38-60`
  (`Dispose`/`Stop` → `provider.Stop()`), public API `Runtime/YoudooAPI.cs:94-107`.
- No session-end stop: `git grep "CameraImage.Stop()" -- Runtime Modules` matches only `CameraImage.cs:10` (the API
  definition) and tests; `MatchSessionHost` only pauses gameplay:
  `Modules/camera-match-flow/Runtime/MatchFlow/Components/MatchSessionHost.cs:704-736`.
- Cutout suspension: `…/Cutout/AndroidCutoutTextureBridge.cs:52-57,66-88,117-129`.

### What Godot must do to match

Keep the camera texture outside the scene (autoload), stop *dispatching* on `NOTIFICATION_APPLICATION_PAUSED` /
`FOCUS_OUT`, and on resume rebuild the texture if size/orientation changed (the SDK re-creates the RT on size
change). On match end, either keep the texture frozen on the last frame (cheapest, matches "camera as backdrop") or
stop the bridge and drop the `ImageTexture`.

---

## 8. Q7 — What the SDK's own sample/consumer code actually does

### Answer

The canonical consumer is the reference prefab plus a 3-line sample:

```csharp
CameraImage.Start();
var frame = CameraImage.GetFrame();
if (frame.Success)
    rawImage.texture = frame.Value.Texture;
```
(`Modules/camera-match-flow/README.md:18-23`.)

The prefab is the "product shell": one full-screen `Full Camera View` (RawImage + `CameraImageView`) for FULL, and
four `Split Player 1..4` panels under `Split Camera Views` (RawImage + `CameraImageView` + `CameraImageSplitLayout` +
`CameraImageSplitSlotController`/`…SplitPresentationController`) for SPLIT. The host toggles which set is active by
`SetActive`, binds them once (`SetSceneBindings`), and pushes per-slot source regions into them on every layout
change. Nothing in the prefab owns a camera object, a material, or a second Canvas.

Per-view authored values in the reference prefab: `fitMode: 2` (Cover), `mirrorHorizontally: 0`,
`trackingCoordinatesAreMirrored: 1`, `smoothRegionChanges: 1`, `topOffsetPercent: 0.12`, and a `region` that is the
4-player 0.9-high strip for that slot (e.g. `x 0.15 w 0.15 h 0.9` for Split Player 1).

### Evidence

- Prefab composition and component ownership: `Modules/framework.templates/Templates/Reference/FrameworkProductUi.prefab`
  — `Split Camera Views` component `CameraImageSplitLayout` at line 6337; `Full Camera View` `CameraImageView` at
  line 9109; per-view serialized block at `:9109-9125`, split views at `:6762-6778, 6879-6895, 8406-8422, 9367-9383`.
- Host binding of scene views: `Runtime/FrameworkProductUiPrefab.cs:53-56` (`fullCameraView`, `splitCameraViews`,
  `splitCameraLayout`), `Runtime/FrameworkCameraImagePresentation.SetSceneBindings` `Runtime/FrameworkCameraImagePresentation.cs:126-144`.
- Layout driving the views: `Runtime/FrameworkCameraImagePresentation.cs:746-786` (`ApplyViewState`), `:989-1030`
  (`ApplySplitSessionRegions`: profile wins, session overrides are legacy).
- Template/profile assets that select the policy: `Modules/framework.templates/Templates/Reference/FULL+包围盒跟随.asset:29-37`
  (`fitMode: 2`, `trackingFocusEnabled: 1`, `fullFocusMode: 1`), `…/SPLIT+固定槽位.asset:29-36`
  (`trackingFocusEnabled: 0`), `…/SPLIT+分屏追随.asset:28-37` and `:54-55` (`splitLayoutProfileResourcesPath`).
- The four templates are `FULL_FOLLOW`, `FULL_FIXED`, `SPLIT_FOLLOW`, `SPLIT_FIXED`
  (`Modules/framework.templates/README.md:16-22,74-76`).

### What Godot must do to match

Mirror the same structure: one full-screen `TextureRect` for 1-player/full mode, N fixed-size `TextureRect`s for split
mode, both children of a camera `CanvasLayer`/`Control` that sits below the HUD; bind them once, then per frame only
update `texture` + `region` (and `flip_h`/UV for the mirror), and per layout change only update the regions.

---

## 9. Feasibility verdict for the Godot port

### 9.1 What is Unity-specific (cannot be reused)

| Layer | Why it does not transfer |
|---|---|
| `AndroidTextureBridge*`, `CameraImageView`, `CameraTextureView`, `CameraImage*` | `MonoBehaviour`, `RenderTexture`, `RenderTexture.GetNativeTexturePtr()`, `GL.IssuePluginEvent`, `RawImage.uvRect` — all engine API |
| `libyoudoo_plugin.so` GL/Vulkan entry points | Not JNI — a **Unity native-plugin** ABI: it exports `UnityPluginLoad`/`UnityPluginUnload` plus `GetRenderEventFunc*`, `SetUnityTexturePtr*`, `GetTextureWidth/Height*`, `CleanupVulkan`, i.e. it expects to be driven by Unity's plugin loader and an `IUnityGraphics*` interface, and it has no exported entry point that simply returns pixels. No non-Unity integration path is documented. Treat as unsupported — and unnecessary, because the same `HardwareBuffer` is reachable directly over AIDL. |
| `com.youdoo.androidLibrary.UnityDataTransfer` | extends `DataTransfer` but is wired to `com.unity3d.player.UnityPlayer.currentActivity` and `UnitySendMessage` for notifications |

### 9.2 What *is* reusable from a plain Java/NDK plugin

1. **The AIDL itself** — `com.sdt.game.service.IGameServiceV1_0_3` is a normal Binder interface compiled into
   `YoudooAndroidLibrary-release.aar`, which the Godot plugin already depends on and already binds
   (`android/plugins/youdoo/YoudooAndroidLibrary-release.aar`, `android/src/com/youdoo/godot/YoudooSkeletonPlugin.java:21-26,135-140`).
   Methods that matter: `getFrameBuffer(long) → HardwareBuffer`, `setTrackSegment(int[])`,
   `setCameraLiveOnScreen(int,boolean,float×8,int)`, `clearAllCameraLiveOnScreen()`,
   `registerFrameInfoCallback(IFrameInfoCallback)`. Full list in §11.
2. **The frame-time coupling** — the SDK fetches the buffer with the *same* `FrameInfo.getFrameTimeMs()` that carries
   the skeleton, so image and pose are the same capture. Godot can do exactly that inside its existing
   `onFrame(FrameInfo)` callback.
3. **The YUV420 layout knowledge** — `AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420`, three planes with independent
   `rowStride`/`pixelStride`, chroma at `(x/2, y/2)`; proven by the SDK's own reader
   (`youdoo_plugin_rpc.cpp:62-123`).
4. **The exact conversion constants** — BT.601 limited range, integer, already in the SDK bridge:
   `youdoo_plugin_rpc.cpp:207-212` (`c=y-16; d=cb-128; e=cr-128; R=(298c+409e+128)>>8; G=(298c-100d-208e+128)>>8;
   B=(298c+516d+128)>>8`) and the horizontal flip at `:100` (`sourceX = sourceWidth - 1 - mappedX`).
5. **`mapSeg` RGBA output** — if per-person alpha is ever needed, `com.youdoo.cutout.JniOpenCV.mapSeg(src, dst, seg)`
   plus `JniHardwareBuffer.createHwBuffer(w,h,R8G8B8A8_UNORM)` are plain JNI calls into
   `libAndroidCutoutLibrary.so`, callable from Godot's Java plugin.

### 9.3 Minimum NDK surface to reproduce the SDK's result

One small `.so` (or one `externalNativeBuild` module) with a single JNI entry, ~150 lines of C:

| Step | API | Note |
|---|---|---|
| wrap | `AHardwareBuffer_fromHardwareBuffer(env, jobject)` | `android/hardware_buffer_jni.h` |
| query | `AHardwareBuffer_describe(&desc)` | require `desc.format == AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420` (0x23) |
| lock | `AHardwareBuffer_lockPlanes(..., AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1, NULL, &planes)` | API 26+; the project's minSdk is 30 |
| read | `planes.planes[0..2].data/rowStride/pixelStride` | Y full res, Cb/Cr half res, **stride-aware** |
| convert | BT.601 limited integer (same constants as the SDK) | optional NEON |
| orient | Y flip and/or X flip as two booleans | the only place mirroring should exist on this path |
| scale | nearest/bilinear to 640×360 or 960×540 | keep 16:9 to avoid re-letterboxing |
| emit | `env->SetByteArrayRegion` → `byte[]` (or a reusable direct `ByteBuffer`) | RGBA8 |
| unlock | `AHardwareBuffer_unlock` | always, in a cleanup block |

Godot side: a `PackedByteArray` → `Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)` →
`ImageTexture.update(image)` (reuse one `ImageTexture`), sampled by a full-screen `TextureRect` below the HUD.
Cost at 640×360 RGBA: 0.92 MB/frame ≈ 27 MB/s at 30 fps (fine); at 1280×720 it is 3.7 MB/frame ≈ 110 MB/s (measure
first). No EGL, no Vulkan, no Unity.

Not needed: `setCameraLiveOnScreen` (keep as fallback), cutout/`mapSeg`, `libyoudoo_plugin.so`.

---

## 10. Three cheapest ways to get a mirrored, correctly framed camera image into Godot

Ranked by incremental cost for this project (which already ships #1).

### 1) System overlay with signed source rects — **already shipped, cheapest**
`IGameServiceV1_0_3.setCameraLiveOnScreen(id, on, srcRect×4, dstRect×4, mode)`; the service owns a translucent,
non-focusable `TYPE_APPLICATION_OVERLAY` window above the app. Mirror by inverting the source rect
(`x1=1, x2=0`), frame by choosing the source crop, per-player by using one `id` per view.

- Cost: zero native code, zero new dependencies (`android/src/com/youdoo/godot/YoudooSkeletonPlugin.java` already
  exposes `cameraLiveView`).
- Trade-offs: it is **above** the app, so it cannot sit behind the arena, cannot be clipped/masked by game UI, cannot
  be captured in screenshots, ignores Godot's colour pipeline, and is limited to two normalized rectangles per view
  (no perspective, no rounded corners, no per-slot focus). The A/B rect pair semantics are still only empirically
  inferred (source crop vs destination) — `Docs/CAMERA-LIVE-EVIDENCE.md` §3, §9.
- Verdict: keep as the fallback path and for device A/B testing, not as the product look.

### 2) NDK YUV420 → RGBA → `ImageTexture` — **the SDK-equivalent, recommended**
`getFrameBuffer(frameTimeMs)` → lock planes → BT.601 convert (with the two flip booleans) → downscaled RGBA →
`ImageTexture` on a `TextureRect` under the HUD.

- Cost: one small `.so` + one JNI method + ~30 lines of GDScript; no new Gradle dependency (the AAR and binder are
  already present).
- Trade-offs: CPU conversion + one upload per frame (0.9 MB at 640×360; budget a few ms and measure at 720p, where
  it is 3.7 MB/frame), a JNI byte-array copy unless a direct `ByteBuffer` is used, and it needs `getFrameBuffer` to
  be served at the rate you want (drive it from the frame callback; do not poll faster than the service produces
  frames).
- Why it is the right target: it is the *only* option that reproduces the SDK's composition — a texture inside
  Godot's own compositor, behind all gameplay UI, croppable/mirrorable per slot, captured by screenshots, and
  independent of the service's overlay window.

### 3) Ask the platform for an RGBA (alpha-carrying) buffer — **highest ceiling, most risk**
Two variants:
(a) cutout path: `setTrackSegment(personIds)` + `YoudooPlugin.mapSeg(srcHb, dstHb, seg)` → `R8G8B8A8_UNORM`
`HardwareBuffer` whose alpha is real, then lock/copy (no YUV maths) and composite the players *over* the game;
(b) engine-translucent path: put the platform's camera `SurfaceView` behind a translucent Godot surface
(`PixelFormat.TRANSLUCENT` + transparent clear) so the platform composites the camera and Godot draws over it.

- Cost: (a) needs person ids, `IGameServiceV1_0_3`, an extra OpenCV pass and its own pacing (the SDK's editor bridge
  caps this stream at 640×360 / 10 fps — `Documentation~/cutout.zh-CN.md:47-48`); (b) needs the GL-Compatibility
  surface to accept per-pixel transparency and to survive Godot's own surface management — unproven on this device,
  and the failure mode is a black screen.
- Trade-offs: (a) is the only way to get people-on-top-of-game compositing and it skips YUV conversion, but it is
  proprietary, undocumented, rate-limited, and requires the cutout model to be present on the device; (b) is elegant
  but the riskiest thing you can do to a working renderer.
- Verdict: not now. Revisit only if the product wants players composited above the arena.

**Recommendation.** Implement **#2** behind the existing `camera_live_*` switch: add `getFrameBuffer` + the NDK
converter to `YoudooSkeletonPlugin`, expose `camera_frame_rgba()` returning `{w, h, PackedByteArray}` (or update a
persistent `ImageTexture` from a direct `ByteBuffer`), render it with a full-screen `TextureRect` at the bottom of the
scene tree with signed-UV mirroring, and keep #1 as the fallback for devices where the frame buffer is unavailable.
That is a faithful port of the SDK's pipeline with roughly 200 lines of new code and no Unity.

---

## 11. Appendix — extracted AIDL and native surface

`IGameServiceV1_0_3` (from `YoudooAndroidLibrary-release.aar!/classes.jar!/com/sdt/game/service/IGameServiceV1_0_3.class`,
descriptors verbatim):

```
void registerFrameInfoCallback(IFrameInfoCallback)          (Lcom/sdt/game/service/IFrameInfoCallback;)V
void unregisterFrameInfoCallback(IFrameInfoCallback)        (Lcom/sdt/game/service/IFrameInfoCallback;)V
void touchEvent(int,int,int,boolean)                        (IIIZ)V
void pressKey(int,int)                                      (II)V
HardwareBuffer getFrameBuffer(long frameTimeMs)             (J)Landroid/hardware/HardwareBuffer;
void setCameraLiveOnScreen(int,boolean,float x8,int)        (IZFFFFFFFFI)V
void clearAllCameraLiveOnScreen()                           ()V
void startRecord(String,int,int,long,boolean)               (Ljava/lang/String;IIJZ)V
void stopRecord()                                           ()V
void appendRecordDuration(long)                             (J)V
String getConfigJson() / getCurrentConfigJson()
String setConfigJson(String)
int setTrackHandsAndFace(int[],int[],int[])                 ([I[I[I)I
int setPlayerID(int[])                                      ([I)I
List<FaceInfo> getFaceInfo(long)                            (J)Ljava/util/List;
List<FaceInfo> getFaceInfoJPG(HardwareBuffer)
float getFaceInfoCosSim(float[],float[])
int getHandsCursorInfo(int,double,int[],double[])
double getFaceSizePixel(int)
int setTrackSegment(int[])                                  ([I)I
```

Native exports relevant to the camera (strings in `libyoudoo_plugin.so`; the same set with a `…Cutout` suffix exists in
`libAndroidCutoutLibrary.so`):

```
GetRenderEventFuncOpenglES / GetTextureWidthOpenglES / GetTextureHeightOpenglES
SetUnityTexturePtrOpenglES / SetUnityTextureSizeOpenglES / ResetTextureIdsOpenglES
GetRenderEventFuncVulkan / GetTextureWidthVulkan / GetTextureHeightVulkan / SetUnityTexturePtrVulkan / CleanupVulkan
UnityPluginLoad / UnityPluginUnload
CopyHardwareBufferToMemory / CopyHardwareBufferToMemoryWithScale / GetHardwareBufferInfo
Java_com_youdoo_jni_YoudooPlugin_setHardwareBufferForGraphics
Java_com_youdoo_jni_YoudooPlugin_clearHardwareBufferQueueForGraphics
Java_com_youdoo_cutout_JniOpenCV_mapSeg
Java_com_youdoo_cutout_JniHardwareBuffer_createHwBuffer{,_getY8Cb8Cr8420,_getR8G8B8A8Unorm}
GraphicsHardwareBufferQueuePush / AcquireLatest / AcquireLatestIfNewer / HasImage / Clear
```

Formats seen in the shipped binaries: camera = `AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420` (3 planes), cutout output =
`AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM`, Unity GL target = `ARGB32`, Unity Vulkan target = `R8G8B8A8_UNorm` with
`enableRandomWrite`.
