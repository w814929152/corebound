# B-1 零教学 · 立项规格（minimal tutorial overlay）

> **立项来源**：`playtest-report.md` §B-1（`uic4` 需脚本注入才建塔 · 首局 W4 崩且不知为何）
> **决策记录**：`polish-backlog.md` §2.2 ⑭ —— 推荐 **✅ 立项**（Minor · 独立轻量 · 零数值 / 零基线影响）
> **归属**：UI 呈现层（`scripts/ui/`）· **零玩法影响 · 零数值变更 · 零基线迁移**
> **状态**：🟡 规格待拍板 → 拍板后交工程实现（1 提交）
>
> 🔴 本文只是规格，**未实现任何代码**。

---

## 0. TL;DR

最简 4 步串行引导（**买 → 放 → 跑 → 修**），一个纯浮层 `tutorial_overlay.gd` + 一个单向状态机。
**数据 100% 来自既有 `runtime.snapshot()`**（`pending` / `towers` / `placing_index` / `slots[].disabled` 均已导出）⇒ **不新增 snapshot 键、不新增信号、不读私有字段**。
唯一编辑的既有文件是场景挂载点；层号常量写在**新文件**里，不碰 `mvp_config.gd`。

---

## 1. 问题（现状为什么不构成"教学"）

`hud.gd:208` 已有一行常驻按键表：

```
Tab 商店 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位 · F3 调试
```

它回答的是「**有哪些键**」，不回答「**现在该干什么**」。三个具体缺口：

| 缺口 | 证据 | 后果 |
|---|---|---|
| W1 开局**直接进战斗**，无「不建塔会死」的因果提示 | `playtest-report.md` W1-battle.png：开局即战斗、无引导 | 玩家不知要抢安全窗建塔 |
| 建塔是**两段式**（买卡 → 入 `pending` → 点「放置」→ 点塔位），一步没做就卡住 | `shop_runtime.gd:518` 建筑卡买时 `pending.append`；`:712` `begin_placement` | 买了卡以为完事，塔没落地 |
| 塔被打成 `Disabled` 后**只有红点计数**，无"安全窗可修"的指向 | `shop_controller.gd:322` `_remaining_disabled_rows()` | 塔哑火后不知何故、不知如何恢复 |

> 结论：缺的不是按键清单，是**时序上的"下一步"**。

---

## 2. 目标 / 非目标

**目标**

1. 首局无需外部说明，即可完成一次完整循环：买到卡 → 塔落地 → 开波 → 处理受损塔。
2. 每步**做完即自动推进**，不要求玩家点「下一步」。
3. 任意时刻可一键跳过，且不阻塞任何操作。

**非目标（明确不做）**

- ❌ 不做新手关卡 / 独立教学场景（成本高、且要动 `boot.gd` 的开局分支）
- ❌ 不做持久化（不写 `user://`，避免引入存档版本问题）→ **仅在进程内生效**
- ❌ 不做多语言 / 不做引导文案外部化
- ❌ 不做强制阻塞式教程（不锁输入、不锁 `time_scale`）
- ❌ 不改 keymap、不改 `mvp_config.gd`、不改任何定稿数值

---

## 3. 方案：单一浮层 + 单向状态机

```
        ┌──────────┐  买过任意卡   ┌──────────┐  塔数≥1    ┌──────────┐  开波    ┌──────────┐
 OFF ──→│   BUY    │──────────────→│  PLACE   │───────────→│   RUN    │─────────→│  REPAIR  │
(首帧)  └──────────┘               └──────────┘            └──────────┘          └──────────┘
              │                         │                       │                     │ 受损塔清空
              └──────── 跳过（Esc / 点「跳过」）────────────────┴─────────────────────┴──→ DONE
```

**单向推进，永不回退。** `DONE` 后本进程内不再出现。

---

## 4. 逐步判定表（触发 / 文案 / 完成判据 / 数据源）

数据源统一为 `controller.runtime.snapshot()`（记作 `S`）与 `wave_director.snapshot()`（记作 `W`）。
🔴 全部为**只读快照**，无一处新增键。

| 步 | 进入条件 | 引导文案 | 完成判据 | 数据源 |
|---|---|---|---|---|
| **BUY** | 首帧（`S.wave == 1` 且未买过任何卡） | `Tab 打开商店 · 1/2/3 买一张建筑卡` | 买过任意卡：`S.towers > 0 or S.pending.size() > 0` | `sm.towers` / `sm.pending` |
| **PLACE** | 上一步完成且 `S.towers == 0` | `点「放置」→ 再点一个塔位落子` | 塔落地：`S.towers >= 1` | `sm.towers` |
| **RUN** | 上一步完成且 `W.state == State.IDLE` | `Space 开始本波 —— 守住核心` | 已开波：`W.state != State.IDLE`（`SPAWNING`/`FIGHTING`） | `wd.snapshot().state` |
| **REPAIR** | 上一步完成，且 `S.slots` 中**任一** `disabled == true` | `安全窗可修复受损塔（点塔位 → 修复 / 拆除）` | 全部 `disabled == false` | `sm.slots[].disabled` |

**REPAIR 的兜底**（见 §7 待拍板 A）：
若打到 W8 结束仍未出现任何 `Disabled` 塔（玩家打得干净），**自动转 DONE**，不把"必须挨打"当成教学前置条件。

**推进节奏**：判定在 `shop_changed` / `run_changed` 事件与 `_process` 的节流轮询中做（≤10 Hz），**不每帧重算**（对齐 SR-6 口径）。

---

## 5. 关闭 / 跳过

| 行为 | 结果 |
|---|---|
| 点浮层上的「跳过」按钮 | 立即 `DONE`，本进程不再出现 |
| 按 `Esc`（**仅当商店抽屉未开时**） | 同上。抽屉开着时 `Esc` 归既有语义（关抽屉），**不抢键** |
| 单局结束（胜 / 负） | 若未 `DONE`，保留当前步——重开一局继续教（避免"死一次就再也不教"） |
| 进程重启 | 重置为 `OFF`（无持久化，刻意如此） |

---

## 6. 呈现规格

| 项 | 规格 |
|---|---|
| **文件** | **新增** `scripts/ui/tutorial_overlay.gd`（`extends Control`）· 约 150–200 行 |
| **层号** | `const LAYER_TUTORIAL := 135` —— 写在**新文件内**。高于商店（100）与核心 HP（130），低于确认弹窗（140）⇒ 弹窗仍可压住引导。🔴 **不修改 `mvp_config.gd`**（保持零 cfg-shape 变更） |
| **挂载点** | `scenes/battle_shop.tscn` 新增 `TutorialLayer/TutorialOverlay` 节点 + `battle_shop.gd` 注入 `bind_controller(controller)` / `bind_director(wave_director)`（对齐既有 `bind_*` 依赖注入风格，不用 `get_node` 满天飞） |
| **位置** | 屏幕底部上方 96px，水平居中，宽 720 · 高 40（避开 `hud.gd:107` 底部 44px 的常驻键位行） |
| **字号** | **18px**（🔴 不低于 S1 定下的 16px 无障碍下限）；行高 24 |
| **配色** | 背景 `Color(0.05,0.06,0.08,0.82)` 圆角 6 · 主文案取既有 `C_TEXT` · 「跳过」用 `C_TEXT_DIM`（复用 `hud.gd` 既有色常量，不引入新色） |
| **交互** | 浮层 `mouse_filter = MOUSE_FILTER_IGNORE`；**仅**「跳过」子按钮 `MOUSE_FILTER_STOP` ⇒ 绝不遮挡塔位点击 |
| **动效** | 淡入 120ms（`_process` 内 alpha 插值）；步进切换用同一淡入。**不引粒子、不进 VFX 层、不碰 `time_scale`** |
| **资源** | 零新增字体 / 零新增图片 / 零新增音频（若后续接音频事件，走既有一事件一 id 的 `AudioDirector`，本批不做） |

---

## 7. 待拍板（2 项）

| # | 待定 | 选项 | 建议 |
|---|---|---|---|
| **A** | REPAIR 步的兜底波次 | (a) W8 结束自动 DONE ／ (b) 不设兜底，一直挂到出现受损塔 ／ (c) 只在"首次出现受损塔"时才教学，其余直接 DONE | **(a) W8 兜底** —— 既覆盖"会挨打的玩家"，也不惩罚打得干净的玩家；W8 早于首局常见崩点之后的复盘窗口 |
| **B** | 引导上线后，`hud.gd:208` 的常驻键位行是否精简 | (a) 保留全量 ／ (b) 引导 `DONE` 前隐藏该行（减少首屏文字量），`DONE` 后显示 | **(b)** —— 首屏同时出现「键位表 + 步骤引导」会互相稀释；引导结束后再露出完整键位表 |

---

## 8. 红线核对

| 红线 | 本方案 |
|---|---|
| 不改定稿数值（`ATTRITION` / `κ_r` / `AGGRO_R` / 塔位 / 核心 HP / 三原型表…） | ✅ 一行不碰 |
| 不动三条守恒 / PATH 逐位等价 / 金标本 | ✅ 纯 UI 新增文件，不触及 `engine/` 与 `gameplay/` |
| 渲染层只读 snapshot | ✅ 只读 `runtime.snapshot()` / `wave_director.snapshot()` |
| 零新信号 | ✅ 只订阅既有 `shop_changed` / `run_changed` |
| 零 snapshot 键新增 | ✅ `pending` / `towers` / `slots[].disabled` / `state` 均已导出 |
| `mvp_config.gd` 零 cfg-shape 变更 | ✅ 层号常量写在新文件 |
| 只读契约（`snapshot()` 不改） | ✅ |
| 不引第三方依赖 / 不引 ShaderMaterial | ✅ 纯 `Control` + `Label` |

---

## 9. 实施拆解（目标：**1 提交**）

| # | 任务 | 文件 | 验收 |
|---|---|---|---|
| 1 | 浮层与状态机 | `scripts/ui/tutorial_overlay.gd`（新） | 4 步可推进、可跳过 |
| 2 | 场景挂载 + 注入 | `scenes/battle_shop.tscn`、`scripts/ui/battle_shop.gd` | 启动即出现 BUY 步 |
| 3 | headless 断言 | `tests/run_tutorial_asserts.gd`（新） | 见下 |
| 4 | 接入默认回归 | `tests/run_tests.gd` | 新套件进默认回归，失败即红 |

**headless 断言（状态机可测，不依赖绘制）**

- A1：初始 `step == BUY`
- A2：注入 `towers == 1` 的假快照 → 推进到 `RUN`（跳过 PLACE）
- A3：`pending` 非空且 `towers == 0` → 维持 `PLACE`
- A4：`state` 由 `IDLE → SPAWNING` → 推进到 `REPAIR`
- A5：`slots[].disabled` 全 false → `DONE`
- A6：跳过调用 → 立即 `DONE` 且后续快照不再推进

> 引导是纯 UI，**不写进 MC 门禁**（与 §T1 的聚合口径无关），只进默认回归。

**窗口人工验收**：首局不借助任何外部说明，能走通「买 → 放 → 跑 → 修」四步；`Esc` 在抽屉开着时不误触跳过。

---

## 10. 不做项（本批）

- 引导覆盖"献祭 / 加固 / 刷新 / 锁定"等进阶玩法的第二段教学（留 Phase 6.2，或并入 `C3` 精英波强度提示）
- 引导进度持久化 / 跨存档记忆
- 引导的多语言与文案外部化
- 与 `hud.gd` 常驻键位行的联动改造（待 §7 B 拍板后才做）

---

**规格起草**：主理人（游承峰）· 承接 `playtest-report.md` §B-1 + `polish-backlog.md` ⑭
**下一步**：用户拍板 §7 A/B → 派 engineering-lead 按 §9 实现 → quality-lead 复核 → 单提交收口
