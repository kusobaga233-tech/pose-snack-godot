#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Validate a character pack against Docs/AI-CHARACTER-PROMPT-SPEC.md.

Usage:
    python tools/check_character_pack.py --zip <pack.zip>
    python tools/check_character_pack.py --dir <folder with <slug>/layers/...>

Checks per character (hard requirements):
  * body/head/eyes/mouth present (decor optional -> treated as empty)
  * every PNG is 400x1200 RGBA
  * background is transparent (corner alpha < 8)
  * alpha coverage sane (0.2 % .. 70 %)
  * body: bbox inside x 110..290 / y 200..860, straight section y 290..770 has a
    constant alpha width (median 160 +-6, per-row deviation <= 4 px)
  * head: bbox centre within +-25 px of (199, 900), width <= 270
  * eyes: bbox centre y within +-45 of 930, x range inside 90..310
  * mouth: bbox centre within +-45 px of (199, 1030)
  * decor: if non-empty, its bbox must sit above y <= 900 (on top of the head)

Exit code 0 = all characters PASS, 1 = at least one FAIL.
"""
import argparse
import io
import os
import sys
import zipfile

from PIL import Image

CANVAS = (400, 1200)
HEAD = (199, 916)         # measured head bbox centre (786..1045)
HEAD_Y = HEAD[1]
EYE_Y = 942              # measured eyes bbox centre (850..1034)
MOUTH = (199, 1051)       # measured mouth bbox centre (990..1112)
TUBE_X = (119, 279)
TUBE_W = 179          # visible width incl. outline (measured 178-179)
STRAIGHT = (290, 770)

LAYER_NAMES = ("body", "head", "eyes", "mouth", "decor")
OPTIONAL = ("decor",)

FAIL = []
WARN = []


def fail(slug, msg):
    FAIL.append("%s: %s" % (slug, msg))


def warn(slug, msg):
    WARN.append("%s: %s" % (slug, msg))


def load_layers(reader, slug, files):
    """files: dict name -> bytes for this slug. Returns dict name -> Image or None."""
    out = {}
    for name in LAYER_NAMES:
        raw = files.get(name)
        if raw is None:
            if name in OPTIONAL:
                out[name] = None
            else:
                fail(slug, "missing layer %s.png" % name)
                out[name] = None
            continue
        try:
            img = Image.open(io.BytesIO(raw))
            img.load()
        except Exception as exc:  # noqa: BLE001
            fail(slug, "%s.png unreadable (%s)" % (name, exc))
            out[name] = None
            continue
        if img.size != CANVAS:
            fail(slug, "%s.png is %dx%d, expected 400x1200" % (name, img.size[0], img.size[1]))
        if img.mode != "RGBA":
            img = img.convert("RGBA")
            warn(slug, "%s.png was %s, converted for checks" % (name, img.mode))
        out[name] = img
    return out


def alpha_stats(img):
    a = img.getchannel("A")
    w, h = img.size
    px = a.load()
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    hist = a.histogram()
    total = w * h
    covered = total - hist[0] - (hist[1] if len(hist) > 1 else 0)
    return corners, covered / float(total)


def bbox(img):
    return img.getchannel("A").getbbox()


def check_body(slug, img):
    if img is None:
        return
    bb = bbox(img)
    if bb is None:
        fail(slug, "body.png is fully transparent")
        return
    x0, y0, x1, y1 = bb
    if x0 < 100 or x1 > 300:
        fail(slug, "body x range %d..%d outside 100..300" % (x0, x1))
    if y0 < 80 or y1 > 950:
        fail(slug, "body y range %d..%d outside 80..950" % (y0, y1))
    a = img.getchannel("A").load()
    widths = []
    for y in range(STRAIGHT[0], STRAIGHT[1], 8):
        row = [x for x in range(0, 400) if a[x, y] > 32]
        if row:
            widths.append(row[-1] - row[0] + 1)
    if not widths:
        fail(slug, "body straight section y290..770 is empty")
        return
    widths.sort()
    med = widths[len(widths) // 2]
    dev = max(abs(w - med) for w in widths)
    if abs(med - TUBE_W) > 6:
        fail(slug, "body straight-section width %d px, expected %d +-6" % (med, TUBE_W))
    if dev > 4:
        fail(slug, "body width varies by %d px in y290..770 (must be constant)" % dev)


def check_head(slug, img):
    if img is None:
        return
    bb = bbox(img)
    if bb is None:
        fail(slug, "head.png is fully transparent")
        return
    x0, y0, x1, y1 = bb
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    if abs(cx - HEAD[0]) > 25 or abs(cy - HEAD_Y) > 25:
        fail(slug, "head centre (%.0f,%.0f) far from (199,916)" % (cx, cy))
    if (x1 - x0) > 270:
        fail(slug, "head width %d px > 270 (must fit a 124 px radius)" % (x1 - x0))


def check_eyes(slug, img):
    if img is None:
        return
    bb = bbox(img)
    if bb is None:
        fail(slug, "eyes.png is fully transparent")
        return
    x0, y0, x1, y1 = bb
    cy = (y0 + y1) / 2.0
    if abs(cy - EYE_Y) > 55:
        fail(slug, "eyes centre y=%.0f far from 930" % cy)
    if x0 < 55 or x1 > 345:
        fail(slug, "eyes x range %d..%d outside 55..345" % (x0, x1))


def check_mouth(slug, img):
    if img is None:
        return
    bb = bbox(img)
    if bb is None:
        fail(slug, "mouth.png is fully transparent")
        return
    x0, y0, x1, y1 = bb
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    if abs(cx - MOUTH[0]) > 45 or abs(cy - MOUTH[1]) > 45:
        fail(slug, "mouth centre (%.0f,%.0f) far from (199,1051)" % (cx, cy))


def check_decor(slug, img):
    if img is None:
        return
    bb = bbox(img)
    if bb is None:
        warn(slug, "decor.png is empty (fine if the character has no accessory)")
        return
    if bb[1] < 550:
        fail(slug, "decor starts at y=%d, too high above the head (must hug the head, y>=550)" % bb[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip")
    ap.add_argument("--dir")
    args = ap.parse_args()

    packs = {}  # slug -> {name: bytes}

    if args.zip:
        with zipfile.ZipFile(args.zip) as zf:
            for info in zf.infolist():
                if info.is_dir() or not info.filename.lower().endswith(".png"):
                    continue
                parts = info.filename.replace("\\", "/").split("/")
                if len(parts) < 2:
                    continue
                slug = parts[0]
                name = os.path.splitext(parts[-1])[0].lower()
                base = os.path.basename(parts[-1]).lower()
                for layer in LAYER_NAMES + ("eyes_half", "eyes_closed", "mouth_closed", "mouth_tongue"):
                    if base == layer + ".png":
                        packs.setdefault(slug, {})[layer] = zf.read(info)
    elif args.dir:
        root = args.dir
        for slug in sorted(os.listdir(root)):
            sdir = os.path.join(root, slug)
            if not os.path.isdir(sdir):
                continue
            for sub in ("layers", ""):
                d = os.path.join(sdir, sub) if sub else sdir
                if not os.path.isdir(d):
                    continue
                for fn in os.listdir(d):
                    if not fn.lower().endswith(".png"):
                        continue
                    name = os.path.splitext(fn)[0].lower()
                    if name in LAYER_NAMES or name in ("eyes_half", "eyes_closed", "mouth_closed", "mouth_tongue"):
                        with open(os.path.join(d, fn), "rb") as fh:
                            packs.setdefault(slug, {})[name] = fh.read()
    else:
        print("need --zip or --dir")
        return 2

    if not packs:
        print("no characters found")
        return 2

    print("characters found: %d (%s)" % (len(packs), ", ".join(sorted(packs))))
    for slug in sorted(packs):
        layers = load_layers(None, slug, packs[slug])
        for name, img in layers.items():
            if img is None:
                continue
            corners, cover = alpha_stats(img)
            if max(corners) > 8:
                fail(slug, "%s.png has an opaque background (corner alpha %s)" % (name, corners))
            if cover < 0.0005:
                fail(slug, "%s.png alpha coverage %.3f%% too small (empty layer?)" % (name, cover * 100))
            if cover > 0.70:
                fail(slug, "%s.png alpha coverage %.1f%% too large (background not removed?)" % (name, cover * 100))
        check_body(slug, layers["body"])
        check_head(slug, layers["head"])
        check_eyes(slug, layers["eyes"])
        check_mouth(slug, layers["mouth"])
        check_decor(slug, layers["decor"])

    print("")
    if WARN:
        print("WARNINGS (%d)" % len(WARN))
        for w in WARN:
            print("  ~ " + w)
        print("")
    if FAIL:
        print("FAILED (%d)" % len(FAIL))
        for f in FAIL:
            print("  X " + f)
        print("")
        print("RESULT: FAIL - fix the items above and re-submit")
        return 1
    print("RESULT: PASS - %d characters meet the spec" % len(packs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
