# V-6′ · 多塔流安全裕度 —— 只读测量实现记录（R1 + R2 + R3）

| 项 | 内容 |
|---|---|
| 任务 | 实现 V-6′（多塔流安全裕度）**只读测量** R1+R2+R3（R4 只读扫参挂 T2，本次不做） |
| 归属 | 程基岩（engineering-lead）· 实现与实测 |
| 日期 | 2026-10-10 |
| 依据 | `docs/phase3/qg-radial/v6prime-multitower-margin.md` §4（V6′-R1 / R2 / R3） |
| 前置 | `tests/run_slice_attrition8.gd`（八槽既有）· `tests/golden_slice2.gd` / `tests/test_suite_slice2.gd`（六槽金标本）· `docs/phase3/qg-radial/r4-eight-slot-v0-closure.md` · `r4-attrition8-after.log` · `a-side-balance-adjudication.md` |
| 状态 | 🟢 **完成** · 全部只读测量 · 🔴 零生产代码改动 · 零定稿数值改动 · 金标本零扰动 |
| 交付物 | `tests/probe_v6prime.gd`（新增）· `docs/phase3/qg-radial/v6prime-r1r2r3.log` · `docs/phase3/qg-radial/v6prime-default-regression.log` · 本文 |

---

## 0. 三句话结论

1. 🟢 **R1 双口径对齐完成，且揭开一个被忽略的第四重混淆**：六槽 A `0.693` 来自**无塔死亡的六槽金标本引擎**（`RunLoop`），八槽 A `0.597` 来自 **aggro 引擎**（`RunLoopAggro` + `ATTRITION=1.50`，含塔死亡）。二者相差 `0.0963`（`z=2.48`，非噪声），但**差值的主导来源是"引擎口径迁移"（−0.4097），不是槽数**。归因控制实测：**八槽几何/运动学在 aggro 引擎下反而更利于 A（+0.2667）**。→ 🔴 **规格预置的「八槽本身在压 A」这一 naive 读数被实测否定**；真实根因是 **跨引擎口径混用**，与 `Q-R9`（八槽是否启用）不是同一件事。

2. 🟢 **R2：B 近乎免疫，但非"全程满血"**。八槽 300 局 B 的 `core_hp_min = 750.0`（**3/300 局**在 **W2** 掉一次血后全程不变）；确定性单局 B **全程 1000.0**。→ `survive_rate = 1.000` 的真相是「**99% 满血通关 + 1% 在 W2 早泄一次**」，后期（W13+）**从未被逼近** → H1 分量上升，但存在一个极小的**早期**压力窗口。

3. 🟢 **R3：A 的失败零后期（W16+ = 0）**。121 个失败局**双峰分布**：早期崩塌 W3–4（55 局，苟活期）+ 成型期悬崖 W10–11（54 局）；**W16+ 一个都没有**。失守前 3 波 `core_hp` 斜率均值 `−218.80`/波。→ A 的问题是**早期/成型期塔死**，**不是后期压力不足** → **不构成"多塔太安全"的证据**（H2/A 侧案）。

---

## 1. 交付物清单

| # | 文件 | 性质 |
|---|---|---|
| 1 | `tests/probe_v6prime.gd`（新增 · 23 KB · `extends SceneTree`） | 只读测量探针（R1+R2+R3 独立入口） |
| 2 | `docs/phase3/qg-radial/v6prime-r1r2r3.log` | 探针运行日志（原始证据） |
| 3 | `docs/phase3/qg-radial/v6prime-default-regression.log` | 默认无参回归日志（金标本零扰动证据） |
| 4 | `docs/phase3/qg-radial/v6prime-impl.md` | 本文 |

> 🔴 **改动只在 `tests/` 内**，且为**新增独立脚本**——未改任何既有测试脚本，未改 `scripts/` 一字。

### 1.1 探针做了什么（逐项）

| 段 | 内容 | 口径来源 |
|---|---|---|
| **R1-a** | 六槽 PATH 金标本：MC 300（`_Stats.takeoff_rate` · seed `20260930`）+ 确定性单局（`rng=null`） | 逐位镜像 `test_suite_slice2.gd` 六槽入口 |
| **R1-ATTR(1)** | 归因控制：六槽 PATH 几何/运动学 · **aggro 引擎** · seed `20260930` · A 的 `survive_rate` | `RunLoopAggro.run("A", n_slots=6, mode=PATH, ATTRITION=1.50)` |
| **R1-b** | 八槽 RADIAL：MC 300×A/B（seed `20261002` · `ATTRITION=1.50` · `WARMUP=2` · `max_actions=12`）+ 确定性单局（`Geo8.build8()`） | 逐位镜像 `run_slice_attrition8.gd` 主循环 |
| **R1-ATTR(2)** | 归因控制：八槽 RADIAL · **换回六槽金标本 seed `20260930`** · A 的 `survive_rate` | 同上，仅换 seed |
| **R2** | B 逐波压力剖面（确定性单局全表 + 300 局逐波聚合）+ A 对照 + `core_hp_min`/`w_min` | `run_loop_aggro.gd:121-139` row 字段 |
| **R3** | A 失败局 `w_end` 直方图 + 失守前 3 波 `core_hp` 斜率 | 复用 R1-b 主循环 rows，**不新增 MC** |

---

## 2. 验收原始证据

### 2.1 命令 + exit code

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# ① 探针（R1+R2+R3）
"$GODOT" --headless --path D:/roguedemo --script res://tests/probe_v6prime.gd
#   -> exit 0 · 3m21s · 日志 docs/phase3/qg-radial/v6prime-r1r2r3.log

# ② 语法检查
"$GODOT" --headless --path D:/roguedemo --script res://tests/probe_v6prime.gd --check-only
#   -> exit 0（无 Parse Error）

# ③ 默认无参回归（金标本零扰动）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd
#   -> exit 0 · 2m31s · 日志 docs/phase3/qg-radial/v6prime-default-regression.log

# ④ 生产代码零改动
git diff --stat -- scripts      # -> 空
```

### 2.2 验收项逐条

| # | 验收项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 探针 → **exit 0**，R1/R2/R3 三节读数齐备 | 🟢 **PASS** | 日志 L13–129 三节完整 |
| 2 | 默认回归（无参）→ **exit 0**，金标本逐位不变 | 🟢 **PASS** | `[FAIL]` 计数 **0**；汇总 222/2228/142/123/302/41/31/**92**/216，失败全 0 |
| 3 | `git diff --stat -- scripts` → **空** | 🟢 **PASS** | 输出为空 |
| 4 | 八槽基线 `s=1.0` 与 `r4-attrition8-after.log` 逐位一致 | 🟢 **PASS** | B `1.0000` / A `0.5967`（=179/300）/ det `B/A 0.6217` 全部 `true` |
| 5 | `project.godot` 跑后 clean | 🟢 **PASS** | `git status --porcelain -- project.godot` 为空（未被引擎重写，无需还原） |

### 2.3 默认回归断言计数（逐位比对基线）

```
汇总：通过 222  项 / 失败 0 项   (slice1)
汇总：通过 2228 项 / 失败 0 项   (slice2)
汇总：通过 142  项 / 失败 0 项   (slice3)
汇总：通过 123  项 / 失败 0 项   (slice4)
汇总：通过 302  项 / 失败 0 项   (slice5)
汇总：通过 41   项 / 失败 0 项   (slice6)
汇总：通过 31   项 / 失败 0 项   (slice7)
切片8 合计：PASS=92  FAIL=0
T1 仇恨 汇总：通过 216 项 / 失败 0 项
```

> 与任务给定基线 `222/2228/142/123/302/41/31/92/216`、失败 0 **逐位一致**。出口仅有既存 RID/ObjectDB 泄漏告警（`1ca10ef` 前既有，非本次引入）。

---

## 3. R1 · 双口径对齐与归因

### 3.1 R1-a 六槽 PATH 金标本（seed `20260930` · N=300）

| 量 | 实测 | 金标本 | 一致? |
|---|---|---|---|
| A `survive_rate` | **0.6930** | 0.693 | ✅ |
| A `takeoff_rate` | **0.6930** | 0.693 | ✅ |
| A 中位起飞波 | **W8** | W8 | ✅ |
| A `n_takeoff` | **208/300** | 208 | ✅ |
| B `survive_rate` | **1.0000** | 1.000 | ✅ |
| B `takeoff_rate` | **0.9130** | 0.913 | ✅ |
| B 中位起飞波 | **W13** | W13 | ✅ |
| B `n_takeoff` | **274/300** | 274 | ✅ |
| det A 起飞 / W20 ratio | **W8 / 21.772** | W8 / 21.77 | ✅ |
| det B 起飞 / W20 ratio | **W12 / 9.966** | W12 / 9.97 | ✅ |
| det `B/A` | **0.4577** | 0.458 | ✅ |

### 3.2 R1-b 八槽 RADIAL（seed `20261002` · `ATTRITION=1.50` · `WARMUP=2` · `max_actions=12` · N=300）

| 量 | 实测 | `r4-attrition8-after.log` | 一致? |
|---|---|---|---|
| A `survive_rate` | **0.5967**（179/300） | 0.597（`.log` %.3f） / 0.5967（`[R4-V0]` %.4f） | ✅ |
| A `takeoff_rate` | **0.5967** | 0.5967 | ✅ |
| A 中位起飞波 | **W8** | W8 | ✅ |
| B `survive_rate` | **1.0000** | 1.000 | ✅ |
| B `takeoff_rate` | **0.9133**（274/300） | 0.913 / 0.9133 | ✅ |
| B 中位起飞波 | **W14** | W14 | ✅ |
| MC 均值 W20 ratio A/B | **21.174 / 8.337** | 21.174 / 8.337 | ✅ |
| MC 均值 `B/A` | **0.3937** | 0.3937 | ✅ |
| det A 起飞 / W20 | **W8 / 21.772** | W8 / 21.772 | ✅ |
| det B 起飞 / W20 | **W11 / 13.535** | W11 / 13.535 | ✅ |
| det `B/A` | **0.6217** | 0.6217 | ✅ |

> ✅ **八槽基线（含 MC 均值、确定性单局）与现行 `r4-attrition8-after.log` 逐位一致** —— 验收 #4 达成，且八槽 MC 无任何漂移。

### 3.3 R1 判读：`[R1-FLAG]` + 归因三分量（🔴 关键发现）

同一份输出并排：

```
six-slot A (golden) = 0.6930   vs   eight-slot A = 0.5967   ->   diff = 0.0963  (> 0.05)
   noise: SE_diff = 0.0389 · z = 2.48  (|z|>1.96 => 非随机噪声)
```

按规格打印：

```
[R1-FLAG] six-vs-eight A diff 0.0963 > 0.05 (naive reading: eight-slot itself suppresses A) -> Q-R9 pre-input
```

**但**归因控制（两张额外的只读 MC，均 N=300）给出：

| 点 | 引擎 | 几何/运动学 | 槽数 | seed | A `survive_rate` |
|---|---|---|---|---|---|
| ① 六槽金标本 | `RunLoop`（**无塔死亡**） | PATH | 6 | 20260930 | **0.6930** |
| ② 归因控制 1 | `RunLoopAggro`+`ATTRITION` | PATH | 6 | 20260930 | **0.2833** |
| ③ 归因控制 2 | `RunLoopAggro`+`ATTRITION` | RADIAL | 8 | 20260930 | **0.5500** |
| ④ R1-b 主扫 | `RunLoopAggro`+`ATTRITION` | RADIAL | 8 | 20261002 | **0.5967** |

**三分量分解**（①→④ 的 −0.0963）：

```
engine   (①->② · RunLoop -> aggro @6槽,seed6)   = -0.4097
geometry (②->③ · 6槽 -> 8槽 @seed6,aggro)        = +0.2667
seed     (③->④ · seed6 -> seed8 @8槽,aggro)      = +0.0467
                                              ----------
                                              sum = -0.0963  ✅ 分解自洽
```

> 🔴 **结论：规格预置的 naive 读数「八槽本身在压 A」被实测否定。**
> - **主导抑制者是"引擎口径"（−0.4097）**：`0.693` 是**无塔死亡**的六槽金标本口径；一旦切到**含塔死亡的 aggro 引擎**，A 的存活率在六槽 PATH 上直接掉到 `0.283`。
> - **八槽几何/运动学在 aggro 引擎下反而更利于 A（+0.2667）**（`0.283 → 0.550`）。即：从"会塔死的六槽"换成"会塔死的八槽径向"，A 是**受益**的。
> - 因此 `0.693 vs 0.597` 的差 **不是"八槽压 A"**，而是**跨引擎口径混用**的假象（与 `v6prime-multitower-margin.md` §1.2 的口径警示同源，但规格只列了「槽数/几何/seed」三重混淆，**漏了第四重"引擎"**）。
> - 🔴 **给 Q-R9 的输入相应修正**：八槽本身**不压** A；"A 的 0.597 < 0.60 红线"若成立，其机制是**塔死亡/aggro 口径**（这也是 `a-side-balance-adjudication.md` 已裁决为"噪声·不处置"的那条），**与"是否启用八槽"无关**。

---

## 4. R2 · B 路径压力剖面（回答"赢得多轻松"）

### 4.1 确定性单局（`rng=null` · `geo8`）

B 全 20 波：`core_hp = 1000.0` 恒定，`leaked = 0`，`kills = n`，`residual = 0`。
A 对照：`core_hp = 900.0` 恒定（W1 起 900，因 A 首波漏 2 只 → 100 伤害），`ratio` 从 0.128 升到 21.772。

> 🔴 **残留怪数说明**：rows **无专门字段**；用 `residual = n - kills - leaked` **近似**（本口径下恒 0）。🔴 **不新增引擎埋点** —— 已按规格登记为**缺口**（§7-D2）。

### 4.2 300 局逐波聚合

| 波 | B: n_runs | B: mean core_hp | B: min core_hp | A: n_runs | A: mean core_hp |
|---|---|---|---|---|---|
| W1 | 300 | 1000.00 | 1000.00 | 300 | 900.00 |
| W2 | 300 | **997.50** | **750.00** | 300 | 855.67 |
| W3 | 300 | 997.50 | 750.00 | 300 | 810.33 |
| W4 | 300 | 997.50 | 750.00 | 296 | 739.86 |
| W5–W11 | 300 | 997.50 | 750.00 | 245→225 | 874.9 → 716.0 |
| W12–W20 | 300 | 997.50 | 750.00 | **179** | 900.00 |

> - **B**：`core_hp_min = 750.0 @ W2`；**仅 3/300 局**曾低于满血——这 3 局在 **W2 掉 250**（=5 只漏怪 ×50）后**全程不变**（未恢复也不继续掉）。
> - **A**：`mean core_hp` W1 900 → **W4 触底 739.86** → 回升；`n_runs` 由 300 单调降到 **179**（失败局在 W4/W11 成批退出 → 删失）。

### 4.3 判读

```
[R2-SUM]   B core_hp_min (300 runs) = 750.0 @ W2 ; runs ever below full HP = 3/300
[R2-SUM]   B core_hp_min (det single) = 1000.0 @ W1
[R2-JUDGE] B only lightly pressured (core_hp_min=750.0, 3/300 runs, earliest W2)
           -> near-immune; H1 component UP, tiny early window
```

- 🟢 **B 后端（W13+）从未被逼近**（1000.0 满血进入雪崩期）→ **H1 分量上升**（后期对 B 无压力）。
- 🟡 **但 `core_hp_min ≈ 1000.0 全程满血` 的说法不精确**：真相 = **99% 满血 + 1% 于 W2 早泄一次**。压力窗口存在但**极小且极早**（W2，B 尚未成型），非后期。
- 对照：A 的压力窗口清晰（W4 触底、W10–11 二次下探 716），B 几乎没有 → **"B 赢得多轻松"= 几乎是碾压**。

---

## 5. R3 · A 侧失守波次分布（隔离 H2）

### 5.1 `w_end` 直方图（121 失败局 · 复用 R1-b MC 的 rows）

| `w_end` | 局数 | 归属期 |
|---|---|---|
| W3 | 4 | 苟活期 |
| **W4** | **51** | 🔴 早期崩塌峰 |
| W5 | 6 | |
| W6 | 3 | |
| W8 | 1 | |
| W9 | 2 | |
| W10 | 8 | 成型期 |
| **W11** | **46** | 🔴 成型期悬崖峰 |
| W16+ | **0** | —— |

```
share W8-W11 = 57/121 = 0.471
share W16+   =  0/121 = 0.000
```

> ✅ **与现行 `r4-attrition8-after.log` 逐位一致**（交叉核对）：该日志 A 失败局 **总数 121**、`w_end=4` **51** 局、`w_end=11` **46** 局 —— 与本探针 **121 / 51 / 46 逐位相同**。

### 5.2 失守前 3 波 `core_hp` 斜率

```
[R3-SLOPE] pre-fail 3-wave core_hp slope (core_hp/wave): mean=-218.80 median=-225.00 n=121
```

> 含义：失败局在失守前的 3 波里，核心 HP 平均以 **−218.8/波** 的速度塌陷 —— 是**陡崖式**（非缓慢磨死），与"塔死 → DPS 塌 → 核心瞬时被打爆"的螺旋一致。

### 5.3 判读

```
[R3-JUDGE] ZERO failures at W16+ -> NO late-pressure shortfall (not evidence of 'multitower too safe')
[R3-JUDGE] failures are bimodal: early collapse W3-4=51 + formation cliff W10-11=54
           -> A-side tower-death, not late pressure
```

- 🔴 **A 的失败双峰**：**早期崩塌（W3–4，55 局）** + **成型期悬崖（W10–11，54 局）**，**W16+ 为零**。
- → A 的问题是**早期/成型期塔死**（`R-T10` 正反馈螺旋），**不是后期压力不足**。
- → **不构成"多塔太安全"的证据** → 归 **H2 / A 侧案**（`card-system` §5.7.2 已记录"死亡高度集中在 W10–13 起飞悬崖"；本次八槽实测把早期崩塌峰 W4 也标出来了）。

---

## 6. 偏差登记与意外发现

| # | 项 | 说明 | 处置 |
|---|---|---|---|
| **D1** | 🔴 **规格漏列第四重混淆"引擎"** | §4 V6′-R1 只列了「槽数/几何/seed」。但六槽金标本 `0.693` 走 `RunLoop`（无塔死亡），八槽 `0.597` 走 `RunLoopAggro`（含塔死亡）→ **引擎口径本身就是最大混淆项**（−0.4097）。 | 已加两张只读归因控制 MC 量化；`[R1-FLAG]` 的 naive 读数被否定。**回传主理人**（影响 Q-R9 结论方向） |
| **D2** | 🟡 `residual_monsters` 无专门字段 | 规格要求"每波打印场上残留怪数"；rows 无此字段。 | 用 `n - kills - leaked` **近似**（本口径恒 0）；🔴 **不新增埋点**，登记为缺口 |
| **D3** | 🟡 R2 `core_hp_min = 750.0`（非 1000.0） | 3/300 局在 W2 早泄一次。规格的判读二分（"≈1000 从未被逼近" vs "显著掉血后回升"）都不精确命中。 | 实测按"**近似免疫 + 极小早期窗口**"登记；确定性单局确为全程 1000.0 |
| **D4** | 🟢 常量口径 | `r4-attrition8-after.log` 的 A 存活 `0.597` 是 `%.3f` 打印；真值 `0.5967`（=179/300，`%.4f`）。 | 探针常量取 `0.5967`，比对容差 `5e-5` |
| **D5** | 🟢 成本 | 探针 ~3m21s（含 3 张额外归因控制 MC，各 300 局）。 | 可接受；R4 未做（挂 T2） |
| **D6** | 🟢 六槽 det B `w20 = 9.966` | 规格写 `9.97`（2 位）。 | 同一量，仅舍入位数不同 |

---

## 7. 红线核对

| 红线 | 状态 | 证据 |
|---|---|---|
| 零生产代码改动 | 🟢 | `git diff --stat -- scripts` 为空 |
| 零定稿数值改动 | 🟢 | `ATTRITION=1.50` / `κ_r=0.050` / `AGGRO_R=9.0` / 塔位 6 / `SLOTS6` / `SLOTS8` / `t_reach=10.0s` / `hp_growth=1.42` / DPS 曲线 —— 全部零改动（改动只在 `tests/` 新增文件） |
| 金标本零扰动 | 🟢 | 默认无参回归 **exit 0**，9 套断言计数逐位不变、失败 0；八槽 MC 与 `r4-attrition8-after.log` 逐位一致 |
| `t_remain` 唯一权威状态量 | 🟢 | 未触碰 |
| 出生角零 RNG 消费 | 🟢 | 未触碰 `spawn_theta`；确定性单局 `rng=null` |
| 改动只在 `tests/` 内（新增独立脚本） | 🟢 | 仅新增 `tests/probe_v6prime.gd`；未改任何既有测试脚本 |
| ASCII 机器可读行 | 🟢 | 全部输出 ASCII；进度用 `push_error`（stderr 不缓冲） |
| 只扫描不落点 | 🟢 | 探针无任何写回；无配置落点 |

---

## 8. 给主理人的下一步建议

1. 🔴 **Q-R9 判读方向修正**：规格预置的"八槽本身在压 A"**不成立**。八槽（aggro 口径）对 A **有利**（+0.2667）；`0.693→0.597` 是**跨引擎口径**假象。→ **不建议**以"八槽压 A"为由处置八槽启用问题。
2. 🟡 **对价（C1）仍成立**：八槽确定性 `B/A = 0.6217`、MC 均值 `B/A = 0.3937`，均 **显著 < 1** → **V-6′ 主判据不触发**（与规格 §1.2 / §3 先验一致）。
3. 🟡 **H1（B 太安全）分量确认存在**：B 后端 100% 满血进入雪崩期（R2）→ 后期对 B 无张力；但这是**后期压力源**问题（新增 Elite/怪物曲线，另立项），**不是**多塔流对价问题。
4. 🟢 **R4（只读扫参 `M_B`）可留 T2**：R1–R3 已足以判 H1/H3 谁占优（H3 成立、H1 部分真），当前无决策需要 `M_B` 的具体数字。

---

*文档结束 · 程基岩（engineering-lead）· V-6′ 多塔流安全裕度 · 🟢 R1+R2+R3 完成 · 🔴 零生产代码改动 · 零定稿数值改动 · 金标本零扰动（默认回归 exit 0）*
