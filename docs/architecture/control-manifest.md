# 《守核 Corebound》工程控制清单（Control Manifest）

> **一页规则 · 写/改代码前读完 · 改完对着第 7 节自检一遍**
>
- **维护人**：程基岩（工程主理人）
- **适用引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`（换版本必须重跑第 7 节全量自测）
- **来源**：ADR-0001（`kr_mode` 口径）／ADR-0002（浮点可移植性）／切片1·切片2·切片3·切片4·切片5·切片6·切片7·切片8 联调实测
- **状态**：切片8 全量自测 **222 + 2228 + 142 + 123 + 302 + 41 + 31 + 92 + 63 = 3244 项断言 / 0 失败 / 退出码 0**（92 = 切片8，含 I-7 塔位点选 + C2 高亮 + 续3 可玩 MVP 胜负结算 21 项；63 = T1 塔死亡玩法批次，含仇恨激活 + 塔死亡 + 修复入口 + **V-1 ATTRITION 定稿守护**；另有切片4 场景冒烟 46 项、切片5 场景冒烟 22 项回归）；🔴 切片4 的 9 项接线冲突（D-1…D-9）已全部拍板（`shop-reroll` §9.2 v1.3），其中 **D-9 已落地**（I-7 塔位点选）；🟡 切片5 的 4 项新分歧（S5-D1/S5-D2/S5-F1/S5-F2）已全部拍板（`wave-spawner` v0.3）；✅ 切片7 = S5-D1 校准闸门**已过**；✅ 切片8 = 拆除回收 `Salvage`（Q-C3 原文）+ I-9 二次确认 + I-7 塔位点选 + **C2 智能高亮 H2/H3/H5/H6/H7/H9**（SR-R2 只标事实合规）+ **续3 可玩 MVP 胜负结算**（核心 HP 单一数据源 + W20 通关胜利 + 核心归零失败 + 结算覆盖层 + 重开）+ **T1 塔死亡玩法批次**（机会型仇恨 Q-T3 + 塔 HP Q-T2 + Disabled 中间态 Q-T4 + 修复入口 Q-T4/Q-T8 + **✅ V-1 ATTRITION=1.50 定稿 + WARMUP=2 起手保护**，`aggro=false` 与金标本逐位等价）全部落地，κ 兜底①不回升守护通过，金标本零改动

---

## 0. 三条总红线

1. **金标本是唯一真理。** Python 模拟器（`design/phase2/numeric-sim/*.py`）产出的数字，
   GDScript 必须**逐位复现**；任何"差不多"都要追到根因，不许用容差糊过去。
2. **口径冻结。** 第 1 节表里的参数一个都不许改。发现"改了才对"= 发现了口径分歧 → 走第 6 节（写 ADR 上报），
   **不是**自己改参数，也**不是**改金标本。
3. **不许拿实现反塑金标本。** 包括"挑一个正好能解析对的字面量写法"（ADR-0002 方案 D，已否决）。

---

## 1. 🔴 口径冻结清单（改一个 = 全部判据作废）

`scripts/engine/mvp_config.gd` 顶部已有不变量自检，被改动当场抛错。

| 参数 | 冻结值 | 备注 |
| --- | --- | --- |
| `kr_mode` | **`"tier"`** | `"flat"` 仅作回归/敏感性口径，一行可切回；生产/金标本/GDD §10.1 统一 tier（ADR-0001） |
| `salvage_on` | `false` | |
| `ntower_mode` | `"current"` | 兜底① `"max"` 只用于敏感性测试 |
| `synergy_on` | `false` | Syn 乘区已摘除（Q-C6），恒为 1.0 |
| `link_rule` / `f` | `"substantial"` / **0.65** | GEO6 方案 A |
| `hp_growth` / `hp_base` | **1.42** / **16.0** | |
| `focus_per_layer` / `focus_full` | **0.06** / `false` | |
| `pity` | `true` | |
| `softcap_decay` / `reinf_cap` | 1.03 / 100 | 衰减不归零 |
| `tower_stack_exp` | 0.6 | |
| `allin_mult` / `allin_share` | 1.6 / 0.60 | |
| `crossfire` | 1.25（N=2）/ 1.50（N=6） | N=1 → 1.00 |
| `aux_tau` / `aux_cap` / `aux_mode` | 8.0 / 1.5 / `"global"` | |
| `use_empowerment` | `false` | |
| `coverage_mode` | `"path"` | MVP 用路径常量 0.78 / 0.95，不走几何 |
| `link_min_level` | 3 | 双向门槛 `h ≥ 3` |
| `κ_r` 基准 / 终档 | 0.045 / 0.050 | tier 口径：中性塔取基准档 |
| `wave_dur(w)` / `spawn_window(w)` | `28.0 + 2.2w` / `0.30 / 0.60 / 1.0` | 改它等于改 HP 曲线分母 |
| `MAX_FRAME_REAL_DT` | **0.25** | 单帧计入减速预算的实时秒上限（GDD v1.2 Q-S3-B，工程健壮性夹子，非平衡参数） |
| 视口 / stretch | **1920×1080** + `mode="canvas_items"` + `aspect="expand"` | GDD v1.2 Q-S3-C 拍板（基准屏，抽屉 614.4 = 32%）；`shop_layout.gd` 的 `maxf(560, 0.32×屏宽)` 是随动算尺不是独立口径，不得删 |
| MC `seed` / 局数 | **20260930** / **300** | |
| 塔数值表 | `scripts/data/tower_data.gd` | 🔴 SSOT，禁止在引擎侧二次定义 |

---

## 2. 🔴 浮点可移植性（N1 / N2 —— 全工程强制，ADR-0002 已拍板）

> 这两条是切片2 用 2.0pp 的起飞率偏差换来的，**不遵守就会在决定性跑里全绿、在 MC 里翻车**。
> 典型症状：决定性跑逐波全对，MC 起飞率低 1~2pp，某些局起飞波差 2 波。

### N1 —— 整数指数的幂必须走 `FpPow.pow_int()`

```gdscript
const _FpPow := preload("res://scripts/engine/fp_pow.gd")

# ✅ 指数恒为整数
_FpPow.pow_int(kappa, int(lv))                  # 软 cap κ^lv / κ^cap / decay^(lv−cap)
_FpPow.pow_int(1.0 + float(kr[i]), int(E[i]))   # 共鸣 (1+κ_r)^E
_FpPow.pow_int(float(cfg["hp_growth"]), w - 1)  # 血量 hp_growth^(w−1)
_FpPow.pow_int(10.0, nd)                        # 10^nd
_FpPow.pow_int(2.0, -52)                        # ULP

# ✅ 指数可能是小数 → pow_py()（只在指数确为整数时改道 pow_int）
_FpPow.pow_py(float(h[i]), float(cfg["tower_stack_exp"]))   # 塔层 h^0.6

# ❌ 禁止
pow(kappa, float(lv))
```

- 为什么：Godot（MSVC 构建）`pow()` 在整数指数上与 Python `**` **85% 的采样点差 1 ULP**
  （`1.06**6`：Python `1.4185191122560004` / Godot `1.4185191122560006`，真值恰为 `1.418519112256`）。
  Python 侧对精确值 **0/2025 不一致** = 恒为正确舍入。非整数指数本来一致，**不用管**。
- 实现只依赖 IEEE-754 双精度与 Dekker 分裂常数，**与 libm 无关** → 换平台/换 Godot 版本只会更稳。
- `pow_int` 有二级缓存 `{底数: {指数: 值}}`，热路径上无分配。

### N2 —— 移植 Python 的 float `sum()` 必须走 `FpSum.sum_py()`

```gdscript
const _FpSum := preload("res://scripts/engine/fp_sum.gd")

# ✅
var subtotal := _FpSum.sum_py(dps_list)     # sum(p["dps"] for p in per_tower)
# ❌ 禁止
var subtotal := 0.0
for p in per_tower: subtotal += float(p["dps"])
```

- 为什么：CPython 3.12+ `sum()` 对 float 走 **Neumaier 补偿求和**快路径（双累加器），
  它对**同一多重集与次序无关**；朴素 `+=` 不是。贪心 AI 会为「升级 S3」和「升级 S5」各算一次 subtotal，
  两者逐塔 dps 是同一多重集、只换位置 —— 朴素累加让二者差 1.4e-14，**并列候选被末位噪声翻转**，
  一个塔位的差别被后续 16 波复利放大 → 起飞波 13 → 15。
- 整数序列（`sum(attach.values())` 之类）**不受影响**，照常累加。

### N3（已知债务，不强制但要知道）

- Godot 的**浮点字面量解析不是正确舍入**，且成败与位数**非单调**
  （`186.26806084384762` 错、`186.268060843847620` 对、`3.07925140603429918e+03` 又错）。
  → 只影响测试金标本。金标本导出统一用 **`%.17e`**（`tools/export_golden_slice2.py::gd_float`）；
  逐波原始列断言用 `TOL_ROW = 1e-15`（实测最大偏差 **1.712e-16**，比 1e-6 验收线紧 9 个数量级）。
- 运行时只用 `1.42` / `0.045` / `1.03` / `0.6` 这类短字面量，实测全部解析正确 → **不影响引擎**。
- 切片1 的 `tests/golden_reference.gd` 仍是 `%.17g`（17 位），同类噪声风险；切片1 在 1e-15 下全过，暂不改。

---

## 3. 🔴 Python 语义移植规则

| # | 规则 | 说明 |
| --- | --- | --- |
| P1 | **RNG 用 `PyRandom`，不用 `RandomNumberGenerator`** | 金标本 MC 是 `random.Random(seed)` = MT19937 + `genrand_res53`；Godot 是 PCG32，序列不同起飞率就会漂 |
| P2 | `random.choice(seq)` = `seq[_randbelow(n)]`，**不是** `seq[int(random()*n)]` | `_randbelow` 用 `getrandbits(k)`（消耗 1 个 uint32），后者消耗 2 个 —— 序列长度不同 |
| P3 | `random.choices(pop, weights, k)` = `bisect(cum_weights, random()*total, 0, n-1)` | 累积权重 + 二分，边界语义照抄 |
| P4 | `round()` 是 **banker's rounding**（`round(2.675, 2) == 2.67`） | GDScript `round()` 是四舍五入远离零且返回 float。只在".5 恰落在十进制中值"时有别，`stats.gd` 已按 CPython `_Py_dg_dtoa` 移植 |
| P5 | `max(seq, key=...)` **并列取第一个** | GDScript 无 `argmax` → 用**严格 `>`** 比较实现；写成 `>=` 会取到最后一个，改变选择 |
| P6 | Dictionary 迭代顺序 = 插入顺序（与 Python 3.7+ 一致） | 浮点加法次序因此可复现；**不要**为了"好看"去排序或换容器 |
| P7 | `sorted()` 是**字典序** | `draw_offers` 的保底挤出用到了它，必须照做（ShopAI S1） |
| P8 | Python `set` → Dictionary（`name → true`） | 只用于成员判定，语义等价 |

---

## 4. Godot 语言陷阱（每条都曾静默改变结果）

| # | 陷阱 | 正确写法 |
| --- | --- | --- |
| G1 | `int / int` 是**整数除法** | 期望 float 的除法两侧显式 `float()`（`interval`、`lv - cap` …） |
| G2 | `**` 不是运算符 | 用 `pow()` / `FpPow.pow_int()`；底数指数都转 float |
| G3 | `static var` 跨场景共享 | 只缓存纯函数结果，不放可变状态 |
| G4 | 热路径分配 | `FpPow` 的 dd 乘法全部内联成局部变量，不分配 Array —— 否则 MC 300 局慢到分钟级 |
| G5 | 类型推不出来 | `absf()` / `floor()` / 无类型 Variant 的 `.size()` 必须显式标注（`: float` / `: bool`）或就地使用 |
| G6 | headless `--script` **没有** `global_script_class_cache.cfg` | 全局 `class_name` 类型解析不到 → 一律 `preload()`，本文件自己的 `class_name` 也不在自身作用域内 |
| G7 | `String % …` **不支持 `%e` / `%g`** | 要用 `String.num(v, 17)` |
| G8 | 十六进制字面量不能带小数点 | `0x1.7489…p7` 是语法错误，别试 |

---

## 5. 分层编码标准

| 层 | 状态 | 规则 |
| --- | --- | --- |
| `scripts/engine/`（core） | ✅ 已建 | 纯函数、无副作用；**热路径零分配**；不持有游戏状态（`compute_dps()` 只读 `player_state`） |
| `scripts/data/` | ✅ 已建 | **SSOT**：塔数值 / 卡池权重只在这里定义，引擎侧禁止二次定义 |
| `scripts/geo/` | ✅ 已建 | 定稿地图 = 方案 A；几何只算 Coverage / 链接，不参与伤害乘区 |
| `scripts/ui/` | ✅ 已建（`boot.gd`） | **不持有游戏状态**，只读 + 发信号 |
| `scripts/gameplay/` | 🟡 后续切片 | **数据驱动**：数值进 `tower_data.gd` / `mvp_config.gd`，禁止硬编码；配置保持可打印/可序列化（Dictionary 里**不塞 Callable**） |
| `scripts/ai/` | 🟡 后续切片 | 可调试：枚举顺序 = 决策顺序，任何"取最大"都要能打印出候选与比值 |
| `scripts/network/` | 🟡 后续切片 | 服务端权威；客户端只发意图 |
| 通用 | | 注释里写明**金标本出处（文件:行号）**；不确定引擎 API 就标注知识缺口上报，**不臆造 API** |

---

## 6. 发现"对不上"怎么办（流程，不许跳步）

1. 先判定是不是**浮点噪声**：决定性跑逐波是否全对？MC 起飞波是否逐局吻合？
   决定性跑全对 + MC 偏差 → 几乎必是 N1/N2（末位翻转），按第 2 节查。
2. 判定是**口径分歧**（参数/公式/次序理解不同）→ **不许改任何冻结参数，不许改金标本** →
   在 `docs/architecture/adr-000N-*.md` 写 ADR：上下文（含二分定位证据链）/ 备选方案（至少 3 个，含"改金标本"这个必须被否决的选项）/ 决定 / 后果 → **上报主理人拍板**。
3. 参考：ADR-0001（`kr_mode` tier vs flat）、ADR-0002（浮点可移植性）。两条都已拍板。

---

## 7. 提交前自检（一行命令，必须退出码 0）

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# 全量（切片1–5，含 MC 300 局，约 1.5 分钟）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd

# 只跑切片N（注意：参数必须以 "slice" 开头才会被过滤，写 "-- only=slice5" 会跑全量）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice1
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice2
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice3
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice4
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice5
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice6
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice7
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- slice8

# 切片3 真机场景冒烟（真实帧，会真等 10 实时秒做预算实测，约 15 秒）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_slice3_scene_smoke.gd
# 切片4 真机场景冒烟（商店接线 · 三类卡分流 · 锁定 · 波次信号，约 20 秒）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_slice4_scene_smoke.gd
# 切片5 真机场景冒烟（真实刷怪 · 弧长推进 · 减速隔离 · 安全窗静止；headless 跳过截帧）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd
# 切片5 窗口截帧（真出图 → docs/phase3/slice5-wave.png；加 "-- split" 出减速态分屏帧）
"$GODOT" --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd
```

对照检查项：

- [ ] 退出码 **0**，且日志里九段汇总齐全：`通过 222 项`（切片1）/ `通过 2228 项`（切片2）/ `通过 142 项`（切片3）/ `通过 123 项`（切片4）/ `通过 302 项`（切片5）/ `通过 41 项`（切片6）/ `通过 31 项`（切片7）/ `通过 92 项`（切片8，含续3 可玩 MVP 胜负结算 21 项）/ `T1 仇恨 汇总：通过 56 项`（T1 塔死亡玩法批次，含仇恨激活 + 塔死亡 + 修复入口）
- [ ] 定稿判据链 16 条逐条对上（A 起飞 W8 / B 起飞 W12 / B÷A **0.458** / cross **16-4** / flips **1** /
      三阶段健康 A **2.4** / B **3.0** 单调上升）
- [ ] MC：**A 69.3%（208/300）/ B 91.3%（274/300）**，中位起飞波 A W8.0 / B W13.0；
      MC 前 20 局逐局起飞波 A/B **逐位相同**（这是抓 1 ULP 回归最灵敏的探针）
- [ ] 决定性跑逐波原始列最大相对偏差 **≤ 1e-15**（实测 1.712e-16，验收线 1e-6）
- [ ] 新代码里没有裸 `pow(`（整数指数）、没有 float 序列的 `+=` 求和、没有裸 `RandomNumberGenerator`
- [ ] 🔴 切片4 额外确认：`shop_ai.gd` **零修改**（金标本逐位对齐产物）；三类卡分流（建筑 12 / 单塔 9 / 全局 10 分）逐条对上
- [ ] 🔴 切片5 额外确认：`wave_sim.gd` / `shop_ai.gd` **零修改**（mtime + 内容探针 + MC 逐位复现三重证据；项目暂无 git）；等价三件套 PASS（[A] W1–W20 逐波 |d|=0 · [B] DPS 扫描 90 组且 ≥10 组非平凡 · [C] delta 粒度 9 档）
- [ ] 🔴 切片5 时间轴红线：`wave_director.gd` 无墙钟/帧计数/`Timer`（单测源码探针）；安全窗 paused → `t_wave` Δ=0
- [ ] 🔒 切片6 额外确认：`wave_sim.gd` / `shop_ai.gd` / `corebound_sim_v03.py` **零修改**（git diff 证据）；`disabled` 占位 MVP 恒 false → DPS 逐位零影响（AC-S6-1）；断输出不断链（AC-S6-2：E/κ/κ_r 不变 + 全局乘区不变）；硬约束「≥1 安全位」成立（AC-S6-3）；`tower_aggro_enabled` 默认 false（AC-S6-4）
- [ ] ✅ 切片7 额外确认：`wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` **零修改**（三原型+Elite 走独立 `wave_sim_proto.gd` / `run_loop_proto.gd`，金标本证据链纯净）；S5-D1 校准闸门三闸门全过（①B 起飞率 91.7%≥80% ②起飞点 W13∈W10-15 ③B/A 0.432<1）；AC-S7-1 proto=false 逐位等价金标本（9 波次）
- [ ] ✅ 切片8 额外确认：`shop_ai.gd` / `player_state.gd` 金标本路径 **零改动**（`invested` 只在玩家路线 `shop_runtime.gd` 记录）；Q-C3 原文落地（返还 50% 向下取整 + 装配卡全销毁 + I-9 二次确认 CanvasLayer 140 自定义 Control 禁 AcceptDialog + 仅安全窗 T-C1/E16）；🔴 兜底① κ 不回升（`n_hist_max` 只增不减，AC-S8-2）；弃卡全销毁腾槽无返还（AC-S8-3）；卸下改投降 1 层（AC-S8-4）；🟡 **I-7 塔位点选**（AC-S8-7）：Tag 合法性 `can_attach_card`/`get_legal_hosts`（D-8① 禁异 Tag · 中性塔收任意）· reinforce 改投点选塔（2 次输入）否则默认主塔（1 次输入）· D-TB-6 强制点选（主塔拒→`选择宿主塔`高亮合法副塔）· 无宿主→H8 `无塔接收该 Tag` · 点选每波清空
- [ ] ✅ 切片8·C2 智能高亮额外确认：H2 Tag 协同脉冲 / H3 +1 档位角标 / H5 层数→下一层 / H6 κ 折价预告（含不可逆披露）/ H7 槽位占用事实 / H9 ΔDPS 相对增量 %（读 `damage_engine` 纯函数，SR-1）全部只读 `highlights()` / `slot_usage()`；🔴 **SR-R2 只标事实**（grep 推荐/最优/best/recommend/suggest 在商店源码零命中，仅规则注释 + 命中测试变量）；SR-6 事件驱动刷新（overlay 订阅 shop_changed/run_changed，不每帧调 `evaluate_delta`）；✅ **H10 暴露度 UI 已落地**（T1 玩法① · 方案A 显式图标：决策期空塔位标 ⚔红 X「会挨打」/ 🛡绿盾「安全」，`monster_layer.gd :: _draw_exposure_icons/_draw_cross/_draw_shield`；🔴 SR-R2 只标事实不标推荐；复用切片5 `slot_exposure` 4暴露/2安全数据地基，无新逻辑；切片5 场景冒烟 22/0 覆盖 monster_layer 全分支）
- [ ] 🟢 切片8续3·可玩 MVP 胜负结算额外确认：核心 HP **单一数据源**（`player.core_hp`，`WaveDirector` 漏怪扣血写回 player / `ShopRuntime` 只读 / `grant_wave_result` 不再二次扣血，AC-S8-9）；**胜利** = 打完 W20（`MAX_WAVE=20`）且核心未归零 → `run_won` 信号 + `victory` 标志（🔴 变量名不能与 signal `run_won` 同名 → 用 `victory`；🔴 判胜放在 `last_result` 记录真实 kills/scrap **之后** → W20 逐位等价零扰动，AC-S8-10b）；**失败** = 核心归零 → `run_lost`（E-W3 实时，AC-S8-10a）；结算覆盖层 `result_overlay.gd`（CanvasLayer 150 纯展示 + 重开/退出）；HUD 终局状态行 + 核心 HP 条低血量告警红
- [ ] 🔒 T1 塔死亡玩法批次额外确认：`wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` **零修改**（仇恨走独立镜像 `wave_sim_aggro.gd` / `run_loop_aggro.gd`，金标本证据链纯净）；`tower_aggro_enabled` 默认 false → `aggro=false` 与金标本逐位等价（AC-T1-3/4）；**仇恨只改路径不改 DPS 分配**（DPS 分配口径不变，只改怪物态 + 塔损耗）；塔状态**单一数据源 = `player.towers`**（实时版与批处理镜像都改 `player.towers[i].hp/disabled` → `dps_only` 重算一致 → 逐位相同，AC-T1-9；曾踩"双份塔状态"坑已修）；Q-T2 塔 HP `HP0×h^0.6`（复用 `tower_stack_exp`）· Q-T3 机会型仇恨 `AGGRO_R=9.0`/`AGGRO_EXIT=10.8` 迟滞带 · Q-T4 Disabled 中间态（断输出不断链，仍占塔位供 `h_j`）；**修复入口 Q-T4/Q-T8**（`repair_tower` 修复 `ceil(0.30×累计投入)` 回满 HP 保留装配卡 · `salvage_disabled_tower` 被动拆除返还 0% · 放着不管 no-op · E-T4 永不死锁 · E-T2 `list_disabled_towers` 合并弹窗，AC-T1-10~12）；✅ **修复入口 UI 弹窗已落地（方案B 重决策面板入口）**：安全窗 `_heavy_panel` 加「处置受损塔 (N)」按钮（有受损塔才亮 + 红点计数，SR-R2 只标事实）→ `repair_requested` 信号（TimeDirector 信号总线）→ `ShopController._show_repair_dialog` 弹多塔处置弹窗 `disabled_tower_dialog.gd`（CanvasLayer 140 自定义 Control，每座一行三选一：修复/被动拆除/放着不管；修复按钮积分不足置灰 E-T4；处置后 `refresh` 重算剩余列表，空则自动关闭；数据源 `snapshot().slots[].disabled`，AC-T1-15 守护）；🔴 headless 闭包标量回写坑 → dps 用单元素 Array 可变容器（引用捕获）；✅ **V-1 ATTRITION=1.50 + WARMUP=2 起手保护已定稿**（300 局 MC 扫参，AC-T1-13）；✅ **V-2 起飞率 A 破线已诊断定稿**（`protect_core` 对照：A 无保护 0.393 / A 保主力塔 0.583 / B 0.883；根因 = 单核零冗余 × 全暴露位 × AI 不保塔三重结构性碰撞，非数值失衡；处置 = 承认单核高风险画像为设计预期，不动红线/金标本，AC-T1-14）；✅ **肉盾塔 Bulwark 玩法② 已诊断定稿（2026-10-07，涌现策略 + ①理想肉盾建模）**：肉盾塔 = 涌现策略（机制已存在：仇恨选最近未 Disabled 塔 → 暴露位塔先挨打、怪物锁定后停下不前进不漏怪 → 锁仇恨保后排；缺口"肉盾身份"HP/DPS 脱钩在涌现策略下**不新增卡种**，金标本零改动）；诊断参数 `bulwark` 贯穿 `wave_sim_aggro._relocate_carry_to_safe`/`run_loop_aggro`（默认 false 金标本零改动，AC-T1-16 守护重定位 + 零改动）；`tests/scan_bulwark.gd` 300 局：A 无保护 0.393 / A 隐身 0.583 / **A 理想肉盾 0.623（≥0.60 破线）** / B 0.883 → 保塔策略对单核流有效、肉盾塔玩法成立（玩家能救 A），真放安全位 DPS 代价有限（Δ+0.04）；**可读性 UI 已落地（R-T4）**：战斗态在正被仇恨锁定的塔上标橙环 `monster_layer.gd :: _draw_under_attack`（数据源 snapshot `state==AGGRO_TOWER`+`target_slot`；金标本口径零绘制）；V-4 定稿：暴露度惩罚不过重，定稿数值零改动）
- [ ] 🔴 **玩家路线发牌池口径**（D-4/D-2，v1.3）：金标本 `CARD_NAMES` 是 **7 张**（AI 路线，含 RerollD，MC 来源，不动）；**玩家路线发牌池 = 7 − RerollD = 6 张**（`shop_runtime.player_card_names()` 由金标本派生，有放回抽 3，恒 3 位可重复）。⚠️ 别与**设计卡池 12 张**（card-system §7.3，13→12 移除 G2 `SupplyChain`）混淆——前者是金标本运行时实际抽的 6 张，后者是设计意图的 12 张，两个口径都对，只是作用层不同
- [ ] 完整输出存档到 `docs/phase3/sliceN-headless-run.log`

---

## 8. 证据与产物索引

| 产物 | 路径 |
| --- | --- |
| 自测入口（SceneTree + `quit(exit_code)`） | `tests/run_tests.gd` |
| 切片1 断言套件（222 项） | `tests/test_suite.gd` |
| 切片2 断言套件（2006 项） | `tests/test_suite_slice2.gd` |
| 金标本期望值常量 | `tests/golden_reference.gd`（`%.17g`）、`tests/golden_slice2.gd`（`%.17e`） |
| 金标本导出脚本 | `tools/export_golden_reference.py`、`tools/export_golden_slice2.py` |
| 切片1 报告 / 日志 | `docs/phase3/slice1-headless-verify.md` / `slice1-headless-run.log` |
| 切片2 报告 / 日志 / 金标本 JSON | `docs/phase3/slice2-headless-verify.md` / `slice2-headless-run.log` / `slice2-golden.json` |
| 切片3 架构 / 报告 / 日志 / 截图 | `docs/architecture/slice3-shop-ui-architecture.md` · `docs/phase3/slice3-verify.md` / `slice3-full-run.log` / `slice3-scene-smoke.log` / `slice3-godot47-api-probe.log` / `slice3-skeleton.png` |
| 切片3 自测 / 场景冒烟 / API 探针 | `tests/test_suite_slice3.gd`（142 项）· `tests/run_slice3_scene_smoke.gd`（25 项）· `tools/probe_godot47.gd` |
| 切片3 布局探针（Q-S3-C · 1920 实测） | `tools/probe_layout_1920.gd` / `docs/phase3/slice3-layout-1920-probe.log` |
| 切片3 五态时钟纯逻辑 / 适配层 | `scripts/engine/time_state_machine.gd`（零副作用）· `scripts/ui/time_director.gd`（唯一写 `time_scale`/`paused`） |
| 切片4 架构 / 报告 / 日志 / 截图 | `docs/architecture/slice4-shop-wiring-architecture.md` · `docs/phase3/slice4-verify.md`（§6 = D-1…D-9 拍板留档）/ `slice4-full-run.log` / `slice4-baseline-run.log` / `slice4-unit-run.log` / `slice4-scene-smoke.log` / `slice4-scene-smoke-windowed.log` / `slice4-slice3-smoke-regression.log` / `slice4-shop.png` |
| 切片4 自测 / 场景冒烟 | `tests/test_suite_slice4.gd`（123 项）· `tests/run_slice4_scene_smoke.gd`（46 项） |
| 切片4 接线层（唯一的桥 + 运行时） | `scripts/gameplay/shop_controller.gd`（Node·ALWAYS，桥；切片5 起波次驱动交给 WaveDirector）· `scripts/gameplay/shop_runtime.gd`（RefCounted，复用 ShopAI/WaveSim/SimPlayer/PyRandom） |
| 切片5 架构 / 报告 / 日志 / 截图 | `docs/architecture/slice5-wave-spawner-architecture.md` · `docs/phase3/slice5-verify.md`（§5 = S5-D1/D2/F1/F2 待拍板）/ `slice5-full-run.log` / `slice5-unit-run.log` / `slice5-scene-smoke.log` / `slice5-scene-smoke-windowed.log`（+`-split.log`）/ `slice5-slice4-smoke-regression.log` / `slice5-wave.png` / `slice5-wave-split.png` |
| 切片5 自测 / 场景冒烟 | `tests/test_suite_slice5.gd`（302 项，含等价三件套）· `tests/run_slice5_scene_smoke.gd`（22 项） |
| 切片5 刷怪层（时间轴权威） | `scripts/gameplay/wave_director.gd`（Node·ALWAYS，逐 tick 展开金标本循环）· `scripts/gameplay/monster.gd`（RefCounted 实体）· `scripts/ui/monster_layer.gd`（占位渲染） |
| 切片5 几何 / 怪物数据 SSOT | `scripts/geo/path_geometry.gd`（F-3：L=101 · `sample(s)` 二分 · ExposureArc）· `scripts/data/monster_data.gd`（三原型/Elite/v0/composition） |
| 切片6 验证报告 | `docs/phase3/slice6-verify.md`（T1 仇恨口径登记 + 暴露度数据地基 + `Disabled_i≡1.0` 占位落地；边界=不激活玩法） |
| 切片6 自测 | `tests/test_suite_slice6.gd`（41 项：AC-S6-1 disabled 占位零影响 · AC-S6-2 断输出不断链 · AC-S6-3 暴露度硬约束 · AC-S6-4 AGGRO 参数登记） |
| 切片6 占位落点 | `scripts/engine/player_state.gd`（`TowerState.disabled: bool = false`）· `scripts/engine/damage_engine.gd`（per_tower 末尾 `dps_i *= disabled ? 0.0 : 1.0`） |
| 切片6 拍板留档（设计侧） | `design/gdd/mechanics-tower-life-death.md` §0.2 切片6 落地留档 · `design/gdd/wave-spawner.md` v0.3（S5-D1/D2/F1/F2 拍板 + §2.6 仇恨状态机） |
| 切片7 验证报告 | `docs/phase3/slice7-verify.md`（S5-D1 校准闸门：三原型+Elite MC 300 过闸门，金标本零改动） |
| 切片7 自测 | `tests/test_suite_slice7.gd`（31 项：AC-S7-1 proto=false 逐位等价金标本 · AC-S7-2 确实换口径 · AC-S7-3 闸门①②③） |
| 切片7 批处理战斗结算（金标本不动） | `scripts/engine/wave_sim_proto.gd`（`simulate_wave_proto`，镜像 `WaveDirector._substep`）· `scripts/engine/run_loop_proto.gd`（MC 重扫运行器，shop_ai 金标本不变） |
| 切片8 验证报告 | `docs/phase3/slice8-verify.md`（拆除回收 `Salvage` Q-C3 原文落地 + I-9 二次确认 + κ 不回升守护，金标本零改动） |
| 切片8 自测 | `tests/test_suite_slice8.gd`（**92 项**：AC-S8-1 逐塔投入追踪 · AC-S8-2 拆除返还 50%+全销毁+κ 不回升 · AC-S8-3 弃卡 · AC-S8-4 卸下改投 · AC-S8-5 I-9 弹窗组件 · AC-S8-6 金标本零改动 · AC-S8-7 I-7 塔位点选 · AC-S8-8 C2 高亮 · **AC-S8-9 核心 HP 单一数据源 · AC-S8-10a 失败 run_failed · AC-S8-10b 胜利 run_won**） |
| 切片8 结算核心（玩家路线，金标本不动） | `scripts/gameplay/shop_runtime.gd`（`salvage_tower` / `discard_card` / `unequip_downgrade` / `preview_salvage` + `pending_cost` 平行数组 + `invested` 累加；续3：`core_hp` 迁到 `player`，`grant_wave_result` 只入积分不扣血）· `scripts/engine/player_state.gd`（`TowerState.invested` + 续3 `core_hp`/`core_hp_max` 单一数据源）· `scripts/engine/sim_player.gd`（续3 按 `cfg.core_hp` 初始化核心 HP） |
| 切片8 I-9 二次确认弹窗 | `scripts/ui/salvage_confirm_dialog.gd`（CanvasLayer 140 · 自定义 Control 禁 AcceptDialog · `show_confirm(title,body,on_confirm)`）· `scripts/gameplay/shop_controller.gd`（`_on_salvage_requested` 接线 + 弹窗组装 + SafeWindow 守卫注入） |
| 切片8续3 可玩 MVP 胜负结算 | `scripts/gameplay/wave_director.gd`（`MAX_WAVE=20` + `run_won` 信号 + `victory` 标志 + 判胜放 `last_result` 后保等价）· `scripts/ui/result_overlay.gd`（CanvasLayer 150 结算覆盖层 · 胜负展示 + 重开/退出）· `scripts/gameplay/shop_controller.gd`（`_on_run_lost`/`_on_run_won` 接弹窗 · `_on_restart_requested` 重开一局）· `scripts/ui/hud.gd`（终局状态行）· `scripts/ui/core_hp_bar.gd`（`bind_controller` 实时读 player + 低血量告警红） |
| T1 塔死亡玩法批次（仇恨激活 + 被动移除 Destroyed + 修复入口 + 肉盾塔） | `scripts/gameplay/wave_director.gd`（`tower_aggro_enabled` 开关 + `_apply_aggro` 仇恨状态机 + `_damage_tower` 塔死亡 → disabled + DPS 重算 + `tower_destroyed` 信号 + snapshot 暴露 towers/state/target_slot）· `scripts/engine/wave_sim_aggro.gd`（仇恨版批处理镜像，塔状态单一数据源 = `player.towers`；`bulwark` 诊断 `_relocate_carry_to_safe` 主力塔重定位安全位）· `scripts/engine/run_loop_aggro.gd`（仇恨版 MC 重扫运行器，`bulwark` 贯穿）· `scripts/gameplay/shop_runtime.gd`（修复入口：`repair_tower`/`preview_repair`/`salvage_disabled_tower`/`list_disabled_towers` + `REPAIR_RATE=0.30`；snapshot slots 带 disabled）· `scripts/data/monster_data.gd`（`HP0=120` + `tower_hp()` + `AGGRO_R/AGGRO_EXIT/ATTRITION`）· `scripts/engine/player_state.gd`（`TowerState.hp/hp_max`）· `scripts/ui/disabled_tower_dialog.gd`（修复入口 UI：多塔处置弹窗，CanvasLayer 140 自定义 Control，每座三选一）· `scripts/ui/shop_overlay.gd`（重决策面板「处置受损塔 (N)」按钮 + 红点计数）· `scripts/ui/monster_layer.gd`（H10 暴露度图标 `_draw_exposure_icons` 决策期红X/绿盾 + 肉盾塔可读性 `_draw_under_attack` 战斗态橙环）· `tests/scan_protect_core.gd`（V-2 诊断）· `tests/scan_bulwark.gd`（肉盾塔有效性诊断，300 局四组对照）· `tests/test_suite_t1_aggro.gd`（**77 项**：AC-T1-1~9 仇恨激活+塔死亡 · AC-T1-10~12 修复入口 · AC-T1-15 修复入口 UI 数据源 · AC-T1-16 肉盾塔 bulwark 重定位+金标本零改动 · AC-T1-13 V-1 ATTRITION=1.50+WARMUP=2 定稿 · AC-T1-14 V-2 protect_core 诊断留档） |
| 切片4 拍板留档（设计侧） | `design/gdd/shop-reroll.md` §9.2（v1.3，D-1~D-7 拍板）· `design/gdd/card-system.md` A4/§7.3（v1.1.6，D-4 卡池 13→12） |
| 口径 / 浮点决策记录 | `docs/architecture/adr-0001-kr-tier-vs-flat.md`、`adr-0002-float-portability.md` |
| 引擎 | `scripts/engine/{damage_engine,wave_sim,shop_ai,run_loop,stats,softcap,mvp_config,player_state,sim_player,py_random,fp_pow,fp_sum,time_state_machine}.gd` |
