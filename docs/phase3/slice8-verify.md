# 切片8 验证报告 · 拆除回收 `Salvage` / 弃卡 / 卸下改投 + I-9 二次确认 + I-7 塔位点选 + C2 智能高亮 + 可玩 MVP 胜负结算 + T1 塔死亡玩法批次

> **结论**：🟢 **切片8 全量自测 92 项断言 / 0 失败 / 退出码 0** + **T1 塔死亡玩法批次 67 项断言 / 0 失败 / 退出码 0**（仇恨激活 + 塔死亡 + 修复入口 + **V-1 ATTRITION=1.50 定稿 + WARMUP=2 起手保护** + **V-2 起飞率 A 破线诊断定稿**）；金标本零改动；切片1-7 逐位等价基线纹丝不动。
> **意义**：把切片4 遗留的 **I-9 重决策** + **D-9 单塔效果卡 2 次输入购买（I-7 塔位点选）** + **C2 智能高亮 H2/H3/H5/H6/H7/H9** 全部落地，并在 **切片8续3** 把已验证系统串成 **W1→W20 完整可试玩一局**（含胜负结算 + 核心 HP 归零判定）；**T1 批次**激活机会型仇恨（Q-T3）+ 塔 HP（Q-T2）+ Disabled 中间态（Q-T4），把「塔会死」从占位变成可执行玩法，且 `aggro=false` 与金标本逐位等价。

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

### 1.4 I-7 塔位点选（D-9 / D-TB-5 / D-TB-6）

| 文件 | 职责 | 与金标本关系 |
|---|---|---|
| `scripts/gameplay/shop_runtime.gd` | `selected_tower_slot` 点选状态 + `select_tower`/`clear_selection` + `tower_accepts_tag`/`can_attach_card`/`get_legal_hosts`（D-8① Tag 合法性）+ `_reinforce_host`（点选合法→该塔，否则→主塔） | 玩家路线专属；金标本 AI 恒不点选 |
| `scripts/ui/monster_layer.gd` | 已建塔渲染（塔原型色 + h 层刻度 + 主塔描边）+ 选中高亮（青圈）+ D-TB-6 合法宿主高亮（橙底圈）+ 点击命中 `_hit_tower_slot` → 发 `tower_select_requested` | 只读 runtime + 只发意图 |
| `scripts/ui/time_director.gd` | `tower_select_requested(slot)` 意图信号 | 接线，无口径 |
| `scripts/gameplay/shop_controller.gd` | `_on_tower_select_requested` → `runtime.select_tower` | 接线层 |

**装配宿主判据链**（`_reinforce_host`）：
```
① 有点选塔且该塔 Tag 合法 → 投该塔（2 次输入，D-TB-5 可覆盖默认）
② 否则主塔合法 → 投主塔（1 次输入默认）
③ 主塔也不合法 → -1（无宿主）
```
**legal_note 三态**（D-TB-6 强制点选）：
- 存在任一塔接收 → 主塔接收 = `""`（1 次输入）；主塔拒但副塔收 = `选择宿主塔`（强制点选，仍 legal）
- 无任何塔接收 → `无塔接收该 Tag`（H8 置灰）

### 1.5 C2 智能高亮（H2/H3/H5/H6/H7/H9 · SR-R2 只标事实）

| 高亮 | 口径 | 数据来源（只读） |
|---|---|---|
| **H2** Tag 协同 | 卡 Tag ∈ {主塔 Tag, 全场已投 Tag} → 卡种行 `◈协同` 脉冲标记 | `damage_engine` info `tag_invest` + 主塔 Tag |
| **H3** +1 档位 | 再投 1 层跨 κ_tag/κ_r 档位（阈值 3 / 20）→ `+1 档位` 角标 | info `tag_invest` |
| **H5** 层数→下一层 | 单塔效果卡宿主当前层 → +1 → `Lv N → N+1` | `player.towers[].attach` |
| **H6** κ 折价预告 | 建筑卡**新建**塔：N+1 → disc +0.01 → κ 降（🔴 强制披露「拆除塔不会让 κ 回升」） | info `kappa` + N 计算 |
| **H7** 槽位占用 | `强化槽 x/5 · 全局槽 y/3 · 塔位 z/6`（只读） | `slot_usage()` |
| **H9** ΔDPS | 买下后相对增量 %（`投主塔 DPS +X%`），读 `damage_engine` 纯函数（SR-1），🔴 只给 % 不给多步预演 | `action_value` snap/apply/after/rest |

🔴 **SR-R2 合规**：全部只标事实（grep 推荐/最优/best/recommend/suggest 在商店源码零命中，仅规则注释 + 命中测试变量 `best`）。SR-6：overlay 事件驱动（订阅 `shop_changed`/`run_changed`）调一次 `highlights()`，不每帧重算。H10 暴露度 ✅ 已落地（见 §1.5 遗留表 H10 行 · 方案A 显式图标，同受 SR-R2 只标事实约束）。

### 1.6 可玩 MVP 胜负结算（切片8续3 · W1→W20 完整一局）

把已验证系统（伤害引擎 + 实时商店 + 真实刷怪战斗 + 拆除回收 + 点选 + 高亮）串成从头到尾可试玩的一局，补齐三处「能玩起来」的缺口：

**① 核心 HP 单一数据源（消除双账本）**
- 之前 `WaveDirector.core_hp`（战斗侧扣）与 `ShopRuntime.core_hp`（HUD/商店读）**各扣各的** → HUD 读数与真实战斗脱节。
- 现统一到 `player.core_hp`（`PlayerState` 新增字段，`SimPlayer.new_player` 按 `cfg.core_hp` 初始化）：
  - `WaveDirector`：`setup` 从 player 读初值、漏怪扣血**写回** player（单一权威）；
  - `ShopRuntime`：删除独立 `core_hp`/`core_hp_max`，`snapshot` 读 `player.core_hp`；
  - `grant_wave_result` **不再**二次扣血（扣减已在漏怪当刻完成，避免双扣）；
  - `CoreHpBar`：新增 `bind_controller`，订阅 `run_changed` 实时读 player 刷新（≤25% 告警红）。

**② 胜利条件（打完 W20 通关）**
- `WaveDirector` 新增 `MAX_WAVE=20`（对齐金标本 `run_loop` 默认）、`run_won` 信号、`victory` 标志（🔴 变量名不能与 signal `run_won` 同名 → Godot 解析冲突，故用 `victory`）。
- 🔴 **等价性零扰动**：胜利判定放在 `_end_wave` 记录 `last_result`（真实 kills/scrap）**之后** —— W20 全清 = 40 杀的真实结算先落盘，再判胜。若判胜提前返回会抹掉 W20 结算、破坏 slice5 的 W20 逐位等价断言（曾导致 `kills 1 vs 40` 回归，已修正）。

**③ 胜负展示 + 重开（`result_overlay.gd` 新建）**
- CanvasLayer **150**（高于弹窗 140 / 商店 100），`show_result(won, wave, hp, hp_max, scrap)` 纯展示 + 重开/退出意图。
- `ShopController` 接 `run_lost`→失败弹窗、`run_won`→胜利弹窗；「再来一局」→ `runtime.setup` 重建 + `wave_director.bind_runtime` 刷新 player 引用 + `start_run(1)`。
- HUD 终局状态行追加「通关胜利 / 核心归零·失败」标记。

🔴 **金标本零改动**：`run_loop.gd` 用独立本地 `core_hp` 变量、不走 `grant_wave_result`，故上述改动对 MC 判据链零影响。

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

## 2. 验收（全绿，92 项）

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

### AC-S8-7 · I-7 塔位点选（Tag 合法性 + reinforce 改投 + D-TB-6 强制点选）
- **Tag 合法性**：Cannon(fire) 收 FireUp 拒 FrostUp；Arrow(中性) 收 FrostUp/FireUp 任意
- **get_legal_hosts**：FrostUp 合法宿主仅 Arrow(slot2)；FireUp 合法宿主 = 2 座（fire+中性）
- **reinforce 改投**：默认宿主 = 主塔 slot1；点选 slot2 后 `_reinforce_host` = slot2；点选不存在塔位 → 拒绝
- **D-TB-6 强制点选**：主塔 Cannon 拒 FrostUp 但 Arrow 收 → `legal_note = 选择宿主塔`；全场 fire 塔拒 FrostUp → `无塔接收该 Tag`（H8）
- **点选生命周期**：`select_tower` 设置成功；`start_wave` 清空点选（防跨波残留误投）

### AC-S8-8 · C2 智能高亮（H2/H3/H5/H6/H7/H9）
- **H7 槽位占用**：强化槽 1/5 · 塔位 2/6 · 全局槽 0/3
- **H2 Tag 协同**：FireUp（fire）与主塔 Cannon(fire) 协同 = true；FrostUp（frost）与 fire 主塔不协同 = false
- **H5 层数→下一层**：FireUp 主塔 `Lv 3 → 4`
- **H9 ΔDPS**：FireUp 投主塔 ΔDPS > 0（有增益，读 damage_engine 纯函数）
- **H6 κ 折价预告**：Cannon 新建塔触发（N=2→3 disc 0→0.01），文案含「建造新塔」+「拆除塔不会让 κ 回升」；升级同塔不触发
- **H3 +1 档位**：fire 投入 2 层 → 再投 1 层跨档 3 = plus_one；投入 3 层未跨 20 档 = 非 plus_one

### AC-S8-9 · 核心 HP 单一数据源（切片8续3）
- `player.core_hp` 初值 = `cfg.core_hp`（1000）· `core_hp_max` = 1000
- `runtime.snapshot.core_hp` 读 player（1000）
- 战斗侧扣到 player=500 → snapshot 同步 500（单一数据源）
- `grant_wave_result` 入积分 40 · **不再**扣核心 HP（仍 500，无双扣）

### AC-S8-10a · 失败（核心归零 run_failed）
- 零 DPS（拆光塔）→ W1 10 只全漏 → 核心 1000→500（未失败）
- 续 W2 第 20 只漏怪 → 核心归零 0 → `run_failed=true`（E-W3 立即失败）
- `run_lost` 信号发一次 · `run_won`/`victory` 保持 false（二者互斥）· `player.core_hp` 同步归零

### AC-S8-10b · 胜利（通关 run_won）
- 超强构筑（核心塔 + 5 座 Cannon h=400）→ W1..W20 全清不漏
- 打完 W20 → `victory=true`（通关胜利）· `run_won` 信号发一次 · `run_lost` 未发
- 通关时核心仍满血 1000（零漏怪）· `last_result["won"]=true`
- 🔴 逐波推进（模拟玩家一波波打），W20 真实结算 40 杀先落盘再判胜（等价性零扰动）

---

## 1.7 T1 塔死亡玩法批次（仇恨激活 + 被动移除 Destroyed · Q-T2/Q-T3/Q-T4 定稿）

> 🔴 **定位**：把切片6 登记的 T1 占位（`disabled` 因子恒 1.0）激活成完整玩法。**不动金标本**
>    （`wave_sim.gd` / `run_loop.gd` 一字不改）——新建镜像 `wave_sim_aggro.gd` / `run_loop_aggro.gd`，
>    由 `tower_aggro_enabled` 开关控制；`aggro=false` 与金标本逐位等价（单测守护）。

### 实现要点（定稿值一字不改）
- **塔 HP（Q-T2 = ①）**：`HP_i = HP0 × h_i^0.6`（`MonsterData.HP0=120` + `tower_hp()`，指数复用
  `tower_stack_exp=0.6`，与 `Base_i` 同口径 → 逐位同）。波首未 Disabled 塔满血（MVP 无修复机制的最简口径）。
- **机会型仇恨（Q-T3 = ①）**：`WaveDirector._substep` 增④仇恨阶段——Marching 怪 `dist(怪,最近未Disabled塔) ≤ AGGRO_R=9.0`
  → 转 `AggroTower`（停 `t_remain` 冻结）；目标失效/超 `AGGRO_EXIT=10.8`（迟滞带）→ 回 Marching。
- **塔死亡（Q-T4 = ①）**：`AggroTower` 怪对目标塔造成 `ATTRITION × HP0 × m_dps(proto)` 伤害；塔 hp 归零
  → `disabled=true`（断输出不断链，仍占塔位供 `h_j`）→ 发 `tower_destroyed` 信号 + **本波 dps 重算下降**。
- **修复入口（Q-T4 三选一 + Q-T8 数值）**：`ShopRuntime` 新增 `repair_tower`（`repair_cost = ceil(0.30 × 累计投入)`
  → 回满 HP、保留装配卡、恢复输出；E-T6 只回 HP 不改层数）/ `salvage_disabled_tower`（被动拆除返还 **0%**、
  释放塔位、销毁装配卡）/ `list_disabled_towers`（E-T2 合并弹窗数据）；放着不管 = no-op（继续占位不输出）。
  🔴 E-T4 永不死锁：积分不足拒绝修复 → 玩家可「放着不管」或「0 返还拆除」释放塔位。
- **「仇恨只改路径不改 DPS 分配」**：DPS 分配口径不变（全场池→t_remain 排序→填满→结转），仇恨只改怪物态 + 塔损耗。
- **塔状态单一数据源 = `player.towers`**：实时版与批处理镜像都直接改 `player.towers[i].hp/disabled`
  （TowerState 字段切片 T1 已加）→ `dps_only` 重算读到一致 disabled → 逐位相同（曾踩"双份塔状态"坑已修）。
- **雪崩期自然退场**：DPS ≫ 怪物 HP → 怪在路径前段被清光 → 塔 W13+ 几乎不受创（定稿 P2 美学）。

### AC-T1-1~9 · 验收（仇恨激活 + 塔死亡，31 项）
- **AC-T1-1/2**：塔 HP 派生数学（h=1→120 / h=133→≈2255 次线性）+ 仇恨常量登记（AGGRO_R/EXIT/TICK/ATTRITION）。
- **AC-T1-3/4**：**等价守护**——`aggro=false` 实时版/批处理镜像与金标本 `simulate_wave` 逐位一致（kills/leaked/scrap/core_dmg）。
- **AC-T1-5**：仇恨状态机——暴露位 S0 塔 → 怪转 `AggroTower` 并锁定目标 = S0。
- **AC-T1-6**：塔死亡——暴露位 S0 塔被 AggroTower 怪打死 → `disabled=true` + `tower_destroyed` 信号（slot=0）。
- **AC-T1-7**：安全位免疫——S4 塔（d_path=10.82 > 9.0）aggro=true 全程不被打死（towers_disabled=0）。
- **AC-T1-8**：仇恨效果——aggro=true 出现塔死、aggro=false 无塔死。
- **AC-T1-9**：**实时↔批处理逐位一致**（aggro=true 的 kills/leaked/scrap/塔死数相同）。

### AC-T1-10~12 · 验收（修复入口，25 项）
- **AC-T1-10**：修复入口——`repair_cost = ceil(0.30×累计投入)` 数学（invested=100→30）· 修复回满 HP · 恢复输出（disabled=false）· 装配卡保留 · 未受损塔拒绝 · 积分不足拒绝（E-T4）。
- **AC-T1-11**：被动拆除——返还 **0%**（对比主动拆除 50%）· 释放塔位 · 销毁装配卡（含层数）· 未受损塔拒绝。
- **AC-T1-12**：放着不管（no-op，塔保持 Disabled/scrap 不变）+ E-T4 永不死锁（没钱修复不欠分 + 可 0 返还拆除释放塔位）+ `list_disabled_towers`（E-T2 合并弹窗数据，repair_cost 正确）。

### 复验留档（Q-T12 = 定稿数值零改动只复验）
- ✅ **`ATTRITION` V-1 已定稿 = 1.50**（300 局 MC 扫参，2026-10-03，commit `2258c80`+定稿批）：
  扫参区间 [0.5, 8] 步长 0.5，本值 = 首个全判据通过点（对起飞率冲击最小的甜点）。
  - 判据全过：T-A 苟活期 W1-5 = 1.81（≥1 机制可感知）✓ / T-B 成型期 W6-12 = 0.46（≤2 不失控）✓ /
    T-C 雪崩期 W13-20 = 0.0（≈0 自然退场）✓ / 起飞率 B = 0.883（≥0.80 红线，余量 +8.3pp）✓
  - 🔴 **起手保护耦合定稿**：`WARMUP = 2`（W1–2 起手单塔期仇恨不激活，机制 W3 起才致命）。
    无保护时起手塔 W1 必死、起飞率 0%（对照诊断证实）→ ATTRITION 与 WARMUP 成对生效。
    实时版（`WaveDirector.warmup_waves` 默认 2）与批处理镜像（`simulate_wave_aggro` warmup_waves=2）对称。
  - 🟡 **遗留（✅ V-2 已定稿关闭 · 2026-10-04）**：起飞率 A 全程 0.29–0.46 < 0.60 红线
    （金标本 A 主塔也站暴露区，与起手崩盘同源）→ **V-2 根因诊断定稿**（`tests/scan_protect_core.gd`
    300 局 `protect_core` 对照）：根因 = **单核零冗余 × 全暴露位 × 金标本 AI 不保塔 三重结构性碰撞**
    （非数值失衡）。数字：A 无保护 **0.393** / A 保主力塔 **0.583**（仍破线）/ B **0.883**。
    处置（方案④）= **承认"单核高风险画像"为设计预期**（60% 红线针对会保塔的玩家；AI 的 0.393 =
    不保塔下限、0.583 = 半保塔上限，均非玩家真实水平），不动红线 / 金标本；真实可行性由暴露度 UI
    （玩法①）支撑。详见 GDD `mechanics-tower-life-death` §4.2 V-2 定稿行。
  - 扫参脚本 `tests/scan_attrition.gd`（16 点 × 300 局 × A/B 双路径，判据 T-A/T-B/T-C + 起飞率双红线）。

---

## 3. 回归

- 切片1-7 全量自测 **3089 项断言全过**（本切片未触碰任何 engine/golden 文件）。
- 全量（含切片8 + T1）：**222 + 2228 + 142 + 123 + 302 + 41 + 31 + 92 + 67 = 3248 项 / 0 失败 / 退出码 0**。
  - 切片8 从 71 → 92 项（+21）：AC-S8-9（核心 HP 单一数据源 6 项）+ AC-S8-10a（失败 9 项）+ AC-S8-10b（胜利 8 项）。
  - **T1 共 67 项**（`test_suite_t1_aggro.gd`）：AC-T1-1~9（仇恨激活 + 塔死亡 31 项）+ AC-T1-10~12（修复入口 25 项）+ AC-T1-13（V-1 ATTRITION=1.50 定稿 + WARMUP=2 起手保护 7 项）+ **AC-T1-14（V-2 protect_core 主力塔保护诊断留档 4 项）**。
- 切片5 场景冒烟 **22 项 / 0 失败**（全场景树编译 + 运行，含 overlay C2 高亮渲染 + MonsterLayer 塔渲染 + 核心 HP 条接线，零新增 SCRIPT ERROR）。
- 🔴 **SR-R2 合规**：商店源码 grep 推荐/最优/best/recommend/suggest 零命中（仅规则注释 + 命中测试变量）。
- 🔴 **金标本零改动**：`run_loop.gd` / `wave_sim.gd` / `shop_ai.gd` 均未改；T1 仇恨只在 `tower_aggro_enabled=true` 的镜像 + WaveDirector 仇恨分支。

---

## 4. 遗留（后续切片）

| 项 | 说明 |
|---|---|
| ~~**I-7 塔位点选**~~ | ✅ **本切片落地**（D-9 单塔效果卡 2 次输入购买 + D-TB-5 默认主塔 + D-TB-6 强制点选）。 |
| ~~**被动移除 `Destroyed`**~~ | ✅ **T1 批次落地**（Q-T4 = ① `Disabled` 中间态：塔归零 → `disabled=true` 断输出不断链、仍占塔位供 `h_j`、返还 0%、装配卡冻结；战斗内禁操作 T-C1）。 |
| ~~**修复入口**~~ | ✅ **T1 批次落地（逻辑 + UI 弹窗）**。逻辑层：`repair_tower` 修复 `ceil(0.30×累计投入)` 回满 HP 保留装配卡 · `salvage_disabled_tower` 被动拆除返还 0% · 放着不管 no-op；E-T4 永不死锁；E-T2 `list_disabled_towers` 合并弹窗数据。UI 层（方案B 重决策面板入口）：安全窗 `_heavy_panel` 加「处置受损塔 (N)」按钮（有受损塔才亮 + 红点计数，SR-R2 只标事实）→ `repair_requested` 信号 → `ShopController._show_repair_dialog` 弹多塔处置弹窗 `disabled_tower_dialog.gd`（CanvasLayer 140 自定义 Control，每座一行三选一：修复/被动拆除/放着不管；修复按钮积分不足置灰 E-T4；处置后 `refresh` 重算剩余列表，空则自动关闭）。数据源 = `snapshot()` 的 `slots[].disabled`（AC-T1-15 守护）。验证：切片5 场景冒烟 22/0 + T1 单测 74 项（含 AC-T1-15）。 |
| ~~**C2 高亮 H2-H9**~~ | ✅ **本切片落地**（H2/H3/H5/H6/H7/H9 + SR-R2 只标事实合规；H10 暴露度 ✅ 已落地，见遗留表 H10 行）。 |
| ~~**可玩 MVP 胜负结算**~~ | ✅ **切片8续3 落地**（核心 HP 单一数据源 + W20 通关胜利 + 核心归零失败 + 结算覆盖层 + 重开）。 |
| ~~**T1 仇恨真激活**~~ | ✅ **T1 批次落地**（Q-T3 = ① 机会型仇恨 `AGGRO_R=9.0`/`AGGRO_EXIT=10.8` 迟滞带：怪进圈且塔 `!disabled` → 转 `AggroTower` 停下打塔；塔死 → DPS 下降）。新建镜像 `wave_sim_aggro.gd`/`run_loop_aggro.gd`（金标本零改动）；「仇恨只改路径不改 DPS 分配」口径落地；`aggro=false` 与金标本逐位等价由单测守护。 |
| ~~**ATTRITION 扫参（V-1）**~~ | ✅ **V-1 定稿 = 1.50**（300 局 MC 扫参，首个全判据通过点；T-A=1.81/T-B=0.46/T-C=0.0/起飞B=0.883 全过）。🔴 与 **WARMUP=2 起手保护成对定稿**（W1–2 仇恨不激活，机制 W3 起才致命；实时版 `WaveDirector.warmup_waves` + 批处理镜像 `simulate_wave_aggro` warmup_waves 对称）。扫参脚本 `tests/scan_attrition.gd`。 |
| ~~🟡 **起飞率 A 破线（V-2 专项）**~~ | ✅ **V-2 已诊断定稿（2026-10-04，方案④）**：根因 = 单核零冗余 × 全暴露位 × 金标本 AI 不保塔 三重结构性碰撞（非数值失衡）。`tests/scan_protect_core.gd` 300 局 `protect_core` 对照：A 无保护 **0.393** / A 保主力塔 **0.583**（仍破 0.60）/ B **0.883**。处置 = 承认"单核高风险画像"为设计预期（60% 红线针对会保塔的玩家；AI 0.393 = 不保塔下限 / 0.583 = 半保塔上限，均非玩家真实水平），不动红线 / 金标本。真实可行性由暴露度 UI（玩法①）支撑。详见 GDD §4.2 V-2 定稿行。 |
| ~~🟡 **H10 暴露度 UI**~~ | ✅ **本批次落地（T1 玩法① · 方案A 显式图标）**：决策期（非 COMBAT）在**空塔位**上方标 ⚔红 X「会挨打」/ 🛡绿盾「安全」——把 V-2 定稿"把保塔决策交还玩家"落地（单核流保塔是 AI 做不到、玩家能做到的事，可行性由暴露度 UI 支撑）。实现 `monster_layer.gd :: _draw_exposure_icons/_draw_cross/_draw_shield`（新增 `_TSM` preload + `C_EXPOSE_ICON`/`C_SAFE_ICON` 配色）。🔴 SR-R2 合规：只标事实（会/不会挨打），不标推荐（该不该放）。数据地基 `d_path`/`is_exposed` 复用切片5 `path_geometry.gd :: slot_exposure`（4 暴露 / 2 安全，AC-W2 逐位守护，无新逻辑）。只标空塔位避免与塔身+红环叠图；战斗中不显示保持观赏清爽。验证：切片5 场景冒烟 22/0 全通过（真实场景树编译+运行零 SCRIPT ERROR，覆盖 `monster_layer` 全分支）。 |
