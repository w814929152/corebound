# 仇恨镜像 ② 相位保真度修复 · 独立复核报告

- **日期**：2026-10-12
- **任务**：T-DEBT-01-VERIFY（质量 lead · 严守真）
- **被验**：T-DEBT-01（工程 lead · 程基岩）改动，**留在工作区、未提交**
- **环境**：Godot 4.7.2-stable · `D:/roguedemo` · headless · 串行跑
- **复核立场**：🔴 **独立复核 —— 只验不修**；用新鲜视角独立跑、独立读码，不复述工程结论

## §0 一句话判定

**PASS** —— 修复成立且**判别性守护确实能抓到该缺陷**；零阈值改动、零残留、零污染。

---

## §1 读码确认（语义对齐是否成立）

| 项 | 证据 | 结论 |
|---|---|---|
| 镜像 L193 现为 assign | `wave_sim_aggro.gd:193` = `monsters = _stable_sort_by_time(monsters)` | ✅ |
| `_stable_sort_by_time` 返回**新数组** | 同文件 L853-864：`var out: Array = arr.duplicate()` … `return out`（非原地） | ✅ |
| 旧写法确为 no-op | 丢弃返回值 → `monsters` 永不重排 → ② 相位「距核心最近优先」从未生效 | ✅ |
| 真身 `_stable_sort_by_remain` 为**原地** | `wave_director.gd:747` `func …() -> void`，直接原地排 `monsters` 成员；调用处 L365 `_stable_sort_by_remain()`（无 assign） | ✅ |
| 「语义对齐」成立 | 真身「原地排序」≡ 镜像「assign 回写」；修复后一致 | ✅ |
| 同族既有正确写法（旁证） | `wave_sim.gd:155` / `wave_sim_proto.gd:89` / `wave_sim_proto_aggro.gd:162` 三处**均为** `monsters = _stable_sort_by_time(...)`（assign） | ✅ 修复后写法与同族一致 |

> 结论：工程侧「一行语义修复」的描述**与代码事实相符**。

---

## §2 默认回归（九段聚合）

命令：`"$G" --headless --path D:/roguedemo --script res://tests/run_tests.gd` → 日志 `/tmp/t01_default.log`
**EXIT=0** · `[FAIL]` 计数 = **0** · `[OK]` 计数 = 8

| 段 | 实测 | 期望（before） | 判定 |
|---|---|---|---|
| slice1 | 222 / 0 | 222 / 0 | ✅ 逐位不变 |
| slice2 | 2228 / 0 | 2228 / 0 | ✅ 逐位不变 |
| slice3 | 142 / 0 | 142 / 0 | ✅ 逐位不变 |
| slice4 | 123 / 0 | 123 / 0 | ✅ 逐位不变 |
| slice5 | 302 / 0 | 302 / 0 | ✅ 逐位不变 |
| slice6 | 41 / 0 | 41 / 0 | ✅ 逐位不变 |
| slice7 | 31 / 0 | 31 / 0 | ✅ 逐位不变 |
| slice8 | PASS=92 FAIL=0 | 92 / 0 | ✅ 逐位不变 |
| **t1aggro** | **220 / 0** | **220 / 0**（216 旧 + 4 新守护） | ✅ |

🔴 **除 T1 段外 8 段逐位不变**（金标本零扰动成立）。

### T1 段新增守护 `AC-T1-25`（4 断言）实测

```
[PASS] AC-T1-25A 逐波 真身↔镜像 差异（kills/leaked/scrap/dps/towers_disabled）  got=0 want=0
[PASS] AC-T1-25A 场景有效性：确曾触发 aggro 杀伤（towers_disabled>0，非空转）  got=true want=true
[PASS] AC-T1-25B 整局 B 逐波逐位差异格数（aggro vs proto_aggro proto/elite OFF）  got=0 want=0
[PASS] AC-T1-25B 整局 B+Sapper 逐波逐位差异格数（aggro vs proto_aggro proto/elite OFF）  got=0 want=0
```
→ **4/4 PASS**。

---

## §3 radial8 聚合闸门

命令：`… -- radial8` → 日志 `/tmp/t01_radial8.log`
**EXIT=0** · **radial8 结论：PASS（exit 0）** · 8 成员全 PASS

```
[PASS] geo8(套件)        exit=0      35 ms
[PASS] radial(套件)      exit=0     913 ms
[PASS] geo8_smoke        exit=0     798 ms
[PASS] geo8_golden       exit=0     512 ms
[PASS] expo              exit=0     399 ms
[PASS] bulwark8          exit=0     521 ms
[PASS] panorama8         exit=0     488 ms
[PASS] attrition8        exit=0  119634 ms
```

真闸门关键读数（attrition8 · 300 局 A/B）：

| 判据 | 实测 | 门禁 | 判定 |
|---|---|---|---|
| T-B′ A 成型期塔死均值 | 0.407 | ≤ 4.0 | ✅ PASS |
| T-C′ B 雪崩期塔死 | 0.000 | ≈ 0 | ✅ PASS |
| T-D′ B 全程塔死 | 0.000 | = 0 | ✅ PASS |
| takeoff_rate B | 0.913 | ≥ 0.80 | ✅ PASS |
| T-A1 hit | 0.2033 | TH 0.12（+3.59 SE） | ✅ PASS |
| T-A2 hit_fail | 0.5126 | TH 0.30（+4.64 SE） | ✅ PASS |

→ 与 impl 文档 §3.2 读数逐位吻合；**无门禁破线**。

---

## §4 `-- aggro_golive` 第五刀退化守护

命令：`… -- aggro_golive` → 日志 `/tmp/t01_golive.log`
**EXIT=0** · **汇总：通过 56 项 / 失败 0 项**

关键登记读数（修复后）：
```
A：40 局 × ≤20 波，逐位差异格数=0（修复前 A=0 / B=4）
B：40 局 × ≤20 波，逐位差异格数=0（修复前 A=0 / B=4）
B（Sapper 开）：逐位差异格数=0（修复前 4）
```
→ B 路径整局 **4 → 0**、B+Sapper **4 → 0**，与工程登记一致。

---

## §5 🔴 判别性反证（关键 · 独立复现）

**目的**：证明新守护 `AC-T1-25` 真能抓到该缺陷（而非恒绿的橡皮章）。

**安全流程**（严格按序）：
1. 备份：`mkdir -p /tmp/t01_bak && cp scripts/engine/wave_sim_aggro.gd /tmp/t01_bak/`
   → 备份 md5 = `c672df6c7b23e00e7021231012401d0a`（= 修复态）
2. 临时改回 no-op：L193 `monsters = _stable_sort_by_time(monsters)` → `_stable_sort_by_time(monsters)`
3. 跑 `… -- t1aggro`
4. **立即**从备份 `cp` 还原
5. 校验 `md5sum` + `git diff --stat` 与还原前一致

**反证结果（no-op 态）** → 日志 `/tmp/t01_reduced.log`，**EXIT=1（≠0）**：
```
[PASS] AC-T1-25A 逐波 真身↔镜像 差异  got=0 want=0          ← 单波仍恒等（与「只在整局显形」一致）
[PASS] AC-T1-25A 场景有效性 … got=true want=true
[FAIL] AC-T1-25B 整局 B 逐波逐位差异格数  got=4 want=0      ← 🔴 翻红
[FAIL] AC-T1-25B 整局 B+Sapper 逐波逐位差异格数  got=4 want=0  ← 🔴 翻红
T1 仇恨 汇总：通过 218 项 / 失败 2 项
```

**还原校验**：
- 还原后 md5 = `c672df6c7b23e00e7021231012401d0a` —— 与备份/还原前**逐位相同** ✅
- `git diff --stat`：`3 files changed, 147 insertions(+), 10 deletions(-)` —— 与还原前**完全一致** ✅

🔴 **判定：守护确为判别性**（撤修复即翻红，EXIT 由 0→1，与文档登记「B=4 / B+Sapper=4 / 218-2」逐位吻合）。
🔴 **零残留 / 零污染**：还原后工作树与反证前逐位一致；临时备份位于仓库外 `/tmp`，已清理。

---

## §6 零阈值核查（全量 diff 审阅）

`git status --porcelain` 的**已跟踪改动**仅 3 个文件（新文档 `aggro-mirror-fidelity-impl.md` 为 untracked 新增）：

| 文件 | 改动性质 | 是否触数值/判据 |
|---|---|---|
| `scripts/engine/wave_sim_aggro.gd` | 仅 L193 一行 `assign` + 4 行注释 | ❌ 无（`-U0` 逐字核：唯一代码行变更 = assign） |
| `tests/test_suite_aggro_golive.gd` | 仅 `_log(...)` 字符串文案（登记 INFO） | ❌ 无（`-U0` 逐字核：所有变更行均为 `_log(...)`，无判等逻辑） |
| `tests/test_suite_t1_aggro.gd` | 5 行 import + 新增 `AC-T1-25` 守护 + 注册进 `run_all()` | ❌ 无（纯新增；未改任何既有期望值） |

**逐字确认未改任何定稿数值 / 判据阈值**：
- `ATTRITION` 定稿点（1.50）未见 diff；`KAPPA_R` / `KR_FINAL` / `AGGRO_R` 未见 diff；
- `0.80` 门禁、radial8 各阈值（`TH_HIT=0.12` / `TH_HIT_FAIL=0.30` / T-B′/C′/D′ / `V0_*`）均未见 diff；
- `wave_sim_aggro.gd` 的 `-U0` diff 仅 `_stable_sort_by_time(monsters)` → `monsters = _stable_sort_by_time(monsters)`，无任何数字变更。

✅ **零阈值改动成立**。

---

## §7 无残留

- `**/_tmp_*`：**零命中**（Glob 全仓库 + `git status | grep _tmp_` 双证）。
- 仓库外临时备份 `/tmp/t01_bak` 已删除。

---

## §8 逐项结论

| # | 验证项 | 判定 |
|---|---|---|
| 1 | 读码确认（assign / 新数组 / 真身原地 / 语义对齐） | ✅ PASS |
| 2 | 默认回归 EXIT=0 · 8 段逐位不变 · T1=220/0 | ✅ PASS |
| 3 | radial8 结论 PASS（8 成员 exit 0） | ✅ PASS |
| 4 | aggro_golive 56/56 · exit 0 | ✅ PASS |
| 5 | 判别性反证（撤修复翻红 + 安全还原） | ✅ PASS |
| 6 | 零阈值核查（全量 diff 审阅） | ✅ PASS |
| 7 | 无残留（`**/_tmp_*` 零命中） | ✅ PASS |

## §9 遗留 / 供主理人裁决

1. 🟡 **`scripts/engine/wave_sim_proto_aggro.gd` 头部 L20-27 注释现已过期**（仍称 `wave_sim_aggro.gd:189` 为 no-op 缺陷）—— 复核**证实**该注释与修复后事实矛盾。该文件属红线 #3「不改」之列，工程侧未动。建议主理人决定是否同步（纯注释、零逻辑）。**复核不修改。**
2. 🟡 **设计侧读数迁移（无门禁破线）**：`scan_sapper` 的 Sapper 惩罚（B 路径 Δ起飞率）由 -0.067（温和）→ -0.117（中等）—— 修复使镜像忠实真身，该读数更接近真相。**建议文策渊复核** Sapper 平衡判断是否仍成立。**复核不修改数值，仅登记。** 〔🔴 2026-10-12 工程侧补注（T-DEBT-01-CLOSE）：本工具口径 = **六槽 PATH**（`scan_sapper` 不设 `mode`/`n_slots`）；该 Sapper 读数已按其**预登记处置 A** 用忠实镜头 N=300 复核 → `ΔB=−0.077`（温和档）· 案已关闭，见 `docs/phase3/sapper-balance-review.md` v2。〕
3. 🟢 **未提交**：本报告与工程改动均留在工作区，最终 git commit 由用户决定（复核阶段**未 commit**）。

> 🔴 质量门（**建议性**）：本次复核判定 **PASS**，无阻塞项；放行与否由用户裁决。
