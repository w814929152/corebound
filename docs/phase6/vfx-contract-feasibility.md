# Phase 6 · VFX snapshot 契约可行性评估（T-P6-05）

> **性质**：**只读**静态分析。本轮**未改动任何生产代码 / 数值 / 口径**，**未 push**。
> **背景**：T-P6-03 资产审计确认本作最大视觉缺口是「爽点层」——零投射物 / 零伤害数字 / 零击杀反馈，P2「雪崩填屏」在画面上无载体。审计指出 P1-1（投射物渲染）与 P1-2（伤害数字）**需先核对 snapshot 契约**。
> **负责人**：engineering-lead（程基岩） · **引擎**：Godot 4.7.2-stable · **日期**：Phase 6 打磨期
> **方法**：静态阅读（未跑 Godot，规避 `.godot` 实例锁）。证据均给行号。

---

## 0. 结论速览（先看这张）

| # | 项目 | 可行性 | 最小改动面 | 是否触碰红线 | 成本估 | 前置依赖 |
|---|---|---|---|---|---|---|
| **P1-1** | 视觉投射物（从塔飞向目标） | ✅ **可行**（渲染层纯派生·**装饰性**） | `scripts/ui/monster_layer.gd`（1 文件） | **否** | **中** | 无 |
| **P1-2** | 伤害数字（逐怪 Δhp 浮字） | ✅ **可行**（需 +1 只读派生键） | `scripts/gameplay/wave_director.gd` **+1 行** + `scripts/ui/` 新代码 | **否**（纯 additive 只读键） | **中** | 无（键可即时加） |
| **P1-3a** | 击杀碎片/冲击环 | ✅ **可行**（订阅既有信号） | `scripts/ui/monster_layer.gd` | **否** | **低** | 无 |
| **P1-3b** | hitstop（`Engine.time_scale` 微停） | ⚠️ **有条件可行**（须走 TimeDirector） | `scripts/ui/time_director.gd`（时间权威） | **⚠️ 触碰「时间轴权威」架构红线**（非数值红线） | **中–高** | **需单独 ADR + 红线复核** |

**一句话**：P1-1 / P1-2 / P1-3a **全部可落呈现层、零玩法口径改动**（P1-2 仅需 1 个只读派生键）；**唯一需谨慎的是 hitstop**——它不破坏 golden 逐位复现，但会触碰「时间轴权威」的架构约束，建议单独走 ADR。

---

## 1. 伤害结算方式：hitscan（瞬时聚合）· 无投射物实体

**结论：玩法层是 hitscan（瞬时聚合结算），不存在任何可被观察的投射物对象。**

证据：
- **金标本** `scripts/engine/wave_sim.gd:92-103`：每子步 `var dmg := dps * DT`，然后**贪心**依次打到队列最前面的怪（`m[0] = float(m[0]) - dmg`）、耗尽即停。**没有"子弹"或"命中事件"，只有"把 dmg 铺到 hp 上"**。
- **实时版** `scripts/gameplay/wave_director.gd:372-386`（`_substep` ②）：与金标本逐行相同——`var dmg := dps * _WaveSim.DT`，`for m in monsters: ... m.hp = float(m.hp) - dmg`。判死即 `emit_signal("monster_killed", m)`（:383）。
- **伤害引擎** `scripts/engine/damage_engine.gd:64-347`（`compute_dps`）：输出的是**每塔聚合 DPS `per_tower[].dps` + 全场 `total`**（:256-260、:332），**不是逐目标伤害**；`dps_only()`（:346-347）只返回一个标量。
- **怪物实体** `scripts/gameplay/monster.gd`：字段只有 `index/proto/elite/hp/hp_max/m_spd/m_dps/t_remain/theta/state/target_slot/sapper`（:35-58）——**无投射物/无"被谁打"的字段**。`monsters` 数组（`wave_director.gd:145`）持的是这些逻辑怪。

**含义**：玩法层**不产出**"某塔发射了一发弹 × 命中某怪 × 造成 N 点伤害"的因果链。因此任何投射物 / 命中闪 / 伤害数字，**只能从既有状态（塔位、怪位、hp 差分）派生**，不可能"照抄"玩法事件——这是 §3/§4 全部结论的根。

---

## 2. `_snap["projectiles"]` 现状：字段缺失 → 零绘制

**结论：`projectiles` 键在 snapshot 中不存在，全仓库无任何生产者；`_draw_projectiles()` 永远画空。审计判断（"字段缺失→零绘制"）正确。**

证据：
- **消费端** `scripts/ui/monster_layer.gd:1147-1148`：`_draw_projectiles()` 读 `var ps: Array = _snap.get("projectiles", [])` → 键缺失 → 空数组 → 循环不执行。
- **调用点** `monster_layer.gd:759`：`_draw_projectiles(sc)` 注释即写「层8：字段缺失 → 零绘制」；`monster_layer.gd:1146` 注释同。
- **生产端** `scripts/gameplay/wave_director.gd:865-900` `snapshot()` 的**实际键全集**为：
  `w, state, t_wave, spawned, n, alive, kills, leaked, scrap_earned, core_hp, failed, won, dps, interval, limit, hp_unit, v0, t_reach, monsters[], towers[], towers_disabled, revive_ui, prototype_split_enabled, elite_waves_enabled, tower_aggro_enabled, is_elite_wave, aggro_ui, next_is_elite_wave` —— **无 `projectiles`**。
- 全仓库 grep `projectiles`（`*.gd`）**只命中消费端 3 处**（monster_layer.gd:759/1146/1147/1148），**零生产端**。
- `monsters[]` 每项（`wave_director.gd:838-849`）= `proto/elite/hp/hp_max/t_remain/s/pos/state/target_slot/sapper`；`towers[]` 每项（:858-864）= `slot/hp/hp_max/disabled/revive_charged`——**均无投射物字段**。

**含义**：投射物渲染（P1-1）**不需要新增 snapshot 字段**——因为玩法里根本没有投射物这一层，加字段也无源可派生。正确做法是**渲染层自造装饰性弹**（§3）。

---

## 3. P1-1 视觉投射物：渲染层纯派生，可行（**装饰性**）

**结论：可行 —— 渲染层可**纯派生**一个「从塔飞向目标」的视觉弹，**不改玩法层、不加 snapshot 字段**。但必须诚实标注：它是**装饰性**的，与真实伤害分配**无因果对应**。**

**依据（渲染层已握有全部所需输入）**：
- **塔位坐标**：`monster_layer.gd:242-245 _slots_arr()` ← `controller.runtime.geo.slots`（未绑定时回退 `_Geo6.SLOTS6`）。渲染层**已经在画塔**（`_draw_radial_towers` :1046 / `_draw_towers` :431），塔位现成。
- **怪位坐标**：`_snap["monsters"][].pos`（`monster_layer.gd:1097` 已在 `_draw_radial_monsters` 里逐怪用 `m["pos"]`）。
- **"谁在最前"**：`_snap["monsters"][].t_remain`（`wave_director.gd:843`）——升序即"距核心最近优先"，与集火口径同源。
- **本地演出范式已存在**：`monster_layer.gd` 的 `_vfx_t`（:152）、`_core_flash`/`_tower_flash`（:157-159）已是"只驱动画面、不回写玩法、不新增信号"的本地计时器（注释 :112、:155 明写此纪律）。

**可行方案（零玩法改动）**：在 `_process`（:248）里新增一个**本地装饰弹池**：每座塔按固定**视觉节奏**（如 `X` 发/秒）朝"当前最前的活怪"生成一发纯视觉弹，`_vfx_t` 推进其飞行插值，命中即销毁（可选触发受击闪）。**全部状态留在 UI 本地**，与 §2 的 `_draw_projectiles` 同层，可复用其绘制代码或新写 `_draw_vfx_bolts`。

**🔴 诚实边界**：由于玩法是 hitscan 聚合（§1），**无法**做到"这一发弹对应哪只怪挨了多少血"。该弹流是**氛围/爽点装饰**，节奏与真实 DPS **解耦**（顶多按 `dps` 高低调视觉密度，让观感大致匹配输出）。若产品要求"因果投射物"，则**必须改玩法**（把 hitscan 拆成真实 projectile 实体）——这超出 VFX 范畴，是**玩法机制变更**，另议。

**最小增量字段**：**无需**。若未来想要"塔→哪个怪"的因果映射，最小增量也**不止**一个字段（需改伤害分配为逐塔逐目标结算）——**不建议**，代价与风险远超收益。

> ⚠️ 若采用"按 `dps` 调视觉密度"：只读 `_snap["dps"]`（`wave_director.gd:878`）即可，仍是纯派生。

---

## 4. P1-2 伤害数字：需 1 个只读派生键（`index`）· 信号已就绪

**需要什么**：拿到「**哪只怪**、**受多少伤害**、**在哪**」三要素。

**现状盘点**：
- **在哪**：`_snap["monsters"][].pos` ✅ 已有（:845）。怪死瞬间的位置可由信号对象取（见下）。
- **哪只怪（稳定 id）**：🔴 **当前 snapshot 不导出任何稳定 id**。`monster.gd:35` 有 `index`（本波出生序号，0-based，波内唯一），但 `snapshot()` 的 monsters 字典（`wave_director.gd:838-849`）**未包含它**。这正是 `monster_layer.gd:287` 注释的来源：「🔴 无稳定怪物 id（第一刀已验证）→ 怪物命中闪**不做**（登记不做项）」。
- **受多少伤害**：玩法不产出"逐怪伤害事件"。**唯一可行路径 = 帧间差分**：渲染层缓存"上一帧每怪的 hp"，与本帧 `_snap["monsters"][].hp`（:841）相减得 `Δhp`。**而帧间差分必须有稳定键**，否则怪序变化会错配 → 这就是卡点。

**`monster_killed` 信号带什么**：`wave_director.gd:82` 声明 `signal monster_killed(m)`，:383 `emit_signal("monster_killed", m)` —— **携带 Monster 对象 `m`**（非字典）。此刻 `m` 仍存活（RefCounted 未释放），可直接读 `m.pos(v0_)` / `m.hp_max` / `m.index`。同样地 `monster_spawned(m)`（:81/:754）、`monster_leaked(m)`（:83/:408）都在。渲染层**已具备订阅范式**（`tower_revived` 在 `monster_layer.gd:181-182` 已连）。

**最小增量（推荐）**：在 `snapshot()` 的 monsters 字典里**加 1 个只读派生键**：
```
"index": int(m.index),   # wave_director.gd:838-849 内，与 proto/elite/hp... 并列
```
- **来源**：既有字段 `m.index`（`monster.gd:35`），**纯派生**。
- **不新增信号**（信号本就存在）；**不引入任何随机**；**不改任何数值/口径**（只是把一个已存在的整数**多读出来一份**）。
- 渲染层据此建 `id → prev_hp` 缓存，`diff = prev_hp − hp`（>0 即本帧伤害）→ 在 `pos` 上浮字。波切换时 `snapshot()["w"]`（:866）变化 → 清缓存（`index` 每波重置，天然无跨波冲突）。
- **影响面**：`scripts/gameplay/wave_director.gd` **+1 行**（additive read-only）。有先例：T1 已向本 snapshot 增过只读键（`sapper` :848、`revive_charged` :863、`aggro_ui` :898、`next_is_elite_wave` :899），均为 additive、零口径扰动。

**对"击杀数字"**：`monster_killed(m)` 对象即可（`m` 存活）→ 直接 `m.pos(v0_)` 弹出"击杀/掉落"提示，**连 `index` 键都不需要**。

**次选（零改动，不推荐）**：渲染层用 `monster_spawned`/`monster_killed` 维护 `WeakRef → last_hp` 映射，帧间用快照 hp 匹配。**脆弱**（对象生命周期、波内多次 spawn/kill 交错、无法稳健区分同帧多怪），且仍逃不开"需要一个键把快照项与缓存对上"。**推荐走 +1 键方案**。

> 注：`v0_` 可经 `director.v0_`（`wave_director.gd:142`，public）或快照 `v0`（:882）取得，供 `m.pos(v0_)` 用。

---

## 5. P1-3 击杀反馈：碎片/冲击环 ✅ vs hitstop ⚠️

### 5a. 碎片 / 冲击环（纯呈现）— ✅ 不触碰红线

- 实现：`monster_layer` 订阅既有 `monster_killed(m)` 信号 → 以 `m` 的 `pos` 生成本地 VFX（碎片/扩散环），用本地计时器衰减。**与既有 `_revive_flash`（:149/:187-188）完全同构**。
- **不新增信号**（信号本就存在）、**不回写玩法**、**不改数值/口径** → **不触碰红线**。成本 **低**。

### 5b. hitstop（`Engine.time_scale` 短暂变化）— ⚠️ 触碰「时间轴权威」架构红线

**逐条核对红线**：

| 红线维度 | hitstop 的影响 | 判定 |
|---|---|---|
| **golden sample 逐位复现** | golden `WaveSim.simulate_wave`（`wave_sim.gd`）走**固定 DT**；hitstop 只改 `Engine.time_scale`（影响 SceneTree `_process(delta)` 的 delta）。而 `WaveDirector.advance(dt)`（:334）虽消费**缩放后**的 dt，但每子步用**固定 `_WaveSim.DT=0.1`** 结算（:341-345）→ **子步输出的每个值不变**，只是"何时跑"变了。 | ✅ **数值面不破坏** |
| **headless 确定性（MC/golden）** | headless 测试走 `advance(DT)`（:357）或 `run_to_end`（:353），**显式喂固定 dt、从不读 time_scale** → hitstop **根本波及不到**。 | ✅ **不影响 headless 复现** |
| **`t_remain` 权威量** | hitstop 不改 `t_remain`/hp/dps，只是**减速墙钟**。 | ✅ **不动** |
| **零新信号** | hitstop 不新增信号。 | ✅ |
| **🔴 时间轴权威 / SSOT** | `Engine.time_scale` 的**唯一写入者**应是 `TimeDirector`（`wave_director.gd:42-44` 明写「本项目用 `get_tree().paused=true`；`Engine.time_scale` 永不为 0」；TimeDirector 是时钟权威、写 `time_scale`/`paused`）。**若由 UI/VFX 直接写 `Engine.time_scale` → 越权，破坏 SSOT 分层**。 | **⚠️ 触碰**（架构面） |

**结论**：hitstop **不触碰「数值/口径/golden」红线，但触碰「时间轴权威」这条架构红线**——必须**经由 `TimeDirector`** 实施（`scripts/ui/time_director.gd`），且**永不为 0**（SR-R5）。次要风险：`time_scale<1` 会拉慢**所有非 `ALWAYS` 节点**的 `_process(delta)`，与安全窗 `get_tree().paused`（:328）机制交互，**影响面偏宽**。→ **建议：hitstop 单独走 ADR + 红线复核，不并入本轮 VFX**（**不建议本轮**）。

> 补充：hitstop 即便"值不变"，其**存在本身**是新的**择时/手感机制**——与「零择时读数」等既有设计纪律相关，属需设计侧共同评审的范畴，非纯工程可单方面拍板。

---

## 6. 分层契约核对：是否全部可落 `scripts/ui/`？

| 项目 | 落点 | 是否必须动 engine/gameplay | 最小改动面 | 风险 |
|---|---|---|---|---|
| **P1-1** 装饰投射物 | ✅ 全落 `scripts/ui/monster_layer.gd` | **否** | 1 个 ui 文件 | 低（纯呈现） |
| **P1-2** 伤害数字 | 逻辑在 `scripts/ui/`；**需 1 只读键**在 `wave_director.snapshot()` | **是**（`scripts/gameplay/wave_director.gd`，**+1 行**） | 1 gameplay 文件 +1 行（additive 只读）+ 1 ui 文件 | 低（additive、不动值/口径/信号） |
| **P1-3a** 碎片/冲击环 | ✅ 全落 `scripts/ui/monster_layer.gd` | **否** | 1 个 ui 文件 | 低 |
| **P1-3b** hitstop | 需经 `scripts/ui/time_director.gd`（时间权威） | **是**（时间权威，须走 SSOT） | 1 个 ui 文件（但语义是"权威扩展"） | **中–高（架构红线）** |

**要点**：除 **P1-2 的一个只读派生键** 外，全部可落呈现层。**P1-2 的 `index` 键不改任何值/口径/信号**，与既有 `sapper`/`revive_charged` 同族（additive read-only），**属安全的契约扩展**。**唯一需额外 ADR 的是 hitstop**（时间轴权威面）。

---

## 7. 汇总表（最终交付）

| 项目 | 可行性 | 最小改动面 | 是否触碰红线 | 成本估 | 前置依赖 |
|---|---|---|---|---|---|
| **P1-1** 装饰投射物 | ✅ 可行（渲染层纯派生·装饰性） | `scripts/ui/monster_layer.gd`（1 文件） | **否** | **中** | 无（塔位/怪位/`t_remain` 均现成） |
| **P1-2** 伤害数字 | ✅ 可行 | `wave_director.snapshot()` **+1 只读键 `index`** + `scripts/ui/` 新代码 | **否**（additive 只读） | **中** | 无（键可即时加） |
| **P1-2** 击杀数字 | ✅ 可行（更简） | 仅 `scripts/ui/`（订阅 `monster_killed`） | **否** | **低** | 无 |
| **P1-3a** 碎片/冲击环 | ✅ 可行 | `scripts/ui/monster_layer.gd` | **否** | **低** | 无 |
| **P1-3b** hitstop | ⚠️ 有条件可行 | `scripts/ui/time_director.gd`（时间权威） | **⚠️ 触碰「时间轴权威」架构红线**（非数值红线） | **中–高** | **单独 ADR + 红线复核 + 设计侧评审** |

**总判读**：Phase 6 爽点层三件套中的**投射物 / 伤害数字 / 击杀反馈（碎片环）三项，均可在呈现层落地，几乎零玩法改动**（唯一 gameplay 触碰是 1 个 additive 只读快照键，零口径扰动）。**hitstop 是唯一需要谨慎的红线项**，建议隔离为独立 ADR 议题。

---

## 8. 需实测项（若获批进入实现）

本轮静态分析即可定可行性（§1–§6 证据充分），**无需跑 Godot**。以下仅"实现期"需实测：
- **P1-2 `index` 键**加入后：跑 `tests/run_tests.gd`（EXIT=0）+ `tests/scan_counterplay_factorial.gd`（锚点 224/300 & 204/300 不变）→ 确认 additive 键**零回归**（预期零扰动，因不改任何结算）。
- **P1-1 装饰弹**：窗口模式截帧确认视觉（不涉数值）。
- 均属**实现后验证**，非可行性阻塞。

---

## 9. 红线声明

- 本文档为**只读评估**：未改任何 `scripts/`、`design/`、`tests/` 生产代码；未改任何数值/口径；未 push。
- 全部结论基于**静态阅读 + 行号证据**。
- 唯一标注为"触碰红线"的是 **P1-3b hitstop**（时间轴权威架构面），已建议隔离为独立 ADR。
