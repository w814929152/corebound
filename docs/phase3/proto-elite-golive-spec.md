# 原型 / 精英波 **上线** · 设计裁决 + 实现规格

| 项 | 内容 |
|---|---|
| 文档 | `docs/phase3/proto-elite-golive-spec.md` |
| 作者 | 文策渊（设计裁决） |
| 日期 | 2026-10-11 |
| 目标 | 把已实现却从未在真实游戏开启的 **三原型分化 / Elite 波 / Sapper**（`prototype_split_enabled` / `elite_waves_enabled`）**限定在窗口模式开启**，并给出**出生几何裁决**、实现规格、验收清单与红线核对 |
| 硬约束 | 🔴 **只出文档**：不改任何 `.gd` / `project.godot` / `tests/`；🔴 **绝不改动任何定稿数值**；🔴 一切"需改定稿语义"的事项**登记为需用户拍板项**，不自行决定 |
| 复核基准 | `wave_director.gd` · `monster_data.gd` · `space_model.gd` / `monster.gd` / `wave_sim_proto.gd` / `wave_sim_aggro.gd` / `shop_ai.gd` / `boot.gd` / `battle_shop.gd` / `monster_layer.gd` / `battlefield_placeholder.gd` / `tests/*` · GDD `wave-spawner.md` §2.5 · `radial-core-siege-draft.md` §2.5 |

> ✅ **状态（2026-10-10）**：本文所有"需用户拍板项"**已全部拍板**（① 修 Tank 钳制 ② 收入接实时 ③ 上线前补 300 局 MC ④ 只上原型/精英 aggro OFF ⑤ 更正 R-10），**已放行交工程落地**。裁决全文见 **§8**，落地工单见 **附录 C**。正文中"需用户拍板"字样为文策渊原始表述（历史保留），以 §8 / 附录 A 裁决列为准。

---

## 0. 一页速览（TL;DR）

| # | 结论 |
|---|---|
| **§1** | 🔴 **R-10 / 任务简报的"Rush 出生 ρ₀ = 73.33 > span = 58"是推导口径错误 —— 生产代码下 Rush 实际出生 ρ₀ = `R_s` = 55.0，三原型最大出生 ρ = 55.0 ≤ span 58。不存在屏外出生。** 故 **唯一推荐处置 = 不扩 span、不改几何（等价于候选 (d) 的 OFF 分支）**。附：**发现一个真实的小几何异常（Tank 钳制）**，登记为需用户拍板项。 |
| **§2** | 注入点 = `boot.gd` **窗口分支**，`add_child(battle_shop)` **之后**、deferred `start_run` **之前**，设 `bs.wave_director.prototype_split_enabled = true` / `elite_waves_enabled = true`。**不注入 `battle_shop.gd`**（会误红 `run_slice5_scene_smoke`，见 §2.3）。headless 金标本零扰动。 |
| **§3** | Elite 波 = W5/10/15/20（`n_e` 2/2/3/4）；**Sapper 由 `elite_waves_enabled` 独立驱动但只有 `tower_aggro_enabled` 开时才具杀伤**；**Elite 的 HP 词缀必须 proto 与 elite 双开才生效**（`_build_spawn_table` 在 proto OFF 时提前 return）；经济/难度曲线见 §3.4。 |
| **§4** | 金标本口径（`shop_ai` AI 路线 / PATH）**不变** → T-A′…T-D″ **无需重跑**；但**新的"实机口径"（RADIAL + proto/elite ON）从未被测**，须按 S5-D1 补 300 局 MC。 |
| **§5** | `run_slice_panorama8.gd` 的 P-G8-5 现用**假定式** `R_s·max_m_spd`（=73.33，proto ON 必红）；应改为**镜像生产出生逻辑**的 `R_s·m_spd·clamp(1/m_spd,0,1)` → 最大 55 ≤ 58 → **真闸门 PASS**，radial8 不误红。 |
| **§6** | headless 默认回归 3397 断言 / 0 失败；`-- radial8` 8 项 PASS；窗口截帧应见 Rush 尖刺扇 / Tank 焦褐内环 / Elite 品红环 / 三档摆幅 / 精英波标记。 |
| **§7** | 逐条核对：未改任何定稿数值；PATH 逐位等价；不削 B 抬 A；未改 `{geo,engine,gameplay,data}` 定稿语义。 |

---

## §1 出生几何裁决（**核心 · 结论先行**）

### 1.1 结论

> 🔴 **不需要任何几何改动。** 生产代码下三原型**最大出生极径 = 55.0 ≤ 相机包围盒内切半径 span = 58.0** —— **没有任何原型会出生在画面外**。
> **唯一推荐处置 = 维持 `span = SPAWN_RADIUS + 3 = 58`（即候选 (d) 的 OFF 分支 / 候选 (e) 保持现状）**，代价为零、已验收视觉零扰动。

### 1.2 为什么简报的 73.33 是错的（推导链 · 可证伪）

**生产出生极径的权威公式**（三处独立代码 + GDD 守恒律互相印证）：

| 环节 | 出处 | 事实 |
|---|---|---|
| 出生 `t_remain` | `wave_director.gd:722` `var tr := t_reach / mspd` | 出生时 `t_remain = t_reach / m_spd`（**不是** `t_reach`） |
| 实体写入 | `monster.gd:61-70` `setup(..., p_m_spd, p_t_remain)` → `t_remain = p_t_remain` | `t_remain` 初值 = `t_reach/m_spd` |
| 极径派生 | `space_model.gd:113-115` `rho_of_t(t,m)= R_s·m·clampf(t/t_reach,0,1)` | ρ = `R_s·m_spd·clamp(t_remain/t_reach, 0, 1)` |
| 批处镜像 | `wave_sim_proto.gd:84` `var tr := t_reach / float(spd_mults[spawned])` | 批处理三原型版**同一式** |
| GDD 在场时间 | `wave-spawner.md:269-278` | Rush **7.5 s** / Swarm **10.0 s** / Tank **15.0 s**（= `t_reach/m_spd`） |
| GDD C-3 守恒 | `wave-spawner.md:265,278` `Σpᵢ/m_spdᵢ=1.000` ⟺ 加权平均在场时间 `= t_reach` | 只对 `t_remain=t_reach/m_spd` 成立 |
| 既有单测 | `test_suite_radial.gd:139` `_check("…Tank(m_spd=2/3) 出生 ρ = 55×2/3", rho_of_t(15.0, 2/3), …)` | 单测自己就用 `t_remain=15=t_reach/m_spd` 算 Tank | 

代入 `t_remain = t_reach/m_spd`：

| 原型 | `m_spd` | 出生 `t_remain = 10/m_spd` | `frac = clamp(t_remain/t_reach,0,1)` | **ρ₀ = 55·m_spd·frac** |
|---|---|---|---|---|
| Rush | 4/3 | 7.5 | clamp(0.75) = 0.75 | **55.0** |
| Swarm | 1.0 | 10.0 | clamp(1.0) = 1.0 | **55.0** |
| Tank | 2/3 | 15.0 | clamp(1.5 → **1.0**) | **36.67** |

> **→ 最大出生 ρ = 55.0 ≤ span 58.0。没有任何原型出生在包围盒外。**

**R-10 的错误来源**：`run_slice_panorama8.gd:117-119`（与 `r6789-10-test-hygiene.md:§R-10`）用的是
```
spawn_rho_max := SPAWN_RADIUS * max_m_spd          # = 55 × 4/3 = 73.33
```
这等价于把出生 `t_remain` 取成 **`t_reach`（=10）** 而非生产真值 `t_reach/m_spd`。它与同一份代码里的 E-R4（Tank 用 `t_remain=15`）**自相矛盾** —— 同一支 `rho_of_t`，Tank 用 `t_reach/m_spd`、Rush 却用 `t_reach`，两者不能同时成立。

**可证伪的最小验证（1 条，headless，不改任何文件）**：任何现有/新增探针里打印
`SpaceModel.rho_of_t(7.5, 4.0/3.0)` → **应为 `55.0000`**（而非 73.33）；`rho_of_t(15.0, 2.0/3.0)` → **应为 `36.6667`**（与 E-R4 一致）。若前者输出 73.33 则我的推导有误，请以该实测为准并回退到候选 (a)/(d)。

### 1.3 候选逐项评估

> 说明：**(a)/(b)/(c) 只在"把三原型改成"同刻到核"变体（出生 `t_remain = t_reach`，ρ₀ = R_s·m_spd）"这一前提成立时才有意义**。该变体与 GDD C-3（在场时间守恒 = `t_reach/m_spd`）冲突，**当前生产不采用**。下表给出"若切到该变体"的处置评估，以备未来拍板；当前推荐 = **(e)/维持现状**。

| 候选 | 做法 | 代价 | 对已验收视觉的影响 | 裁决 |
|---|---|---|---|---|
| **(a) 扩 span ≥ 76.33** | 全场 `sc` 8.48 → **6.446**（`min(1824/152.66, 984/152.66)=6.446`），**整体缩小约 24%** | 一/二/三刀全部 `u×sc` 元素同比缩小；需全量重验像素基线 | 🔴 大（三刀都要重验） | ❌ 不推荐（无条件触发，连 proto OFF 也缩） |
| **(b) 钳制 ρ₀ ≤ span** | Rush 出生半径压到 58 → 径向速度 7.33 → 5.8 u/s | **"快原型"身份被抹平**（Rush 与 Swarm 速度差从 1.33× 掉到 1.05×），三原型分化名存实亡 | 中（Rush 观感变慢） | ❌ 不推荐（破坏 §2.5.3 设计意图） |
| **(c) 允许屏外出生、走入** | 保尺寸；Rush 出生 ρ₀=73.33，约 **2.1 s**（=(73.33−58)/7.33）后进入画面 | 出生环视觉与真实位置脱节；**威胁楔形照明（按真实 pos 分扇区）会先亮但看不见怪** → "幽灵威胁" | 中 | ❌ 不推荐（可读性倒退） |
| **(d) 条件化 span** | `proto OFF` 维持 58（现状零变化）；`proto ON` 用 76.33 | 需改**两处**同源 span（`monster_layer._xform` + `battlefield_placeholder._draw_radial_ground`），并让 P-G8-2 的 span 断言随开关分档 | ✅ **小**（proto OFF 逐像素不变） | 🟡 **条件化变体下的最优解** |
| **(e) 维持现状** | 不改 span，不改几何 | **零** | ✅ **零**（span 不变 → sc 不变 → 三刀逐像素不变） | 🟢 **当前唯一推荐** |

> ⚠️ **对 (c) 的数值更正**：按径向 `v₀ = R_s/t_reach = 5.5`、Rush 速度 `5.5×4/3 = 7.33 u/s`，Rush 从 ρ₀=73.33 走到包围盒边 ρ=58 需 `(73.33−58)/7.33 ≈ 2.09 s`（简报写的 ~1.4 s 疑为误用 PATH 的 `v₀=10.10`）。如实登记此差异。

### 1.4 对第一 / 二 / 三刀已验收视觉的影响与重验范围

- **推荐处置 (e) 下**：`span` 不变 → `sc = 8.483` 不变 → 一/二/三刀**全部逐像素不变**，**重验范围 = ∅**。
- **若采 (a)/(d) 的 ON 分支**：`sc` 8.483 → 6.446，所有 `u×sc` 元素同比缩小 24%，**三刀都需重验**（尤其"恒定屏幕 px"类元素，见 §1.6）。

### 1.5 对可读性对比度地板的影响

- **对比度是相对亮度之比，等比缩放下不变**：三刀 §A.4 的最坏帧 T1（塔青↔场地 `7.39:1`／怪橙↔场地 `4.81:1`）在任意 `sc` 下**保持不变**。
- **推荐处置 (e) 下**：`sc` 不变 → 对比度**与现状完全一致**，无新增风险。
- 🟢 **补充利好**：RADIAL 渲染器给**所有原型**用同一 `P_ENEMY #FF6B3D 熔橙`（`monster_layer.gd:1119`）—— 原型只改**形状**（`rs/ts/尖刺扇`）与 Tank 内环，**不改色**。故"开启三原型"**不引入任何新颜色**，`怪橙↔场地 4.81:1` 的贴线达标结论**原样适用**（不给地板添新压力）。
- **若采 (a)/(d)**：比值不变，但**绝对像素尺寸变小** → 需核 `maxf(...)` 下限是否仍 ≥1px、以及最小支持分辨率下的可辨性（见 §1.6）。

### 1.6 (a)/(d) 若生效：像素尺寸与 `maxf` 下限复核（预备）

`sc = 6.446` 时（括注为现状 `sc=8.483`）：
| 元素 | 公式 | ON 时 px | 现状 px | `maxf` 下限是否兜住 |
|---|---|---|---|---|
| 单位描边 `U_OUTLINE·sc` | `maxf(1.5, 0.22·sc)` | 1.42 → **1.5** | 1.87 | ✅ 下限兜住（≥1.5） |
| Rim 内发光 `RIM_W` | 常量 0.8px | **0.8** | 0.8 | ✅ 屏幕常量，不受 sc 影响 |
| 同心环弧宽 | `maxf(1.0, 0.15·sc)` | 0.97 → **1.0** | 1.27 | ✅ 下限兜住 |
| 出生环描边 | `maxf(2.0, 0.28·sc)` | 1.80 → **2.0** | 2.37 | ✅ 下限兜住 |
| Rush 尖刺长 | `spike_len·sc`（0.9） | **5.80** | 7.63 | ⚠️ 无下限 → 缩小 24%，**最小特征**，须实机核可辨 |
| 怪体 Rush / Tank | `0.65·sc` / `1.30·sc` | 4.19 / 8.38 | 5.51 / 11.03 | ⚠️ 无下限 → 缩小 24% |

> 结论：`maxf` 地板使**线宽不塌到亚像素**，但**体量类特征等比缩小**。仅当未来真采 (a)/(d) 时，需在**最小支持分辨率**上重截一帧核 Rush 尖刺可辨性。**推荐处置 (e) 下本表全部为"无影响"。**

### 1.7 性能预算影响

- **(e)**：零改动 → **性能逐位不变**。
- **(a)/(d)**：`sc` 变小使**屏幕像素覆盖减少**（同屏单位更小 → 光栅化开销下降），draw call 数不变 → 性能**中性偏正**，无护栏需求。

### 1.8 🔴 真实几何异常（**新发现 · 需用户拍板**）

**Tank 出生钳制异常**：由 §1.2 表可见，`Tank` 因 `clamp(1.5→1.0)`：
1. **出生 ρ₀ = 36.67**（在出生环 `R_s=55` **内侧** 18.33 单位），而 Rush/Swarm 都在环上；
2. 更关键：`t_remain ∈ (10, 15]` 期间 `frac` 恒被钳到 1 → **ρ 恒为 36.67 → Tank 出生后原地静止约 5 s**，之后才向内移动。

这**偏离** GDD"所有原型从出生环涌入"的视觉意图，且"站着不动 5 秒"是可感知的观感瑕疵。

- **性质**：这是**既有几何语义**（`space_model.gd:114` 的 `clampf(...,0,1)`）在三原型开启后**首次被触发**才暴露的问题（proto OFF 时全部 `m_spd=1`，`frac=1`，无异常）。
- **候选修法（**仅为登记，不落地、不决定**）**：把上钳改为 `maxf(1.0, 1.0/m_spd)` 或对"出生瞬间"特判 `t_remain = t_reach` 归一（即让 Tank 也出生在环上、正常向内走 15 s）。二者都**触及 `scripts/geo/space_model.gd` 的定稿语义**。
- **裁决**：✅ **已拍板 —— 修**（用户 2026-10-10；根因与一行修法见 **§8.1**，落地工单 **C-2/C-3**）。注意：**修不修都不影响 §1 的相机裁决**（钳制只会让 ρ 更小，永不越界）。

---

## §2 开关注入点与形式

### 2.1 目标

在**窗口模式**下把 `WaveDirector` 实例的两个开关置真，**保证 headless 金标本口径零扰动**：

```gdscript
wave_director.prototype_split_enabled = true   # GDD §2.5.3 三原型
wave_director.elite_waves_enabled     = true   # GDD §2.5.4 Elite 波 + Sapper
```

### 2.2 推荐注入点（`boot.gd` 窗口分支 · 实例化后）

**位置**：`scripts/ui/boot.gd` 的 `else:`（非 headless）分支，**紧跟 `add_child(BattleShop.instantiate())` 之后**。骨架（**仅为规格，不落地**）：

```gdscript
# scripts/ui/boot.gd · _ready() · else 分支（窗口模式）
SpaceModel.mode = SpaceModel.Mode.RADIAL
var bs := BattleShop.instantiate()
add_child(bs)                                   # ← 此处同步跑完 bs._ready()，wave_director 已建
# 🔴 注入点：必须在 add_child 之后（实例已存在）、deferred start_run 之前（W1 尚未开波）。
#    battle_shop._ready() 用 controller.call_deferred("start_run", 1) → 在帧末才开波，
#    故此处置真**先于**开波（与简报侦察一致）。
bs.wave_director.prototype_split_enabled = true
bs.wave_director.elite_waves_enabled = true
print("[boot] WaveDirector: 三原型 + Elite 波 已开启（窗口模式）")
```

**为什么这样安全（三条独立保证）**：
1. **只有窗口分支执行**：本分支被 `if DisplayServer.get_name() == "headless": ... else: ...` 隔离；headless 分支与 `--script res://tests/run_tests.gd`（根本不装载 `main.tscn`）**永不进入**。
2. **开关是实例变量**：`prototype_split_enabled` / `elite_waves_enabled` 是 `WaveDirector` 的**实例成员**（`wave_director.gd:111/113`），默认 `false`（`test_suite_slice6.gd:234-235` 已断言）。不设真则一切测试保持金标本等价。
3. **与 `SpaceModel.mode` 注入同款先例**：`boot.gd:24-36` 的注释已确立"窗口分支注入 + 一行回退 + headless 零扰动"的范式，本次沿用（可回退性对称）。

### 2.3 为什么不注入 `battle_shop.gd`

`tests/run_slice5_scene_smoke.gd`（**直接实例化 `scenes/battle_shop.tscn`** 的真实场景冒烟）用 `split_model` 参数（`-- split`）决定口径，并断言
`bool(wd.prototype_split_enabled) == split_model`（`run_slice5_scene_smoke.gd:79-80`）。

- 若把开关硬写进 `battle_shop.gd._ready()` → **无 `-- split` 的默认冒烟**（headless 与窗口两种跑法，见 `control-manifest.md:190-192`）会因 `wd.prototype_split_enabled == true ≠ split_model(false)` **误红**；
- 亦即在**场景自身**里写死开启，会波及所有**直接实例化该场景**的测试与工具（`run_slice5_scene_smoke`、切片4/3 系列冒烟），破坏"测试可自选口径"的能力。

→ **场景保持中性（口径由调用方注入），开启只落在"实机首次装载"的唯一入口 `boot.gd`。**

### 2.4 🟡 连带：`shop_controller` 的收入口径回落（**需用户拍板项 #2**）

`shop_controller.gd:362-366` 有：
```gdscript
if int(rt.get("w",-1)) == w and _realtime_is_golden_equivalent():
    res = rt                                  # 金标本等价 → 用实时结果入账
elif not rt.is_empty() and int(rt.get("w",-1)) == w:
    print("[shop_controller][WARN] W%d 实时结果与金标本口径不一致（三原型/Elite 已开）"
        % w + " → 收入回落金标本（S5-D1 待拍板）")
```
`_realtime_is_golden_equivalent()`（:379-384）= proto OFF **且** elite OFF **且** aggro OFF。

**后果**：**一旦开启 proto/elite，实机每波收入会回落到"金标本口径"的 `scrap`**，而**战斗**跑的是三原型/Elite 口径 → **"打的"与"算钱的"不一致**，且每波打印 WARN。这不是崩溃，但**是上线前必须知情/处置的设计缺口**。→ 登记为**需用户拍板项 #2**（保底可接受 vs 接实时结果）。**本规格不动 `shop_controller.gd`。**

---

## §3 连带影响（开启后行为变化）

### 3.1 三原型分化（`prototype_split_enabled = true`）

- **`_build_spawn_table()` 走 `spawn_sequence(n)`**（`wave_director.gd:298`）：按 `Swarm→Rush→Tank` 轮转均匀铺开；`_hp_mults`/`_spd_mults` 由 `MonsterData.hp_mult/spd_mult` 给出。
- **Monster HP 乘数**：Rush 0.60 / Swarm 0.40 / Tank 3.00（**× HP_unit(w)**）；**速度**：Rush 4/3 / Swarm 1.0 / Tank 2/3。
- **C-1/C-2/C-3 三守恒保持**（`monster_data.gd:9-13`）→ 总 HP / 只数 / 加权在场时间**不变**；
- **但战斗结果会变**：多原型下 `t_remain` 不再全相等 → 集火排序从"正序==升序"变为**真排序**（`_stable_sort_by_remain`），贪心集火的命中分配改变。S5-D1 实测（`monster_data.gd:15-19`）：W10 同构筑金标本 7 杀 / 17 漏 vs 三原型 17 杀 / 7 漏 → **会改动起飞率判据链**。

### 3.2 Elite 波（`elite_waves_enabled = true`）

- **触发**：`is_elite_wave(w) = (w % 5 == 0)` → **W5 / W10 / W15 / W20**（`monster_data.gd:158-159`）。
- **只数**：`n_e = max(2, round(0.10·N))` → **W5 2 / W10 2 / W15 3 / W20 4**（按 `N(w)=round(8+1.6w)`：16/24/32/40）。
- 🔴 **重要耦合**：`_build_spawn_table()` 在 `not prototype_split_enabled` 时**提前 return**（`wave_director.gd:290-297`），`_elite_flags` 恒 false → **Elite 的 HP 词缀（`ELITE_HP_MULT=2.5`）只有 proto 与 elite 双开才生效**。只开 elite 不开 proto → `is_elite_wave()` 为真、Sapper 标记生效，**但没有精英 HP**（也无精英体量渲染）。
- **`is_elite_wave()`**（:310-311）会进 `snapshot()` 的 `is_elite_wave` 字段（:881）→ 渲染层/UI 可据此做"精英波标记"（当前 `monster_layer` 只用每只怪的 `elite` 布尔画品红环，未用波级字段）。

### 3.3 Sapper（**由 `elite_waves_enabled` 独立驱动**）

- **生成**：`_spawn_one` 在 `elite_waves_enabled and is_elite_wave(w)` 时，把 `elite_indices(n,n_e)` 命中的出生序号标 `m.sapper=true`（`wave_director.gd:734-740`）；批处镜像 `_build_sapper_flags` 同算法（`wave_sim_aggro.gd:739-750`）。
- **行为**：`_apply_aggro` 里 Sapper **出生即锁最近塔、无视 `AGGRO_R` 距离门槛、锁定后不因距离退出**（:439-443、:501-502），对塔伤害 ×`SAPPER_DMG_MULT=3.0`（:517）。
- 🔴 **关键前提**：上述 Sapper **行为**只在 `tower_aggro_enabled = true` 时才生效（`_apply_aggro` 整体被 `if tower_aggro_enabled and w > warmup_waves` 守卫，:414）。**只开 elite 不开 aggro → Sapper 标记被设但永不行动**（金标本口径下塔不挨打）。→ **Sapper 的"杀伤"是"elite × aggro"的联合产物**。
- **当前 scope**：本任务为"原型/精英波上线"，**未含 tower_aggro**（另属 T1 批次）。故 Sapper 在本轮**只落地"标记 + 渲染可辨识"，不产生实际塔损**。是否同时开 aggro → **需用户拍板项 #4**（见文末，代价：塔可被打死，需配套 V-8 复活/修复等已定稿机制）。

### 3.4 掉落 / 经济 / 难度曲线

| 维度 | 变化 |
|---|---|
| **`scrap_per_kill`** | `spk = 2 + 0.5w` **每杀不变**（`wave_sim.monster_stats`）；但**总击杀数变**（三原型重分配 HP → 杀/漏比变）→ **本波 `scrap_earned` 变** |
| **核心损耗** | `leak_damage = 50` **每漏不变**；漏怪数变 → **核心受损变** |
| **难度** | Elite 波把 `n_e` 只抬到 **2.5× HP**（其余按 `c(w)<1` 等比下调以保持总 HP 守恒，`monster_data.gd:169-176`）→ **W5/10/15/20 局部尖峰**（"精英波"节奏锚点） |
| **实机收入** | ⚠️ 因 §2.4 的回落逻辑，实机**入账**仍取金标本口径 `scrap` → **与实机战斗产出脱钩**（待拍板项 #2） |
| **起飞判据** | 三原型 + Elite **与金标本不等价**（S5-D1）→ 影响"起飞率/起飞点"判据链，须按 §4 补测 |

---

## §4 判据 / 平衡影响

### 4.1 金标本口径（`shop_ai` AI 路线 / PATH）：**不变**

**结论：不因本次开启而改变。** 三条独立理由：

1. **开关只在窗口分支被置真**（§2.2）；headless 默认回归（`run_tests.gd` 无参 = slice1~8 + t1aggro）与 `-- radial8` **均不进入 `boot.gd` 窗口分支**，且 `--script` 跑法不装载 `main.tscn`。
2. **`shop_ai.gd` 完全不读这三个开关**（已核：`shop_ai.gd` 无 `prototype_split_enabled`/`elite_waves_enabled`/`tower_aggro_enabled` 引用）→ **AI 决策流 / RNG 消费序列逐位不变** → 金标本 build 一致。
3. **生产默认仍为 `false`**（`test_suite_slice6.gd:233-235` 守护）→ 任何**未显式开启**的测试/工具**保持逐位等价**。

→ **T-A′ / T-A′-1 / T-A′-2 / T-B′ / T-C′ / T-D′ / T-D″ 无需重跑 / 重定档。**

### 4.2 新增口径：**实机口径（RADIAL + proto/elite ON）从未被测** —— 须补测

- 现有 MC 诊断（`run_slice_geo8_mc.gd`）**只跑 PATH 与 RADIAL、proto 恒 OFF**，**不覆盖"三原型 + Elite"**的实机口径 → **上线后的真实起飞率无既有读数**。
- **S5-D1 定稿要求**（`wave-spawner.md:7`）："上线前须真实 build 跑 **300 局 MC** 确认 **起飞率≥80% / 起飞点 W10–15 / B/A<1**，破线则按兜底**砍 Elite** 或**重扫 m_hp/m_spd**"。
- **批处理工具就绪度**：`wave_sim_proto.gd`（三原型+Elite）与 `wave_sim_aggro.gd`（仇恨）**已具备**（镜 `WaveDirector._substep`）→ 补测**不需新增引擎代码**，只需一个"开 proto/elite 的 MC 入口"（类似 `geo8_mc`，**属测试文件，本规格不落地**）。
- 🔴 **注意**：若 S5-D1 扫出破线且需**重扫 `m_hp/m_spd`** → 那是**改动定稿数值** → **必须停下、登记需用户拍板**（本规格不擅动）。

### 4.3 需重跑 / 重定档的判据清单

| 判据 | 是否需重跑 | 说明 |
|---|---|---|
| T-A′ / T-A′-1 / T-A′-2（苟活期） | ❌ 否（金标本口径不变） | 若要"实机口径"读数，另起 300 局 MC |
| T-B′（成型期） | ❌ 否（同上） | 同上 |
| T-C′ / T-D′ / T-D″（雪崩/起飞率） | ❌ 否（同上） | 同上 |
| **新增：实机口径 300 局 MC**（起飞率≥80% / 起飞点 W10–15 / B/A<1） | ✅ **是（S5-D1 门槛）** | 现有 `geo8_mc` 不含 proto/elite → 需新入口 |
| P-G8-5（几何闸门） | ✅ 是（**校正公式**，见 §5） | 由假定式 → 生产镜像式 |

---

## §5 测试更新（`tests/run_slice_panorama8.gd` P-G8-5）

### 5.1 现状问题

`run_slice_panorama8.gd:115-139` 的 P-G8-5：
- 用 `spawn_rho_max := SPAWN_RADIUS * max_m_spd`（**= 73.33**，假定 `t_remain=t_reach`）；
- `proto OFF` 档 → 只打印 `[TODO-R10]`（不设真闸门）；
- `proto ON` 档 → 断言 `spawn_rho_max ≤ span` → **必红**（73.33 > 58），**与生产真几何（55 ≤ 58）不符** → **假红**。

### 5.2 建议改动（**仅为规格，不落地**）

1. **把"假定式"换成"生产镜像式"**：出生极径应镜像 `_spawn_one` 的 `tr := t_reach/m_spd`：
   ```
   ρ₀(proto) = SpaceModel.rho_of_t(T_REACH / m_spd(proto), m_spd(proto))
             = R_s · m_spd · clampf(1.0/m_spd, 0.0, 1.0)
   spawn_rho_max = max over PROTOS
   ```
   期望：Rush 55.0 / Swarm 55.0 / Tank 36.67 → **max = 55.0 ≤ 58.0 → PASS**。
2. **保留** `M_SPD` 三原型常量真值断言（Rush 4/3 / Swarm 1 / Tank 2/3）—— 继续作为"数据被误改即红"的证伪网。
3. **`proto ON` 档转为真闸门**：断言 `spawn_rho_max ≤ span`（现在会 **PASS**，因为几何本就满足）。
4. **消除 `[TODO-R10]`**：改为 `[R-10-CLOSED] 最大出生 ρ = 55.0 ≤ span 58.0（口径更正：t_remain=t_reach/m_spd）`，并**在注释里登记 R-10 原式错误**。
5. **读生产真身默认值**（保持现有 `_WaveDirector.new().prototype_split_enabled`，非影子常量）。

### 5.3 如何避免误红既有 `radial8` 闸门

- `radial8` 聚合（`run_tests.gd:RADIAL8_GATES`）含 `panorama8` → 必须**保持 exit 0**。
- 校正后 P-G8-5 在 `proto OFF`（默认）与 `proto ON`（若探针显式开启）**两档都 PASS** → 不误红。
- **兜底**：即使未来 Tank 钳制被修（ρ₀→55），`max` 仍为 55 → 闸门**仍 PASS**（与 §1.8 拍板项解耦）。
- 🟡 **可选加固**：新增一条"生产出生 ρ 与真实 `WaveDirector._spawn_one` 一致"的软断言（推进 W1 后读 `snapshot()["monsters"][i]["pos"]` 到核心距离 ≈ 55/36.67）——**归属 `test_suite_radial`（RADIAL 专属口径）**，避免污染 PATH 套件。

### 5.4 其他测试面

- `test_suite_slice5.gd:639-660,854-855`、`run_slice5_scene_smoke.gd:66-80` 已**显式开启** proto/elite 做对照，**不受本次影响**（它们本就自选口径）。
- `test_suite_slice6.gd:233-235` 断言三开关**默认 false** → 应继续 **PASS**（默认不变）。

---

## §6 验收清单

### 6.1 headless 回归（默认口径 + `radial8`）应保持的读数

| # | 命令 | 期望 |
|---|---|---|
| 1 | `--headless --script res://tests/run_tests.gd`（无参） | **exit 0** · 断言数**逐位不变**：`222/2228/142/123/302/41/31/92/216 = 3397 项 · 0 失败`（`r6789-10-test-hygiene.md:104`） |
| 2 | `--headless --script res://tests/run_tests.gd -- radial8` | **exit 0** · 8 项全 PASS（含 `panorama8`；P-G8-5 校正后仍 PASS） |
| 3 | `--headless --script res://tests/run_tests.gd -- geo8` | **exit 0** · 33/0 |

> 🔴 判定：**断言计数与 exit code 与改前逐位相同** = 金标本口径零扰动。

### 6.2 实机截帧应看到什么（窗口模式）

按 `monster_layer._draw_radial_monsters` 的现状代码，开启后应首次**可见**：

| 观察点 | 期望（出处） |
|---|---|
| **Rush 尖刺扇** | 4 根尖刺（`n_spike=4`）、长 0.9u、径向拉长 `rs=1.5 / ts=0.75`（:1101） |
| **Tank 焦褐内环** | 体宽扁 `rs=0.85 / ts=1.25`、6 根短粗刺、体内 `P_ENEMY_DARK #8A2F1C` 内环（:1103、:1120-1121） |
| **Swarm 基准形** | 5 根中刺、`rs=ts=1.0`（:1105） |
| **精英品红环** | W5/10/15/20 上 `elite` 怪外圈 `P_ELITE #E8437F`，体量 ×1.35（:1106-1108、:1133-1134） |
| **三档摆幅差异** | `_sway_amp` Rush **0.10** / Swarm **0.06** / Tank **0.04**（:837-844）—— Rush 明显"活蹦"、Tank 沉稳 |
| **精英波标记** | `snapshot()["is_elite_wave"]` 为真（:881）；（当前渲染层未消费该字段，属"数据就绪、可选增强"） |
| **出生位置** | Rush/Swarm 出生在出生环 `R_s` 上（ξ应为 55）；🔴 Tank 出生在环**内侧**（§1.8 拍板项 #1，若未修则可见） |

### 6.3 可执行验收步骤

```
# ① 金标本口径零扰动（须 exit 0 且断言数不变）
<godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd
<godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd -- radial8

# ② 几何闸门（校正后）
<godot> --headless --path D:/roguedemo --script res://tests/run_slice_panorama8.gd
#   期望：P-G8-5 PASS（max 出生 ρ = 55.0 ≤ span 58.0）

# ③ 实机三原型/精英截帧（窗口模式）
<godot> --path D:/roguedemo --script res://tests/run_slice5_scene_smoke.gd -- split
#   （该脚本以 split_model=true 跑真实场景 → 截帧核 §6.2 五要素）

# ④ 实机默认启动（注入生效）
<godot> --path D:/roguedemo                       # boot.gd 窗口分支打印 "三原型 + Elite 已开启"
#   观察：Rush 尖刺扇 / Tank 焦褐内环 / W5 精英品红环
```

> ⚠️ **前置**：`③④` 需**先落地 §2 的注入**（本规格不落地）。`①` 在**注入落地前后都应** exit 0（因注入只在窗口分支）。

---

## §7 红线核对（逐条声明）

| # | 红线 | 声明 | 证据 |
|---|---|---|---|
| 1 | **不改动任何定稿数值** | ✅ 未改 `M_HP / M_SPD / M_DPS / ATTRITION=1.50 / κ_r=0.050 / AGGRO_R=9.0 / 塔位6 / SLOTS6 / SPAWN_RADIUS=55 / 核心HP1000 / leak_damage=50 / hp_growth=1.42` | 本文件只读引用；§1 结论 = **不改几何** |
| 2 | **PATH 逐位等价** | ✅ 本次不碰 PATH 分支；注入只在窗口分支、只改 `WaveDirector` 实例开关，默认仍 false | §2.2；`boot.gd:24-36` 范式 |
| 3 | **不削 B 抬 A** | ✅ 未改任何强度/弱化项；Elite/Sapper 只在 proto/elite/aggro 联合开启时生效 | §3.2-3.3 |
| 4 | **不改 `scripts/{geo,engine,gameplay,data}` 定稿语义** | ✅ 本文件**零代码改动**；§1.8 的 Tank 钳制若需修 → **登记为需用户拍板项 #1**，不擅改 | 文首硬约束 |
| 5 | **只出文档** | ✅ 未改任何 `.gd` / `project.godot` / `tests/` | 本文件为唯一产出 |
| 6 | **headless 金标本零扰动** | ✅ 由 §4.1 三条独立保证 | §4.1 |

---

## 附录 A · 需用户拍板项（**不自行决定**）

> **✅ 本表已全部拍板（2026-10-10）—— 裁决列见右，详见 §8 拍板记录。**

| # | 事项 | 现状 / 影响 | 待拍板的选项 | ✅ **用户裁决（2026-10-10）** |
|---|---|---|---|---|
| **#1** | **Tank 出生钳制异常**（§1.8） | Tank 出生 ρ=36.67（环内侧）+ 原地静止 ~5s（`space_model.gd:114` 上钳触发） | ①修 ②接受 | **①修** —— 上钳参照 `1.0` → `1.0/m_spd`（见 §8.1）；根因与修法由主理人独立定位 |
| **#2** | **实机收入回落金标本**（§2.4） | 开 proto/elite → `shop_controller` 每波 WARN 且收入取金标本口径，与实机战斗脱钩 | ①接受回落 ②改接实时结果 | **②改接实时结果** —— 去回落、去 WARN（见 §8.2） |
| **#3** | **实机口径 300 局 MC（S5-D1 门槛）** | 现有诊断不含 proto/elite → 实机起飞率无读数 | ①上线前补跑 ②先上后测 | **①上线前补跑** —— 新增实机口径 MC 入口，作为上线门禁（见 §8.3） |
| **#4** | **是否同开 `tower_aggro_enabled`**（Sapper 杀伤前提，§3.3） | 不启 → Sapper 只"标记+可辨识"、不产生塔损 | ①只上原型/精英 ②一并开启 | **①只上原型/精英（aggro 保持 OFF）** —— Sapper 本轮仅视觉/数据标记（见 §8.4） |
| **#5** | **R-10 文档更正**（信息项） | `r6789-10-test-hygiene.md §R-10` 与 `run_slice_panorama8.gd` 注释的 73.33 之口径错误 | 是否请工程一并更正 | **请工程一并更正**（主理人已实测坐实 §1.2，见 §8.5） |

**裁决状态汇总**：#1 修 · #2 接实时 · #3 补 MC · #4 aggro OFF · #5 更正 —— **五项全部有明确裁决，无遗留待决。**

---

## 附录 B · 已知风险与取舍

| 风险 | 等级 | 说明 / 缓解 |
|---|---|---|
| **实机三原型+Elite 未 MC** | 🟡 中 | 起飞率可能破 80% 红线（S5-D1 已预警）；缓解 = 拍板项 #3 |
| **实机收入与战斗脱钩** | 🟡 中 | §2.4 回落逻辑；缓解 = 拍板项 #2 |
| **R-10 口径错误的传播** | 🟢 低 | 已在本文件 §1.2 完整推导 + 可证伪验证；缓解 = 附录 A #5 |
| **Tank 钳制观感** | 🟢 低 | 不影响相机裁决；缓解 = 拍板项 #1 |
| **我（文策渊）未实机运行验证 §1.2** | 🟡 中 | 依铁律"只出文档"，未运行任何脚本；结论基于**静态代码 + GDD 守恒 + 既有单测 E-R4** 三重印证；**强烈建议**以附录 A #5 的最小探针实测坐实（若与推导不符，回退候选 (a)/(d)） |

---

## §8 主理人复核 + 用户拍板记录（2026-10-10）

> 本节由**主理人（Supervisor）**在**独立复核**文策渊交付后撰写。复核方法：**逐条回到源码坐实**（不采信文档结论），并对 §1.2 的 R-10 口径翻转**实机探针验证**。所有裁决均**已获用户拍板**。

### 8.0 复核结论总纲

| 项 | 文策渊结论 | 主理人复核 | 判定 |
|---|---|---|---|
| §1 出生几何 | **不需要几何改动** | ✅ 探针实测 Rush/Swarm ρ₀=**55.0**、Tank **36.67**，`max=55 ≤ span 58` | **采纳** |
| §1.2 R-10 翻转 | 73.33 系推导错误 | ✅ 三重印证（探针 + E-R4 单测 + GDD 在场时间） | **采纳** |
| §1.8 Tank 钳制 | 登记为拍板项，**未敢下根因** | ✅ **主理人独立定位根因**（见 8.1），并给出**一行修法** | **补强** |
| §2.2 注入点 | `boot.gd` 窗口分支 | ✅ 由 `run_slice5_scene_smoke.gd:265/80` 坐实（直接 load `.tscn` 不走 boot、且 L80 有断言） | **采纳** |
| §2.4 收入脱钩 | 登记为拍板项 | ✅ `shop_controller.gd:362-366` 坐实 | **采纳** |
| §5 P-G8-5 | 改生产镜像式 | ✅ 与 §1 一致（镜像 `_spawn_one` 的 `tr:=t_reach/m_spd`） | **采纳** |

**R-10 口径翻转的实机证据（主理人探针）**：`_spawn_one`(`wave_director.gd:722`) 传 `tr := t_reach / m_spd`，`monster.setup` 把它赋给 `t_remain`；而 `rho_of_t = R_s × m_spd × clamp(t_remain/t_reach,0,1)`。故：
- Rush(m_spd=4/3)：`t_remain=7.5` → `55×(4/3)×clamp(0.75)=55.0`
- Swarm(m_spd=1)：`t_remain=10` → `55×1×clamp(1.0)=55.0`
- Tank(m_spd=2/3)：`t_remain=15` → `55×(2/3)×clamp(1.5→**1.0**)=36.67`

→ **`max=55.0 ≤ span 58.0`，无任何原型出生在屏外**。R-10 断言式等价于**取 `t_remain=t_reach`**（即假设所有原型 `m_spd=1`），**与同文件单测 E-R4 的 Tank 断言自相矛盾**。

### 8.1 裁决 #1 · Tank 出生钳制 —— **修**（根因由主理人定位）

**现象**：Tank 出生在 `ρ₀=36.67`（出生环内侧 18.33 单位），且 `t_remain ∈ (10,15]` 期间 `frac` 恒被钳到 1 → **原地静止约 5s** 才向内移动。

**根因（精确）**：`scripts/geo/space_model.gd:114`
```gdscript
var frac: float = clampf(float(t_remain) / t_reach, 0.0, 1.0)   # 🔴 上钳 1.0 隐含 t_remain_max == t_reach
```
上钳 `1.0` 只在 `m_spd == 1` 时正确。真实归一上限是 **`t_remain_max/t_reach = 1.0/m_spd`**（Tank 的 `t_remain_max=15 > t_reach=10` → 上钳被误触发）。

**修法（一行，非"触及语义"的大改）**：
```gdscript
## 上钳参照改为 1.0/m_spd（= t_remain_max/t_reach）
var frac: float = clampf(float(t_remain) / t_reach, 0.0, 1.0 / m_spd)
```
**验证**：`rho_of_t(15.0, 2/3) = 55×(2/3)×clamp(1.5, 0, 1.5) = **55.0**` → Tank 归环、匀速内插，**静止 5s 消失**。

**金标本零扰动保证**：`m_spd == 1` 时 `1.0/m_spd ≡ 1.0` → **公式逐位恒等**，PATH/默认口径（全 Swarm，`m_spd=1`）**零影响**。

**同步项**：`tests/test_suite_radial.gd:138-139` 的 E-R4 Tank 断言 `55×(2/3)=36.67` **本身把钳制错值写成了"预期"** → 同步改为 **55.0**（这才是"出生在环上"的正确断言）。

### 8.2 裁决 #2 · 实机收入 —— **改接实时结果**

`scripts/gameplay/shop_controller.gd:362-366` 现状：三原型/Elite 开启时打印 WARN 并**回落金标本收入口径**（"打"与"算钱"脱钩）。裁决：**去回落、去 WARN**，收入直接取**实时结果**（`rt`），与实机战斗一致。金标本口径仅在 proto/elite **全 OFF** 时自然生效（默认路径不变）。

### 8.3 裁决 #3 · 实机口径 300 局 MC —— **上线前补跑（作为上线门禁）**

现有诊断不含 proto/elite → 实机起飞率**无读数**。裁决：**新增实机口径 MC 入口**（RADIAL + `prototype_split_enabled` + `elite_waves_enabled` ON），**跑满 300 局**，读数纳入上线前的 S5-D1 门禁。**若起飞率破 80% 红线 → 不得上线，回退本刀并上报**（红线优先于进度）。

### 8.4 裁决 #4 · `tower_aggro_enabled` —— **保持 OFF（只上原型/精英）**

本轮仅开启 `prototype_split_enabled` + `elite_waves_enabled`。`tower_aggro_enabled` **继续 false** → Sapper 本轮**仅产生视觉/数据标记**，无实际塔损机制。理由：aggro 会引入塔被击毁（需配套 V-8 等），超出本刀范围，且红线要求逐刀可回滚。

### 8.5 裁决 #5 · R-10 文档更正 —— **一并更正**

请工程按 §1.2/§5 一并更正：
- `docs/phase3/qg-radial/r6789-10-test-hygiene.md §R-10` 的"几何不满足=真实待办"结论（**已证伪**）；
- `tests/run_slice_panorama8.gd:115-139` 的"假定式"`max_m_spd`（`73.33`）→ **生产镜像式**（见 §5.2，期望 `max=55.0 ≤ 58.0 → PASS`）；
- 消除 `[TODO-R10]`，改 `[R-10-CLOSED]`，并在注释登记原式错误（`t_remain=t_reach/m_spd`）。

---

## 附录 C · 落地工单（交 engineering-lead · 逐条可验收）

> **前置约束**：不改任何定稿数值；PATH 逐位等价；`t_remain` 唯一权威；出生角零 RNG；`t_reach=10.0s` 恒定；禁止"削 B 抬 A"、禁止下调判据阈值。

| # | 工单 | 文件 / 位置 | 验收 |
|---|---|---|---|
| **C-1** | 窗口分支注入双开关 | `scripts/ui/boot.gd`（`add_child(bs)` 后、deferred `start_run` 前）：`wd.prototype_split_enabled = true`、`wd.elite_waves_enabled = true`（`tower_aggro_enabled` 保持 false） | 窗口启动即生效；默认 headless 路径**不受影响** |
| **C-2** | 修上钳参照 | `scripts/geo/space_model.gd:114`：`clampf(t_remain/t_reach, 0.0, 1.0/m_spd)` | `rho_of_t(15,2/3)=55.0`；`m_spd==1` 时**逐位恒等** |
| **C-3** | 同步 E-R4 断言 | `tests/test_suite_radial.gd:138-139`：Tank 断言 `36.67` → `55.0` | `radial8` 全绿 |
| **C-4** | 收入接实时 | `scripts/gameplay/shop_controller.gd:362-366`：去回落、去 WARN，取 `rt` | 实机战斗↔收入一致 |
| **C-5** | 补 300 局 MC 入口 | 新增测试入口（`tests/`），RADIAL + proto/elite ON，300 局 | 起飞率读数落盘；**破 80% → 上报、不上线** |
| **C-6** | P-G8-5 转真闸门 | `tests/run_slice_panorama8.gd:115-139`：生产镜像式 + `[R-10-CLOSED]` | proto OFF/ON **两档都 PASS**，不误红 `radial8` |
| **C-7** | 更正 R-10 文档 | `docs/phase3/qg-radial/r6789-10-test-hygiene.md §R-10` | 结论与 §1.2 一致（已证伪原式） |
| **C-8** | 实机截帧核验 | 窗口模式 | 见 §6.2：Rush 尖刺扇 / Tank 焦褐内环 / 精英品红环 / 三档摆幅 / 精英波标记 |
| **C-9** | 出 impl 记录 | `docs/phase3/proto-elite-golive-impl.md` | 改动清单 + 逐项↔规格节号 + 证据 + 偏差登记 |

**落地后主理人独立复核**：默认回归**逐位一致**（`222/2228/142/123/302/41/31/切片8=92/T1=216`）+ `radial8` PASS + MC 读数 + 实机截帧，全部通过方可提交。

---

*文档结束 · 文策渊（设计裁决）+ 主理人复核（2026-10-10）· 只出文档 · 零代码/零定稿数值改动 · 结论可执行、可证伪*
