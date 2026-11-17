# 设备操作红线（硬规则）

**设备**：`YDG01010000063`（HP52S0-Youdoo）—— 用户自己的盒子。

## 规则

> **除非用户明确允许，不得对盒子做任何修改操作。需要修改时必须先向用户申请并得到同意。**

本规则高于任何任务书、任何"为了验证""为了排查"的理由。子 agent 同样适用，
派单时必须把本文件内容写进任务书。

## 什么算"修改"（一律需要事先批准）

| 类别 | 具体命令 |
| --- | --- |
| 装/卸/停应用 | `adb install`、`adb uninstall`、`am force-stop`、`am start`、`pm clear`、`pm disable/enable` |
| 改系统设置 | `settings put`、`svc power stayon`、`appops set`、`pm revoke/grant`、`wm size/density` |
| 输入注入 | `input tap`、`input keyevent`、`input swipe`、`input text` |
| 电源/系统 | `adb reboot`、`reboot recovery`、关机 |
| 文件系统 | `adb push/pull`（pull 出日志算只读，但也要先说明）、在 `/sdcard` 建删文件 |
| 其它 | 任何会改变盒子状态的命令，包括"看起来无害"的开关 |

## 只装包，不启动（2026-11-14 用户明确要求）

> **以后只装包，不启动，用户自己启动和操作。**

| 允许 | 禁止 |
| --- | --- |
| `adb install -r -t <apk>` | `am start`（任何 Activity） |
| 装完报告路径/SHA256/时间 | `am force-stop`、`input keyevent`、`input tap`、`screencap` 之外的任何注入 |
| 用户抱怨时才读 `logcat` / `dumpsys` | 替用户选模式、进游戏、按遥控器 |

装包前必须：**盒子已连接**（`adb devices` 有设备）→ 装 → 报告 → 结束。
装完不要"顺手启动"，也不要为了截图去注入按键。

## 只读也默认不做

`dumpsys`、`logcat`、`pm list packages` 这类读取本身不改状态，但**默认也不执行**；
只在用户明确要求排查时才做，并且先说明要读什么。

## 本项目已经踩过的坑（不要再犯）

1. `adb shell am force-stop com.youdoo.settings` —— 杀掉后遥控器"按 OK 接管系统控制"失效，
   用户表现为**遥控器连不上盒子**。settings 是该逻辑的宿主，不能随便杀。
2. `adb shell appops set com.youdoo.settings SYSTEM_ALERT_WINDOW deny` —— 拒绝系统浮层权限后，
   "主遥控器失去连接 / 按 OK 接管"提示无法显示，接管通道也断了。已改回 `default`。
3. `svc power stayon true` —— 会把 `stay_on_while_plugged_in` 从默认 0 改成 7，用后必须还原。
4. 遥控器原生钩子会在**应用前台时消费按键**，导致系统收不到键。属于设计行为，但测试时必须先退出应用，
   否则会被误判为"遥控器坏了"。

## 恢复初始状态清单（用户要求时执行）

```powershell
$adb = 'D:\platform-tools\adb.exe'
& $adb uninstall com.youdoo.posesnake                      # 移除测试包
& $adb shell settings put global stay_on_while_plugged_in 0 # 还原屏幕常亮
& $adb shell appops set com.youdoo.settings SYSTEM_ALERT_WINDOW default  # 还原浮层权限
& $adb shell am start -a youdoo.settings.SETTINGS -n com.youdoo.settings/.MainSettings  # 让 settings 重新加载
```

执行前后各记录一次状态，并向用户报告改了什么、现状如何。
