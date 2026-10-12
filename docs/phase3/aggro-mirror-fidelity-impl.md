# 仇恨镜像 ② 相位保真度修复 · 实现记录

- **日期**：2026-10-12
- **任务**：T-DEBT-01（工程 lead · 程基岩）· 第五刀 D6 裁定「登记债务」的兑现
- **项目**：《守核 Corebound》· Godot 4.7.2-stable · `D:/roguedemo`
- **范围**：**只修镜像保真度**，零数值 / 零阈值 / 零金标本改动

---

## §1 结论

`scripts/engine/wave_sim_aggro.gd` 的 ② 集火相位**丢弃了稳定排序的返回值**（`_stable_sort_by_time(monsters)`），
而该函数返回**新数组**（非原地）→ 该调用**恒 no-op**，导致镜像 ② 相位「距核心最近优先」**从未生效**，
**不忠实真身** `WaveDirector._substep:365 _stable_sort_by_remain()`（原地排序 = assign 语义）。

本次修为 **assign 写法**（一行），镜像现与真身**逐位一致**。

- 🔴 **未触发任何门禁阈值变化**（radial8 全绿，判据裕度反而增大）→ **不触发红线 #6 的"停下上报"**。
- 🔴 **无任何既有断言期望值需重钉**（T1 段 216 断言逐位不变）。
- 🟢 新增 1 条**判别性守护** `AC-T1-25`（修复前 FAIL / 修复后 PASS，见 §5）。

---

## §2 改动

| 文件 | 改动 | 性质 |
|---|---|---|
| `scripts/engine/wave_sim_aggro.gd` | L189–193：`_stable_sort_by_time(monsters)` → `monsters = _stable_sort_by_time(monsters)` + 4 行「2026-10-12 保真度修复」注释 | 🔴 一行语义修复 |
| `tests/test_suite_t1_aggro.gd` | +5 行 import（`_Geo8`/`_SpaceModel`/`_RunLoopAggro`/`_RunLoopPA`/`_PyRandom`）＋ `AC-T1-25` 守护（4 断言）＋ 注册进 `run_all()` | 🟢 守护 |
| `tests/test_suite_aggro_golive.gd` | 登记段「旧镜像 ② 为 no-op 的既有缺陷」→「2026-10-12 已修复」（**改标签/注释，不改判等逻辑**；仍 56/56） | 🟢 同步去过期 |

**对齐依据**（同族既有正确写法）：`wave_sim.gd:155`、`wave_sim_proto.gd:89`、`wave_sim_proto_aggro.gd:162`
均为 `monsters = _stable_sort_by_time(monsters)`（assign）；真身 `wave_director.gd:365` 为
`_stable_sort_by_remain()`（**原地排序**，等价 assign 语义）。

> **缺陷为何只在整局显形**：无 aggro 冻结时「插入序 ≡ t_remain 升序」（怪以同一 `t_reach` 出生、
> 后到者 t_remain 最大）→ assign 为恒等变换（与 no-op 一致）。一旦 aggro 冻结某些怪的 t_remain
> （AggroTower 停下不漏怪），插入序不再升序 → 分歧显现。**单波恒等、整局演化 build 才分化**（见 §5）。

---

## §3 before → after 读数表

### 3.1 默认回归·九段聚合（金标本 PATH 口径）

| 段 | before | after | Δ |
|---|---|---|---|
| slice1 | 222 / 0 | 222 / 0 | 0 |
| slice2 | 2228 / 0 | 2228 / 0 | 0 |
| slice3 | 142 / 0 | 142 / 0 | 0 |
| slice4 | 123 / 0 | 123 / 0 | 0 |
| slice5 | 302 / 0 | 302 / 0 | 0 |
| slice6 | 41 / 0 | 41 / 0 | 0 |
| slice7 | 31 / 0 | 31 / 0 | 0 |
| slice8 | 92 / 0 | 92 / 0 | 0 |
| **t1aggro** | **216 / 0** | **220 / 0** | **+4（新增守护）** |

🔴 **除 T1 段外 8 段逐位不变**（金标本零扰动核对通过）。exit code 全 0。
🔴 **T1 段 216 条既有断言 before/after 逐位相同**（diff 仅进程退出时 RID 泄漏噪声，非测试内容）。

### 3.2 radial8 聚合闸门（`run_slice_attrition8.gd` · **真闸门** · 300 局 A/B）

| 指标 | before | after | 门禁 |
|---|---|---|---|
| A 成型期 W6–12 塔死均值 | 0.380 | **0.407** | T-B′ ≤4 PASS |
| B 全程塔死 | 0.000 | 0.000 | T-D′ =0 PASS |
| B 雪崩期 W13–20 塔死 | 0.000 | 0.000 | T-C′ ≈0 PASS |
| 起飞率 takeoff B / A | 0.913 / 0.597 | 0.913 / **0.603** | B ≥0.80 PASS |
| **T-A1** hit（TH 0.12） | 0.1900（+3.09 SE） | **0.2033（+3.59 SE）** | **PASS** |
| **T-A2** hit_fail（TH 0.30 · n_fail） | 0.4711（+3.77 SE · n=121） | **0.5126（+4.64 SE · n=119）** | **PASS** |
| T-D″ 阳性对照（3 seed 累计） | 3 | 3 | PASS |
| V-0-4a B MC 中位起飞波 | 14 | 14 | PASS |
| V-0-5b MC 均值 W20 B/A | 0.3937 | 0.3938 | PASS |
| V-0-4b B 确定性起飞波 | 11 | 11 | PASS |
| V-0-5a 确定性 W20 B/A | 0.6217 | 0.6217 | PASS |
| **汇总失败项** | **0** | **0** | ✅ |

🔴 **阈值一字未动**（`TH_HIT=0.12` / `TH_HIT_FAIL=0.30` / 0.80 / `V0_*` 全冻结）。读数小漂移但**全部 PASS，
且 T-A1/T-A2 裕度反而增大** → **无门禁破线**。

### 3.3 radial8 其他闸门成员

| 脚本 | before | after | 依赖 aggro？ |
|---|---|---|---|
| `run_slice_bulwark8.gd`（闸门） | 4 PASS / 0 FAIL | **4 PASS / 0 FAIL（逐位相同）** | 仅直调 `_relocate_carry_to_safe`（无战斗） |
| `run_slice_geo8_mc.gd`（**INFO 诊断**，恒 quit 0） | 见下 | 见下（读数漂移，无闸门） | 是 |
| `run_slice_geo8_smoke/golden/expo/panorama8` | — | — | **否**（grep 证：不 import aggro → 不受影响） |

`geo8_mc`（INFO，无闸门）读数漂移示例（起飞率）：
`PATH A八槽 0.340→0.317` · `PATH B六槽 0.813→0.817` · `PATH B八槽 0.873→0.870` ·
`RADIAL A六槽 0.607→0.567` · `RADIAL A八槽 0.550→0.547` · `RADIAL B六槽 0.900→0.900` · `RADIAL B八槽 0.870→0.870`。
脚本自身「Δ 温和（≥ -0.05）」判读在 before/after 均成立。

### 3.4 `-- aggro_golive`（第五刀退化守护 · 独立入口）

| 指标 | before | after |
|---|---|---|
| 退化守护汇总 | 56 / 0 | 56 / 0 |
| 整局 run-loop 逐位差异（A） | 0 | 0 |
| 整局 run-loop 逐位差异（B） | **4** | **0** |
| 整局 run-loop 逐位差异（B + Sapper） | **4** | **0** |
| 逐波 registry（真身↔旧 aggro，全部场景） | 0 | 0 |

> 逐波 registry（geo6 W3/W5/W8 ±Sapper）**before 亦为 0** —— 印证「② no-op 只在整局演化 build 下显形」。

### 3.5 诊断 scan 工具（**无闸门 · INFO**，N=60 快速抽样）

| 工具 | 组 | before | after | Δ |
|---|---|---|---|---|
| `scan_sapper.gd` | A 无 Sapper | 0.300 | 0.300 | 0 |
| | A 有 Sapper | 0.283 | 0.283 | 0 |
| | B 无 Sapper | 0.850 | 0.850 | 0 |
| | **B 有 Sapper** | **0.783** | **0.733** | **-0.050** |
| | Δ起飞率 B（判读） | **-0.067**（温和档） | **-0.117**（**中等档**） | 档位迁移 |
| `scan_bulwark.gd` | A 无保护 / 隐身 / 理想肉盾 / B 无保护 | 0.300 / 0.483 / 0.483 / 0.850 | 与 before 逐位相同 | 0 |
| `scan_attrition.gd`（PATH B · 粗扫 N=60 步长 1.0） | **全 16→8 点表** | — | — | **逐位相同**（含定稿点 ATTRITION=1.50：T-A 1.033 / T-B 0.0 / T-C 0.25 / 起飞B 0.85 / 起飞A 0.3 / 存活B 0.917，✅PASS） |

🟡 **设计相关读数迁移（`scan_sapper` 的 Sapper 惩罚 · B 路径 Δ起飞率）**：
- N=60 快样：`-0.067（温和档）→ -0.117（中等档）` —— 🟡 但 N=60 欠功效，与 `-0.10` 统计不可分。
- 🔴 **N=300 复测（默认档 · 忠实镜头 · 2026-10-12 补跑）**：A 无/有 0.277/0.270 · B 无/有 0.817/0.740
  → **ΔA = -0.007 · ΔB = -0.077 → 回落「温和档」（ΔB ≥ -0.10）**。
  95% CI（独立两比例）：ΔB ≈ [-0.143, -0.010]（SE≈0.0338）· ΔA ≈ [-0.078, +0.065]。
  → **N=60 的「中等档」确认为小样本假象**；按 `scan_sapper.gd` 预登记处置 = **保留 ×3 不动、本案关闭**（不进入兜底处置 D）。
- 仅存**定性翻转**（A 更扛：ΔA -0.007 > ΔB -0.077+0.05 = -0.027）在 N=300 仍稳健（见 `docs/phase3/sapper-balance-review.md` §3.3）。
- 🔴 **口径**：`scan_sapper.gd` **不设 `SpaceModel.mode` / `n_slots`**（默认 **PATH + 六槽**）→ 上列全部读数为**六槽 PATH**（非 RADIAL 八槽）。
- 🔴 **无闸门破线**（诊断件恒 quit 0）；`SAPPER_DMG_MULT` 一字未动。设计侧裁定见文策渊 `docs/phase3/sapper-balance-review.md`（T-DEBT-01-DESIGN）。
🔴 A 路径扫描（`scan_bulwark` 3 组 + `scan_attrition` 全表）**逐位不变**，与「PATH 口径 A 路径 0 格分歧」一致。

### 3.6 复现命令

```bash
G="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path D:/roguedemo --script res://tests/run_tests.gd                 # 九段（含新守护）
"$G" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8      # radial8 聚合闸门
"$G" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- aggro_golive # 第五刀退化守护
"$G" --headless --path D:/roguedemo --script res://tests/run_slice_attrition8.gd      # 八槽 V-1′ 判据
```
⚠️ Godot 对 `.godot/` 有实例锁 → **串行**跑，禁并行多实例。

---

## §4 受影响断言清单

| 类别 | 处置 |
|---|---|
| `test_suite_t1_aggro.gd`（216 断言） | 🔴 **无需重钉**：修复后逐位不变（该段全部为单波 / 单怪 / 阈值型场景，sort 顺序等价） |
| `run_slice_attrition8.gd` 判据（T-A1/T-A2/T-D″/V-0′-④⑤） | 🔴 **阈值冻结、无需重钉**：判据为「实测 vs 冻结阈值」型；实测漂移但全 PASS，裕度增大 |
| `run_slice_bulwark8.gd`（4 断言） | 🔴 逐位不变 |
| `-- aggro_golive` 登记 INFO | 🟢 **标签同步**（「既有缺陷」→「已修复」）；**非判等**，不改判据 |

> 🔴 **结论：本次修复未使任何**「硬编码期望值」**失效** → **无断言需重钉**。
> 因此本刀**未添加**「corrected after mirror-fidelity fix」标注（无对象可标）。

---

## §5 保真度自证（新增守护 `AC-T1-25`）

**目标**：修复后 `wave_sim_aggro` ② 相位逐位忠实真身 `WaveDirector._substep`（对标 `-- aggro_golive` 写法）。

- **(A) 逐波**（wave-level · 恒等不变式）：同确定性初值造同一 player，一次喂真身 `WaveDirector.run_to_end`、
  一次喂 `wave_sim_aggro`，逐位比 `kills/leaked/scrap_earned/dps/towers_disabled`
  （PATH/RADIAL × geo6/geo8 × A/B × W5/W8 × Sapper 关/开）。🟡 单波层面**修复前后皆 0**（锁死不变式）。
- **(B) 整局**（run-level · 🔴 **判别性闸门**）：同 seed（20260930）跑 40 局，`run_loop_aggro`（消费本镜像）
  逐波逐位 == `run_loop_proto_aggro`（proto/elite OFF · ② 恒 assign，且由 `-- aggro_golive` 守护② 已证 == 真身）。
  比 `kills/leaked/core_hp_raw/eff_dps_raw/ratio_raw/total_hp_raw/income_raw/hp_each_raw/n`。

**判别性证据（撤修复 → 复现缺陷）**：

| 状态 | AC-T1-25B（B） | AC-T1-25B（B+Sapper） | T1 汇总 | exit |
|---|---|---|---|---|
| **修复前**（撤 assign） | **4（FAIL）** | **4（FAIL）** | 218 / **2** | **1** |
| **修复后**（assign） | **0（PASS）** | **0（PASS）** | 220 / 0 | 0 |

🔴 守护**确为判别性**：撤掉修复即翻红（与文档登记的「B 路径 4 格 / B+Sapper 4 格」逐位吻合）。

---

## §6 红线核对

| # | 红线 | 核对 |
|---|---|---|
| 1 | 禁止改动任何定稿数值 / 判据阈值 | ✅ 仅改排序 assign；`ATTRITION`/`KAPPA_R`/`KR_FINAL`/`AGGRO_R`/0.80/radial8 阈值**一字未动**（git diff 仅 3 文件，见 §7） |
| 2 | 金标本零扰动（九段除 T1 外逐位不变） | ✅ `222/2228/142/123/302/41/31/92` 逐位不变 |
| 3 | 不改 `wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` / `wave_sim_proto_aggro.gd` | ✅ `git status` 只列 3 个已改文件，无此四者 |
| 4 | 不 git commit | ✅ 未提交（改动留在工作区） |
| 5 | 临时脚本用完即删（`**/_tmp_*` 零命中） | ✅ 探针 `tests/_tmp_find_div.gd` 已删，`ls tests/_tmp_*` 零命中 |
| 6 | 门禁阈值若看似需下调 → 停下上报 | ✅ **无门禁变化**（radial8 全绿），不触发 |

---

## §7 遗留 / 待主理人裁决

1. ✅ **已同步（2026-10-12 · 用户放行「全部回写」）**：`scripts/engine/wave_sim_proto_aggro.gd` 头部注释 L20–27 已更新为「`wave_sim_aggro` ② **2026-10-12 已修复**（assign）→ 与真身/本文件一致」（**纯注释，零逻辑**）。
2. 🟡 **`docs/phase3/tower-aggro-golive-impl.md` §4-1 的债务登记现已兑现**：该处建议「后续单独立 ADR 修
   `wave_sim_aggro` ② + 重扫 T1 定稿」。**本刀即该 ADR 的执行**。该文档 §4-1 的「T1 既有 agg 定稿读数」
   （A 无保护 0.393 / A 保主力塔 0.583 / A 理想肉盾 0.623 / B 0.883 等）**来源于旧（不忠实）镜像** →
   权威口径应改用修复后读数（本刀 §3 已重新登记门禁读数）。
3. 🟢 **T1 段断言数 216 → 220**（新增 4 条守护）。此为**唯一**默认回归读数变化（红线 #2 已明确 T1 段除外）。
4. ✅ **已闭环 · 设计侧复核（Sapper，无门禁破线）**：文策渊已完成复核（`docs/phase3/sapper-balance-review.md`，T-DEBT-01-DESIGN）；工程侧按其**预登记处置 A** 在忠实镜头补跑 `scan_sapper` **N=300** → **ΔB = -0.077（温和档，≥ -0.10）→ 本案关闭、`×3` 不动**（N=60 的「中等档」= 小样本假象）。仅「A 更扛 Sapper」定性翻转在 N=300 仍成立。详见本刀 §3.5。
5. 🟡 **后续项（不阻塞，待排期）· Sapper「玩家反制臂」缺失**：`scan_sapper` 只测**金标本 AI 地板**（纯 DPS 贪心，不玩保塔）；**玩家反制臂**（对标 `scan_bulwark` 的 `protect_core`/`bulwark` 臂）仍缺 → `-0.077` 只是 worst case，玩家可应对空间**存在但未测**。文策渊已在其备忘 §4-处置 C 登记；工程侧在此同步登记，作为 T1 试玩/后续扫参的候选诊断项（🔴 非本次交付，未实现）。
6. ✅ **独立复核（PASS）· 回挂指针**：本刀修复的独立复核 → `docs/phase3/aggro-mirror-fidelity-verify.md`（quality-lead）；Sapper 设计侧裁定 → `docs/phase3/sapper-balance-review.md`（design-strategist，T-DEBT-01-DESIGN）。
