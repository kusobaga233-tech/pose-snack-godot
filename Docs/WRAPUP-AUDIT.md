# WRAPUP-AUDIT — 基础功能缺口 + 性能压力测试（2026-11-14）

范围：`src/present/**`、`src/main.gd`、`scenes/**`、`Docs/**`、`tools/verify_release.ps1`（只加新守卫）。
未改动：`src/core/{game,snake}.gd`、`android/**`、`export_presets.cfg`、`project.godot`、`tests/**`。
**构建专用**：本文件与本次改动全程没有跑 adb、没有碰 Android 盒子（`Docs/DEVICE-POLICY.md`）。

图例：**必须** = 出货游戏缺了会被玩家当 bug；**应该** = 该有、但不至于退货；**可选** = 锦上添花。
工作量：S ≤ 半天、M ≤ 2 天、L > 2 天。

---

## Phase A — 玩家视角功能缺口表

| # | 功能 | 现状 | 缺什么 | 是否必须 | 工作量 | evidence（改动前 path:line） |
|---|---|---|---|---|---|---|
| A1 | 静音 / 音量 | 声音只有 `PSAudio.enabled`（“宿主有没有 audio bus”），**没有任何静音状态、没有可见控件、不持久化** | 玩家无法关声音；关掉也不会记住 | 必须 | S | `src/present/ps_audio.gd:11`（`var enabled`）、`:37`（`play()` 只看 enabled）；HUD 无入口 |
| A2 | 最佳成绩持久化 | `PSGame.best_length` 只在内存里（注释明说“persistence lives outside the core”），`ConfigFile` 里只有 `[skin] player`；`cfg.round.best_length_key` 定义了却没人用 | 重启后“最佳”回到 16；结算的“历史最长”是假的 | 必须 | S | `src/core/game.gd:90-91`、`src/core/round_result.gd:26-27`、`src/present/ps_skins.gd:197-218`（只存 skin）、`src/core/config.gd:314`（key 未用）、`src/present/ps_hud.gd:1624`（分数行 BEST 只显示内存值） |
| A3 | 无尽模式入口 | 规则层支持（`timed` / `endless`），但**只有构建期关闭的调试面板**能切；正常 UI 没有入口，`cfg.round.mode` 永远 `timed` | 玩家见不到“无尽练习” | 应该 | S | `src/core/config.gd:310-311`、`src/core/game.gd:445,1301`、`src/present/ps_tuning_panel.gd:176-177`（唯一入口，`PSBuild.TUNING_ENABLED=false` 时脚本都不加载，`src/main.gd:981-995`） |
| A4 | 规则 / 玩法说明 | 只有选人界面底部一行 18 px 小字“玩法与操作说明 · 举手转向，手伸远加速” | 没有一屏可读的玩法（目标/转向/加速/进食/死亡/道具/赛制/遥控器） | 必须 | S | `src/present/ps_hud.gd:1069-1071`（唯一一行） |
| A5 | 2P 相机框 | 2P band 的两个 mirror box 传 `show_frame=false`，**只画空底板 + 边框**，没有相机像素也没有骨骼 | 分屏时两个玩家看不到自己的镜像 | 必须 | S | `src/present/ps_hud.gd:618-619`（`_draw_cam_cell(..., false)`）、`:714-721`（`if show_frame and cam_rgba_tex != null`） |
| A6 | 暂停统计 | 暂停条只有 3 格：长度 / 吞并 / 最长；`_draw_play()` 在暂停时跳过整排“分数/长度/吞并/最佳” | 暂停后**分数和名次都消失**（分数只在这一排里） | 应该 | S | `src/present/ps_hud.gd:1833-1861`（`_pause_cell(0..2)`）、`:1565`（`in_play` 跳过分数行）、`:1618-1624`（分数行内容） |
| A7 | 结算 | 有排名、8 行 lane（名次/名字/风格/长度/吞并/死亡）、两个按钮（再来一局 / 返回模式选择）、BACK 也能回 | “本局最长”和“历史最长”**同一个字段打印两次**，结算把本局峰值说成历史最佳 | 应该 | S | `src/present/ps_stage.gd:116-124`（两次都用 `result.best_length`） |
| A8 | 局内退出 / 返回 | play → OK/BACK → pause；pause → 返回模式 → `_enter_select()`；结算 → BACK → 模式选择。全链路可用 | 无（验证过） | 必须 | — | `src/main.gd:5576-5580`（play→pause）、`:5721-5745`（pause 三项）、`:5758-5774`（settle）、`:1749-1772`（`_enter_select`） |
| A9 | 存档 | 只存 `[skin] player` 一个值 | 最佳 / 音效 / 赛制都不存；“上次模式”也没存 | 必须 | S | `src/present/ps_skins.gd:197-218`、`src/main.gd:906-910`（boot 只恢复 skin） |

### 本次已实现（全部 S，全部在“必须/应该”内）

| # | 做了什么 | 入口 / 关键符号 | 证据 |
|---|---|---|---|
| A1 | 静音状态 + 可见控件 + 持久化：`PSAudio.muted` + `set_muted()`；模式选择底部“音效 开/关”chip（远程 LEFT/RIGHT/OK 都能切），写 `[audio] muted` | `ps_audio.gd:22,50,60`；`ps_hud.gd:1203`（options bar）、`:1226`（chip）；`main.gd:6098`（`_toggle_audio`）、`:338-346`（focus slots 3/4/5） | `evidence/flow-01-mode-select.png`（chip 行）、`--capture-flow` 日志 `[audio] SFX ...` |
| A2 | 最佳成绩持久化 `[round] best_length`：`_apply_best_length()` 在每次 `game.reset()` 后回填，`_save_best_length()` 在结算和“返回模式”时写盘（只在变大时写） | `ps_settings.gd:81`（`record_best`）、`main.gd:2147` / `:2156` | 真实运行日志 `[settings] new best length=N -> user://pose_snake.cfg`；验证跑打印 `(harness: not written)` |
| A3 | 赛制入口：模式选择底部“赛制 限时 2:00 / 无尽练习”chip，写 `[round] mode`，直接改 `cfg.round.mode`（规则层本来就读它）；无尽时 band 的时钟显示 `--:--` + “无尽练习” | `ps_hud.gd:684,694`；`main.gd:6112`（`_cycle_round_mode`） | `evidence/flow-01-mode-select.png`（chip）、`--endless` 启动参数 |
| A4 | 一屏“玩法说明”（8 条：目标/转向/加速/进食/死亡/道具/赛制/遥控器），OK 或 BACK 关闭，打开时吃掉所有方向键 | `ps_hud.gd:1245-1316`（`_draw_help`）、`main.gd:6122`（`_open_help`）、`:5590-5600`（help 优先路由） | `evidence/help-1920.png` |
| A5 | 2P band 两个 mirror box 现在真的画相机像素 + 各自的骨骼（每个玩家自己那一半，规则同 READY 卡与 `CAMERA_2P_SRC`） | `ps_hud.gd:659-661`（2P 传各自 UV + slot）、`:762-775`（`_draw_cam_cell(host_uv, skel_slot)`） | `evidence/cam-2p-band-1920.png`（`--capture-cam2p`，两块都有画面+骨骼） |
| A6 | 暂停层把“分数/长度/吞并/最佳”这一排重新画在 scrim 之上（暂停条仍是 web 对齐的 3 格） | `ps_hud.gd:2036`（`_draw_pause` 里 `_draw_score_row()`） | `evidence/b2-pause-1920.png`（左上四格仍在） |
| A7 | 结算数据修正：“本局最长”= `me.peak_length`，“历史最佳”= `result.best_length`（持久化后的值） | `ps_stage.gd:115-128` | `evidence/b2-settle-1920.png` |
| A9 | 新增 `PSSettings`（`user://pose_snake.cfg` 的 `[audio]/[round]` 段），写之前先 load，绝不覆盖 `[skin]`；验证跑 `harness=true` 时读写全禁（否则两次确定性截图会因为第一次写下的 best 而不同） | `src/present/ps_settings.gd:1-92`、`main.gd:845-862` | `%APPDATA%\Godot\app_userdata\PoseSnake\pose_snake.cfg`（验证跑后 mtime 不变） |

### 没做（留给 owner 决策，M/L）

| # | 项 | 为什么不做 | 建议 |
|---|---|---|---|
| L1 | 暂停框改成 1024 参考的 1148×556 弹框 + 3 个 247×196 图标键（`Docs/UI-REFERENCE-1024.md` §0.4 明说这是“结构差异”，web 版没有这块） | 属于重做暂停层，动 web 对齐元素 | owner 先定“要不要 1024 那种大框” |
| M2 | 结算加“本局得分/名次变化趋势”，以及 ResultForm 的 6 s 倒计时自动回主页 | 需要规则层给 `RoundResult` 加字段（`src/core/**` 不在本工单） | 需要 coordinator 改 core |
| L2 | 选人界面按 1024 参考改成“logo + 两张 342×138 模式卡”的宽屏布局 | 已明确被 owner 否过一次（`ps_hud.gd:168-171`） | 不动 |
| M3 | 音量分级（音乐/音效分开）+ 遥控器音量键 | 目前根本没有 BGM，分轨没有意义 | 有 BGM 之后再说 |

---

## Phase B — 压力测试 + 优化（owner 优先级：帧数）

### 最坏场景定义（`--capture-stress`，实测脚本化）

`src/main.gd:4737-5120`（`_capture_stress_tick` / `_stress_stage`），**实时**跑（不加 `--fixed-fps`），1920×1080：

- **8 条蛇 × 240 节**（`STRESS_CAPS = [240, 120]`）。240 节是 120 节 girth 上限的 2 倍，也是真实 2 分钟局峰值（约 100–150）的 ~2 倍；每条蛇按 18 px 间距铺 4320 px 长的正弦weave（振幅 300 px、波长 1200 px，约 0.05 rad/节点），**蛇身首尾都在画面外**——这正是实际长蛇的样子，也是“整条蛇按包围盒全量构图”的真实代价。
- **食物铺到上限**：`food.target_count 195 + trim_extra 70 = 265` 颗（`_stress_stage` 用 `game.foods.append(game.random_food())`）。
- **道具铺到上限**：`powerups.target_count = 7`。
- **FX 池每帧灌满**：220 粒子 / 16 漂浮字 / 8 冲击波（`_stress_fx_saturate`，每帧 60 粒子 + 3 字 + 1 波，高于衰减率）。
- **8 条蛇全部挂加速 buff**（多一层 aura 四边形 + 暖色叠加层）。
- **相机取到本 build 能开的最广视界**：span 是按人数写死的（`CAM_SPAN=900`，2P ×1.5），zoom 因此固定 0.98（1P）/ 0.652（2P）——这就是“最大拉远”。
- **常驻性能面板 ON**（出货默认，owner 要求），另跑一段 OFF 的窗口把面板自身成本单独量出来（`[stress] nofxpanel`）。
- **相机画面照样在**：一条 576×324 合成帧 + 每个玩家槽位的骨骼，每帧走真实管线（盒子上的实际状态）。
- 规则层在 `STATE_COUNTDOWN` 停住（`game.update()` 直接 return），所以窗口里没有人吃东西/死亡，帧成本稳定可复现。

测量模式：默认**保持出货状态**（`Engine.max_fps=60` + vsync），另加 `--stress-uncapped` 关 vsync 看真实单帧成本。`[stress]` 行里的 `ms/p95` 用**墙钟帧间隔**（`_process` 的 delta 被 clamp 到 100 ms，不能拿来做帧时间）。

### 前测 → 后测（同一台 PC，RTX 5060，1920×1080，出货 vsync 模式）

| 场景 | 版本 | fps avg | ms | draw | prim |
|---|---|---|---|---|---|
| 1P cap=240 | 改动前（原始代码） | 36.7 → 60 打不满 | 27.3* | 201 | 43 282 |
| 1P cap=240 | **改动后** | **60.0**（锁 60，p95 16.9 ms） | **12.2**（uncapped 时 81.8 fps） | **169** | **18 020** |
| 2P cap=240 | 改动前（原始代码） | 41.0 | 24.4* | 354 | 32 518 |
| 2P cap=240 | **改动后** | **53.0**（p95 21.9 ms，21/144 帧 >20 ms） | **18.9**（uncapped 时 52.7 fps） | **280** | **29 982** |
| 1P cap=120 | 改动前 | 59.6 | 16.8* | 199 | 29 886 |
| 1P cap=120 | 改动后 | 60.0 | 11.2 | 168 | 18 280 |
| 2P cap=120 | 改动前 | 45.2 | 22.1* | 354 | 37 736 |
| 2P cap=120 | 改动后 | **56.9** | 17.6 | 279 | 30 076 |

\* 改动前的 `ms` 列不可信（第一版测量用了被 clamp 的 delta，最大只能读到 100 ms），因此改动前以 `fps avg` 与 `draw/prim` 为准；改动后新增墙钟测量。
瓶颈定位（改动前，cap=240 单帧 CPU，来自 `[stress] prof`）：`world.band` 13.0 ms、`world.collect` 3.5 ms、`world.halo` 3.4 ms，HUD 全部合计 0.6 ms、常驻性能面板 0.04 ms。

### 优化项与收益（每一项都实测）

| # | 优化 | 位置 | 收益（cap=240，2P / 1P） | 视觉 |
|---|---|---|---|---|
| B1 | **画面外切片裁剪**：四个 band appender 多收一个 `vis` 屏幕矩形，切片两端都在框外就整片不构图（框比画面大 96 px，被裁掉的永远在屏幕外） | `ps_theme.gd:986-995`（`_slice_vis`/`vis_rect`）、`band_rim_append/band_tex_append/band_halo_append/band_stack_append` 的 `vis` 参数；`ps_world_view.gd:762,994` | band 13.0→5.7 ms（1P），halo 3.4→1.6 ms；**1P 帧 27.3→14.0 ms** | 无（裁掉的像素本来就在屏外） |
| B2 | **可见索引段裁剪**：`_collect_snakes` 记下落在裁框内的首/末索引；若可见点恰好连续（`inside == i1-i0+1`），dense 身体只对该段加密（ramp 仍用全局 `t`，颜色不变）；蛇身出画面再进来（不连续）则整条照旧构建，不出洞 | `ps_world_view.gd:853`、`:880`（`_build_dense_body(i0,i1)`） | collect 3.5→1.8 ms（1P/2P 一样） | 无 |
| B3 | **大食物按层合批**：原来每颗大食物 flush 一次 + 3 次独立 blit（265 颗食物里 ~21 颗大食物 ≈ 85 draw call），改成 4 个图层各一次（body/crown/face-open/face-shut） | `ps_world_view.gd:512-651`（`_draw_food` + `_big_*`） | draw −80/视野；1P 201→196 | 两颗**互相重叠**的大食物从“逐颗覆盖”变成“层覆盖”（30 px 圆盘，极少见） |
| B4 | **道具合批**：每个道具原来 3 次画（旋转环 + 徽章 + 文字），环与徽章各合成一层 | `ps_world_view.gd:_draw_powerups` | 7 个道具 21→3 draw call/视野 | 无（同层顺序不变） |
| B5 | **冲击波合批**：8 个 `draw_arc` 换成一次 `draw_multiline_colors` | `ps_fx.gd:383-421` | −7 draw call/视野 | 环线宽度统一为 2.2 px×zoom（原来随各自生命值变细） |
| B6 | **轮廓羽化关闭**：rim 的 1.2 px alpha 羽化是每切片 2 个四边形（rim 几何的一半） | `ps_world_view.gd:66`（`RIM_FEATHER := 0.0`）、`ps_theme.gd:768`（`feather` 参数） | band 3.7 ms/视野（2P 合计 −2 ms），2P 40→47 fps 的那一步 | **有**：蛇身轮廓对地板的 1 px 柔边没了（1080p 下基本看不出） |
| B7 | **漂浮字池 24→16** | `ps_fx.gd:17` | −8 draw call/视野（2P −16），这是 2P 331→312 的关键 | **有**：同屏最多 16 条 YUMS（原来 24） |
| B8 | **`band_stack_append` 顶点上限不再丢蛇**：撞到共享 65000 上限时由调用方 flush 后重试，而不是整条蛇不画 | `ps_theme.gd:618`（`last_capped`）、`ps_world_view.gd:_draw_body_stack` | 正确性（8×240 原来会静默丢身体） | 修复（本来该画的现在画出来） |

关掉羽化 + 字池之后，2P 从 331 draw/19.9 ms 走到 **280 draw/18.9 ms**，第一次越过 50 fps 线。

### 硬指标结果

| 指标 | 目标 | 实测（出货 vsync 模式） | 结论 |
|---|---|---|---|
| 1P 最坏帧率 | 60 fps | **60.0 fps**（p95 16.9 ms；uncapped 81.8 fps = 12.2 ms/帧，留 4.4 ms 余量） | PASS |
| 2P 最坏帧率 | ≥ 50 fps | **53.0 fps**（18.9 ms；uncapped 52.7 fps） | PASS（余量薄，见下） |
| 1P draw | ≤ 200 | **169** | PASS |
| 2P draw | ≤ 300 | **280** | PASS |
| 常驻性能面板成本 | 可接受 | **0.03–0.05 ms / 3–4 draw call**（`[stress] nofxpanel` 对比） | 保留默认 ON |

**盒子（Mali-G52）映射**：这台 PC 是 RTX 5060 级独显，Mali-G52 MP2 的填充率/带宽大约差一个数量级，CPU（GDScript 构图）也要慢 3–5 倍。1P 12.2 ms 里约 9 ms 是 GDScript 构图（`world.band 4.2 + collect 2.4 + halo 1.4 + 其它`），所以按 3–5× 估算，盒子上 1P 最坏场景约 35–60 ms（17–28 fps），2P 更差。**“60 fps on the box at 8×240” 做不到**，而且这不是渲染功率问题，是 GDScript 每帧重建 ~1900 个 dense 点的几何。真实局（1 条长蛇 + 7 条 16–40 节）只有这里 1/4 的可见长度，盒子上是另一条曲线；盒子上要确认的是真实局，不是这个合成最坏场景。

**如果要盒子也扛住合成最坏场景**，需要的是“低配特效”开关（不做静默降级）：
`--lowend` 已经存在（`cfg.apply_device_profile(PROFILE_LOW_END)`，食物 120 / 道具 5 / 粒子 700）。
建议再加一档“低配 FX”（默认关、owner 可开）：关 halo 第二层 + rim 只留内侧 + 粒子 220→120 + 漂浮字 16→8，
预计 1P 构图再降 40%。**本次没有实现这个开关**，因为桌面 1P/2P 目标已经达到，且它会改变画面。

### 回归守卫（`tools/verify_release.ps1` 新增第 9 项）

`[9/9] Stress guard`：跑
`--capture-stress`（1P）与 `--capture-stress --capture2p`（2P），1920×1080，**不加** `--fixed-fps`，
读 `[stress] leg=<n>p cap=240 ... draw=D ... fps_avg=F`：

- **FAIL 条件**：`2P cap=240 draw > 300` 或 `2P cap=240 fps_avg < 45`；或 `1P cap=240 draw > 200` 或 `1P fps_avg < 50`；或任一条 `[stress] leg=...cap=240` 行缺失。
- 为什么 fps 门槛取 45（而不是刚测到的 53）：一台正在跑其它事的 CI/开发机，帧率抖动 ±15% 是常态，53→45 留了 15% 噪声余量，同时仍能在“退回优化前（41 fps）”时报警。1P 取 50（实测 60，留 17% 余量）。
- 为什么用 `fps_avg` 而不是 `fps_min`：`fps_min` 是单帧最差（1000/max ms），一次 GC 抖动就会假报警；`p95` 仍然打印在证据里供人看。

最终门禁（`evidence/release-gate-20261114-191720.txt`，**RESULT: PASS**）：1 parse 51/51、2 boot stderr 0 B、
3 suite 448/0、4 资源、5 渲染 7/7、6 perf 1P draw=120 / 2P draw=202、7 determinism 10/10、8 皮肤、
9 **stress 1P 169 draw / 60.0 fps / p95 16.9 ms；2P 280 draw / 54.6 fps / p95 20.3 ms**。

### 盒子上的验收动作（给 owner，不需要我动盒子）

1. 装包后自己启动（按 `Docs/DEVICE-POLICY.md`：只装不启动）。
2. **双人模式**跑满一局 2 分钟，右下角常驻性能面板（默认 ON）盯着 `fps` / `frame ms` / `draw calls` / `primitives`。
3. 按顺序做这四个最坏点，每个点记一次面板数字（`fps` 与 `draw`）和当时的 `长度`：
   a. 分屏 + 三个人以上长过 80 节；
   b. 吃 加速 道具并连续转向（相机 + boost aura 同时动）；
   c. 一次吞并/死亡（粒子 + 冲击波峰值）；
   d. 把蛇贴到墙角（墙体脉冲 + 相机 clamp）。
4. 对照：F10（或遥控器 INFO 连按两次）关掉面板再跑同一段，比较 `frame ms`（面板本身约 0.03–0.05 ms，应当看不出来）。
5. 顺带确认 **2P band 两个 mirror box 都有实时画面 + 骨骼**（这次修的就是这个），以及选人界面底部三个 chip：
   「玩法说明 / 音效 / 赛制」可用方向键选中、OK 生效、重启后音效与赛制保持。
6. 如果 1P 真实局在盒子上掉到 45 fps 以下，请把那一帧的面板数字 + 模式 + 长度回报，我再按
   “低配 FX 开关”方案给数值（不是静默降级）。
