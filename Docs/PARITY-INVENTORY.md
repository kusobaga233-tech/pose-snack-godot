# PARITY INVENTORY — 网页原版 vs Godot 移植

状态：只读盘点（未修改任何源码、未运行 Godot、未接触设备）。
时间：2026-11-13。
目的：把「完全还原网页版的行为与表现」拆成可执行的清单：**已同、已偏、缺什么、为什么难、先做哪一步**。

## 0. 读法与证据口径

路径前缀（下文一律用前缀 + 相对路径 + `:行号`）：

| 前缀 | 绝对路径 |
| --- | --- |
| `P/` | `D:\CODEX-PROJ\yoodou\pose-snake-full-20261112\pose-snake\` （网页原版 = 规格） |
| `G/` | `D:\CODEX-PROJ\yoodou\pose-snake-godot\` （当前 Godot 移植） |

三条重要口径，避免误判：

1. **规则层已经是逐行移植，不是重写。** `G/src/core/config.gd:2` 明确写着 “ported 1:1 from `js/config.js`”，
   `G/Docs/core-model.md:1-58` 记录了运动学 / 时钟 / 确定性契约。所以绝大多数「玩法数值」条目应为 `same`，
   真正的差距集中在 **表现层、界面层、输入层、以及网页独有的调试/工具界面**。
2. **网页截图是多代产物，不能一律当规格。** 例如 `P/screenshots/01-arena.png`、`41-playing-quickplay.png`
   还是「无界面带 + 左下小地图 + 浮动设置面板」的旧代；当前代码已经有 `#uiBar` 三栏界面带
   （`P/style.css:2182-2204`），最新一代证据是 `P/screenshots/land-scape-20261112-005226.png`（1P）、
   `land-split-20261112-005644.png`（2P）、`title-final-20261112-004643.png`（标题）、
   `land-result3-20261112-010017.png`（结算）。本文件的「表现差异」以**最新一代**为准，
   旧代只用来证明「某功能曾经存在、后来被删」。
3. **Godot 的 `evidence/*.png` 混着「真实流程截图」和「preview 表演截图」。** `--capture` 路径会跑
   `_prepare_preview()` / `_preview_fx()`（`G/src/main.gd:1759-1795`），所以 `render-preview-1080p.png`
   里的 `YUM!`、两个玩家同屏同镜等都**不是**真实对局表现。真实流程看 `flow-04-play.png`、
   `remote-03-play.png`、`ship-31-final.png`；流程界面看 `ship-30-final-mode-select.png`、
   `flow-02-ready.png`、`remote-05-settle.png`。

另外：**当前 `P/screenshots/*` 里的「3×3 地图」小地图是历史遗留**。`P/js/render.js:898` 仍导出
`drawMinimap()`，但 `P/js/main.js` 从未 import 它（`P/js/main.js:12` 的 import 列表里没有），`P/play.html:10529`
也只有定义、没有调用点 → 现行网页版**没有小地图**。Godot 反而有小地图（见 §1-I）。

---

## 1. 功能对照矩阵

状态取值：`same` / `different` / `missing-in-godot` / `extra-in-godot` / `missing-in-web`。

### A. 世界 / 战场

| # | 功能 | web（怎么做的，file:line） | godot（现在怎么做的，file:line） | status | 差距说明 |
|---|---|---|---|---|---|
| A1 | 世界 4800×2700（3×3 屏，单屏 1600×900） | `P/js/config.js:10`、派生 `config.js:573-576` | `G/src/core/config.gd:26-38`（`w/h` 由 tile 派生） | same | 数值完全一致。 |
| A2 | 3×3 分屏虚线 | `P/js/render.js:116-138`：`setLineDash([14,18])`，`rgba(86,232,255,0.11)`，`lineWidth 2` | `G/src/present/ps_world_view.gd:163-181`：32×2 dash 贴图，alpha 0.16 | different | 都是静态虚线；Godot 无 dash 相位动画，透明度略高。 |
| A3 | 世界光斑（22 个） | `P/js/render.js:39-51, 90-102`：`Math.random` 位置、`globalCompositeOperation='lighter'`、radial gradient、alpha 0.07-0.15 | `G/src/present/ps_world_view.gd:73-90`：固定种子、预烘 blob 贴图、普通混合、alpha 0.075-0.15 | different | Godot 少了 additive 提亮，光斑偏「灰」；同时是**确定性**的（收益：可复现截图）。 |
| A4 | 90px 地面点阵（十字 + 圆点） | `P/js/render.js:54-70`：`rgba(120,220,255,.075)` 画布 pattern | `G/src/present/ps_assets.gd:82-99`：一次性烘成 90×90 贴图（0.075 / 十字 0.055） | same | 图案一致，Godot 走贴图平铺（更快）。 |
| A5 | 世界边界墙 + 危险预警 | `P/js/render.js:148-194`：14px 描边 + `shadowBlur 40`，`danger` 阈值 320，脉冲 140ms | `G/src/present/ps_world_view.gd:184-231`：88×zoom 的红色衰减贴图带 + 4px 实线，阈值 340，脉冲 7.2rad/s | different | 观感不同：网页是「发光红线」，Godot 是「向场内衰减的红色光墙」。Godot 的更强、更占画面。 |

### B. 相机

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| B1 | 跟随平滑 + 朝向前瞻 | `P/js/main.js:1947-1973`：`follow=9`（指数 k），`lookahead=min(240, speed*0.45)` | `G/src/main.gd:1187-1219`：同一公式（`1-exp(-follow*dt)`，同一 lookahead） | same | 公式逐行一致。 |
| B2 | 视野跨度规则（短边决定跨度） | `P/js/main.js:1880-1920`：桌面短边 900；手机 `640*(cssShort/390)` clamp 380-780；双人**仅手机**乘 1.5；`maxViewH 1900` | `G/src/main.gd:631-638`：恒定 `CAM_SPAN=900`（`main.gd:217`），双人**无条件**乘 `split_span_boost=1.5`；手机字段仅声明未使用（`G/src/core/config.gd:41-51`） | different | ① 设备固定 1920×1080 时 1P 与网页等价（都是 1600×900 世界 → zoom 1.2）；② **双人分屏 Godot 比网页远 1.5 倍**（Godot zoom≈0.71，网页≈1.07），蛇明显变小；③ 手机规则是死代码。 |
| B3 | 相机夹取到世界内 | `P/js/main.js:1968-1969` | `G/src/main.gd:1207-1214` | same | 夹取方式一致（span≥世界时居中）。 |
| B4 | 开局/复活瞬移对准 | `P/js/main.js:1923-1934`（`snapCamera`） | `G/src/main.gd:1181-1185`（`_snap_cameras`）+ `1201-1203` 距离 >1500 直接跳 | different | Godot 多了一条「差太远就瞬移」，网页只有开局/复活显式 snap。 |
| B5 | 吃/击杀的推镜（zoom pulse） | `P/js/main.js:2444`（`scale = ... * fx.zoom`）+ `P/js/fx.js:364-365,392,633` | 无：`zoom` 在重建视图时定死（`G/src/main.gd:599,628`） | missing-in-godot | 打击感的核心一层缺失。 |
| B6 | 震屏 | `P/js/fx.js:355-358,618-627`：按幅度分档衰减（18 以上 4.6，否则 8.5），每帧随机方向 | `G/src/present/ps_fx.gd:294,298-303`：`exp(-7.5dt)`，正弦叠加方向；`G/src/main.gd:1219` 施加到相机 | different | Godot 幅度上限 26、方向是正弦而非随机，小震感偏「机械」。 |
| B7 | hit-stop（时间放缓） | `P/js/fx.js:368,637-643`：`timeScale=0.12`，最长 0.16s | 无（`impact.hit_stop` 只在 `G/src/core/config.gd:415` 声明，无人读取） | missing-in-godot | 击杀/被吃没有顿帧。 |

### C. 蛇的运动与外观

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| C1 | 初始 16 节 / 间距 18 / 半径 22 / 基础速度 300 | `P/js/config.js:63-66` | `G/src/core/config.gd:86-89` | same | — |
| C2 | 转向角速度 8.5 + 反向补偿 1.35 | `P/js/config.js:118-128`，应用点 `P/js/snake.js`（见 `G/Docs/core-model.md:16-25`） | `G/src/core/config.gd:108-114`；`G/src/core/snake.gd:290-300` | same | 上限语义（clamp 到 max_turn，而非直接设角）也一致。 |
| C3 | 越大越慢（指数趋近） | `P/js/config.js:109-116` | `G/src/core/config.gd:98-105`；`G/src/core/snake.gd:253-265` | same | — |
| C4 | 越长越粗（1.00→2.00×，120 节封顶，判定同源） | `P/js/config.js:93-100,604-620` | `G/src/core/config.gd:74-82,548-561`；`G/src/core/snake.gd:149` | same | 半径同时进碰撞与绘制，两边都强调这一点。 |
| C5 | 蛇身正弦摆动 | `P/js/snake.js` `renderPoints()`（`G/Docs/core-model.md:111` 记录「wobble 只在渲染，不在碰撞链」） | `G/src/core/snake.gd:427-469`（`render_points_into`） | same | 只影响绘制，碰撞链不受影响。 |
| C6 | 蛇身绘制（光晕/描边/渐变/高光/鳞纹） | `P/js/render.js:468-592`：Path2D 二次曲线平滑；`lighter` 光晕 α0.13、宽 `2R+30`；深色描边 `2R+5`；**head→tail 四段线性渐变**；顶部高光带整体上移 `R*0.36`；`shadowBlur 26`；逐节圆弧鳞纹（`arc(R*0.55,-0.6π..0.6π)`，带淡出）；进食脉冲圆点 | `G/src/present/ps_world_view.gd:381-472`：每层一个大三角带（glow 3 条同心 / outline +5 / body / aura / sheen），16 色 ramp；**鳞纹是直线横纹**（`396-416`），无淡出；sheen 居中而非上移 | different | 三处可感知差异：① 网页渐变是沿「头→尾」方向的真实线性渐变，Godot 是沿体长的 ramp（观感接近但虎口/尾端色相不同）；② 网页鳞纹是有弧度的鳞片且向尾淡出，Godot 是等距直纹（读起来像「刻度」）；③ 网页有 `shadowBlur` 柔光，Godot 用 3 层 alpha 带替代（略硬）。 |
| C7 | 蛇头 | `P/js/render.js:727-870`：椭圆 `1.06×R*1.12`、深色描边 4px、径向高光、舌头、眼睛（白椭 + 瞳孔 + 高光）、张嘴 | `G/src/present/ps_world_view.gd:533-582`：圆盘 `R*1.38`、只有「暗环」没有描边、纯色 + 左上小高光、舌头/眼/嘴 | different | Godot 头**大 23%**（1.38 vs 1.12），且没有描边与径向高光 → 头显得「平、糊、偏大」。这是最容易被一眼看出的角色外观差异。 |
| C8 | 9 款 NPC 蛇头造型 | `P/js/heads.js`（549 行，9 款完整绘制），派发 `P/js/render.js:733-744` | `G/src/present/ps_world_view.gd:586-703`：9 款程序化近似（googly/bucktooth/moustache/shocked/glitch/lowpoly/pixel/neon/block） | different | 覆盖 9/9，但造型细节是「同名单、异实现」；例如 moustache 的胡子和 lowpoly 的多边形轮廓与网页不是同一套几何。 |
| C9 | 名字 + 风格标签 | `P/js/render.js:878-892`（`snake.name + ' · ' + style.label`，15px） | `G/src/present/ps_world_view.gd:511-515`（`display_name + " · " + style_label`，`15*zoom`） | same | 文案结构一致。 |
| C10 | 走神「?」气泡 | `P/js/render.js:614-632`（13px 黄圆 + 800 18px 问号） | `G/src/present/ps_world_view.gd:516-520` | same | — |
| C11 | 免疫环 | `P/js/render.js:598-609`：`lighter` + **虚线** + 旋转偏移 | `G/src/present/ps_world_view.gd:492-494`：实线 `draw_arc` | different | 少了虚线/旋转，读起来更像「选中圈」。 |
| C12 | 复活/开局待命提示 | `P/js/render.js:637-662`：亮绿环 + 头下文字「待命 0.5s · 给方向」 | 只有环（`G/src/present/ps_world_view.gd:495-498`），**没有文字** | missing-in-godot | 玩家在 0.5s 静止期不知道「现在可以摆方向」。 |
| C13 | 增益呈现（磁铁圈 / 加速光 / 头下读秒） | `P/js/render.js:664-723`：磁铁=径向淡填充 + 虚线圆 + 旋转；加速=沿整条蛇的 additive 橙色呼吸带；头部「加速 4.6s · 磁铁 7.9s」 | `G/src/present/ps_world_view.gd:499-502`（磁铁只画 1 个 0.30α 圆）、`445-455`（加速=2 条 inner shimmer 带）、`521-528`（头部文字） | different | 磁铁缺少「吸附范围」的空间感（网页有渐隐填充 + 虚线），加速带位置在身体内部而非外扩。 |

### D. 食物

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| D1 | 195 个 / 半径 24 / 金果 8% | `P/js/config.js:130-147` | `G/src/core/config.gd:119-131` | same | 低端档会降到 120（`config.gd:531-538`），这是设备 profile 的既定差异。 |
| D2 | 补充节奏（0.2s 一批 ≤8 个，超 target+70 才裁） | `P/js/game.js:1112-1148` | `G/src/core/game.gd:1120-1164` | same | — |
| D3 | 吃判定 `radius*0.82` | `P/js/config.js:139` | `G/src/core/config.gd:126`；`G/src/core/game.gd:1060-1119` | same | — |
| D4 | 食物表情 5 种 | `P/js/game.js:39`（`happy/wink/wide/tongue/sleepy`）+ `1002-1008`；绘制 `P/js/render.js:282-369`（还带**眨眼**：`render.js:283-300`） | 只有 2 种烘图 `happy/wink`（`G/src/present/ps_assets.gd:24-26,128-173`），绘制按 wink 二选一（`ps_world_view.gd:278`）；**没有眨眼** | different | 表情多样性 5→2，且失去时间维度的眨眼 → 食物看起来「呆」。`face` 字段本身是 `StringName`（`G/src/core/food.gd:22`），扩到 5 种只需补 3 张贴图。 |
| D5 | 外发光 | `P/js/render.js:212-222`：仅近处（`detail`）才画 radial glow | 烘进每张贴图（`G/src/present/ps_assets.gd:141-143`）→ 始终有 | different | Godot 更「亮」更均匀，但没有网页那种「近处才有光」的层次；性能上 Godot 更优。 |
| D6 | 金果：皇冠 + wide 嘴 + 半径 ×1.22 | `P/js/render.js:246-266`；`P/js/game.js:1005-1008` | `G/src/present/ps_assets.gd:134,176-180`（皇冠烘图，不旋转） | different | 网页皇冠有 `sin(time*4+seed)*0.12` 的摆动，Godot 是静态贴图。 |
| D7 | 呼吸/浮动 | `P/js/render.js:200-205`（bob 3.2Hz、beat 6.5Hz ±6%） | `G/src/present/ps_world_view.gd:269-274`（同频同幅） | same | — |
| D8 | 远景简化（两只点眼） | `P/js/render.js:269-276` + 调用方 `P/js/main.js:2475`（`detail` 由距离 760 决定） | 无 LOD，全部同一张贴图 | different | Godot 在极多食物时开销更高（但烘图 blit 很便宜），观感更统一。 |
| D9 | 尸体食物用死者颜色 | `P/js/game.js:764`（`makeFood(..., snake.color, true)`） | `G/src/core/game.gd:769+`；渲染就近取色板 `G/src/present/ps_world_view.gd:236-251` | same | 注意 Godot 会把任意色**就近映射**到 6 色板，网页是真实色。 |

### E. 道具

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| E1 | 全场 7 个 / 被吃后 5s 补 / 半径 26 / 拾取 30 | `P/js/config.js:158-180` | `G/src/core/config.gd:149-159`；`G/src/core/game.gd:886-937` | same | — |
| E2 | 加速 5s ×1.65 / 磁铁 10s 300px 620px/s | `P/js/config.js:167-179` | `G/src/core/config.gd:134-159`；`G/src/core/snake.gd:189-220`；`G/src/core/game.gd:975-1014` | same | — |
| E3 | 道具图标（闪电 / U 形磁铁 + 虚线旋转环 + 发光） | `P/js/render.js:376-457`（逐帧：radial glow + 旋转 dash 环 + 深底盘 + 图标 + 14px 标签） | `G/src/present/ps_world_view.gd:285-309` + 烘图 `G/src/present/ps_assets.gd:185-228`（每帧只转环 + blit；标签 20*zoom） | different | 结构一致；Godot 标签更大、发光是烘图所以不随缩放变柔和。 |
| E4 | HUD 增益 chip（名称 / 秒数 / 进度条） | `P/index.html:411-422`；`P/js/main.js:1229-1257`（右上角 `#buffs`，无增益时整块隐藏） | `G/src/present/ps_hud.gd:590-598,636-647`（右侧列表，chip 宽 210、高 54） | different | 语义相同、位置不同：网页贴屏幕右上角，Godot 贴在右侧「输入状态 pill」下方，与排行榜同一列。 |

### F. 碰撞与死亡

| # | 规则 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| F1 | 撞墙（`wallPad 10`） | `P/js/config.js:70`；`P/js/game.js:581-703` 第 1 步 | `G/src/core/config.gd:93`；`G/src/core/snake.gd:387-405`；`G/src/core/game.gd:612` | same | — |
| F2 | 头撞自己的身体 | `P/js/game.js:581+` 第 1 步 → 死（AI 有 `ai.selfHit` 宽容：skip 12 / radiusMul 0.45，`P/js/config.js:346-355`） | **默认不死**：`G/src/core/config.gd:331-338`（`self_kill=false`），`G/src/core/game.gd:613-620, 800-812` | missing-in-godot（**刻意**） | 见 §4。`self_kill=true` 可回到网页行为，且仍保留 AI 宽容窗口。 |
| F3 | 撞别人身体 → 撞的人死 | `P/js/game.js:581+`；击杀记账 `P/js/game.js:720-753` | `G/src/core/game.gd:607-732, 740-768` | same | — |
| F4 | 头撞头：正面对撞（`headRadius 2.05`、`headOnCos 0.55`）→ 长的吞短的；等长双亡 | `P/js/config.js:439-448`；`P/js/game.js:704-753` | `G/src/core/config.gd:339-344`；`G/src/core/game.gd:733-739` | same | — |
| F5 | 击杀收益（absorb 0.28 / min 8 / max 42 / 玩家 ×2 / AI ×0.3 / 吞并后 500ms 免疫） | `P/js/config.js:78-86`；`P/js/game.js:720-753` | `G/src/core/config.gd:62-71`；`G/src/core/game.gd:740-768` | same | — |
| F6 | 死亡：尸体散落食物（≤64）、3s 复活、复活 1.4s 免疫、0.5s 静止无敌 | `P/js/config.js:146,426-436`；`P/js/game.js:754-837` | `G/src/core/config.gd:320-327`；`G/src/core/game.gd:769-841` | same | 静止期语义也一致（`G/src/core/snake.gd:281-286`：冻结时只跟角度、不位移）。 |
| F7 | 相撞/击杀的飘字 | `P/js/game.js:645`（同归于尽）、`740-753`、`781`（阵亡）、`785`（击杀）、`814`（复活） | `G/src/core/game.gd:674,764,795-797,822`（同归于尽 / **吞并！** / 阵亡 / 击杀 / 复活） | extra-in-godot | Godot 多一条「吞并！」（56px）。网页没有；如果追求 1:1 应删或确认保留。 |

### G. 回合流程

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| G1 | 2:00 限时 + 最后 10s 警示 | `P/js/config.js:409-413`；`P/js/main.js:791-796,927-929`（`ui-lastcall`） | `G/src/core/config.gd:309-314`；`G/src/present/ps_hud.gd:550-564`（红字「最后 N 秒！」+ 进度条变红）；`G/src/core/game.gd:1300-1303` | different | Godot 多了显式文案，网页只是变色 + 界面带能量线；两边都可接受，但观感不同。 |
| G2 | 无尽练习（不计时不结算） | 可选：`P/index.html:345-348`；`P/js/main.js:1997-2012`；不结算 `P/js/game.js:458` | 内核支持（`G/src/core/game.gd:445,1300-1303`，`round.mode != timed` 就不结算），**但没有入口** | missing-in-godot（仅 UI） | 加一个 selector 或 debug 开关即可，成本很小。 |
| G3 | 开局前「准备 / 举手」 | 局内 ready 态：`P/js/game.js:53,286-305`；举手 1s：`P/js/config.js:511-512`；中央提示 `P/js/main.js:2522-2535`；镜像框进度条 `P/js/main.js:1199-1226` | **独立 READY 屏**：`G/src/main.gd:98-121`（`READY_ZONE_SEC 1.0` / `READY_RAISE_SEC 1.5`），卡 + 竖向进度条 + 印章 `G/src/present/ps_hud.gd:314-450` | different（**已决策**） | 依据 `G/Docs/FLOW-REFERENCE-1024.md:29-41,78-98`：卡片式准备屏 + 竖向条 + 举手确认。网页是「在战场里举手」。 |
| G4 | 开局倒计时 / GO | 无倒计时，只有 `GO!` 飘字（`P/js/main.js:1845`） | `MODE_COUNTDOWN` 1.5s：`G/src/main.gd:1106-1145`；`G/src/present/ps_hud.gd:506-525`（GO! + 圆环 + 「出发！」） | extra-in-godot（**已决策**） | `FLOW-REFERENCE-1024.md:95-96` 明确「保留 1.5s 短倒计时作开场仪式」。 |
| G5 | 暂停 | `P`/`Esc` → `paused`：`P/js/main.js:2043-2046`；画布大字「已暂停 / 按 P 继续」`P/js/main.js:2590-2602`；暂停层 + 数据条 `P/index.html:238-269` | `OK`/`BACK` → 暂停卡（继续/重新开局/返回模式选择 + 焦点环）：`G/src/main.gd:1166-1176,1999-2044`；`G/src/present/ps_hud.gd:726-765` | different（**已决策**） | 遥控器必须能选；网页是「P 键继续」的键盘方案。 |
| G6 | 开局朝向对齐手臂 | `P/js/main.js:1833-1838`：`heading = lastSignals[i].angle` | 冻结期直接跟随控制角（`G/src/core/snake.gd:281-286`），出生朝内（`G/src/core/game.gd:357-374`） | different | 结果接近（0.5s 内都能摆好方向），但网页是「瞬间对准」，Godot 是「出生朝内 + 冻结期跟手」。 |
| G7 | 通关结算（8 名按结束瞬间长度） | `P/js/game.js:419-449`；`P/js/main.js:1101-1169` | `G/src/core/game.gd:1273-1298`；`G/src/main.gd:1148-1159`；`G/src/present/ps_stage.gd:48-59` | same | 口径一致（死亡长度记 0、峰值另记）。 |
| G8 | 结算后「再来一局」在生长动画期间禁用 | `P/js/main.js:1037-1045`（按钮改文案「蛇还在长…」） | 无此限制：`G/src/present/ps_stage.gd:209-227` 按钮始终可用 | different | 网页是防误点设计；Godot 没有生长演出，因此也无所谓（见 Q2）。 |

### H. 排名 / 排行榜

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| H1 | 排名口径（长度降序，死亡 0） | `P/js/game.js:368-418`（`rankSnapshot`/`rankOf`） | `G/src/core/game.gd:1197-1272`（`_rank_before`/`rank_snapshot`/`live_ranking`） | same | 含「同长时按创建顺序」的稳定排序。 |
| H2 | 局内实时榜 | 左下 DOM：前 3 名 + 自己（不在前 3 才补），带「复活中」「N 节」、风格小字、`me` 高亮：`P/js/main.js:983-1005`；容器 `P/index.html:427-430`；CSS `P/style.css:1129-1180` | 右栏卡片：**全部 8 行**，带玩家高亮条与名次色：`G/src/present/ps_hud.gd:650-671` | different | 信息量更大但**遮挡战场**；网页刻意只给前 3 + 我，且放在界面带之外但属「旁路信息」。 |
| H3 | 「我的名次」块（含 ▲▼ 与「共 8 位玩家」） | 界面带右栏：`P/index.html:207-211`；箭头动画 `P/js/main.js:798-808`（`rank-up/rank-down`）+ `P/style.css:2352-2359` | 时钟下方一行「第 N 名  ▲/▼」：`G/src/present/ps_hud.gd:565-574`，箭头由 `G/src/main.gd:1437-1445` 驱动（2.6s 后消失） | different | 网页是界面带里的大号 96px 名次块；Godot 是 22px 小字。 |
| H4 | 结算 8 列排序 | `P/js/main.js:1138-1150` | `G/src/present/ps_stage.gd:147-208` | same | 列数、名次、名字、节数、吞/死都一致。 |
| H5 | 历史最佳长度（本地持久化） | `P/js/config.js:413`；`P/js/game.js:540-543`（`localStorage`） | `best_length` 只在内存（`G/src/core/game.gd:91,545-546`）；**全工程无 `user://` / `ConfigFile` 写入**（grep 无命中） | missing-in-godot | 重启就丢「历史最长」，结算页的「历史最长」因此无意义。 |

### I. 小地图

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| I1 | 小地图 | `P/js/render.js:898-994` 有完整实现（208px、食物抽稀、道具方块、玩家呼吸点、视野框、「3×3 地图」标题），但**当前 build 从不调用**（`P/js/main.js:12` 的 import 里没有它） | 实装：`G/src/present/ps_hud.gd:673-721`（240×135，食物点云 + 蛇折线 + 相机框 + 3×3 缝） | extra-in-godot | 结论：**网页现行版没有小地图**，Godot 有。旧截图（`P/screenshots/01-arena.png`、`41-playing-quickplay.png`）里的小地图是历史版本。建议保留 Godot 的（见 §6）。 |

### J. HUD 卡片

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| J1 | 局内常驻信息数量 | 界面带只有 3 项：镜像框 / 倒计时 / 我的名次（`P/index.html:166-235`，`P/style.css:2204-2218` 三栏 grid） | 8 组：4 张数据卡 + 时钟 + 名次 + 输入 pill + 增益 chip + 8 行榜 + 小地图（`G/src/present/ps_hud.gd:530-606`） | different | 结构差异最大的一条：网页「界面带 + 战场带物理分离」，Godot 全部浮在战场上。 |
| J2 | 「分数」卡 | 网页已废弃积分：节点保留但 `legacy-stat` 视觉隐藏（`P/index.html:258-266`，`P/style.css:2397`），且不在界面带里 | Godot 把 `game.score` 作为**第一张卡**显示（`G/src/present/ps_hud.gd:535-545`；`score` 是内部 legacy 计数 `G/src/core/game.gd:88-89`） | different | Godot 展示了规则外指标，且占据最显眼位置。建议删。 |
| J3 | 长度 / 吞并 / 最佳 卡 | 都在**暂停层**数据条里（`P/index.html:245-269`），局内不常驻 | 常驻 3 张卡（`ps_hud.gd:535-545`） | different | 网页刻意「局内只留时间」，其余收进 OPTIONS。 |
| J4 | 倒计时外观 | 界面带中央：`120px*ui-scale`、900 字重、`#d7f7ff` + 38px 青色辉光；`.tick` 每秒放大、`.last-call` 橙色脉冲（`P/style.css:2319-2333`） | 48px、白色 / 最后 10s 红白呼吸；下方 5px 进度条（`G/src/present/ps_hud.gd:546-564`） | different | 字号约 1/3，辉光/秒跳动画缺失；Godot 多了进度条（网页没有）。 |
| J5 | 输入状态显示 | 右上 `#statusbar`（待启动/识别中/游戏中/已暂停/本局结束，`P/index.html:402-405`，`P/js/main.js:1259-1262`） | 右上 pill「体感 · 已识别/未识别」「调试 / 演示」（`G/src/present/ps_hud.gd:575-589`） | different | 文案体系不同（遥控器版刻意不出现 keyboard 字样，见 `ps_hud.gd:576-578`）。 |
| J6 | 复活倒计时 | 画布：径向暗角 + 大字倒计时 + 提示（`P/js/main.js:2626-2660`） | 文本「N.N 秒后复活 / 尸体化成了食物」（`G/src/present/ps_hud.gd:608-613`），无暗角 | different | 网页的暗角把注意力收进「等待」，Godot 只是两行字。 |
| J7 | 未识别到人的提示 | 镜像框 `.lost` + 诊断面板 + hint（`P/js/main.js:829-835,1288-1292`） | `pose_hint` chip：未识别 / 手放外侧（`G/src/main.gd:1291-1304`，`ps_hud.gd:614-622`） | same | 都有，形态不同（chip vs 面板）。 |

### K. AI

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| K1 | 7 只 AI、风格池 5 种、每局洗牌 | `P/js/config.js:183-186,370-379`；`P/js/game.js:316-338` | `G/src/core/config.gd:275-298,466-491`；`G/src/core/game.gd:375-398` | same | 数值逐项对齐（bold/timid/greedy/hunter/steady）。 |
| K2 | 难度 / 失误 / 压迫三旋钮（0.85 / 0.10 / 1.0） | `P/js/config.js:200-276`；`P/js/config.js:630-638`（`computeAiPressure`） | `G/src/core/config.gd:164-245,566-573`；`G/src/core/tuning.gd:52-55` | same | 公式一致；但 Godot **没有 UI 可调**（见 §3-1）。 |
| K3 | 围猎 / 拦截 / 领跑压制 / 自体避让 / 防绕圈 | `P/js/ai.js`（672 行）；`P/js/config.js:212-355` | `G/src/core/brain.gd`（645 行）；`G/src/core/config.gd:172-243` | same | 逐参数一致；`G/tests/suite_ai.gd` 固定了行为基线。 |
| K4 | AI 蛇头造型分配（池 9 抽 7 不重复） | `P/js/game.js:339-367`；`P/js/config.js:387-400` | `G/src/core/game.gd:399-427`；`G/src/core/config.gd:269-273,494-499` | same | — |
| K5 | AI 吃食成长 ×0.60、领跑加成 | `P/js/config.js:238-248` | `G/src/core/config.gd:193-197,291-292` | same | — |

### L. 视觉特效

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| L1 | 粒子（碎片 / 火花 / 星星，带重力 + 阻力 + 旋转） | `P/js/fx.js:38-108`（5 种 shape，含 `spark` 拖尾、`star` 五角）；进食 34+26 个、金果 52+40 | `G/src/present/ps_fx.gd:116-154`（3 种 kind，**无重力**，纯 drag）；进食 7 / 金果 14+6 | different | 数量约 1/4，缺少重力下坠与五角星碎片 → 「炸开感」明显弱。上限也不同：网页 1600（`P/js/config.js:545`），Godot 硬编码 220（`ps_fx.gd:12`）；`cfg.fx.max_particles`（1600/700，`G/src/core/config.gd:434,529,538`）**从未被 PSFx 读取**。 |
| L2 | 冲击波（双层，一快一慢） | `P/js/fx.js:113-147,456-463`（白 + 品色，`easeOutCubic`，α=pow(1-t,1.6)） | `G/src/present/ps_fx.gd:182-198,335-346`（单层，线性半径，α=life*0.55） | different | Godot 只有 1 个环，且没有缓动。 |
| L3 | 卡通爆炸星（BurstStar） | `P/js/fx.js:152-191,468-473`（12/16 尖角，放大 1.9×） | 无 | missing-in-godot | 与 `headClarity.skipStar` 相关：网页对「玩家吃普通食物」跳过，金果/击杀仍画。 |
| L4 | 飘字（GO / 击杀 / 复活 / 道具名） | `P/js/fx.js:197-237`（弹出 1.28×、上飘 -90、α 淡出） | `G/src/present/ps_fx.gd:210-227,347-359`（-46 上飘、pop 1.55×、无淡出曲线） | different | Godot 的 pop 更夸张、上飘只有一半、且不透明衰减。 |
| L5 | 全屏闪白 | `P/js/fx.js:628-631,663-669`（按 impact 档：0.09/0.22/0.48/0.55，颜色分档） | `G/src/main.gd:1394-1406`（自己吃 0.10；金果 0.10 色；死亡 0.24 红）；`ps_world_view.gd:121-124` 以 `flash*0.55` 上限绘制 | different | 网页击杀档闪 0.48、死亡 0.55；Godot 上限被压到 0.5*0.55≈0.27 → 闪光更弱。 |
| L6 | 头部可读性收敛（`headClarity`） | `P/js/config.js:547-558`；`P/js/fx.js:407-473`（吃普通食物削粒子/火花/波/跳星） | 配置已移植（`G/src/core/config.gd:425-431,435`）但**没有任何代码读取**（grep `head_clarity` 只命中 config.gd） | missing-in-godot | Godot 粒子本来就少，问题不突出；但一旦按 A3 补粒子就会立刻需要这层，否则蛇头会被自己的碎片糊住。 |
| L7 | 加色混合（`lighter`） | 全篇使用：光晕、火花、冲击波、爆炸星（`P/js/fx.js:651-655`，`P/js/render.js:496,561,674,696`） | 只有普通 alpha 混合；`ps_world_view.gd:435-443` 用三层 alpha 模拟 | different | 「发光」是靠颜色叠加出来的；Godot 的 GL Compatibility 也能做加色材质，但当前没做。 |

### M. 音频

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| M1 | 音效合成方式 | WebAudio 实时合成：三角波上滑 + 噪声爆破（带 bandpass），`P/js/fx.js:260-341` | 启动时烘 6 条 22.05kHz PCM16（正弦扫频 + 可选噪声），`G/src/present/ps_audio.gd:18-76` | different | 实现路径不同（预算限制使然），听感上网页更「脆」（噪声层 + 滤波器），Godot 更「电子音」。 |
| M2 | 音效覆盖 | 3 类：`eat(big)` / `powerup` / `die`（`P/js/fx.js:260,302,325`），只在「自己的事件」播放（`P/js/fx.js:481-484,516-519,564-571`） | 6 类：`eat/big/pickup/kill/death/go`（`G/src/present/ps_audio.gd:29-34`），**所有蛇的事件都播**（`G/src/main.gd:1392,1400,1403`） | different | 8 条蛇一起进食时 Godot 会持续吵；网页刻意只对自己的行为出声。 |
| M3 | 静音开关 | 右上按钮 + `M` 键（`P/index.html:445-451`，`P/js/main.js:2047-2050,2064-2067`） | 无 UI、无快捷键（`ps_audio.gd:11` 有 `enabled` 字段但无人改） | missing-in-godot | 电视场景必需。 |
| M4 | 音频必须用户手势后启动 | `P/js/fx.js:249-257`（`AudioContext.resume`） | 无此限制（`AudioStreamPlayer` 可直接播） | missing-in-web（机制差异） | 不是缺陷。 |

### N. 输入

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| N1 | 圆心 = 脖子→腰按 `centerT=0.35` 插值 | `P/js/config.js:450-461`；`P/js/pose.js:746-773` | `G/src/core/config.gd:383-387`；`G/src/present/ps_pose_input.gd:341-353`（`neck.lerp(waist, center_t)`） | same | — |
| N2 | 圆心横向自动居中（按右手左右伸展极限的中点，`learn 0.06 / minSamples 45 / minSpan 0.5 / maxShift 0.4`） | `P/js/config.js:463-478`；`P/js/pose.js:782-790,1027-1054` | **只有配置字段**（`G/src/core/config.gd:371-380`），`ps_pose_input.gd` / `pose_steer.gd` 全无引用 | missing-in-godot | 直接后果：向右伸手比向左更远，两侧「距离→速度」不对称。是手感问题，不是视觉问题。 |
| N3 | 手腕相对圆心的角度 = 方向 | `P/js/pose.js:797-805`（`atan2`，canvas y 向下） | `G/src/core/pose_steer.gd:74-86` | same | 角度约定一致（0=右，+π/2=下）。 |
| N4 | 死区 `deadzone 0.05`（归一化距离内沿用上一角度） | `P/js/config.js:529`；`P/js/pose.js:797-805` | `G/src/core/config.gd:405-406`；`G/src/core/pose_steer.gd:79-86` | same | — |
| N5 | 距离→速度（0.65~1.80×，near 0.30 / far 0.75，smooth 0.09、slew 3.0） | `P/js/config.js:496-509`；`P/js/pose.js:806-832` | `G/src/core/config.gd:349-368`；`G/src/core/pose_steer.gd:88-109` | same | 低通 + 变化率限制两步都在。 |
| N6 | 丢帧沿用旧方向 `lostTimeoutMs 1000` | `P/js/config.js:510`；`P/js/pose.js:894-925` | `G/src/core/pose_steer.gd:117-127` | same | 保持期间 `hold=true`、速度不回 1。 |
| N7 | 镜像（`1-x`） | 网页用镜像 `<video>` + 坐标直接按镜像画面算（`P/index.html:178-196`、`P/js/pose.js` 内 `px`） | `G/src/present/ps_pose_input.gd:9-17,236-238,427`（`1.0 - provider_x`，默认开；`F7` 可切） | same（约定一致，实现方式不同） | SDK 坐标系本身镜像（`G/src/main.gd:172-189` 有 AIDL 证据），Godot 显式翻转，可运行时关掉。 |
| N8 | 举手开局（0.35 阈值 / 1.0s 保持 / 左右手均可） | `P/js/config.js:511-512`；`P/js/pose.js:834-843`；判定 `P/js/main.js:1210-1225` | 闸门改为「站定 1.0s（`READY_ZONE_SEC`）+ 举手累计 1.5s（`READY_RAISE_SEC`）」：`G/src/main.gd:1044-1075`；举手判定在 `G/src/present/ps_pose_input.gd:394-400`（两手任一） | different | 网页「举手满 1s 即发车」，Godot 最长要 2.5s，且中途撒手进度清零。手感更「仪式化」，现场可能觉得慢。另外 `pose.raise_hold_sec` 的独立计时（`ps_pose_input.gd:409-419,446-450`）**没有任何调用方**，是死代码。 |
| N9 | 兜底放行（人识别不到也能开：`forceStartSec 2.5` / `raiseWaitMaxSec 8`） | `P/js/config.js:513-519`；`P/js/main.js` 内 `readyAt` 逻辑 | 无自动放行：改为 30s「没有检测到玩家」提示 + 只能按返回（`G/src/main.gd:119,482-492`，`ps_hud.gd:482-492`） | different（**已决策**） | `FLOW-REFERENCE-1024.md:97` 把它列为待定 C；当前实现是「永不自动放行」，与设备安全策略一致。 |
| N10 | 键盘兜底 | 方向键 / WASD / 空格 / P / M / L / O：`P/js/main.js:2016-2062`；UI 入口 `P/index.html:513`（先用方向键玩） | 仅桌面调试：`G/src/main.gd:1270-1322` + `G/src/core/keyboard_steer.gd`，Android 上被 `_allow_keyboard_steer=false` 关掉（`G/src/main.gd:394`）；**界面上无入口** | different（**已决策**） | 遥控器盒子没有键盘；保留代码供 PC 调试即可。 |
| N11 | 鼠标 / 触摸转向 | 触摸拖拽（14px 死区、松手保活 8s）：`P/js/main.js:2069-2110`；README 注释里也提到鼠标 | **完全没有** `InputEventMouse*` / `InputEventScreenTouch`（grep 无命中） | missing-in-godot | 设备是遥控器 + 体感，不需要；但调试时没有「点一下就能动」的快路径。 |
| N12 | 遥控器按键 | 无（网页假设键盘/触摸） | `G/src/present/ps_remote.gd` + `G/src/main.gd:1896-2059`（DPAD/OK/BACK，F3-F7 调试键），原生 hook 见 `G/Docs/REMOTE-INPUT.md` | extra-in-godot（**已决策**） | 见 §4。 |
| N13 | 隐藏输入源（capture / autopilot） | 无 | `SRC_SYNTH` + `_autopilot()`（`G/src/main.gd:123,1325-1369`） | extra-in-godot | 只用于自动化截图，不出现在 UI（显示为「演示」）。 |
| N14 | 输入手选择（自动/右手/左手） | UI 三按钮 + `localStorage`：`P/index.html:379-386`；`P/js/main.js:487-500` | 硬编码「自动 + 1.15 迟滞」（`G/src/present/ps_pose_input.gd:354-390`），无手动覆盖 | missing-in-godot | 现场若左手习惯或镜像装反，只能在代码里改。 |

### O. 调试 / 调参 / 日志

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| O1 | 手感调节面板（12 滑杆 + 模式下拉 + NPC 头开关 + 实时读数） | `P/index.html:272-399`；绑定 `P/js/main.js:404-760`；持久化 `localStorage`（如 `main.js:577,586,595,608,618,631`） | 无。`PSTuning` 存在但只能在代码里改（`G/src/core/tuning.gd:17-25`） | missing-in-godot | 见 §3-1。 |
| O2 | 体感识别诊断（状态 / 识别率 / 角度 / 距离 / 死区 / 可见性 / 控制手） | 面板 `P/index.html:373-397`；刷新 `P/js/main.js:527-562` | 只有 F3 调试浮层的 4 行（`G/src/present/ps_hud.gd:787-797` 中的 input/binder 行）+ logcat `[pose]` 行（`G/src/main.gd:1473-1483`） | different | Godot 有等价的**数据**（`ps_pose_input.gd:61-64` 的 `diag`），但没有可视化面板。 |
| O3 | 体感日志录制 / 导出 JSON / CSV / 清空 | `P/js/poselog.js`（40 列、20Hz + 状态跳变补记、含配置快照）；按钮 `P/index.html:388-395`；快捷键 `L`（`P/js/main.js:2051-2052`） | 无任何记录/导出 | missing-in-godot | 排「手感/识别」问题的唯一数据来源，缺了就只能靠 logcat 文本。 |
| O4 | 摄像头环境体检 / 错误分类 | `P/js/diag.js:14-168`（9 类错误）+ `177-248`（安全上下文/权限/设备枚举） | 不适用（无 getUserMedia）；等价信息是 bridge 的 `bound/frames/age/binder/error`（`G/src/present/ps_hud.gd:790-792`） | missing-in-web / extra-in-godot | 网页这套是浏览器专属，**不建议移植**。 |
| O5 | 启动阶段进度与看门狗 | `P/js/main.js:1350-1560`（每阶段硬超时、进度文案、可取消） | 无启动 UI；`bridge` 异步绑定，HUD 显示「等待体感」（`ps_hud.gd:298-309`） | different | 见 §3-7。 |
| O6 | 性能读数 | 无（只有 Chrome DevTools） | F3 浮层 fps/draw/prim/粒子数（`ps_hud.gd:780-786`）+ 每秒 `[perf]` 打印（`main.gd:1450-1464`） | extra-in-godot | 移植带来的收益，保留。 |

### P. 开始面板 / 标题

| # | 内容 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| P1 | 品牌与标题 | `MOTION ARENA` + `TV EDITION` 标签行、绿点 + 「体感贪吃蛇」、副标题：`P/index.html:479-495` | 「• Pose Snake」112px 绿 + 「体感贪吃蛇 · 9 屏大地图 · 8 个 AI 对手」：`G/src/present/ps_hud.gd:236-241` | different | 网页是中文主标题 + 英文徽标；Godot 反过来（英文主标题 + 中文副标题）。 |
| P2 | 四个卖点徽标（2:00 / 8 位玩家 / 长度决胜 / 9 屏地图） | `P/index.html:489-494` | 无 | missing-in-godot | 低成本高感知的「这是什么游戏」信息。 |
| P3 | 人数选择 | 两张大按钮（1 人 / 2 人 + 说明）：`P/index.html:498-508`；切换逻辑 `P/js/main.js:1742-1792`（同时改 `data-split`、键位提示、副标题） | 两张模式卡（单人/双人 + 人物图标 + 1P/2P 角标 + 焦点环）：`G/src/present/ps_hud.gd:261-289`；选择逻辑 `G/src/main.gd:2005-2022` | different | 语义等价、视觉不同；Godot 卡片副标题写「独自挑战 **8 个 AI**」（`ps_hud.gd:284`）——实际是 7 AI + 玩家 = 8 条蛇，**文案错了**。 |
| P4 | 开始 / 键盘兜底 / 快速开玩 | `开始游戏` + `先用方向键玩` + 常驻右上「直接开玩 / 重连体感」：`P/index.html:510-514, 408`；逻辑 `P/js/main.js:1795-1817` | 只有模式卡（点卡片即开始）；无快速开玩、无键盘入口 | missing-in-godot | 遥控器场景下「直接开玩」没有意义（不能动），但「重连体感」的诊断价值仍在。 |
| P5 | 玩法说明（折叠 accordion，10 条） | `P/index.html:524-542`（`<details>` + `ul.rules`，含碰撞/计时/风格/道具/复活等） | 无任何规则说明（只在 READY 屏有一句「举起右手 → 方向 · 手伸远 → 加速」，`ps_hud.gd:348-350`） | missing-in-godot | 现场玩家不看规则会不知道「撞身体会死」「按长度排名」。 |
| P6 | 资源准备状态 / 细则 / 键位提示 | `P/index.html:517-520`（`assetState` / `fineprint` 三行 / pad-hints 一行） | 无 | missing-in-godot | 其中键盘提示对盒子无意义，但「需要允许摄像头…建议站 2 米」这类现场指引有价值（Godot 只在模式选择底部有一句，`ps_hud.gd:254-257`）。 |
| P7 | 启动遮罩 / 自举急救条 | `P/index.html:90-124`（脚本没起来时的红条 + 三个兜底按钮） | 无 | missing-in-web | 浏览器专属，不移植。 |

### Q. 结算舞台

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| Q1 | 8 条「蛇」按长度向上生长、镜头随最高者升高 | `P/js/resultStage.js`（443 行；列 = 真蛇身体，`begin/update/skip`），`P/js/main.js:1109-1120` | 8 根**矩形渐变柱** + 圆头：`G/src/present/ps_stage.gd:146-190`；高度按 `bar_max=330` 固定比例，无镜头抬升 | different | 网页是「8 条小蛇比高」，Godot 是「柱状图」。这是结算页最大的观感差。 |
| Q2 | 生长动画 + 「跳过演出」 | 生长 0.95s（带 0.055s/列 延迟）+ 顶部 `跳过演出 ›`（`P/index.html:462-464`，`P/js/main.js:1994`）+ 按钮禁用「蛇还在长…」（`main.js:1037-1045`） | 0.95s ease-out 生长（`ps_stage.gd:150-152`），**无跳过按钮**，按钮始终可用 | different | 网页的「跳过」+ 禁用逻辑是一套完整防误点设计。 |
| Q3 | 成绩牌（每列一格：名次/名字/节数/吞死） | `P/index.html:466-473`；填充 `P/js/main.js:1138-1150`；列宽与蛇列对齐（`main.js:1016-1029` 用 CSS 变量 `--result-rows-w`） | 每列一张卡：名次/名字/风格/节数/吞死（`ps_stage.gd:191-208`），列宽 132 + gap 18 | different | 网页是**无边框分隔线**的整条成绩带，且与蛇列几何严格对齐；Godot 是 8 张独立圆角卡。 |
| Q4 | 头像（从摄像头裁头） | `P/js/main.js:1056-1098`（鼻+双耳取中心、肩宽定尺度、水平翻转、192×192 JPEG） | 无（无摄像头帧可用，见 §5-1） | missing-in-godot | 依赖帧缓冲，属于硬缺口。 |
| Q5 | 顶部标题与统计 | 「第 1 名 · 本局获胜！」/「第 N 名」+「最长 N 节 · 历史最佳 N 节」：`P/js/main.js:1122-1165`；元素 `P/index.html:457-461` | 左上「FINAL RESULTS / 长度赛」青条 + 「第 N 名」62px + 一行统计 + 「冠军！」（`ps_stage.gd:95-124`） | different | 信息量接近，排版完全不同（网页顶部一条窄带，Godot 左侧一整块）。 |
| Q6 | 双人结算文案 | 两人名次并列 + 「XX 获胜！」（`P/js/main.js:1123-1128`） | 只写玩家 1 的名次（`ps_stage.gd:103-111`，`result.player_rank`） | different | 双人模式结算缺少 2P 名次。 |
| Q7 | 结算底部按钮 | 一个主按钮「再来一局」+ `A` 键帽 + 「按 A 或举手」（`P/index.html:468-472`） | 两个按钮：再来一局（绿）/ 返回模式选择（ghost）+ 遥控器提示（`ps_stage.gd:209-232`） | different | 遥控器需要「返回」；网页只能重开。 |

### R. 文案 / i18n

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| R1 | 语言 | 全中文硬编码（无 i18n 层），少量英文装饰（`MOTION ARENA`、`GO!`、`FINAL RESULTS`） | 中文优先 + `_cn(cn, en)` 双语回退（`G/src/present/ps_hud.gd:168-170`），依赖系统 CJK 字体（`G/src/present/ps_theme.gd:72-133`） | extra-in-godot | 设备有中文字体（`G/evidence/device-menu-cjk.png`），但 `ps_theme.cjk_ok()` 为假时会整屏英文。 |
| R2 | 文案准确性 | 规则文案与数值一致（`P/index.html:528-539`） | 发现 2 处不一致：① 模式卡「独自挑战 8 个 AI」（应为 7 AI / 8 条蛇，`ps_hud.gd:284`）；② 结算右栏「视野 16 ~ N 节」（`ps_stage.gd:239`，语义不明） | different | 属于「看起来不专业」的细节，成本极低。 |
| R3 | 数字格式 | `m:ss`，无尽显示 `∞`（`P/js/main.js:899-903`） | `%d:%02d`（`ps_hud.gd:549`）；无 `∞` | different | 无尽模式没有 UI，所以暂时看不出来。 |

### S. 启动 / 壳层

| # | 功能 | web | godot | status | 差距说明 |
|---|---|---|---|---|---|
| S1 | 摄像头权限 / 模型下载 / 失败引导 | `P/js/main.js:1473-1676`、`P/js/diag.js` | SDK 服务绑定（`G/src/youdoo_bridge.gd`、`G/Docs/WBS.md:38`），失败只体现在「体感不可用」chip | missing-in-web / extra-in-godot | 两边形态完全不同，不建议对齐。 |
| S2 | 加载期间的可取消进度 | `P/js/main.js:1445-1560` | 无（启动即 mode select，绑定在后台） | different | Godot 的启动体验更短，无需取消。 |
| S3 | 窗口失焦自动暂停 | `P/js/main.js:2112-2117` | 无 | missing-in-godot | Android 上由生命周期接管（后台即停帧），可不做。 |

---

## 2. 表现差异（截图对截图）

对照物：
- web 最新一代：`P/screenshots/land-scape-20261112-005226.png`（1P 局内）、`land-split-20261112-005644.png`（2P）、
  `title-final-20261112-004643.png`（标题）、`land-result3-20261112-010017.png`（结算）；
  历史代（用来说明「曾经有什么」）：`01-arena.png`、`41-playing-quickplay.png`（含浮动设置面板 + 小地图）。
- godot：`G/evidence/ship-30-final-mode-select.png`（模式选择）、`flow-02-ready.png`（准备）、
  `flow-04-play.png`（局内真实流程）、`render-preview-1080p.png`（preview 表演）、
  `render-preview-split.png`（双人）、`render-preview-settlement-1080p.png`（结算）、`remote-04-pause.png`（暂停）。

### 2.1 画布结构（最大结构差）

- web：**顶部一条 200px（`--ui-h: calc(200px * var(--ui-scale))`，`P/style.css:2182`）实底界面带**，
  下方 `#arena` 从 `top: var(--ui-h)` 开始（`P/style.css:2191-2198`）；界面带是 3 栏 grid
  `340px | 1fr | 300px`（`P/style.css:2204-2220`）。战场因此是「宽幅横条」（2532×970 ≈ 2.6:1），
  世界跨度按短边 900 → 实际显示约 2340×900 世界单位。
- godot：**没有界面带**。`PSWorldView` 铺满 1920×1080，HUD 作为 CanvasLayer 浮在上面
  （`G/src/main.gd:583-599, 462-473`）；视野固定 1600×900（`G/src/main.gd:631-638`）。
- 后果：Godot 顶部的 4 张数据卡 + 8 行排行榜 + 小地图**直接压在战场与蛇身上**；
  网页的「比赛转播」框感（上下分离、战场带取景框）完全没有。

### 2.2 调色板与对比

| 项 | web | godot | 差异 |
|---|---|---|---|
| 底色 | `--tv-ink #050912`，界面带渐变 `#0c1d30 → #091524 → #050c16`（`P/style.css:1392-1395, 2204-2211`） | `#081226 / #060D1C / #040914` 渐变（`G/src/present/ps_theme.gd:9-11`） | 色相接近，Godot 更偏蓝、更暗。 |
| 主色 | 青 `#56e8ff`（系统/界面）、绿 `#b6ff57`（玩家）、金 `#ffd54a`、文字 `#eaf6ff`（`P/style.css:1397-1401`） | 青 `56E8FF`、绿 `B6FF57`、金 `FFC53D`/`FFE066`、文字 `EAF4FF`（`G/src/present/ps_theme.gd:13-33`） | 基本一致（金略偏橙）。 |
| 面板 | `rgba(7,15,28,.94)` + 1px 青边 + **四角 30×2 青色角标**（`P/style.css:1429-1436`） | `rgba(11,19,33,.84)` + 1px `rgba(89,133,184,.28)`（`ps_theme.gd:39-42`），**无角标** | Godot 面板对比度低（边框几乎看不见）、缺少「TV UI」的角标符号。 |
| 发光 | 大量 `text-shadow: 0 0 38px cyan` 等（`P/style.css:2320-2321, 2349`） | 只有 `draw_string_outline` 暗描边（`ps_theme.gd:140-149`），无辉光 | 网页是「霓虹」，Godot 是「贴纸」。 |

### 2.3 玻璃 / 模糊

- web：`backdrop-filter: blur(14px)` 出现在 `.stat`（`P/style.css:53-54`）、`.tuning`（89-90）、
  `.leaderboard`（1138-1139）、面板（363-364、387-388、515-516、540-541、575-576、967-968）；
  暂停层 `blur(3px)`（`P/style.css:2367`）。标题面板是**半透明玻璃 + 背景战场透视**。
- godot：只有 `StyleBoxFlat`（`G/src/present/ps_theme.gd:190-208`），纯色 alpha 面板，
  **没有任何背景模糊**。标题/模式选择改成了「整屏不透明背景」（`ps_hud.gd:222-235`），
  因此不会出现「糊」的问题，但也失去了玻璃质感。
- 参考图：web 标题 `title-final-20261112-004643.png` 的面板后方能看到战场网格；Godot
  `ship-30-final-mode-select.png` 是纯背景 + 装饰食物。

### 2.4 字体与字号

- web：`"PingFang SC","Microsoft YaHei",sans-serif`（`P/js/render.js:447,627,649,713` 等），
  TV 层字号：时钟 `120px*scale`、名次 `96px*scale`、名次标签 `36px`、总人数 `24px`
  （`P/style.css:2319-2351`），且用 `font-variant-numeric: tabular-nums` + 重度字距。
- godot：`SystemFont`（YaHei/Noto/思源，`ps_theme.gd:46-62`），字号：时钟 48、卡值 40、
  名次 22、标签 18-20、模式卡标题 54（`ps_hud.gd:238-290, 543-574`）。
- 差距：**关键数字（时钟 / 名次）小 2-3 倍**，3 米电视距离可读性明显不如网页；
  另外 Godot 用 `draw_string_outline`（`ps_theme.gd:146-148`）代替网页的外发光。

### 2.5 图标体系

- web：表情全部是 canvas 手绘（食物 5 种脸 + 眨眼、NPC 9 种头、玩家头吐信），
  UI 图标是内联 SVG（静音喇叭 `P/index.html:446-451`）与 keycap 样式（`.keycap`）。
- godot：食物脸烘成 2 种贴图（`ps_assets.gd:138-173`），NPC 头是即时几何（`ps_world_view.gd:586-703`），
  UI **完全没有图标**（没有静音、没有钥匙帽、没有人物以外的图形）。
- 结论：不是「emoji 字体」问题（两边都是手绘/几何），而是 **Godot 缺少第二档细节与眨眼/摆动等时间动画**。

### 2.6 蛇身外观

| 维度 | web | godot | 观感 |
|---|---|---|---|
| 渐变 | 沿头→尾的四段线性渐变（`render.js:513-531`），玩家 `B6FF57→5BEFA0→2FD6C8→1FA8D8` | 沿体长 16 色 ramp，玩家用 `ramp4` 同四色（`ps_world_view.gd:365-369`，`ps_theme.gd:234-247`） | 接近 |
| 轮廓 | 深色描边 `2R+5`，色 `rgba(6,30,34,.5)`（`render.js:504-510`） | 深色带 `2R+10`，色 `rgba(3,13,19,.85)`（`ps_world_view.gd:461-463, 101`） | Godot 描边更黑更宽 → 卡通感更重 |
| 高光 | 整体上移 `R*0.36`、白 α0.22、宽 `R*0.6`（`render.js:546-553`） | 居中白带、宽约为体的 40%、α0.13（`ps_world_view.gd:466-470, 102`） | 网页是「顶光」，Godot 是「内芯亮条」 |
| 鳞纹 | 逐节圆弧 + 向尾淡出 + 随脉冲发亮（`render.js:569-592`） | 等距直横纹、固定 α0.075（`ps_world_view.gd:396-416`） | 网页像蛇腹，Godot 像刻度尺 |
| 尾部 | 圆头线帽自然收细（`lineCap round`） | 三角带 `taper 0.58` + 尾端小圆（`ps_world_view.gd:396`） | Godot 尾巴更「尖」 |
| 头部 | `R*1.12` 椭圆 + 4px 描边 + 径向高光（`render.js:766-786`） | `R*1.38` 圆 + 无描边（`ps_world_view.gd:490-505`） | Godot 头大且平 |

### 2.7 食物外观

- web：果冻球（radial gradient 三段）+ 2.5px 深描边 + 左上椭圆高光 + 近处才有的外发光 +
  5 种表情（含眨眼、wide 张嘴、tongue 吐舌、sleepy 眯眼）+ 金果旋转皇冠（`render.js:200-369`）。
- godot：烘图（发光 + 球体 + 描边 + 高光 + 皇冠都在图里）+ 2 种表情 + 竖向呼吸挤压
  （`ps_world_view.gd:269-280`）。
- 观感：Godot 食物更大更糊（发光烘焙进图、`size = 48*zoom`），脸只有「笑嘻嘻 / 眨眼」两种，
  金果没有皇冠摆动。**总体可辨认，但缺少网页那种「一屏 195 个各有表情」的热闹感。**

### 2.8 HUD 布局位置

| 元素 | web | godot |
|---|---|---|
| 数据卡 | 局内**不显示**（只在暂停层） | 左上 4 张（40,28 起，150×92，间距 12；`ps_hud.gd:539-545`） |
| 倒计时 | 界面带正中（`1fr` 栏，120px） | 屏幕正中偏上（y 24-120，48px；`ps_hud.gd:554-556`） |
| 名次 | 界面带右栏（96px + 「共 8 位玩家」+ ▲▼） | 时钟下方一行 22px（`ps_hud.gd:566-574`） |
| 镜像框 | 界面带左栏 320×180 + 速度条 + 1P 角标 | 无（系统 PiP 覆盖在 0.76-0.98 × 0.74-0.96，`main.gd:164-170`） |
| 排行榜 | 左下 DOM，前 3 + 我（`P/style.css:1129-1180`） | 右栏 8 行（`ps_hud.gd:650-671`），与增益 chip 同列 |
| 小地图 | 无（已删） | 左下 240×135（`ps_hud.gd:673-721`） |
| 输入状态 | 右上 `#statusbar`（小圆点 + 文本） | 右上 pill（`ps_hud.gd:580-589`） |
| 底部提示 | `#hint` + `#padBar` 键位条（`P/index.html:433-442`） | 只有一句「按 OK 暂停」（`ps_hud.gd:628-630`） |
| 暂停 | 全屏暗层 + 顶部「OPTIONS / 局内信息」+ 中部数据条（`P/index.html:238-269`） | 居中 520×380 卡片 + 3 个按钮（`ps_hud.gd:726-765`） |

### 2.9 结算布局

- web（`land-result3-20261112-010017.png`）：全屏深色背景 + **8 条真实蛇身立柱**，柱顶是 9 款 NPC 头；
  柱底一条彩色基线；下方一整条成绩带（无边框，仅 1px 分隔），每格「名次 / 名字 / N 节（玩家额外 吞/死）」；
  左上角「第 1 名 · 本局获胜！」+「最长 16 节」；底部居中一个绿色主按钮 + `A` 键帽 + 「按 A 或举手」。
- godot（`render-preview-settlement-1080p.png`）：左上一块「FINAL RESULTS / 长度赛」青条 + 62px「第 1 名」+
  两行小字统计；中间 8 根**矩形渐变柱**（顶上一个圆头 + 两只眼），柱间有 8 张圆角卡；
  右侧竖排「N 节」网格线标签；右上「镜头·最高者 / 视野 16 ~ N 节」卡片；
  底部两个大按钮 + 键盘提示文案（`render-preview-settlement-1080p.png` 里写的是
  「ENTER / 空格 再来一局 · ESC 返回标题」，与当前遥控器文案 `ps_stage.gd:229-232` 不一致 → 该图是旧代）。
- 差距等级：**大**。网页是「蛇比高」，Godot 是「条形图 + 卡片墙」。

### 2.10 开始画面

- web（`title-final-20261112-004643.png`）：居中玻璃面板（约 780px 宽），顶部品牌行，
  大号中文标题 + 绿点，副标题，4 个徽标，「游戏人数」两张大号选择卡（选中态绿边/绿字），
  「开始游戏」+「先用方向键玩」两按钮（带 A / X 键帽），资源状态行，三行细则，一行键位提示；
  面板外右上角常驻「直接开玩」。背景是**模糊的战场**。
- godot（`ship-30-final-mode-select.png`）：整屏背景（渐变 + 网格 + 装饰食物 + 绿/橙光斑），
  居中「• Pose Snake」112px + 中文副标题，两张大模式卡（人物图标 + 单人/双人 + 副标题 + 1P/2P 角标），
  一行遥控器提示 + 一行现场指引，右上「体感就绪」chip。**没有规则、没有徽标、没有键位、没有快速开玩。**
- 差距等级：中。结构都是「标题 + 两张卡」，但网页的信息层次（品牌/徽标/细则/键位）更完整，
  Godot 更「干净但空」。

---

## 3. 缺失的「屏」（web 有、Godot 没有）

按「是否值得移植」排序。每条给出 web 实现位置。

1. **手感调节面板**（12 滑杆 + 比赛模式下拉 + NPC 头开关 + 3 行实时读数 + 说明段）
   `P/index.html:272-370`，绑定与持久化 `P/js/main.js:404-760`。
   缺失影响：现场无法调「转向速度 / 速度区间 / 减速 / 加粗 / 复活静止 / AI 难度 / 失误 / 压迫」。
2. **体感诊断面板**（状态徽标 / 识别率 / 角度 / 距离 / 死区 / 可见性 / 控制手三按钮 / 日志条数）
   `P/index.html:373-397`，刷新 `P/js/main.js:527-562`，数据源 `P/js/pose.js:856-925`。
3. **玩法说明 accordion（10 条规则）** `P/index.html:524-542`。
4. **无尽练习模式选择** `P/index.html:343-349` + `P/js/main.js:1996-2012`。
5. **快速开玩 / 重连体感常驻按钮** `P/index.html:408` + `P/js/main.js:1795-1817`。
6. **体感日志录制/导出（JSON/CSV/清空 + L 快捷键）** `P/index.html:388-395`、
   `P/js/poselog.js:13-43,101-120`、`P/js/main.js:509-518,2051-2052`。
7. **启动阶段进度 + 可取消 + 看门狗** `P/js/main.js:1445-1560`（Godot 目前是「直接进模式选择 + 等待体感 chip」）。
8. **摄像头失败诊断页（9 类错误 + 修复建议 + 环境体检）** `P/js/main.js:1600-1676`、`P/js/diag.js:14-248`。
   浏览器专属，不建议移植（见 §6）。
9. **静音按钮 + M 键** `P/index.html:445-451`、`P/js/main.js:2047-2050,2064-2067`。
10. **键位提示条（padBar）** `P/index.html:436-442`（遥控器版应改写为 DPAD/OK/BACK）。
11. **状态栏（待启动/识别中/游戏中/已暂停/本局结束）** `P/index.html:402-405`、`P/js/main.js:1259-1262`。
12. **底部 hint 行（每次操作都有反馈）** `P/index.html:433`、`P/js/main.js:1288-1292`（Godot 无任何「操作反馈」文本）。
13. **镜像框内容**（实时视频 + 骨架叠加 + 四角取景框 + REC 点 + 距离→速度条 + 举手进度）
    `P/index.html:178-196`、`P/js/main.js:2339-2403`、`P/js/main.js:1199-1226`。
    Godot 只有系统 PiP 画面，**没有骨架叠加、没有速度条、没有举手进度**。
14. **结算头像**（摄像头裁头）`P/js/main.js:1056-1098`。
15. **「跳过演出」按钮** `P/index.html:462-464`、`P/js/main.js:1994`。
16. **战场边缘反馈**（四角 L 形取景框 + 四边暗角 + 顶部光带 + 分屏发光接缝）
    `P/js/render.js:1006-1045`、`P/js/main.js:2515-2517, 2568-2577`。
17. **双人 1P/2P 徽标**（镜像框上的 `cam-tag`）`P/index.html:184,226`、CSS `.cam-tag`。
18. **触摸转向 / 窗口失焦暂停** `P/js/main.js:2069-2110, 2112-2117`（设备不需要）。

反向：Godot 有而 web 没有的屏（不算缺口，但矩阵里要记）：
模式选择屏、READY 屏、COUNTDOWN/GO 屏、暂停菜单（三按钮）、F3 调试浮层、相机 variant toast
（`G/src/present/ps_hud.gd:206-213`）、系统 PiP 相机预览。

---

## 4. 已决策的「刻意分歧」（不要当 bug）

| # | 分歧 | 具体表现 | 文档出处 |
|---|---|---|---|
| D1 | **自撞不致死** | `cfg.collide.self_kill=false`；头穿自己身体是完整 no-op：不死亡、不计时、不散落食物、不记击杀、不给免疫、不发表现事件，连夹取都不做。`true` 可恢复网页规则（含 AI `self_hit` 宽容）。 | `G/src/core/config.gd:331-338`；`G/src/core/game.gd:613-620, 800-812`；`G/Docs/core-model.md:113-135`；测试 `G/tests/suite_collisions.gd` |
| D2 | **输入来自 Youdoo SDK 骨骼，不是 MediaPipe** | 18 关键点（COCO-18 / Youdoo-18 / Blaze33 自动探测），AIDL Binder 取帧；无 getUserMedia、无 WASM 模型、无 CDN。 | `G/Docs/WBS.md:4-21`；`G/src/present/ps_pose_input.gd:1-31, 255-311`；`G/src/youdoo_bridge.gd` |
| D3 | **相机预览是系统级 PiP 浮层（盖在应用之上）** | SDK `OverlaySurfaceView` + `TYPE_SYSTEM_OVERLAY`，位置 0.76,0.74,0.22,0.22（1P）/ 左右下角（2P）；不是全屏背景，也不是 Godot 贴图。 | `G/src/main.gd:150-214, 698-771`；`G/Docs/CAMERA-LIVE-EVIDENCE.md:82-141` |
| D4 | **菜单走遥控器** | 模式选择用 DPAD 聚焦 + OK 确认（无默认焦点）；暂停三选项；结算两选项；BACK 逐级返回；OK/BACK 的重复触发有 90ms 去重；原生 hook 把 RCU 的 gamepad 事件 canonicalise 成纯键盘事件。 | `G/src/main.gd:2005-2059`；`G/src/present/ps_remote.gd`；`G/Docs/REMOTE-INPUT.md` |
| D5 | **新增 READY + COUNTDOWN 两屏** | 参考 1024 项目：卡片式找人/举手准备、竖向进度条、绿色印章；保留 1.5s GO 开场。网页只有「局内举手 1s」。 | `G/Docs/FLOW-REFERENCE-1024.md:29-41, 78-98`；`G/src/main.gd:98-121, 1106-1145` |
| D6 | **设备档位（low-end）降规格** | Android 默认 `PROFILE_LOW_END`：食物 195→120、每批 8→6、散落 64→32、道具 7→5、粒子上限 1600→700。 | `G/src/core/config.gd:521-540`；`G/src/main.gd:422-423` |
| D7 | **确定性随机（xorshift32）取代 `Math.random`** | 同种子同输入逐字节一致；渲染/特效独立随机流；`PSRng` 内 `self.randf()` 修正全局 RNG 陷阱。 | `G/Docs/core-model.md:60-99`；`G/src/core/rng.gd` |
| D8 | **时钟口径改为模拟时钟** | 冻结/免疫/增益用 `time`，只有回合计时/复活/增益倒计时用 `real_dt`；网页用 `performance.now()`。 | `G/Docs/core-model.md:53-58, 104-106` |
| D9 | **AI 自撞宽容保留但已无玩法作用** | `ai.self_hit`（skip 12 / radius 0.45）只在 `self_kill=true` 时生效；`ai.self_avoid` 仍跑，但纯装饰。 | `G/Docs/core-model.md:119-124` |

---

## 5. 硬技术缺口与可行性

### 5.1 全屏摄像头背景（最难）

- 现状：SDK 的预览是**系统浮层，画在应用之上**（`TYPE_SYSTEM_OVERLAY` / `TYPE_APPLICATION_OVERLAY`），
  见 `G/Docs/CAMERA-LIVE-EVIDENCE.md:82-108`；因此「全屏」只会盖住战场，不能当背景。
- 取帧的唯一路径：`IGameServiceV1_0_3.getFrameBuffer(frameTimeMs)` 返回 **YUV420 HardwareBuffer**；
  Java 无 `HardwareBuffer` lock API，`Bitmap.wrapHardwareBuffer` 不接受 YUV；
  需要 **NDK + CMake 锁定 buffer → YUV→RGBA → 上传纹理**。本项目目前没有 NDK/CMake 构建步骤。
  证据：`G/Docs/CAMERA-LIVE-EVIDENCE.md:113-125`。
- 可行性：**L**（新工作流：Android NDK 模块 + JNI + 纹理上传 + 与画面同步；还要处理 30fps/1080p 的转换开销，
  Mali-G52 上建议先降到 640×360 再上屏）。
- 折中（**推荐先做**，S/M）：不动 SDK，把 PiP 放大成「左侧或右侧竖条 + 暗化 + 取景框」，
  视觉上接近网页的「摄像头在画面边缘」而不需要 NDK。网页本身也只是 320×180 的镜像框，**不是全屏**——
  全屏摄像头背景是「历史网页版」才有的东西，现行 `land-scape` 截图里并没有。

### 5.2 玻璃模糊（backdrop blur）

- 现状：Godot 4 GL Compatibility（`G/project.godot:30-37`）没有 `backdrop-filter` 等价物；
  面板全是 `StyleBoxFlat`（`G/src/present/ps_theme.gd:190-208`）。
- 可行方案：
  1. 用 `Viewport` 把战场渲染到 `ViewportTexture`，再在面板区域画一个「模糊采样」的 shader（真模糊，成本中等，需要 shader 与 mip 链）；
  2. 伪玻璃：2-3 层半透明渐变 + 顶部 1px 高光 + 内阴影（成本极低，视觉 70% 接近）；
  3. 直接改成不透明实底（当前的模式选择/READY 已这么做，观感干净）。
- 可行性：方案 1 = **M/L**（1080p 上对 GL Compatibility 的 mip blur 要小心带宽）；方案 2 = **S**。

### 5.3 emoji 字形渲染

- 结论：**不是问题，也不是方向**。两版的「表情」都是手绘几何/贴图，从来没有用系统 emoji 字体：
  web 见 `P/js/render.js:282-369`，Godot 见 `G/src/present/ps_assets.gd:138-173`。
- 若真要用 emoji 文本（不推荐）：需要彩色 emoji 字体（NotoColorEmoji）并处理 Godot 的彩色字体支持；
  在 Android 上还得处理字体回退。成本 **M**，收益低。
- 真正要做的是「补 3 种脸 + 眨眼 + 皇冠摆动」= **S**。

### 5.4 骨骼差异（18 vs 33 关键点）

- 现状：SDK 18 点（鼻子/眼/耳/肩/肘/腕/髋/膝/踝/胸），Godot 每帧校验布局并回退
  （`G/src/present/ps_pose_input.gd:26-31, 241-311`）；MediaPipe 33 点还有手部/脚部/脸部细点。
- 具体缺失：
  1. **无手部 21 点** → 不能做「握拳/张手」等手势（网页也没用，所以无损）；
  2. **无耳朵/鼻子精度** → 网页的结算头像是用 nose+ears 定位裁切（`P/js/main.js:1056-1098`），
     Godot 侧 SDK 的 `persons` 里有 `face` DetectBox（`G/Docs/WBS.md:16`），**可以用人脸框代替**，成本 **S/M**；
  3. **可见性分数可能全 0** → `ps_pose_input.gd:325-332` 已做兜底（`use_scores=false`）；
  4. **第三人称数量**：SDK 支持多人但槽位分配按镜像肩中点 x（`ps_pose_input.gd:177-192`），
     与网页的 MediaPipe 多 pose 分配逻辑不同（网页按画面左右 + `maxPoses`）。
- 可行性：**S**（已有布局自适应与诊断），风险点是某些盒子固件关键点顺序不同 → 已有 `_plausible()` 校验。

### 5.5 其它

| 缺口 | 说明 | 可行性 |
|---|---|---|
| 加色混合（`lighter`） | Godot 可用 `CanvasItemMaterial.blend_mode = BLEND_MODE_ADD`，但当前每个 `_draw()` 是一个 CanvasItem，要拆成独立 item 或改顶点色预乘 | **M** |
| 逐帧多层蛇身（网页 5 遍 stroke/node） | Godot 的 3 层三角带已是最优；若要「顶光偏移 + 弧形鳞纹」需在 band 生成时按法线偏移并画弧（弧不能批量 → 需换折线近似） | **M** |
| 真·逐节鳞片弧 | 用 `draw_multiline` 近似弧（每节 3-4 段），仍是一次 draw call | **S** |
| 摄像头帧 → 结算头像 | 同 5.1，若不做帧缓冲，可用 SDK 的 face box 做「占位头像」 | **S/M** |
| 历史最佳持久化 | `user://` + `ConfigFile`，5 行代码 | **S** |
| 静音 | `AudioServer.set_bus_mute(0, on)` + 一个按钮/遥控器键 | **S** |
| 体感日志导出 | 写 `user://poselog_*.csv` + logcat 一行路径；复用 `ps_pose_input.diag` | **S/M** |

---

## 6. 优先级建议（按「用户可感知收益 / 成本」）

### 第一梯队：视觉还原（不改规则、不改输入）

| 优先级 | 事项 | 工作量 | 会改的文件 |
|---|---|---|---|
| V1 | **HUD 改回「界面带 + 战场带」**：顶部 200px（1920 下）实底三栏带（镜像框占位 / 时钟 / 名次），战场下移；删掉 4 张数据卡、8 行榜、小地图移入带内或删除；分数卡直接删 | **M** | `G/src/present/ps_hud.gd`、`G/src/main.gd`（`_rebuild_views` / `_span_for` 用带高重算视野）、`G/src/present/ps_theme.gd` |
| V2 | **关键数字放大到 TV 尺寸**：时钟 120→（按 1080 缩放）至少 84-96px、名次 96/2≈56-64px，加 `text-shadow` 式辉光（用两层 `draw_string` 偏移实现） | **S** | `ps_hud.gd`、`ps_theme.gd`（新增 `text_glow()`） |
| V3 | **蛇头回到网页比例**：`hr = R*1.12`，补深色椭圆描边 + 径向高光；`R` 同步 | **S** | `ps_world_view.gd:477-582` |
| V4 | **蛇身细节**：高光带按法线**向上偏移** `R*0.36`；鳞纹改成弧线折线（每节 3 段）并向尾淡出；尾部收细 | **M** | `ps_world_view.gd:381-472`、`ps_theme.gd:264-306`（band 增加偏移参数） |
| V5 | **食物补 3 种脸 + 眨眼 + 皇冠摆动** | **S** | `ps_assets.gd:128-180`、`ps_world_view.gd:254-280` |
| V6 | **结算改成「蛇身立柱」**：列体用同一条 band 渲染（rap），顶部用 `_draw_npc_head` 缩小版；成绩带改成无边框分隔条并与列对齐 | **M** | `ps_stage.gd`（重写 146-208）、`ps_world_view.gd`（导出头部绘制函数） |
| V7 | **战场取景框 + 暗角 + 分屏发光接缝** | **S** | `ps_world_view.gd`（新增 `_draw_arena_overlay`）、`main.gd`（2P 接缝） |
| V8 | **免疫虚线环 / 待命文字 / 磁铁渐隐圈** | **S** | `ps_world_view.gd:492-528` |
| V9 | 面板加角标线 + 提高边框对比（伪玻璃） | **S** | `ps_theme.gd:190-208` |

### 第二梯队：屏/功能补齐（不改规则）

| 优先级 | 事项 | 工作量 | 会改的文件 |
|---|---|---|---|
| S1 | **静音**（遥控器键 + chip） | **S** | `ps_audio.gd`、`main.gd`（`_dispatch_action`）、`ps_hud.gd` |
| S2 | **历史最佳持久化** | **S** | `game.gd`（或新增 `src/core/store.gd`）、`main.gd` |
| S3 | **玩法说明屏**（标题下折叠页或 READY 前的一页），文案搬 `P/index.html:527-539` 并修正「0.3s→0.5s」等 | **S** | `ps_hud.gd`（新 `_draw_rules`）、`main.gd`（新 `MODE_HELP` 或选择屏内翻页） |
| S4 | **无尽练习开关**（调试面板或模式卡第三项） | **S** | `main.gd`、`ps_hud.gd`、`config.gd:310` |
| S5 | **调参面板（遥控器可操作）**：8 项核心（转向/速度上下限/减速强度/加粗/复活静止/AI 难度/失误/压迫），左右调值、上下换项 | **M** | 新 `src/present/ps_tuning_panel.gd`、`main.gd`、`ps_remote.gd` |
| S6 | **体感诊断页（READY 屏第二页）**：识别率/距离/角度/死区/控制手/帧龄/persons，数据全部现成（`pose.diag`） | **S** | `ps_hud.gd`、`main.gd`（把 `pose.diag` 传进 hud） |
| S7 | **体感日志**：20Hz 采样 + 跳变补记 + `user://poselog.csv` + logcat 路径；F9 导出 | **M** | 新 `src/present/ps_poselog.gd`、`main.gd` |
| S8 | **镜像框信息**：PiP 旁边/下方补「距离→速度」条与举手进度（PiP 内部画不了，只能在附近画） | **S** | `ps_hud.gd`、`main.gd` |
| S9 | **文案修正**：8 个 AI → 7 个 AI；结算双人名次；删「视野 16 ~ N 节」 | **S** | `ps_hud.gd:284`、`ps_stage.gd:103-111,236-239` |
| S10 | 「跳过演出」+ 结算按钮在生长中禁用 | **S** | `ps_stage.gd`、`main.gd`（`_act_settle`） |

### 第三梯队：音频 / 特效

| 优先级 | 事项 | 工作量 | 会改的文件 |
|---|---|---|---|
| A1 | **音效只在「自己的事件」触发**（网页 `own` 语义）：`fx`/`audio` 调用加 `ev.own` gate | **S** | `main.gd:1382-1408` |
| A2 | 击杀 / 被吃 / 拾取补「噪声爆破 + 低通」层（Kill/Death 用锯齿下坠 + 噪声），重烘 6 条音 | **S/M** | `ps_audio.gd:29-34,51-76` |
| A3 | **粒子补齐**：重力、五角星、spark 拖尾、数量 34+26（低端档可 0.6×）、上限 1600 | **M** | `ps_fx.gd:116-154`、`config.gd:433-436` |
| A4 | **双层冲击波 + 缓动 + 爆炸星** | **S** | `ps_fx.gd:182-198`（新增 `star` 字段与绘制） |
| A5 | **推镜（zoom pulse）+ hit-stop**：`fx.zoom` 乘到绘制 scale，`hit_stop` 缩 `dt` | **M** | `main.gd:539,1187-1219`、`ps_world_view.gd`（zoom 已支持） |
| A6 | 加色混合层（火花/光晕） | **M** | `ps_fx.gd`、`ps_world_view.gd`（拆独立 CanvasItem 或顶点预乘） |
| A7 | 全屏闪白按 impact 档位（0.09/0.22/0.48/0.55） | **S** | `main.gd:1394-1406`、`config.gd:411-437`（已有档位表但未用） |

### 第四梯队：摄像头背景（独立工作流）

| 优先级 | 事项 | 工作量 | 会改的文件 |
|---|---|---|---|
| C1 | 放大 PiP + 暗化 + 取景框（无 NDK 的折中） | **M** | `main.gd:164-214`、`ps_hud.gd`、`ps_world_view.gd`（可选：背景暗化） |
| C2 | NDK YUV→RGBA 通路 + 纹理上屏（真·全屏背景） | **L** | 新 `android/**` NDK 模块、`youdoo_bridge.gd`、`ps_world_view.gd` |
| C3 | 用 SDK face box 做结算头像 | **S/M** | `ps_pose_input.gd`、`ps_stage.gd` |

### 第五梯队：验证

| 优先级 | 事项 | 工作量 | 会改的文件 |
|---|---|---|---|
| T1 | 把「表现快照」纳入自动化：`--capture` 之外增加 `--capture-hud/--capture-settle` 固定真值图，对比首帧/关键帧 | **M** | `main.gd`（capture 分支）、新 `tools/compare_shots.ps1` |
| T2 | 新增 `tests/suite_presentation.gd`：断言 HUD 文本（"3×3 地图"、名次格式）、结算列数/列宽、食物 face 覆盖 5 种 | **S** | `G/tests/**` |
| T3 | 手感回归：把网页 `tools/measure.mjs`、`ai-loop-check.mjs` 的指标（自撞率 / 平均长度 / 进食量）在 Godot 侧复跑 | **M** | `G/tests/**`、新 `tools/measure.gd` |
| T4 | 设备侧只读验收清单：`DEVICE-REPORT.md` 增补「表现」小节（截图点位 + 通过标准） | **S** | `G/Docs/DEVICE-REPORT.md` |

---

## 7. 我建议 **不要** 照搬的网页实现

| 项 | 为什么不要照搬 |
|---|---|
| 1. 网页的逐帧 canvas 蛇身（5 遍 stroke + 逐节弧 + shadowBlur） | 这正是 WebView 壳在盒子上 1.5fps 的根因（`G/Docs/WBS.md:8-10`）。要还原的是**观感**（多段渐变/描边/顶光/弧形鳞纹），实现必须留在 Godot 的批量三角带上。 |
| 2. 12 项实时滑杆 + `localStorage` 持久化 | 盒子上只有遥控器，滑杆不可达；而且这些值应该由产品定（`config.gd` 已是唯一真相源）。真需要现场调参，做「上下换项 / 左右调值」的 8 项面板即可。 |
| 3. 浏览器启动看门狗 / 模型 CDN / `diag.js` 九类相机错误 | 全部是 `getUserMedia` + MediaPipe WASM 的产物；SDK 路径没有这些失败模式。保留等价物即可（bridge `bound/frames/age/error` 已在 HUD）。 |
| 4. 体感日志的「浏览器下载」UI | `Blob + <a download>` 在 Android 上没有落点。改成写 `user://` + logcat 打印路径，或用 `adb pull` 取。 |
| 5. 触摸拖拽 / 鼠标转向 / 手机视野公式 / 手机键位条 | 设备是 1920×1080 电视盒子 + 遥控器 + 体感；这些分支在盒子上永远不触发，只会增加维护面。桌面调试用现有的键盘兜底就够了。 |
| 6. 「分数 / 最佳」两张数据卡 | 网页已经把积分制删了（`P/index.html:258-266` 视觉隐藏，`P/js/main.js:907-915` 只更新不展示）。Godot 把 legacy `score` 摆到第一张卡上是**把已废弃的指标重新变成主视觉**，应删。 |
| 7. 小地图（如果目标是 1:1） | 现行网页版**没有小地图**（`drawMinimap` 是死代码）。但从「9 屏大地图找不到食物」的玩法角度，Godot 的小地图是**改进**——建议保留，只是别把它当成「网页有、我们缺」的缺口。 |
| 8. 8 行实时排行榜 | 网页刻意只给「前 3 + 我」，因为 8 行会盖住战场。若保留 Godot 的 8 行，应放进界面带或暂停层，而不是叠在战场上。 |
| 9. 全屏摄像头背景（作为「必做项」） | 现行网页版自己也只是界面带里的 320×180 镜像框（`land-scape` 截图可证）。全屏背景是**更早的历史版本**，且需要 NDK（§5.1）。建议按 C1 折中做，把 C2 当成独立立项。 |
| 10. `play.html` 单文件构建 / 自举急救条 / 服务端脚本（`serve.py`、`start.bat`、`tools/cdp.mjs`） | 纯 Web 交付形态，与 APK 无关。 |

---

## 8. 一句话结论

- **规则层已经对齐**（`G/Docs/core-model.md` + 404 条断言），要补的不是玩法，是**表现**。
- 感知差距最大的三件事：**① 没有界面带（HUD 压战场）② 蛇头/蛇身/结算的「卡通细节」降级 ③ 关键数字太小**。
- 功能缺口里最该补的三件事：**静音、历史最佳持久化、规则/诊断页**（都便宜）。
- 最贵的两件事：**全屏摄像头背景（NDK）** 与 **玻璃模糊（shader 或伪玻璃）**；
  前者建议先做折中版，后者建议直接做伪玻璃。
