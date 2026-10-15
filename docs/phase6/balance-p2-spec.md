# Phase 6 · P2-Sapper 域 参数规格（只写规格 · 零改值）—— OBS-2 修正方向 P2

> **性质**：**只写规格**（spec-only）。本轮**未改动任何数值 / 代码**（`mvp_config.gd` / `monster_data.gd` / `wave_director.gd` / `wave_sim_aggro.gd` 均**未动**），**未跑 Godot**，**未 push**。数值列**原为 PLACEHOLDER**（待用户拍板 + 工程实现 + MC 标定）—— **✅ 已于 Phase 6 · P2 提交② 定稿**（见 **§1.3 · §7.2**）。
> **授权依据**：用户已批准「平衡推进 = **P2-Sapper 域 · 仅 W≥10**」。
> 🔴 **命名消歧**：带「P2」的旧引用须**按域判别** —— **「P2-Sapper 域」**（本文件 · Sapper 对塔伤害余额/倍率 `SAPPER_DMG_MULT × g(w)`）与 **「P2-雪崩支柱」**（`docs/phase6/vfx-art-spec.md` §10 · 视觉密度）**互不相干**。
> **上游诊断**：`docs/phase6/balance-eval.md`（复核订正版 v2）§2.2 · `docs/phase6/balance-eval-verify.md`（V7）。
> **负责人**：design-strategist（文策渊） · **引擎**：Godot 4.7.2-stable · **日期**：Phase 6 打磨期
> 🟢 **执行口径（team-lead 确认 · 2026-10-13）**：**先落机制、后调参（解耦）** —— 提交①「落机制」中性 `G0=1.0/SLOPE=0.0` ⇒ `g≡1`（零行为变更 · CI 全绿 · `203` 有效）；提交②「翻参」= 独立提交 + 独立基线重签。详见 **§7.1 / §8.2**。

---

## 0. 范围声明（Scope lock）

本规格**只落 Sapper 域**，且**只作用 W≥10**：

- ✅ 允许：改 **`SAPPER_DMG_MULT` 的取值口径**（把常量换成「随波因子 × 常量」的函数）。
- 🔴 禁止（不在本规格内）：碰 `n_e(w)` / `m_hp_elite` / `c(w)` / `spawn_window` / `scrap_*` / `hp_growth` / `max_actions` / `wave_price_step` 等任何其它值。
- 🔴 **W5 精确保留**：梯度**不作用于 W5**（W5 = 教「首精英 + 修复」的教学墙，见 `playtest-report` §1.1 / R2）。

---

## 1. 精确公式

### 1.1 设计选择：**给 `SAPPER_DMG_MULT` 乘一个随波因子**（不新增独立乘区）

复用**既有乘位**，Sapper 对塔伤害从
```
dmg = ATTRITION × HP0 × m_dps × SAPPER_DMG_MULT × DT        （现行 · 两处消费）
```
改为
```
dmg = ATTRITION × HP0 × m_dps × sapper_dmg_mult(w) × DT
其中 sapper_dmg_mult(w) = SAPPER_DMG_MULT × g(w)           （单点 SSOT）
```
**理由**：① 不新增乘区 = 不动 7 乘区结算顺序（`damage_engine` 红线 R-1 不受影响）；② 只改 Sapper 分支 → 与「只碰 Sapper 域」的授权一致；③ `g` 是可退化函数 —— **`g≡1` 即现行行为**（见 §6 回滚）。

### 1.2 随波因子 `g(w)` 定义（精确）

```
# ---- SSOT：scripts/data/monster_data.gd（新增 static func；参数为 const）----
# ✅ 已定稿（Phase 6 · P2 提交②）—— 参数 `W0=10 / G0=1.5 / SLOPE=0.10 / CAP=3.0`
const SAPPER_RAMP_W0    := 10      # 首个受梯度作用的波（GRADIENT_ON_WAVE）= 10
const SAPPER_RAMP_G0    := 1.5     # W0 处的梯度基线（g(10)）
const SAPPER_RAMP_SLOPE := 0.10    # 每波线性增量（≥0）
const SAPPER_RAMP_CAP   := 3.0     # g 的上限（clamp 上界，≥ G0）

static func sapper_dmg_mult(w: int) -> float:
    if w < SAPPER_RAMP_W0:                     # w ∈ {1..9}（含 W5）
        return SAPPER_DMG_MULT                 # ← 精确 = 3.0，逐位保留现行
    var g := SAPPER_RAMP_G0 + SAPPER_RAMP_SLOPE * float(w - SAPPER_RAMP_W0)
    g = clampf(g, SAPPER_RAMP_G0, SAPPER_RAMP_CAP)
    return SAPPER_DMG_MULT * g
```

| 量 | 含义 | 取值 |
|---|---|---|
| `SAPPER_RAMP_W0` | 梯度**开启波**（首个受梯度作用的波） | **10** |
| `g(w)`, `w < 10` | 未开启 → 恒等 | **1.0**（→ mult = **3.0**，逐位不变） |
| `g(w)`, `w ≥ 10` | `G0 + SLOPE·(w−10)`，clamp 到 `[G0, CAP]` | 线性、单调不减 |
| 生效波（离散） | 仅精英波 **{10, 15, 20}** 会**实际消费**（Sapper 只在精英波生成） | — |
| 数学定义域 | 全 `w`（函数纯） | 但 w<10 恒 3.0、非精英波不消费 |

### 1.3 定稿值（✅ Phase 6 · P2 提交②）

| 参数 | 定稿值 | 效果 |
|---|---|---|
| `SAPPER_RAMP_G0` | 1.5 | W10 → g=1.5 → mult **×4.5** |
| `SAPPER_RAMP_SLOPE` | 0.10 / 波 | W15 → g=2.0 → ×6.0 |
| `SAPPER_RAMP_CAP` | 3.0 | W20 → g=2.5 → ×7.5（未触顶；CAP 仅兜底） |

> ✅ **本表数值已定稿**（Phase 6 · P2 提交② · 已 MC 标定「W10/15/20 恢复压力且不造新墙」+ 用户签 · 2026-10-15）。**实际落地结果见 §7.2。**
> 🟢 **回滚口径**：把 `G0` 设为 **1.0** 可回到「W10 与现状持平」（若同时置 `SLOPE=0.0` 则全 `w` 中性/逐位等价）—— **零代码**，见 §6.1 / §7.1。

---

## 2. 边界（下限 / 上限 / clamp / 斜率 / 封顶）

| 边界 | 约定 |
|---|---|
| **下限** | `w<10` → **精确 `SAPPER_DMG_MULT`（3.0）**；`w≥10` → **≥ `SAPPER_DMG_MULT × G0`**（G0 ≥ 1） |
| **上限（封顶）** | `SAPPER_DMG_MULT × SAPPER_RAMP_CAP`（`clampf` 上界） |
| **clamp** | ✅ 对 `g` 做 `clampf(g, G0, CAP)`（防线性外推越界） |
| **斜率** | `SLOPE ≥ 0`（**单调不减** → 威胁只增不减，绝不弱化） |
| **增长型** | **`g` 上线性**（即 mult 线性）；**不用**指数/复利（避免后期爆表） |
| **连续性** | `w=9→10` 处 **阶跃**：`g` 从 1.0 跳到 `G0`（若 `G0>1`）。阶跃**只落在 W10**（W5/W6–9 不受影响） |
| **奇偶/取整** | 无取整；全程 float |

---

## 3. 实现契约（保证实时↔批处理逐位等价 · 关键）

### 3.1 消费点（全部必须走同一 SSOT）

| # | 文件:行 | 角色 | 现读法 |
|---|---|---|---|
| 1 | `scripts/gameplay/wave_director.gd:525` | **实时** | `_MonsterData.SAPPER_DMG_MULT if m.sapper else 1.0` |
| 2 | `scripts/engine/wave_sim_aggro.gd:824` | **批处理镜像** | `float(_MonsterData.SAPPER_DMG_MULT) if bool(m[5]) else 1.0` |
| 3 | `scripts/engine/wave_sim_proto_aggro.gd:220` | 三原型镜像 | **复用 #2 的 static helper**（注释明示「塔伤害 / sapper×3 一律复用」）→ 随 #2 一起改，无需单列 |

→ 改动**只有 2 个直接读点**（#1、#2）；#3 经 #2 继承。

### 3.2 位等价铁律

- 因子是 **`w` 的纯函数** → 实时与批处理**用同一个 `w`、调同一个函数** → 逐位相同（构造性保证）。
- **实现建议（二选一，均位安全）**：
  - **(A) 波级预计算 + 贯穿**：在波首算 `var sapper_mult := MonsterData.sapper_dmg_mult(w)`，贯穿到 `_apply_aggro` → `_damage_tower`。（实时 `w` 为成员变量、批处理 `simulate_wave_aggro(w,…)` 已持有 `w`。）
  - **(B) 出生时落值**：`_spawn_one` / `_build_sapper_flags` 处把 `sapper_mult` 存到怪物（实时 `m.sapper_mult`；批处理 monster 元组尾加一格）。`_damage_tower` 直读，不穿 `w`。
- 🔴 **禁止**：只在实时或只在批处理改（→ AC-T1-25 逐位守护会破）。

### 3.3 配置入口 & 授权（承 req 7）

- **入口**：`scripts/data/monster_data.gd` = Sapper/Elite/仇恨表的 **SSOT**（`monster_data.gd:46-50`）。新增 `SAPPER_RAMP_*` const + `sapper_dmg_mult(w)` static func **放这里**。
  - 🔴 **不放进 `mvp_config.gd`**：该文件的 `cfg_of()` 是金标本 config 对象，**新增 key 会改 cfg 形状** → 波及打印/序列化/遍历。放 `monster_data.gd` = **零 cfg-shape 变更** = 零金标形状风险。
- **属性确认**：`SAPPER_DMG_MULT` 现标 **T1 诊断域**（`monster_data.gd:46-50`：「由 `elite_waves_enabled` 诊断开关控制，MVP 恒 false → 本值不消费」）；GDD `wave-spawner` §2.11（`:487-497`）：「**Sapper 不进 MVP**」。
- **改它是否需额外授权**：**需要**。理由：它是**玩法数值口径**且**参与默认回归套件 `t1aggro`（W5 断言）** → 按项目纪律（动平衡域玩法值须主理人/用户批准 + MC 复核）→ **需用户批准**。**但它不触任何金标本冻结项、不触三条守恒律**（§4）。
- **口径回写**：落地后须在 **GDD §2.11** 登记「Sapper 对塔伤害进入 W≥10 梯度档」以使文档=引擎（避免「文档定 A、引擎跑 B」）。

---

## 4. 与守恒律 / 默认金标 / 定稿的关系（明确）

| 关系 | 结论 | 依据 |
|---|---|---|
| **三条守恒律**（§2.5.2 总 HP / 只数 / 在场时间） | ✅ **正交**（本规格只改 Sapper 词缀的**对塔伤害**，不动三原型 `Σp·m_hp / Σp / Σp/m_spd`，也不动 `n_e` / `m_hp_elite`） | `balance-eval-verify.md` §4.2；本规格 Scope lock（§0） |
| **GDD §2.5.4 Elite 守恒 `c(w)`** | ✅ **不触**（未动 `n_e` / `m_hp_elite`） | 同上 |
| **默认金标（PATH 逐位等价）** | ✅ **不破**（默认 `elite_waves_enabled=false` → 无 Sapper → `sapper_dmg_mult` **不被消费**；且 `w<10` 恒 3.0） | `balance-eval-verify.md` §4.3；`monster_data.gd:46-50` |
| **全波次逐位 MC 金标**（`test_suite_slice2`：B 起飞率 91.3% / 274·300 / 20 局 trace） | ✅ **不破**（slice2 走 `run_loop` 金标本口径，**无 aggro/无 Sapper** → 本函数不被调用） | 见 §5.3 复算 |
| **单测定稿值** | ✅ **不动定稿**：本规格不碰 Q-T8(`REPAIR_RATE`)、§2.5.4、`hp_growth` 等任一冻结/定稿项；只动 **T1 诊断域**的 `SAPPER_DMG_MULT` | — |

---

## 5. 验收判据（可测）

> 全部为**可复现的静态断言或 headless 复跑**；任一项不达标 = 未通过。

### 5.1 边界守恒（静态 · 必过）

| # | 断言 | 期望 |
|---|---|---|
| A1 | `sapper_dmg_mult(5)` **逐位 == 3.0** | PASS（W5 教学墙钉死） |
| A2 | `∀ w ∈ {1..9}: sapper_dmg_mult(w) == 3.0` | PASS（梯度绝不泄漏到 W<10） |
| A3 | `∀ w: sapper_dmg_mult(w) ≥ 3.0` | PASS（单调不减，只加压不弱化） |
| A4 | `∀ w ∈ {10,15,20}: sapper_dmg_mult(w) == 3.0 × clampf(G0 + SLOPE·(w−10), G0, CAP)` | PASS（公式一致） |
| A5 | `G0 == 1 && SLOPE == 0` ⇒ `∀ w: sapper_dmg_mult(w) == 3.0` | PASS（退化=现行，回滚性质，§6） |

### 5.2 W5 教学墙未破坏（行为 · 必过）

| # | 判据 | 期望 |
|---|---|---|
| B1 | 重跑 `t1aggro` 的 `_test_sapper_realtime` / `_test_sapper_batch`（**全部 W5** 断言）| **全绿不变**（`test_suite_t1_aggro.gd:629-732`） |
| B2 | `run_tests.gd` **无参**回归（默认段 slice1~8 + t1aggro） | **PASS**（exit 0） |
| B3 | 端到端 `playtest_driver.gd -- product`：**W5 行为逐位不变**（核心 HP 轨迹 = 1000→850、W5 结束 3 塔 Disabled） | PASS（对齐 `playtest-report` §1.1） |

### 5.3 W10 / W15 / W20 恢复压力（行为 · 必过——本规格的**目的**）

| # | 判据 | 现状 | 期望 |
|---|---|---|---|
| C1 | RADIAL 产品口径下，精英波 **{W10,W15,W20}** 中 **≥2 波** `core_damage > 0` 或 `towers_disabled ≥ 1` | **0 波**（`playtest-report` §1.1：W10/15/20 零核心伤害、Disabled=0） | **≥2 波**（恢复梯度） |
| C2 | 该口径下 **W10 未成为新硬墙**（核心未在 W10 归零；W10 掉血 ≤ W5 量级） | — | PASS（避免「前重后轻」变成「前后都重」） |

### 5.4 非精英波零扰动（行为 · 必过）

| # | 判据 | 期望 |
|---|---|---|
| D1 | W6–W9 / W11–W14 / W16–W19 的核心轨迹与改前**逐位一致**（梯度只作用精英波） | PASS |

### 5.5 实时↔批处理逐位等价（行为 · 必过）

| # | 判据 | 期望 |
|---|---|---|
| E1 | `t1aggro` 的 `AC-T1-25A`（真身↔镜像 逐波差异，w∈{5,8}） | 差异 **0** |
| E2 | `t1aggro` 的 `AC-T1-25B`（整局 W1–20 `run_loop_aggro` vs `run_loop_proto_aggro`，sapper∈{false,true}） | 差异格数 **0** |

> **C/D 的实测方式**：优先复用 `tests/playtest_driver.gd`（RADIAL 产品口径）逐波读数；如工程新增「精英波专项」场景更佳。**不改 playtest_driver 的既有断言**，仅读核心 HP / towers_disabled。

---

## 6. 回滚方式 & 影响面

### 6.1 回滚（三档，由小到大）

1. **参数退化（零代码）**：设 `G0 = 1.0`、`SLOPE = 0.0` → `sapper_dmg_mult(w) ≡ 3.0`（**全 w**）→ 等价于现行为。**这是最干净的 kill-switch**（无需改代码、无需改开关）。
2. **函数回退**：把 §3.1 的两处读点改回 `_MonsterData.SAPPER_DMG_MULT`（保留函数不删）。
3. **默认关**：本函数**本就只在 `elite_waves_enabled=true` 且 `tower_aggro_enabled=true` 时被消费** → 默认/MVP 路径**天然不触发**（见 §4）。
> 一行回滚性：删 `elite_waves_enabled = true`（boot.gd 产品注入）即退回无 Sapper 口径。

### 6.2 预估影响面

| 面 | 影响 |
|---|---|
| **生效条件** | 仅 `elite_waves_enabled ∧ tower_aggro_enabled`（= **RADIAL 产品口径**）；仅精英波 **{5,10,15,20}** |
| **W5** | 🔴 **逐位不变**（g=1） |
| **W10/15/20** | 对塔伤害 ×`g(w)`（恢复压力的落点） |
| **非精英波** | 零影响（无 Sapper） |
| **默认回归** | ✅ 全绿（§4 · §5.2/5.5） |
| **MC 门禁 / 扫描件**（详见 **§8** · 🧭 按脚本名引用） | 🔴 **变**（实机全开族）：`run_slice_aggro_golive_mc.gd` / `run_counterplay_mc.gd` / `run_realtime_counterplay_mc.gd`（全 elite+aggro on → W≥10 消费）+ 诊断件 `scan_sapper` / `scan_counterplay_player_arm` / `scan_counterplay_upper_ci`。✅ **不变**：radial8 / `run_slice_proto_elite_mc.gd`（aggro off）/ `test_suite_aggro_golive.gd`（等价/INFO 断言）。<br>🟢 **解耦后仅「翻参」提交触发**（落机制中性提交 `g≡1` → **全不变**，见 §7.1）。**复跑清单见 §8.2** |
| **守恒律 / PATH 金标 / 定稿值** | ✅ 不受影响（§4） |

---

## 7. 待拍板 → 🟢 答复登记（team-lead · 2026-10-12）

> 下表左=原问，右=**已答复**（team-lead 逐条批）；仅**梯度具体取值**待 MC 标定，其余已闭合。
> 🟢 **状态更新（2026-10-15 · supersede 批注）**：本节为 **2026-10-12 答复快照**，其状态项（「仅梯度取值待 MC 标定」/「明确标 PLACEHOLDER」/「v0.5 · 待加梯度」）**已于 Phase 6 · P2 提交② 全部定稿** —— 现况见 §1.3 与 **§7.2**。**历史记录不回改**（同 §8 序号口径处置）。

| # | 问题 | 🟢 答复 |
|---|---|---|
| 1 | **梯度参数** `G0/SLOPE/CAP` 取 §1.3 起步值？ | ✅ **批准起步值 1.5 / 0.10 / 3.0**，明确标 **PLACEHOLDER**（待 MC 标定后定稿） |
| 2 | **锚点语义**：W10 是否加压（`G0>1`）？ | ✅ **是** —— W10 也加压（`G0 = 1.5 > 1`），避免梯度在 W10 断一档 |
| 3 | **实现路线** (A) 预计算贯穿 / (B) 出生落值？ | 🟢 交**工程**定（两者位安全，见 §3.2） |
| 4 | **GDD §2.11 回写**由 design 做？ | ✅ **已由 design 完成** —— `wave-spawner.md` **v0.5**（§2.11「Sapper 已进实机 · 待加 W≥10 梯度」；原「Sapper 不进 MVP」作废） |
| 5 | **非默认扫描件复跑**由谁跑？ | 🟢 由**工程**跑（清单见 **§8.2** · 按解耦分 A/B 两组） |

### 7.1 🟢 机制 / 调参解耦（team-lead 确认 · 2026-10-13 · **本方案的执行口径**）

> 🔴 **为什么必须解耦**：§8 的纠正已证明 —— **只要 Sapper 口径变，CI 三条「实机全开」MC 门禁（`run_slice_aggro_golive_mc.gd` / `run_counterplay_mc.gd` / `run_realtime_counterplay_mc.gd`）的 `203` 基线必失效**（OFF/PRODUCT 两臂都消费 Sapper）。若「实现机制」与「迁移基线」绑死成一个提交，则一次改动同时含**行为变更 + 基线重签 + 平衡风险**三件事，回滚代价高、归因不清。→ **拆成两个可独立回滚的提交**，把风险锁死在"翻参"这一步。

| 提交 | 代码改动 | 参数 | CI 后果 | 回滚 |
|---|---|---|---|---|
| **① 落机制**（中性） | 常量 `SAPPER_DMG_MULT` → 函数 `sapper_dmg_mult(w)`（两处消费点共享 SSOT，见 §3） | `G0=1.0 / SLOPE=0.0` ⇒ **`g(w) ≡ 1.0`** | ✅ **逐位等价 → CI 三条「实机全开」MC 门禁（`run_slice_aggro_golive_mc` / `run_counterplay_mc` / `run_realtime_counterplay_mc`）保持绿、`203` 仍有效** | 独立撤该提交 |
| **② 翻参** | **零代码**（只改参数） | `G0=1.5 / SLOPE=0.10 / CAP=3.0`（= §1.3 定稿值 · ✅ **已拍板（用户 · 2026-10-15）并已落地**） | 🔴 `203` 失效 → 已**同步重签基线**（`203→205`，见 §7.2） | 独立退回中性值（见下） |

- 🔴 **中性值 = kill-switch**：`G0=1.0 / SLOPE=0.0` ⇒ `sapper_dmg_mult(w) ≡ SAPPER_DMG_MULT = 3.0`（**全 w**）⇒ 与现行**逐位等价**。它同时是**提交①的默认值**与**翻参后的一键回退位**。
- 🔴 **回滚（翻参之后）**：把 `G0 / SLOPE` 退回中性值即可 —— **零代码**（不撤任何代码、只改参数）→ 回到 §6.1 第 1 档（最干净的 kill-switch）。
- **验收门分工**：**提交①** 门 = `t1aggro` 全绿（尤其 `AC-T1-25A/B` 真身↔镜像逐位差 0）+ CI 三条 MC 门禁绿 + `203` **复现** → 见 **§8.2 组 A**（**不重签基线**）；**提交②** 门 = **§8.2 组 B**（**含基线重签**）。
- 🔴 **只有提交②需要用户拍板参数**；**提交①是纯重构 · 零行为变更 · 可先落地**。

### 7.2 🟢 提交② 落地记录（Phase 6 · 2026-10-15）

> 记账：登记**参数定稿 / 基线重签 / 效果证据 / 回滚**四项实际结果。**只登记、不改任何数值口径**（`SAPPER_DMG_MULT` 仍 = 3.0，`g` 公式同 §1.1 / §1.2）。

**① 参数定稿**
- `W0 = 10 / G0 = 1.5 / SLOPE = 0.10 / CAP = 3.0` ⇒ `g(10)=1.5`（W10 → mult **×4.5**）· `g(15)=2.0`（W15 → **×6.0**）· `g(20)=2.5`（W20 → **×7.5**，未触顶，CAP 仅兜底）。
- 🔴 **W5 精确保留**：`g(5) = 1.0` ⇒ `sapper_dmg_mult(5) = 3.0`（教学墙逐位不变 · §0 / §5.1 A1）。

**② 基线重签**（三「实机全开」MC 门禁）
- `BASE_B6_N_TAKEOFF`：**203 → 205**（`run_slice_aggro_golive_mc.gd` / `run_counterplay_mc.gd` / `run_realtime_counterplay_mc.gd`）。
- 🔴 **如实标注：`203 → 205` 是 rng 再分岔假象、非行为改善。** 依据 **quality-lead 前缀 hash 实验**：连续共享 rng 下 **W1–9 前缀 hash `1998867701 → 2549223616`（变了）**；per-run rng 对照 **`3485991772` 不变** → 分岔来自 `g≡1`→`g≠1` 改变了共享 rng 流的分支对齐，**并非 OFF 臂行为真的变好**。clean 对照方向为**预期微负**（PRICED `0.867 → 0.863`）。
- ✅ **未下调任何阈值**（`TH_TAKEOFF_B = 0.80` 不变）。

**③ 效果证据在逐波压力、不在聚合起飞率**
- PRICED 逐波：W10 `0.200 → 0.343` · W15 `0.037 → 0.130` · W20 `0.040 → 0.077`；**≥2 波有压 `0.030 → 0.117`**（对齐 §5.3 **C1**「≥2 波恢复压力」）。
- 三门禁主判 **B@6 = 0.850 / 0.823 / 0.823（全 ≥0.80，未破线）**；W10 **未成新硬墙**（对齐 §5.3 **C2**）。
- ⚠️ 聚合起飞率**不进反微降**（见 ② clean 对照）→ **判据以逐波压力为准**（聚合量被 rng 分岔污染，不宜作效果主指标）。

**④ 回滚**
- `G0 / SLOPE` 退回中性 `1.0 / 0.0` ⇒ `sapper_dmg_mult(w) ≡ 3.0` ⇒ **零代码** kill-switch（= §6.1 第 1 档 / §7.1）。

---

## 8. 对既有 MC / 门禁的连带影响〔team-lead 增补〕

> 🧭 **序号口径（2026-10-13 更新）**：本文原按 CI **步号**引用。因 `ci.yml` 插入 2 个音频硬门禁（`音频资产 lint` / `音频框架回归断言 §7`，位置在「默认回归」之后、「radial8」之前），**硬门禁序列由 7 → 9、序号整体 +2**。⇒ **本文以下已全部改为按脚本名引用**；若仍需序号，**以 `ci.yml` 现序为准**（**插步会整体再偏移，优先按脚本名识别**）。
> **现序对照（1-indexed · 供对照，非引用键）**：① 默认回归`run_tests.gd` ｜ ② 音频资产 lint〔新〕 ｜ ③ 音频框架回归断言§7〔新〕 ｜ ④ **radial8** ｜ ⑤ **`aggro_golive`** ｜ ⑥ **`run_slice_proto_elite_mc.gd`** ｜ ⑦ **`run_slice_aggro_golive_mc.gd`** ｜ ⑧ **`run_counterplay_mc.gd`** ｜ ⑨ **`run_realtime_counterplay_mc.gd`**。

> 🔴 **一句话**：P2 **翻参后**，**CI 三条「实机全开族」MC 门禁（`run_slice_aggro_golive_mc.gd` / `run_counterplay_mc.gd` / `run_realtime_counterplay_mc.gd`）会变红**，分**两类**原因：
> 🟢 **解耦后仅「翻参」提交触发** —— 「落机制」中性提交取 `G0=1.0/SLOPE=0.0` ⇒ `g≡1` ⇒ **三门禁全不变、`203` 有效**（见 **§7.1**）。本节的"会变"**特指翻参提交**。
> **(a) 硬编码 OFF 基线 `203` 陈旧** —— 需**重签该基线号**（3 个脚本；**非**下调阈值）；
> **(b) 主判 `B@6 ≥ 0.80` 可能破线** —— Sapper 只增威胁 → 起飞率**倾向 ↓**；若破线 → **禁下调阈值 · 立即上报用户**。
>
> 🔴 **重要纠正**（复核代码后）：team-lead 提及「OFF 臂走默认、`elite=false` → 不受影响」——**经验证不成立**。这三条 MC 门禁（`run_slice_aggro_golive_mc` / `run_counterplay_mc` / `run_realtime_counterplay_mc`）的 OFF 臂**一律设 `elite_waves_enabled=true`**（`run_loop_proto_aggro.run(…, proto=true, elite=true, aggro=true, …)`；R-1 的 `wd.elite_waves_enabled=true` 与其 `combat_revive` 无关）→ **同一脚本的 OFF / PRODUCT 两臂都消费 Sapper** → **OFF 臂读数也变** → 硬编码 `203` **自检 / 守门必失效**。

### 8.1 逐产物清单（会变 / 不变 + 消费波次区间）

| # | 产物（脚本）〔🧭 引用键〕 | CI 步〔现序·会漂移〕 | 消费 Sapper？ | 消费波次区间 | P2 后 | 原因 |
|---|---|---|---|---|---|---|
| 1 | `run_tests.gd` 默认回归（slice1–8 + t1aggro） | 现序 1 | 部分 | t1aggro **W5/W4**（+整局 W1–20 等价） | ✅ **不变** | slice2/5 **无 Sapper 杀伤**（无 aggro）；t1aggro 断言全在 **W5**（g=1）+ 整局 AC-T1-25B 为 **runner 间等价** |
| 2 | radial8 聚合闸门（geo8/expo/bulwark8/panorama8/attrition8） | 现序 4 | 预期否 | — | ✅ **预期不变** | 这些件**不启用 elite/aggro** → 无 Sapper 杀伤（复跑确认） |
| 3 | `test_suite_aggro_golive.gd`（`-- aggro_golive`） | 现序 5 | **是** | `_cross_sapper` **W5/W10** | ✅ **不变** | 断言 = **真身↔镜像等价**（`_cmp_rt_wave` diff==0）；`_info_registry_old_mirror` 为 **INFO 不判等**；SSOT 共享 → 两边**同步变** → 仍 0 差异 |
| 4 | `run_slice_proto_elite_mc.gd` 实机口径 MC | 现序 6 | **否** | — | ✅ **不变** | **`tower_aggro_enabled=false`** → Sapper 只标记**不杀伤** → 函数不被消费；B≥0.80 门禁**保持绿** |
| 5 | `run_slice_aggro_golive_mc.gd` 实机全开 MC | 现序 7 | **是** | **三档全** W5/10/15/20 | 🔴 **必变** | 全 elite+aggro on → 自检 `OFF B@6==203` 失效 + 主判 `PRICED B@6≥0.80` 可能破 |
| 6 | `run_counterplay_mc.gd` C-8 门禁 | 现序 8 | **是** | MODES={0,1,2,9} **全** W5/10/15/20 | 🔴 **必变** | 全 elite+aggro on → 自检 `203` 失效 + 主判 `REVIVE(9) B@6≥0.80` 可能破 |
| 7 | `run_realtime_counterplay_mc.gd` R-1 门禁 | 现序 9 | **是** | **两臂全** W5/10/15/20 | 🔴 **必变** | OFF(=revive false) 与 PRODUCT(=true) **均** elite+aggro on → 守门 `OFF B@6==203` 失效 + 主判 `PRODUCT B@6≥0.80` 可能破 |
| 8 | `scan_sapper.gd` 六槽 PATH Sapper 诊断 | 诊断件 | **是** | W5/10/15/20 | 🔴 **必变** | `RunLoopAggro` sapper=true → ΔA/ΔB 读数变 |
| 9 | `scan_counterplay_player_arm.gd` C-9 玩家反制臂 | 诊断件 | **是** | W5/10/15/20 | 🔴 **必变** | RADIAL 八槽 · `run_loop_proto_aggro` 全开 → T0–T4 区间变 |
| 10 | `scan_counterplay_upper_ci.gd` C-9 上限 CI（N=1000） | 诊断件 | **是** | W5/10/15/20 | 🔴 **必变** | 逐字复刻 C-9 → T0/T1 点估计 + CI 变 |

> **不变（1–4）的根因统一为一条**：**Sapper 只在「`elite_waves_enabled` ∧ `tower_aggro_enabled`」下才产生杀伤** → 只要放大器不生成（`run_tests` 默认回归 / `-- radial8`）或 `aggro=false`（`run_slice_proto_elite_mc.gd`），或断言为**等价/INFO**（`run_tests` 内 t1aggro / `-- aggro_golive`），P2 就不改变读数。

### 8.2 复跑清单（工程按此执行 · **按 §7.1 的两个提交分两组 · 勿合并**）

> 🔴 **前置**：本清单按 §7.1 拆成 **组 A（落机制 · 中性）** 与 **组 B（翻参）**。**组 A 不触基线、组 B 才触基线** —— 必须分两次跑、分两次提交。

#### 组 A · 「落机制」中性提交（`G0=1.0/SLOPE=0.0` ⇒ `g≡1` · **预期全绿 · `203` 有效**）

| 序 | 动作 | 期望 | 不达标处置 |
|---|---|---|---|
| A1 | 跑 `run_tests.gd`（默认回归 · 无参） | 全绿 | 🔴 红 = SSOT 未共享（漏改一处消费点）→ 修实现 |
| A2 | 跑 `-- radial8` | 全绿 | 同上 |
| A3 | 跑 `-- aggro_golive`（`test_suite_aggro_golive.gd`） | 全绿 | 🔴 红 = 实时/镜像 sapper 不同源 → 修实现 |
| A4 | 跑 `run_slice_proto_elite_mc.gd`（实机口径 MC · aggro off） | B≥0.80（**不变**） | 若变 → aggro 未关 → 查脚本 |
| A5 | 跑 **三条「实机全开」MC 门禁**（`run_slice_aggro_golive_mc.gd` / `run_counterplay_mc.gd` / `run_realtime_counterplay_mc.gd`） | 🔴 **`203` 必须复现、B@6 与旧逐位同** | 任一红/漂 → **中性值不中性** → 修实现（🔴 **勿重签基线**） |

> ✅ **组 A 通过 = 「机制落地、行为零变更」得证** —— 这正是 §7.1 拆分的意义：把「接线正确性」与「平衡决策」解耦。**组 A 全绿后才允许进入组 B。**

#### 组 B · 「翻参」提交（`G0=1.5/SLOPE=0.10/CAP=3.0` · **触基线**）

| 序 | 动作 | 期望 | 不达标处置 |
|---|---|---|---|
| B1 | 跑 `run_slice_aggro_golive_mc.gd`（实机全开 MC） | 记录**新** OFF 基线 + PRICED B@6 | 主判 <0.80 → **上报用户** |
| B2 | 跑 `run_counterplay_mc.gd`（C-8 门禁） | 记录**新** OFF 基线 + REVIVE B@6 | 主判 <0.80 → **上报用户** |
| B3 | 跑 `run_realtime_counterplay_mc.gd`（R-1 实时版门禁） | 记录**新** OFF 基线 + PRODUCT B@6 | 主判 <0.80 → **上报用户** |
| B4 | 跑三个诊断件（`scan_sapper.gd` / `scan_counterplay_player_arm.gd` / `scan_counterplay_upper_ci.gd`） | 记录新读数（更新 C-9 / Sapper Δ 结论） | 仅供判读，无门禁 |
| B5 | 复跑 **组 A A1–A4** | 仍全绿 | 红 = 翻参破坏非精英路径 → 修 |

**基线重签（组 B 专属）**：B1/B2/B3 得到的**新 OFF 基线号**回填 `BASE_B6_N_TAKEOFF`（**3 个脚本**）→ 与**翻参同一提交**进 CI 才能复绿。🔴 **组 A 不重签。**
**回滚（组 B 之后）**：把 `G0/SLOPE` 退回中性值 → **零代码**、回到组 A 状态（见 §7.1 / §6.1）。
**红线**：`≥0.80` 是平衡红线 → **禁下调**；破线**只许上报用户**（唯一被授权改的是 P2 自身的 `G0/SLOPE/CAP`，且须用户拍板）。

### 8.3 CI 语义提醒

- CI `on: push` 已 `paths-ignore: docs/**` → **本规格/GDD 的文档改动不触发 CI**；**只有工程代码改动**（`monster_data.gd` + 两处调用点 + 3 个基线号）才触发。
- **建议（解耦后）**：**组 A** 本地跑 A1–A5 → 全绿即提交（🔴 **不重签基线**）；**组 B** 本地跑 B1–B5 取新基线 → **与翻参同批提交**（含 3 个 `BASE_B6_N_TAKEOFF` 回填）→ 再 push，避免 CI 因「基线陈旧」假红。
- `203` 自检 = **「接线零扰动」证据**（repair/revive 不动）；**组 A**（中性 `g≡1`）→ `203` **应逐位复现**（A5 判据）；**组 B 翻参**改了 Sapper 口径 → `203` **本应改变** → 属**预期基线迁移**、**非回归**。CI 不区分 → **仅组 B 须同步重签**。

---

## 9. 证据 / 引用（file:line）

- **Sapper 常量**：`scripts/data/monster_data.gd:46-50`（`SAPPER_DMG_MULT := 3.0` · 标注「T1 诊断域 · MVP 恒 false」）。
- **消费点**：`scripts/gameplay/wave_director.gd:519-527`（实时 `_damage_tower`）· `scripts/engine/wave_sim_aggro.gd:816-825`（批处理）· `scripts/engine/wave_sim_proto_aggro.gd:220`（复用批处理 helper）。
- **Sapper 生成**：`wave_director.gd:741-751`（`_spawn_one`）· `wave_sim_aggro.gd:743-754`（`_build_sapper_flags`，均以 `w` 驱动 `elite_indices`）。
- **默认回归构成**：`tests/run_tests.gd:25-26,155-156`（默认 = slice1~8 + t1aggro）· `tests/test_suite_t1_aggro.gd:629-732`（W5/W4 Sapper 断言）· `:1322-1351`（AC-T1-25 A/B 逐位守护）。
- **金标 MC**：`tests/test_suite_slice2.gd`（B 起飞率 91.3% / 274·300 / 20 局 trace，经 `run_loop` 无 aggro）。
- **GDD**：`design/gdd/wave-spawner.md` §2.5.4（Elite 守恒）· §2.11（Sapper 破塔者 · 🟢 **v0.6** 口径回写：已进实机 + **已含 W≥10 梯度 · P2 提交② 落地**）。
- **上游**：`docs/phase6/balance-eval.md` §2.2 · `docs/phase6/balance-eval-verify.md` §3.3/§4.2/§4.3。

---

## 10. 连带注记（非 P2-Sapper 范围 · 手感/口径 · 2026-10-13）

> 记账用：VFX 视觉复核（`docs/phase6/vfx-visual-review.md` §8）暴露的 2 条**非红线**问题落在**手感 / 口径**域，**与 P2-Sapper 无关**，但**下游可能影响本规格的"密度/手感"复验口径**，故在此挂链。**裁定全文见 `docs/phase6/vfx-art-spec.md` §10。**

| # | 问题 | 与 P2 关系 | 裁定落点 | 触及红线 |
|---|---|---|---|---|
| **1** | **P2「雪崩」密度未饱和 + 弹体汇流**（全塔 h≈21 峰值 ~17） | **同名不同物**：此处 P2 = **美术圣经 §0「雪崩」支柱（视觉密度）**，**非**本规格的 **P2-Sapper 域**（勿混） | `vfx-art-spec.md` §10.1（判据：W≥13 ∧ 同屏怪≥12 → 弹体峰值 ≥120 且落点 ≥3） | 🔴 **仅"玩法层集火口径"W-A1~A4 触红线**；**VFX 密度/靶选择杠杆均无红线、且对雪崩足够** → **无需动本规格任何值** |
| **2** | **超杀档 tier4 实践不可达**（`escalate` 需"击杀帧 ≥60%·hp_max"） | 无关（纯 VFX 手感） | `vfx-art-spec.md` §10.2（推荐 (c) 纯表现层"爆发击杀"触发） | 🟡 (b) 改阈值触「不改定稿数值」； (c) 纯表现层变体**不触**（加键则触只读契约）→ **两者均须用户拍板** |

> 🔴 **对本规格的影响 = 无**：P2-Sapper 只作用于 `SAPPER_DMG_MULT × g(w)`（Sapper 域、W≥10），**既不碰投射物密度、也不碰伤害数字分档** → 本规格 §1–§9 全部不变。
