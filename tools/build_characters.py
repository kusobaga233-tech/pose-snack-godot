#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Build the runtime character-skin assets from one or more owner packs.

Sources: D:\\CLAUDE-PROJ\\snake-characters\\modular_front.zip  (the base ten,
         400x1200 layered art under <slug>/layers/)
         D:\\CLAUDE-PROJ\\snake-characters\\godot_pack\\C1_panda.zip  (add-on;
         400x1200 art under <slug>/ plus a <slug>/skin.json)
Outputs: assets/characters/<slug>/atlas.png   per-character head atlas
         assets/characters/<slug>/body.png    tube texture (tiled along the body)
         assets/characters/README.md          folder list + how to rebuild
         src/present/ps_skin_data.gd          the generated skin table

Packs are **merged by slug**: pass `--zip` more than once (or `--pack` for the
base pack(s) plus `--extra` for add-ons) and the later pack wins for a slug it
repeats.  A pack may ship the legacy `<slug>/layers/<layer>.png` layout or the
flat `<slug>/<layer>.png` layout (or both; `layers/` wins).  When a pack ships a
`<slug>/skin.json` its `name`/`full`/`rim`/`halo`/`dot`/`tint` are used for the
table entry; without it the colours are sampled from the body art exactly as
before, and the name comes from the CHARACTERS table.

Expression variants are taken from the pack when it ships them
(`eyes_half.png`, `eyes_closed.png`, `mouth_closed.png`, `mouth_tongue.png`);
the ones it does not ship are derived from the shipped open eyes/mouth art.
Re-running on the old pack alone reproduces the ten existing characters byte
for byte (the build is deterministic; no timestamps or set iteration order
reach the output).

Why an atlas per character: the runtime must draw a whole head (head base +
decor + one eye variant + one mouth variant) in ONE `canvas_item_add_triangle_array`,
so expression variants are a UV-rect swap and cost no extra draw call.

Regions packed per character (all cropped to their alpha bbox):
    head            head.png
    decor           decor.png                   (drawn last, over eyes/mouth)
    eyes_open       eyes.png
    eyes_half       pack art, else derived: the open art + a lid over the top half
    eyes_closed     pack art, else derived: a lid crescent only
    mouth_open      mouth.png                   (the shipped expression)
    mouth_closed    pack art, else derived: the shipped art squashed to its lip
    mouth_tongue    pack art, else mouth_open (+ a drawn forked tongue when the
                    art does not already carry one)
Every region records `[x, y, w, h, ox, oy]` in atlas texels, where (ox, oy) is
the region's top-left offset from the shared head anchor (199, 900) of the pack
canvas, also in atlas texels (source px * ATLAS_K).

Body: crop of the straight tube section, x 119..279 (the 160 px tube) and
y 290..770 (the 480 px usable straight run between the round tail cap and the
neck), resampled to 128x384.  v runs along the tube, u across it.

Usage:  python tools/build_characters.py [--zip PATH ...] [--project PATH]
        python tools/build_characters.py --pack BASE.zip --extra PANDA.zip
        python tools/build_characters.py --zip BASE.zip        # the ten only
"""
import argparse
import io
import json
import math
import os
import re
import sys
import zipfile

from PIL import Image, ImageDraw

# ---------------------------------------------------------------- pack geometry
CANVAS = (400, 1200)
HEAD_ANCHOR = (199, 900)
EYE_L = (150, 930)
EYE_R = (248, 930)
MOUTH = (199, 1030)
NECK = (199, 850)
TAIL = (199, 210)
TUBE = (119, 210, 279, 850)          # nominal 160 x 640 tube
TUBE_STRAIGHT = (119, 290, 279, 770)  # constant-width run between the two caps
BODY_TEX = (128, 384)                 # 0.8x of 160x480

ATLAS_K = 0.5        # source px -> atlas texel (head is drawn at 76..123 px)
ATLAS_PAD = 8
ATLAS_MAX_W = 400
HEAD_HALF_W = (323 - 74) / 2.0        # 124.5 source px, anchor x 199 -> head edge

LAYERS = ("body", "head", "eyes", "mouth", "decor")
## Optional expression art a pack may ship instead of the derived variants.
VARIANT_NAMES = ("eyes_half", "eyes_closed", "mouth_closed", "mouth_tongue")

# slug, Chinese short name (the row label), full pack name.
#
# The first ten are the original pack and are required in every run; the extras
# are optional (built only when a pack on the command line carries them).  The
# generated table has one entry per character actually built, in this order
# followed by any slug found only in an add-on pack (alphabetical).
BASE_CHARACTERS = [
    ("A1_spicy", "辣椒蛇", "辣到喷火 · 辣椒蛇"),
    ("A2_shy", "帽衫蛇", "社恐隐身 · 帽衫蛇"),
    ("A3_gym", "蛋白蛇", "健身狂魔 · 蛋白蛇"),
    ("A4_drama", "抓马蛇", "戏精影帝 · 抓马蛇"),
    ("A5_lazy", "摆烂蛇", "躺平咸鱼 · 摆烂蛇"),
    ("B1_boba", "珍珠蛇", "奶茶续命 · 珍珠蛇"),
    ("B2_selfie", "滤镜蛇", "自拍网红 · 滤镜蛇"),
    ("B3_miser", "金币蛇", "守财奴 · 金币蛇"),
    ("B4_gamer", "手柄蛇", "游戏宅 · 手柄蛇"),
    ("B5_diva", "下午茶蛇", "优雅贵妇 · 下午茶蛇"),
]

OPTIONAL_CHARACTERS = [
    ("C1_panda", "熬夜熊猫", "熬夜冠军 · 熊猫蛇"),
]

CHARACTERS = BASE_CHARACTERS + OPTIONAL_CHARACTERS

## Default packs: the base ten + the C1 add-on.  `--zip` / `--pack` / `--extra`
## replace this list; `--zip <base only>` rebuilds exactly the old ten.
DEFAULT_PACKS = [
    r"D:\CLAUDE-PROJ\snake-characters\modular_front.zip",
    r"D:\CLAUDE-PROJ\snake-characters\godot_pack\C1_panda.zip",
]
HEX_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")


# ------------------------------------------------------------------- helpers
def scan_pack(zf):
    """Group one zip's members by slug.

    Returns {slug: {"slug", "zip", "members": {stem: member_path}, "skin"}}.
    `members` maps a lower-case layer stem (`head`, `eyes_half`, ...) to the
    member path, preferring `<slug>/layers/<name>.png` over a flat
    `<slug>/<name>.png` when a pack ships both.  A `<slug>/skin.json` is parsed
    into `skin` (None when absent).
    """
    packs = {}
    for info in zf.infolist():
        if info.is_dir():
            continue
        name = info.filename.replace("\\", "/")
        parts = name.split("/")
        if len(parts) < 2:
            continue
        slug = parts[0]
        base = parts[-1]
        stem, ext = os.path.splitext(base)
        if ext.lower() == ".png":
            e = packs.setdefault(slug, {"members": {}})
            key = stem.lower()
            if key not in e["members"] or parts[1:-1] == ["layers"]:
                e["members"][key] = name
        elif base.lower() == "skin.json":
            e = packs.setdefault(slug, {"members": {}})
            e["skin_member"] = name
    for slug, e in packs.items():
        e["slug"] = slug
        e["zip"] = zf
        if "skin_member" in e:
            raw = zf.read(e["skin_member"]).decode("utf-8-sig")
            try:
                e["skin"] = json.loads(raw)
            except ValueError as exc:
                raise SystemExit("%s/skin.json: %s" % (slug, exc))
        else:
            e["skin"] = None
    return packs


def load_layer(pack, name):
    slug = pack["slug"]
    member = pack["members"].get(name)
    if member is None:
        raise SystemExit("%s: missing %s.png in %s" % (
            slug, name, os.path.basename(pack.get("zip_name", "pack"))))
    with pack["zip"].open(member) as f:
        im = Image.open(io.BytesIO(f.read()))
    im = im.convert("RGBA")
    if im.size != CANVAS:
        raise SystemExit("%s/%s: unexpected canvas %s" % (slug, name, im.size))
    return im


def alpha_bbox(im):
    bb = im.getchannel("A").getbbox()
    if bb is None:
        raise SystemExit("empty layer")
    return bb


def crop_rgba(im, rect):
    rect = [int(round(v)) for v in rect]
    x0, y0, x1, y1 = rect
    if x1 <= x0 or y1 <= y0:
        raise SystemExit("empty crop %s" % (rect,))
    return im.crop((x0, y0, x1, y1))


def mean_rgb(im, alpha_min=200, box=None):
    src = im if box is None else im.crop(box)
    px = src.load()
    r = g = b = 0.0
    n = 0
    for y in range(src.height):
        for x in range(src.width):
            p = px[x, y]
            if p[3] >= alpha_min:
                r += p[0]
                g += p[1]
                b += p[2]
                n += 1
    if n == 0:
        return (255, 255, 255)
    return (r / n, g / n, b / n)


def hexcol(rgb, mul=1.0):
    return "#%02X%02X%02X" % tuple(
        max(0, min(255, int(round(c * mul)))) for c in rgb)


def blend(a, b, k):
    return tuple(a[i] * (1.0 - k) + b[i] * k for i in range(3))


def eye_boxes(eyes):
    """Split the eyes layer into a left/right box around the shared anchors."""
    bb = alpha_bbox(eyes)
    a = eyes.getchannel("A").load()
    # column runs, so a character with wide brows still splits at the face axis
    runs = []
    inside = False
    start = 0
    for x in range(eyes.width):
        used = any(a[x, y] > 8 for y in range(bb[1], bb[3], 3))
        if used and not inside:
            start = x
            inside = True
        elif not used and inside:
            runs.append((start, x))
            inside = False
    if inside:
        runs.append((start, eyes.width))
    if len(runs) < 2:
        runs = [(bb[0], 199), (199, bb[2])]
    left = (runs[0][0], 199)
    right = (199, runs[-1][1])
    out = []
    for center, (x0, x1) in ((EYE_L, left), (EYE_R, right)):
        r = max(24, int(round((x1 - x0) / 2)))
        out.append((center[0] - r, center[1] - r, center[0] + r, center[1] + r))
    return out


def sample_lid_colour(eyes, box):
    """The lid colour: the dominant chromatic colour in the eye box's top band.

    The lid is the most *saturated* thing above the eyeball (the sclera is white
    and the lash/outline is near black, both ~0 saturation), so bucketing the
    top 42 % of the box by quantised RGB and taking the most frequent chromatic
    bucket survives highlights, antialiasing and a brow in the same band.
    """
    x0, y0, x1, y1 = box
    band = eyes.crop((x0, y0, x1, y0 + max(8, int((y1 - y0) * 0.42))))
    px = band.load()
    for min_sat in (18, 0):
        buckets = {}
        for y in range(band.height):
            for x in range(band.width):
                p = px[x, y]
                if p[3] < 200:
                    continue
                lum = 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
                sat = max(p[0], p[1], p[2]) - min(p[0], p[1], p[2])
                if lum > 238 or lum < 40 or sat < min_sat:
                    continue
                key = (p[0] // 12, p[1] // 12, p[2] // 12)
                acc = buckets.setdefault(key, [0, 0.0, 0.0, 0.0])
                acc[0] += 1
                acc[1] += p[0]
                acc[2] += p[1]
                acc[3] += p[2]
        if buckets:
            best = max(buckets.values(), key=lambda a: a[0])
            n = float(best[0])
            return (best[1] / n, best[2] / n, best[3] / n)
    return (205, 205, 205)


def ink_colour(eyes, box):
    crop = eyes.crop(box)
    px = crop.load()
    best = 999
    col = (20, 20, 28)
    for y in range(crop.height):
        for x in range(crop.width):
            p = px[x, y]
            if p[3] < 220:
                continue
            lum = 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
            if lum < best:
                best = lum
                col = (p[0], p[1], p[2])
    return col


def draw_lid(eyes, boxes, cover, thick, tint):
    """Copy of `eyes` with a lid over the top `cover` of each eye box.

    The lid is the sampled lid colour with the sampled ink outline on its lower
    edge, so it reads as the character's own eyelid rather than a grey bar.
    """
    out = eyes.copy()
    d = ImageDraw.Draw(out)
    for box in boxes:
        x0, y0, x1, y1 = box
        w = x1 - x0
        h = y1 - y0
        lid = blend(sample_lid_colour(eyes, box), tint, 0.30)
        ink = ink_colour(eyes, box)
        hgt = int(round(h * cover))
        # an ellipse wider than tall, so the lid's lower edge is a shallow curve
        d.ellipse([x0 - 2, y0 - int(h * 0.22), x1 + 2, y0 + hgt],
                  fill=(int(lid[0]), int(lid[1]), int(lid[2]), 255))
        d.arc([x0 - 2, y0 - int(h * 0.22), x1 + 2, y0 + hgt], 18, 162,
              fill=(int(ink[0]), int(ink[1]), int(ink[2]), 255), width=thick)
    return out


def draw_closed(eyes, boxes, squash, tint):
    """A closed eye: a lid crescent on the eye anchor, lash line underneath."""
    out = Image.new("RGBA", eyes.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    for box in boxes:
        x0, y0, x1, y1 = box
        cx = (x0 + x1) // 2
        cy = (y0 + y1) // 2
        r = (x1 - x0) // 2
        lid = blend(sample_lid_colour(eyes, box), tint, 0.30)
        ink = ink_colour(eyes, box)
        w = int(r * 0.92)
        h = max(7, int(r * squash))
        d.ellipse([cx - w, cy - h, cx + w, cy + h],
                  fill=(int(lid[0]), int(lid[1]), int(lid[2]), 255))
        d.arc([cx - w, cy - h, cx + w, cy + h], 12, 168,
              fill=(int(ink[0]), int(ink[1]), int(ink[2]), 255), width=4)
    return out


def draw_tongue(mouth, colour):
    """Forked tongue below the mouth anchor, for a flat-mouthed character."""
    out = mouth.copy()
    d = ImageDraw.Draw(out)
    mx, my = MOUTH
    top = my + 6
    pink = (int(colour[0]), int(colour[1]), int(colour[2]), 255)
    d.rectangle([mx - 5, top, mx + 5, top + 46], fill=pink)
    d.line([mx, top + 44, mx - 13, top + 62], fill=pink, width=7)
    d.line([mx, top + 44, mx + 13, top + 62], fill=pink, width=7)
    d.rectangle([mx - 2, top + 46, mx + 2, top + 54], fill=pink)
    return out


def squash_v(im, box, anchor_top, factor):
    """Scale `im`'s crop vertically by `factor`, keeping `anchor_top` fixed."""
    x0, y0, x1, y1 = box
    h = max(1, int(round((y1 - y0) * factor)))
    small = im.crop(box).resize((x1 - x0, h), Image.LANCZOS)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(small, (x0, anchor_top))
    return out


def pack(regions, max_w):
    """Shelf-pack [(key, image)] into an atlas, biggest first."""
    items = sorted(regions, key=lambda kv: -kv[1].height)
    x = y = ATLAS_PAD
    row_h = 0
    placed = []
    used_w = 0
    for key, img in items:
        w = img.width + ATLAS_PAD
        if x + w > max_w:
            x = ATLAS_PAD
            y += row_h
            row_h = 0
        placed.append((key, img, x, y))
        used_w = max(used_w, x + w)
        x += w
        row_h = max(row_h, img.height + ATLAS_PAD)
    w = int(math.ceil((used_w + ATLAS_PAD) / 4.0) * 4)
    h = int(math.ceil((y + row_h + ATLAS_PAD) / 4.0) * 4)
    return placed, w, h


# --------------------------------------------------------------- build one skin
def skin_hex(skin, key, fallback, slug):
    """`skin.json`'s `#RRGGBB` colour for `key`, else `fallback`."""
    value = skin.get(key) if skin else None
    if value is None:
        return fallback
    text = str(value).strip()
    if not HEX_RE.match(text):
        raise SystemExit("%s/skin.json: %s=%r is not #RRGGBB" % (slug, key, value))
    return text.upper()


def build_one(entry, atlas_dir, fallback_name, fallback_full):
    """Build one character from its merged pack entry.

    Layers may be flat (`<slug>/head.png`) or legacy (`<slug>/layers/head.png`);
    a pack-supplied expression variant replaces the derived one.
    """
    slug = entry["slug"]
    layers = {n: load_layer(entry, n) for n in LAYERS if n in entry["members"]}
    for req in ("body", "head", "eyes", "mouth"):
        if req not in layers:
            raise SystemExit("%s: missing %s.png" % (slug, req))
    if "decor" not in layers:
        # decor is optional in the pack spec: no accessory, empty layer
        layers["decor"] = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    body = layers["body"]
    eyes = layers["eyes"]
    mouth = layers["mouth"]
    supplied = {k: load_layer(entry, k) for k in VARIANT_NAMES if k in entry["members"]}
    skin = entry.get("skin") or {}

    boxes = eye_boxes(eyes)
    tint = mean_rgb(body, 200, (TUBE[0], 700, TUBE[2], 770))
    half = supplied.get("eyes_half")
    if half is None:
        half = draw_lid(eyes, boxes, 0.46, 4, tint)
    closed = supplied.get("eyes_closed")
    if closed is None:
        closed = draw_closed(eyes, boxes, 0.30, tint)

    mbb = alpha_bbox(mouth)
    m_ext = mbb[3] - MOUTH[1]
    tongue = supplied.get("mouth_tongue")
    if tongue is None:
        tongue = mouth
        if m_ext < 46:
            # no tongue in the shipped art: draw one in the character's own pink
            tongue = draw_tongue(mouth, (245, 90, 140))
    closed_mouth = supplied.get("mouth_closed")
    if closed_mouth is None:
        closed_mouth = squash_v(mouth, mbb, mbb[1], 0.32)

    raw = [
        ("head", layers["head"]),
        ("decor", layers["decor"]),
        ("eyes_open", eyes),
        ("eyes_half", half),
        ("eyes_closed", closed),
        ("mouth_open", mouth),
        ("mouth_closed", closed_mouth),
        ("mouth_tongue", tongue),
    ]

    regions = {}
    packed_src = []
    for key, img in raw:
        bb = alpha_bbox(img)
        crop = crop_rgba(img, bb)
        crop = crop.resize((max(1, int(round(crop.width * ATLAS_K))),
                            max(1, int(round(crop.height * ATLAS_K)))),
                           Image.LANCZOS)
        packed_src.append((key, crop))
        regions[key] = [bb[0], bb[1], bb[2], bb[3]]

    placed, aw, ah = pack(packed_src, ATLAS_MAX_W)
    atlas = Image.new("RGBA", (aw, ah), (0, 0, 0, 0))
    for key, img, x, y in placed:
        atlas.alpha_composite(img, (x, y))
        sx0, sy0, _, _ = regions[key]
        regions[key] = [x, y, img.width, img.height,
                        int(round((sx0 - HEAD_ANCHOR[0]) * ATLAS_K)),
                        int(round((sy0 - HEAD_ANCHOR[1]) * ATLAS_K))]

    # ---- body tube texture --------------------------------------------------
    bx0, by0, bx1, by1 = TUBE_STRAIGHT
    body_tex = body.crop((bx0, by0, bx1, by1)).resize(BODY_TEX, Image.LANCZOS)

    # ---- palette ------------------------------------------------------------
    mid = mean_rgb(body, 200, (bx0, 470, bx1, 610))
    head_c = mean_rgb(body, 200, (bx0, 700, bx1, 770))
    tail_c = mean_rgb(body, 200, (bx0, 290, bx1, 350))
    rim = tuple(c * 0.30 for c in head_c)
    halo = tuple(min(255.0, c * 1.06) for c in mid)
    dot = tuple(min(255.0, c * 1.12 + 18) for c in mid)
    palette = {
        "body_mid": hexcol(mid),
        "body_head": hexcol(head_c),
        "body_tail": hexcol(tail_c),
        "rim": skin_hex(skin, "rim", hexcol(rim), slug),
        "halo": skin_hex(skin, "halo", hexcol(halo), slug),
        "dot": skin_hex(skin, "dot", hexcol(dot), slug),
        "head_lid": hexcol(sample_lid_colour(eyes, boxes[0])),
    }
    tint_hex = skin_hex(skin, "tint", palette["halo"], slug)
    name = str(skin.get("name") or fallback_name)
    full = str(skin.get("full") or fallback_full)

    os.makedirs(atlas_dir, exist_ok=True)
    atlas.save(os.path.join(atlas_dir, "atlas.png"), optimize=True)
    body_tex.save(os.path.join(atlas_dir, "body.png"), optimize=True)
    return {
        "slug": slug,
        "name": name,
        "full": full,
        "atlas": (aw, ah),
        "body": BODY_TEX,
        "regions": regions,
        "palette": palette,
        "tint": tint_hex,
        "mouth_ext": m_ext,
        "variants": [k for k in VARIANT_NAMES if k in supplied],
    }


# ------------------------------------------------------------------- emit table
HEADER = '''extends RefCounted
## GENERATED by `tools/build_characters.py` from the owner's character pack
## (%s).  Do not hand-edit the numbers: re-run the script.
##
## Geometry (pack canvas 400x1200, shared by all %s characters):
##   canvas 400x1200, head at the bottom facing +Y, body above, layers
##   body -> head -> eyes -> mouth -> decor with no offsets.
##   neck (199,850) · head (199,900) · eyes (150,930)/(248,930) ·
##   mouth (199,1030) · decor (199,824) · tail (199,210)
##   body length 640, thickness 160; usable straight section y 290..770.
##
## `regions[key] = [x, y, w, h, ox, oy]`: the atlas texel rect and its top-left
## offset from the head anchor (199,900) in atlas texels (source px * K).
## Draw order per head: head -> eyes(variant) -> mouth(variant) -> decor.
##
## `body_tex`: 128x384 crop of the straight tube (x 119..279, y 290..770),
## u across the tube, v along it (v=0 is the tail end, v=1 the neck end).
'''

ATLAS_K_DECL = "const ATLAS_K := %.4f\n" % ATLAS_K
HEAD_HALF = "const HEAD_HALF_W := %.2f\n" % HEAD_HALF_W
HEAD_MUL = "const HEAD_W_MUL := 1.06\n"

_NUM_WORDS = {0: "zero", 1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
              6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
              11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen",
              15: "fifteen", 16: "sixteen"}


def num_word(n):
    return _NUM_WORDS.get(n, str(n))


def emit_gd(out_path, built, packs):
    pack_desc = " + ".join("`%s`" % os.path.basename(p) for p in packs)
    lines = [HEADER % (pack_desc, num_word(len(built))),
             ATLAS_K_DECL, HEAD_HALF, HEAD_MUL,
             '## pack canvas / anchor constants, for the docs and the tools\n',
             'const CANVAS := Vector2(400, 1200)\n',
             'const ANCHOR_HEAD := Vector2(199, 900)\n',
             'const ANCHOR_NECK := Vector2(199, 850)\n',
             'const ANCHOR_MOUTH := Vector2(199, 1030)\n',
             'const ANCHOR_TAIL := Vector2(199, 210)\n\n',
             'const LIST := [\n']
    for info in built:
        slug = info["slug"]
        r = info["regions"]
        p = info["palette"]
        lines.append('\t{\n')
        lines.append('\t\t"slug": "%s",\n' % slug)
        lines.append('\t\t"name": "%s",\n' % info["name"])
        lines.append('\t\t"full": "%s",\n' % info["full"])
        lines.append('\t\t"atlas": "res://assets/characters/%s/atlas.png",\n' % slug)
        lines.append('\t\t"body": "res://assets/characters/%s/body.png",\n' % slug)
        lines.append('\t\t"atlas_size": Vector2i(%d, %d),\n' % info["atlas"])
        lines.append('\t\t"rim": Color("%s"),\n' % p["rim"])
        lines.append('\t\t"halo": Color("%s"),\n' % p["halo"])
        lines.append('\t\t"dot": Color("%s"),\n' % p["dot"])
        lines.append('\t\t"tint": Color("%s"),\n' % info["tint"])
        lines.append('\t\t"regions": {\n')
        for key in ("head", "decor", "eyes_open", "eyes_half", "eyes_closed",
                    "mouth_open", "mouth_closed", "mouth_tongue"):
            v = r[key]
            lines.append('\t\t\t"%s": [%d, %d, %d, %d, %d, %d],\n'
                         % (key, v[0], v[1], v[2], v[3], v[4], v[5]))
        lines.append('\t\t},\n\t},\n')
    lines.append(']\n')
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(lines))


README = """# assets/characters — 角色皮肤 (character skins)

Generated by `tools/build_characters.py` from the owner's pack
%s (400x1200 layered art).

**Folder names are the pack's own slugs and must stay stable** — the skin table
(`src/present/ps_skin_data.gd`) and `PSData.LIST` reference them by path:

| folder | 角色 |
|---|---|
%s

Each folder holds exactly two files:

| file | size | contents |
|---|---|---|
| `atlas.png` | see the table below | per-character head atlas: `head`, `decor`, `eyes_open/half/closed`, `mouth_open/closed/tongue` |
| `body.png` | 128x384 | the straight tube section (pack x 119..279, y 290..770), u across the body, v along it |

`atlas.png` is NPOT and shelf-packed; every region is cropped to its alpha bbox
and its rect is recorded in the table together with the offset from the shared
head anchor `(199, 900)`. At runtime one head is four textured quads
(`head -> eyes -> mouth -> decor`) in **one** `canvas_item_add_triangle_array`,
so an expression change is a UV-rect swap and costs no draw call.

Rebuild after changing the pack:

```
python tools/build_characters.py
```

then re-import in Godot (`godot --headless --path . --import`). The script
writes the two PNGs per character, this README's table and the whole skin table;
nothing else in the project needs editing.
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", action="append", metavar="PATH",
                    help="character pack zip; repeat to merge packs (later pack "
                         "wins for a slug it repeats)")
    ap.add_argument("--pack", action="append", metavar="PATH",
                    help="base pack zip (repeatable); combined with --extra")
    ap.add_argument("--extra", action="append", metavar="PATH",
                    help="add-on pack zip (repeatable); merged after the base packs")
    ap.add_argument("--project", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    args = ap.parse_args()

    if args.pack or args.zip or args.extra:
        packs = list(args.pack or []) + list(args.zip or []) + list(args.extra or [])
    else:
        packs = list(DEFAULT_PACKS)
    pack_paths = []
    seen = set()
    for p in packs:
        a = os.path.abspath(p)
        if a not in seen:
            seen.add(a)
            pack_paths.append(a)
    root = args.project

    table = {s: (n, f) for s, n, f in CHARACTERS}
    zips = []
    merged = {}
    try:
        for p in pack_paths:
            if not os.path.isfile(p):
                raise SystemExit("pack not found: %s" % p)
            zf = zipfile.ZipFile(p)
            zips.append(zf)
            for slug, pack in scan_pack(zf).items():
                pack["zip_name"] = p
                if slug in merged:
                    print("merge: %-10s %s overrides %s" % (
                        slug, os.path.basename(p),
                        os.path.basename(merged[slug]["zip_name"])))
                merged[slug] = pack
        print("packs: %s -> %d character(s)" % (
            " + ".join(os.path.basename(p) for p in pack_paths), len(merged)))

        # table order: the base ten, then the optional extras, then any slug
        # only an add-on pack carries (alphabetical, so a re-run is stable)
        slugs = []
        missing = [s for s, _n, _f in BASE_CHARACTERS if s not in merged]
        if missing:
            raise SystemExit("missing from every pack: %s" % ", ".join(missing))
        slugs.extend(s for s, _n, _f in BASE_CHARACTERS)
        slugs.extend(s for s, _n, _f in OPTIONAL_CHARACTERS if s in merged)
        slugs.extend(sorted(s for s in merged if s not in table))

        built = []
        rows = []
        total = 0
        for slug in slugs:
            name, full = table.get(slug, (slug, slug))
            d = os.path.join(root, "assets", "characters", slug)
            info = build_one(merged[slug], d, name, full)
            size = os.path.getsize(os.path.join(d, "atlas.png")) + \
                os.path.getsize(os.path.join(d, "body.png"))
            total += size
            built.append(info)
            rows.append("| `%s` | %s | %dx%d | %d KB |" % (
                slug, info["name"], info["atlas"][0], info["atlas"][1],
                int(round(size / 1024.0))))
            variants = ",".join(info["variants"]) if info["variants"] else "derived"
            print("%-10s atlas=%dx%d body=%dx%d regions=%d mouth_ext=%d "
                  "variants=%s  %d KB"
                  % (slug, info["atlas"][0], info["atlas"][1], BODY_TEX[0],
                     BODY_TEX[1], len(info["regions"]), info["mouth_ext"],
                     variants, int(round(size / 1024.0))))

        emit_gd(os.path.join(root, "src", "present", "ps_skin_data.gd"),
                built, pack_paths)

        table_md = "\n".join("| `%s` | %s |" % (b["slug"], b["name"])
                             for b in built)
        sizes = "\n".join(rows)
        packs_txt = " + ".join("`%s`" % p for p in pack_paths)
        readme = README % (packs_txt, table_md) + \
            "\n## atlas sizes (PNG on disk)\n\n" \
            "| folder | 角色 | atlas | size |\n|---|---|---|---|\n" + sizes + "\n"
        pack_variants = [b for b in built if b["variants"]]
        if pack_variants:
            readme += ("\n## expression variants shipped by the packs\n\n"
                       "`eyes_half` / `eyes_closed` / `mouth_closed` / "
                       "`mouth_tongue` come from the pack art where it exists;\n"
                       "the rest are derived from the shipped open eyes/mouth. "
                       "This build used pack art for:\n\n")
            for b in pack_variants:
                readme += "- `%s`: %s\n" % (b["slug"], ", ".join(b["variants"]))
        with open(os.path.join(root, "assets", "characters", "README.md"),
                  "w", encoding="utf-8", newline="\n") as f:
            f.write(readme)
        print("characters: %d (%s)" % (len(built), ", ".join(
            b["slug"] for b in built)))
        print("total PNG on disk: %.1f KB" % (total / 1024.0))
    finally:
        for zf in zips:
            zf.close()


if __name__ == "__main__":
    sys.exit(main())
