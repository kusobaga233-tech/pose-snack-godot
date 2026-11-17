# 流程参考：1024《蟹蟹大冒险》模式选择 → 准备 → 开局

参考工程：`D:\CODEX-PROJ\yoodou\1024-xiexie\game_1024`（Unity 2022.3 + CorgiEngine + Youdoo 体感 SDK）。
证据：C# 脚本（主）、`Assets/AGame/UIPrefab/UIForms/*.prefab`（布局/字号/颜色）、`Assets/AGame/DataTable/Localization/ChineseSimplified.bytes`（UI 文案，二进制表，已解析）。该工程**没有集中式游戏状态机**：流程 = UI 栈 + 准备期开关 `isCheckPersonReadyIng` + 每槽位 `DetectionState{Unknown,OutOfArea,InArea,Ready}`，UI 每帧轮询数据（`onCanGameStart` 等事件声明了但没人订阅）。

## 1. 状态顺序与转移

| # | 状态（工程里的名字） | 进入 | 离开 |
|---|---|---|---|
| 0 | `HealthTipForm` splash → `CheckVersion` → `PreLoad` → `ProcedureEnterGame` | 启动 | PreLoad 100% |
| 1 | `KinestheticInfoForm`(206) 常驻打开，其 onOpen 里再开 `ModelForm`(209) | EnterGame | 立刻叠加模式选择（Editor 下跳过 206） |
| 2 | **模式选择** `ModelForm` | 上一步 | 点按钮 → 设 `playerCount` → `StartStage` |
| 3 | **转场** `TransitionForm`(213) | `StartStage` | 1.3s 自关；1.0s 时开 Loading |
| 4 | **加载** `LoadingForm`(101)，同一帧准备面板开始滑入 | `LoadScene(Level_1)` 的 `onLoadingFormOpen` | 加载完 fade 0.3s |
| 5 | **准备** `KinestheticInfoForm.findPlayerRoot`（常驻体感界面的子面板，不是独立场景） | 上一步回调 `OpenFindPlayerForm()` + `ModelForm.Close()` | 全员确认 |
| 6 | **游玩** `XX_LevelManager.State.Playing` | `FindPlayerFormClose` 事件 → `_UnFreeezRole()` | 成功/失败 |
| 7 | **结算** `SuccessForm`/`FailureForm` → `ResultForm` 6s | 结束 | `BackToModelForm()` 回到 2 |

- 返回/取消：准备期 Esc → `_PauseGame()` 见 `IsFindPlayerFormShowed` → `BackToModelForm()`（关面板 + 卸载场景 + 重开 ModelForm）；模式界面 Esc → `MoveTaskToBack()`（退后台，不退出）。
- 槽位子状态机：Unknown（没锁到人）→ OutOfArea（不在自己区 / 抱臂）→ InArea（区内静置 60 帧）→ Ready（举手满 120 帧）→ 已确认（`personPlayerIds[i] != -1`）。已确认后再出区或抱臂 → 回落 OutOfArea，进度清零，需重新举手。

## 2. 模式选择屏

- 文案（本地化 key）：`ModelForm.Model0Text`=**单人模式**、`Model1Text`=**2人**、`Model2Text`=**3人**。prefab 里 2 人按钮的字面文本是「双人模式」，运行时被 key 覆盖为「2人」。英文表：`One-Player` / `2 Players` / `3 Players`（参考工程自己也不统一）。
- 布局（设计分辨率 1920×1080，背景图 2448×1080）：满屏插画 `ImgBg`（珊瑚/海胆装饰）；`logo` 居中 (0,331)、1004×401；按钮行 `buttons` 在 (0,-314)，每个 342×138、字号 48、白字，父节点 HorizontalLayoutGroup（两/三个并排居中）；左上 `btnAgeTip` 适龄提示 150×192；右下 `txtVersion` 字号 35；底部居中健康忠告 `tip` 字号 30、白色 70%；2 人按钮右上 `ic_vip` 角标 103×94（MVP 已隐藏）。入场：logo 从 y=780 落到 331（0.5s OutBack）；按钮 scale 0→1（0.35s OutBack，延迟 0.4s）。
- 确认：**单击即确认**，无二次确认、无默认高亮、无键盘/遥控/举手路径；Esc 只把 App 切后台。点击后同帧：`click` 音效 → `playerCount` → `InitGameInfo(playerCount, PartitionView)` → `StartStage(ToLevelId(1))`。
- 当前 MVP 出包：`_btnModel_0.SetActive(false)`（单人入口被隐藏），可见 = 2人 + 3人；代码里三个入口都直接进各自模式第 1 关（1P=101、2P=1001、3P=2001）。

## 3. 准备状态（Ready）

- 出现：整块 `findPlayerRoot` 从 y=+1400 滑到 0（0.3s OutQuad），关闭时滑回 +1400（0.3s）。它是**盖在已加载关卡上的全屏面板**。背景：1P 用 `bg_single.jpg`（整屏珊瑚 #FF8574 + 海洋线稿）；2P+ 用 `bg_mul.jpg`（左珊瑚 / 右淡紫 #B68BE8 对半）；**背景里没有烘焙文字**。
- 每人一张卡：`player_1` x=-388、`player_2` x=+388，卡 scale 0.9。卡内：自己的相机裁切 `cameraTex` 428×624（水平镜像）、描边 `outline` 436×632、竖向进度条 `progress/fill` 218×488（P1 #E03C14、P2 #8417A0，底槽白 39%）、完成印章 `tag`（绿✓ 165×164）、角色头像 `role`（y=-417）、圆头像+人脸小图 `headIcon`（y=+398）、状态文字 `txtLabel`（y=+503，字号 60）。
- 提示文案（按槽位状态，全部来自本地化表）：
  - `KinestheticForm.WaitingPlayers` = **等待玩家进入屏幕**（该区没锁到人）
  - `KinestheticForm.FaceRecognition` = **人脸识别中...**（锁到人，人脸未返回；仅开人脸识别时出现）
  - `KinestheticForm.RaiseHand` = **请举手确认准备**（已识别或已判游客，等举手）
  - `KinestheticForm.Ready` = **已准备**（已确认）
- 常驻角标：左下 `KinestheticForm.RCTip` = **按上键可更换用户**（+ 上箭头图标 87×180，仅开人脸识别且有头像时出现）；右下 `KinestheticForm.RefuseReady` = **双手抱臂拒绝准备**（+ 抱臂图标 168×168）。
- 就绪判定（每人）：站在自己判定区内 → 先静置 60 帧（`readyShowTime`）→ 举手（`poseType & 3`，左右手任一即可）连续 120 帧（`readyNeedFrame`）→ 确认。**不是必须双手，也不是固定计时**。
- 进度表现：不是圆环，是**竖向进度条 `fillAmount = 举手帧数 / 120`**；到 1 时印章弹出（0.3s 缩放 + 360° 自转）同时整条隐藏。
- 全员就绪：`CompleteFindPlayer()` → 所有条瞬间补满 → 0.3s → 面板滑出 0.3s → 派发 `FindPlayerFormClose` → 角色解冻。**没有 3-2-1 倒计时**，从最后一人举手到可操作约 0.6s；之后 1s 内屏蔽跳跃手势，避免举手误触发。

## 4. 1P / 2P 差异

| 项 | 1P | 2P（3P） |
|---|---|---|
| 判定区（相机归一化 x） | [0.40, 0.60] | P0 [0.25,0.45] / P1 [0.55,0.75]（3P: [0.2,0.4]/[0.45,0.55]/[0.6,0.8]） |
| 卡 | 1 张，x=0 | 2 张 ±388（3P 3 张，scale 0.7） |
| 背景 | `bg_single` | `bg_mul` |
| 相机 | 整屏 1 路 | PartitionView 切成 N 条竖条；**槽位 0 = 画面右侧**（镜像），卡内纹理交叉绑到对侧父节点 |
| 文案 / 关卡 / 出生 | 无差异；101；(0,0) | 无「等待第二位玩家」专门文案，第二张卡就是「等待玩家进入屏幕」；1001/2001；全在 (0,0)，P2+ 0.1s 后朝左翻转，3P 左右再错开 ±1.4 |

游玩不分屏：一关一张图，一个镜头取全员中点。

## 5. 失败 / 超时

- **没有整体超时**：没人举手就一直等，唯一出路是 Esc 回模式选择，没有「重试」按钮。
- **没有摄像头错误界面**：权限/相机失败由 SDK 兜底，游戏里没有任何提示、降级或重试；追踪不来就永远停在「等待玩家进入屏幕」。
- 人脸识别卡住：每个锁到的人最多等 5s（真实时间），超时按游客（userId=-1）放行举手。
- 准备期离开判定区：进度立刻清零、文案回「请举手确认准备」；连续丢 60 帧（≈2s）才释放槽位 → 文案回「等待玩家进入屏幕」。双手抱臂（`poseType & 4`）则立刻取消锁定/准备（`onPlayerNotGame`），需重新站回区内举手。
- **游玩中有人离开**：丢 60 帧后清槽 → `isCheckPersonReadyIng = true` → 准备面板**在跑着的关卡上重新滑出**，游戏不暂停；此人在区内重新出现会被直接认回（不需要再举手）。
- 结算：成功/失败 → 6s「即将返回主界面 {0}秒」→ 回模式选择。

## 6. 数字

| 项 | 值 | 说明 |
|---|---|---|
| `readyNeedFrame` | 120 帧 | 举手维持帧数；注释称「30 帧约 1 秒」→ 按 ~30fps ≈4s |
| `readyShowTime` | 60 帧 | 进区后静置期，≈2s |
| `missingFrameThreshold` | 60 帧 | 丢多少帧算离场，≈2s |
| `FACE_RECOGNITION_TIMEOUT_SECONDS` | 5.0s | 人脸超时降级游客 |
| 判定区半宽 / 锁定置信度 | 0.15 / 0.6 | 通用算法 ±0.15（PartitionView 下被 §4 硬编码覆盖）；置信度低于 0.6 丢弃该人锁定 |
| 面板滑入 / 滑出 / 全员就绪→关闭 | 0.3s / 0.3s / 0.3s | OutQuad；关闭后 1.0s 手势锁 |
| 模式界面入场 | 0.5s / 0.35s(延迟 0.4s) | logo / 按钮 |
| 转场 + 加载 | 1.3s / 1.0s 起 | TransitionForm / 场景加载 |
| 结算返回 | 6s | ResultForm 倒计时 |

## 7. 我们 Godot 版应该长什么样

现状：`src/main.gd` 已有 `MODE_MENU/MODE_PLAY/MODE_PAUSE/MODE_SETTLE`；`ps_hud._draw_menu()` 把「人数 1P/2P」做成菜单卡里一排小按钮，之后直接进 3s「准备/READY」倒计时，**没有准备/找人阶段**。

1. 把人数选择从规则卡里拿出来，做成**独立第一屏**：两张大按钮「单人模式」「双人模式」，点了直接进下一步，不预选。
2. 新增 `MODE_READY`（MENU 与 PLAY 之间）：不推进模拟、不刷新蛇、不计时，只跑追踪与就绪判定。
3. 准备屏原样复用这四句：等待玩家进入屏幕 / 人脸识别中... / 请举手确认准备 / 已准备。
4. 每人一张卡：1P 居中一张；2P 左右各一张（左卡=画面右侧的人，保持镜像一致），P1 珊瑚红 #E03C14、P2 紫 #8417A0。
5. 进度用**竖向条**（不是圆环），`fillAmount = 已举手时长 / 门槛`；满格弹绿色✓印章并隐藏进度条。
6. 就绪条件 = 站在自己半区 + 举手维持；建议 1.5s 静置 + 2.0s 举手（比参考短，见待定 B）。
7. 全员就绪 → 0.3s 定格 → 面板 0.3s 滑出 → **此时才启动本局模拟**（参考工程 2P/3P 是关卡在面板背后已经在跑，我们不能学）。
8. 有人出区或放下手：进度清零、文案回「请举手确认准备」，不要直接踢人；游玩中有人掉线则**暂停本局**并重新滑出准备面板等这个人（参考是不暂停）。
9. Esc / 返回：准备期回模式选择，模式选择期回主菜单，任何一屏都不能卡死。
10. 摄像头 / 追踪不可用：参考工程没有这条路径，我们必须自己补一句提示（见待定 C）。
11. 文案全部走 `_cn(cn, en)` 双语，键名沿用参考语义分组（mode / ready / reason）。

**待定（需协调人拍板）**
- A. 是否保留现有 3-2-1「准备/READY」倒计时：参考工程准备完**直接开始**，没有倒计时；建议保留 1.5s 短倒计时作开场仪式，但别和 ready 混为一谈。
- B. ready 门槛时长：参考 2s 静置 + 4s 举手（按 30fps 折算）对 2 分钟的贪吃蛇偏长；建议 1.5s + 2.0s，或只保留 1.5s 举手。
- C. 失败兜底：要不要「摄像头未就绪 / 识别不到人」超时（例如 30s 后给「重试 / 用键盘玩」）。参考没有，真机会被投诉。
- D. 模式标签统一成「单人模式 / 双人模式」（参考是「单人模式 / 2人 / 3人」，不统一）。

## 8. 证据索引

路径相对 `1024-xiexie/game_1024/`。

1. `Assets/AGame/Scripts/UI/KinestheticInfoForm.cs:196-204` — 四句提示文案的取值分支；文案原文见 `Assets/AGame/DataTable/Localization/ChineseSimplified.bytes`（键 14/15/51-56/64，同目录 `English.bytes` 为英文版）。
2. `Assets/AGame/Scripts/UI/KinestheticInfoForm.cs:389-413` — 进度=举手帧/120，满格出印章并隐藏条。
3. `Assets/AGame/Scripts/UI/KinestheticInfoForm.cs:113-118,346-370` — 全员确认后 0.3s 关闭；面板滑入 0.3s 与参数重置。
4. `Assets/AGame/Scripts/UI/KinestheticInfoForm.cs:236-260` — 1P/2P/3P 卡片排布与相机纹理互换。
5. `Assets/AGame/Scripts/Game/XXYoudoo/XXAndroidParseData.cs:92,126,135,140` — 120 / 60 / 60 帧、5s 人脸超时。
6. `Assets/AGame/Scripts/Game/XXYoudoo/XXAndroidParseData.cs:983-1011` — 就绪判定：区内静置 → `poseType & 3` 累计 120 帧 → 确认。
7. `Assets/AGame/Scripts/Game/XXYoudoo/XXAndroidParseData.cs:937-956` — 抱臂（`& 4`）取消锁定。
8. `Assets/AGame/Scripts/Game/XXYoudoo/XXAndroidParseData.cs:1046-1071` — 全员确认 → `CompleteFindPlayer()`。
9. `Assets/AGame/Scripts/Game/XXYoudoo/XXAndroidParseData.cs:615-630` — 游玩中丢人 → 重新打开准备面板。
10. `Assets/AGame/Scripts/UI/ModelForm.cs:40-45,109-124,138-149` — 隐藏单人入口、2人/3人点击链路、`InitGameInfo(PartitionView)`。
11. `Assets/AGame/Scripts/DataManager/GameDataManager.cs:161-181` + `Assets/AGame/Scripts/UI/TransitionForm.cs:34-36` — 转场 1.3s、1.0s 起加载。
12. `Assets/XXFramework/Managers/Procedure/ProcedureState/ProcedureEnterGame.cs:18-30` — 启动顺序（先常驻体感界面，再模式选择）。
13. `Assets/Third Party/Youdoo/Scripts/AndroidServerInfo/Rendering/PlayerMatchView.cs:125-144` — 各人数判定区硬编码值。
14. `Assets/Third Party/Youdoo/Scripts/AndroidServerInfo/AndroidParseData.cs:117-119` — poseType 位定义（1 左手 / 2 右手 / 3 双手 / 4 抱胸 / 8 叉腰 / 16 蹲）。
15. `Assets/AGame/Scripts/Game/XXCorgiEngine/XX_LevelManager.cs:471-476` — 准备面板关闭才解冻角色。

次要旁证（其它 Youdoo 项目，仅作交叉印证，不作为本工程结论）：`1031-tennis/.../CheckPlayerHumanPoseUIPage.cs:39-45` 把同样四步写成 `StandStable→RecognizeFace→RaiseHand→Ready`，文案「请站在画面中间 / 正在识别人脸 / 请举手准备 / 已准备」，`standStableSeconds = 1f`，举手 2s 起算，人脸 10s 超时——与 1024 的四态模型一致，但门槛更短、文案更清楚。
