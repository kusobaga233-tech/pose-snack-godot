package com.youdoo.godot;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.graphics.RectF;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.RemoteException;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import com.sdt.game.service.DetectBox;
import com.sdt.game.service.FrameInfo;
import com.sdt.game.service.IFrameInfoCallback;
import com.sdt.game.service.IGameServiceV1_0_2;
import com.sdt.game.service.IGameServiceV1_0_3;
import com.sdt.game.service.KeyPoint;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Godot Android plugin that binds the YoudooGame SDK AIDL service
 * (com.sdt.game.service) and exposes the newest body-tracking frame to GDScript.
 *
 * <p>The SDK service pushes {@link FrameInfo} objects through
 * {@code registerFrameInfoCallback}; this plugin keeps only the latest one in a
 * volatile field so GDScript can poll it without any per-frame bridge crossing.
 */
public class YoudooSkeletonPlugin extends GodotPlugin {
    private static final String TAG = "YoudooSkeleton";

    private static final String SDK_PACKAGE = "com.sdt.game.service";
    private static final String SDK_SERVICE = "com.sdt.game.service.SdtGameService";
    private static final String ACTION_V103 = "com.sdt.game.service.IGameServiceV1_0_3";
    private static final String ACTION_V102 = "com.sdt.game.service.IGameServiceV1_0_2";
    private static final String BINDER_NONE = "none";
    private static final String BINDER_V103 = "IGameServiceV1_0_3";
    private static final String BINDER_V102 = "IGameServiceV1_0_2";

    /** Upper bounds keep latestFrameJson() small even if the SDK reports a crowd. */
    private static final int MAX_BOXES_PER_MAP = 4;
    private static final int MAX_KEYPOINTS_PER_BOX = 33;
    private static final int MAX_FRAME_JSON_CHARS = 24 * 1024;

    private static final long FRAME_LOG_INTERVAL_MS = 1000L;
    private static final long IDLE_LOG_INTERVAL_MS = 5000L;
    /**
     * A {@link FrameInfo} older than this is not offered to the camera-frame pump: the
     * SDK looks buffers up by frame time, so a stale timestamp can only return null.
     */
    private static final long CAMERA_FRAME_STALE_MS = 2000L;

    /**
     * Camera live is composited by the SDK service (its own SurfaceView in a
     * WindowManager overlay window), not by this plugin: the AIDL call takes no
     * Surface, so there is no texture upload and no extra draw here. The service
     * keeps one entry per id, therefore the plugin also remembers the desired
     * state of every id and re-sends it after a bind reconnect.
     *
     * <p>Rects are kept as the raw AIDL floats, not as {@link RectF}: a source
     * rect may be INVERTED ({@code x1 > x2} / {@code y1 > y2}) to ask the
     * native renderer for a mirror. That is the SDK's own display-mirror
     * mechanism: Unity's {@code CameraImageUvRegionUtility.CalculateUvRect}
     * flips by making the UV width negative ({@code source.x += width;
     * source.width = -width}), and the AIDL call carries the same signed edges
     * straight to the native renderer.
     */
    private static final int CAMERA_LIVE_ID = 0;
    private static final float[] CAMERA_LIVE_SRC_FULL = {0f, 0f, 1f, 1f};
    private static final float[] CAMERA_LIVE_DST_FULL = {0f, 0f, 1f, 1f};
    private static final int CAMERA_LIVE_MODE_DEFAULT = 0;

    /** Desired overlay view, keyed by the AIDL {@code id} (the service's map key). */
    private static final class CameraView {
        boolean on;
        final float[] src = new float[4];
        final float[] dst = new float[4];
        int mode;

        CameraView(boolean on, float[] srcEdges, float[] dstEdges, int mode) {
            this.on = on;
            System.arraycopy(srcEdges, 0, src, 0, 4);
            System.arraycopy(dstEdges, 0, dst, 0, 4);
            this.mode = mode;
        }
    }

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final StringBuilder statusBuilder = new StringBuilder(192);
    private final StringBuilder frameBuilder = new StringBuilder(4096);

    private volatile IGameServiceV1_0_3 service;
    private volatile IGameServiceV1_0_2 legacyService;
    private volatile String binder = BINDER_NONE;
    private volatile boolean bindRequested;
    private volatile FrameInfo latestFrame;
    private volatile long frameCounter;
    private volatile long lastFrameWallMs;
    private volatile long lastFrameLogMs;
    private volatile long lastIdleLogMs;
    private volatile String lastError = "";

    /** Desired camera-live state per id; survives a service rebind. */
    private final Object cameraLock = new Object();
    private final HashMap<Integer, CameraView> cameraViews = new HashMap<>();
    /** Last camera-live call that the service accepted (or false after a drop). */
    private volatile boolean cameraLiveApplied;
    /** Last accepted AIDL mode int, reported by status() for compatibility. */
    private volatile int cameraLiveMode = CAMERA_LIVE_MODE_DEFAULT;
    private volatile String lastCameraLiveError = "";

    /** Created on first camera-frame call; owns the RGBA worker thread. */
    private CameraFramePump framePump;

    private final IFrameInfoCallback frameCallback = new IFrameInfoCallback.Stub() {
        @Override
        public void onFrameInfoEvent(FrameInfo frameInfo) {
            onFrame(frameInfo);
        }
    };

    private final ServiceConnection connection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binderToken) {
            String descriptor = "";
            try {
                descriptor = binderToken.getInterfaceDescriptor();
            } catch (RemoteException exception) {
                Log.w(TAG, "getInterfaceDescriptor failed", exception);
            }
            if (IGameServiceV1_0_3.DESCRIPTOR.equals(descriptor)) {
                service = IGameServiceV1_0_3.Stub.asInterface(binderToken);
                binder = BINDER_V103;
            } else if (IGameServiceV1_0_2.DESCRIPTOR.equals(descriptor)) {
                legacyService = IGameServiceV1_0_2.Stub.asInterface(binderToken);
                binder = BINDER_V102;
            } else {
                binder = "unsupported";
                lastError = "unsupported binder descriptor: " + descriptor;
                Log.e(TAG, lastError);
                return;
            }
            Log.i(TAG, "connected " + name.flattenToShortString() + " descriptor=" + descriptor);
            try {
                registerCallback();
                lastError = "";
                Log.i(TAG, "frame callback registered on " + binder);
                int wantedViews = cameraViewCount();
                if (wantedViews > 0) {
                    Log.i(TAG, "camera live was on before the reconnect: re-applying "
                            + wantedViews + " view(s)");
                    reapplyAllViews("service connected");
                }
            } catch (RemoteException | RuntimeException exception) {
                lastError = "register failed: " + exception;
                Log.e(TAG, "failed to register frame callback on " + binder, exception);
                service = null;
                legacyService = null;
                binder = BINDER_NONE;
            }
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            Log.w(TAG, "disconnected " + name.flattenToShortString());
            clearConnection("disconnected");
        }

        @Override
        public void onBindingDied(ComponentName name) {
            Log.w(TAG, "binding died " + name.flattenToShortString());
            clearConnection("binding died");
        }

        @Override
        public void onNullBinding(ComponentName name) {
            Log.w(TAG, "null binding " + name.flattenToShortString());
            clearConnection("null binding");
        }
    };

    /** Logs a heartbeat while the service is connected but silent, so logs prove the state. */
    private final Runnable heartbeat = new Runnable() {
        @Override
        public void run() {
            long now = SystemClock.elapsedRealtime();
            if (now - lastFrameWallMs >= IDLE_LOG_INTERVAL_MS && now - lastIdleLogMs >= IDLE_LOG_INTERVAL_MS) {
                lastIdleLogMs = now;
                Log.i(TAG, "idle: bound=" + isConnected() + " binder=" + binder
                        + " frames=" + frameCounter + " waiting for frames");
            }
            handler.postDelayed(this, FRAME_LOG_INTERVAL_MS);
        }
    };

    public YoudooSkeletonPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "YoudooSkeleton";
    }

    @Override
    public View onMainCreate(Activity activity) {
        // Headless plugin: no view is added to the Godot activity.
        return null;
    }

    @Override
    public void onMainDestroy() {
        stop();
        super.onMainDestroy();
    }

    // ---------------------------------------------------------------- Godot API

    /** Binds the SDK service and registers the frame callback. Safe to call twice. */
    @UsedByGodot
    public boolean start() {
        Context context = contextOrNull();
        if (context == null) {
            lastError = "no android context";
            Log.e(TAG, "start() failed: " + lastError);
            return false;
        }
        if (isConnected()) {
            Log.i(TAG, "start(): already connected via " + binder);
            return true;
        }
        boolean ok = bindWith(context, ACTION_V103);
        if (!ok) {
            Log.w(TAG, "V1_0_3 bind refused, falling back to V1_0_2");
            ok = bindWith(context, ACTION_V102);
        }
        bindRequested = ok;
        if (!ok) {
            lastError = "bindService returned false for " + ACTION_V103 + " and " + ACTION_V102;
        }
        Log.i(TAG, "start(): bindService=" + ok + " (requested " + ACTION_V103 + ")");
        handler.removeCallbacks(heartbeat);
        handler.postDelayed(heartbeat, FRAME_LOG_INTERVAL_MS);
        return ok;
    }

    /** Unregisters the callback, clears any camera-live overlay and unbinds the service. */
    @UsedByGodot
    public void stop() {
        handler.removeCallbacks(heartbeat);
        if (framePump != null) {
            // The pump calls into the binder, so it must be quiescent before the unbind.
            framePump.stop();
        }
        // The service owns the overlay window: if we go away without clearing it,
        // the camera stays on screen with no owner. Clear every id before unbinding.
        clearAllViews("stop");
        try {
            IGameServiceV1_0_3 boundService = service;
            IGameServiceV1_0_2 boundLegacy = legacyService;
            if (boundService != null) {
                boundService.unregisterFrameInfoCallback(frameCallback);
            } else if (boundLegacy != null) {
                boundLegacy.unregisterFrameInfoCallback(frameCallback);
            }
        } catch (RemoteException exception) {
            Log.w(TAG, "failed to unregister frame callback", exception);
        }
        Context context = contextOrNull();
        if (context != null && bindRequested) {
            try {
                context.unbindService(connection);
            } catch (IllegalArgumentException exception) {
                Log.w(TAG, "service was not bound", exception);
            }
        }
        bindRequested = false;
        clearConnection("stopped");
        Log.i(TAG, "stop(): frames=" + frameCounter);
    }

    /** JSON: {"bound":bool,"binder":"...","frames":N,"lastFrameMs":N,
     *        "cameraSupported":bool,"cameraLive":bool,"cameraMode":N
     *        [,"cameraError":"..."] [,"error":"..."]} */
    @UsedByGodot
    public String status() {
        FrameInfo frame = latestFrame;
        synchronized (statusBuilder) {
            statusBuilder.setLength(0);
            statusBuilder.append("{\"bound\":").append(isConnected());
            statusBuilder.append(",\"binder\":\"").append(binder).append('"');
            statusBuilder.append(",\"frames\":").append(frameCounter);
            statusBuilder.append(",\"lastFrameMs\":").append(frame == null ? 0L : frame.getFrameTimeMs());
            statusBuilder.append(",\"cameraSupported\":").append(service != null);
            statusBuilder.append(",\"cameraLive\":").append(cameraLiveApplied);
            statusBuilder.append(",\"cameraMode\":").append(cameraLiveMode);
            statusBuilder.append(",\"cameraViews\":").append(cameraViewCount());
            if (!lastCameraLiveError.isEmpty()) {
                statusBuilder.append(",\"cameraError\":\"");
                appendEscaped(statusBuilder, lastCameraLiveError);
                statusBuilder.append('"');
            }
            if (!lastError.isEmpty()) {
                statusBuilder.append(",\"error\":\"");
                appendEscaped(statusBuilder, lastError);
                statusBuilder.append('"');
            }
            statusBuilder.append('}');
            return statusBuilder.toString();
        }
    }

    /** JSON of the newest frame, or "{}" before the first frame arrives. */
    @UsedByGodot
    public String latestFrameJson() {
        FrameInfo frame = latestFrame;
        if (frame == null) {
            return "{}";
        }
        synchronized (frameBuilder) {
            frameBuilder.setLength(0);
            frameBuilder.append("{\"frameTimeMs\":").append(frame.getFrameTimeMs());
            frameBuilder.append(",\"imageWidth\":").append(frame.getImageWidth());
            frameBuilder.append(",\"imageHeight\":").append(frame.getImageHeight());
            appendMap(frameBuilder, "persons", frame.getPersons());
            appendMap(frameBuilder, "lHand", frame.getLHand());
            appendMap(frameBuilder, "rHand", frame.getRHand());
            appendMap(frameBuilder, "face", frame.getFace());
            frameBuilder.append('}');
            return frameBuilder.toString();
        }
    }

    @UsedByGodot
    public int frameCount() {
        return (int) Math.min(frameCounter, Integer.MAX_VALUE);
    }

    // ------------------------------------------------------------- camera live

    /**
     * True only while {@link IGameServiceV1_0_3} is bound; the V1_0_2 fallback
     * has no camera-live method at all.
     */
    @UsedByGodot
    public boolean cameraLiveSupported() {
        return service != null;
    }

    /**
     * Legacy single-view entry point (id 0), kept for the 1P path and the
     * verifier recipe. On = send the remembered source/destination rects and
     * mode; off = the legacy teardown, i.e. clear every id the service holds.
     * Nothing is uploaded and no draw call is added here: the SDK service owns
     * a SurfaceView inside a WindowManager overlay window. Returns true when
     * the service accepted the call; false when it cannot be sent (the request
     * is still remembered and is re-sent after a reconnect).
     */
    @UsedByGodot
    public boolean cameraLive(boolean on) {
        if (!on) {
            Log.i(TAG, "cameraLive(false): clearing all ids (supported=" + (service != null)
                    + " binder=" + binder + ")");
            return clearAllViews("cameraLive(false)");
        }
        float[] src;
        float[] dst;
        int mode;
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(CAMERA_LIVE_ID);
            if (view == null) {
                view = new CameraView(true, CAMERA_LIVE_SRC_FULL, CAMERA_LIVE_DST_FULL,
                        CAMERA_LIVE_MODE_DEFAULT);
                cameraViews.put(CAMERA_LIVE_ID, view);
            }
            view.on = true;
            src = view.src.clone();
            dst = view.dst.clone();
            mode = view.mode;
        }
        Log.i(TAG, "cameraLive(" + on + "): supported=" + (service != null)
                + " binder=" + binder + " src=" + rect4(src) + " dst=" + rect4(dst)
                + " mode=" + mode);
        return applyView(CAMERA_LIVE_ID, "cameraLive(on)");
    }

    /**
     * Drives ONE camera-live view by its AIDL {@code id}. The SDK service keeps
     * a {@code HashMap<Integer, ...>} of views, so ids 0 and 1 can show two
     * previews at once (one per player in 2P). Godot calls this with plain
     * primitives because array arguments do not cross the plugin JNI bridge.
     *
     * <p>{@code srcX1..srcY2} is the source crop and {@code dstX1..dstY2} the
     * on-screen destination, in the AIDL wire order proven on device. The
     * source crop is signed on purpose: {@code srcX1 > srcX2} requests a
     * horizontal flip, which is how the SDK itself mirrors
     * ({@code CameraImageUvRegionUtility} uses a negative UV width). Values are
     * normalized 0..1 but not clamped, so an inverted edge survives.
     *
     * @return true only when the service accepted this call (a request made
     *         before the bind is remembered and re-sent after a reconnect).
     */
    @UsedByGodot
    public boolean cameraLiveView(int id, boolean on,
                                  float srcX1, float srcY1, float srcX2, float srcY2,
                                  float dstX1, float dstY1, float dstX2, float dstY2,
                                  int mode) {
        if (id < 0) {
            lastCameraLiveError = "cameraLiveView: id < 0";
            Log.w(TAG, lastCameraLiveError);
            return false;
        }
        float[] src = {srcX1, srcY1, srcX2, srcY2};
        float[] dst = {dstX1, dstY1, dstX2, dstY2};
        if (!allFinite(src) || !allFinite(dst)) {
            lastCameraLiveError = "cameraLiveView: non-finite value";
            Log.w(TAG, lastCameraLiveError);
            return false;
        }
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(id);
            if (view == null) {
                view = new CameraView(on, src, dst, mode);
                cameraViews.put(id, view);
            } else {
                view.on = on;
                System.arraycopy(src, 0, view.src, 0, 4);
                System.arraycopy(dst, 0, view.dst, 0, 4);
                view.mode = mode;
            }
        }
        Log.i(TAG, "cameraLiveView: id=" + id + " on=" + on
                + " src=" + rect4(src) + " dst=" + rect4(dst) + " mode=" + mode);
        if (on) {
            return applyView(id, "cameraLiveView");
        }
        return disableView(id, "cameraLiveView");
    }

    /**
     * Clears every camera-live id. This is the teardown path when the game
     * leaves READY/PLAY/PAUSE: it sends the AIDL {@code clearAllCameraLiveOnScreen}
     * so no overlay can outlive the state that asked for it.
     */
    @UsedByGodot
    public boolean cameraLiveClear() {
        Log.i(TAG, "cameraLiveClear(): clearing all ids (supported=" + (service != null)
                + " binder=" + binder + ")");
        return clearAllViews("cameraLiveClear");
    }

    /**
     * Two normalized (0..1) rect pairs exactly as the AIDL call takes them.
     * A is the source crop, B the on-screen destination (proven on device);
     * either may be inverted. Legacy single-view method: it updates id 0.
     * Changing this while on re-sends the request. Values are not clamped.
     */
    @UsedByGodot
    public boolean cameraLiveRect(float x1, float y1, float x2, float y2,
                                  float x3, float y3, float x4, float y4) {
        float[] next = {x1, y1, x2, y2, x3, y3, x4, y4};
        if (!allFinite(next)) {
            lastCameraLiveError = "cameraLiveRect: non-finite value";
            Log.w(TAG, lastCameraLiveError);
            return false;
        }
        boolean wanted;
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(CAMERA_LIVE_ID);
            if (view == null) {
                view = new CameraView(false, CAMERA_LIVE_SRC_FULL, CAMERA_LIVE_DST_FULL,
                        CAMERA_LIVE_MODE_DEFAULT);
                cameraViews.put(CAMERA_LIVE_ID, view);
            }
            System.arraycopy(next, 0, view.src, 0, 4);
            System.arraycopy(next, 4, view.dst, 0, 4);
            wanted = view.on;
        }
        Log.i(TAG, "cameraLiveRect: " + rectString(next) + " wanted=" + wanted);
        return !wanted || applyView(CAMERA_LIVE_ID, "cameraLiveRect");
    }

    /** Opaque mode int from the AIDL call (0 in the SDK reference app). */
    @UsedByGodot
    public boolean cameraLiveMode(int mode) {
        boolean wanted;
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(CAMERA_LIVE_ID);
            if (view == null) {
                view = new CameraView(false, CAMERA_LIVE_SRC_FULL, CAMERA_LIVE_DST_FULL, mode);
                cameraViews.put(CAMERA_LIVE_ID, view);
            } else {
                view.mode = mode;
            }
            wanted = view.on;
        }
        Log.i(TAG, "cameraLiveMode: " + mode + " wanted=" + wanted);
        return !wanted || applyView(CAMERA_LIVE_ID, "cameraLiveMode");
    }

    /** True when the last camera-live call was accepted (false after a drop). */
    @UsedByGodot
    public boolean cameraLiveActive() {
        return cameraLiveApplied;
    }

    /** Number of views whose desired state is on (0..N). */
    private int cameraViewCount() {
        int count = 0;
        synchronized (cameraLock) {
            for (CameraView view : cameraViews.values()) {
                if (view.on) {
                    count++;
                }
            }
        }
        return count;
    }

    /** Re-sends every wanted view after a binder reconnect. */
    private void reapplyAllViews(String reason) {
        int[] ids;
        synchronized (cameraLock) {
            ids = new int[cameraViews.size()];
            int index = 0;
            for (Integer id : cameraViews.keySet()) {
                ids[index++] = id;
            }
        }
        Arrays.sort(ids);
        for (int id : ids) {
            applyView(id, reason);
        }
    }

    /** Sends one wanted view with its exact stored edges (idempotent). */
    private boolean applyView(int id, String reason) {
        float[] src;
        float[] dst;
        int mode;
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(id);
            if (view == null || !view.on) {
                src = null;
                dst = null;
                mode = cameraLiveMode;
            } else {
                src = view.src.clone();
                dst = view.dst.clone();
                mode = view.mode;
            }
        }
        if (src == null || dst == null) {
            return disableView(id, reason);
        }
        IGameServiceV1_0_3 bound = service;
        if (bound == null) {
            cameraLiveApplied = false;
            lastCameraLiveError = "IGameServiceV1_0_3 not bound";
            Log.w(TAG, "cameraLive view " + id + " " + reason + ": " + lastCameraLiveError
                    + " (request kept)");
            return false;
        }
        try {
            bound.setCameraLiveOnScreen(id, true,
                    src[0], src[1], src[2], src[3], dst[0], dst[1], dst[2], dst[3], mode);
            cameraLiveApplied = true;
            cameraLiveMode = mode;
            lastCameraLiveError = "";
            // The service adds its own SurfaceView with TYPE_APPLICATION_OVERLAY:
            // the preview is above this app, not behind it.
            Log.i(TAG, "cameraLive ON: id=" + id + " src=" + rect4(src) + " dst=" + rect4(dst)
                    + " mode=" + mode + " (system overlay above the app) [" + reason + "]");
            return true;
        } catch (RemoteException exception) {
            cameraLiveApplied = false;
            lastCameraLiveError = "RemoteException: " + exception.getMessage();
            Log.e(TAG, "cameraLive ON failed: id=" + id + " [" + reason + "]", exception);
            return false;
        } catch (RuntimeException | LinkageError exception) {
            cameraLiveApplied = false;
            lastCameraLiveError = exception.getClass().getSimpleName() + ": " + exception.getMessage();
            Log.e(TAG, "cameraLive ON failed: id=" + id + " [" + reason + "]", exception);
            return false;
        }
    }

    /** Turns ONE id off without touching the other views. */
    private boolean disableView(int id, String reason) {
        float[] src;
        float[] dst;
        int mode;
        synchronized (cameraLock) {
            CameraView view = cameraViews.get(id);
            if (view == null) {
                return true;
            }
            view.on = false;
            src = view.src.clone();
            dst = view.dst.clone();
            mode = view.mode;
        }
        IGameServiceV1_0_3 bound = service;
        if (bound == null) {
            cameraLiveApplied = false;
            return false;
        }
        try {
            bound.setCameraLiveOnScreen(id, false,
                    src[0], src[1], src[2], src[3], dst[0], dst[1], dst[2], dst[3], mode);
            lastCameraLiveError = "";
            Log.i(TAG, "cameraLive OFF: id=" + id
                    + " (other ids untouched) [" + reason + "]");
            return true;
        } catch (RemoteException exception) {
            lastCameraLiveError = "RemoteException: " + exception.getMessage();
            Log.w(TAG, "cameraLive OFF failed: id=" + id + " [" + reason + "]", exception);
            return false;
        } catch (RuntimeException | LinkageError exception) {
            lastCameraLiveError = exception.getClass().getSimpleName() + ": " + exception.getMessage();
            Log.w(TAG, "cameraLive OFF failed: id=" + id + " [" + reason + "]", exception);
            return false;
        }
    }

    /** Marks every view off and clears the service's whole camera-live map. */
    private boolean clearAllViews(String reason) {
        synchronized (cameraLock) {
            for (CameraView view : cameraViews.values()) {
                view.on = false;
            }
        }
        cameraLiveApplied = false;
        IGameServiceV1_0_3 bound = service;
        if (bound == null) {
            return false;
        }
        try {
            bound.clearAllCameraLiveOnScreen();
            lastCameraLiveError = "";
            Log.i(TAG, "cameraLive CLEAR ALL (every id) [" + reason + "]");
            return true;
        } catch (RemoteException exception) {
            lastCameraLiveError = "RemoteException: " + exception.getMessage();
            Log.w(TAG, "cameraLive CLEAR ALL failed [" + reason + "]", exception);
            return false;
        } catch (RuntimeException | LinkageError exception) {
            lastCameraLiveError = exception.getClass().getSimpleName() + ": " + exception.getMessage();
            Log.w(TAG, "cameraLive CLEAR ALL failed [" + reason + "]", exception);
            return false;
        }
    }

    private static boolean allFinite(float[] values) {
        for (float value : values) {
            if (Float.isNaN(value) || Float.isInfinite(value)) {
                return false;
            }
        }
        return true;
    }

    private static String rect4(float[] r) {
        return "[" + r[0] + "," + r[1] + "," + r[2] + "," + r[3] + "]";
    }

    private static String rectString(float[] r) {
        return rect4(new float[]{r[0], r[1], r[2], r[3]})
                + rect4(new float[]{r[4], r[5], r[6], r[7]});
    }

    // ------------------------------------------------------------ camera frames

    /**
     * Starts the RGBA camera-frame pump at the configured rate (default 15 fps, scale
     * 0.3) and returns true only when it is running.
     *
     * <p>This is the texture path; {@link #cameraLive(int)} is the system-overlay path
     * and they are independent. The pump calls
     * {@code IGameServiceV1_0_3.getFrameBuffer(frameTimeMs)} with the newest pose
     * timestamp, converts the {@code HardwareBuffer} to RGBA in
     * {@code libcamframe.so} and keeps exactly one newest frame. It returns false - and
     * starts no thread - without a bound V1_0_3 service, which is what makes desktop and
     * pre-bind calls a no-op.
     */
    @UsedByGodot
    public boolean cameraFramesStart() {
        return pump().start();
    }

    /** Stops the pump and drops the held frame. Safe to call when it never started. */
    @UsedByGodot
    public void cameraFramesStop() {
        pump().stop();
    }

    @UsedByGodot
    public boolean cameraFramesRunning() {
        return pump().isRunning();
    }

    /**
     * True only when frames can actually be delivered: V1_0_3 bound <em>and</em> the
     * native reader loaded. Off-device this is always false; a bound binder with a
     * missing {@code libcamframe.so} also reports false (the pump then only probes).
     */
    @UsedByGodot
    public boolean cameraFramesSupported() {
        return service != null && CameraFrameNative.isAvailable();
    }

    /** Capture rate in fps, clamped to 1..30 (default 15). */
    @UsedByGodot
    public boolean cameraFramesRate(int fps) {
        return pump().setRate(fps);
    }

    /** Downscale applied before conversion, clamped to 0.05..1.0 (default 0.3). */
    @UsedByGodot
    public boolean cameraFramesScale(float scale) {
        return pump().setScale(scale);
    }

    /** Sequence number of the newest frame (0 before the first one). */
    @UsedByGodot
    public long cameraFrameSeq() {
        return pump().seq();
    }

    @UsedByGodot
    public int cameraFrameWidth() {
        return pump().width();
    }

    @UsedByGodot
    public int cameraFrameHeight() {
        return pump().height();
    }

    /**
     * Newest frame as {@code width*height*4} RGBA8 bytes, or null. The array belongs to
     * the pump and is overwritten by the next frame, so the caller must copy it (the
     * Godot bridge does). Reading marks the frame consumed for the drop counter.
     */
    @UsedByGodot
    public byte[] cameraFrameBytes() {
        return pump().bytes();
    }

    /**
     * Base64 of the same newest frame, for Godot builds whose bridge cannot marshal
     * {@code byte[]} to {@code PackedByteArray}. Allocates; never the fast path.
     */
    @UsedByGodot
    public String cameraFrameBytesBase64() {
        return pump().base64();
    }

    /** JSON: {"running","reader","fps","scale","frames","drops","missing","errors",
     *        "seq","size":"WxH","src":"WxH","format":"0x23 Y8Cb8Cr8_420"
     *        [,"readerError"][,"probe"][,"error"]}. Stable keys, always readable. */
    @UsedByGodot
    public String cameraFrameInfoJson() {
        return pump().infoJson();
    }

    /** Lazily binds the pump to the current service and newest pose timestamp. */
    private CameraFramePump pump() {
        if (framePump == null) {
            framePump = new CameraFramePump(new CameraFramePump.Host() {
                @Override
                public IGameServiceV1_0_3 service() {
                    return service;
                }

                @Override
                public long latestFrameTimeMs() {
                    FrameInfo frame = latestFrame;
                    if (frame == null) {
                        return -1L;
                    }
                    long age = SystemClock.elapsedRealtime() - lastFrameWallMs;
                    if (lastFrameWallMs <= 0L || age > CAMERA_FRAME_STALE_MS) {
                        return -1L;
                    }
                    return frame.getFrameTimeMs();
                }
            });
        }
        return framePump;
    }

    // -------------------------------------------------------------- internals

    private boolean bindWith(Context context, String action) {
        Intent intent = new Intent(action);
        intent.setComponent(new ComponentName(SDK_PACKAGE, SDK_SERVICE));
        try {
            boolean ok = context.bindService(intent, connection, Context.BIND_AUTO_CREATE);
            if (!ok) {
                Log.w(TAG, "bindService returned false for " + action);
            }
            return ok;
        } catch (SecurityException exception) {
            lastError = "SecurityException: " + exception.getMessage();
            Log.e(TAG, "bind denied for " + action, exception);
            return false;
        } catch (RuntimeException exception) {
            lastError = exception.getClass().getSimpleName() + ": " + exception.getMessage();
            Log.e(TAG, "bind failed for " + action, exception);
            return false;
        }
    }

    private void registerCallback() throws RemoteException {
        IGameServiceV1_0_3 boundService = service;
        if (boundService != null) {
            boundService.registerFrameInfoCallback(frameCallback);
            return;
        }
        IGameServiceV1_0_2 boundLegacy = legacyService;
        if (boundLegacy != null) {
            boundLegacy.registerFrameInfoCallback(frameCallback);
        }
    }

    private boolean isConnected() {
        return service != null || legacyService != null;
    }

    private void clearConnection(String reason) {
        if (cameraLiveApplied) {
            // The service still owns the overlay window; a rebind re-sends every
            // wanted id because the CameraView map is kept.
            Log.w(TAG, "camera live dropped with the binder: " + reason
                    + " (will re-send " + cameraViewCount() + " view(s))");
        }
        cameraLiveApplied = false;
        service = null;
        legacyService = null;
        binder = BINDER_NONE;
        latestFrame = null;
        lastError = reason;
    }

    private Context contextOrNull() {
        Activity activity = getActivity();
        if (activity != null) {
            return activity.getApplicationContext();
        }
        Context context = getContext();
        return context == null ? null : context.getApplicationContext();
    }

    private void onFrame(FrameInfo frame) {
        if (frame == null) {
            return;
        }
        latestFrame = frame;
        frameCounter++;
        long now = SystemClock.elapsedRealtime();
        lastFrameWallMs = now;
        if (now - lastFrameLogMs < FRAME_LOG_INTERVAL_MS) {
            return;
        }
        lastFrameLogMs = now;
        HashMap<Integer, DetectBox> persons = frame.getPersons();
        Log.i(TAG, "frame #" + frameCounter + " t=" + frame.getFrameTimeMs()
                + " " + frame.getImageWidth() + "x" + frame.getImageHeight()
                + " persons=" + (persons == null ? 0 : persons.size())
                + " lHand=" + sizeOf(frame.getLHand())
                + " rHand=" + sizeOf(frame.getRHand())
                + " face=" + sizeOf(frame.getFace())
                + " kpts=" + firstKeypointCount(persons));
    }

    private static int sizeOf(Map<Integer, DetectBox> map) {
        return map == null ? 0 : map.size();
    }

    private static int firstKeypointCount(Map<Integer, DetectBox> map) {
        if (map == null || map.isEmpty()) {
            return 0;
        }
        for (DetectBox box : map.values()) {
            List<KeyPoint> keypoints = box.getKptList();
            if (keypoints != null && !keypoints.isEmpty()) {
                return keypoints.size();
            }
        }
        return 0;
    }

    private static void appendMap(StringBuilder builder, String name, Map<Integer, DetectBox> map) {
        builder.append(",\"").append(name).append("\":{");
        if (map != null && !map.isEmpty()) {
            int written = 0;
            for (Map.Entry<Integer, DetectBox> entry : map.entrySet()) {
                if (written >= MAX_BOXES_PER_MAP || builder.length() > MAX_FRAME_JSON_CHARS) {
                    break;
                }
                if (written > 0) {
                    builder.append(',');
                }
                builder.append('"').append(entry.getKey()).append("\":");
                appendBox(builder, entry.getValue());
                written++;
            }
        }
        builder.append('}');
    }

    private static void appendBox(StringBuilder builder, DetectBox box) {
        if (box == null) {
            builder.append("null");
            return;
        }
        builder.append("{\"score\":");
        appendNumber(builder, box.getScore(), 100f);
        RectF rect = box.getLocation();
        builder.append(",\"rect\":[");
        if (rect != null) {
            appendNumber(builder, rect.left, 100f);
            builder.append(',');
            appendNumber(builder, rect.top, 100f);
            builder.append(',');
            appendNumber(builder, rect.right, 100f);
            builder.append(',');
            appendNumber(builder, rect.bottom, 100f);
        }
        builder.append("],\"kpts\":[");
        List<KeyPoint> keypoints = box.getKptList();
        if (keypoints != null) {
            int limit = Math.min(keypoints.size(), MAX_KEYPOINTS_PER_BOX);
            for (int i = 0; i < limit; i++) {
                if (i > 0) {
                    builder.append(',');
                }
                KeyPoint keypoint = keypoints.get(i);
                builder.append('[');
                appendNumber(builder, keypoint.getX(), 1000f);
                builder.append(',');
                appendNumber(builder, keypoint.getY(), 1000f);
                builder.append(',');
                appendNumber(builder, keypoint.getZ(), 1000f);
                builder.append(',');
                appendNumber(builder, keypoint.getScore(), 100f);
                builder.append(']');
            }
        }
        builder.append("]}");
    }

    /** Appends a JSON number rounded to 1/scale, without allocating a formatter. */
    private static void appendNumber(StringBuilder builder, float value, float scale) {
        if (Float.isNaN(value) || Float.isInfinite(value)) {
            builder.append('0');
            return;
        }
        builder.append(Math.round(value * scale) / scale);
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
