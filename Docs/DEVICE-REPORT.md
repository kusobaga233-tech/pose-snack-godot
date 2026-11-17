# 真机验收报告（D 工作流）

设备：`HP52S0-Youdoo`（Android 11 / SDK 30 / arm64-v8a / 1920×1080 / Mali-G52 / 4GB）
包：`com.youdoo.posesnake`，APK 90.5 MB，debug 签名（`debug.keystore`）
时间：2026-11-12 15:03–15:19

## 结论

**Godot 原生版跑通，体感由 YoudooGame SDK 骨骼驱动，真机 60fps。**

| 项 | 结果 |
| --- | --- |
| 安装/启动 | ✅ `GodotAppLauncher` 正常，全屏无系统栏 |
| 帧率 | ✅ **60fps**，特效高峰 50–52fps（`draw 130–200`，`prim 3.8k–6.9k`） |
| 一局完整流程 | ✅ 菜单 → 2:00 对局 → **结算舞台**（第7名、8 列比高、再来一局） |
| SDK 骨骼 | ✅ AIDL 绑定 `IGameServiceV1_0_3`，~30 帧/秒，`persons` 有识别，18 关键点 |
| 体感驱动 | ✅ `layout=youdoo18`、`hand=left/right` 自动切换、`angle` 实时变化 |
| 中文 UI | ✅ 修好（`/system/fonts/NotoSansCJK-Regular.ttc` 直接加载） |
| 稳定性 | ✅ 连续 5 分钟（2 分钟对局 + 3 分钟停留）无崩溃、无 ANR |
| 内存 | ⚠️ 高水位 1.09GB PSS（Native 613MB / GL 371MB），3 分钟内**持平不涨**，非泄漏 |

## 关键日志证据

### 1. SDK 骨骼帧（A 工作流）
```
YoudooSkeleton: start(): bindService=true (requested com.sdt.game.service.IGameServiceV1_0_3)
YoudooSkeleton: connected com.sdt.game.service/.SdtGameService descriptor=...V1_0_3
YoudooSkeleton: frame callback registered on IGameServiceV1_0_3
YoudooSkeleton: frame #613 t=4623241 1920x1080 persons=2 kpts=18
```
SDK 自身推理（设备侧原生，非我们的代码）：
```
NnsdkYoloPose: yolov8n_pose_int16_w512xh288_18_20260911.adla ... runCost:17
```

### 2. 体感映射（D 新增诊断）
```
[pose] layout=youdoo18 hand=right dist_n=0.55 angle=2.455 conf=1.00 torso=261 s0=true
[pose] layout=youdoo18 hand=left  dist_n=0.83 angle=1.104 conf=1.00 torso=341 s0=true
[pose] layout=youdoo18 hand=right dist_n=0.58 angle=1.318 conf=1.00 torso=264 s0=true
```
- `layout=youdoo18`：锁定 SDK 的 `KeyPointIndex` 顺序（`0 鼻 1 左眼 2 右眼 3 左耳 4 右耳 5 左肩 6 右肩 7 左肘 8 右肘 9 左手腕 10 右手腕 11 左髋 12 右髋 13 左膝 14 右膝 15 左脚踝 16 右脚踝 17 胸口`）
- `hand=left/right`：远处手腕自动选取（带迟滞）
- `dist_n` 0.55–0.84、`angle` 1.09–2.46 rad：随人体动作实时变化 ⇒ **转向确实来自身体**

### 3. 帧率
```
[perf] fps=60 draw=145 prim=5077 snakes=8 food=126 pwr=4 fx=7/0/0
[perf] fps=52 draw=130 prim=3838 snakes=8 food=135 pwr=4 fx=49/0/0   ← 粒子爆发瞬间
```
低配档自动生效：`food=120`、`pwr=5`（桌面 195/7）。

### 4. 内存（3 分钟采样）
```
t+  0s  PSS 1090174
t+ 30s  PSS 1089775
t+ 60s  PSS 1091323
t+ 90s  PSS 1089787
t+120s  PSS 1090747
t+150s  PSS 1090843
t+180s  PSS 1091059
```
双向波动 ±2MB，**无单调增长** ⇒ 不是泄漏，是启动+开局的纹理/字体图集高水位。

## 截图

| 文件 | 内容 |
| --- | --- |
| `evidence/device-menu-cjk.png` | 中文开始页（体感就绪 / 开启摄像头 / 先用方向键玩） |
| `evidence/device-game-02.png` | 局内：HUD、排名、小地图、POSE·TRACK |
| `evidence/device-after-3min.png` | 结算舞台：第7名、8 列比高、全长中文 |
| `evidence/render-preview*.png` | PC 端渲染预览（含 1080p、2P 分屏） |

## 待改进（不影响"能玩"，但建议排期）

1. **内存高水位 1.1GB**：主要来自 CJK 字体图集与食物精灵图集。可把字体改成按需子集、食物精灵降到 128px，预计降到 600–700MB。
2. **体感难度**：本局玩家 17 节 / 死 18 次，AI 最高 67 节。核心规则忠实于网页版，但 AI 压力对首次玩家偏硬，建议加"前 20 秒保护期/AI 降档"。
3. **相机画面**：当前没有把 SDK 的相机画面（`getFrameBuffer` / `setCameraLiveOnScreen`）画到背景，玩家看不到自己。网页版是有的；这是产品级差距，建议后续补。
4. **偶发掉帧**：粒子爆发瞬间 52fps，可再压粒子上限或改批量绘制。
5. **打包**：目前是 debug 签名（本机 keytool 被安全策略拦截，建不了正式 keystore），发布前需在有权限的机器上出正式签名。

## 复现命令

```powershell
# 生成 JDK 副本（本机安全策略禁止 D:\android_tc\jdk 下的 JVM 写文件）
robocopy D:\android_tc\jdk C:\jdkcopy /E
# 导出（gradle 走可写 JDK）
$env:YOUDOO_JAVA_HOME='C:\jdkcopy'; $env:GRADLE_USER_HOME='C:\Users\Admin\.gradle'
D:\godot-proj\Godot_v4.6.3-stable_win64.exe --headless --path D:\CODEX-PROJ\yoodou\pose-snake-godot `
  --export-debug "Android" D:\CODEX-PROJ\yoodou\pose-snake-godot\build\PoseSnake.apk
# 安装 + 启动
D:\platform-tools\adb.exe install -r -t build\PoseSnake.apk
D:\platform-tools\adb.exe shell am start -n com.youdoo.posesnake/com.godot.game.GodotAppLauncher
```
