# 新机器上从 clone 到出包

> 这个仓库 **不是"clone 下来就能直接导出 APK"**：源码、资源、AAR、签名都带过来了，
> 但 Godot 的 Android 构建模板、编辑器里的 SDK/JDK 路径、以及缓存类目录不在库里
> （要么太大、要么是本机生成的）。按下面做一次即可。

## 1. 需要预装

| 软件 | 版本 / 说明 |
| --- | --- |
| **Godot** | **4.6.3-stable**（工程按它做的，别的版本可能报错） |
| **Godot 导出模板** | 4.6.3 的 export templates（编辑器里 `编辑器 → 管理导出模板` 安装） |
| **Android SDK + JDK 17** | 导出 APK 用（Tuanjie 自带的 JDK 也可） |
| **Python 3.12+** | 只有改角色资源时才需要（`tools/build_characters.py`，依赖 Pillow/numpy） |
| Git | — |

## 2. 打开工程

```
git clone https://github.com/kusobaga233-tech/pose-snack-godot.git
```

用 Godot 4.6.3 打开 `project.godot` 所在目录。首次打开会自动生成 `.godot/`
（导入缓存，几百 MB，所以没进库）。

打开后先跑一次发布闸门，确认环境没问题：

```powershell
powershell -NoProfile -File tools\verify_release.ps1
```

预期最后一行：`RESULT: PASS - safe to package`。

## 3. 配置 Android 导出（只做一次）

1. `编辑器 → 编辑器设置 → 导出 → Android`：
   - `Java SDK 路径` 指向 JDK 17
   - `Android SDK 路径` 指向 SDK
2. `项目 → 安装 Android 构建模板`（生成 `android/build/`，这一步不在库里）
3. 应用本项目的 Java 覆盖（**必须**，否则遥控器钩子和 SDK 绑定会丢）：

```powershell
powershell -NoProfile -File tools\setup_android_build.ps1
```

该脚本是幂等的：会装模板、补 manifest（SDK 服务权限 / queries / 插件 meta-data）、
把 `android/build-overrides/` 里的 `GodotApp.java`（遥控器原生钩子）覆盖进去、
并给 `gradlew.bat` 加上 `YOUDOO_JAVA_HOME` 支持。

> 如果本机 JDK 目录有权限限制（曾遇到 JVM 无法在 `D:\android_tc\jdk` 建文件），
> 把 JDK 复制到可写目录后用环境变量指定：
> ```powershell
> $env:YOUDOO_JAVA_HOME='C:\jdkcopy'
> $env:GRADLE_USER_HOME='C:\Users\<你>\.gradle'
> ```

## 4. 导出 APK

```powershell
$env:YOUDOO_JAVA_HOME='C:\jdkcopy'
$env:GRADLE_USER_HOME='C:\Users\<你>\.gradle'
godot --headless --path . --export-debug "Android" build\PoseSnake.apk
```

首次导出会下载 gradle 依赖，耗时较长；之后约 1–3 分钟。

## 5. 仓库里**没有**的东西（都在这台机器上）

| 目录 | 体积 | 为什么不进库 |
| --- | --- | --- |
| `.godot/` | ~85 MB | 导入缓存，打开工程自动重建 |
| `build/` | ~90 MB | APK 产物 |
| `evidence/` | ~240 MB | 截图 / 日志 / 轨迹，可重新生成 |
| `android/build/` | ~1 GB | Godot 构建模板 + 我们覆盖后的副本（第 3 步生成） |
| `android/_work/` | ~1.7 GB | gradle 中间产物 |

**进库了的关键二进制**（不带这些就编不过）：
`android/plugins/youdoo/*.aar`（SDK / 抠像 / 遥控器 / 埋点 / 自建取帧）、
`android/plugins/youdoo/godot-youdoo-skeleton.jar`、`debug.keystore`（debug 签名，口令 `android`）。

> `debug.keystore` 进库是为了让任何人导出的 debug 包**签名一致、可覆盖安装**。
> 正式发布前要换成自己的 release keystore（`export_presets.cfg` 的 `keystore/release*`）。

## 6. 桌面（PC）运行时的预期表现

> **先说结论：PC 上"功能不全"是正常的，不是工程坏了。** 体感和相机都依赖盒子上
> 的 Android 服务（`com.sdt.game.service`），PC 上永远拿不到。要验这两块必须上盒子。

### 6.1 在 PC 上**能**正常看到的

| 功能 | 说明 |
| --- | --- |
| 全部界面 | 模式选择 / 准备 / 倒计时 / 局内 / 暂停 / 结算，尺寸与真机一致（1920×1080） |
| 游戏逻辑 | 蛇的移动、AI、食物、道具、碰撞、结算排名，与真机同一套代码 |
| **桌面自动准备** | PC 上约 2.5 秒自动通过准备页进局（真机必须真人举手）。想回到真实流程：加 `--no-auto-ready` |
| 键盘操作 | 方向键转向（**仅桌面**；盒子上的键盘转向是强制关闭的） |
| 遥控器界面 | 用键盘的 ←→↑↓/回车/ESC 等价于遥控器按键 |
| 性能窗 | 开机即显示（F10 开关），数字是本机真实值 |
| 皮肤 / 表情 / 骨骼叠层 | 正常；骨骼需要合成帧，桌面用 `--camera-test` 造数据 |

### 6.2 在 PC 上**一定不会有**的（不要当 bug）

| 现象 | 原因 | 真机表现 |
| --- | --- | --- |
| 准备页显示"没有检测到玩家" | 没有 SDK 体感帧 | 真人站镜头前立刻变成"请举手确认准备" |
| 相机框是占位图 / 一直 `1.00×` | 没有原生取帧 | 显示实时画面 + 骨骼 |
| 日志里 `[pose] reason=no-frame` 或 `no-bridge` | 同上 | `reason=` 为空且 `s0=true` |
| `[bind]` 永远 `wait` | 没有可绑定的人 | `wait → cand(0.5s) → bound` |
| 日志 `rgba: YoudooBridge unavailable (desktop/editor)` | 同上，**只会打一次** | `rgba: seq=… fps=15` |
| 遥控器物理按键 | PC 没接 | 原生钩子转发 |

### 6.3 每台机器各自独立的东西

| 项 | 说明 |
| --- | --- |
| `user://pose_snake.cfg` 存档 | 最佳成绩 / 静音 / 赛制 / 玩家皮肤，**换机器从默认开始** |
| 帧率与压测数字 | 与 CPU/GPU 相关；闸门的 draw 数与机器无关，fps 有关 |
| 闸门的"逐字节一致"检查 | 是**同一台机器跑两次**的对比；跨机器不保证像素完全相同（驱动/抗锯齿差异） |

### 6.4 想在 PC 上尽量接近真机

```powershell
# 1) 完整校验：逻辑 + 资源 + 渲染 + 性能
powershell -NoProfile -File tools\verify_release.ps1

# 2) 用合成帧看相机框 + 骨骼叠层（不需要摄像头）
godot --path . -- --camera-test

# 3) 走真实准备流程（不自动通过），用于验证 2.5 秒那套逻辑
godot --path . -- --no-auto-ready

# 4) 压力场景（8 条蛇 × 240 节）
godot --path . -- --capture-stress
```

### 6.5 只能在盒子上验的清单

| 项 | 判定标准 |
| --- | --- |
| 体感绑定 | `[bind] -> cand` ≈0.5s、`-> bound` ≈2.5s（区域 1s + 举手 1.5s） |
| 举手容错 | 中途掉 1 帧不清零（日志 `gr=0.2x`） |
| 快速挥手 | 蛇全程跟着转，不中途僵住 |
| 垂手保持 | 手自然下垂 → 蛇直行，`reason=arm-low`、`conf=0.00` |
| 相机 | 界面带左格显示实时画面（镜像正确）+ 青色骨骼贴合身体 |
| 遥控器 | 每次按键只触发一次，DPAD/OK/BACK 全流程可用 |
| 双人 | 两块相机框各有画面；两人中途换位槽位不换人 |

## 7. 常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 导出报 `android/build` 不存在 | 没做第 3 步 |
| 遥控器按键没反应 / 应用里无 `GodotRemoteInput` 日志 | 没跑 `setup_android_build.ps1`，`GodotApp.java` 覆盖没进去 |
| 体感一直"没有检测到玩家" | 盒子上没装/没启动 `com.sdt.game.service`（SDK 服务）；查 `adb logcat -s godot` 的 `[bind]`/`[pose]` |
| 相机框一直是占位图 | 原生取帧库没加载（`libcamframe.so`）或服务不给帧，日志搜 `[camera] rgba:` |
| 闸门红在 stress（draw/fps） | 机器太弱或后台有负载；关掉其它程序再跑 |

## 8. 目录说明

| 路径 | 内容 |
| --- | --- |
| `src/core/` | 规则内核（与网页版 1:1，448 断言覆盖） |
| `src/present/` | 表现层：HUD / 世界 / 结算 / 特效 / 体感输入 / 皮肤 |
| `src/main.gd` | 主状态机（选人→准备→倒计时→局内→暂停→结算） |
| `src/youdoo_bridge.gd` | SDK 桥（AIDL 体感 + RGBA 相机帧） |
| `android/` | Android 插件源码、AAR、原生取帧 C 代码、构建覆盖文件 |
| `assets/characters/` | 11 个角色的图集与身体贴图（由 `tools/build_characters.py` 生成） |
| `tools/` | 闸门、资源校验、角色构建、设备脚本 |
| `Docs/` | 架构、UI 参考、素材规范、设备操作红线 |
| `tests/` | 448 断言 + 各类探针（绑定/相机/遥控器/性能） |
