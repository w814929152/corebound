# 切片6 验证报告 · T1 仇恨口径登记 + 暴露度数据地基

> **结论**：🟢 **全部验收项通过，退出码 0**；金标本零改动；`disabled` 占位 MVP 恒 false → DPS 逐位零影响；切片5 逐位等价基线纹丝不动。
> **边界**（用户 2026-10-01 拍板）：本切片**只登记口径 + 核验数据地基 + 落地 MVP 占位，不激活任何 T1 玩法**。仇恨整体留后续批次 + 300 局 MC 重扫后上线。

---

## 0. 背景：为什么切片6 是「口径登记」而非「玩法实现」

用户在切片5 完成后拍板 T1 仇恨的落地方式 = **留到后续批次**（遵从设计文档 `mechanics-tower-life-death` §0「MVP 只登记口径不实现」）。核心原因：

> **仇恨在物理上无法与切片5 刚建立的「实时版与金标本逐位等价」基线共存。**
> 仇恨 = 怪物距塔 ≤ `AGGRO_R=9.0` 时转向攻塔 → 偏离最短路径 → 到达核心时间改变 → 漏怪分布改变。而切片5 的逐位等价依赖「怪物沿最短路径、波内 DPS 恒定」。

这与 S5-D1（三原型+Elite 列校准闸门）是**同一哲学**：设计已定稿，校准未过不默认开。

---

## 1. 验收锚点

| # | 验收项 | 结果 |
|---|---|---|
| AC-S6-1 | `disabled` 占位：MVP 恒 false → 对定稿 DPS **逐位零影响** | ✅ PASS |
| AC-S6-2 | `disabled=true` → **断输出不断链**（E/κ/κ_r 不变 + 全局乘区不变） | ✅ PASS |
| AC-S6-3 | 暴露度数据地基：`d_path` 逐位 + 硬约束「≥1 安全位」 | ✅ PASS |
| AC-S6-4 | AGGRO 参数登记 + `tower_aggro_enabled` 默认 false（金标本等价口径） | ✅ PASS |

---

## 2. 代码落地（唯一的 MVP 占位，逐位零影响）

### 2.1 `TowerState.disabled` 字段
`scripts/engine/player_state.gd`：
```gdscript
class TowerState extends RefCounted:
    var slot: int = 0
    var ctype: String = ""
    var h: int = 0
    var attach: Dictionary = {}
    # 🔒 T1 占位（§4.3 交接点③）：塔死亡对 7 乘区管线的唯一落点。
    #    MVP 恒 false → 该乘数恒 1.0 → 对定稿 DPS 逐位零影响。
    var disabled: bool = false
```

### 2.2 `damage_engine` 的 `Disabled_i≡1.0` 落点
`scripts/engine/damage_engine.gd`（per_tower 末尾）：
```gdscript
var dps_i := base * stack * syn * res * foc * ali * cov
# 🔒 T1 占位：塔死亡唯一落点。MVP disabled 恒 false → 乘数恒 1.0。
dps_i *= 0.0 if bool(t.disabled) else 1.0
per_tower.append({ ..., "dps": dps_i, "disabled": bool(t.disabled) })
```

**为什么逐位零影响**：MVP `disabled` 恒 false → `dps_i *= 1.0` → 所有 per_tower.dps、ΣRaw、TOTAL DPS 与金标本逐位相同。单测 AC-S6-1 已钉死（默认 vs 显式 disabled=false 逐位相同）。

---

## 3. 断输出不断链（AC-S6-2 的实证）

把深叠主塔（h=133 Cannon）打停机后：
- ✅ 该塔 `dps → 0.0`（**断输出**）
- ✅ 其他塔 `dps` 不变（**不断链**：不重建邻接表）
- ✅ `E / κ / κ_r` 全部不变（停机不重算共鸣 —— E-T 口径）
- ✅ 全局乘区（AoE×Crossfire×Aux×Empower）不变（`tag_tower_lv`/塔数都不变）
- ✅ TOTAL 减少量 = 停机塔 dps × 全局乘区（**线性可加，无 κ/E 连锁放大**）

> 🔑 这正是设计文档 §0.2 第3条「不算失败，且不断链」口径的工程落点：塔死亡对 7 乘区管线**只需在 `Raw_i` 末尾乘一个 `×0`**，不触发 `LinkGraph` 重算。

---

## 4. 暴露度数据地基（AC-S6-3）

`path_geometry.gd` 的 F-3 暴露度计算已随切片5 落地，本切片用 Python 金标本交叉验证逐位一致：

| 塔位 | 坐标 | `d_path`（实算） | GDD §5.3 表 | 暴露（≤9.0） |
|---|---|---|---|---|
| S0 | (6,33) | 6.00 | 6.00 ✅ | 🔴 暴露 |
| S1 | (22,40) | 8.00 | 8.00 ✅ | 🔴 暴露 |
| S2 | (30,33) | 5.00 | 5.00 ✅ | 🔴 最暴露 |
| S3 | (45,33) | 8.00 | 8.00 ✅ | 🔴 暴露 |
| S4 | (18,16) | 10.82 | 10.82 ✅ | 🟢 安全（余量+1.82） |
| S5 | (48,42) | 13.00 | 13.00 ✅ | 🟢 最安全 |

- 🔴 **硬约束成立**：`AGGRO_R=9.0` 切出 **4 暴露位（S0–S3）+ 2 安全位（S4/S5）**，满足「任何地图必须保证 ≥1 个塔位在 `AGGRO_R` 之外」。

---

## 5. AGGRO 参数登记（AC-S6-4，一字不改定稿数值）

| 参数 | 值 | 说明 |
|---|---|---|
| `AGGRO_R` | 9.0 | R1 转向半径（🔒 T1 才生效） |
| `AGGRO_EXIT` | 10.8 | R4 迟滞带退出阈值 = 9.0×1.2（🔒 T1） |
| `AGGRO_TICK` | 0.10 | R3 判定频率（与 sim dt=0.1 对齐，🔒 T1） |
| `tower_aggro_enabled` | false | MVP 金标本等价口径（默认关闭） |
| `prototype_split_enabled` | false | 三原型（默认关闭） |
| `elite_waves_enabled` | false | Elite 波（默认关闭） |

---

## 6. 全量回归

```
切片1  通过 222 项 / 失败 0 项
切片2  通过 2228 项 / 失败 0 项   （含 MC A69.3%/B91.3% 逐位复现）
切片3  通过 142 项 / 失败 0 项
切片4  通过 123 项 / 失败 0 项
切片5  通过 302 项 / 失败 0 项   （实时版与金标本逐位等价）
切片6  通过 41 项 / 失败 0 项
─────────────────────────────────
合计   3058 项断言 / 0 失败 / 退出码 0
```

- 🔴 **金标本零改动**：`wave_sim.gd` / `shop_ai.gd` / `corebound_sim_v03.py` 均未变（git diff 证据）。
- 🔴 **逐位等价基线纹丝不动**：切片5 的 W1/5/10/15/20 kills/leaked/scrap 仍 |d|=0。

---

## 7. 踩坑留档（供后续切片）

1. **GDScript `var x := func_return()` 类型推断失败**：`_Geo6.build()` 返回类型未标注 → `:=` 报错 "Cannot infer the type"。改用 `var geo = _Geo6.build()`（切片5 的 `_geo = null` 后赋值同理）。
2. **GDScript `%` 格式化不支持 `%e`**（slice5 注释 G7 已说明）：科学计数法要自己写 `_sci()`，或直接用 `%s` + `str()`。切片6 首版照抄了 `_check` 却漏看这点 → 1 项格式化崩溃。
3. **`TOTAL = ΣRaw × 全局乘区`**：验证「断输出不断链」时，不能断言「TOTAL 减少量 == 单塔 dps」，要乘上全局乘区（`total/ΣRaw`）。单塔 dps 不变 + 全局乘区不变 = 线性可加无连锁。

---

## 8. 下一步（依 S5-D1 校准闸门）

1. **T1 仇恨真激活**（`tower_aggro_enabled=true`）——需先设计「仇恨只改路径、不改 DPS 分配」的等价口径，或接受验收从逐位等价改为统计容差 + 300 局 MC 重扫。
2. 三原型+Elite 的 300 局 MC 重扫（S5-D1 校准闸门）。
3. 拆除回收 / 弃卡 / 卸下改投（切片4 遗留）。
4. C2 高亮 H2–H9。
