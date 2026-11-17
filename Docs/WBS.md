# Pose Snake → Godot 4.6 移植：任务分解与状态

更新时间：2026-11-12 14:25（Asia/Shanghai）
目标：Godot 原生 APK，**动作识别基于 YoudooGame SDK**（不是 MediaPipe / 网页版）。

## 0. 结论先说：这条路已跑通关键环节

之前 WebView 壳方案卡在真机 1.5fps（Chromium 每帧约 8000 次 canvas 绘制调用，软件光栅化），
根因是网页版渲染量太大，不是链路不通。改 Godot 原生 2D 后渲染走 GPU；
同时 SDK 的**骨骼数据来自 AIDL Binder 服务，Godot 已成功直连**：

```
app ──bindService──> com.sdt.game.service.SdtGameService
                       action: com.sdt.game.service.IGameServiceV1_0_3
                        └─ registerFrameInfoCallback → onFrameInfoEvent(FrameInfo)
                             ├ persons / lHand / rHand / face → DetectBox{RectF, score, KeyPoint[]}
                             └ KeyPoint{x, y, z, score}
```

证据：`YoudooAndroidLibrary-release.aar` 内含 `classes.jar`（`com/sdt/game/service/*`）与 `aidl/`；
签名由 `javap` 逐条确认；参考实现见 SDK 自带 `Tools~/Android/SkeletonBridge`。

## 1. 环境（已就绪）

| 项 | 值 |
| --- | --- |
| Godot | `D:\godot-proj\Godot_v4.6.3-stable_win64.exe` |
| 导出模板 | `%APPDATA%\Godot\export_templates\4.6.3.stable`（含 `android_source.zip` → `libs/*/godot-lib.template_*.aar`） |
| JDK / SDK | `D:\android_tc\jdk`、`D:\android_tc\sdk`（platforms 35/36，build-tools 35.0.0/36.1.0） |
| 签名 | 复用 `%USERPROFILE%\.android\debug.keystore`（alias `androiddebugkey` / 密码 `android`）——**本机 keytool 被安全软件拦截，不能新建 keystore** |
| 设备 | `D:\platform-tools\adb.exe`，HP52S0-Youdoo，Android 11/SDK30，arm64-v8a，1920×1080@320dpi，Mali-G52 |
| 设备注意 | 屏幕会休眠 → `svc power stayon true` + `KEYCODE_WAKEUP`；`com.youdoo.settings` 的“遥控器失联”浮层会抢焦点 → `am force-stop com.youdoo.settings` |

## 2. 任务分解与状态

| # | 工作流 | 负责人 | 产出 | 状态 |
| --- | --- | --- | --- | --- |
| A | **SDK 桥**：Godot Android 插件绑定 AIDL，GDScript 读骨骼 | 子 agent A | `android/**`、`src/youdoo_bridge.gd`、APK + 真机证据 | ✅ 已验证 |
| B | **玩法内核**：蛇/食物/碰撞/回合计时/排名/AI，纯 GDScript + headless 测试 | 子 agent B | `src/core/**`、`tests/**`、`Docs/core-model.md` | ✅ 404 断言全绿（18.4s） |
| C | **表现层**：原生 2D 渲染（蛇身/食物/蛇头脸/相机/HUD/结算舞台/特效）+ 输入接线 | 子 agent C | `src/presentation/**`、`scenes/**` | 🔄 进行中 |
| D | **集成与验收**：APK 集成、真机帧率、体感联调、稳定性 | 主控 | 验收报告 + 截图 | ⏸ 等 C |

工程骨架（主控）：`project.godot`（GL Compatibility，1920×1080 canvas_items）、`export_presets.cfg`
（Android gradle、arm64、minSdk 30、targetSdk 35、包名 `com.youdoo.posesnake`）、`scenes/main.tscn`、`src/main.gd`。

### A 的真机证据

`evidence/device-logcat.txt`：

```
YoudooSkeleton: start(): bindService=true (requested com.sdt.game.service.IGameServiceV1_0_3)
YoudooSkeleton: connected com.sdt.game.service/.SdtGameService descriptor=...V1_0_3
YoudooSkeleton: frame callback registered on IGameServiceV1_0_3
YoudooSkeleton: frame #32 ... persons=1 kpts=18      （约 30 帧/秒持续增长）
godot: OpenGL ES 3.2 ... Mali-G52 - Compatibility
```

### B 的测试结果（主控独立复跑确认）

```
RESULT: PASS - 404 assertions, 0 failures
total time: 18402 ms
```

覆盖：config、config/formulas、input、snake、collisions、food、round、ai、determinism。
修复的两个根因：

1. `rng.gd` 里 `randf()` 裸调用解析到 Godot **全局** RNG（不是类方法），导致同 seed 不可复现
   → 改为 `self.randf()`，并加回归守卫。
2. `turn cap` 三条断言原本把“上限”当成“实际转角”，与 `js/snake.js` 的 clamp 语义不符
   → 修正测试并补足上限覆盖。

## 3. 验收标准

- A：`adb logcat -s YoudooSkeleton` binder 连上、帧计数持续增长；屏幕关节数值随动作变化。
- B：`run_all.gd` 全绿 + 同 seed 两次签名逐字节一致（已达成）。
- C：真机 30fps 以上、8 条蛇可辨认、HUD/倒计时/结算正确、体感与键盘都能玩。
- D：连续 5 分钟不崩、体感跟手、帧率与内存稳定。

## 4. 机器防卡死措施（重要）

本机跑并发重活会卡死（已发生两次，其中一次是测试里的死循环吃光内存）。现在统一：

- 所有 Godot 调用走 `tools/run_godot_safe.ps1` / `tools/run_suites_sequential.ps1`：
  **一次一个进程、BelowNormal/Idle 优先级、硬超时自动 kill**；
- 单套件入口 `tests/run_one.gd`；
- 不并行跑 gradle / 导出 / 编辑器 GUI；
- 不在 PS 5.1 里用 `Get-Content`/`Set-Content` 往返 UTF-8 文件（会乱码），改文件用编辑工具。

## 5. 参考

- 网页版原型（玩法语义与视觉参考、截图）：`D:\CODEX-PROJ\yoodou\pose-snake-full-20261112\pose-snake`
- 已放弃的 WebView 壳（保留备查）：`D:\CODEX-PROJ\yoodou\pose-snake-webview`
- SDK 文档：`D:\CODEX-PROJ\yoodou\sdk\Documentation~\`
- SDK 参考 App：`D:\CODEX-PROJ\yoodou\sdk\Tools~\Android\SkeletonBridge`
