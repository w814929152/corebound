# 切片8 验证报告 · 拆除回收 `Salvage` / 弃卡 / 卸下改投 + I-9 二次确认

> **结论**：🟢 **切片8 全量自测 43 项断言 / 0 失败 / 退出码 0**；金标本零改动；切片1-7 逐位等价基线纹丝不动。
> **意义**：把切片4 遗留的 **I-9 重决策**落地 —— 主动移除 `Salvage`（Q-C3 原文：返还 50% 累计投入 + 装配卡全销毁 + 二次确认 + 仅安全窗）+ 弃卡 + 卸下改投全部可用；🔴 兜底①「拆塔不回升 κ」守护通过。

---

## 0. 背景：切片4 遗留的 I-9 重决策

切片4 接线时，`shop_controller._on_salvage_requested` 只 `print` 未实现，`shop_runtime` 无拆除/弃卡/卸下方法，且**核心难点 = 当前数据模型无逐塔投入追踪**（金标本 `apply_action` 直接改 towers 并返回花费 12/12/9，但不记成本去向），而「返还 50% 累计投入」必须逐塔记录建筑卡分 + 装配卡分。本切片补齐这一缺口。

### 设计口径（Q-C3 原文，一字不改）

| 操作 | 规则 | 出处 |
|---|---|---|
| **主动移除 `Salvage`**（✅ MVP） | 返还 **50% 累计投入**（向下取整）· 装配卡**全销毁** · **必须二次确认** · 仅**波次间安全窗** | card-system §4.3 / §7.2.2 / E8 / Q-C3 |
| **弃卡 `discard`** | 该卡及**全部层数**销毁，槽位释放，**无返还** | card-system §4.3 |
| **卸下改投 `unequip`** | 该卡**降 1 层**（降到 0 层整卡销毁） | card-system §4.3 / Q8 / §2.4.2 |

---

## 1. 实现（不动金标本）

| 文件 | 职责 | 与金标本关系 |
|---|---|---|
| `scripts/engine/player_state.gd` | `TowerState.invested: float = 0.0`（逐塔累计投入字段） | 金标本 `apply_action` **不读不写**，零改动 |
| `scripts/gameplay/shop_runtime.gd` | `pending_cost` 平行数组 + `invested` 累加 + `salvage_tower` / `discard_card` / `unequip_downgrade` / `preview_salvage` | 玩家路线专属；`shop_ai.gd` 零改动 |
| `scripts/ui/salvage_confirm_dialog.gd` | I-9 二次确认弹窗（CanvasLayer 140 · 自定义 Control） | 纯展示 + 意图确认，不含玩法口径 |
| `scripts/gameplay/shop_controller.gd` | `_on_salvage_requested` 接线 + 弹窗组装 + SafeWindow 守卫注入 | 接线层，无口径 |

### 1.1 逐塔投入追踪（数据前提）

- **建筑卡**：买时入 `pending` + 成本锁进平行数组 `pending_cost`；`confirm_placement` 落子时把成本累加到**具体塔**的 `invested`（build/upgrade 同价 12）。
- **装配卡**：`buy` 时 `apply_action` 投到 `core_tower_slot()` 那座塔，成本直接 `_add_invested(host, 9)`。

### 1.2 拆除回收 `salvage_tower(slot)`（Q-C3 定稿）

```
返还 = floor(invested × 0.5)   → 入账 scrap
装配卡全销毁（attach 清空 + player.cards 移除）
塔位释放（towers 删除）
🔴 κ 不回升：n_hist_max 只增不减（兜底①，E11）→ 本方法不动 n_hist_max
```

### 1.3 三条红线遵守

| 红线 | 落地 |
|---|---|
| **T-R1 反通胀**（返还 ≤100%，无「买入折扣×移除返还」组合） | 返还系数 = 50% ≤ 100%；本游戏无买入折扣 → 安全 |
| **T-C1 / E16**（战斗内禁止塔操作） | 三个方法**入口即校验** `_in_safe_window()`，非 SafeWindow 直接拒绝（UI 置灰 + 本层兜底双保险） |
| **兜底① κ 不回升**（E11） | `salvage_tower` 不碰 `n_hist_max`；AC-S8-2 断言拆除后 `n_hist_max` 不变 |

---

## 2. 验收（全绿，43 项）

### AC-S8-1 · 逐塔投入追踪
建筑卡 build 记 12 → 装配卡 reinf 累加 9（=21）→ 升级 up 累加 12（=33）。

### AC-S8-2 · 拆除回收 Salvage（核心）
`invested=33`（建筑12+装配9+升级12）+ 2 张装配卡共 3 层：
- preview 返还 `floor(33×0.5)=16` · 销毁 2 张 / 3 层
- 实际拆除：返还 16 分入账 · 塔位释放（塔数→0）· FireUp/FrostUp 从卡册销毁
- 🔴 **κ 不回升**：拆除后 `n_hist_max` 不变

### AC-S8-2b · 返还 50% 向下取整边界
`invested=15 → 7`（7.5 向下取整）· `invested=10 → 5`。

### AC-S8-3 · 弃卡 discard_card
跨塔装配 FireUp（2+1 层）弃掉 → 销毁 3 层 · 卡册移除 · 两塔清空 · **无返还**（scrap 不变）；弃未持有的卡 → 拒绝。

### AC-S8-4 · 卸下改投 unequip_downgrade
FireUp 3 层 → 卸到 2 → 1 → 0（整卡销毁 + 卡册移除 + 塔键移除）。

### AC-S8-5 · I-9 二次确认弹窗组件
- 是 Node（CanvasLayer 派生）· **layer = 140**（shop-reroll §2.4 分层表）
- 🔴 **不是 AcceptDialog**（art-bible §5.1 / shop-reroll §11 禁用默认控件）
- `show_confirm` 记录标题/正文 · 确认回调触发并传参 · 取消不触发确认

### AC-S8-6 · 金标本零改动
金标本 `apply_action` 路径（升级）不写 `invested`（恒 0）—— 证明投入追踪只在玩家路线。

---

## 3. 回归

- 切片1-7 全量自测 **3089 项断言全过**（本切片未触碰任何 engine/golden 文件）。
- 全量（含切片8）：**222 + 2228 + 142 + 123 + 302 + 41 + 31 + 43 = 3132 项 / 0 失败 / 退出码 0**。

---

## 4. 遗留（后续切片）

| 项 | 说明 |
|---|---|
| **I-7 塔位点选** | 当前 `salvage_requested` 无参 → 目标取主塔（与 reinforce 恒投 core_tower 同口径）。D-9「单塔效果卡 2 次输入购买」随战场塔 SubViewport 点选补齐后，salvage 也可支持点选具体塔位。 |
| **被动移除 `Destroyed`** | 返还 0% + 装配卡随 Disabled 冻结，🔒 T1（随塔死亡玩法整体批次）。 |
| **修复入口** | 🔒 T1（随 `Destroyed` 分支）。 |
