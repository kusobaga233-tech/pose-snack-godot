/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.Godot;
import org.godotengine.godot.GodotActivity;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.util.SparseLongArray;
import android.view.KeyEvent;
import android.view.View;

import androidx.activity.EdgeToEdge;
import androidx.core.splashscreen.SplashScreen;

/**
 * Template activity for Godot Android builds, extended with a native RCU key hook.
 *
 * Why this exists (verified on the Youdoo HP52S0 box):
 *   - The physical remote is enumerated as a gamepad (`source=1793`, which carries
 *     SOURCE_GAMEPAD). Godot's `GodotInputHandler.isKeyEventGameDevice()` therefore
 *     routes its key events into the joypad path. KEYCODE_DPAD_UP..RIGHT become
 *     JOY_BUTTON_DPAD_* (11..14), while KEYCODE_DPAD_CENTER (23) maps to the
 *     invalid button -102 and is logged as
 *       `ERROR: Index (int)p_button = -102 is out of bounds ((int)JoyButton::MAX = 128)`
 *     and dropped. The GDScript router only listens to InputEventKey, so a human
 *     pressing the remote produces zero `[key]` lines.
 *   - adb-injected keys work because they arrive as SOURCE_KEYBOARD.
 *
 * Fix (ported from the GaoShanSki reference project's GodotApp.java, same platform):
 *   - `dispatchKeyEvent` logs every key under the `GodotRemoteInput` tag.
 *   - Every remote key is consumed and re-dispatched as a synthetic KeyEvent with
 *     `deviceId=-1, scanCode=0`, i.e. `source=0` (SOURCE_UNKNOWN). Godot then takes
 *     its keyboard path and translates the Android keycode through
 *     `android_keys_utils.h` (19->KEY_UP ... 23->KEY_ENTER, 4->KEY_BACK).
 *   - KEYCODE_BUTTON_A (96) has no Godot keyboard mapping, so it is canonicalised
 *     to KEYCODE_ENTER (66) before injection; the same canonicalisation covers
 *     NUMPAD_ENTER/MEDIA_PLAY_PAUSE/SPACE.
 *   - The platform's second channel, `com.youdoo.assistant.SendHotKey`, is received
 *     as a fallback for keys the platform never lets through as KeyEvents.
 *   - The hook is strictly re-entrancy-safe. The decor view re-enters
 *     `dispatchKeyEvent` through `Window.Callback`, so an `INJECTING` thread-local
 *     (try/finally) plus the synthetic signature (`deviceId=-1, scanCode=0,
 *     source=0`) guarantee exactly one injected ACTION_DOWN and one ACTION_UP per
 *     physical press and make recursion impossible.
 *
 * The original event is consumed (dispatchKeyEvent returns true) so the same press
 * can never reach Godot's joypad path as well; see `deliverBroadcastKey` for the
 * cross-channel de-duplication.
 *
 * Source of truth: this file lives in `android/build-overrides/`; `tools/setup_android_build.ps1`
 * copies it into the generated `android/build/` template. Edit this copy, not the
 * generated one.
 */
public class GodotApp extends GodotActivity {
	private static final String TAG = "GodotRemoteInput";

	/** Platform broadcast used by the Youdoo assistant for remote hot keys. */
	private static final String ACTION_SEND_HOTKEY = "com.youdoo.assistant.SendHotKey";
	/** Wait this long before acting on a broadcast, so a same-press KeyEvent can win. */
	private static final long HOTKEY_SETTLE_MS = 40L;
	/** A broadcast for a key that `dispatchKeyEvent` delivered this recently is a duplicate. */
	private static final long HOTKEY_DEDUPE_MS = 200L;

	/** Last time `dispatchKeyEvent` injected each canonical Android keycode. */
	private final SparseLongArray lastDispatchAt = new SparseLongArray();
	private final Handler mainHandler = new Handler(Looper.getMainLooper());
	private BroadcastReceiver hotkeyReceiver;

	static {
		// .NET libraries.
		if (BuildConfig.FLAVOR.equals("mono")) {
			try {
				Log.v("GODOT", "Loading System.Security.Cryptography.Native.Android library");
				System.loadLibrary("System.Security.Cryptography.Native.Android");
			} catch (UnsatisfiedLinkError e) {
				Log.e("GODOT", "Unable to load System.Security.Cryptography.Native.Android library");
			}
		}
	}

	/** Android keycodes that mean "confirm" on this platform. */
	private static boolean isConfirmKey(int keyCode) {
		return keyCode == KeyEvent.KEYCODE_DPAD_CENTER   // 23: TV remote OK
				|| keyCode == KeyEvent.KEYCODE_BUTTON_A  // 96: some boxes report OK as gamepad A
				|| keyCode == KeyEvent.KEYCODE_ENTER     // 66
				|| keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
				|| keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
				|| keyCode == KeyEvent.KEYCODE_SPACE;
	}

	/**
	 * Android keycode injected into Godot's keyboard path, or -1 when this event is
	 * not a remote key (leave it to the normal Android/Godot dispatch).
	 *
	 * <p>KEYCODE_MENU (82) is canonicalised to KEYCODE_F6 (136) and KEYCODE_INFO
	 * (165) to KEYCODE_F7 (138), so the box's remote can drive the camera-variant
	 * debug cycle and the pose-mirror toggle without a keyboard. GDScript handles
	 * F6 (`_cycle_camera_mode`) and F7 (`_toggle_pose_mirror`). Both mappings are
	 * logged as `mapped key=82 -> key=136` / `mapped key=165 -> key=138`.
	 *
	 * <p>KEYCODE_F6 and KEYCODE_F7 themselves are deliberately NOT in this switch.
	 * An adb-injected `input keyevent 136` (or 137/138) arrives as SOURCE_KEYBOARD;
	 * returning -1 here makes `dispatchKeyEvent` fall through to
	 * `super.dispatchKeyEvent(event)`, so the event reaches Godot untouched.
	 * Adding them would route them through the synthetic re-injection path; do not.
	 */
	private static int canonicalKeyCode(int keyCode) {
		if (isConfirmKey(keyCode)) {
			// 96/160/85/62 have no useful Godot keyboard mapping; 66 always does.
			return KeyEvent.KEYCODE_ENTER;
		}
		switch (keyCode) {
			case KeyEvent.KEYCODE_DPAD_UP:
			case KeyEvent.KEYCODE_DPAD_DOWN:
			case KeyEvent.KEYCODE_DPAD_LEFT:
			case KeyEvent.KEYCODE_DPAD_RIGHT:
			case KeyEvent.KEYCODE_BACK:
			case KeyEvent.KEYCODE_ESCAPE:
				return keyCode;
			case KeyEvent.KEYCODE_MENU:   // 82: remote MENU -> camera variant cycle
				return KeyEvent.KEYCODE_F6;
			case KeyEvent.KEYCODE_INFO:   // 165: remote INFO -> pose-mirror toggle
				return KeyEvent.KEYCODE_F7;
			default:
				// Unmapped keys (including F6/F7 from adb) fall through to the
				// normal dispatch path: the hook must never swallow them.
				return -1;
		}
	}

	private static String actionName(int action) {
		if (action == KeyEvent.ACTION_DOWN) {
			return "down";
		}
		if (action == KeyEvent.ACTION_UP) {
			return "up";
		}
		return Integer.toString(action);
	}

	/**
	 * True while this thread is inside one of our own `decor.dispatchKeyEvent(...)`
	 * injections.
	 *
	 * The decor view dispatches key events through `Window.Callback`, i.e. straight
	 * back into this activity's `dispatchKeyEvent` override. Injecting from there
	 * recursed forever: one physical press produced 151 `key=` lines, zero
	 * `action=up` lines, and a `StackOverflowError` that killed the process at
	 * 17:54:57 (main thread, 8 MB stack).
	 *
	 * ThreadLocal because a key event may be dispatched from a non-main thread;
	 * restored in a `finally` so a throw mid-injection cannot leave the hook
	 * permanently wedged (which would silently disable the remote).
	 */
	private static final ThreadLocal<Boolean> INJECTING = new ThreadLocal<>();

	/**
	 * True when `event` is one of our own synthetic events.
	 *
	 * `injectKeyboardKey` builds them with `deviceId=-1, scanCode=0`; the 8-argument
	 * KeyEvent constructor leaves `source` at SOURCE_UNKNOWN (0), so the three
	 * fields together identify ours. Platform keys never match all three: the RCU
	 * reports `source=1793, device=9`, adb `input keyevent` reports SOURCE_KEYBOARD,
	 * and a real keyboard event carries a real device id and scan code.
	 *
	 * Second line of defence behind `INJECTING`: a matching event is forwarded to
	 * the normal path and is never logged as a remote key, canonicalised or
	 * injected again.
	 */
	private static boolean isInjectedSynthetic(KeyEvent event) {
		return event.getDeviceId() == -1
				&& event.getScanCode() == 0
				&& event.getSource() == 0;
	}

	/**
	 * Sends a pure-keyboard KeyEvent (source=0) to the decor view.
	 *
	 * This is the mechanism that is known to work on this box: it is the
	 * `injectEnter()` path from the reference project. Keeping source=0 is what
	 * makes Godot take `handleKeyEvent` instead of `handleJoystickButtonEvent`.
	 *
	 * The decor dispatches through `Window.Callback` and therefore re-enters
	 * `dispatchKeyEvent`; `INJECTING` is raised for the duration so the re-entry
	 * only forwards to the normal path. Restored in a `finally`.
	 */
	private boolean injectKeyboardKey(int keyCode, int action, int repeat) {
		View decor = getWindow() != null ? getWindow().getDecorView() : null;
		if (decor == null) {
			Log.w(TAG, "inject failed: no decor view (key=" + keyCode + ")");
			return false;
		}
		long now = SystemClock.uptimeMillis();
		// 8-arg KeyEvent: deviceId=-1, scanCode=0; source is SOURCE_UNKNOWN (0).
		KeyEvent synthetic = new KeyEvent(now, now, action, keyCode, repeat, 0, -1, 0);
		final boolean wasInjecting = Boolean.TRUE.equals(INJECTING.get());
		INJECTING.set(Boolean.TRUE);
		boolean handled;
		try {
			handled = decor.dispatchKeyEvent(synthetic);
		} finally {
			if (wasInjecting) {
				INJECTING.set(Boolean.TRUE);
			} else {
				INJECTING.remove();
			}
		}
		Log.i(TAG, "injected key=" + keyCode + " action=" + actionName(action)
				+ " name=" + KeyEvent.keyCodeToString(keyCode)
				+ " repeat=" + repeat + " handled=" + handled);
		return handled;
	}

	@Override
	public boolean dispatchKeyEvent(KeyEvent event) {
		// Re-entrancy guard, first line of defence. `injectKeyboardKey` dispatches
		// the synthetic event through the decor view, whose Window.Callback calls
		// this override again. While an injection is in flight, never inject: hand
		// the event to the normal window path (once) and let it be consumed there.
		if (Boolean.TRUE.equals(INJECTING.get())) {
			Log.i(TAG, "[inject] re-entry source=" + event.getSource()
					+ " device=" + event.getDeviceId()
					+ " action=" + actionName(event.getAction()) + ": forwarded, not injected");
			return super.dispatchKeyEvent(event);
		}

		// Our own synthetic event, second line of defence (e.g. one re-posted on a
		// thread that never set the flag). Forward it untouched: it is not a remote
		// key, so no remote log line, no canonicalisation and no second injection.
		if (isInjectedSynthetic(event)) {
			Log.i(TAG, "[inject] synthetic code=" + event.getKeyCode()
					+ " action=" + actionName(event.getAction()) + ": forwarded");
			return super.dispatchKeyEvent(event);
		}

		final int keyCode = event.getKeyCode();
		final int action = event.getAction();
		Log.i(TAG, "key=" + keyCode + " action=" + actionName(action)
				+ " name=" + KeyEvent.keyCodeToString(keyCode)
				+ " source=" + event.getSource()
				+ " repeat=" + event.getRepeatCount()
				+ " device=" + event.getDeviceId());

		final int canonical = canonicalKeyCode(keyCode);
		if (canonical < 0 || (action != KeyEvent.ACTION_DOWN && action != KeyEvent.ACTION_UP)) {
			return super.dispatchKeyEvent(event);
		}

		if (action == KeyEvent.ACTION_DOWN && event.getRepeatCount() > 0) {
			// Exactly one injected down + up per physical press: the platform
			// reports a held key as repeated ACTION_DOWN, which would otherwise be
			// injected as extra presses (menus would advance several times).
			Log.i(TAG, "[inject] repeat suppressed code=" + keyCode
					+ " repeat=" + event.getRepeatCount());
			return true;
		}

		lastDispatchAt.put(canonical, SystemClock.uptimeMillis());
		if (canonical != keyCode) {
			Log.i(TAG, "mapped key=" + keyCode + " -> key=" + canonical
					+ " (" + KeyEvent.keyCodeToString(canonical) + ")");
		}

		if (injectKeyboardKey(canonical, action, 0)) {
			// Consume the original. It must not also reach Godot's joypad path.
			return true;
		}

		// Engine not ready or the view did not take the synthetic event: fall back
		// to the normal path. This still delivers the press once, not twice.
		Log.w(TAG, "synthetic key not handled; falling back to normal dispatch for key=" + keyCode);
		return super.dispatchKeyEvent(event);
	}

	/**
	 * Second channel: the platform's remote-hotkey broadcast. Some keys (notably
	 * OK on some boxes) never reach `dispatchKeyEvent`; this is the fallback.
	 */
	private void registerHotkeyReceiver() {
		hotkeyReceiver = new BroadcastReceiver() {
			@Override
			public void onReceive(Context context, Intent intent) {
				if (intent == null) {
					return;
				}
				final int specialKey = intent.getIntExtra("specialKey", 0);
				final String deviceName = intent.getStringExtra("deviceName");
				final int mapped = canonicalKeyCode(specialKey);
				// Unknown platform code: mirror the reference and treat it as OK
				// instead of dropping the only channel the platform gives us.
				final int canonical = mapped >= 0 ? mapped : KeyEvent.KEYCODE_ENTER;
				Log.i(TAG, "broadcast hotkey specialKey=" + specialKey
						+ " device=" + deviceName
						+ " -> key=" + canonical);
				mainHandler.postDelayed(
						() -> deliverBroadcastKey(canonical, specialKey), HOTKEY_SETTLE_MS);
			}
		};
		IntentFilter filter = new IntentFilter(ACTION_SEND_HOTKEY);
		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
				registerReceiver(hotkeyReceiver, filter, Context.RECEIVER_EXPORTED);
			} else {
				registerReceiver(hotkeyReceiver, filter);
			}
			Log.i(TAG, "hotkey receiver registered: " + ACTION_SEND_HOTKEY);
		} catch (Exception error) {
			Log.w(TAG, "hotkey receiver register failed: " + error);
		}
	}

	/** Delivers one down+up pair unless `dispatchKeyEvent` already handled this key. */
	private void deliverBroadcastKey(int canonical, int specialKey) {
		long now = SystemClock.uptimeMillis();
		long last = lastDispatchAt.get(canonical, Long.MIN_VALUE);
		if (last != Long.MIN_VALUE && now - last < HOTKEY_DEDUPE_MS) {
			Log.i(TAG, "broadcast hotkey suppressed: key=" + canonical
					+ " already delivered by dispatchKeyEvent " + (now - last) + "ms ago");
			return;
		}
		Log.i(TAG, "broadcast hotkey accepted: specialKey=" + specialKey + " -> key=" + canonical);
		injectKeyboardKey(canonical, KeyEvent.ACTION_DOWN, 0);
		injectKeyboardKey(canonical, KeyEvent.ACTION_UP, 0);
	}

	private final Runnable updateWindowAppearance = () -> {
		Godot godot = getGodot();
		if (godot != null) {
			godot.enableImmersiveMode(godot.isInImmersiveMode(), true);
			godot.enableEdgeToEdge(godot.isInEdgeToEdgeMode(), true);
			godot.setSystemBarsAppearance();
		}
	};

	@Override
	public void onCreate(Bundle savedInstanceState) {
		SplashScreen.installSplashScreen(this);
		EdgeToEdge.enable(this);
		super.onCreate(savedInstanceState);
		Log.i(TAG, "remote key hook active: dispatchKeyEvent -> synthetic keyboard KeyEvent (source=0)");
		registerHotkeyReceiver();
	}

	@Override
	public void onDestroy() {
		if (hotkeyReceiver != null) {
			try {
				unregisterReceiver(hotkeyReceiver);
			} catch (Exception ignored) {
				// Already unbound by the system.
			}
			hotkeyReceiver = null;
		}
		super.onDestroy();
	}

	@Override
	public void onResume() {
		super.onResume();
		updateWindowAppearance.run();
	}

	@Override
	public void onGodotMainLoopStarted() {
		super.onGodotMainLoopStarted();
		runOnUiThread(updateWindowAppearance);
	}

	@Override
	public void onGodotForceQuit(Godot instance) {
		if (!BuildConfig.FLAVOR.equals("instrumented")) {
			// For instrumented builds, we disable force-quitting to allow the instrumented tests to complete
			// successfully, otherwise they fail when the process crashes.
			super.onGodotForceQuit(instance);
		}
	}
}
