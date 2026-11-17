# UI-REFERENCE-1024 — Unity 参考工程 UI 层拆解 vs 我们的 Godot 四屏

> 只读分析产物（本文件是本次唯一写入的文件；未改任何源码、未运行 Godot、未碰 Android 盒子）。
> 参考工程：`D:\CODEX-PROJ\yoodou\1024-xiexie\game_1024`（Unity，AGame 层）。
> 我们的工程：`D:\CODEX-PROJ\yoodou\pose-snake-godot`（Godot 4.6 / GL Compatibility，设计分辨率 1920×1080，`project.godot:23-24`）。
> 解析方式：自写 Unity YAML 解析器（PyYAML + 去 `!u!` tag），按 `RectTransform` 树递推出**画布绝对矩形**；`m_Text` 直接取 prefab 序列化值（UTF-8）。GBK 源文件用 `gb18030` 解码（`ModelForm.cs` / `KinestheticInfoForm.cs` / `XXAndroidParseData.cs` / `XX_LevelManagerBase.cs` / `TransitionForm.cs` / `GameInfoForm.cs` 等 61 个）。
> 坐标：Unity 的 y 向上（左下原点），我们 y 向下（左上原点）。本文参考值同时给出 `y_bottom` 与换算后的 `top = 1080 − y0 − h`，方便和我们的数直接比。

---

## 0. 先给结论（owner 最需要知道的 6 条）

1. **参考工程的“主界面”其实只有一块 logo + 底部两张卡，没有面板**：`ModelForm.prefab` 全屏铺底，`logo = 1004×401` 贴顶（top 9..410），两张模式卡 `342×138` 落在 **top 785..923**（屏幕下五分之一），中间大片留空。我们则是一块 `780×582.72` 的居中标语板（`ps_hud.gd:148`）把所有东西装进去。**这是最大的“结构差”，不是尺寸差。**
2. **参考的模式卡是 342×138、字号 48**；我们是 `351×79`、主字 19 / 副字 11.5（`ps_hud.gd:151-153, 1152-1158`）。卡片高度差 **+75%**，字号差 **+153%**。这两个数同时是 TV 可读性最关键的项。
3. **参考的“准备”不是一屏 UI，而是常驻体感层的子面板**（`KinestheticInfoForm.findPlayerRoot`）：整屏相机画面 + 每名玩家一张竖版照片卡 `428×624`（外框 `436×632`），状态字 **60 px**，进度条 `218×488`；面板从 `y=+1400` 滑到 0（0.3 s OutQuad）。我们的 `MODE_READY` 是不透明设计底板 + 横版卡 `556×496`、相机窗只有 `342×250`、状态字 34。**参考是“相机优先”，我们是“面板优先”。**
4. **参考的暂停是 1148×556 的居中弹框 + 一排 3 个 247×196 图标键（字 48）**；我们**没有框**，只有 561×193 的 `#pauseStats` 数据条 + 3 行 400×54 文本键。结构完全不同，但注意：**我们的暂停动作区在 web 版里不存在**（`ps_hud.gd:1702-1704` 自己写明），所以改它**不破坏 web parity**。
5. **导航语义高度一致**：BACK 都是“暂停↔继续”和“准备→模式选择”，方向键都是线性循环、OK 都是确认。真正的差异只有 3 个：① 参考 `ModelForm` 的 BACK 是 `MoveTaskToBack`（退到后台），我们是 `get_tree().quit()`（`main.gd:5349-5351`）；② 参考“准备”是**自动收面板、无 GO 拍**，我们有 1.5 s `GO!`（`main.gd:208, 1928-1958`）；③ 参考暂停第三项是“返回主页/退出关卡”两件事，我们是“重新开局/返回模式选择”。
6. **参考的 `StartForm` 是死代码**：`ProcedureEnterGame.cs:19-30` 启动直接开 `KinestheticInfoForm` + `ModelForm`，全工程没有任何 `OpenUIForm(StartForm)`。所以“主界面 = StartForm（Play 260×100）”只代表设计意图，**不要照着实现**。

---

## 1. 画布基准

| 项 | 值 | 证据 |
|---|---|---|
| 参考分辨率 | **1920×1080** | `Assets\AGame\Scenes\Level_1_Backup.unity:2656-2661`：`m_UiScaleMode: 1`（ScaleWithScreenSize）、`m_ReferenceResolution: {x: 1920, y: 1080}`、`m_ScreenMatchMode: 1`、`m_MatchWidthOrHeight: 0`；另 `Assets\CorgiEngine\Common\Prefabs\GUI\UICamera.prefab:91` 同值 |
| 每个 UIForm 自带 Canvas | 是（`--- !u!223 Canvas` 在根节点） | 例 `StartForm.prefab` 根 `StartForm` 组件 = `RectTransform + Canvas + GraphicRaycaster + StartForm.cs` |
| 根 RectTransform | 1920×1080，anchor (0,0)-(1,1)，pivot (.5,.5) | 全部 17 个 `UIForms\*.prefab` 一致 |
| 排序 | 后开的 form 在上 | `UIFormBase.cs:83-91`（`Open()` 里 `App.UI.SetSortingOrder(this, true)`），`ToClose()` 反向（:117-119） |
| 我们的画布 | 1920×1080，`stretch/mode=canvas_items`，`aspect=expand` | `project.godot:23-28` |

> 因此下文的“参考画布单位”与我们的“设计 px”是 **1:1**，可以直接减。

---

## 2. 表单清单（Form inventory）

| # | Form（常量 id） | prefab | 谁打开 | 它打开/关闭谁 | 入场/退场动画 | 背板 |
|---|---|---|---|---|---|---|
| 1 | `LoadingForm` 101 | `UIForms\LoadingForm.prefab` | `XXSceneManager.cs:176-181`（任何 `showLoadingForm:true` 的 LoadScene） | 加载完成后自己 `CloseWithAni()` | 0.3 s CanvasGroup 淡出（`LoadingForm.cs:57-61`） | 全屏 2448×1080 图 + 进度条 |
| 2 | `StartForm` 201 | `StartForm.prefab` | **无人调用（死代码）** | 设计上 `btnPlay → LogoForm` + 自关（`StartForm.cs:40-44`） | `currSelectedButton.Select()` | 全屏黑图 + 两个 260×100 键 |
| 3 | `LogoForm` 211 | `LogoForm.prefab` | `StartForm.cs:42`（仅死路径） | 5 s 后 `OpenUIForm(ModelForm)` + 自关（`LogoForm.cs:15-23`） | 0.3 s 淡入/淡出，`stayTime=5f` | 全屏图 + 600×220 logo |
| 4 | **`ModelForm` 209（主界面+人数选择）** | `ModelForm.prefab` | `ProcedureEnterGame.cs:28`（开机）/ `GameDataManager.BackToModelForm():309`（暂停“返回主页”） | `StartStage(ToLevelId(1), cb)`→`TransitionForm`→`LoadingForm`；`cb` 里 `OpenFindPlayerForm()` + 自关（`ModelForm.cs:139-144`） | logo `y 780→331` 0.5 s OutBack；两键 `scale 0→1` 0.35 s，延迟 0.4 s（`ModelForm.cs:30-46`） | 全屏 2448×1080，无面板 |
| 5 | `KinestheticInfoForm` 206（常驻体感层；内含**准备面板** `findPlayerRoot`） | `KinestheticInfoForm.prefab` | 开机 `ProcedureEnterGame.cs:21`；之后**从不关闭** | 准备面板 `OpenFindPlayerForm/CloseFindPlayerForm` 由 `XXAndroidParseData` 与 `ModelForm`/`PauseForm` 调 | 面板 `y 1400→0` / `0→1400`，0.3 s OutQuad（`KinestheticInfoForm.cs:352-377`） | 整屏相机 `ImgBg` 1920×1080 |
| 6 | `FindPlayerForm` 207 | `FindPlayerForm.prefab`（93 KB） | **没有任何代码打开它**（`FindPlayerForm.cs` 是空类，187 B） | — | — | 与 #5 同构的旧版，勿用 |
| 7 | **`PauseForm` 202（暂停）** | `PauseForm.prefab` | `XX_LevelManagerBase.cs:98`（`Escape → _PauseGame()`） | `btnContinue` 自关；`btnBack` → `LoadScene(Hall)`；`btnHome` → `BackToModelForm()`（`PauseForm.cs:70-91`） | 整框 `DOTweenAnimation` type5/scale，0.3 s（ease 27） | 全屏黑 0.784 + 1148×556 框 |
| 8 | `TransitionForm` 213 | `TransitionForm.prefab` | `GameDataManager.cs:179`（每次 StartStage） | 1.3 s 后自关，`OnClose` 回调 `_onComplete`（`TransitionForm.cs:38-49`） | Spine 骨骼动画，全屏 2464×1081 | 全屏 Spine |
| 9 | `GameInfoForm` 203（局内 HUD） | `GameInfoForm.prefab` | `XX_LevelManager.cs:318`（关卡初始化末尾） | 关：回模式选择时 `StartForm.cs:31-33` | — | 透明；暂停键/血量/金币 |
| 10 | `SuccessForm` 204 / `FailureForm` 205 / `ResultForm` | 各自 prefab | `XX_FinishDoor.cs:151` / `XX_LevelManager.cs:416` / `XX_World2Rule.cs:192` | `ResultForm` 6 s 倒计时后 `BackToModelForm()` | — | 结算 |

`Constant.UIForm.cs:16-105` 的 id 全表：101 Loading / 102 Message / 103 Float / 201 Start / **202 Pause** / 203 GameInfo / 204 Success / 205 Failure / **206 KinestheticInfo** / 207 FindPlayer / 208 SelectLevel / **209 Model** / 210 Pay / 211 Logo / 212 SceneInfo / 213 Transition / 214 AgeTip / 215 PaySuccess。

---

## 3. 导航图（实际跳转，一行一屏）

```
启动 (Scene_Launch)
  └─ ProcedureEnterGame ──> [KinestheticInfoForm 常驻] + [ModelForm 主界面/人数选择]
        ├─ OK(聚焦卡) ──> StartStage(level 1)
        │      ├─ 立即: TransitionForm (Spine, 1.3 s, 全屏遮挡)
        │      ├─ t=1.0 s: LoadScene(Level_1, showLoadingForm) ──> LoadingForm 打开
        │      │        └─ LoadingForm.onOpen 回调 ──> OpenFindPlayerForm() + ModelForm.Close()
        │      │             （此刻准备面板在 LoadingForm **下面**滑入，玩家先看到进度条）
        │      └─ t=1.3 s: TransitionForm 自关
        ├─ 加载完: LoadingForm 0.3 s 淡出 ──> [准备面板] 露出（整屏相机 + N 张照片卡）
        │      ├─ 全员举手确认(readyNeedFrame=120 帧) ──> CompleteFindPlayer()
        │      │      └─ 0.3 s 后 CloseFindPlayerForm()（0.3 s 滑出）+ 派发 FindPlayerFormClose
        │      │           └─ XX_LevelManager._UnFreeezRole()  ──> 局内可动
        │      ├─ BACK ──> BackToModelForm(): 开 ModelForm + UnLoadCurrScene
        │      └─ （局内有人离场）XXAndroidParseData.cs:615-630 ──> 准备面板**重新滑入**（游戏继续在背后跑）
        ├─ 局内: BACK/ESC ──> PauseForm（全屏黑 0.784 + 1148×556 框）
        │      ├─ 继续游戏 / BACK ──> Close() ──> UnPause（若有 pending 则先回准备）
        │      ├─ 退出关卡 ──> LoadScene(Hall, showLoadingForm)（LoadingForm 再出现）
        │      └─ 返回主页 ──> Close(skipAni) + BackToModelForm()
        └─ 结束: Success/Failure ──> ResultForm 6 s ──> BackToModelForm()
```

**按键语义（参考，实测代码路径）**

| 屏 | ←/→/↑/↓ | OK | BACK(ESC) | 证据 |
|---|---|---|---|---|
| ModelForm | 线性循环 `[btnModel_0(已隐藏) → btnModel_1 → btnAgeTip]`；四个方向都是 prev/next | `JoystickButton0`/`Space` → 点当前项 | `MoveTaskToBack()`（退后台，不退出） | `ButtonMgr.cs:86-108`；`ModelForm.cs:88-95`；ButtonMgr 数组含 `btnAgeTip`（prefab `_buttonExArr`） |
| 准备 | 人脸识别模式下 ←/→ 换角色、↑ 选第一个 | `SelectRole()` 确认角色 | `BackToModelForm()` | `KinestheticInfoForm.cs:120-148`；`XX_LevelManagerBase.cs:90-92` |
| 暂停 | 线性循环 3 项（默认第 0 项=继续） | 点当前项 | `Close(skipAni)` → 继续 | `ButtonMgr.cs`；`PauseForm.cs:61-65` |

> 参考的 `ButtonMgr.OnEnable` 自动选第 0 项（`ButtonMgr.cs:29-36`）；`App.cs:225` 每帧 `CurrBtnMgr.OnUpdate()`。`KinestheticInfoForm.IsFindPlayerFormShowed` 时 ButtonMgr 直接 return（`ButtonMgr.cs:87-88`）。
> ⚠️ 参考的“三人模式”按钮是 `ModelForm.OnOpen` 里 `Instantiate` 出来的（`ModelForm.cs:154-215`），**晚于 `ButtonMgr.Awake`**，所以不在 `_buttonArr` 里 —— 遥控器**选不到三人模式**。这是参考的 bug，别抄。

---

## 4. 组件尺寸表（参考画布单位，1920×1080）

### 4.1 主界面 / ModelForm 头部（prefab `Assets\AGame\UIPrefab\UIForms\ModelForm.prefab`）

| 节点 | x | y_bottom | top | w×h | 字号 / 其它 |
|---|---|---|---|---|---|
| `ModelForm`（根 Canvas） | 0 | 0 | 0 | 1920×1080 | — |
| `ImgBg`（RawImage） | −264 | 0 | 0 | 2448×1080 | 全屏溢出 264 px/侧 |
| `logo`（Image） | 458 | 670 → | **9..410** | **1004×401** | pivot .5；运行时 ap.y 331（`ModelForm.cs:32`） |
| `buttons`（HorizontalLayoutGroup） | 960 | 176 | 804..904 | 0×100 | spacing **60**，alignment 4，forceExpand 1/1 |
| `buttons/btnModel_0` | 见下 | 157 | **785..923** | **342×138** | `Text` 48 MiddleCenter `"单人模式"`（MVP 隐藏） |
| `buttons/btnModel_1` | 见下 | 157 | **785..923** | **342×138** | `Text` 48 `"双人模式"`；`ic_vip` 103×94 @(1056,180) |
| `buttons/btnModel_2`（克隆） | 见下 | — | 同 | 342×138 | 文案 `"三人模式"`（`ModelForm.cs:205-213`） |
| `btnAgeTip`（锚 0,1；pivot 0,1） | 30 | 858 | **30..222** | **150×192** | 子 `frame` 257×293、`selected` 100×100、`imgAgeTip` 150×192 |
| `txtVersion`（锚 1,0） | 1740 | 10 | 1040..1070 | 160×30 | **35**，align 8（右下） |
| `tip`（锚 .5,0） | 880 | 52 | 998..1028 | 160×30 | **30**，`"健康游戏忠告\n抵抗不良游戏…"` |

卡片实际 x（布局组算出来的，不是序列化值）：3 张 `387..729 / 789..1131 / 1191..1533`；**MVP 实发 2 张 = `588..930 / 990..1332`**（`_btnModel_0.SetActive(false)`，布局组忽略 inactive）。

### 4.2 主界面（死代码 StartForm，仅作设计意图参考；`StartForm.prefab`）

| 节点 | x | y_bottom | top | w×h | 字号 |
|---|---|---|---|---|---|
| `btnPlay` | 830 | 309 | 671..771 | **260×100** | `Text` **50** `"Play"` |
| `btnEditor` | 830 | 146 | 834..934 | 260×100 | `Text` 50 `"编辑器"` |

### 4.3 人数选择 / ModelForm 卡片（同上 prefab，`buttons` 子节点）

| 项 | 值 |
|---|---|
| 卡片 | **342×138**，圆角/九宫图来自 Image（无 sprite 引用，纯色 1,1,1,1） |
| 主文案 | **48 px**，Unity `Text`，MiddleCenter，每张卡一段 |
| 卡间距 | **60** |
| 行宽（2 张） | 744；居中 x 588..1332 |
| 行宽（3 张） | 1146；居中 x 387..1533 |
| 行垂直位置 | top 785..923（屏幕下缘往上 157 px 起） |
| 选中态 | 子节点 `selected`（100×100）+`frame` 257×293，由 `XXButton.SetSelectState` 开关（`XXFramework\Component\XXButton.cs:34`） |

### 4.4 准备 / `KinestheticInfoForm.findPlayerRoot`（`KinestheticInfoForm.prefab`）

| 节点 | x（1P / 2P 左 / 2P 右） | top | w×h | 说明 |
|---|---|---|---|---|
| `findPlayerRoot` | 960 | — | 100×100（pivot 盒） | 容器；运行时 `ap.y = +1400 → 0`，0.3 s OutQuad（`KinestheticInfoForm.cs:13, 352-353`） |
| `single/ImgBg`、`mul/ImgBg` | 0 | 0..1080 | **1920×1080** | RawImage 整屏相机 |
| `player_1` / `player_2` | 572 / 1348 | — | 0×0 | 间距 **±388**（`_baseCardSpacing` 取自 `_rtPlayerArr[1].x`，`KinestheticInfoForm.cs:66`）；3P 时 `scale 0.7`（:277） |
| `…/frame/cameraTex` | 572 / 1348 | **228..852** | **428×624** | 玩家照片（`CameraImagView` 425×620） |
| `…/frame/outline` | 572 / 1348 | 224..856 | **436×632** | 边框 |
| `…/frame/progress/bg`、`fill` | 572 / 1348 | 296..784 | **218×488** | 竖进度条；fill 色 P1 `rgba(224,60,20)`、P2 `rgba(132,23,160)` |
| `…/headIcon` | 572 / 1348 | **141..241** | **100×100** | `imgIcon` 128×127、`imgFace` 63×63 |
| `…/txtLabel` | 572 / 1348 | **71..101** | 160×30 | **60 px**，"请举手等待识别" / "Ready"（`KinestheticInfoForm.cs:196-204`） |
| `imgSelected`（人脸选中框） | 1275 | 816..962 | 146×146 | 仅人脸模式 |
| `RefuseReadyTip` | 1757 | 26..? | 310×40 文本（30 px）+168×168 图 | "双手抱臂拒绝准备" |
| `tip`（左下，inactive） | 10 | −180 | 87×180 图 + 30 px 文本 | "Press the up arrow…" |

### 4.5 暂停 / `PauseForm.prefab`

| 节点 | x | y_bottom | top | w×h | 字号 / 其它 |
|---|---|---|---|---|---|
| `bg`（Image） | 0 | 0 | 0..1080 | **1920×1080** | `rgba(0,0,0,0.784)` |
| `frame`（Image） | 386 | 262 | **262..818** | **1148×556** | 居中；DOTweenAnimation type=5(Scale)、`isFrom=1`、0.3 s、ease 27(OutElastic) |
| `frame/title/txtTitle` | 910 | 739 | **311..341** | 160×30 | **60 px**，`"第1关"`（运行时 `App.Localization.GetString("PauseForm.Title", stage)`，`PauseForm.cs:22-23`） |
| `frame/btnRoot` | 960 | 465 | 515..615 | 0×100 | HorizontalLayoutGroup，spacing **100**，alignment 4 |
| `btnContinue` | 490..737 | 417 | **467..663** | **247×196** | 文本 248×70、**48 px**、`"继续游戏"` |
| `btnBack` | 837..1084 | 417 | 467..663 | **247×196** | 48 px `"退出关卡"` |
| `btnHome` | 1184..1430 | 417 | 467..663 | **246×196** | 48 px `"返回主页"` |
| 每个按钮的 `Text` | 同卡 | 295 | **715..785** | 248×70 | 文字在图标**下方**，48 px |
| 每个按钮的 `selected` | 780 / 1127 / 1474 | 312 | — | **359×306** | 选中光圈（略大于 247×196） |

> 三个按钮的 x 是布局组算的（序列化时三者都在 `(836,367)`）；`3×247 + 2×100 = 941`，居中 → 490 起。

### 4.6 顺带（跟四屏相邻、会影响观感）

| 节点 | 值 | 证据 |
|---|---|---|
| `LoadingForm` logo | 1004×401，top 9..410 | `LoadingForm.prefab` `logo` |
| `LoadingForm` 进度槽 | 988×100 @ top 863..963；fill 626×43；百分比 **36 px** @ x 577 | `progress/bg`,`fill`,`txtTip` |
| `TransitionForm` 全屏 Spine | 2464×1081 | `spine` |
| `GameInfoForm` 暂停键 | **112×103**，右上 100 px 内边距（x 1764..1876, top 49..152），**prefab 里 `m_IsActive: 0`** | `btnPause` |
| `GameInfoForm` 血量 | 3×100×100（`Heart`），右上 | `HpRoot/Heart` |
| `GameInfoForm` 金币 | 300×100（底 374×147），左上 | `Gold` |

---

## 5. 我们现在的四个屏（1920×1080 设计 px）

### 5.1 尺寸

**MODE_SELECT（主界面 + 人数选择合一）** — `ps_hud.gd:928-1019`

| 元素 | 值 | 代码 |
|---|---|---|
| 标语板 `SLAB` | **780×582.72 @ (570, 248.64)**，圆角 4，顶 4 px 青柠边 | `ps_hud.gd:148-149, 942-946` |
| 品牌 chip | 132.31×22 @ (cx−111, 272.64)，字 10 | `:951-955` |
| H1 "体感贪吃蛇" | **58 px** 渐变 + 2.32 字距，基线 370.64 | `:966-967` |
| 副标 | 13 px，基线 400.64 | `:968-970` |
| 4 个 meta 徽章 | 高 29，字 11，基线 415.64 | `:972-1000` |
| "游戏人数" 标签 | 11 px，基线 479.64 | `:1002-1003` |
| 模式卡 | **351×79**，gap **12**，y 495.11..574.11，x **603..954 / 966..1317** | `ps_hud.gd:151-153, 1004-1007` |
| 卡内主字 | **19 px** @ 卡顶+34（"1 人"/"2 人"） | `:1152-1154` |
| 卡内副字 | **11.5 px** @ 卡顶+58 | `:1155-1158` |
| 角色行 | 372×48 @ y 584.64 | `:1084, 1090, 1009` |
| 体感状态 | 12 px，基线 656.64 | `:1011-1015` |
| 细则 | 10.5 px，基线 683.64 | `:1017-1019` |

**MODE_READY（准备）** — `ps_hud.gd:1178-1332`

| 元素 | 值 | 代码 |
|---|---|---|
| 背板 | 不透明 `bg_grad`+`grid`+左右半屏 tint；无相机整屏 | `:1182-1201` |
| 头部 chip | 104×42 @ (448,40)，"准备" 22 | `:1207-1209` |
| 模式名 | 28 px @ x 572 | `:1210` |
| 大标题 "准备开始" | **56 px**，基线 152 | `:1215` |
| 操作提示 | 26 px，基线 214 | `:1216-1218` |
| 槽卡 | 2P：**556×496** @ y 286，x **340..896 / 1024..1580**（gap 128）；1P：620×496 @ x 650 | `:1220-1227` |
| 相机窗 | **342×250** @ 卡内 (36,74) | `:1281` |
| 竖进度条 | **64×280** @ (r.end.x−120, y+74) | `:1305-1320` |
| 玩家标题 | 24 px；左右半屏标 18 px | `:1271-1279` |
| 状态行 | **34 px** @ 卡底−46 | `:1329` |
| 保持举手 | 17 px @ 卡底−18 | `:1331-1332` |
| 无人提示面板 | 780×120 @ y 800 | `:1372-1381` |
| 返回提示 | 18 px @ (44, h−30) | `:1232-1233` |

**MODE_PAUSE（暂停）** — `ps_hud.gd:1705-1784`

| 元素 | 值 | 代码 |
|---|---|---|
| 遮罩 | 仅竞技区 `y=200..1080`，`rgba(3,8,14,.82)`；**band 继续活着** | `:1709` |
| kicker | 24 px，基线 246 | `:1711-1712` |
| 标题 | **44 px**，基线 306 | `:1713-1714` |
| 数据条 `#pauseStats` | **561.28×193.39 @ (679.36, 318)**，圆角 4，左 4 px 青边 | `:158-159, 1716-1718` |
| 数据格 | **120×110.39**，x 767.5 / 895.5 / 1023.5，y 335；标签 28、值 48 | `:159-163, 1770-1779` |
| 道具行 | 26 px，基线 489.39 | `:1732-1733` |
| 动作键 | **400×54**，x 760..1160，y **537.39 / 603.39 / 669.39**，gap 66 | `:1735-1760` |
| 动作字 | 28（继续）/ 26（重开、返回） | `:1744-1759` |
| 提示 | 18 px，基线 757.39 | `:1761-1763` |
| 排行榜 | 340 宽 @ (1536, 248) | `:164, 1765` |

### 5.2 我们的导航/按键

状态机：`MODE_SELECT(0) → MODE_READY(4) → MODE_COUNTDOWN(5, 1.5 s) → MODE_PLAY(1) → MODE_PAUSE(2) / MODE_SETTLE(3)`（`main.gd:177-182`）。

| 屏 | ←/→/↑/↓ | OK | BACK |
|---|---|---|---|
| MODE_SELECT | LEFT/UP = 焦点左移（0/1，角色行=2）；RIGHT/DOWN = 右移；在角色行上 ←/→ 换角色 | 焦点 0/1 → `_on_mode_selected(1/2)`；角色行 → 换角色；**无默认焦点时 OK 无效** | `_flow_to("quit") + get_tree().quit()`（**退出 App**）`main.gd:5349-5351` |
| MODE_READY | 忽略 | **忽略**（只有体感举手能确认） | `_enter_select("back")` `main.gd:5289-5290` |
| MODE_COUNTDOWN | 忽略 | 忽略 | `_enter_select("back")` |
| MODE_PLAY | 忽略（方向=体感） | `_toggle_pause("ok")` | `_toggle_pause("back")` `main.gd:5294-5299` |
| MODE_PAUSE | 线性循环 3 项（左右上下都行） | 焦点 0=继续 / 1=重新开局 / 2=返回模式选择 | **继续**（关暂停）`main.gd:5380-5397` |
| MODE_SETTLE | 焦点 0/1 | 再来一局 / 返回模式选择 | 回模式选择 `main.gd:5401-5412` |

确认条件：每个槽 `READY_ZONE_SEC=1.0 s` 进区 + `READY_RAISE_SEC=1.5 s` 举手（`main.gd:186-194, 1849-1857`）；全就绪 → `_begin_countdown` 1.5 s → `_begin_play`（`main.gd:1928-1969`）。

---

## 6. Delta 表

类别：**S** = 结构不同（整个组件不一样）；**Z** = 只是尺寸；**N** = 导航。

| # | 屏 | 元素 | 参考值（prefab:node） | 我们的值（file:line） | Δ | 类 | 要改哪里 |
|---|---|---|---|---|---|---|---|
| D1 | 主 | 主容器 | 无面板，全屏铺底（`ModelForm:ImgBg`） | 780×582.72 板（`ps_hud.gd:148`） | 结构差 | **S** | `ps_hud._draw_select()` 整体重排，非改常量 |
| D2 | 主 | 品牌块 | logo 图 **1004×401**，top 9（`ModelForm:logo`） | H1 文本 **58 px**，基线 370.64（`:966`） | 高 401 vs ~58 = **6.9×** | **S** | 需要 logo 资源；`_draw_select()` 顶部 |
| D3 | 主 | 模式卡 | **342×138**（`:btnModel_1`） | **351×79**（`:151-152`） | W −9 / **H +59（+75%）** | Z | `CARD_W/CARD_H` |
| D4 | 主 | 卡主字 | **48**（`btnModel_1/Text`） | **19**（`:1152-1154`） | **+29（+153%）** 🔴TV | Z | `_draw_mode_card()` |
| D5 | 主 | 卡副字 | 参考无副字（单行 48） | **11.5**（`:1155-1158`） | 11.5 vs 48 | **S** | `_draw_mode_card()` |
| D6 | 主 | 卡间距 | **60**（`buttons` layout） | **12**（`:153`） | +48 | Z | `CARD_GAP` |
| D7 | 主 | 卡行 y | top **785..923** | **495.11..574.11** | 参考比我们低 **290** | Z | `_draw_select()` 的 `cy` |
| D8 | 主 | 底部信息 | `tip` 30 px / `txtVersion` 35 px | 体感 12 / 细则 10.5 | −18 ~ −24 🔴TV | Z | `_draw_select()` 底部 |
| D9 | 人 | 卡数量 | 实发 2（双人/三人），单人隐藏 | 2（1 人/2 人） | 语义不同（3P vs 1P） | N | `_draw_mode_card()` 文案 + `BTN_MODE_*` |
| D10 | 人 | 年龄提示 | 150×192 可聚焦按钮（`btnAgeTip`，且在 ButtonMgr 数组里） | 无 | 缺件 | S | 无对应物，需产品决定 |
| D11 | 备 | 背板 | 整屏相机 **1920×1080**（`findPlayerRoot/mul/ImgBg`） | 设计渐变底板 + 2 个 342×250 窗（`:1182-1201`） | — | **S** | `_draw_ready()` 顶 |
| D12 | 备 | 玩家卡 | 照片 **428×624** / 外框 **436×632**（`frame/cameraTex`,`outline`） | 卡 **556×496**，相机窗 342×250（`:1221-1222, 1281`） | 照片高 **+150%**，我们卡是横的 | **S** | `_draw_ready()` 卡宽高 + `_draw_ready_card()` |
| D13 | 备 | 卡间距 | 中心距 **776**（±388） | **684**（556+128） | +92 | Z | `_draw_ready()` |
| D14 | 备 | 状态字 | **60**（`txtLabel`） | **34**（`:1329`） | −26（−43%） 🔴TV | Z | `_draw_ready_card()` |
| D15 | 备 | 进度条 | **218×488** 竖条（`progress/bg`） | **64×280**（`:1306-1309`） | 宽 ×0.29，高 ×0.57 | Z | `_draw_ready_card()` |
| D16 | 备 | 头像 | 100×100（`headIcon`，卡上方） | 无（卡内 92 px 人形图标） | 缺件 | S | `_draw_ready_card()` |
| D17 | 备 | 头部标题 | 无（状态字就在卡上方） | 104×42 chip + 56 px 标题（`:1207-1215`） | 多一层 | S | `_draw_ready()` |
| D18 | 备 | 触发 | 全确认 → 0.3 s 后自动收（`KinestheticInfoForm.cs:113-118`） | 全就绪 → 1.5 s GO 拍（`main.gd:208`） | — | N | `main._update_ready` / `_begin_countdown` |
| D19 | 暂 | 面板 | **1148×556** 居中框（`frame`） | **无框**（`:1709-1714`） | 缺件 | **S** | `_draw_pause()` 需新增框 |
| D20 | 暂 | 动作键 | **247×196** 图标块 + 48 px 字，一排 gap 100（`btnContinue`…） | **400×54** 文本行，竖排 gap 66，字 28/26（`:1735-1760`） | 高 +142（+263%） 🔴TV | **S+Z** | `_draw_pause()` 动作区 |
| D21 | 暂 | 标题 | **60 px** `"第1关"`（`txtTitle`） | 24 kicker + **44** 标题（`:1711-1714`） | −16 | Z | `_draw_pause()` |
| D22 | 暂 | 数据条 | 参考暂停**没有**数据条 | **561.28×193.39** 三格（`:158-163`） | 多出 web 件 | **S** | 保留（web parity），见 §7 |
| D23 | 暂 | 遮罩 | 全屏 0.784（`bg`） | 只盖 200..1080（`:1709`） | 少 200 px | Z | `_draw_pause()` 首行 |
| D24 | 暂 | 动作项 | 继续 / 退出关卡 / 返回主页（`PauseForm.cs:70-91`） | 继续 / 重新开局 / 返回模式选择 | 两项语义不同 | N | `main._act_pause` + `_on_hud_button` |
| D25 | 局 | 暂停入口 | 右上 112×103 按钮（**prefab 里未激活**），实际只有 ESC | 无按钮，OK/BACK | — | N | 一致（都是按键），无需改 |
| D26 | 局 | 局内 HUD | 桃心 3×100×100 + 金币 300×100，右上/左上 | 200 px band + 记分/小地图/榜 | — | **S** | 不在四屏范围，勿动 |

🔴TV = 电视观看距离下的可读性关键项（见 §9）。

---

## 7. 与 web-parity 的冲突判定

我们的 HUD 是按 web 版量的（`Docs/WEB-COMPUTED-STYLES.md`），关键锚点：

| web 锚点 | 值 | 我们的实现 | 行 |
|---|---|---|---|
| `#uiBar` | 1920×**200**，radius **0**，底部 3 px 青缝 | `ARENA_TOP=200 / BAND_H=197 / SEAM_H=3` | `ps_hud.gd:74-76` |
| 时钟 | **120 px**（2P 96） | `CLOCK_SZ` | `ps_hud.gd:122-123` |
| 圆角族 | 4 / 3 / 2 / 0 | `R_PANEL/R_CARD/R_BADGE/R_NONE` | `ps_theme.gd:84-87` |
| `#overlay .panel.title-screen` | 780×**582.72** @ (570,248.64)，r4 | `SLAB` | `ps_hud.gd:148`；web 依据 `WEB-COMPUTED-STYLES.md:381` |
| `#overlay .ps-btn` | **351×79**，r3，19/11.5 | `CARD_W/H/GAP` | `ps_hud.gd:151-153`；web 依据 `WEB-COMPUTED-STYLES.md:169-174, 395-398` |
| `#pauseStats` | **561.28×193.39** @ (679.36,318)，格 120×110.39，28/48 | 同值 | `ps_hud.gd:158-163`；web 依据 `WEB-COMPUTED-STYLES.md:361-364` |
| `#pauseStats` 存在但**没有动作键** | — | 动作键是 port 自己加的（代码注释自认） | `ps_hud.gd:1702-1704` |
| `#startBtn` | 391.11×54 | 被 pad 键帽替代 | `WEB-COMPUTED-STYLES.md:401`；`ps_hud.gd:1049-1072` |

**逐条判定（采纳参考值会不会毁掉 web 观感）**

| Delta | 判定 | 理由 |
|---|---|---|
| D3/D4/D6/D7 模式卡 342×138 + 48 px | ⚠️ **会破 parity** | 351×79 与 19/11.5 是 web 量出来的（`.ps-btn`）。改高度只动观感、不动结构，但 48 px 主字 + 79→138 的卡会把 `#overlay` 的“电视控制台”比例改成参考的“大按钮”比例；一旦卡变高，`SLAB` 里 584 的角色行、656 的提示会全部要下移 → 板内节奏变 |
| D1/D2 去掉板 / 换 logo 图 | ❌ **结构性破坏** | 780×582.72 板 + 58 px H1 是 web 版 title-screen 的核心；参考根本没有板 |
| D8 底部 30/35 px 文本 | ✅ **安全**（且建议做） | 我们 10.5/12 px 远低于 web 自己的 16 px base，放大到 24–30 不破坏构图，只提升可读性 |
| D11/D12/D13/D14/D15/D16 准备屏 | ✅ **不冲突** | web 的 `ready` 只是 `game.state='ready'`，**没有 ready 覆盖层**（`WEB-COMPUTED-STYLES.md:452-456`）；准备屏是 port-only，参考怎么排都不影响 parity |
| D17 准备屏头部 chip | ✅ 不冲突，但是我们的品牌件 | 可保留（TV 上需要“我在哪一屏”的锚点） |
| D19/D20/D21 暂停框 + 247×196 键 | ✅ **不冲突**（动作区 port-only） | 但 `#pauseStats`（D22）必须**原样**留在 (679.36,318) 561.28×193.39；加框会把它包进去，视觉上从“web 信息面板”变成“游戏弹窗菜单”——这是观感选择，不是 parity 破坏，需 owner 点头 |
| D23 遮罩扩到全屏 | ⚠️ 轻微破 parity | web 暂停时 band 仍可见（`body.pause-open` 只加 scrim 在内容区）；把 band 也压黑会丢掉“控制台一直亮着”的设定 |
| D24 暂停项语义 | ✅ 不冲突 | 我们是单场景，没有 Hall 场景可退；“重新开局”是合理替代 |
| D25 局内暂停按钮 | ✅ 不冲突（参考自己也没启用） | — |

---

## 8. 提议：最小、可排序的改动清单

### A. 安全采纳（不碰 web 量出来的数，纯 TV 可读性 + port-only 屏）

1. **A1｜准备屏按参考重排（收益最大，风险最低）** — `ps_hud._draw_ready()` / `_draw_ready_card()`
   - 玩家卡：`556×496` → 照片 **428×624** + 外框 **436×632**（竖版）；间距中心距 **776**（±388）。
   - 状态字 **34 → 60**（`_draw_ready_card():1329`）；玩家标题 24 → 28。
   - 进度条 `64×280` → **218×488**（`:1306-1309`），仍走 `ready_fill`。
   - 相机窗从 342×250 放大到卡内 428×624（复用 `cam_rgba_tex`，**零新增纹理**）。
   - 不动：整屏不透明底板、头部 chip、BACK 行为、1.5 s GO（这些是 port 的导航/品牌件）。
2. **A2｜暂停动作区改成参考的图标块** — `ps_hud._draw_pause()` `:1734-1763`
   - `400×54` 文本行 → **3 × 247×196**，gap **100**，居中 x 490..1430；文字 **48 px**，放在块**下方**（top 715..785 的等价位置）。
   - 位置：现动作区 y 537.39 起，196 高 + 70 字 = 537..803，不与 `#pauseStats`(318..511.39)、榜(1536..)冲突。
   - `_btns` 命中框同步；`pause_focus` 不变。
   - **前提**：不加 1148×556 外框（加框是 §8B 的事），所以只动按钮，不改 parity。
3. **A3｜暂停遮罩对齐参考的整屏** — 可选；建议**保留** 200 起（见 §7 D23），只把标题字号 44 → **60**、kicker 24 → 26。
4. **A4｜模式屏底部文本 10.5/12 → 24/26** — `_draw_select():1011-1019`；纯可读性，不动卡片。
5. **A5｜导航不变**：BACK/OK/方向循环与参考一致；**不要**把 SELECT 的 BACK 从“退出”改成“退后台”（盒子场景是 TV App，退出是预期）。

### B. 会实质改变观感（需 owner 拍板）

1. **B1｜模式卡 351×79 → 342×138，主字 19 → 48**（`ps_hud.gd:151-158, 1152-1158`）
   - 卡变高后：角色行 584.64 → ~660，提示 656/683 → ~740/770，`SLAB` 底 831 仍装得下；但整个 title 屏的“密度”会从 web 的紧凑控制台变成参考的大按钮。
   - 若只想折中：**只把主字 19 → 32、卡高 79 → 104**，保留 351 宽（`web` 的宽不变，观感变化小一半）。
2. **B2｜加暂停外框 1148×556**（`frame`）：会把 `#pauseStats` 包进弹窗，web 的“信息面板”感消失。
3. **B3｜主界面去板 + 换 1004×401 logo 图**：等于放弃 web 的 title-screen；需要 logo 资源与美术确认。
4. **B4｜人数选项对齐参考的“双人/三人”**：我们是 1P/2P + AI，参考 MVP 是 2P/3P 真人。语义不同，**不建议**为了“像”而改。

### 建议顺序（每步可独立验收）

`A4`（改 4 个数，5 分钟）→ `A2`（暂停动作区，1 个函数）→ `A1`（准备屏重排，1 个函数 + 卡绘制）→ `A3` → 再看 owner 对 `B1/B2` 的决定。

---

## 9. 设备风险（HP52S0 / Amlogic / 遥控器 / 1080p / GL Compatibility）

| 风险 | 具体数 | 判断 |
|---|---|---|
| **遥控器无触摸无键盘** | 参考最小可点目标 **247×196**；我们最小 **400×54**（高 54） | 54 px @1080p 在 3 m 处约 **0.55°** 视角，低于电视 UI 常用的 1° 下限；参考的 196 高约 2°，**A2 必须做** |
| **TV 观看距离** | 我们的 10.5 / 11 / 11.5 / 12 px 文本 @3 m ≈ **0.12°**，实际不可读；参考最小 30 px（≈0.31°），主文案 48–60（≈0.5–0.63°） | 🔴 D4/D8/D14 是硬伤；A1/A4 解决 |
| **1920×1080 固定** | `project.godot:23-24` + `stretch=canvas_items`；参考 1920×1080 matchWidth | 同基准，可 1:1 搬数；但 `aspect=expand` 在非 16:9 屏会露边，盒子是 16:9 无风险 |
| **GL Compatibility** | 参考的整屏相机=1 次全屏 blit；我们已有一张 `cam_rgba_tex`，准备屏 2 张卡各 1 次 region blit | 只增 draw call 不增纹理/RT；`_draw_ready` 现已是 O(固定)，A1 后仍 O(1)/卡，**帧预算安全** |
| **只有 5 个键** | 参考：方向 4 + OK + BACK；我们一致 | 导航不用改 |
| **暂停时 band 仍活** | 我们 `_draw_play()` 在 PAUSE 下跳过记分/小地图/榜（`ps_hud.gd:1440`），band 保留；参考暂停把整屏压黑 | 观感选择，非 bug |
| **准备屏 3 人布局** | 参考 `scale 0.7`、±388；我们引擎只支持 2 真人槽 | 不实现 3 槽，避免抄到“克隆按钮不在 ButtonMgr”的 bug |

---

## 10. 证据索引（关键 path:line）

**参考（Unity）**
- 画布：`Assets\AGame\Scenes\Level_1_Backup.unity:2656-2661`
- 表单 id：`Assets\AGame\Scripts\Definition\Constant\Constant.UIForm.cs:16-105`
- 启动：`Assets\XXFramework\Managers\Procedure\ProcedureState\ProcedureEnterGame.cs:19-30`
- 主界面死代码：`StartForm.cs:36-50`；`ModelForm.cs:30-46, 88-145, 154-215`
- 开局队列：`GameDataManager.cs:161-181`、`304-315`；`TransitionForm.cs:12-49`；`XXSceneManager.cs:176-181`
- 准备：`KinestheticInfoForm.cs:13, 63, 113-118, 196, 230-279, 329-382`；`XXAndroidParseData.cs:92, 1046-1066, 615-630`
- 暂停：`XX_LevelManagerBase.cs:81-101`；`PauseForm.cs:15-33, 35-59, 61-92`；`XX_LevelManager.cs:106-117, 318`
- 遥控：`ButtonMgr.cs:86-108`；`App.cs:225`；`XXButton.cs:34`
- prefab：`Assets\AGame\UIPrefab\UIForms\{StartForm,ModelForm,KinestheticInfoForm,PauseForm,LoadingForm,TransitionForm,GameInfoForm}.prefab`

**我们（Godot）**
- 画布：`project.godot:23-28`、`:32`（gl_compatibility）
- HUD 常量/绘制：`src\present\ps_hud.gd:74-88, 148-170, 928-1019, 1178-1332, 1705-1784`
- 主题：`src\present\ps_theme.gd:84-87, 182-214`
- 流程/按键：`src\main.gd:177-182, 1706-1766, 1928-2006, 5284-5351, 5378-5412`
- 结算：`src\present\ps_stage.gd:212-235`
- web 基准：`Docs\WEB-COMPUTED-STYLES.md:107-108, 169-174, 361-364, 381, 395-401, 452-456`
- 已有流程文档（本次结果与之一致）：`Docs\FLOW-REFERENCE-1024.md:8-16, 66-76`
