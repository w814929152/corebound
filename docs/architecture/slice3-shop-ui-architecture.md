# 切片3 · 实时商店覆盖层 —— 架构设计 + Godot 4.7.2 API 调研

- **作者**：程基岩（工程主理人）
- **引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`（本机实测，非推测）
- **上游**：`design/gdd/shop-reroll.md` **v1.1 定稿**（§2.1 五态状态机 · §2.2 C1 减速预算 · §2.3 C2 高亮规则表 · §2.4 C3 双焦点界面 · §1.3 五条红线）· `design/gdd/mechanics-tower-life-death.md` v1.0（红线 T-C1）· `design/gdd/damage-pipeline.md`（§4.3 三套时钟）
- **下游（被约束）**：`docs/architecture/control-manifest.md`（口径冻结清单 · N1/N2 · P1–P8 · G1–G8）
- **状态**：🟢 **架构已定稿 · 骨架已跑通 · 167 项断言全过**（切片3 自测 142 + 场景冒烟 25）· ✅ **3 项拍板（Q-S3-A/B/C）已于 2026-10-01 落定并回写 GDD v1.2**（§9 各小节附拍板结果）

---

## 0. 摘要（给赶时间的人）

| 验收项 | 结果 |
|---|---|
| 场景在 4.7.2 跑起来（headless + 窗口） | ✅ 退出码 0 |
| 五态 `time_scale` / `paused` 逐条对上 GDD §2.1 | ✅ 7 次切换 × 2 项 = 14 项全对 |
| 减速预算 unscaled 计时（10 实时秒 → 20→10） | ✅ 实测 **10.005 s 消耗 / 剩 9.940**，战场只推进 **3.502 s**，思考增益 **×2.86** |
| 不破坏切片1/2 的 2228 断言 | ✅ 全量重跑退出码 0 |
| 🔴 SR-R5（`time_scale` 永不为 0） | ✅ 30 组（6 波 × 5 态）恒 > 0，且代码里有 `assert` 兜底 |

**本轮最重要的三个架构决策：**

1. **时钟逻辑与引擎副作用分离。** 纯逻辑 `TimeStateMachine`（RefCounted，**零副作用**，不碰 `Engine`/`SceneTree`）＋ 适配层 `TimeDirector`（Node，`process_mode=ALWAYS`，唯一允许写 `Engine.time_scale` / `get_tree().paused` 的地方）。→ 五态口径可在 headless 下**不建场景树**直接单测。
2. **unscaled 计时只用 `Time.get_ticks_msec()`。** 4.7.2 实测：`_process(delta)` 的 delta **被 `time_scale` 缩放**（`Σdelta/Σ真实秒` = 1.006 / 0.350 / 0.250），所以 `delta / Engine.time_scale` 成立；但 🔴 `Engine` 类在 4.7.2 **没有** `get_process_delta_time()`（ClassDB 实测），且 `time_scale=0` 时 delta 恒为 0 → `δ/ts = 0/0 = NaN`。**故 `Time` 差值是唯一安全口径。**
3. **布局算尺单点裁决。** `ShopLayout.drawer_width() = maxf(560, 0.32×屏宽)`，战场与抽屉都读它。✅ **Q-S3-C 已拍板（2026-10-01）**：视口提到 **1920×1080**（GDD 基准屏，抽屉 614.4 = 32% / 战场 68%，与 GDD 完全吻合）；`maxf` 算尺保留作非基准屏（窗口 resize / `expand`）安全网。落地见 §9 拍板结果。

---

## 1. 本轮范围（严格边界，未越界）

| 做 ✅ | 不做 ❌ |
|---|---|
| 五态状态机落到场景树（节点结构 / 时钟口径 / 信号流） | 完整商店逻辑（发牌 / pity / 锁定 / 刷新扣费） |
| Godot 4.7.2 API 调研（§7，附 URL + 本机实测） | 真实塔 / 怪 / 卡数据 |
| 可运行空场景骨架（占位节点）+ 实测打印 | C2 智能高亮的**内容**（只钉死结构） |
| 后续切片的接口点预留（§8） | 美术资产、音效、存档 |

---

## 2. 场景树设计

```
Main (Node)                                   scenes/main.tscn · scripts/ui/boot.gd
└── [窗口模式] BattleShop (Node)                scenes/battle_shop.tscn · scripts/ui/battle_shop.gd
    │
    ├── TimeDirector (Node)            🔴 process_mode = ALWAYS      scripts/ui/time_director.gd
    │      └── 持有 TimeStateMachine（纯逻辑）；唯一写 Engine.time_scale / get_tree().paused
    │
    ├── Battlefield (Node2D)           🔴 process_mode = INHERIT(→PAUSABLE)
    │      └── scripts/ui/battlefield_placeholder.gd   ← 占位：怪点随 scaled delta 移动
    │          暂停时**必须**停 → 这是"世界真的停了"的证据
    │
    ├── HudLayer (CanvasLayer layer=10)    ALWAYS
    │      └── Hud (Control)                          scripts/ui/hud.gd
    │
    ├── ShopLayer (CanvasLayer layer=100)   🔴 ALWAYS（GDD 交接点 2 硬要求）
    │      └── ShopOverlay (Control)                  scripts/ui/shop_overlay.gd
    │
    ├── PulseLayer (CanvasLayer layer=120)  ALWAYS
    │      └── ThreatPulse (Control)                  scripts/ui/threat_pulse.gd
    │
    └── CoreHpLayer (CanvasLayer layer=130) 🔴 ALWAYS —— 穿透层，必须高于 100
           └── CoreHpBar (Control)                    scripts/ui/core_hp_bar.gd
```

**为什么这么切：**

| 决策 | 理由 |
|---|---|
| 战场放 `Node2D`（不是 Control） | 后续要换成 `SubViewport`（3D 等距战场）；Control 不能当 Node2D 的子节点做世界绘制 |
| 战场 `process_mode = INHERIT` | 根 Window 默认 `PAUSABLE` → 安全窗下世界**真的停**；这是唯一必须随暂停停的节点 |
| 所有 UI 层 `ALWAYS` | 商店/HP 条/脉冲在安全窗下必须继续跑（交接点 2 / 锚点 6 第 2 条） |
| 层号读 `MvpConfig.LAYER_*` | GDD §2.4 分层表是口径，口径只在 SSOT 里出现一次 |
| 依赖注入不用 `get_node` 满天飞 | `battle_shop.gd` 在 `_ready()` 把 director 注入各 UI 子节点；UI **不持有**游戏状态（control-manifest §5） |

### 2.1 布局算尺（C3 双焦点）

```gdscript
# scripts/ui/shop_layout.gd —— 唯一裁决点
static func drawer_width(vw: float) -> float:
    return maxf(MvpConfig.OVERLAY_MIN_WIDTH_PX, vw * MvpConfig.OVERLAY_WIDTH_RATIO)
```

| 视口宽 | 抽屉 | 占屏 | 战场 | 备注 |
|---|---|---|---|---|
| **1920（✅ 本工程，Q-S3-C 拍板）** | **614.4** | **32.00%** | **1305.6 (68%)** | GDD 基准屏，两条约束正好一致；`project.godot` 已钉死 |
| 1280 | 560.0 | 43.75% | 720.0 (56.25%) | 非基准屏安全网：最小宽压过比例（窗口 resize / expand 时可能出现），**有意行为** |
| 1000 | 560.0 | 56.0% | 440 | 下限兜底，绝不突破 560 |

---

## 3. 五态状态机实现方案

### 3.1 分层：纯逻辑 ↔ 引擎副作用

```
┌────────────────────────────────────────────┐
│ scripts/engine/time_state_machine.gd       │  RefCounted · 零副作用
│  · state / wave / budget_left              │  ← headless 可直接单测
│  · clock()      → 时钟口径 Dictionary       │     不需要场景树、不需要帧
│  · tick(dt_real)→ 扣预算 + 自动转态         │
│  · transition() / open_shop() / wave_end() │
└────────────────────┬───────────────────────┘
                     │  组合（不是继承）
┌────────────────────▼───────────────────────┐
│ scripts/ui/time_director.gd   (Node·ALWAYS)│  唯一有副作用的地方
│  · 每帧算 dt_real（Time 差值）→ sm.tick()   │
│  · 把 clock() 写进 Engine.time_scale        │
│  ·                    get_tree().paused     │
│  · 状态变化 → 广播信号；收输入 → 发意图信号  │
└────────────────────────────────────────────┘
```

**为什么拆**：GDD §2.1 说"五个态的时钟口径各不相同，最容易写错"。把口径变成一张**可单测的纯表**，写错就会在 `tests/test_suite_slice3.gd` 里红，而不是在试玩时表现为"预算莫名不消耗"。

### 3.2 时钟口径表（`clock()` 的返回值 = GDD §2.1 表格的镜像）

| 态 | `time_scale` | `paused` | 消耗预算 | 抽屉 |
|---|---|---|---|---|
| ① `Combat` | `1.0` | `false` | ❌ 冻结 | `CLOSED` |
| ② `ShopDilated` | `0.35`（W1–5 `0.25`） | `false` | ✅（W1–5 ❌） | `LIGHT` |
| ③ `ShopRealTime` | `1.0` | `false` | ❌ 已耗尽 | `LIGHT`（🔴 不强制关闭，Q-SR2） |
| ④ `SafeWindow` | `1.0`（🔴 不为 0） | `true` | ❌ 冻结 | `HEAVY`（可被玩家手动收起） |
| ⑤ `PlacementMode` | `0.25` | `false` | ✅（W1–5 ❌）复用同池 | 🔴 `CLOSED` |

### 3.3 显式转换表（🔴 不许用布尔 `is_shop_open`）

| from | 允许的 to |
|---|---|
| ① Combat | ② ③ ④ |
| ② ShopDilated | ① ③ ⑤ ④ |
| ③ ShopRealTime | ① ⑤ ④ |
| ④ SafeWindow | ① ⑤ |
| ⑤ PlacementMode | ② ③ ④（回到**进入前**的态） |

非法转换 `transition()` 返回 `false` 并把原因写进 `last_error()`，不抛异常（输入噪声不该崩游戏）。自测里 4 条非法路径被逐条断言。

---

## 4. 时钟与减速预算

### 4.1 三套时钟（GDD `damage-pipeline` §4.3 / 交接点 1）

| 时钟 | 取法 | 用在哪 |
|---|---|---|
| **游戏时钟**（scaled） | `_process(delta)` 的 `delta` | 战场推进 / 怪物移动 / 塔开火 |
| **实时时钟**（unscaled） | `Time.get_ticks_msec()` 差值 | 🔴 **减速预算** / 边缘红光脉冲 / UI 动画 |
| **事件时钟**（dirty flag） | 信号 → 帧末统一刷新 | 后续切片的 C2 智能高亮（SR-6，禁止每帧重算） |

### 4.2 预算计时（GDD §5.2 的落地）

```gdscript
# scripts/ui/time_director.gd::_process
var now := Time.get_ticks_msec()
var dt_real := float(now - _last_msec) / 1000.0      # 🔴 unscaled
_last_msec = now
if dt_real > MvpConfig.MAX_FRAME_REAL_DT:            # 🟡 夹子 → Q-S3-B
    dt_real = MvpConfig.MAX_FRAME_REAL_DT
real_seconds += dt_real        # 玩家实际思考时间
game_seconds += float(delta)   # 战场实际推进量（scaled）
sm.tick(dt_real)
```

**为什么不用 `delta / Engine.time_scale`（两条原因，都是实测）：**

1. `time_scale = 0` 时 `delta` 恒为 **0** → `0 / 0 = **NaN**` → 预算被 NaN 污染、且不会崩，最难查。这就是 SR-R5 的物理原因（探针日志 D 段实测 `is_nan(0/0) = true`）。
2. 4.7.2 的 `Engine` 类**没有** `get_process_delta_time()`（ClassDB 实测），拿不到"引擎自己的未缩放 delta"，只能反除。

→ 文档里 GDD 给的两种口径都成立，**但工程上只保留 `Time` 差值一种**，反除只作为交叉校验留在文档里。

### 4.3 实测证据（`docs/phase3/slice3-scene-smoke.log`）

```
验收标准 3：开商店 10 实时秒 → 预算 20 → 10
  实时经过 = 10.005 s（unscaled，Time 差值）
  战场推进 = 3.502 s（scaled，Σdelta）        ← 10.005 × 0.35 = 3.502 ✅
  预算消耗 = 10.005 s
  预算剩余 = 9.940 / 20 s                     ← 20 − 10.005 = 9.995，差 0.055s（首帧对齐误差）
  思考增益 = ×2.86（实时 / 游戏）              ← 与 GDD §5.2 的 "2.86×" 完全一致
```

---

## 5. 信号流

```
                       ┌──────────────────────────┐
   Tab / Esc / R / 1-3 │                          │
   ───────────────────►│   TimeDirector (ALWAYS)  │
                       │   _unhandled_key_input   │
                       └────────────┬─────────────┘
                                    │ 语义化入口（open_shop / wave_end / …）
                                    ▼
                       ┌──────────────────────────┐
                       │  TimeStateMachine（纯）   │
                       │  clock() / tick()        │
                       └────────────┬─────────────┘
                                    │ 时钟口径 Dictionary
                    ┌───────────────┼────────────────┐
                    ▼               ▼                ▼
        Engine.time_scale   get_tree().paused    广播信号
                                                   │
    ┌──────────────┬──────────────┬───────────────┼──────────────┐
    ▼              ▼              ▼               ▼              ▼
state_changed  budget_changed  drawer_mode_   wave_started   budget_drained
    │              │            changed            │              │
    ▼              ▼              ▼                ▼              ▼
 Battlefield     HUD         ShopOverlay      （后续 wave-      HUD（标红）
 （压暗/恢复）   （读数+条）  （抽屉形态）      spawner 订阅）
```

**已声明、后续切片要接的意图信号**（骨架阶段只发不实现）：
`reroll_requested` / `buy_requested(slot)` / `lock_toggled(slot)` / `placement_confirmed(slot)` / `placement_cancelled` / `salvage_requested`

🔴 依赖方向：商店**只发意图**，不改卡牌/管线状态（SR-5 / CD-E / control-manifest §5）。

---

## 6. 🔴 C-3 / SR-R2 合规（骨架阶段就钉死结构）

| 规则 | 落地 |
|---|---|
| **只标事实，绝不标推荐** | 三个商品位**尺寸/配色/字号完全一致**（`custom_minimum_size = 150×190`，同 `C_SLOT`）→ 杜绝 X3「用布局暗示推荐」 |
| 禁止排序/评分/星级 | 骨架里根本没有"排序"数据结构 |
| 禁止第三种置灰理由 | 商店只有 H1 买不起 / H8 无合法目标两种置灰；骨架阶段未实现置灰 |
| 自动回归 | `tests/test_suite_slice3.gd` §9 会 **grep 商店源码正文**（自动剥掉注释行），命中 `推荐 / 最优 / best / recommend / suggest` 即 FAIL |

> 🟢 这条自检是**可自动化的红线**，比人工 review 可靠。后续填卡面内容时它会一直守着。

---

## 7. Godot 4.7.2 API 调研（🔴 程基岩训练数据只到 4.3，以下**全部本机实测**）

> **证据等级说明**：
> **[实测]** = 本机 4.7.2 跑出来的数字，证据在 `docs/phase3/slice3-godot47-api-probe.log`；
> **[文档]** = 官方文档（4.7 分支），经 WebSearch 取回的原文摘要；
> **[ClassDB]** = 用 `ClassDB.class_get_method_list()` 在本机枚举出的真实类表面。

### 7.1 `Engine.time_scale`

- **[文档]** `float time_scale = 1.0` — "affects `Timer`, `SceneTreeTimer`, and all other simulations that make use of delta time (such as `Node._process()` and `Node._physics_process()`)". 官方明确 "recommended to keep this property above **0.0**, as the game may behave unexpectedly otherwise"，且 "does **not** affect audio playback speed（用 `AudioServer.playback_speed_scale` 单独调）"。
  → <https://docs.godotengine.org/en/4.7/classes/class_engine.html>
- **[实测]** `_process(delta)` 的 delta **确实被缩放**：

  | 设定 ts | Σdelta / Σ真实秒（200 帧） |
  |---|---|
  | 1.00 | 1.0061 |
  | 0.35 | **0.3500** |
  | 0.25 | **0.2500** |

  → `delta / Engine.time_scale` = 真实秒，**公式成立**（GDD §5.2 口径对）。
- **[实测]** `ts = 0.0` 时 `Σdelta = 0.0`，`δ/ts = **NaN**`（`is_nan` = true），而 `Time.get_ticks_msec()` 仍在走。
  → 🔴 **SR-R5 的物理证据**：安全窗绝不能用 `time_scale = 0`。
- **[ClassDB]** 🔴 **`Engine` 在 4.7.2 没有 `get_process_delta_time()` / `get_physics_process_delta_time()`**。可用方法只有：`set/get_time_scale`、`get_frames_drawn`、`get_frames_per_second`、`get_process_frames`、`get_physics_frames`、`is_in_physics_frame`、`set/get_physics_ticks_per_second`、`set/get_max_physics_steps_per_frame`、`set/get_physics_jitter_fix`、`get_physics_interpolation_fraction`。
  → **unscaled 计时只能靠 `Time`**，这条改变了实现方式（见 §4.2）。

### 7.2 `SceneTree.paused` × `Node.process_mode`

- **[文档]** <https://docs.godotengine.org/en/4.7/tutorials/scripting/pausing_games.html>
  `get_tree().paused = true` 会 ① 停 2D/3D 物理；② 按 `process_mode` 决定哪些节点还跑。`_process` / `_physics_process` / `_input` / `_input_event` 都不再调用；**但信号照常**、Tween/动画/粒子/音频会暂停。
- **[ClassDB]** 枚举值：`PROCESS_MODE_INHERIT=0` / `PAUSABLE=1` / `WHEN_PAUSED=2` / `ALWAYS=3` / `DISABLED=4`。
- **[实测]** 暂停 200 帧期间：`process_mode=PAUSABLE` 的子节点 `_process` 被调用 **0 次**；`ALWAYS` 节点照常跑（200 次）。
- **[实测]** 暂停期间 **`_unhandled_key_input` 仍能被 `ALWAYS` 节点收到**（发了 1 次 TAB → 命中 1 次）。
  → 安全窗下商店可交互，这条 GDD 硬要求**成立**。
- **[ClassDB]** `SceneTree.create_timer(time_sec, process_always, process_in_physics, ignore_time_scale)` —— 有 `ignore_time_scale` 形参，做 unscaled 定时器不用自己写。

### 7.3 输入事件

- **[文档]** <https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html>
  传播顺序：`_input()` → **GUI（`Control._gui_input`）** → `_shortcut_input()` → `_unhandled_key_input()` → `_unhandled_input()` → 物理拾取。
- 🔴 **[实测]** **`Node.accept_event()` 在 4.7.2 不存在**（`time_director.gd` 第一版直接编译报错："Function accept_event() not found in base self"）。
  → 正确写法是 **`get_viewport().set_input_as_handled()`**（`Viewport` 上确认存在）。`Control` 有自己的 `accept_event()`，普通 `Node` 没有。
- **选型**：商店热键走 **`_unhandled_key_input`** —— 让按钮先吃事件，避免"点按钮时同时触发全局热键"；它是 `_unhandled_*` 里最靠前的一档，且只收键盘事件，比 `_unhandled_input` 更省。

### 7.4 `Control` 锚点与容器

- **[实测]** 🔴 **直接赋值 `anchors_preset` 在 4.7.2 静默失效**：

  ```gdscript
  c1.set_anchors_preset(Control.PRESET_FULL_RECT)   # anchor_right = 1.0 ✅
  c2.anchors_preset = Control.PRESET_FULL_RECT      # anchor_right = 0.0 ❌ 无声无息
  c3.set_anchor(SIDE_RIGHT, 1.0)                    # anchor_right = 1.0 ✅
  ```
  `layout_mode` 默认是 **3**（`UNCONTROLLED`），`anchors_preset` 是编辑器向的内部属性，setter 在非 Anchors/Uncontrolled 布局模式下早退。
  → **代码建 UI 一律用 `set_anchors_preset()` / `set_anchor(side, …)` / `set_offset(side, …)`**；本轮所有 `.tscn` 里也**不写** anchors，锚点全在脚本里设。
  → 同一结论见社区参考（明确标注 verified against 4.7.2）：
    <https://github.com/lynricsy/hyperskills/blob/main/skills/godot/references/godot-ui.md>
- **[实测]** 全局 `Side` 枚举：`SIDE_LEFT=0 / SIDE_TOP=1 / SIDE_RIGHT=2 / SIDE_BOTTOM=3`（**是全局常量，不是 `Control.SIDE_*`** —— 写 `Control.SIDE_RIGHT` 会编译报错）。
- **[实测]** 容器排序（⏳ 1280×720 时代的调研数据，MarginContainer 16px + HBoxContainer separation 12；Q-S3-C 落地后的 1920 实测见下方补充与 `docs/phase3/slice3-layout-1920-probe.log`）：

  | 节点 | pos | size |
  |---|---|---|
  | HBoxContainer | (16,16) | 1248×688 |
  | 左（战场，`SIZE_EXPAND_FILL`） | (0,0) | **676**×688 |
  | 右（抽屉，`custom_minimum_size.x=560`，`SIZE_SHRINK_END`） | (688,0) | **560**×688 |

  → 布局算尺的计算与容器真实行为一致（676 + 12 + 560 = 1248）。

- **[实测 · Q-S3-C 落地后]** 视口 1920×1080 下骨架场景真实像素（探针 `tools/probe_layout_1920.gd`，日志 `docs/phase3/slice3-layout-1920-probe.log`）：

  | 量 | 实测 | 算尺期望 |
  |---|---|---|
  | 视口 `visible_rect` | **1920×1080** | project.godot 钉死值 |
  | `ShopOverlay` 宽 | **614.4**×1080（offset_left = −614.4） | `maxf(560, 0.32×1920)` = 614.4 ✅ |
  | 战场（Node2D 视口） | 1920×1080，抽屉外可视 1305.6 | 1920 − 614.4 ✅ |

  → 取整口径：算尺返回**浮点原值**（614.4，不 floor / 不 round），写入 `Control.offset` 后由引擎按 float32 存储（探针显示 614.400024414063，float32 表示误差，非算尺误差）。

### 7.5 4.3 → 4.7 的破坏性变更（与本切片相关的部分）

来源：<https://docs.godotengine.org/en/4.7/tutorials/migrating/upgrading_to_godot_4.7.html>

| 变更 | 影响 | 处置 |
|---|---|---|
| **新建项目的默认 stretch 改为 `canvas_items` + `expand`**（原 `disabled` + `keep`） | 本工程 `project.godot` 已写 `mode="canvas_items"`，但**没写 `aspect`** → 4.7 下取默认 `expand` | ✅ **已钉死 `window/stretch/aspect="expand"`**（随 Q-S3-C 落地一起改，防止以后随引擎升级漂移） |
| **鼠标/键盘的 device ID 从 `0` 改成 `InputEvent.DEVICE_ID_MOUSE` / `DEVICE_ID_KEYBOARD`** | 若将来按 device 过滤输入会错 | 骨架阶段不按 device 过滤；后续若做手柄支持必须注意 |
| **GDScript：覆写带类型返回的方法时，必须显式 `return`** | 可能影响既有覆写 | 本轮新代码无此模式 |
| **GDScript：给 packed array 的元素赋值不再触发整个属性的 setter** | 无影响 | — |
| 4.7 新增 `Control.offset_transform_*`（位移/旋转/缩放，默认 visual-only 不影响输入） | 4.3 没有 | 未使用；做抽屉滑入动画时可考虑（不影响鼠标命中是个加分项） |
| `CanvasItem` 画线不再加抗锯齿 feather | 无影响 | — |
| `RichTextLabel.add_image` 参数类型/命名变更 | 未使用 | — |

> 🟢 **未发现**任何与 `Engine.time_scale` / `SceneTree.paused` / `process_mode` / `CanvasLayer` / `Time` 相关的破坏性变更 —— 这几块 4.3→4.7 是稳定的。

---

## 8. 后续切片的接口点（每个占位节点都标了 `[接口]`）

| # | 接口点 | 谁来接 | 契约 |
|---|---|---|---|
| **I-1** | `TimeDirector.wave_start(w)` / `wave_end(w)` | `wave-spawner` | WS-1 / WS-2（GDD §8.5）。`wave_start` 内部做 `n←0`、`budget←20`；`deal_initial_shop` 由下游在收到 `wave_started` 信号后自己做（🔴 商店不自发牌） |
| **I-2** | `TimeDirector` 的 `reroll_requested` / `buy_requested` / `lock_toggled` | 完整商店逻辑 | 商店**只发意图**，扣费/发牌/装配由 `card-system` 侧做 |
| **I-3** | `ShopOverlay` 的 3 个商品位卡面 | 美术 + 商店逻辑 | 填 H1–H9 事实标注；🔴 **尺寸/亮度必须继续完全一致**（自测 §9 会 grep） |
| **I-4** | `ShopOverlay._heavy_panel`（弃卡/卸下改投/拆除回收） | `TowerRemove` 结算器 | 仅 `SafeWindow` 可用；战斗内置灰**且不响应**（已实现 `disabled`，T-C1 / E16） |
| **I-5** | `CoreHpBar.set_hp(hp, max)` | `wave-spawner` | WS-5 |
| **I-6** | `ThreatPulse.set_threat(t)` | `wave-spawner` | WS-4；🔴 必须继续用 unscaled 时钟驱动（锚点 4 第 4 条） |
| **I-7** | `Battlefield (Node2D)` → 换成 `SubViewport` | 3D 战场 | 保持 `PAUSABLE`；vignette 只作用于这一层（交接点 4） |
| **I-8** | `TimeDirector` 的 `placement_confirmed` / `placement_cancelled` | `tower-build` | TB-3；取消**不退款** |
| **I-9** | 二次确认弹窗 `CanvasLayer 140` | 后续切片 | 🔴 用自定义 `Control`，**禁止** `AcceptDialog` 默认值（交接点 11）；弹窗打开时**不得**解除暂停（E15） |
| **I-10** | 音频 | 阮和鸣 | `Engine.time_scale` **不影响**音频播放速度（官方明确），所以 UI 音效天然安全 —— 无需额外解耦（交接点 9 自动满足） |

---

## 9. 🔴 待主理人拍板（3 项，均未擅改口径）—— ✅ **三项均已于 2026-10-01 拍板**（拍板结果与落地位置附在各小节末尾）

### Q-S3-A · 预算在**放置模式（⑤）**里耗尽的处置（GDD 未定义）

- **上下文**：GDD §2.1 表给 ⑤ 写的是「`0.25×` · 消耗预算」，§5.2 的耗尽规则只写了「`budget_left ≤ 0 → state = ShopRealTime`」，没说 ⑤ 里耗尽怎么办。
- **本实现的选择**：**立即退出放置模式、落 ③ `ShopRealTime`（1.0×）**，待放置的卡**退回队列**（不销毁、不退款，与 Esc 取消同口径）。
- **为什么不能选另一条**：若允许 ⑤ 在预算耗尽后继续 `0.25×`，玩家就能拿到**免费的无限慢动作** —— 预算不再是货币，"何时开商店"这个真选择当场消失（违反 §0 结论 2 与 P4）。
- **选项**：① 立即退出（本实现）／② 保持 `0.25×` 直到落子或 Esc，退出后落 ③／③ 保持 `0.25×` 且下一波预算照常重置（等于给一次免费额度）。
- **影响面**：只在"预算剩余 < 放置耗时"的窄场景出现；选 ② 才有额外数值风险。
- ✅ **拍板结果（2026-10-01）**：采纳**选项 ①**（= 本实现），另加一条**推论**：「**预算为 0 时进入 ⑤ 不得再减速（等效 `1.0×`）**」。已回写 GDD v1.2 §2.1 易错口径第 4 条。
  **落地**：原 `tick()` 的「耗尽 → 退 ⑤ 落 ③」本就符合拍板方向；推论部分为**新修**——`clock()` 的 ⑤ 分支在 `is_budget_drained()` 时改回 `1.0× / 不耗预算 / 抽屉仍收起`，`tick()` 开头对「预算已是 0 却仍在 ⑤」立即退出放置（否则 `enter_placement()` 那一帧会先写入 0.25×）。断言：自测 §3.8（8 项）。
  🟡 **遗留歧义（已上报，未擅改）**：从 ④ 进入 ⑤ 时预算耗尽 → 本实现回 **④**（按 §2.1 图注「⑤ 原路返回」），而拍板文字「落 ③ 全速」按字面会与 ④ 的「世界暂停」矛盾 —— 两条 GDD 条文冲突，待主理人澄清。

### Q-S3-B · 单帧计入预算的实时秒上限（GDD 未定义，🟡 工程参数）

- **上下文**：`Time.get_ticks_msec()` 差值在窗口失焦、系统休眠、断点调试回来时会是一次**巨大跳变**。不夹住的话玩家一切回来预算就被整段吃掉。
- **本实现**：`MvpConfig.MAX_FRAME_REAL_DT = 0.25`（单帧最多计 0.25 实时秒；超过视为"这段时间没在玩"）。
- **⚠️ 这是一个新数值，不在 GDD §3.1 常量表里**，也不在 control-manifest 冻结清单里 → 按纪律必须上报，不能自己当它不存在。
- **选项**：① 0.25s（本实现）／② 不夹（忠实但会被失焦惩罚）／③ 只在 `Window` 失焦期间冻结计时（更准，但要接 `NOTIFICATION_APPLICATION_FOCUS_OUT`）。
- ✅ **拍板结果（2026-10-01）**：采纳 **0.25**，已回写 GDD v1.2 §3.1 常量表，并进入 control-manifest §1 口径冻结清单。代码无需改动（`time_director.gd` 已按此实现）。

### Q-S3-C · 🔴 1280×720 下「32% 比例」与「最小宽 560px」互相顶牛

- **上下文**：`design/gdd/shop-reroll.md` §2.4 写「基准 1080p/1920 下宽 614px（≈32%）；战场保留左侧 ≈68%」，同时写「🔴 覆盖层宽度不得 < 560px（WCAG AA 可访问性红线）」。
  本工程 `project.godot` 的视口是 **1280×720**（不是 1920）→ `0.32 × 1280 = 409.6px < 560px`。
- **本实现**：取 `max()`，两条约束都满足 → **抽屉 560px = 43.75% 屏宽，战场只剩 56.25%**（不是 GDD 写的 68%）。
- **这是真实冲突，不是浮点噪声**，所以我没有改任何一条约束去凑。三条出路：
  1. **把工程视口提到 1920×1080**（GDD 的基准屏）→ 两条约束正好一致（614.4 / 32%），战场真正拿到 68%。**成本**：`project.godot` 一行 + 所有 UI 按 1080p 重排。
  2. **接受 1280 下抽屉 43.75%**（本实现）→ 战场被压到 56.25%，与 GDD 的视觉焦点分配有偏差，但 WCAG AA 守住了。
  3. **1280 下放宽最小宽**（比如 420px）→ 🔴 直接违反 WCAG AA 红线，不建议。
- **我的建议**：**①** —— GDD 的 68/32 是设计意图，560px 只是可访问性下限；在基准屏上两者不冲突，说明"1280 视口"才是那个偏离项。但这改的是工程配置不是设计口径，**等你拍**。
- ✅ **拍板结果（2026-10-01）**：采纳**出路 ①** —— 视口提到 **1920×1080**（GDD 基准屏），`maxf` 算尺保留作非基准屏安全网。已回写 GDD v1.2，并进入 control-manifest §1 口径冻结清单（视口 + `stretch/aspect="expand"`）。
  **落地清单**：`project.godot`（视口 1920×1080 + aspect 显式钉死）· `shop_layout.gd` 注释更新（算尺逻辑**未动**）· `battlefield_placeholder.gd` 默认视口占位值同步 · 自测 §8（基准屏 4 项 + 工程配置 3 项 + 安全网用例保留）· 冒烟布局断言 4 项 · 重截图 `slice3-skeleton.png`（1920×1080）· 实测探针 `tools/probe_layout_1920.gd`。

### （附）已按 GDD 推定的次级口径 —— 若与理解不符请指出

| # | 推定 | 依据 |
|---|---|---|
| a | 从 **③** 也能进放置模式（⑤） | §2.1 表给 ③ 的操作列写「同上（但无减速）」，含"放置" |
| b | 安全窗里玩家手动收起抽屉后按「开始下一波」→ 下一波抽屉保持**关** | §4.1「保持玩家上次的开/关状态（不强制弹出）」 |
| c | 安全窗里**不**收抽屉 → 下一波抽屉保持**开** | 同上 |
| d | ④ 的 `time_scale` 恒为 1.0，抽屉形态由玩家开/关偏好决定 | §2.1「time_scale 保持 1.0」+ §4.2「Tab 在 ④ 可用」 |

---

## 10. 与 GDD 红线的对照自检

| 红线 | 落地 | 证据 |
|---|---|---|
| 🔴 **SR-R1** 战斗永不停止 | ②③④ 都不设 `paused`；只有 ④ 用 `paused` | 冒烟日志：①②③⑤ `paused=false` |
| 🔴 **SR-R2** 只标事实不标推荐 | 三商品位尺寸/配色/字号完全一致；源码 grep 自动回归 | 自测 §9 零命中 |
| 🔴 **SR-R3** 战斗内禁止塔操作 | 重决策入口在非 `SafeWindow` 一律 `disabled=true`（置灰 + 不响应） | `shop_overlay.gd::_refresh_mode` |
| 🔴 **SR-R4** pity 不覆盖锁定 | 骨架未实现（I-2 接口留给完整商店逻辑） | — |
| 🔴 **SR-R5** `time_scale` 永不 0 | ④ 用 `paused=true`、`time_scale` 保持 1.0；代码里 `assert(ts > 0.0)` | 自测 §2（30 组恒 > 0）+ 冒烟 ④ 行 `ts=1.00 / paused=true` |
| 🔴 **T-C1** 战斗内禁止塔操作 | 同 SR-R3；拆除/弃卡/卸下三按钮在轻决策模式全灰 | 同上 |
| 🔴 **Q-SR2** 耗尽不强制关闭 | ②→③ 时抽屉仍是 `LIGHT`，预算条标红 | 自测 3.2 / 冒烟 ShopRealTime 行 `抽屉=1` |
| 🔴 **Q-SR6** 放置复用同一预算池 | ⑤ 与 ② 共用一个 `budget_left` | 自测 3.5 |
| 🔴 **`Engine` 无 `get_process_delta_time()`** | unscaled 只用 `Time` 差值 | §7.1 |
| 🔴 **G6** headless 无 `global_script_class_cache` | 本轮新增脚本**全部不写 `class_name`**，跨脚本一律 `preload` | 全量 headless 跑通 |
| 🔴 **G7** `String %` 不支持 `%e`/`%g` | 自测里自己写 `_sci()` | 自测 §8 曾踩到，已修 |

---

## 11. 交付文件索引

| 文件 | 作用 |
|---|---|
| `docs/architecture/slice3-shop-ui-architecture.md` | 本文档 |
| `scripts/engine/time_state_machine.gd` | 🆕 五态时钟**纯逻辑**（零副作用、可单测） |
| `scripts/engine/mvp_config.gd` | 修改：新增切片3 常量块（**未触碰** `cfg_of()` 与冻结项） |
| `scripts/ui/time_director.gd` | 🆕 适配层：唯一写 `time_scale` / `paused` 的地方 + 输入 + 意图信号 |
| `scripts/ui/shop_layout.gd` | 🆕 C3 布局唯一算尺 |
| `scripts/ui/shop_overlay.gd` | 🆕 抽屉占位（3 商品位 + 预算条 + 重决策入口组） |
| `scripts/ui/hud.gd` | 🆕 HUD 占位 + 切片3 实测读数面板 |
| `scripts/ui/battlefield_placeholder.gd` | 🆕 战场占位（scaled delta 移动，暂停时静止） |
| `scripts/ui/threat_pulse.gd` | 🆕 边缘红光脉冲占位（unscaled） |
| `scripts/ui/core_hp_bar.gd` | 🆕 穿透式核心 HP 条（层 130） |
| `scripts/ui/battle_shop.gd` / `scenes/battle_shop.tscn` | 🆕 骨架场景与依赖注入 |
| `scripts/ui/boot.gd` | 修改：headless 跑自测；窗口模式装载骨架 |
| `tests/test_suite_slice3.gd` | 🆕 切片3 自测（142 项） |
| `tests/run_slice3_scene_smoke.gd` | 🆕 真机场景冒烟（25 项，含 10 实时秒预算实测 + 1920 布局 4 项） |
| `tests/run_tests.gd` | 修改：新增 `slice3` 段 |
| `tools/probe_godot47.gd` | 🆕 一次性 API 探针（不进自测、不进产品） |
| `docs/phase3/slice3-godot47-api-probe.log` | API 实测证据 |
| `docs/phase3/slice3-scene-smoke.log` | 场景冒烟证据 |
| `docs/phase3/slice3-verify.md` | 验证报告 |

## 12. 跑法

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 全量自测（切片1 + 2 + 3）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd
# 只跑切片3 单元
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice3
# 真机场景冒烟（会真等 10 实时秒做预算实测）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_slice3_scene_smoke.gd
# Godot 4.7.2 API 探针
"$GODOT" --headless --path D:/roguedemo --script res://tools/probe_godot47.gd
# 窗口模式看骨架（headless 下会自动跑自测后退出）
"$GODOT" --path D:/roguedemo
```
