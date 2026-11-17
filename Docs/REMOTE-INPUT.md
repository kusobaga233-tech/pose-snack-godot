# Remote-control native key hook (`GodotRemoteInput`)

Workstream: RCU input for the Youdoo HP52S0 box (Android 11).
Status: implemented, Java compile-checked, PC suite green; **device cycle pending**
(the coordinator runs it separately — no APK was exported by this change).

## 1. Problem

A 180 s window with a human pressing LEFT/RIGHT/UP/DOWN/OK/BACK produced **zero**
`[key]` lines in the Godot router, while `adb shell input keyevent` worked.
`dumpsys input` showed the RCU devices registered and the window
`hasFocus=true canReceiveKeys=true`, so focus was not the issue.

Verified root cause (same platform, skiing project log 2026-10-26):

```
I GodotRemoteInput: key=23 action=0 source=1793 repeat=0 device=9
I GodotRemoteInput: key=19 action=0 source=1793 repeat=0 device=9
...
E godot: ERROR: Index (int)p_button = -102 is out of bounds ((int)JoyButton::MAX = 128).
E godot:    at: joy_button (core/input/input.cpp:1336)
```

* The RCU is enumerated as a gamepad: `source=1793` (`0x701`) carries
  `SOURCE_GAMEPAD` (`0x401`).
* `GodotInputHandler.isKeyEventGameDevice()` therefore routes its key events to
  `handleJoystickButtonEvent()`.
* DPAD 19..22 map to `JOY_BUTTON_DPAD_*` 11..14 (invisible to the GDScript
  `InputEventKey` router), while DPAD_CENTER 23 maps to the invalid button
  `-102` and is dropped with the error above.
* The GDScript router (`src/present/ps_remote.gd` + `main.gd::_input`) only read
  `InputEventKey`, so the physical remote looked like "no input at all".
* adb injection works because `input keyevent` arrives as `SOURCE_KEYBOARD`.

## 2. Fix

Canonical source:
`android/build-overrides/src/main/java/com/godot/game/GodotApp.java`
(copied into the generated `android/build/` by `tools/setup_android_build.ps1`).

`GodotApp.dispatchKeyEvent()`:

1. Logs every event:
   `GodotRemoteInput: key=23 action=down name=KEYCODE_DPAD_CENTER source=1793 repeat=0 device=9`
2. Canonicalises the remote key:
   * 19/20/21/22 -> same (DPAD),
   * 23/66/96/160/85/62 -> 66 (`KEYCODE_ENTER`; 96 is `KEYCODE_BUTTON_A`,
     which Godot has no keyboard mapping for),
   * 4/111 -> same (BACK/ESCAPE).
3. Consumes the original (`return true`) and sends a **pure-keyboard**
   `KeyEvent` to the decor view:
   `new KeyEvent(now, now, action, code, repeat, 0, -1, 0)`.
   This has `deviceId=-1`, `scanCode=0`, and source `0`, so Godot takes
   `handleKeyEvent` and translates the Android keycode through
   `android_keys_utils.h` (19 -> `KEY_UP`, 23 -> `KEY_ENTER`, 4 -> `KEY_BACK`).
   The existing router then sees a normal `InputEventKey`.
4. If the engine/view does not take the synthetic event, falls back to
   `super.dispatchKeyEvent(event)` so the press is not lost.

This is the `injectEnter()` mechanism from the reference project, generalised
from "ENTER only" to every remote key. The reference's other attempt —
`new KeyEvent(..., event.getSource())` for 23 — keeps `SOURCE_GAMEPAD` and is
therefore still classified as a joypad button; the log above proves it did not
fix OK. Only the `source=0` event works.

### Second channel

The platform also broadcasts `com.youdoo.assistant.SendHotKey` with
`specialKey` / `deviceName` extras. `GodotApp` registers a runtime
`BroadcastReceiver` (`RECEIVER_EXPORTED` on Android 13+) and treats it as a
fallback for keys that never arrive as `KeyEvent`s:

* known `specialKey` -> canonical key above;
* unknown/0 -> `KEYCODE_ENTER` (reference behaviour: an unknown hotkey still
  confirms, because on this box a swallowed OK is worse than a wrong confirm);
* injects one down+up pair.

## 3. Key table

| Action | Android keycodes accepted | Godot code the router sees |
|---|---|---|
| UP | 19 `DPAD_UP` | `KEY_UP` 4194320 |
| DOWN | 20 `DPAD_DOWN` | `KEY_DOWN` 4194322 |
| LEFT | 21 `DPAD_LEFT` | `KEY_LEFT` 4194319 |
| RIGHT | 22 `DPAD_RIGHT` | `KEY_RIGHT` 4194321 |
| OK | 23 `DPAD_CENTER`, 66 `ENTER`, **96 `BUTTON_A`**, 160 `NUMPAD_ENTER`, 85 `MEDIA_PLAY_PAUSE`, 62 `SPACE` | `KEY_ENTER` 4194309 (canonical 66) |
| BACK | 4 `BACK`, 111 `ESCAPE` | `KEY_BACK` 4194376 / `KEY_ESCAPE` 4194305 |

`adb shell input keyevent 8/9/21/22/23/66/111/4` still works: those events also
hit `dispatchKeyEvent`, are canonicalised, and are delivered once through the
same synthetic path. 8/9 (`1`/`2`) are not remote keys and pass through
unchanged (they remain harmless unicode keys).

### 3.1 Debug keys reachable on the box

`main.gd::_input()` handles these **before** the menu router (all are
`key.pressed && !key.echo`, handled and returned). Android keycodes: `KEYCODE_F1
= 131`, so `F<n> = 130 + n`; `KEYCODE_F10 = 140` (141 is **F11** and is unbound).

| Key | adb (`input keyevent`) | Remote | Effect |
|---|---|---|---|
| F3  | 131 | — | detailed developer overlay (bottom-left) |
| F4  | 134 | — | camera live on/off |
| F5  | 135 | — | 1P PiP placement |
| F6  | 136 | **MENU** (82) | camera-variant cycle |
| F7  | 137 | **INFO** (165) | flip the mirror box's RGBA frame |
| Ctrl+F7 | keyboard only | — | pose `1-x` mirror toggle |
| F8  | 138 | — | internal tuning panel (`PSBuild.TUNING_ENABLED` build only) |
| **F10** | **140** | **INFO x2** (two F7 inside 420 ms) | **always-on perf panel** (default on) |
| — | — | **INFO x2** | the second tap flips the camera back, then toggles the panel, so a double tap leaves the picture as it was |

The native hook deliberately does **not** map F10 (same rule as F6/F7 above:
only 82 and 165 are canonicalised, everything else must fall through), so
`input keyevent 140` arrives as a plain `InputEventKey` with `KEY_F10`. The RCU
has no F10 button, hence the double-tap path for the owner: it is the only spare
gesture the shipped hook can deliver without touching `android/**`.

Fallbacks in `src/present/ps_remote.gd` / `main.gd` (only for a stock template
without the native hook):

* `InputEventJoypadButton`: `JOY_BUTTON_A`(0) -> OK, `JOY_BUTTON_B`(1) -> BACK,
  `JOY_BUTTON_DPAD_UP..RIGHT` (11..14) -> UP/DOWN/LEFT/RIGHT.
* raw Android keycodes (19..22, 23/66/96/160/85/62, 4/111) when
  `OS.has_feature("android")` and `unicode == 0`.

## 4. Why one press cannot fire twice

1. **Original event is consumed.** For every remote key, `dispatchKeyEvent`
   returns `true` after the synthetic event was handled. Android does not
   deliver a consumed event again, and Godot's joypad path never sees it. There
   is exactly one injected event per physical event.
2. **Broadcast vs. dispatch de-duplication.** `lastDispatchAt[canonical]` is
   recorded on every `dispatchKeyEvent`; a `SendHotKey` broadcast waits 40 ms,
   then is dropped if the same canonical key was dispatched within the last
   200 ms. Broadcast-only keys are not recorded, so two intentional presses
   through that channel still fire twice.
3. **Router backstop.** `main.gd::_dispatch_action()` drops the same action in
   the same frame or within `DUP_ACTION_MS` (90 ms). This is the final guard if
   a future build adds a third delivery path.
4. **Release events do nothing.** `_input` returns on `not pressed`; the
   broadcast's synthetic up only clears state.

## 5. Device verification

Expected log lines at launch (proves the custom class is installed):

```
I GodotRemoteInput: remote key hook active: dispatchKeyEvent -> synthetic keyboard KeyEvent (source=0)
I GodotRemoteInput: hotkey receiver registered: com.youdoo.assistant.SendHotKey
```

Then one line per physical press/release, for example:

```
I GodotRemoteInput: key=19 action=down name=KEYCODE_DPAD_UP source=1793 repeat=0 device=9
I GodotRemoteInput: injected key=19 action=down name=KEYCODE_DPAD_UP repeat=0 handled=true
I GodotRemoteInput: key=19 action=up name=KEYCODE_DPAD_UP source=1793 repeat=0 device=9
I GodotRemoteInput: injected key=19 action=up name=KEYCODE_DPAD_UP repeat=0 handled=true

I GodotRemoteInput: key=23 action=down name=KEYCODE_DPAD_CENTER source=1793 repeat=0 device=9
I GodotRemoteInput: mapped key=23 -> key=66 (KEYCODE_ENTER)
I GodotRemoteInput: injected key=66 action=down name=KEYCODE_ENTER repeat=0 handled=true

I GodotRemoteInput: key=96 action=down name=KEYCODE_BUTTON_A source=1793 repeat=0 device=9
I GodotRemoteInput: mapped key=96 -> key=66 (KEYCODE_ENTER)
I GodotRemoteInput: injected key=66 action=down name=KEYCODE_ENTER repeat=0 handled=true
```

And in the game log (debug build auto-enables `[key]`):

```
[key] event=pressed code=4194320 physical=4194320 unicode=0     # UP
[key] event=pressed code=4194309 physical=4194309 unicode=10    # OK (unicode may be 0/10; not used)
[key] event=pressed code=4194376 physical=4194376 unicode=0     # BACK
```

### Commands

```powershell
$adb = 'D:\platform-tools\adb.exe'
$serial = '172.28.252.150:5555'

# 0) install the new build (coordinator does this)
# & $adb -s $serial install -r -t build\PoseSnake.apk

# 1) prove the hook class is live
& $adb -s $serial logcat -c
& $adb -s $serial shell am force-stop com.youdoo.posesnake
& $adb -s $serial shell monkey -p com.youdoo.posesnake -c android.intent.category.LAUNCHER 1
& $adb -s $serial logcat -d -s GodotRemoteInput | Select-Object -First 5

# 2) capture a human pressing each RCU button once, in one window
& $adb -s $serial logcat -c
Write-Host 'Press UP, DOWN, LEFT, RIGHT, OK, BACK once each within 60 s...'
Start-Sleep -Seconds 60
& $adb -s $serial logcat -d -s GodotRemoteInput godot |
    Set-Content evidence\remote-keys.txt
Select-String -Path evidence\remote-keys.txt -Pattern 'GodotRemoteInput: key='
Select-String -Path evidence\remote-keys.txt -Pattern '\[key\] event=pressed'
```

Pass criteria:

* launch lines present;
* one `GodotRemoteInput: key=<code> action=down` + one `action=up` per press;
* corresponding `[key] event=pressed` in the game log;
* menu focus/selection moves exactly once per press (no double-step).

### If the remote still sends nothing

1. **No launch lines** -> the APK did not include the override. Run
   `tools\setup_android_build.ps1` and check
   `android/build/src/main/java/com/godot/game/GodotApp.java` contains
   `GodotRemoteInput`; then rebuild in Gradle (not the prebuilt template).
2. **Launch lines present, but no `key=` lines while pressing** -> the platform
   is swallowing the keys before the Activity. Check the kernel sees them:
   ```powershell
   & $adb -s $serial shell getevent -lt
   & $adb -s $serial shell dumpsys input | Select-String -Pattern 'YouDoo Remote'
   ```
   If `getevent` shows events but `GodotRemoteInput` does not, the
   `com.youdoo.assistant` layer owns them. Look for the fallback:
   ```powershell
   & $adb -s $serial logcat -d -s GodotRemoteInput |
       Select-String -Pattern 'broadcast hotkey'
   ```
   * `broadcast hotkey ... -> key=...` followed by `accepted` -> the fallback
     delivered it; `[key]` should follow.
   * `suppressed` means `dispatchKeyEvent` already handled the same key.
   * no broadcast lines at all -> send the coordinator the `getevent` capture.
     The remaining platform channel is the SDK's
     `com.sdt.settings.apiservice` `IInputDeviceService` (the skiing project's
     `skeletonbridge` TCP 18082 wrapper); it is not part of the shipped APK.
3. **`key=` lines but no `[key]`** -> the synthetic event was not handled
   (`injected ... handled=false`). Check that the game window is focused
   (`dumpsys window | findstr mCurrentFocus`) and that the APK is the Gradle
   build. `handled=true` but no `[key]` means the event reached Godot's view but
   was classified as gamepad again; confirm the log line has `source=1793` on
   the original and no `source` mismatch on `injected` (synthetic must be
   source 0).
4. **Double steps** -> capture both `GodotRemoteInput` and `godot` logs; if the
   same action appears twice more than 90 ms apart, the broadcast fallback is
   racing a late `dispatchKeyEvent`. Increase `HOTKEY_DEDUPE_MS` /
   `HOTKEY_SETTLE_MS` in `GodotApp.java` and re-apply.

## 6. Standalone Java check

No APK is built by this change. The exact source Gradle compiles was checked
with javac:

```powershell
powershell -NoProfile -File tools\verify_godotapp_javac.ps1 -Jdk C:\jdkcopy
```

Equivalent core command:

```
C:\jdkcopy\bin\javac.exe -encoding UTF-8 -source 17 -target 17 -Xlint:-options
  -classpath "D:\android_tc\sdk\platforms\android-35\android.jar;<repo>\android\_work\godot-classes.jar;<repo>\android\_work\javac-libs\*"
  -d <repo>\android\_work\javac-out
  <repo>\android\build\src\main\java\com\godot\game\GodotApp.java
  <repo>\android\build\build\generated\source\buildConfig\standard\debug\com\godot\game\BuildConfig.java
```

`android/_work/javac-libs/` is populated from the Gradle cache's androidx AARs
by the script on first run. `GodotApp.class` is produced under
`android/_work/javac-out/`.
