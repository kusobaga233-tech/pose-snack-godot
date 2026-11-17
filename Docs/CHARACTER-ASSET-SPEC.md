# 角色资源结构说明（给 AI 生图 / 图层拆分用）

本文档描述**当前工程实际在用的**角色资源结构。所有数字都来自
`tools/build_characters.py` 与生成的 `src/present/ps_skin_data.gd`，不是约定俗成。

---

## 一、两层结构：原始包（你画的）→ 运行时资源（脚本生成的）

```
原始包（AI 生图 / 手绘产出，400×1200）
  modular_front.zip
    <slug>/layers/body.png     ← 身体（含尾帽、颈部）
    <slug>/layers/head.png     ← 头部底色
    <slug>/layers/eyes.png     ← 眼睛
    <slug>/layers/mouth.png    ← 嘴/舌头
    <slug>/layers/decor.png    ← 头饰
    <slug>/layers/{eyes,mouth}.svg
    <slug>/preview.png, assembled.png
    rig_spec_front.json, README.md, all10_front.png, all10_faces.png

运行时资源（脚本生成，进 APK）
  assets/characters/<slug>/atlas.png   ← 头部图集（8 个区域）
  assets/characters/<slug>/body.png    ← 身体贴图 128×384
  src/present/ps_skin_data.gd          ← 皮肤表（10 条，含区域矩形/锚点/配色）
```

**你只需要产出原始包那 5 层**；`atlas.png` / `body.png` / 皮肤表全部由脚本重算：

```powershell
C:\Python314\python.exe tools\build_characters.py --zip <新包.zip> --project .
```

---

## 二、画布与锚点（所有角色共用，必须严格遵守）

| 项 | 值 |
| --- | --- |
| 画布 | **400 × 1200**，RGBA，透明背景 |
| 朝向 | **头在下方，脸朝 +Y（向下）**，身体在上方 |
| 叠加顺序 | `body → head → eyes → mouth → decor`，**层间零偏移** |
| 颈部 / 身体接头 | `(199, 850)` |
| 头部中心 | `(199, 900)`，头半径约 **124.5**（x 74.5 … 323.5） |
| 左眼 / 右眼 | `(150, 930)` / `(248, 930)` |
| 嘴部 | `(199, 1030)` |
| 头饰锚点 | `(199, 824)` |
| 尾端中心 | `(199, 210)` |
| 身体管 | 宽 **160**（x 119 … 279），长 **640**（y 210 … 850） |
| **可用直管段** | **y 290 … 770**（这段必须等宽、图案可延伸；两端是圆帽） |

> 生图必须按这套锚点出图。**层与层之间不要有位移**，脚本不做对齐补偿。

---

## 三、AI 生图要交付什么

### 每个角色 5 张 PNG（400×1200，透明底）

| 文件 | 内容要求 |
| --- | --- |
| `body.png` | 只画身体管：x 119–279、y 210–850；y 290–770 **严格等宽**；尾端在 y≈210 收成圆帽；不许有阴影溢出管外 |
| `head.png` | 只画头部底色/轮廓，中心 (199,900)，半径 ≤124.5 |
| `eyes.png` | 只画眼睛（左右各一，中心 150/248, 930），**不要画眼皮以外的颜色**（半闭/闭眼由脚本派生） |
| `mouth.png` | 只画嘴 + 舌头，锚点 (199,1030)，**舌头向下伸** |
| `decor.png` | 只画头饰（帽/皇冠/耳机等），锚点 (199,824) |

### 需要额外提供的表情（可选，但推荐）

脚本能**派生** `eyes_half` / `eyes_closed` / `mouth_closed` / `mouth_tongue`；
若你想要更好的表情，**直接按下面命名再给两张**（放进同目录）：

```
eyes_half.png    eyes_closed.png    mouth_closed.png    mouth_tongue.png
```

有就直接用、没有就派生（脚本里 `derived:` 那段逻辑）。

---

## 四、运行时图集里有什么（决定你能改哪些）

每个角色的 `atlas.png` 有 **8 个区域**，全部裁到 alpha 包围盒，缩放系数 **K = 0.5**（源像素 → 图集像素）：

| 区域 | 来源 | 说明 |
| --- | --- | --- |
| `head` | `head.png` | 头底 |
| `decor` | `decor.png` | 头饰，**最后画**（盖住眼/嘴） |
| `eyes_open` | `eyes.png` | 睁眼 |
| `eyes_half` | 派生或提供 | 半闭 |
| `eyes_closed` | 派生或提供 | 闭眼 |
| `mouth_open` | `mouth.png` | 张嘴（默认） |
| `mouth_closed` | 派生或提供 | 闭嘴 |
| `mouth_tongue` | 派生或提供 | 吐舌 |

区域记录格式（`ps_skin_data.gd`）：

```gdscript
"head": [x, y, w, h, ox, oy]
```

- `x, y, w, h`：图集内的像素矩形
- `ox, oy`：该区域左上角**相对头部锚点 (199,900) 的偏移**，单位是**图集像素**（= 源像素 × 0.5）

实测示例（A1_spicy）：

| 区域 | 图集矩形 | 源图等价位置（左上角, 尺寸） |
| --- | --- | --- |
| head | `[8, 8, 124, 130]` | (75, 786) 248×260 |
| decor | `[248, 8, 120, 63]` | (87, 720) 240×126 |
| eyes_open | `[8, 146, 96, 56]` | (103, 880) 192×112 |
| eyes_half | `[140, 8, 100, 64]` | (99, 860) 200×128 |
| eyes_closed | `[238, 146, 94, 14]` | (107, 916) 188×28 |
| mouth_open | `[112, 146, 34, 48]` | (165, 1004) 68×96 |
| mouth_closed | `[196, 146, 34, 16]` | (165, 1004) 68×32 |
| mouth_tongue | `[154, 146, 34, 48]` | (165, 1004) 68×96 |

> 这些矩形是**按 alpha 自动裁出来的**，所以你调整画的内容后矩形会变，不用手填。

---

## 五、身体贴图怎么用（决定图案设计）

- `body.png` = **128×384**，是源图 `x 119–279, y 290–770`（160×480）缩到 0.8 倍
- 映射：**u 横跨管宽，v 沿管长**；`v=0` 是尾端，`v=1` 是颈端
- 当前是**单次拉伸**（不平铺）——所以：
  - **纵向渐变**（尾→颈）没问题
  - **周期性花纹**会被拉伸；若你要等距花纹，请把图案画得**沿长度基本均匀**，或告诉我，我把 `BODY_TILE_MUL` 打开（代价是渐变会出现色阶）

---

## 六、新增 / 替换角色的流程

1. 按第二节规格出 5 层（+ 可选 4 张表情），放进
   `modular_front/<slug>/layers/`
2. 在 `tools/build_characters.py` 的 `CHARACTERS` 表里加一行：
   `("slug", "短名", "完整名")`（短名会显示在模式选择页）
3. 重新打包 zip，重跑：
   ```powershell
   C:\Python314\python.exe tools\build_characters.py --zip <zip> --project .
   ```
4. 跑发布闸门（会校验：10 条皮肤、80 个区域都在图集内、`missing=0`、贴图能加载）：
   ```powershell
   powershell -File tools\verify_release.ps1
   ```
5. 闸门全绿才算可用；红了不许打包。

---

## 七、不要破坏的运行时契约（改资源前必读）

| 契约 | 原因 |
| --- | --- |
| 头部必须是 **1 个 draw call**：head + decor + 1 个眼态 + 1 个嘴态，共 4 个四边形 | 8 条蛇同屏，逐层画会把 draw 从 138 顶到 200+ |
| 表情只能**换 UV 矩形**，不能加新图 | 同上 |
| 身体必须是 **1 个 draw call** | 同上 |
| 头饰永远最后画 | 否则帽檐会被眼睛盖住 |
| 眼睛/嘴的锚点不动 | 派生半闭/闭眼依赖这些锚点裁切 |
| 身体直管段 y 290–770 等宽 | 贴图按这段裁；不等宽会导致贴图变形 |

---

## 八、配套文件

| 文件 | 作用 |
| --- | --- |
| `tools/build_characters.py` | 唯一生成器（区域裁切、派生表情、皮肤表） |
| `src/present/ps_skin_data.gd` | 生成的皮肤表（**不要手改**） |
| `src/present/ps_skins.gd` | 运行时加载/分配/fallback |
| `assets/characters/README.md` | 脚本生成的目录说明 |
| `evidence/release-gate-*.txt` | 每次闸门日志（含资源核对结果） |
