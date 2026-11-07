# 触发型建筑（Tower Triggers）—— 登场 / 整备 / 阵亡 加等级

> 需求（2026-11-07）：「新增让塔升级的方式，比如相同的塔合成，或者其他塔的效果，
> 来丰富卡包内容」→ 明确口径：「按照王者万象棋里的增加等级方式，
> **回合开始时 / 防御塔上场时 / 防御塔死亡时**增加等级，
> 不要简单的光环加等级」。
>
> 落地：`scripts/engine/tower_effects.gd` + `tower_data.TOWERS_EXT` 的 `effect` 字段
> + 三个钩子（`shop_runtime` 落子 / `wave_director.start_wave` / `wave_director` 死亡）。

---

## 0. 结论前置

1. **等级 = 事件触发的一次性加成**，不是光环、不是三合一升星。
   三条时机各自对应一种建筑，玩家用**塔位 + 废料**换等级节奏。
2. **写的是同一个 `h`**：伤害 `h^0.6`、塔 HP `h^0.6`、共鸣门槛 `h≥3` 全部自动跟随，
   不新增任何平行数值通道。
3. **封顶 8 级**：`TowerEffects.LEVEL_CAP = 8`。🆕 2026-11-07 由 3 提到 8 ——
   与形态满级（`h≥8` 外环）/ `Focus` 预热满额（`min(1,h/8)`）同档。
   触发只往上顶到 8，不会无限滚雪球；**合成升级（同格同名再落）不受此限**，仍无硬上限。
4. **金标本零扰动**：金标本走 `wave_sim` + 只买 `TOWERS` 基础塔；三张触发建筑全在
   `TOWERS_EXT`，`apply_trigger` 对没有 `effect` 的塔是纯 no-op。

---

## 1. 三张触发建筑

| 卡 | 触发 | 效果 | 面板 | 设计意图 |
|---|---|---|---|---|
| **Vanguard 先锋** | `enter` 登场 | 自身 +1 级 | dps 8 · rng 18 | 落子即 2 级，抢开局节奏；想拿它就得先占一个塔位 |
| **Drillmaster 教官** | `prepare` 整备 | 每波开始全场 +1 级 | dps 5 · rng 17 | 慢速滚雪球：先立教官再开波，每波全场 +1，约 8 波到满级形态（8 级） |
| **Martyr 遗志** | `death` 阵亡 | 本塔死亡时全场 +1 级 | dps 6 · rng 16 | 用塔位换等级：把它放在暴露位，让它先死 |

🔴 三张都出现在卡包里（泛用包 / 熔炉包 / 咒术包），**每包仍 6 张建筑**。

---

## 2. 触发时机与钩子

| 时机 | 钩子位置 | 生效范围 | 备注 |
|---|---|---|---|
| `enter` 登场 | `ShopRuntime.confirm_placement_at()` 落子成功后 | 立即 | 同格再落（合成）也算一次登场 |
| `prepare` 整备 | `WaveDirector.start_wave()`，在 `dps_only` **之前** | **本波**即生效 | 每波一次 |
| `death` 阵亡 | `WaveDirector` 塔 HP 归零、`disabled = true` 之后 | **后续子步**即生效 | 放在 dps 重算之前 |

### 2.1 为什么阵亡能"当波生效"

`wave_director` 在塔死亡处本来就会重算一次 `dps`（让下一子步的集火用新 DPS）。
阵亡触发挂在**重算之前**，所以加等级 → 重算 → 存活塔立刻吃到。
（注意：这与批处理镜像不同步，但**只有玩家路线**会出现触发塔，金标本/MC 走批处理，不受影响。）

---

## 3. 数据表

```gdscript
"Vanguard":    {"dps": 8.0, "tag": "", "aoe": false, "slow": 0.0, "rng": 18.0,
                "effect": {"on": "enter", "lv": 1, "scope": "self"}},
"Drillmaster": {"dps": 5.0, "tag": "", "aoe": false, "slow": 0.0, "rng": 17.0,
                "effect": {"on": "prepare", "lv": 1, "scope": "all"}},
"Martyr":      {"dps": 6.0, "tag": "", "aoe": false, "slow": 0.0, "rng": 16.0,
                "effect": {"on": "death", "lv": 1, "scope": "all"}},
```

- `on` ∈ `enter` / `prepare` / `death`
- `lv` = 加几级（当前都是 1）
- `scope` ∈ `self` / `all`
- 查询入口：`TowerData.tower_effect(ctype)`（普通塔返回 `{}`）

---

## 4. 与另外两条升级路线的关系

| 路线 | 机制 | 是否需要新卡 | 现状 |
|---|---|---|---|
| **合成** | 同一格再落同名塔 → `h + 1` | 否 | 已存在（`apply_action("up")`） |
| **触发** | 登场 / 整备 / 阵亡 → `h + 1`（封顶 8） | 是（本文件的 3 张） | **本版新增** |
| ~~光环~~ | 被动给范围内塔加等级 | — | ❌ 用户明确否掉 |

🔴 合成是"投入同名牌"，触发是"投入塔位换等级"，两者叠加时都改同一个 `h`。

---

## 5. 结构断言（`tests/run_card_pack_asserts.gd` §H，15 项）

1. 登场只触发 1 座塔、只升自己；
2. 整备一次升全场 3 座；
3. 封顶：继续整备到 8 级后不再升（再触发 0 座变化），且上限常量 == 8；
4. 阵亡只升其它塔，死者自己不吃加成。

---

## 6. 未做 / 后续

- **触发提示**：塔等级牌只显示 `Lv`，不显示"刚被整备 +1"。要做得加一次闪现/飘字。
- **触发冷却 / 每波限次**：当前整备每波必触发；若 MC 显示滚太快，可加 `cooldown_waves`。
- **更多时机**：`kill`（击杀）、`wave_clear`（清波）、`adjacent_death`（邻塔阵亡）——
  `effect.on` 加一个枚举值即可，钩子点已明确。
- **数值未校准**：三张塔的 dps 与 `lv` 都是首版估值，未跑 MC。

---

## 7. 第二批机制（2026-11-07 · 用户点名：攻击 / 防御 / 回复 / 持续掉血 / 击杀升级）

> 需求：「可以增加的机制比如增加攻击，增加防御，回复生命，持续掉血，击杀升级等等」。
> 全部做成**建筑自带效果**，改的都是玩家路线；金标本的塔不带这些字段 → 逐位零扰动。

| 机制 | 字段 | 卡 | 效果 | 实现点 |
|---|---|---|---|---|
| **增加攻击** | `buff_atk` | **Omen 凶兆** | 全场塔 dps +10%（可叠，封顶 +60%） | `damage_engine` 逐塔乘 `(1+Σ)` |
| **增加防御** | `buff_def` | **Quake 震地** | 全场塔最大生命 +15%（封顶 +60%） | `wave_director._init_tower_hp` / 复活处 |
| **回复生命** | `heal` | **Wither 枯萎** | 每秒为全场塔恢复 1.5 生命 | `wave_director._substep` ②c |
| **持续掉血** | `dot` | **Plague 瘟疫** | 每秒对全场怪物造成 4 点无视抗性伤害 | `wave_director._substep` ②b |
| **击杀升级** | `on_kill_lv` | **Null 归零** | 任意怪物被击杀 → 本塔 +1 级（封顶 8） | `_apply_pool_live` 击杀处 |
| **赏金** | `bounty_kills` / `bounty_scrap` | **Scout 斥候** | 存活时全队每累计 10 杀 → +6 废料（可重复） | `tower_effects.on_kill` → 波末 `grant_wave_result` 入账 |
| **弹射** | `bounce` | **Tesla/Bolt/Storm/Arc/Spark/Thunder** | 子弹可跳弹 N 次，每次 +20% 等效输出 | `damage_engine` 逐塔乘 `(1+0.2N)` |
| **贯穿** | `pierce` | **Lance/Javelin/Ballista/Sniper/Harpoon** | 子弹可穿透 N 个敌人，每个 +25% 等效输出 | `damage_engine` 逐塔乘 `(1+0.25N)` |

### 7.1 口径说明

- **攻击 / 防御光环按「座」累加，不按等级**：升级只放大该塔自身输出，光环量恒定，
  避免「升一级光环翻倍」的复利失控（封顶 0.60）。
- **回复与持续掉血都是「每秒」结算**（`_WaveSim.DT` 口径），只在**实时战斗**里生效：
  批处理镜像（金标本 / MC）不含这些塔，不存在两边分叉。
- **击杀升级不区分击杀者**：聚合池模型没有逐塔归属，任一击杀都让 `on_kill_lv` 塔 +1，
  封顶 8 级 —— 与「登场 / 整备 / 阵亡」共用 `LEVEL_CAP`。

### 7.2 卡池总览（48 张 · 8 包 × 6 张 · 一卡一包）

- 基础 18 张：Arrow / Cannon / Frost / Lance / Javelin / Tesla / Bolt / Sunder / Maul /
  Hex / Rune / Ember / Icicle / Oblivion / Void + Vanguard / Drillmaster / Martyr
- 扩充 30 张：Scout / Mortar / Foundry / Blaze / Cinder / Pyre / Glacier / Hail / Permafrost /
  Frostbite / Storm / Arc / Spark / Thunder / Ballista / Sniper / Harpoon / Breaker / Shatter /
  Ruin / Cleave / Quake / Curse / Plague / Wither / Omen / Exile / Null / Rift / Abyss
- 机制分布：登场 1 / 整备 1 / 牺牲 1 / 觉醒 2 / 经济 1 / 攻击光环 1 / 防御光环 1 /
  回复 1 / DoT 1 / 击杀升级 1 / 减抗光环 8（Sunder/Breaker/Shatter/Ruin/Curse/Plague/Hex）

---

## 8. 变更：等级上限 3 → 8（2026-11-07 · v0.2）

> 需求：「增加塔的等级上限」。

- `TowerEffects.LEVEL_CAP` 由 **3 → 8**。8 不是随手选的数：它是**形态满级**
  （`monster_layer._draw_tower_form` 在 `h≥8` 画外环）与 `Focus` 预热满额
  （`min(1, h/8)`）的同档值 → 触发升级能走到「满级形态」，再往上不再有形态/乘区跃迁。
- **只封触发加等级**：合成升级（同格同名再落）仍**无硬上限**，保持「`h^0.6` 次线性、
  雪崩无上限」的定性。因此等级牌在 `h > 8` 时仍会显示真实数字（不标 MAX）。
- **MC 复跑**（`tests/run_pack_mc.gd`，1 seed / 56 组合，其余口径逐项不变；
  读数取 2026-11-07 20:27 快照 —— 与 `pack-mc-v01.md` §7 同一棵树，贯穿机制尚未落地）：

  | 上限 | 通关率 | 平均波次 |
  |---|---|---|
  | 3（改前） | 10 / 56 = 17.9% | 15.79 |
  | **8（改后）** | **10 / 56 = 17.9%** | **16.48** |

  → 通关率不变、平均波次 **+0.69**：上限提高先把「差一点」的组合推近 W20，
  **没有改变胜负结构**（瓶颈仍是成长引擎数量 / 非霜序包缺等效输出，见 `pack-mc-v01.md` §4）。
- **断言**：`tests/run_card_pack_asserts.gd` §H 由 11 项扩到 **15 项**，新增
  「上限常量 == 8」与「推到 8 后再触发 0 座变化」两条硬断言。
