package com.youdoo.godot;

import android.hardware.HardwareBuffer;
import android.util.Log;

/**
 * JNI bridge that turns the camera {@link HardwareBuffer} into flat RGBA8 bytes.
 *
 * <p><b>Why a native shim is unavoidable.</b> The SDK's Unity plugin exports
 * {@code CopyHardwareBufferToMemory}, {@code CopyHardwareBufferToMemoryWithScale} and
 * {@code GetHardwareBufferInfo} from {@code libyoudoo_plugin.so}, but those are plain C
 * symbols with <em>no</em> JNI binding: the library only registers
 * {@code Java_com_youdoo_jni_YoudooPlugin_setHardwareBufferForGraphics} for Java. Java
 * has no FFI, so a plugin written in Java cannot call them at all - not even with a
 * valid {@code long} pointer, and the pointer the Unity sample uses comes from a native
 * out-param that the vendor documents as obsolete since SDK 4.0 (this build is 4.8.0).
 * {@code android.hardware.HardwareBuffer} itself exposes no pixel access, and
 * {@code Bitmap.wrapHardwareBuffer} rejects YUV420. So the only Java-reachable route is
 * our own JNI method, exactly like the vendor's own non-Unity bridge
 * ({@code Tools~/Android/SkeletonBridge/app/src/main/cpp/youdoo_plugin_rpc.cpp}).
 *
 * <p><b>Native side.</b> {@code android/native/camframe.c}, packaged as
 * {@code libcamframe.so} inside {@code android/plugins/youdoo/youdoo_camframe-release.aar}
 * and rebuilt with {@code android/native/build_camframe.ps1}. It uses
 * {@code AHardwareBuffer_fromHardwareBuffer} + {@code AHardwareBuffer_lockPlanes} and
 * converts BT.601 limited-range YUV420 (or copies RGBA8) with nearest-neighbour scaling.
 *
 * <p><b>Contract.</b> {@link #readRgba} writes {@code outWidth * outHeight * 4} RGBA8
 * bytes into {@code out} (row major, top-left origin, alpha 0xFF), nearest-neighbour
 * scaled from the buffer's own size, optionally mirrored horizontally, and returns the
 * byte count written or a negative value on failure. It closes nothing: the caller owns
 * the buffer and closes it after the call.
 *
 * <p>Loading is attempted once and a failure is logged under the {@code YoudooSkeleton}
 * tag; no exception escapes. Without the library the pump still runs as a frame and
 * dimension probe.
 */
final class CameraFrameNative {
    private static final String TAG = "YoudooSkeleton";

    /** {@code System.loadLibrary()} name; the packaged file is {@code libcamframe.so}. */
    static final String LIBRARY = "camframe";

    private static final boolean LOADED;
    private static final String LOAD_ERROR;

    static {
        boolean loaded = false;
        String error = "";
        try {
            System.loadLibrary(LIBRARY);
            loaded = true;
        } catch (Throwable throwable) {
            // Off-device, or a build without the native module: never fatal.
            error = throwable.getClass().getSimpleName() + ": " + throwable.getMessage();
            Log.w(TAG, "[cam] pixel reader lib" + LIBRARY + ".so unavailable (" + error
                    + "); frames will be probed but not delivered");
        }
        LOADED = loaded;
        LOAD_ERROR = error;
    }

    private CameraFrameNative() {
    }

    /** True only when the native readback module is packaged and loaded. */
    static boolean isAvailable() {
        return LOADED;
    }

    /** Human readable reason when {@link #isAvailable()} is false ("" when available). */
    static String unavailableReason() {
        return LOADED ? "" : "lib" + LIBRARY + ".so missing (" + LOAD_ERROR + ")";
    }

    /**
     * Converts {@code buffer} into {@code out} as RGBA8, scaled to
     * {@code outWidth x outHeight}.
     *
     * @param width      buffer width from {@link HardwareBuffer#getWidth()} (cross-checked
     *                   against the native description, not used for indexing)
     * @param height     buffer height from {@link HardwareBuffer#getHeight()}
     * @param outWidth   target width, must be positive
     * @param outHeight  target height, must be positive
     * @param flipX      mirror horizontally inside the native pass; the Godot side keeps
     *                   this false so mirroring stays GDScript-owned and deterministic
     * @param out        destination array, at least {@code outWidth * outHeight * 4} bytes
     * @return bytes written ({@code outWidth * outHeight * 4}) or a negative value
     */
    static native int readRgba(HardwareBuffer buffer, int width, int height,
                               int outWidth, int outHeight, boolean flipX, byte[] out);
}
