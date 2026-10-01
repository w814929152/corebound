# 切片5 验证报告 · 真实刷怪战斗循环

- **日期**：2026-10-01 · **作者**：程基岩（工程主理人）
- **范围**：GDD `wave-spawner.md` v0.2 交接点 ①–⑤ + AC-W1~W8 + 硬验收「实时推进与金标本逐位等价」
- **结论**：🟢 **全部验收项通过，退出码 0**；金标本零改动；MC 判据链逐位不变；4 项新分歧登记待拍板（未擅改口径）

---

## 1. 接线清单

| # | 接线点 | 状态 | 证据 |
|---|---|---|---|
| 1 | `battle_shop.gd` 创建 `WaveDirector` → `bind_runtime(controller.runtime)` → `bind_director(时钟)` → `controller.bind_wave_director(wd)` | ✅ | 冒烟 [0]「WaveDirector 已注入场景」 |
| 2 | `MonsterLayer` ← `bind_director(wd)` + `bind_time_director(时钟)`，挂在 `Battlefield` 下 | ✅ | 冒烟 [0]「MonsterLayer 已接线」+ 截帧 |
| 3 | 时钟 `wave_started(w)` → `WaveDirector.start_wave(w)`（开波：`monster_stats`/波首 `dps_only`/出生表） | ✅ | 冒烟 [0] 波号 W1 · 态 Spawning |
| 4 | `WaveDirector.wave_result(w, result)` → `shop_controller._on_wave_result`（收入入账）→ 时钟 `wave_end(w)` 进安全窗 | ✅ | 冒烟 [3]「击杀收入已入账」+ 态 SafeWindow |
| 5 | `WaveDirector.run_lost(w)` → `shop_controller._on_run_lost`（E-W3 失败） | ✅ | 单测 AC-W6/E-W3 语义断言 |
| 6 | `monster_spawned/killed/leaked` → `MonsterLayer` 占位渲染（运行时侧；I-3 渲染桥就绪） | ✅ | 截帧怪物沿路径分布 |
| 7 | `hud.gd` 战况行 ← `wave_director.snapshot()`（只读） | ✅ | 截帧左上战况（波次/态/t_wave/已出/杀/漏） |
| 8 | **删除** `shop_controller.debug_end_wave()` + HUD `[调试] 结束本波` 按钮（D-8） | ✅ | 源码无该函数/按钮；切片4 冒烟 46 项回归改用 `wd.run_to_end()` 全过 |
| 9 | `tests/run_tests.gd` 注册切片5（`only=slice5` 可单跑） | ✅ | `-- only=slice5` 实测 302/0 |

---

## 2. headless 全量回归（退出码 0）

命令：`"$GODOT" --headless --path D:/roguedemo --script res://tests/run_tests.gd`
日志：`docs/phase3/slice5-full-run.log`

| 段 | 套件 | 通过 | 失败 | 关键附注 |
|---|---|---|---|---|
| 1 | 切片1 伤害引擎 | **222** | 0 | L919 |
| 2 | 切片2 商店AI+MC | **2228** | 0 | A 起飞率 **69.3%**（208/300，中位 W8.0）；B **91.3%**（中位 W13.0）；B 总 DPS 4991135.6102341395 与金标本逐位一致（L986–987） |
| 3 | 切片3 五态时钟 | **142** | 0 | L1146 |
| 4 | 切片4 商店接线 | **123** | 0 | L1317 |
| 5 | **切片5 刷怪循环** | **302** | 0 | L1695；`[OK] …逐条一致 + 与金标本逐位等价` |
| — | **合计** | **3017** | **0** | 退出码 **0** |

场景冒烟回归：切片4 冒烟（含切片5 改动）**46/0**（`slice5-slice4-smoke-regression.log`）；切片5 冒烟 headless **22/0**、窗口 **22/0**。

---

## 3. 🔴 逐位等价对照表（公差 1e-9；实测全部 |d| = 0.000e+00）

### [A] 真实贪婪构筑（决定性 `shop_phase(rng=null)`）W1–W20 逐波

| 波 | N | dps | 金标本 杀/漏/分 | 实时 杀/漏/分 | kills | leaked | scrap | dps | core_dmg |
|---|---|---|---|---|---|---|---|---|---|
| W1 | 10 | 9.50 | 10/0/25.00 | 10/0/25.00 | =0d | =0d | =0d | =0d | =0d |
| W5 | 16 | 315.564818056694 | 16/0/72.00 | 16/0/72.00 | =0d | =0d | =0d | =0d | =0d |
| W10 | 24 | 3289.364096309510 | 24/0/168.00 | 24/0/168.00 | =0d | =0d | =0d | =0d | =0d |
| W15 | 32 | 90703.303868682866 | 32/0/304.00 | 32/0/304.00 | =0d | =0d | =0d | =0d | =0d |
| W20 | 40 | 2574480.119336159900 | 40/0/480.00 | 40/0/480.00 | =0d | =0d | =0d | =0d | =0d |

（全 20 波逐波对照均 OK，上表摘录 5 波；日志 `slice5-unit-run.log` L280 附近）

### [B] DPS 扫描 90 组（单塔 Arrow@S0 叠层 × W1/5/10/15/20）

- 90/90 全部逐位等价；**20 组落在非平凡「部分击杀」中间态**（0 < kills < N）——证明探针不是全 0/全 N 的平凡等价。
- W10 摘录：h=8（dps/thr 0.220）杀0漏24 ｜ h=11（0.267）**杀1漏23** ｜ h=32（0.506）杀2漏22 ｜ h=90（0.941）杀6漏18 ｜ h=190（1.473）杀19漏5 ｜ h=270（1.819）杀24漏0 —— 实时与金标本逐组全同。

### [C] delta 粒度无关性（W10 · h=11 非平凡构筑，金标本 杀1/漏23/scrap 7.0）

| 喂 dt (s) | 1.000 | 0.500 | 0.250 | 0.100 | 0.050 | 0.035 | 0.025 | 0.016 | 0.008 |
|---|---|---|---|---|---|---|---|---|---|
| kills | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| leaked | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 23 | 23 |
| scrap 偏差 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

→ 帧率不影响结算：等价性对帧粒度稳健（accumulator 起作用）。

### 等价机制一句话

MVP 塔不死 → 波内 DPS 恒定 → 金标本批处理循环可**逐 tick 展开**：`acc += 缩放dt`，凑满 `DT=0.1` 跑一个与 `simulate_wave` 循环体逐行相同的子步；`t_wave += DT` 与金标本 `time += dt` 同一条浮点累加序列；稳定排序（按 t_remain 升序）在单一基准怪口径下 ≡ 金标本正序遍历。

---

## 4. 金标本零改动 + MC 不回归确认

- 🔴 **金标本零改动**：项目**无 git 仓库**，采用三重替代证据：
  1. **mtime**：`scripts/engine/wave_sim.gd` = Oct 1 03:40、`shop_ai.gd` = Oct 1 03:05，均早于切片5 全部改动（13:00+）；
  2. **内容探针**（单测断言 PASS）：`wave_sim.gd` 含 `DT=0.1`、含 `simulate_wave_naive` 对照实现、含 Python 语义 sort 注释、无墙钟；
  3. **MC 逐位复现**：A 69.3% / B 91.3% / 中位 W8.0/W13.0 / B 总 DPS 4991135.6102341395，与切片4 定稿逐位一致。
- ⚠️ 建议：**主理人考虑 `git init`**，后续切片的「金标本零改动」可直接用 diff 作证。
- 切片1–4 断言数与切片4 验收时完全一致（222/2228/142/123），无隐藏行为变化。

---

## 5. 🟡 待拍板分歧（均未擅改口径）—— ✅ 已全部拍板（2026-10-01，主理人）

> 🔴 **拍板总原则**：凡改金标本口径 / 破坏 v0.4/v0.7 校准的抉择一律不采纳；三原型+Elite 作为**已实现但未激活**的校准候选，须过**独立 MC 重扫**才能上线。

### S5-D1 · 三原型+Elite ≠ 金标本 —— ✅ 拍板：**MVP 默认金标本等价口径；三原型+Elite 保持双开关 false，列为「校准闸门」后续单独重扫**
- **冲突**：GDD §2.5.3 三原型分化（D-W2=B）+ §2.5.4 词缀 Elite（D-W1=B）把 HP/在场时间重新分配，而金标本 `WaveSim` 是单一基准怪——两者对同一构筑给出**不同战果**（W10 h=11：金标本 杀0漏24 vs 三原型+Elite 杀1漏23）。
- **🔴 拍板理由**：MC 判据链（A 69.3% / B 91.3% / 起飞 W8/W12）是**在单一基准怪口径下校准出来的**。三原型+Elite 虽满足 W-C1 系数级守恒（`Σp·m_hp=Σp/m_spd=1.000`），但**改变了漏怪分布**（Tank `m_hp=3.0`/在场 15s 是硬骨头，即使总 HP 守恒，漏怪率也不同）→ **开开关 = 换难度曲线 = 起飞点漂移 = 未校准**。在独立 MC 重扫验证起飞率不破线之前，**不许默认激活**。
- **落地方式（工程已做，追认）**：两口径都完整实现，🔴 **MVP 默认 `prototype_split_enabled=false` 且 `elite_waves_enabled=false`**（与 `tower_aggro_enabled=false` 同款"结构就位、分支不生效"模式）→ 金标本等价口径，MC 逐位不变。
- **🟢 校准闸门（后续切片前置）**：三原型+Elite 上线前**必须**：① 用真实 build 跑 300 局 MC，确认起飞率仍 ≥80%、起飞点仍落 W10–15、B/A<1；② 若破线，按 GDD §2.5 兜底"第一个砍 Elite"，或重扫 `m_hp/m_spd`；③ 验收口径从"逐位等价"改为"统计容差"（金标本扩展为多原型版本，或改用 MC 分布对齐）。**这是 D-W1/D-W2 的激活前置，不是推翻它们**——设计已定稿，只是校准未过不能默认开。
- **T1 仇恨联动**：`tower_aggro_enabled=true` 会让"波内 DPS 不再恒定"（怪物停下打塔 → 集火目标变），届时等价口径需重议（建议：仇恨只改怪物路径、不改 DPS 分配总量，则等价可保）。
- **✅ 校准闸门已过（2026-10-01，切片7）**：用真实 build 跑 300 局 MC（三原型+Elite 口径，`wave_sim_proto.gd` / `run_loop_proto.gd`，shop_ai 金标本不变）—— **闸门三闸全过**：① B 起飞率 **91.7%** ≥80% ② 起飞点 **W13** ∈W10-15 ③ B/A **0.432** <1。→ 三原型+Elite 从「已实现但未激活」升级为「**已过校准闸门，可激活**」（双开关置 true 即生效）。详见 `docs/phase3/slice7-verify.md`。🔴 注意：这**不改** MVP 默认口径（仍 false = 金标本等价），只是解除"不许默认激活"的封锁。

### S5-D2 · 安全窗实现口径 —— ✅ 拍板：**追认 `paused` 实现，GDD 已补术语前置**
- GDD §2.9 写 `time_scale = 0`；项目红线 SR-R5 规定 `Engine.time_scale` 永不为 0（预算计时除零）→ 用 `get_tree().paused` 实现，paused 帧 delta 强制 0。
- 设计意图（世界完全静止、`t_wave` 不动）完全一致，冒烟实测 Δ=0.000000。
- **处置**：✅ 追认工程实现；已在 `wave-spawner.md` 头部补「术语前置」——全文 `time_scale = 0` 一律读作「世界暂停（paused），等效 0 速」，非字面 `time_scale = 0`。

### S5-F1 · GDD §5.2 组成表加法错误 —— ✅ 拍板：**确认笔误，已修订表格 + 确立保量式为权威**
- W4（6+6+3=15≠14）、W7（8+8+4=20≠19）、W19（15+16+8=39≠38）三行 `R+S+T ≠ N`，确为笔误。
- **处置**：✅ 已修订三行（W4→6/5/3、W7→8/7/4、W19→15/15/8）；并在 §5.2 确立**保量式为权威口径**：`tank=round(0.20N)`、`rush=round(0.40N)`、`swarm=N−rush−tank`（补齐保 C-2 只数守恒）。凡表格与保量式冲突，以保量式为准。

### S5-F2 · 守恒是「系数级」非「逐位级」—— ✅ 拍板：**确认可接受（≤8% 取整残差）**
- 整数取整残差：W10 Σ单怪 HP 偏离 +2.50%（无 Elite）/ +5.76%（有 Elite）。
- **处置**：✅ 确认可接受。三守恒在**系数层**精确成立（`Σp·m_hp=Σp/m_spd=1.000`），逐位不成立是"每只怪必须整数只"的必然取整误差。关键：`threshold` 用**系数级**的 `HP_budget = N×HP_unit`，**不用**取整后的 Σ单怪 HP → **不影响起飞校准**。单测上限放宽至 ≤8% 并逐波登记，合理。

---

## 6. 场景冒烟证据（窗口模式）

命令与产物：
```
"$GODOT" --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd        → slice5-wave.png
"$GODOT" --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd -- split → slice5-wave-split.png
日志：slice5-scene-smoke-windowed.log / -split.log（各 22/0，退出码 0）
```

关键实测（窗口模式，真渲染后端）：
- **实时弧长推进**：t_wave 0.50→2.10 期间 max(s) 5.05→21.21，世界 (5.05,25.0)→(12.0,34.21)，位移 11.54 unit；`sample(s)` 反查正确（拐点后走 y 段）。
- **减速隔离**：开商店 → ShopDilated 0.25×（W1 新手波）；Δ游戏 0.400s / Δ实时 1.595s = 比值 0.251，波次时钟同步 0.251，**怪物慢动作未停**；同 ≈1.6 实时秒：全速 Δt_wave=1.600s vs 减速 0.400s（比值 0.250）。
- **安全窗完全静止**：paused=true，0.8 实时秒 t_wave 18.300000→18.300000（**Δ=0.000000**）；收入已入账、核心 500/1000（演示局漏怪 10 只 × 50）。
- **下一波**：玩家开局 → W2 重出（11 只）。
- 截帧：`slice5-wave.png`（战斗中：5 段路径/核心方块/6 塔位带暴露红圈/怪物红点分布）；`slice5-wave-split.png`（商店+战场分屏，HUD 显示 time_scale 0.253 / paused=false）。

---

## 7. 遗留与下一步建议

1. **拍板 S5-D1~F2**（见 §5）——尤其 D1 决定切片6+ 的等价验收口径。
2. **T1 仇恨实装**（Q-T3：AGGRO_R=9.0/AGGRO_TICK=0.10/滞回 10.8）：状态机骨架已就位，置 `tower_aggro_enabled=true` 后需处理「波内 DPS 不再恒定」→ 等价口径需重议（建议：仇恨只影响怪物路径，不影响 DPS 分配，则等价可保）。
3. `d_path`/`ExposureArc` 已注册为塔位数据（`slot_exposure`），后续切片供「塔位评分 UI / 仇恨判定」直接消费。
4. 建议 `git init`（金标本零改动的 diff 证据链）。
5. 拆除回收/弃卡（切片4 🟡 遗留）按路线图排期。

---

## 附：产物索引

| 产物 | 路径 |
|---|---|
| 全量回归日志 | `docs/phase3/slice5-full-run.log` |
| 切片5 单测日志 | `docs/phase3/slice5-unit-run.log` |
| 切片4 冒烟回归 | `docs/phase3/slice5-slice4-smoke-regression.log` |
| 切片5 冒烟（headless / 窗口 / 窗口split） | `docs/phase3/slice5-scene-smoke.log` / `-windowed.log` / `-windowed-split.log` |
| 截帧 | `docs/phase3/slice5-wave.png` / `slice5-wave-split.png` |
| 架构文档 | `docs/architecture/slice5-wave-spawner-architecture.md` |
