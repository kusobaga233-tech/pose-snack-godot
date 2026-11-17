import subprocess, sys, os, glob, json
import numpy as np
from PIL import Image

FFMPEG = r"D:\ffmpeg-2025-09-18-git-c373636f55-essentials_build\bin\ffmpeg.exe"
VID = r"E:\azrecorder_ooutput\az_recorder_20261114_132439.mp4"
OUT = r"D:\CODEX-PROJ\yoodou\pose-snake-godot\evidence\vidframes"

os.makedirs(OUT, exist_ok=True)
for f in glob.glob(os.path.join(OUT, "*.png")):
    os.remove(f)

# sample 3 windows of 2 s each at 30 fps, grayscale, downscaled
windows = [(20, 2.0), (70, 2.0), (120, 2.0)]
results = []
for start, dur in windows:
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-ss", str(start), "-t", str(dur),
                    "-i", VID, "-vf", "fps=30,scale=640:-1", "-y",
                    os.path.join(OUT, f"w{start}_%03d.png")], check=True)
    files = sorted(glob.glob(os.path.join(OUT, f"w{start}_*.png")))
    arrs = [np.asarray(Image.open(f).convert("L"), dtype=np.float32) for f in files]
    dxs, dys = [], []
    prev = arrs[0]
    for cur in arrs[1:]:
        # phase correlation on the window interior (avoid letterbox edges)
        a = prev[60:-60, 80:-80]
        b = cur[60:-60, 80:-80]
        wa = np.outer(np.hanning(a.shape[0]), np.hanning(a.shape[1]))
        A = np.fft.rfft2((a - a.mean()) * wa)
        B = np.fft.rfft2((b - b.mean()) * wa)
        R = A * np.conj(B)
        R /= (np.abs(R) + 1e-9)
        c = np.fft.irfft2(R, s=a.shape)
        idx = np.unravel_index(np.argmax(c), c.shape)
        dy = idx[0] if idx[0] < a.shape[0] // 2 else idx[0] - a.shape[0]
        dx = idx[1] if idx[1] < a.shape[1] // 2 else idx[1] - a.shape[1]
        dxs.append(float(dx)); dys.append(float(dy))
        prev = cur
    n = len(dxs)
    mag = [abs(x) + abs(y) for x, y in zip(dxs, dys)]
    jerk = np.mean([abs(dxs[i] - dxs[i-1]) + abs(dys[i] - dys[i-1]) for i in range(1, n)]) if n > 1 else 0.0
    # sign flips = oscillation (shake), same sign runs = panning
    flips = sum(1 for i in range(1, n) if (dxs[i] > 0) != (dxs[i-1] > 0) and dxs[i] != 0 and dxs[i-1] != 0)
    results.append({
        "window_s": start,
        "frames": n,
        "mean_abs_step_px": round(float(np.mean(mag)), 2),
        "max_step_px": round(float(np.max(mag)), 2),
        "jerk_px": round(float(jerk), 2),
        "x_sign_flips_per_sec": round(flips / (n / 30.0), 2),
        "dx_range": [round(min(dxs), 1), round(max(dxs), 1)],
        "dy_range": [round(min(dys), 1), round(max(dys), 1)],
    })

print(json.dumps(results, indent=2, ensure_ascii=False))
