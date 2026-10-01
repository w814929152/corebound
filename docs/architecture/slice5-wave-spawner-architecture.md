# 切片5 · 真实刷怪战斗循环 —— 架构与接线清单

- **作者**：程基岩（工程主理人）
- **引擎**：Godot `v4.7.2.stable.official.ed1daf0bf`（沿用切片3/4 实测结论）
- **上游**：`design/gdd/wave-spawner.md` **v0.2**（**本切片唯一设计权威**；D-W1~D-W7 全部已拍板；§7 交接点 ①–⑤；§9 AC-W1~W8）
- **依赖**：切片2 `scripts/engine/wave_sim.gd`（**金标本，本轮零修改**）· `mvp_config.gd`（冻结参数）· `damage_engine.gd`（波首一次 `dps_only`）· 切片3 五态时钟（`time_director.gd`）· 切片4 商店接线（`shop_controller.gd` 信号）
- **状态**：🟢 全量自测 **222 + 2228 + 142 + 123 + 302 = 3017 项断言 / 0 失败 / 退出码 0**；场景冒烟 22 项全过（headless + 窗口各一遍）；切片4 冒烟 46 项回归全过；MC 判据链逐位不变（A 69.3% / B 91.3%）；**实时推进与金标本逐位等价（公差 1e-9 实测 |d|=0.000e+00）**

---

## 0. 摘要（给赶时间的人）

| 验收项 | 结果 |
|---|---|
| **逐位等价**（本切片最硬一条） | ✅ [A] 真实贪婪构筑 W1–W20 逐波：kills/leaked/scrap/dps/core_damage 全部 \|d\|=0；[B] DPS 扫描 90 组（5 波 × 18 档强度）全等价，其中 **20 组落在非平凡「部分击杀」中间态**；[C] delta 粒度无关性 9 档（1.0→0.008s）全等价 |
| F-3 路径几何闭合 | ✅ `d_path` 6.00/8.00/5.00/8.00/10.82/13.00、`ExposureArc` 21.67/8.25/14.96/8.25/0/0、并集 53.13、L=101.0（AC-W1/W2） |
| W-C3 时间轴红线 | ✅ 波次时钟只吃缩放 delta；`t_wave` 与金标本 `time` 走同一条 `+= DT` 累加序列；无墙钟/帧计数/Timer（源码探针断言）；安全窗 `paused` → delta=0 → `t_wave` 完全静止（Δ=0.000000） |
| 弧长参数化移动 | ✅ `s += v₀·m_spd·dt`（以 `t_remain` 反推），`sample(s)` 二分 O(log n)；冒烟实测 5.05 → 21.21 弧长 → 世界位移 11.54 unit；🔴 未用 `PathFollow2D` |
| 伤害分配 W-A1~W-A4 | ✅ 聚合 DPS 池 → `t_remain` 升序稳定排序（= 金标本正序遍历）→ 贪心填满 + 溢出结转；AC-W7 逐项断言 |
| 漏怪 / 失败 | ✅ 漏怪 −50 HP；1000 HP ÷ 50 = 20 只漏怪即败；E-W3 核心 ≤0 立即中断本波（AC-W6） |
| 三原型 + Elite 骨架 | ✅ 结构完整落地（原型表/Elite 保守系数 c(w)/出生序列），🔴 MVP 开关恒 false = 金标本等价口径；偏离登记 **S5-D1** 待拍板 |
| 金标本零改动 | ✅ 无 git，用三重证据：mtime（wave_sim.gd=03:40 / shop_ai.gd=03:05，早于本轮全部改动）+ 内容探针断言 + MC 逐位复现 |
| MC 判据链不回归 | ✅ A 69.3%（中位 W8.0）/ B 91.3%（中位 W13.0）逐位不变；B 总 DPS 4991135.6102341395 与金标本一致 |

**本轮登记的新分歧/发现（🔴 未擅改口径，待主理人拍板）**：S5-D1 / S5-D2 / S5-F1 / S5-F2，见 §6 与 `docs/phase3/slice5-verify.md` §5。

---

## 1. 本轮范围

| 做 ✅ | 不做 ❌ |
|---|---|
| ① `PathGeometry` + 暴露表（F-3 闭合） | 美术资产（占位节点渲染） |
| ② 波次时钟 `t_wave`（W-C3 红线） | 塔仇恨真实生效（骨架落地，`tower_aggro_enabled=false`） |
| ③ 弧长参数化移动 + `sample(s)` 反查 | aggro 实际调参（🔒 T1 之后） |
| ④ 伤害分配 W-A1~W-A4（与金标本逐行对齐） | 存档 / 音效 / 遥测 |
| ⑤ 三态怪物状态机骨架 + 开关组 | D-8 调试跳波（**本轮删除**，由 WaveDirector 接管） |
| WaveDirector 接管波次推进（删 shop_controller 最小驱动器） | `d_path`/`ExposureArc` 参与玩法（MVP 只注册数据，GDD §2.3） |
| 切片5 单测 302 项 + 场景冒烟 22 项 | |

---

## 2. 分层与数据流

```
┌──────────────────────────────────────────────────────────────────────┐
│ scripts/engine/（纯函数 · 零副作用 · 金标本）                          │
│   wave_sim.gd      🔴 零修改。WaveDirector 复用其 DT / monster_stats   │
│   damage_engine.gd 波首一次 dps_only（波内恒定 → 等价性前提）           │
│   mvp_config.gd    冻结参数（D(w)/spawn_window/leak_damage/...）       │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 复用（不重定义任何冻结数值）
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ scripts/geo/ + scripts/data/（SSOT · 静态预计算）                      │
│   path_geometry.gd  ★新 F-3：PATH/CUM_LEN/L=101/CORE_POS；            │
│                     sample(s) 二分；exposure_intervals/arc；union_arc  │
│   monster_data.gd   ★新 三原型/Elite SSOT（m_hp/m_spd/m_dps、         │
│                     composition、spawn_sequence、elite_conserve、v0）  │
│   geo6.gd           SLOTS6 塔位（既有）                                │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 纯数据读取
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ scripts/gameplay/wave_director.gd   ★新 (Node · ALWAYS) ← 时间轴权威   │
│   波次状态机 IDLE→SPAWNING→FIGHTING→SAFE_WINDOW                        │
│   _process → advance(dt)：acc += 缩放dt；凑满 DT=0.1 跑一个 _substep    │
│   _substep = 刷新 → 稳定排序 → 贪心伤害 → 前进/漏怪（= sim 循环体逐行）  │
│   信号：wave_result / monster_spawned / monster_killed /               │
│         monster_leaked / run_lost                                      │
│   monster.gd ★新 (RefCounted)：hp/t_remain/proto/elite/state           │
└───────────────┬──────────────────────────────────────────────────────┘
                │ wave_result → 波次结算（收入/进安全窗）；run_lost → 失败
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ scripts/gameplay/shop_controller.gd（改）                              │
│   − 删：最小波次驱动器（wave_elapsed 计时）+ debug_end_wave()（D-8）    │
│   + bind_wave_director(wd)：订阅 wave_result/run_lost；                │
│     wave 结算按 _realtime_is_golden_equivalent() 决定走实时结果还是     │
│     回退金标本（S5-D1 拍板前的保险丝，回退时打 [WARN]）                  │
└───────────────┬──────────────────────────────────────────────────────┘
                │ 只读 snapshot()
                ▼
┌──────────────────────────────────────────────────────────────────────┐
│ scripts/ui/（不持有游戏状态）                                           │
│   battle_shop.gd（改）：创建/注入 WaveDirector → MonsterLayer 接线      │
│   monster_layer.gd ★新：占位渲染 —— 5 段路径/核心/塔位+暴露红圈/        │
│                     怪物（按原型着色 + Elite 黄环），读 snapshot()      │
│   hud.gd（改）：删 D-8 按钮；+ 战况行（波次/态/t_wave/已出/杀/漏）      │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.1 逐位等价机制（本切片的核心论证）

因为 MVP 塔不死（`tower_aggro_enabled=false`）→ **波内 DPS 恒定**（波首 `dps_only` 一次）。于是金标本的批处理循环可以**逐 tick 展开**而不改变任何数值：

1. `advance(dt)` 把**被 `Engine.time_scale` 缩放后的 delta** 累进 `acc`；
2. 每凑满 `DT = 0.1`（`WaveSim.DT`，直接引用不复制）跑一个 `_substep()`；
3. `t_wave += DT` 与金标本 `time += dt` 是**同一条累加序列**（浮点累进误差逐位一致；不写 `k*DT`）；
4. `_substep()` 内部与 `simulate_wave` 循环体**逐行对应**：
   - 刷新条件 `t_wave >= spawned*interval − 1e-9`；
   - 集火按 `t_remain` 升序**稳定排序**——单一基准怪口径下出生越早 `t_remain` 越小（严格单调），稳定排序 ≡ 金标本的正序遍历；
   - 伤害 `dmg = dps * DT`，贪心填满 + 溢出结转（W-A3）；
   - 判死在前、`t_remain -= DT` 在后，`<= 0` 判漏（E-W5 含等号）；
5. 结束条件：E-W3 失败中断 / E-W1 全结算提前 / E-W2 `t_wave > D + t_reach + 1e-9` 残留怪直接移除（不扣血不给分）。

**等价性证据三件套**（`tests/test_suite_slice5.gd::_test_equivalence_vs_golden`）：
- **[A]** 真实贪婪构筑 W1–W20 逐波对照（kills/leaked/scrap/dps/core_damage 五指标 |d|=0）；
- **[B]** 单塔 DPS 扫描 90 组，覆盖 0 杀 → 部分击杀 → 全歼全程，**20 组非平凡**（0 < kills < N，证明探针有效）；
- **[C]** delta 粒度无关性：同一非平凡构筑喂 dt ∈ {1.0, 0.5, 0.25, 0.1, 0.05, 0.035, 0.025, 0.016, 0.008}，9 档全等价。

### 2.2 W-C3 时间轴红线落点

- `WaveDirector._process(delta)` 只吃 Godot 缩放后 delta；🔴 无 `OS.get_ticks_msec()`/帧计数/`Timer`（单测源码探针 `_src_has_no_wall_clock` 断言，且排除注释误报）。
- 安全窗用 `get_tree().paused`（🔴 SR-R5：`Engine.time_scale` 永不为 0）→ paused 帧 `dt = 0.0` → `acc` 不进 → `t_wave` 完全静止。GDD 原文写 `time_scale = 0`，设计意图（世界完全静止）相同，口径差异登记 **S5-D2**。
- `MAX_SUBSTEPS_PER_FRAME = 64`：窗口失焦回来大 delta 时的追赶夹子，只影响追帧速度，不影响数值口径。
- 减速隔离实测（窗口冒烟）：1.0× 比值 1.000；0.25×（W1 新手波）比值 0.251；同样 ≈1.6 实时秒，全速 Δt_wave=1.600s → 减速 Δt_wave=0.400s（比值 0.250）；安全窗 0.8 实时秒 Δ=0.000000。

### 2.3 三原型 + Elite 骨架（S5-D1）

`WaveDirector` 两个开关完整落地 GDD §2.5.3/§2.5.4：
- `prototype_split_enabled`：Rush/Swarm/Tank 出生序列（确定性轮转 Swarm→Rush→Tank，C-2 保量）+ `m_hp/m_spd` 分化；
- `elite_waves_enabled`：`is_elite_wave(w)`（每 5 波）→ `n_e = max(2, round(0.10N))`，保守系数 `c(w) = (N − 2.5·n_e)/(N − n_e)`，Elite 继承宿主原型速度（C-3 自动满足）。

🔴 **MVP 二者恒 false** = 单一基准怪 = 金标本等价口径——与「塔不死/仇恨不生效」同款处理：结构先落地，拍板后置 true 即生效。单测同时证明**两条口径确实不同**（W10 同构筑：金标本 杀0 漏24 vs 三原型+Elite 杀1 漏23），偏离登记待拍板而非悄悄二选一。

---

## 3. 新增/修改文件一览

| 文件 | 动作 | 说明 |
|---|---|---|
| `scripts/geo/path_geometry.gd` | ★新 | F-3 闭合：PATH/SEG_LEN/CUM_LEN/TOTAL_LEN=101/CORE_POS；`sample(s)` 二分；`exposure_intervals/arc`（解析圆-线段求交 + Neumaier 求和）；`union_arc`；`slot_exposure`；`arc_of_t` |
| `scripts/data/monster_data.gd` | ★新 | 三原型/Elite SSOT；`v0 = 101/10 = 10.10`；`composition`（C-2 保量）；`spawn_sequence`；`elite_conserve/elite_indices`；文件头登记 S5-D1/S5-F1 |
| `scripts/gameplay/monster.gd` | ★新 | RefCounted 怪物实体：`arc_s`/`pos`（弧长→世界坐标）、`reached()`（含等号）、`state_name` |
| `scripts/gameplay/wave_director.gd` | ★新 | 467 行，时间轴权威；§2.1–2.3 全部机制；`run_to_end()`（跑真实子步，非跳波） |
| `scripts/gameplay/shop_controller.gd` | 改 | 删最小波次驱动器 + `debug_end_wave()`；+ `bind_wave_director`/`_on_wave_result`/`_on_run_lost`；金标等价保险丝 |
| `scripts/ui/battle_shop.gd` | 改 | 创建/注入 WaveDirector；MonsterLayer 接线；`start_run(1)` |
| `scripts/ui/monster_layer.gd` | ★新 | 占位渲染（路径/核心/塔位/暴露红圈/怪物着色） |
| `scripts/ui/hud.gd` | 改 | 删 D-8 按钮；+ 战况行（读 `wave_director.snapshot()`） |
| `scenes/battle_shop.tscn` | 改 | + MonsterLayer 节点（`load_steps` 8→9） |
| `tests/test_suite_slice5.gd` | ★新 | 302 项断言，覆盖 AC-W1~W8 + 守恒 + 状态机 + 等价三件套 |
| `tests/run_slice5_scene_smoke.gd` | ★新 | 22 项冒烟：真实帧弧长推进/减速隔离/安全窗静止/下一波/截帧 |
| `tests/run_tests.gd` | 改 | 注册 slice5（支持 `only=slice5`） |
| `tests/run_slice4_scene_smoke.gd` | 改 | [2] 段 `debug_end_wave()` → `wd.run_to_end()`（切片4 冒烟 46 项回归全过） |
| 🔴 `scripts/engine/wave_sim.gd` | **零修改** | mtime 03:40 + 内容探针 + MC 逐位复现三重证据 |

---

## 4. 验证矩阵

| 套件 | 结果 | 产物 |
|---|---|---|
| 切片1 | 222 / 0 | `docs/phase3/slice5-full-run.log`（L919） |
| 切片2（含 MC） | 2228 / 0 · A 69.3% B 91.3% | 同上（L986–987, L1001） |
| 切片3 | 142 / 0 | 同上（L1146） |
| 切片4 | 123 / 0 | 同上（L1317） |
| **切片5** | **302 / 0** | 同上（L1695）+ `slice5-unit-run.log` |
| 切片4 场景冒烟回归 | 46 / 0 | `slice5-slice4-smoke-regression.log` |
| 切片5 场景冒烟（headless） | 22 / 0 | `slice5-scene-smoke.log` |
| 切片5 场景冒烟（窗口） | 22 / 0 | `slice5-scene-smoke-windowed.log` + `slice5-wave.png` / `slice5-wave-split.png` |

复现命令（control-manifest §7 口径）：

```bash
GODOT="…/Godot_v4.7.2-stable_win64_console.exe"
# headless 全量（3017 项）
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd
# 切片5 单跑
"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd -- only=slice5
# 窗口截帧（真出图）
"$GODOT" --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd
"$GODOT" --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd -- split
```

---

## 5. 已知风险与工程夹子

| # | 风险 | 缓解 |
|---|---|---|
| 1 | 波内 DPS 恒定是等价性的**唯一前提**；未来「波中买卡/塔被拆」会破坏它 | 文件头红字标注；届时等价口径需重新拍板（预期与 T1 一起做 DPS 重算节拍） |
| 2 | `MAX_SUBSTEPS_PER_FRAME=64`（6.4 游戏秒/帧）极端掉帧下追赶不及 | 只影响视觉追赶，波次结束判定由 `t_wave`/`limit` 决定，不影响结算 |
| 3 | S5-F2：整数取整残差使 Σ单怪 HP 偏离 N×HP_unit（+2.50% 无 Elite / +5.76% 有 Elite @W10） | 非 bug（GDD 表格自身取整）；单测上限放宽 ≤8%，逐波登记 |
| 4 | `run_to_end()` 与 D-8 的区别靠纪律维持 | 前者跑同一套子步（结果一致），后者是跳过结算——已删，且单测有源码探针防回归 |
| 5 | 无 git 仓库，金标本零改动缺 diff 证据 | mtime + 内容探针 + MC 逐位复现三重替代证据；**建议主理人考虑 `git init`** |

---

## 6. 待拍板分歧（详见 `slice5-verify.md` §5）

- **S5-D1**：GDD §2.5 三原型 + §2.5.4 Elite **不等价**于金标本（单一基准怪）。两口径都已落地，MVP 默认金标本等价，何时切 true 需主理人拍板。
- **S5-D2**：安全窗 GDD 写 `time_scale = 0`，项目用 `paused`（SR-R5 禁 time_scale=0）。设计意图同义，请追认口径。
- **S5-F1**：GDD §5.2 组成表加法错误（W4/W7/W19），代码按 C-2 保量式执行。
- **S5-F2**：取整残差导致 Σ单怪 HP ≠ N×HP_unit，GDD §2.5.2 的守恒是「系数级」而非「逐位级」。
