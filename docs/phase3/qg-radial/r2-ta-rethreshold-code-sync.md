# R-2 · T-A′/T-A2 判据新基线重标定 → 测试代码同步记录

| 项 | 内容 |
|---|---|
| 任务 | QG-RADIAL-01 · Phase 6 打磨 · 判据定档同步到测试代码 |
| 归属 | 程基岩（engineering-lead · 测试代码执行）；判据定档 = 文策渊（`r2-criteria-revision.md` §12） |
| 日期 | 2026-10-09 |
| 规格来源 | `docs/phase3/qg-radial/r2-criteria-revision.md` §12.4（执行规格）/ §12.3（定档结论）/ §12.5（红线边界） |
| 改动文件 | **仅** `tests/run_slice_attrition8.gd`（生产行为、定稿数值一字未动） |
| 触发 | `1ca10ef`（`snap/rest` 修复）后 A 侧基线位移 → T-A′（均值 0.380 < 1.0）与 T-A2（`hit_fail` 0.4711 < 0.60）恒 FAIL → attrition8 / radial8 恒 exit 1。根因 = 判据阈值仍在用缺陷期虚高值标定、代码从未同步定档，**非机制失效**。 |

---

## 1. 五项改动（逐条 · 改前 → 改后）

| # | 位置（改后行号） | 改前 | 改后 | 性质 |
|---|---|---|---|---|
| **1** | `const TH_HIT`（L116 区） | `0.15` | **`0.12`** | 阈值重标定（新实测 `hit=0.1900` · **+3.09 SE**） |
| **2** | `const TH_HIT_FAIL`（L117 区） | `0.60` | **`0.30`** | 阈值重标定（新实测 `hit_fail=0.4711` · **+3.77 SE**） |
| **3** | `_print_criteria()` 内 T-B tail5 | `_ok("T-B tail5 …", t5 <= TH_TAIL5)`（真闸门 · 计 `_fail`） | **`print("[INFO] T-B tail5 … 事实登记 … 不计 _fail")`** | 定位降级（结构恒 0 · 零信号）。`TH_TAIL5=0.07` 常量保留作打印基准 |
| **4** | `_initialize()` 内 T-A′ 均值（L206 区） | `_ok("T-A′ A 成型期塔死 %.3f ≥ 1.0", a_form >= 1.0)`（真闸门 · 计 `_fail`） | **`print("[INFO] T-A′ A 成型期塔死均值 %.3f … 不计 _fail")`** | 定位降级（与 T-A′-1 数学等价：`X_form∈{0,2}` → 均值 = 2×hit 恒等，重复闸门） |
| **5** | `const TH_TDD` + `_run_tdd_control()` + 调用块 | 1 seed（`20261002`），`Σ dis_new ≥ 1` | **3 seed 累计 `Σ dis_new ≥ 3`**；`_run_tdd_control(seed)` 按传入 seed 跑 | 阳性对照加固（原 1 seed margin=0 太脆） |

**T-D″ 选用的 seed（登记）**：`20261002`（§12.4 建议）+ `20261003` + `20261004`。
实测：三 seed 各 `dis_new = 1`（分别落在 W4 / W4 / W5）→ 累计 **3**，vs TH 3 → margin = 0，`[WARN]` 提示保留。
（诚实标注：`Poisson(λ≈3)` 下 `P(≥3)≈0.58`，属存在性阳性对照；🔴 连续两次 FAIL 才判回归，见 §12.3。）

**配套注释更新**：文件头阈值状态块（L41 区）+ 常量声明块（L111 区）均补注「阈值已于 2026-10-09 按 `snap/rest` 修复后新基线重标定，依据 §12」，避免后续读者误以为 0.12/0.30 是被"下调来过关"的。

---

## 2. 红线遵守自检

| 红线 | 状态 |
|---|---|
| 只动判据阈值与定位（闸门→INFO），不动生产行为 | ✅ 仅改 `tests/run_slice_attrition8.gd`；无 `scripts/` 改动 |
| 不动 `survive_rate A = 0.597` 平衡红线 | ✅ 一字未动；本脚本里它本就只是 INFO、非闸门。`TH_HIT_FAIL=0.30` 是判据阈值，与平衡红线 0.60 是两个完全不同的量（§12.5 B-1） |
| 未用"削 B / 再下调阈值"让 A 过线 | ✅ 阈值按 §12.3 定档值同步，非工程自拟下调 |
| 未回退 `snap/rest` 修复 / 未重扫 `ATTRITION` | ✅ `ATTRITION_FINAL = 1.5` 一字未动（§12.5 B-2） |
| `GUARD_N_FAIL` / 统计量定义不动 | ✅ 未动 |
| 金标本零扰动（默认无参回归 exit 0） | ✅ 见下方验收 3，九套件计数与金标本逐位一致 |
| Windows GBK 乱码：输出 ASCII | ✅ `[PASS]/[FAIL]/[INFO]/[WARN]` 全 ASCII |

---

## 3. 三条验收结果（Godot 4.7.2 · `Godot_v4.7.2-stable_win64_console.exe`）

| # | 命令 | 结果 | 关键输出 |
|---|---|---|---|
| **1** | `--script res://tests/run_slice_attrition8.gd` | 🟢 **exit 0** | `T-A1 hit 0.1900 vs TH 0.12 → +3.09 SE PASS` · `T-A2 hit_fail 0.4711 vs TH 0.30 → +3.77 SE PASS (n_fail=121)` · `[INFO] T-A′ A 成型期塔死均值 0.380（…不计 _fail）` · `[INFO] T-B tail5 0.0000 …（…不计 _fail）` · T-D″ 3 seed 累计 = 3 + `[WARN] margin = 0` · **失败 0 项** |
| **2** | `--script res://tests/run_tests.gd -- radial8` | 🟢 **exit 0** | attrition8 子进程 **exit=0 · 失败标记 0 处**；radial8 全 8 项 PASS；`radial8 结论：PASS（exit 0）` |
| **3** | `--script res://tests/run_tests.gd`（默认无参） | 🟢 **exit 0** | 九套件计数 **222 / 2228 / 142 / 123 / 302 / 41 / 31 / 92 / 216**，**全部 FAIL=0**，与 `r4-default-regression.log` 金标本逐位一致 |

> 三条全绿。验收 1 未出现任何非预期 FAIL —— 无需回传文策渊。

---

## 4. 备注

- 退出时 Godot 引擎打印的 `ERROR: N RID allocations … leaked at exit` / `ObjectDB instances were leaked` 是引擎级良性告警（headless 文本服务器资源回收），**非测试失败**，不影响 exit code 与断言结果。
- radial8 全跑含多子进程 MC，耗时约 2 分 9 秒；默认无参回归约 2 分 31 秒。均为正常耗时。

---

*文档结束 · 程基岩（engineering-lead）· QG-RADIAL-01 · Phase 6 判据同步 · 🔴 零生产行为改动 · 零定稿数值改动*
