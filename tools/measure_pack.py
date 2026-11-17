import io, zipfile, statistics as st
from PIL import Image

Z = r"D:\CLAUDE-PROJ\snake-characters\modular_front.zip"
LAYERS = ("body", "head", "eyes", "mouth", "decor")
rows = {}
with zipfile.ZipFile(Z) as zf:
    for info in zf.infolist():
        if not info.filename.lower().endswith(".png"):
            continue
        parts = info.filename.split("/")
        if len(parts) < 2 or parts[0].startswith("all10") or parts[0].startswith("A1_before"):
            continue
        slug = parts[0]
        name = parts[-1].rsplit(".", 1)[0].lower()
        if name not in LAYERS:
            continue
        img = Image.open(io.BytesIO(zf.read(info)))
        img.load()
        w, h = img.size
        a = img.getchannel("A")
        bb = a.getbbox()
        rec = rows.setdefault(slug, {"size": (w, h)})
        rec[name] = bb

print("slug, body_bb, body_w@straight, head_bb, eyes_bb, mouth_bb, decor_bb")
for slug in sorted(rows):
    r = rows[slug]
    bw = None
    # body width at straight section: reopen body
    with zipfile.ZipFile(Z) as zf:
        for info in zf.infolist():
            if info.filename.startswith(slug + "/") and info.filename.lower().endswith("/body.png"):
                img = Image.open(io.BytesIO(zf.read(info))).convert("RGBA")
                ap = img.getchannel("A").load()
                ws = []
                for y in range(290, 770, 10):
                    row = [x for x in range(0, img.size[0]) if ap[x, y] > 32]
                    if row:
                        ws.append(row[-1] - row[0] + 1)
                bw = (min(ws), int(st.median(ws)), max(ws))
    print("%-10s body=%s w=%s head=%s eyes=%s mouth=%s decor=%s" % (
        slug, r.get("body"), bw, r.get("head"), r.get("eyes"), r.get("mouth"), r.get("decor")))

print()
print("=== 汇总（跨 10 个角色） ===")
for name in LAYERS:
    xs0 = [rows[s][name][0] for s in rows if rows[s].get(name)]
    ys0 = [rows[s][name][1] for s in rows if rows[s].get(name)]
    xs1 = [rows[s][name][2] for s in rows if rows[s].get(name)]
    ys1 = [rows[s][name][3] for s in rows if rows[s].get(name)]
    if not xs0:
        continue
    print("%-6s x %3d..%3d   y %3d..%3d   w %3d..%3d  h %3d..%3d" % (
        name, min(xs0), max(xs1), min(ys0), max(ys1),
        min(b - a for a, b in zip(xs0, xs1)), max(b - a for a, b in zip(xs0, xs1)),
        min(b - a for a, b in zip(ys0, ys1)), max(b - a for a, b in zip(ys0, ys1))))
