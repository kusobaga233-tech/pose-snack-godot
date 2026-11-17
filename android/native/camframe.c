/*
 * camframe.c - the one native piece the Godot port needs for camera frames.
 *
 * Why this file exists
 * --------------------
 * The YoudooGame SDK's Unity plugin exports CopyHardwareBufferToMemory,
 * CopyHardwareBufferToMemoryWithScale and GetHardwareBufferInfo from
 * libyoudoo_plugin.so, but those are plain C symbols with no JNI binding
 * (the library only registers Java_..._setHardwareBufferForGraphics for
 * Java). Java has no FFI, so a Godot plugin cannot call them - not even with
 * a valid long pointer. android.hardware.HardwareBuffer also has no Java API
 * to read pixels. Therefore this shim is the only way to turn the camera
 * HardwareBuffer returned by IGameServiceV1_0_3.getFrameBuffer(long) into
 * bytes. It is the same technique the vendor uses for its own non-Unity
 * consumer (sdk/Tools~/Android/SkeletonBridge/app/src/main/cpp/
 * youdoo_plugin_rpc.cpp): AHardwareBuffer_fromHardwareBuffer + lockPlanes.
 *
 * Contract (must match CameraFrameNative.readRgba in Java)
 * -------------------------------------------------------
 * jint Java_com_youdoo_godot_CameraFrameNative_readRgba(
 *     JNIEnv *, jclass, jobject hwBuffer, jint srcWidth, jint srcHeight,
 *     jint outWidth, jint outHeight, jboolean flipX, jbyteArray out)
 *
 * Writes outWidth*outHeight*4 RGBA8 bytes (row major, top-left origin,
 * alpha 0xFF) into `out`, nearest-neighbour scaled from the buffer and
 * optionally mirrored horizontally. Returns the byte count written, or -1
 * on any failure. srcWidth/srcHeight are the Java-side HardwareBuffer
 * getters and are only cross-checked against AHardwareBuffer_describe().
 *
 * Formats: AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420 (0x23, what the device
 * service returns) and AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM (0x1, direct
 * copy). Anything else is rejected with a log instead of guessed at.
 */

#include <jni.h>
#include <android/hardware_buffer.h>
#include <android/hardware_buffer_jni.h>
#include <android/log.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CAM_TAG "camframe"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, CAM_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, CAM_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, CAM_TAG, __VA_ARGS__)

#ifndef AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420
#define AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420 0x23
#endif

#define MAX_DIMENSION 8192

static inline uint8_t clamp_channel(int value) {
    if (value < 0) {
        return 0;
    }
    if (value > 255) {
        return 255;
    }
    return (uint8_t) value;
}

/* Nearest-neighbour source coordinate, including the optional mirror. */
static inline uint32_t map_coordinate(uint32_t index, uint32_t out_size, uint32_t src_size, int flip) {
    uint32_t mapped = (uint32_t) (((uint64_t) index * src_size) / out_size);
    if (mapped >= src_size) {
        mapped = src_size - 1;
    }
    if (flip) {
        mapped = src_size - 1 - mapped;
    }
    return mapped;
}

/* RGBA8 source: one plane, desc.stride is in pixels. */
static int copy_rgba8(AHardwareBuffer *buffer, const AHardwareBuffer_Desc *desc,
                      uint8_t *rgba, int out_width, int out_height, int flip) {
    void *data = NULL;
    if (AHardwareBuffer_lock(buffer, AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1, NULL, &data) != 0) {
        LOGE("RGBA8 lock failed");
        return -1;
    }
    if (data == NULL) {
        AHardwareBuffer_unlock(buffer, NULL);
        LOGE("RGBA8 lock returned no data");
        return -1;
    }
    const uint8_t *src = (const uint8_t *) data;
    for (int y = 0; y < out_height; y++) {
        const uint32_t sy = map_coordinate((uint32_t) y, (uint32_t) out_height, desc->height, 0);
        for (int x = 0; x < out_width; x++) {
            const uint32_t sx = map_coordinate((uint32_t) x, (uint32_t) out_width, desc->width, flip);
            const uint8_t *pixel = src + ((size_t) sy * desc->stride + sx) * 4;
            uint8_t *dst = rgba + ((size_t) y * out_width + x) * 4;
            dst[0] = pixel[0];
            dst[1] = pixel[1];
            dst[2] = pixel[2];
            dst[3] = 0xFF;
        }
    }
    AHardwareBuffer_unlock(buffer, NULL);
    return out_width * out_height * 4;
}

/* Y8Cb8Cr8_420 source: three planes, separate rowStride/pixelStride per plane. */
static int convert_yuv420(AHardwareBuffer *buffer, const AHardwareBuffer_Desc *desc,
                          uint8_t *rgba, int out_width, int out_height, int flip) {
    AHardwareBuffer_Planes planes;
    memset(&planes, 0, sizeof(planes));
    if (AHardwareBuffer_lockPlanes(buffer, AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN, -1, NULL, &planes) != 0) {
        LOGE("YUV420 lockPlanes failed");
        return -1;
    }
    if (planes.planeCount < 3 || planes.planes[0].data == NULL ||
        planes.planes[1].data == NULL || planes.planes[2].data == NULL) {
        AHardwareBuffer_unlock(buffer, NULL);
        LOGE("YUV420 buffer has %u plane(s)", planes.planeCount);
        return -1;
    }
    const uint8_t *y_plane = (const uint8_t *) planes.planes[0].data;
    const uint8_t *cb_plane = (const uint8_t *) planes.planes[1].data;
    const uint8_t *cr_plane = (const uint8_t *) planes.planes[2].data;

    for (int y = 0; y < out_height; y++) {
        const uint32_t sy = map_coordinate((uint32_t) y, (uint32_t) out_height, desc->height, 0);
        const uint32_t cy = sy / 2;
        for (int x = 0; x < out_width; x++) {
            const uint32_t sx = map_coordinate((uint32_t) x, (uint32_t) out_width, desc->width, flip);
            const uint32_t cx = sx / 2;

            const uint8_t yv = y_plane[(size_t) sy * planes.planes[0].rowStride +
                                       (size_t) sx * planes.planes[0].pixelStride];
            const uint8_t cb = cb_plane[(size_t) cy * planes.planes[1].rowStride +
                                        (size_t) cx * planes.planes[1].pixelStride];
            const uint8_t cr = cr_plane[(size_t) cy * planes.planes[2].rowStride +
                                        (size_t) cx * planes.planes[2].pixelStride];

            /* BT.601 limited range, integer, same constants as the SDK's own reader. */
            const int c = (int) yv - 16;
            const int d = (int) cb - 128;
            const int e = (int) cr - 128;

            uint8_t *dst = rgba + ((size_t) y * out_width + x) * 4;
            dst[0] = clamp_channel((298 * c + 409 * e + 128) >> 8);
            dst[1] = clamp_channel((298 * c - 100 * d - 208 * e + 128) >> 8);
            dst[2] = clamp_channel((298 * c + 516 * d + 128) >> 8);
            dst[3] = 0xFF;
        }
    }
    AHardwareBuffer_unlock(buffer, NULL);
    return out_width * out_height * 4;
}

JNIEXPORT jint JNICALL
Java_com_youdoo_godot_CameraFrameNative_readRgba(JNIEnv *env, jclass clazz,
                                                 jobject hardware_buffer,
                                                 jint src_width, jint src_height,
                                                 jint out_width, jint out_height,
                                                 jboolean flip_x, jbyteArray out) {
    (void) clazz;
    if (hardware_buffer == NULL || out == NULL) {
        return -1;
    }
    if (out_width <= 0 || out_height <= 0 ||
        out_width > MAX_DIMENSION || out_height > MAX_DIMENSION) {
        LOGE("bad output size %dx%d", out_width, out_height);
        return -1;
    }
    const jsize needed = (jsize) ((int64_t) out_width * (int64_t) out_height * 4);
    if ((*env)->GetArrayLength(env, out) < needed) {
        LOGE("output array too small: %d < %d", (int) (*env)->GetArrayLength(env, out), (int) needed);
        return -1;
    }

    AHardwareBuffer *buffer = AHardwareBuffer_fromHardwareBuffer(env, hardware_buffer);
    if (buffer == NULL) {
        LOGE("AHardwareBuffer_fromHardwareBuffer returned null");
        return -1;
    }

    AHardwareBuffer_Desc desc;
    memset(&desc, 0, sizeof(desc));
    AHardwareBuffer_describe(buffer, &desc);
    if (desc.width == 0 || desc.height == 0) {
        LOGE("buffer is empty");
        return -1;
    }
    if ((jint) desc.width != src_width || (jint) desc.height != src_height) {
        LOGW("size mismatch: describe=%ux%u java=%dx%d", desc.width, desc.height, src_width, src_height);
    }

    uint8_t *rgba = (uint8_t *) malloc((size_t) needed);
    if (rgba == NULL) {
        LOGE("out of memory for %d bytes", (int) needed);
        return -1;
    }

    int written = -1;
    if (desc.format == AHARDWAREBUFFER_FORMAT_Y8Cb8Cr8_420) {
        written = convert_yuv420(buffer, &desc, rgba, out_width, out_height, flip_x != JNI_FALSE);
    } else if (desc.format == AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM) {
        written = copy_rgba8(buffer, &desc, rgba, out_width, out_height, flip_x != JNI_FALSE);
    } else {
        LOGE("unsupported format 0x%x (want Y8Cb8Cr8_420 0x23 or RGBA8 0x1)", desc.format);
    }

    if (written == needed) {
        (*env)->SetByteArrayRegion(env, out, 0, needed, (const jbyte *) rgba);
    } else {
        written = -1;
    }
    free(rgba);
    return written;
}
