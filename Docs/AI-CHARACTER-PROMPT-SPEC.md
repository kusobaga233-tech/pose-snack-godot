# 角色生图交付规范（交给生图线程）

> 目标：产出可直接进游戏的**分层角色资源**。所有尺寸、锚点、图层规则都是硬约束，
> 不符合的图**无法进游戏**（我们的校验器会逐条判定，见第八节）。
> 本文档可整份复制给生图线程。

---

## 一、交付物清单

每个角色一个文件夹，**必须**包含这 5 个文件（文件名固定，全部 PNG）：

```
<slug>/
  body.png      400×1200  透明背景  只画身体管
  head.png      400×1200  透明背景  只画头部底色
  eyes.png      400×1200  透明背景  只画眼睛
  mouth.png     400×1200  透明背景  只画嘴+舌头
  decor.png     400×1200  透明背景  只画头饰（没有就交一张全透明图）
```

推荐**额外**再交 4 张表情（有就用，没有我们脚本会派生，但手绘更好）：

```
  eyes_half.png     眼睛半闭
  eyes_closed.png   眼睛闭合（只画上下眼睑弧线）
  mouth_closed.png  闭嘴
  mouth_tongue.png  张嘴吐舌
```

打包成 `<角色名>.zip`，根目录是 `<slug>/` 文件夹。

**slug 命名**：大写字母+数字开头，下划线分隔，全部小写后缀，例如 `A1_spicy`、`C2_bubble`。

---

## 二、画布与锚点（所有角色完全一致，禁止偏移）

### 锚点（绘制基准，必须对准）

| 项 | 值 |
| --- | --- |
| 画布 | **400 × 1200** 像素，RGBA，**透明背景** |
| 朝向 | **头在画面下方，脸朝正下方（+Y）**，身体从头上方延伸出去 |
| 图层顺序 | `body → head → eyes → mouth → decor`，**层与层之间零位移**（每张图都在同一套坐标上画） |
| 颈部 / 身体接头 | `(199, 850)` |
| 头部中心 | `(199, 900)`，头半径 **≈124.5**（水平范围 x 74 … 324） |
| 左眼中心 | `(150, 930)` |
| 右眼中心 | `(248, 930)` |
| 嘴部中心 | `(199, 1030)` |
| 头饰锚点 | `(199, 824)` |
| 尾端中心 | `(199, 210)` |
| 身体管 **标称**宽度 | **160 px**（x 119 … 279，这是贴图取样区） |
| 身体管 **可见**宽度 | **≈179 px**（含左右各约 9 px 描边，实测 178–179） |
| 身体可见包围盒 | x **107 … 293**，y **91 … 939** |
| **可用直管段** | **y 290 … 770**（这段可见宽度必须恒定 179±4 px） |

### 实测几何（现有 10 个角色的真实包围盒，供对照）

> 下表是**实测值**，不是估计值。新角色请与它保持一致（±15 px 内的差异可接受）。

| 层 | x 范围 | y 范围 | 说明 |
| --- | --- | --- | --- |
| body | 107 … 293 | 91 … 939 | 直管段可见宽 179 px 恒定 |
| head | 74 … 323 | 786 … 1045 | 直径 249，中心 (198.5, 915.5) |
| eyes | 62 … 333 | 850 … 1034 | 含眼睑/睫毛，可超出头部少许 |
| mouth | 157 … 242 | 990 … 1112 | 舌可伸到 y≈1112 |
| decor | 31 … 369 | 699 … 1104 | **允许垂到头部两侧**（耳机/耳坠），但必须贴着头部 |

> 注意区分：**标称管宽 160** 是引擎贴图取样区；**可见管宽 179** 是含描边的美术尺寸。
> 生图请画到"可见 179"，别按 160 画，否则描边会被裁掉。

示意图（坐标，非比例）：

```
y=210  ┌──────┐  ← 尾端圆帽中心 (199,210)
       │      │
       │ 160  │  ← 身体管：x 119..279
       │ 宽   │
y=290  ├──────┤  ← 直管段开始（必须等宽！）
       │      │
       │      │
y=770  ├──────┤  ← 直管段结束
       │      │
y=850  └──┬───┘  ← 颈 (199,850)
       (head)     ← 头部中心 (199,900) r≈124.5
        ●   ●     ← 眼 (150,930) / (248,930)
          ▬       ← 嘴 (199,1030)
y=1200
```

---

## 三、逐层规范与 Prompt

风格基调（所有层保持一致）：
> 卡通吉祥物，扁平色块 + 粗描边（6–10 px），高饱和，干净渐变，无写实纹理，
> 无投影、无外发光、无水印、无文字。

### 3.1 `body.png` —— 身体管

**要求**
- 只画身体：可见范围 x 107–293（宽 **179**，含左右各 ~9 px 描边），y 91–939；圆尾在 y≈91–210，颈口在 y≈850–939
- **y 290–770 段可见宽度必须恒定 179±4 px**（引擎把这段裁成贴图；不等宽会变形）
- 内部标称管宽 160 px（x 119–279）是取样区，描边画在它两侧
- 允许：纵向渐变、点纹、条纹、鳞片、渐变斑；花纹沿长度**尽量均匀**
- 禁止：任何超出管外的阴影/光晕/装饰；禁止在管内画脸
- 管外必须完全透明

**Prompt（英文）**
```
Flat cartoon snake body tube, vertical, facing down, transparent background, PNG with alpha.
A single smooth cylindrical tube centered on x=199 of a 400x1200 canvas: visible outline spans x=107..293
(about 179 px wide including a thick 8-9 px outline), visible extent y=91..939.
Round cap at the bottom end (y≈91-210), open neck at the top (y≈850-939).
The section from y=290 to y=770 must be perfectly straight with constant visible width 179 px.
Fill: <主色> with a soft vertical gradient toward <辅色>, plus <花纹：圆点 / 人字纹 / 鳞片 / 星点> repeated evenly along the length.
Thick clean outline (8-9 px) in <深色描边色>. Flat cel shading, one soft highlight strip along the left edge.
No face, no eyes, no shadow, no glow, no text, no watermark.
```

**负面词**
```
face, eyes, mouth, shadow, drop shadow, glow, blur, background, scenery, text, watermark, multiple tubes, tapering body in the middle, wavy edges, texture noise
```

---

### 3.2 `head.png` —— 头部底色

**要求**
- 只画头的**底色与轮廓**：圆形/椭圆，可见包围盒约 **x 74–323、y 786–1045**（直径 ≈249，中心 ≈(199, 916)）
- 允许：头顶花纹、腮红、渐变；**不要画眼睛和嘴**（那是单独图层）
- 头饰**不要**画在这一层
- 头外必须透明

**Prompt**
```
Flat cartoon snake head base only, front view, facing the camera, transparent background, PNG with alpha.
Round head with visible bounding box about x=74..323 and y=786..1045 on a 400x1200 canvas
(diameter about 249 px, centre about (199,916)).
Fill: <主色> with a soft radial gradient. Thick clean outline (8-9 px) in <深色描边色>.
Optional: subtle scale pattern on the forehead, small blush marks on the cheeks.
IMPORTANT: no eyes, no mouth, no hat, no accessory, no shadow, no glow, no text, no watermark.
```

**负面词**
```
eyes, mouth, tongue, hat, crown, headphones, shadow, glow, background, text, watermark, multiple heads
```

---

### 3.3 `eyes.png` —— 眼睛

**要求**
- 只有**眼睛**（眼白/眼珠/高光/眼睑/睫毛），左右各一，中心 (150,930) 与 (248,930)
- 可见包围盒大致 **x 62–333、y 850–1034**（睫毛/眼睑可略超出头部边缘，属正常）
- 两只眼睛水平并列，**上眼睑在眼睛上方**，瞳孔朝**下**（朝嘴的方向）
- 不要画眼皮以外的肤色/头部颜色，不要画嘴
- 建议单眼直径 88–104 px

**Prompt**
```
Two cartoon eyes only, side by side, transparent background, PNG with alpha, on a 400x1200 canvas.
Left eye centered at (150,930), right eye centered at (248,930), each about 96 px wide,
visible extent roughly x=62..333, y=850..1034 (eyelashes/lids may overhang the head edge slightly).
Large glossy round eyes, dark pupil, two white specular highlights, thin dark outline.
Upper eyelid sits at the top of each eye (eyelid line horizontal). Pupils look DOWN toward the mouth.
No head, no skin, no mouth, no shadow, no text.
```

**负面词**
```
head, skin, mouth, tongue, hat, shadow, glow, three eyes, asymmetric placement, eyelid on the side
```

---

### 3.4 `mouth.png` —— 嘴 + 舌头

**要求**
- 只有嘴部：中心 (199,1030)，可见包围盒约 **x 157–242、y 990–1112**，**舌头向下（+Y）伸出**（可到 y≈1112）
- 允许：张嘴、舌头、牙齿、口水
- 不要画头部、眼睛

**Prompt**
```
Cartoon mouth only, centered at (199,1030) on a 400x1200 canvas, transparent background, PNG with alpha.
Visible extent about x=157..242, y=990..1112. Wide open smiling mouth, about 80 px wide,
with a pink forked tongue extending DOWNWARD (+Y) out of the mouth to about y=1112.
Thick dark outline, flat cel shading. No head, no eyes, no skin, no shadow, no text.
```

**负面词**
```
head, eyes, skin, tongue pointing sideways, tongue pointing up, shadow, multiple mouths, text, watermark
```

---

### 3.5 `decor.png` —— 头饰

**要求**
- 头饰锚点 (199,824)，画在头顶上方；**允许沿头部两侧垂下**（耳机、耳坠、帽檐），最低可到 y≈1104
- 但必须**贴着头部**（最高点不要高过 y≈550），不要沿身体往上画
- 允许：帽子、皇冠、耳机、花、发带、眼镜（眼镜可覆盖眼部区域）
- 没有头饰 → 交一张**全透明 400×1200** PNG

**Prompt**
```
Single cartoon head accessory only (e.g. <帽子/皇冠/耳机/蝴蝶结>), transparent background, PNG with alpha,
anchored at (199,824) on a 400x1200 canvas, sized to sit on a 249 px wide head.
May hang down along the sides of the head (to y≈1104) like headphones or earrings,
but must stay attached to the head and must not extend up along the body (topmost point y>=550).
Thick clean outline, flat cel shading, one accent highlight.
No head, no face, no eyes, no body, no shadow, no text, no watermark.
```

**负面词**
```
head, face, eyes, mouth, body, multiple accessories, shadow, glow, text, watermark
```

---

## 四、表情变体（推荐手绘，没有就派生）

| 文件 | 内容 |
| --- | --- |
| `eyes_half.png` | 上眼睑下垂盖住约一半瞳孔 |
| `eyes_closed.png` | 只画两条向下弯的闭合眼线（"^ ^" 或 "‿ ‿"），**不要**画眼白 |
| `mouth_closed.png` | 闭嘴的唇线（可以带一点嘴角上扬） |
| `mouth_tongue.png` | 张嘴 + 舌头伸出（与 mouth.png 相同但舌更外伸，用于"吐舌头"动画） |

提示：这 4 张的**锚点与尺寸必须与 `eyes.png` / `mouth.png` 完全一致**，否则切换表情会跳。

---

## 五、配色回报（进皮肤表用）

每个角色请额外给一段文本（或 JSON），我会写进皮肤表：

```json
{
  "slug": "C1_example",
  "name": "短名（4-6 个汉字，显示在选人页）",
  "full": "完整名（例如：甜品控 · 布丁蛇）",
  "rim":  "#2C183F",   // 身体描边色（取管身阴影处 30% 亮度）
  "halo": "#C27FFF",   // 外发光主色（取管身中间调）
  "dot":  "#DF99FF"    // 小地图圆点色（比 halo 更亮）
}
```

---

## 六、生图常见错误（请逐条避免）

| 错误 | 后果 |
| --- | --- |
| 透明背景变成了白底/灰底 | 整张图会带着白框进游戏 |
| 身体中段收窄或弯曲 | 贴图拉伸变形（游戏里蛇是直的管） |
| 各层位置不一致（头偏了） | 眼睛/嘴和头错位 |
| 眼睛画在 head 层里 | 无法眨眼，表情失效 |
| 头饰画在 head 层里 | 头饰会跟着头一起被眼睛盖住 |
| 带了投影/外发光 | 游戏里会变成脏边 |
| 画布不是 400×1200 | 直接判不合格 |
| 一个角色交多张头 | 无法合成 |

---

## 七、交付前自检（生图线程请自行跑一遍）

- [ ] 5 张 PNG（+ 可选 4 张表情）齐全，文件名完全一致
- [ ] 每张都是 **400×1200**，**RGBA**，背景**完全透明**（四角 alpha = 0）
- [ ] 5 张叠在一起时，头/眼/嘴/头饰位置**严丝合缝**
- [ ] `body.png` 在 y=290…770 之间**每一行可见宽度恒定 179±4 px**（校验器会逐行量）
- [ ] 身体可见包围盒落在 **x 107–293、y 91–939**（±15 px）
- [ ] 头部可见包围盒落在 **x 74–323、y 786–1045**（±15 px）
- [ ] 眼睛中心在 (150,930)/(248,930)，可见范围落在 **x 62–333、y 850–1034**
- [ ] 嘴部中心在 (199,1030) 附近，可见范围落在 **x 157–242、y 990–1112**
- [ ] 没有文字、水印、投影、外发光
- [ ] 配色 JSON 已附上

---

## 八、我们这边的验收流程

1. **自动校验**（10 秒）：`python tools/check_character_pack.py --zip <你的包.zip>`
   逐条检查：尺寸/RGBA/透明/锚点包围盒/管宽恒定/层间对齐，输出 PASS/FAIL
2. **生成运行时资源**：`python tools/build_characters.py --zip <包> --project .`
3. **发布闸门**：`tools\verify_release.ps1`（10 条皮肤 / 80 区域在图集内 / missing=0 / 截图非空 / draw ≤200）
4. **PC 截图**：把新角色放进一局，检查头/身/表情是否正常
5. **真机**：装包后人眼确认（遥控器换角色、2P 两人不同角色）

任何一步红了，我会把**具体失败项和坐标**贴给你，你按坐标改。

---

## 九、角色位参考（若要扩充整套）

| 位置 | 人设方向 | 建议主色 |
| --- | --- | --- |
| A 组 | 性格夸张型（辣/怂/健身/戏精/摆烂） | 红橙 / 青灰 / 黄绿 / 品红 / 薄荷 |
| B 组 | 生活方式型（奶茶/自拍/守财/游戏/贵妇） | 紫罗兰 / 灰绿 / 金黄 / 蓝紫 / 粉 |
| C 组（新增） | 可做：夜宵、熬夜、通勤、摸鱼、广场舞 | 建议避开上面已用色相 |

同一批里**避免两个角色主色相近**，否则 8 条蛇同屏时分不清。
