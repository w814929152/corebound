# 仇恨（tower_aggro）**上线** · 实现规格（第五刀）

| 项 | 内容 |
|---|---|
| 文档 | `docs/phase3/tower-aggro-golive-spec.md` |
| 作者 | 主理人（侦察 + 口径裁决）；落地交 engineering-lead |
| 日期 | 2026-10-10 |
| 目标 | 把 T1 批次**已实现、已定稿、却从未在真实游戏开启**的 **仇恨锁塔 / 塔损耗 / Disabled 中间态 / Sapper ×3**（`tower_aggro_enabled`）**限定在窗口模式开启**，补齐**实机全开口径**的验证基础设施与门禁 |
| 硬约束 | 🔴 不改任何定稿数值；🔴 `tower_aggro_enabled=false` / `repair_on_disable=0` 路径**逐位不变**；🔴 PATH 逐位等价；🔴 不改判据阈值、不削 B 抬 A；🔴 渲染层只读 snapshot |
| 复核基准 | `wave_director.gd`（aggro 内联）· `wave_sim_aggro.gd` / `run_loop_aggro.gd` · `wave_sim_proto.gd` / `run_loop_proto.gd` · `monster_data.gd`（AGGRO_R/EXIT/SAPPER_*）· `mvp_config.gd`（repair_on_disable）· `boot.gd` · `disabled_tower_dialog.gd` / `shop_controller.gd`（修复入口）· `tests/scan_{bulwark,sapper,protect_core}.gd` · GDD `mechanics-tower-life-death.md` §2.3 |

> **状态**：口径已按推荐默认拍板（用户 2026-10-10 跳过决策提问、「按推荐继续」）→ **放行落地**。拍板记录见 §7。

---

## §0 一页速览（TL;DR）

| # | 结论 |
|---|---|
| **§1** | 仇恨机制（锁塔 / 塔损耗 / Disabled / 安全窗修复 / Sapper ×3 / 起手保护 WARMUP=2 / 波首满血）**已全量实现并定稿**，全项目**仅差"打开开关"**。 |
| **§2** | **口径 = 窗口模式全开**：`RADIAL + prototype_split_enabled + elite_waves_enabled + tower_aggro_enabled`；`repair_on_disable` **保持 0**（诊断开关，非产品功能）；塔死亡**只走安全窗三选一**（`disabled_tower_dialog` 已落地）。注入点 = `boot.gd` 窗口分支（同第四刀）。 |
| **§3** | 🔴 **真缺口**：`RunLoopProto`（原型/精英）与 `RunLoopAggro`（仇恨）是**两条独立轴**，**无三轴合并镜像** → 必须新建，并满足**退化逐位守护**（任一轴 OFF 时退化为既有口径、逐位一致）。 |
| **§4** | 默认回归读数**逐位不变**（`222/2228/142/123/302/41/31/92/216`）；`radial8` **8-8 PASS**；**新增实机全开 MC（300 局）→ B 起飞率 ≥ 0.80 设为上线门禁**；A 只作 INFO（H2 已裁决关闭）。 |
| **§5** | 实机截帧应见：怪物**停下攻塔**（不再前进）/ 塔被锁定**橙环** / 塔进入 **Disabled 视觉** / 安全窗 **「处置受损塔 (N)」弹窗** / Sapper 精英。 |
| **§6** | 零定稿数值改动；三条零扰动路径（aggro OFF / proto OFF / repair_on_disable=0）逐位保持。 |

---

## §1 现况：机制已全量落地，只差"打开"

**门控清单（全部默认 false / 0，项目从未开启）：**

| 开关 | 位置 | 默认 | 本轮处置 |
|---|---|---|---|
| `tower_aggro_enabled` | `wave_director.gd`（开关 L102） | `false` | **开**（窗口分支） |
| `repair_on_disable` | `mvp_config.gd`（L184，7 档枚举） | `0`（OFF） | **保持 0** |
| `prototype_split_enabled` | `wave_director.gd` | `false` | 已开（第四刀） |
| `elite_waves_enabled` | `wave_director.gd` | `false` | 已开（第四刀） |

**已落地的产品机制（本轮无需新做，只需被激活）：**

1. **机会型仇恨（Q-T3 定稿）**：`Marching` 怪进入 `AGGRO_R=9.0` → 锁**最近未 Disabled 塔**；迟滞带 `AGGRO_EXIT=10.8` 退出防抖动。
2. **锁定即停**：`AggroTower` 态怪物**冻结 `t_remain`**（不前进、**不漏怪**）——`wave_director.gd` ③ 段。
3. **塔损耗与 Disabled（Q-T2/Q-T4 定稿）**：塔 HP `HP0 × h^0.6`；归零 → `Disabled`（**停止输出、仍占塔位、仍持装配卡、仍供 `h_j`**）。
4. **波首满血（Q-T2 = ①）**：aggro 开时，**波首把未 Disabled 塔重置满血**（`_init_tower_hp`）；**跨波持久伤害只经 Disabled**。
5. **起手保护（V-1 定稿）**：`WARMUP=2` → W1/W2 **仇恨不激活**（否则起手塔必死、起飞率 0%）。
6. **Sapper（玩法⑤ 定稿）**：Elite 波里均匀铺开的精英怪**出生即锁"全局最近未 Disabled 塔"、无视 `AGGRO_R` 距离门槛、`SAPPER_DMG_MULT=3.0`**。🔴 **Sapper 的杀伤力只有在 aggro 开启时才真实存在**——这正是上一刀（第四刀）把 aggro 留在这里的原因。
7. **安全窗修复入口（Q-T4/Q-T8 定稿）**：`disabled_tower_dialog.gd` + `shop_controller._show_repair_dialog`——安全窗内每座受损塔**三选一：修复 / 被动拆除 / 放着不管**。
8. **可读性 UI**：塔被锁定**橙环**（`monster_layer :: _draw_under_attack`）、暴露度图标（已落地）。

> 🔴 **`repair_on_disable` 是诊断开关，不是产品功能**（`mvp_config.gd:170-177` / `v7-repair-on-disable-spec.md §2.2` 明确）。塔死亡的**产品路径 = 安全窗三选一**（§1-7）。故本轮**不开** `repair_on_disable`（保持 0）→ 波内自动复活（9/11 档）**不启用**（且 9/11 属 V-8 诊断臂，V-8 残响方向已被终审砍掉，见 `v8-adjudication.md`）。

---

## §2 上线口径（拍板）

### 2.1 窗口模式全开

`scripts/ui/boot.gd` 的**窗口分支**（`else:`），在 第四刀已有注入之后追加一行：

```gdscript
bs.wave_director.tower_aggro_enabled = true
```

→ 实机口径 = `SpaceModel.mode = RADIAL` + 三原型 + Elite + **仇恨**。

**回滚**：删掉这一行（或设回 `false`）即回退到第四刀口径。**headless 分支与 `tests/run_tests.gd` 路径永不进入该分支** → 默认回归零扰动。

### 2.2 不动的开关（明确）

| 开关 | 处置 | 理由 |
|---|---|---|
| `repair_on_disable` | **保持 0** | 诊断开关，非产品功能；产品路径是安全窗三选一 |
| `reverb_enabled` | **保持 false** | V-8b 终审已砍（默认不得启用） |
| 一切定稿数值 | **不动** | `ATTRITION=1.50` / `AGGRO_R=9.0` / `AGGRO_EXIT=10.8` / `HP0=120` / `h^0.6` / `WARMUP=2` / `SAPPER_DMG_MULT=3.0` / 塔位6 / `SLOTS6` / `SPAWN_RADIUS=55` / 核心HP1000 / `hp_growth=1.42` / 三原型表 |

---

## §3 三轴合并镜像（🔴 本轮的真缺口）

### 3.1 问题

`WaveDirector._substep` 的实机全开口径 = **金标本结算 + 原型/精英分化 + 仇恨行为**。但批处理侧：

- `wave_sim_proto` / `run_loop_proto` 镜像 **原型 + Elite**（**无仇恨**）；
- `wave_sim_aggro` / `run_loop_aggro` 镜像 **仇恨**（**无原型/精英**）；
- **二者不可叠加** —— 现有 MC 都测不到"实机全开"这套口径。

### 3.2 要求（交工程实现）

1. 新增**三轴合并镜像**（建议命名 `scripts/engine/wave_sim_proto_aggro.gd` + `scripts/engine/run_loop_proto_aggro.gd`，与既有镜像同族）。
2. **镜像对象 = `WaveDirector._substep` 的全相位**（① 生成 → ② DPS 分配 → ③ 前进/漏怪/**锁定即停** → ④ 仇恨 → ⑤ 复活[Tick，default no-op]），**逐相位与真身同序**。
3. 🔴 **守护（硬要求，必须有测试钉死）—— 已在 A-2 发现分歧后重定义（见 §3.4）**：
   - **①** `aggro=false` → 与 **`run_loop_proto` 逐位一致**；
   - **②** `proto/elite=false` + `aggro=true` → 与 **真身 `WaveDirector`（headless 驱动小场景）逐位一致**（~~原要求"与 `run_loop_aggro` 相等"因旧镜像不忠实而**不可满足**，已替换~~）；
   - **③** 三轴全 OFF → 与 **金标本 `run_loop` 逐位一致**；
   - **④（最强）** 上线口径（全 ON）→ 与 **真身逐位一致**（门禁可信度的地基）。
4. 🔴 **不得新增/改动任何数值常量**；合并镜像只做"相位编排"，各相位语义**逐字复用**既有镜像/真身，不得重写公式。
5. 若发现既有两镜像在共享相位上存在**口径分歧** → **停下上报**（本轮已触发，见 §3.4）。

### 3.4 🔴 A-2 实测发现：旧 aggro 镜像 ② 相位**不忠实于真身**（本刀已绕开 + 登记债务）

**工程实测（300 局，seed=20260930）**：

| 位置 | ② 相位 | 语义 |
|---|---|---|
| 真身 `wave_director._substep:365` | `_stable_sort_by_remain()` | **原地排序（assign）** |
| `wave_sim_proto.gd:89` | `monsters = _stable_sort_by_time(monsters)` | assign ✓ 忠实 |
| `wave_sim_aggro.gd:189` | `_stable_sort_by_time(monsters)`（**返回值被丢弃**） | **no-op** ✗ **不忠实** |

**可观测影响**：aggro 镜像 vs assign 口径 —— A 路径 0 格分歧；**B 路径 129 格**（首个分歧 run34 W19）；**B + Sapper 开 9570 格**。

**裁决（主理人 2026-10-10）**：
1. **合并镜像 ② 恒 assign**（与真身/proto 镜像一致）——**拒绝**"按轴条件归约"（会让 `proto OFF` 配置下静默复现错误语义）。
2. 守护 ② 改**对标真身**（§3.2-3），不再要求与旧 `run_loop_aggro` 相等。
3. 🔴 **`wave_sim_aggro` 本刀不动**（改它会漂移 T1 聚合读数、且属定稿件 → 超范围），但**登记为债务**：
   > 🔴 **T1 既有 aggro 定稿读数（A 无保护 0.393 / A 保主力塔 0.583 / B 0.883 / Sapper 对照等）是在这份"不忠实于真身"的旧镜像上测得 → 不能直接作为上线预期。权威口径 = 本刀新的忠实 all-ON MC。**
4. 建议后续单独立 **ADR** 修 `wave_sim_aggro` ② + 重扫 T1 定稿（V-1 `ATTRITION=1.50` 等）——本刀不开工。

### 3.3 风险与缓解

| 风险 | 缓解 |
|---|---|
| 第三份镜像与真身漂移（"三份状态"经典坑） | §3.2-3 三条退化逐位守护 + 至少一条"合并口径 vs 既有单轴口径"的一致性断言 |
| DPS 分配次序在两镜像中不一致 | §3.2-5：发现分歧即停、上报 |

---

## §4 判据与门禁

### 4.1 必须保持不变的（回归保护网）

| 项 | 期望 | 说明 |
|---|---|---|
| 默认回归（切片1–8 + T1） | EXIT 0；聚合 **`222/2228/142/123/302/41/31/92/216`** 逐位一致 | 三条零扰动路径（aggro OFF / proto OFF / repair 0）保证 |
| `radial8` 聚合 | **8-8 PASS**（exit 0） | 不含新镜像 → 不受影响；但**必须复跑确认** |
| `CI` | 全绿（含新增的全开 MC） | 见 4.3 |

### 4.2 新增：实机全开 MC（🔴 **上线门禁**）

- **口径**：`RADIAL + prototype_split_enabled + elite_waves_enabled + tower_aggro_enabled`（`repair_on_disable=0`、`aggro` 走合并镜像）。
- **规模**：300 局（seed 与既有 MC 对齐，可对拍）。
- **主判据（门禁）**：**多塔 B 起飞率 ≥ 0.80** → 破线**不得上线**、如实上报（禁止自行改数值/下调阈值）。
- **A 路径只作 INFO**：H2 已裁决关闭（单核高风险为设计预期）——附读数供判读，**不作为门禁**。
- **输出**：起飞率 / 存活率 / 中位起飞波 / 平均结算波 / 核心 HP 分布 / **Disabled 塔数分布**（新增，用于确认仇恨确实生效）。
- 落点建议：`tests/run_slice_aggro_golive_mc.gd`；**不进**默认回归入口（耗时长），单列为门禁入口并纳入 **CI**。

### 4.3 CI

`ci.yml` 追加一步：跑 4.2 的全开 MC（作为门禁）；日志并入 artifact。

### 4.4 既有 aggro 读数（⚠️ **口径存疑 · 见 §3.4**）

> 🔴 **警告**：下表读数取自**旧 `run_loop_aggro` 镜像**，其 ② 相位**不忠实于真身**（§3.4）→ **仅供参考，不得作为上线预期**。上线门禁以 §4.2 的**忠实 all-ON MC** 为准。

| 口径 | A | B |
|---|---|---|
| M-1 之前扫描（`scan_bulwark` / `scan_protect_core`，aggro ON、proto/elite OFF） | A 无保护 **0.393** / A 保主力塔 **0.583** / A 理想肉盾 **0.623** | **0.883** |
| Sapper 对照（`scan_sapper`） | A 无 0.393 / A 有 0.400（Δ+0.007） | B 无 0.883 / B 有 0.857（Δ−0.027） |

→ Sapper 惩罚温和（Δ 在 MC 噪声内）；但**因旧镜像口径不忠实，上述数值与上线实际行为可能有系统性偏差**（尤其 B 路径 / Sapper 开）。**本轮三轴合并后必须以新读数重新定论。**

---

## §5 验收清单

### 5.1 headless

- [ ] 默认回归 EXIT 0，聚合读数**逐位一致**（§4.1）。
- [ ] `radial8` 8-8 PASS。
- [ ] 退化逐位守护三条全 PASS（§3.2-3）。
- [ ] 全开 MC：B 起飞率 ≥ 0.80（门禁）；附 A/Disabled 分布读数。
- [ ] `--check-only` 无脚本错误；无新增裸 `pow(` / 裸 `RandomNumberGenerator`。

### 5.2 实机截帧（窗口模式）

- [ ] **怪物停下攻塔**：进入锁定态后 `t_remain` 冻结、不再前进。
- [ ] **塔被锁定橙环**（`_draw_under_attack`）。
- [ ] **塔 Disabled 视觉**（停止输出、仍占塔位）。
- [ ] **安全窗「处置受损塔 (N)」弹窗**三选一可用（修复置灰条件 = 积分不足）。
- [ ] **Sapper 精英**：Elite 波里锁塔且伤害 ×3 生效（对比无 Sapper）。
- [ ] 起手保护：W1/W2 **无塔被锁**（WARMUP=2 生效）。

### 5.3 产物

- impl 记录 `docs/phase3/tower-aggro-golive-impl.md`（改动清单 + 逐项↔本规格节号 + 原始输出 + 偏差登记 + 未决）。
- 截帧存 `docs/phase3/`。

---

## §6 红线核对

| # | 红线 | 声明 |
|---|---|---|
| 1 | 零定稿数值改动 | 仅开开关 + 新增镜像/测试；不动 `ATTRITION/AGGRO_R/AGGRO_EXIT/HP0/h^0.6/WARMUP/塔位/SLOTS6/SPAWN_RADIUS/核心HP/hp_growth/三原型/ELITE_*/SAPPER_*` |
| 2 | 三条零扰动路径逐位保持 | aggro OFF / proto OFF / `repair_on_disable=0` |
| 3 | PATH 逐位等价 | 不碰 PATH 分支；不碰 `SpaceModel` |
| 4 | 不削 B 抬 A / 不下调判据阈值 | 未动任何强度项；门禁阈值 0.80 与 S5-D1 一致 |
| 5 | 双模可回滚 | boot.gd 删一行即回退 |
| 6 | 渲染层只读 snapshot / 零新信号 | 渲染层改动仅限既有 UI 的既有信号 |
| 7 | `t_remain` 唯一权威 / 出生角零 RNG / `t_reach=10.0s` 恒定 | 未触碰 |

---

## §7 拍板记录（2026-10-10）

用户在本轮**跳过决策提问**并指示「按推荐继续」→ 以下按**推荐默认**拍板落地：

| # | 事项 | 裁决 |
|---|---|---|
| **D1** | 实机全开口径的 MC 取法（无现成三轴合并镜像） | **新建三轴合并镜像**（`wave_sim_proto_aggro` / `run_loop_proto_aggro`）+ 退化逐位守护 |
| **D2** | 三轴合并 MC 是否设为门禁 | **设为上线门禁**（B ≥ 0.80，破线不上线） |
| **D3** | aggro 下 A 路径起飞率 0.393（< 0.60 红线） | **按 H2 既有裁决接受**（单核高风险为设计预期，不动红线、不加起手保护） |
| **D4** | 塔死亡处置口径 | **`repair_on_disable` 保持 0**（诊断开关不开），只走**安全窗三选一**（已落地 UI） |
| **D5** | 上线范围 | 窗口模式**全开**（RADIAL + 原型 + 精英 + 仇恨），即叠加在第四刀之上；一行可回滚 |
| **D6** | A-2 发现 ② 相位口径分歧后的裁决（落地中追加） | **合并镜像 ② 恒 assign（忠实真身）**；守护 ② 改为**对标真身**；`wave_sim_aggro` **本刀不动**但**登记债务**（旧 T1 aggro 定稿读数口径存疑）；建议后续单独立 ADR 修 + 重扫（本刀不开工）。详见 §3.4 |
| **D7** | 🔴 **门禁破线后的裁决**（落地实测 B@6=0.677<0.80，用户 2026-10-10 拍板） | **①不上线**：回退 `boot.gd` 的 aggro 开关（实机保持第四刀口径）；**②CI 该步转非阻断诊断**；**③补全"玩家安全窗修复"口径**并重测（MC 增 `repair_on_disable ∈ {0,1 FREE,2 PRICED}` 矩阵，主判 PRICED 臂 B@6 ≥ 0.80）——**不改任何数值、不改 0.80 阈值**；**④顺手修** `disabled_tower_dialog.gd:155` 的 `%` 转义（Disabled 塔视觉解耦**明确不做**）。详见 impl 记录「B 轮」。 |

> **D3 补充**：门禁口径的历史读数（旧 B=0.883）与实测（B=0.677）**均取自"AI 完全不修塔"口径**——该口径**不含产品实际提供的安全窗修复机制**，故两者都是**下界**，不代表真实玩家体验。D7-③ 即为此口径缺口的补全。

> 🔴 D3/D4 若用户日后要改（给 A 加起手保护 / 开波内自动复活），须另立 ADR 并**触及定稿数值**，不在本刀范围。

---

*文档结束 · 主理人规格（第五刀 · 仇恨上线）· 零定稿数值改动 · 口径已拍板放行 · 结论可执行、可证伪*
