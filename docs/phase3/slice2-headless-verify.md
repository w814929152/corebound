# Phase 3 · 切片2：战斗循环 + 商店/贪心AI + 主循环 + 判据统计 — headless 对齐验证报告

- **作者**：程基岩（工程主理人）
- **引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`
- **金标本**：
  - `corebound_sim_v03.py`（`monster_stats` / `simulate_wave` / 商店 / 贪心 AI / 主循环）
  - `corebound_sim_v06_synergy.py`（判据统计；⚠️ 它在 L238 做了 `sv.compute_dps = compute_dps_v6` 猴补丁，
    所以 `sv.run()` 实际调用的是 **v06 引擎**，不是 v03 那份旧的）
  - `corebound_sim_v07_mapA.py`（0.65 口径 `eval_point` / MC）
- **口径**（🔴 全程未改）：`kr_mode="tier"` / `link_rule="substantial"`(f=0.65) / `ntower_mode="current"` /
  `salvage_on=false` / `synergy_on=false` / `focus_full=false` / `hp_growth=1.42` / `hp_base=16` /
  `focus_per_layer=0.06` / `pity=true`
- **结论**：🟢 **2228 项断言全过，0 失败，退出码 0**（切片1 222 + 切片2 2006）
  - 定稿判据链 **16 条逐条对上**
  - MC 起飞率 **A 69.3% / B 91.3%**，中位起飞波 **A W8.0 / B W13.0**，与金标本**完全一致**
  - MC 前 20 局**逐局起飞波** A/B 全部逐位相同
  - 决定性跑逐波原始列最大相对偏差 **1.712e-16**（验收线 1e-6，余量 9 个数量级）

## 1. 跑法（退出码 0）

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd          # 全量
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice2 # 只跑切片2
```

完整输出存档：**`docs/phase3/slice2-headless-run.log`**（1003 行，含 A/B 逐波速览表）

金标本期望值由 `tools/export_golden_slice2.py` **从 Python 实跑导出**（非手抄）：
`docs/phase3/slice2-golden.json`（全精度）+ `tests/golden_slice2.gd`（GDScript 可读）。

## 2. 交付文件

| 文件 | 作用 |
| --- | --- |
| `scripts/engine/wave_sim.gd` | 离散战斗循环（dt=0.1、集火、漏怪、`wave_dur`/`spawn_window` 补入 `mvp_config.gd`） |
| `scripts/engine/shop_ai.gd` | 商店发牌 + 保底 + 动作枚举 + 贪心 `ΔDPS/cost` + 刷新 |
| `scripts/engine/run_loop.gd` | 主循环 `run()`（同时保留 `_raw` 全精度列与 `round` 后列） |
| `scripts/engine/stats.gd` | `takeoff_wave` / `tail_min` / `summarize` / `cross_lead` / `stage_health` / `takeoff_rate` / `eval_point` |
| `scripts/engine/py_random.gd` | Python `random.Random` 的 MT19937 逐位复刻（`choices` / `choice` / `randrange`） |
| `scripts/engine/fp_pow.gd` | 🆕 与 Python `**` 逐位对齐的**正确舍入整数幂**（见 §5.1） |
| `scripts/engine/fp_sum.gd` | 🆕 与 Python `sum()` 逐位对齐的 **Neumaier 补偿求和**（见 §5.2） |
| `scripts/engine/sim_player.gd` | 玩家态 `new_player` / `snap` / `rest` / `build_str` |
| `tests/test_suite_slice2.gd` | 切片2 自测（9 段） |
| `tests/golden_slice2.gd` | 金标本期望值（生成物） |

## 3. 判据链逐条对照（`design/phase2/numeric-sim/mapA-kappaR-sweep.md` §2「新口径·κ_r档位(不动)」行）

| # | 判据 | 金标本 | GDScript | 判定 |
| --- | --- | --- | --- | --- |
| ① | 单核 A 起飞波 | W8 | **W8** | ✅ |
| ② | 多塔 B 起飞波 | W12 | **W12** | ✅ |
| ③ | A W20 ratio | 21.77 | **21.772** | ✅ |
| ④ | B W20 ratio | 9.97 | **9.966** | ✅ |
| ⑤ | B/A（W20） | 0.458 | **0.458** | ✅ |
| ⑥ | 交叉领先 A | 16 | **16** | ✅ |
| ⑦ | 交叉领先 B | 4 | **4** | ✅ |
| ⑧ | 领先易手次数 | 1 | **1** | ✅ |
| ⑨ | 首次 A 领先 | W5 | **W5** | ✅ |
| ⑩ | 首次 B 领先 | W1 | **W1** | ✅ |
| ⑪ | A 三阶段增速（W20/W16） | 2.4 | **2.4** | ✅ |
| ⑫ | B 三阶段增速 | 3.0 | **3.0** | ✅ |
| ⑬ | A W13→W20 单调上升 | true | **true** | ✅ |
| ⑭ | B W13→W20 单调上升 | true | **true** | ✅ |
| ⑮ | A W1–W9 存活 | true | **true** | ✅ |
| ⑯ | B W1–W9 存活 | true | **true** | ✅ |

**敏感性对照（非定稿口径，证明口径开关真的生效）**：`kr_mode="flat"` 下 B 起飞 **W13**、B/A **0.242**
——与 `mapA-kappaR-sweep.md` 里旧口径行的差异一致，说明 `tier` / `flat` 两条路都通且互不串味。

## 4. 决定性跑逐波对照（rng=null，20 波）

完整表见 `slice2-headless-run.log` 的「[5] 定稿 tier 口径 A/B 逐波速览」。关键节点：

| W | A ratio | B ratio | A eff_dps | B eff_dps | 领先 |
| --- | --- | --- | --- | --- | --- |
| 1 | 0.128 | 0.274 | 20.6 | 43.9 | B |
| 4 | 0.419 | 0.492 | 268.5 | 315.6 | B |
| 5 | 0.534 | 0.422 | 555.4 | 439.5 | **A**（首次反超） |
| 8 | **1.241** | 0.457 | 4,855.8 | 1,788.5 | A（A 起飞） |
| 12 | 3.525 | **1.151** | 72,073.2 | 23,536.7 | A（B 起飞） |
| 16 | 9.081 | 3.327 | 950,690.9 | 348,300.6 | A |
| 20 | **21.772** | **9.966** | **10,903,440.3** | **4,991,135.6** | A |

对照项全部**逐位相同**（不是"接近"）：`n` / `kills` / `leaked` / `rerolls` / `cum_rerolls` / `towers` /
`slots` / `build` 串（整数与字符串列）、以及 `round` 后的 `hp_each(1)` / `total_hp(1)` / `eff_dps(1)` /
`ratio(3)` / `core_hp(1)` / `income(1)` 六列。

原始浮点列（`hp_each` / `total_hp` / `eff_dps` / `ratio` / `core_hp` / `income`，共 4 跑 × 20 波 × 6 列 = 480 格）：
**最大相对偏差 1.712e-16**（`tierB W17 eff_dps`），即 **≤1 ULP**。
为什么不是"逐位 0 差"见 §5.3 —— 瓶颈在 Godot 的**字面量解析**，不在计算。

## 5. 🔴 联调挖出的三个末位陷阱（本切片真正的工程量）

这三条都是"决定性跑看不出来、只有 MC 能抓到"的类型：它们不产生可见的数值漂移，
而是**在贪心 AI 的并列候选上翻转选择**，一次翻转被后续十几波复利放大成完全不同的起飞波。

### 5.1 `pow()`：Godot 与 Python 的整数指数幂差 1 ULP

```
Python 1.06 ** 6        = 1.4185191122560004
Godot  pow(1.06, 6.0)   = 1.4185191122560006      ← 差 1 ULP
真值 1.06^6             = 1418519112256 / 10^12 = 1.418519112256（有限小数）
```

采样统计（底数 1.000~1.120、指数 0~80，**2025 个点**）：

| 比较 | 不一致数 |
| --- | --- |
| Godot `pow()` vs Python `**` | **1731 / 2025（85%）** |
| Python `**` vs `Fraction` 精确值后舍入 | **0 / 2025** → Python 侧恒为**正确舍入** |
| Godot `pow(h, 0.6)`（非整数指数）vs Python | **0 / 200** → 非整数指数本来就一致 |

**处置**：新增 `fp_pow.gd`，用 **double-double（Dekker two_prod + two_sum）二进制快速幂**，
最后一次加法完成单次舍入 → 正确舍入。整数指数走 `pow_int()`，非整数指数（`h ** 0.6`）仍走 `pow()`。
接进 `softcap.gd`（`κ^lv` / `κ^cap` / `decay^(lv−cap)`）、`damage_engine.gd`（`(1+κ_r)^E`）、
`wave_sim.gd`（`hp_growth^(w−1)`）、`stats.gd`（`10^nd` / `2^-52`）。
回归验证：5528 个采样点 **0 不一致**。

### 5.2 `sum()`：Python 3.12+ 的 float 快路径是 Neumaier 补偿求和

`subtotal = sum(p["dps"] for p in per_tower)` 在 Python 里**不是**朴素左结合累加，
CPython 3.12+ 对 float 走 `f_result` / `f_result_err` 双累加器，最后返回 `f_result + f_result_err`。

要命的差别：**补偿求和对同一多重集与次序无关**，朴素累加不是。
而贪心 AI 会为「升级 S3」和「升级 S5」各算一次 subtotal —— 两者的逐塔 dps 是同一多重集、只换了位置。

实测（B 局第 18 局 W4 step2，四个并列候选 ΔDPS）：

| 实现 | up@0 / up@3 / up@4 | up@5 | 后果 |
| --- | --- | --- | --- |
| Python（补偿） | 9.406670173149649 | 9.406670173149649 | `max` 取第一个 → **@0** |
| GDScript（朴素） | 9.406670173149**635** | 9.406670173149**649** | @5 大了 1.4e-14 → **@5** |

**处置**：新增 `fp_sum.gd`，逐行移植 CPython 的 Neumaier 快路径，用于 `subtotal` / `aoe_total` / `aux_parts`。

### 5.3 Godot 的浮点**字面量解析**不是正确舍入（只影响金标本载体，不影响运行时）

```
Python float('186.26806084384762')   = 0x1.74893f455b53dp+7
Godot  字面量 186.26806084384762     = 0x1.74893f455b53cp+7   ← 低 1 ULP
Godot  字面量 186.268060843847620    = 0x1.74893f455b53dp+7   ← 加一位反而对了
Godot  字面量 3.07925140603429918e+03 ≠ 3079.251406034299     ← 换 18 位又错
```

即：**能否解析正确与位数不成单调关系**，改生成器的格式化串无法根除。

- **不影响运行时**：引擎里只有 `1.42` / `0.045` / `1.03` / `0.6` 这类短字面量，实测解析全部正确
  （`float(cfg["hp_growth"]) == 1.42` → true）。
- **只影响金标本**：`tests/golden_slice2.gd` 里的 17 位十进制期望值约有 2% 的格子自带 1 ULP 误差。
- **处置**：逐波原始列用 `TOL_ROW = 1e-15`（≈4~5 ULP，比验收线 1e-6 严 9 个数量级），
  并在测试里打印实际最大偏差（当前 1.712e-16）。
  🔴 **没有**为了凑数去"挑一个能跟实现对上的字面量写法"——那等于拿实现污染金标本。

### 5.4 修复顺序与 MC 起飞率的因果链（这是最有说服力的一条证据）

| 状态 | A 起飞率 | B 起飞率 | B 中位起飞波 |
| --- | --- | --- | --- |
| 修 `pow_int` 之前 | 69.3% ✅ | **89.3%** ❌ | W13.0 |
| 只修 `pow_int` | 69.3% ✅ | **89.7%** ❌ | W13.0 |
| 再修 `sum_py` | 69.3% ✅ | **91.3%** ✅ | W13.0 |

A 路径全程不受影响（单核只有 2 座塔，并列候选少），B 路径 6 座塔并列多 → 全线暴露。
**MC 前 20 局逐局起飞波在修完后 A/B 全部逐位相同**，这才是"移植正确"的硬证据。

## 6. 蒙特卡洛起飞率（MC 300 局 / seed=20260930 / 定稿 tier 口径）

| 路径 | 起飞率 | 存活率 | 中位起飞波 | 金标本 |
| --- | --- | --- | --- | --- |
| A 单核 | **69.3%**（208/300） | 69.3% | **W8.0** | 69.3% / W8.0 ✅ |
| B 多塔 | **91.3%**（274/300） | 100.0% | **W13.0** | 91.3% / W13.0 ✅ |

`takeoff_rate` 用**一个共享的** `Random(20260930)` 顺序推进 300 局（不是每局独立种子）——
这一点直接决定 rng 流，已逐位复刻（`py_random.gd` 的 MT19937）。

逐局对照（MC_TRACE，前 20 局）：

```
A got  = [8, -1, 8, 13, -1, -1, -1, -1, 10, -1, 7, 7, 10, 8, 8, 9, -1, 10, 11, 8]
A want = [8, -1, 8, 13, -1, -1, -1, -1, 10, -1, 7, 7, 10, 8, 8, 9, -1, 10, 11, 8, …]
B got  = [16, 8, 8, 9, 18, 19, 19, 13, 10, -1, 19, 9, 14, 13, 9, 9, 9, 13, 15, 17]
B want = [16, 8, 8, 9, 18, 19, 19, 13, 10, -1, 19, 9, 14, 13, 9, 9, 9, 13, 15, 17, …]
```

（`-1` = 该局 20 波内未起飞。逐位相同。）

## 7. 逐段测试内容（`tests/test_suite_slice2.gd`）

| 段 | 内容 | 关键点 |
| --- | --- | --- |
| [0] | 浮点末位对齐 | `pow_int` 8 个采样点 + `sum_py` 置换不变性 + 字面量解析参考输出 |
| [1] | `PyRandom` MT19937 | `random()` 24 个、`choices()` 发牌 8+8、`randrange(7)` 12 个 |
| [2] | `pround` vs Python `round(x, nd)` | 含 `round(2.675,2)==2.67` 这类"恰好 .5"的坑（走整数精确路径） |
| [3] | `monster_stats` | `n` / `hp_each` / `total_hp`；`wave_dur` / `spawn_window` 两个 λ |
| [4] | 正序遍历 ≡ Python 稳定排序 | 等价改写守护（曾写反成倒序 → W1 漏怪 2→6，判据链全崩，已在文件头留警示） |
| [5] | 决定性跑逐波（tier A/B + flat A/B） | 480 格原始列 + 整数列 + `build` 串 + round 后 6 列 |
| [6] | 定稿判据链 16 条 + 4 条红线 + 20 行交叉表 + flat 对照 | 见 §3 |
| [7] | MC 300 起飞率 | A 69.3% / B 91.3% + 存活率 + 中位起飞波 |
| [7b] | MC 前 20 局逐局起飞波 + 第 1/18 局逐波 rows | 发散定位探针（本次就是靠它锁定局 18） |
| [8] | 商店 / 贪心 AI 红线 | `fire_stock` 摩擦、`max_actions` 双处检查、`pity` 挤牌、`drop_from` / `weakest_card`、AllIn 副作用 |

## 8. 遗留与建议

1. **ADR-0002 已拍板**（主理人 2026-10-01 追认）：§5.1 / §5.2 / §5.3 三条末位分歧按方案 A 处置，
   `FpPow` / `FpSum` **提升为全工程强制编码规范（N1 / N2）**，已写入
   **`docs/architecture/control-manifest.md` §2**（含禁止写法与自检项）。
2. **`TOL_ROW` 是权宜**：若未来 Godot 修好字面量解析（或换平台），应把 §5.3 的参考输出复查一遍，
   若两条都变成 `true`，可把 `TOL_ROW` 收紧回逐位判等。测试里已留了对应注释。
3. **切片1 的 `golden_reference.gd` 用的是 `%.17g`**：同样是 17 位十进制，可能也有同样的解析噪声。
   切片1 现在跑在 1e-15 容差下全过，暂不改动；若要统一口径，建议一并切到 `%.17e` 并重跑。
4. **性能**：MC 300 局 B 路径约 50 s（A 约 7 s），`FpPow` 有底数→指数的二级缓存兜底。
   若后续要跑更大样本（如 3000 局），建议把 `action_value` 的 DPS 求值再缓存一层。
