package com.youdoo.godot;

import android.hardware.HardwareBuffer;
import android.os.RemoteException;
import android.os.SystemClock;
import android.util.Base64;
import android.util.Log;

import com.sdt.game.service.IGameServiceV1_0_3;

/**
 * Pumps camera frames out of the YoudooGame SDK binder into a single RGBA slot.
 *
 * <p>This is the Godot-side equivalent of the SDK's own camera pipeline: the service
 * pushes {@code FrameInfo} objects that carry a frame timestamp, and
 * {@code IGameServiceV1_0_3.getFrameBuffer(frameTimeMs)} returns the
 * {@link HardwareBuffer} captured at that timestamp. The pump therefore does not invent
 * timestamps: every tick it asks the host for the newest pose frame time and skips the
 * fetch when that timestamp has not changed, so the 15 fps budget only ever spends
 * binder calls on frames that actually exist.
 *
 * <p><b>Latest-frame semantics, never a queue.</b> Exactly one frame is kept. A newer
 * frame overwrites the older one and increments {@code drops} when the previous frame was
 * never read, so a slow consumer costs memory nothing and lag nothing: it simply misses
 * frames. The RGBA buffer is reused while the output size is unchanged, so steady state
 * allocates zero bytes per frame (the {@code byte[]} only grows when the scaled size
 * changes).
 *
 * <p><b>Off-device and binder-less builds are a strict no-op.</b> Nothing is started
 * without a bound {@code IGameServiceV1_0_3}; the class is only ever constructed by the
 * plugin on the Android host, and {@link CameraFrameNative} catches its own load failure.
 */
final class CameraFramePump {
    private static final String TAG = "YoudooSkeleton";

    /** Default capture rate; the SDK's own Unity bridge caps at 30 fps. */
    static final int DEFAULT_FPS = 15;
    /** Default downscale: 0.3 keeps a 1280x720 device frame at 384x216 (16:9). */
    static final float DEFAULT_SCALE = 0.3f;

    private static final int MIN_FPS = 1;
    private static final int MAX_FPS = 30;
    private static final float MIN_SCALE = 0.05f;
    private static final float MAX_SCALE = 1.0f;
    private static final int MAX_DIMENSION = 8192;
    private static final long LOG_INTERVAL_MS = 1000L;
    private static final long ERROR_LOG_INTERVAL_MS = 5000L;
    private static final int MAX_BASE64_BYTES = 4 * 1024 * 1024;

    private static final int FORMAT_RGBA_8888 = 0x1;
    private static final int FORMAT_BLOB = 0x21;
    private static final int FORMAT_YUV420 = 0x23;

    /** What the plugin provides: the current binder and the newest pose timestamp. */
    interface Host {
        /** Bound {@code IGameServiceV1_0_3}, or null when the service is not usable. */
        IGameServiceV1_0_3 service();

        /** {@code FrameInfo.getFrameTimeMs()} of the newest frame, or -1 when stale/none. */
        long latestFrameTimeMs();
    }

    private final Host host;

    private final Object frameLock = new Object();
    /** Reused RGBA destination; guarded by {@link #frameLock}. */
    private byte[] frameBytes;
    private int publishedWidth;
    private int publishedHeight;
    /** Increments on every published frame; guarded by {@link #frameLock}. */
    private long writtenSeq;
    /** Highest seq the consumer has read; guarded by {@link #frameLock}. */
    private long consumedSeq;

    /** Worker-only: size of the current {@link #frameBytes} allocation. */
    private int allocWidth;
    private int allocHeight;

    private volatile boolean running;
    private volatile Thread thread;
    private volatile int targetFps = DEFAULT_FPS;
    private volatile float targetScale = DEFAULT_SCALE;

    private volatile long frames;
    private volatile long drops;
    private volatile long missing;
    private volatile long errors;
    private volatile long lastFrameTime = Long.MIN_VALUE;
    private volatile int sourceWidth;
    private volatile int sourceHeight;
    private volatile int sourceFormat;
    private volatile String lastError = "";
    private volatile long lastErrorLogAt;
    private volatile String pointerProbe = "";
    private boolean loggedWaiting;
    private boolean loggedFirstFrame;

    CameraFramePump(Host host) {
        this.host = host;
    }

    // ------------------------------------------------------------- lifecycle

    boolean isRunning() {
        return running;
    }

    int rate() {
        return targetFps;
    }

    float scale() {
        return targetScale;
    }

    boolean readerAvailable() {
        return CameraFrameNative.isAvailable();
    }

    /** Clamps to 1..30 fps; the worker picks the new period up on its next tick. */
    boolean setRate(int fps) {
        int clamped = Math.max(MIN_FPS, Math.min(MAX_FPS, fps));
        targetFps = clamped;
        Log.i(TAG, "[cam] rate=" + clamped + " fps");
        return true;
    }

    /** Clamps to 0.05..1.0; a different output size reallocates once. */
    boolean setScale(float value) {
        if (Float.isNaN(value) || Float.isInfinite(value)) {
            Log.w(TAG, "[cam] scale rejected: " + value);
            return false;
        }
        float clamped = Math.max(MIN_SCALE, Math.min(MAX_SCALE, value));
        targetScale = clamped;
        Log.i(TAG, "[cam] scale=" + roundedScale(clamped));
        return true;
    }

    /**
     * Starts the worker. Returns false - and starts nothing - when the binder is absent,
     * which is what keeps desktop and pre-bind calls inert.
     */
    boolean start() {
        if (running) {
            Log.i(TAG, "[cam] start(): already running");
            return true;
        }
        if (host.service() == null) {
            lastError = "IGameServiceV1_0_3 not bound";
            Log.w(TAG, "[cam] start refused: " + lastError);
            return false;
        }
        synchronized (frameLock) {
            frameBytes = null;
            publishedWidth = 0;
            publishedHeight = 0;
            writtenSeq = 0;
            consumedSeq = 0;
        }
        allocWidth = 0;
        allocHeight = 0;
        frames = 0;
        drops = 0;
        missing = 0;
        errors = 0;
        lastFrameTime = Long.MIN_VALUE;
        lastError = "";
        pointerProbe = "";
        loggedWaiting = false;
        loggedFirstFrame = false;
        running = true;

        Thread worker = new Thread(new Runnable() {
            @Override
            public void run() {
                loop();
            }
        }, "YoudooCameraFrames");
        worker.setDaemon(true);
        thread = worker;
        Log.i(TAG, "[cam] start fps=" + targetFps + " scale=" + roundedScale(targetScale)
                + " reader=" + (CameraFrameNative.isAvailable()
                        ? "ok" : "MISSING: " + CameraFrameNative.unavailableReason()));
        worker.start();
        return true;
    }

    /** Stops the worker; a no-op when it never ran. */
    void stop() {
        if (!running) {
            return;
        }
        running = false;
        Thread worker = thread;
        thread = null;
        if (worker != null) {
            worker.interrupt();
            try {
                worker.join(400L);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
            }
        }
        synchronized (frameLock) {
            frameBytes = null;
            publishedWidth = 0;
            publishedHeight = 0;
            writtenSeq = 0;
            consumedSeq = 0;
        }
        allocWidth = 0;
        allocHeight = 0;
        Log.i(TAG, "[cam] stop frames=" + frames + " drops=" + drops
                + " missing=" + missing + " errors=" + errors);
    }

    // ------------------------------------------------------------------- read

    /** Newest published sequence number (0 before the first frame). */
    long seq() {
        synchronized (frameLock) {
            return writtenSeq;
        }
    }

    int width() {
        synchronized (frameLock) {
            return publishedWidth;
        }
    }

    int height() {
        synchronized (frameLock) {
            return publishedHeight;
        }
    }

    /**
     * Newest published RGBA8 bytes, or null. The array is owned by the pump and is
     * overwritten by the next frame, so callers must copy (the Godot bridge does).
     * Reading advances the consumed cursor that drives the {@code drops} counter.
     */
    byte[] bytes() {
        synchronized (frameLock) {
            if (frameBytes == null || writtenSeq == 0) {
                return null;
            }
            consumedSeq = writtenSeq;
            return frameBytes;
        }
    }

    /**
     * Same frame as {@link #bytes()} encoded as base64, or "" when there is nothing to
     * read. Only used when the Godot build cannot marshal {@code byte[]} to
     * {@code PackedByteArray}; it allocates, so it is never on the fast path.
     */
    String base64() {
        synchronized (frameLock) {
            if (frameBytes == null || writtenSeq == 0) {
                return "";
            }
            int length = publishedWidth * publishedHeight * 4;
            if (length <= 0 || length > frameBytes.length || length > MAX_BASE64_BYTES) {
                return "";
            }
            consumedSeq = writtenSeq;
            return Base64.encodeToString(frameBytes, 0, length, Base64.NO_WRAP);
        }
    }

    /** One-line JSON status; always the same keys so GDScript can read it blindly. */
    String infoJson() {
        StringBuilder builder = new StringBuilder(224);
        synchronized (frameLock) {
            builder.append("{\"running\":").append(running);
            builder.append(",\"reader\":").append(CameraFrameNative.isAvailable());
            builder.append(",\"fps\":").append(targetFps);
            builder.append(",\"scale\":").append(roundedScale(targetScale));
            builder.append(",\"frames\":").append(frames);
            builder.append(",\"drops\":").append(drops);
            builder.append(",\"missing\":").append(missing);
            builder.append(",\"errors\":").append(errors);
            builder.append(",\"seq\":").append(writtenSeq);
            builder.append(",\"size\":\"").append(publishedWidth).append('x')
                    .append(publishedHeight).append('"');
        }
        builder.append(",\"src\":\"").append(sourceWidth).append('x')
                .append(sourceHeight).append('"');
        builder.append(",\"format\":\"").append(formatLabel(sourceFormat)).append('"');
        if (!CameraFrameNative.isAvailable()) {
            builder.append(",\"readerError\":\"");
            appendEscaped(builder, CameraFrameNative.unavailableReason());
            builder.append('"');
        }
        if (!pointerProbe.isEmpty()) {
            builder.append(",\"probe\":\"");
            appendEscaped(builder, pointerProbe);
            builder.append('"');
        }
        if (!lastError.isEmpty()) {
            builder.append(",\"error\":\"");
            appendEscaped(builder, lastError);
            builder.append('"');
        }
        builder.append('}');
        return builder.toString();
    }

    // ---------------------------------------------------------------- worker

    private void loop() {
        long lastLogAt = SystemClock.elapsedRealtime();
        while (running && !Thread.currentThread().isInterrupted()) {
            long startedAt = SystemClock.elapsedRealtime();
            try {
                tick();
            } catch (Throwable throwable) {
                recordError("frame loop: " + throwable.getClass().getSimpleName()
                        + ": " + throwable.getMessage());
            }
            long now = SystemClock.elapsedRealtime();
            if (now - lastLogAt >= LOG_INTERVAL_MS) {
                lastLogAt = now;
                Log.i(TAG, "[cam] frames=" + frames + " drops=" + drops
                        + " size=" + sourceWidth + "x" + sourceHeight + suffix());
            }
            long period = Math.max(1L, 1000L / Math.max(1, targetFps));
            long sleep = period - (SystemClock.elapsedRealtime() - startedAt);
            if (sleep > 0L) {
                try {
                    Thread.sleep(sleep);
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    return;
                }
            } else {
                Thread.yield();
            }
        }
    }

    /** One bounded attempt: fetch the newest frame, convert it, publish it. */
    private void tick() {
        IGameServiceV1_0_3 service = host.service();
        if (service == null) {
            if (!loggedWaiting) {
                loggedWaiting = true;
                Log.i(TAG, "[cam] waiting for IGameServiceV1_0_3 to bind");
            }
            return;
        }
        long frameTime = host.latestFrameTimeMs();
        if (frameTime <= 0L || frameTime == lastFrameTime) {
            // No new pose frame since the last fetch: spending a binder call would only
            // return the same buffer again.
            return;
        }
        lastFrameTime = frameTime;

        HardwareBuffer buffer = null;
        try {
            buffer = service.getFrameBuffer(frameTime);
            if (buffer == null) {
                missing++;
                recordError("getFrameBuffer(" + frameTime + ") returned null");
                return;
            }
            int width = buffer.getWidth();
            int height = buffer.getHeight();
            int format = buffer.getFormat();
            if (width <= 0 || height <= 0 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
                recordError("bad buffer size " + width + "x" + height);
                return;
            }
            frames++;
            sourceWidth = width;
            sourceHeight = height;
            sourceFormat = format;
            if (!loggedFirstFrame) {
                loggedFirstFrame = true;
                Log.i(TAG, "[cam] first frame " + width + "x" + height
                        + " format=" + formatLabel(format));
            }
            probePointer(buffer);
            deliver(buffer, width, height);
        } catch (RemoteException exception) {
            recordError("getFrameBuffer: " + exception.getMessage());
        } catch (RuntimeException | LinkageError exception) {
            recordError("frame failed: " + exception.getClass().getSimpleName()
                    + ": " + exception.getMessage());
        } finally {
            if (buffer != null) {
                try {
                    buffer.close();
                } catch (RuntimeException ignored) {
                    // Already closed, or the binder died mid-frame: nothing to do.
                }
            }
        }
    }

    /** Converts into the reusable destination and publishes it as the newest frame. */
    private void deliver(HardwareBuffer buffer, int width, int height) {
        if (!CameraFrameNative.isAvailable()) {
            return;
        }
        int outWidth = Math.max(1, Math.round(width * targetScale));
        int outHeight = Math.max(1, Math.round(height * targetScale));
        if (outWidth > MAX_DIMENSION || outHeight > MAX_DIMENSION) {
            recordError("scaled size out of range " + outWidth + "x" + outHeight);
            return;
        }
        byte[] target;
        synchronized (frameLock) {
            int needed = outWidth * outHeight * 4;
            if (frameBytes == null || allocWidth != outWidth || allocHeight != outHeight
                    || frameBytes.length != needed) {
                frameBytes = new byte[needed];
                allocWidth = outWidth;
                allocHeight = outHeight;
            }
            target = frameBytes;
        }
        int written = CameraFrameNative.readRgba(buffer, width, height,
                outWidth, outHeight, false, target);
        if (written != target.length) {
            recordError("readRgba wrote " + written + " of " + target.length + " bytes");
            return;
        }
        synchronized (frameLock) {
            if (!running) {
                return;
            }
            if (writtenSeq > consumedSeq) {
                // The consumer never read the previous frame: it is dropped, not queued.
                drops++;
            }
            publishedWidth = outWidth;
            publishedHeight = outHeight;
            writtenSeq++;
        }
    }

    /**
     * One-shot diagnostic for the hidden-API question: reports whether
     * {@code HardwareBuffer.mNativeObject} is still reachable by reflection. It is not
     * used for anything else - the readback goes through JNI - but the answer belongs in
     * logcat because it decides whether the obsolete {@code Copy*} route could ever work.
     */
    private void probePointer(HardwareBuffer buffer) {
        if (!pointerProbe.isEmpty()) {
            return;
        }
        String result;
        try {
            java.lang.reflect.Field field = HardwareBuffer.class.getDeclaredField("mNativeObject");
            field.setAccessible(true);
            result = "mNativeObject=0x" + Long.toHexString(field.getLong(buffer));
        } catch (Throwable throwable) {
            result = "mNativeObject blocked: " + throwable.getClass().getSimpleName()
                    + (throwable.getMessage() == null ? "" : ": " + throwable.getMessage());
        }
        pointerProbe = result;
        Log.i(TAG, "[cam] pointer probe: " + result + " (diagnostic only)");
    }

    // --------------------------------------------------------------- helpers

    private void recordError(String message) {
        errors++;
        lastError = message;
        long now = SystemClock.elapsedRealtime();
        if (now - lastErrorLogAt >= ERROR_LOG_INTERVAL_MS) {
            lastErrorLogAt = now;
            Log.w(TAG, "[cam] " + message);
        }
    }

    /** Keeps the per-second line to the documented shape plus a reason when broken. */
    private String suffix() {
        if (!CameraFrameNative.isAvailable()) {
            return " reader=missing";
        }
        if (!lastError.isEmpty()) {
            return " err=" + lastError;
        }
        return "";
    }

    private static float roundedScale(float value) {
        return Math.round(value * 100f) / 100f;
    }

    private static String formatLabel(int format) {
        String name;
        switch (format) {
            case FORMAT_RGBA_8888:
                name = "R8G8B8A8_UNORM";
                break;
            case FORMAT_YUV420:
                name = "Y8Cb8Cr8_420";
                break;
            case FORMAT_BLOB:
                name = "BLOB";
                break;
            default:
                name = "unknown";
                break;
        }
        return "0x" + Integer.toHexString(format) + " " + name;
    }

    private static void appendEscaped(StringBuilder builder, String text) {
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '"' || c == '\\') {
                builder.append('\\').append(c);
            } else if (c < 0x20) {
                builder.append(' ');
            } else {
                builder.append(c);
            }
        }
    }
}
