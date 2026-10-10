# 第五刀 · 仇恨上线（tower-aggro go-live）· 落地记录

> 规格：`docs/phase3/tower-aggro-golive-spec.md`（§1–§7 + D1–D6）
> 引擎：Godot **4.7.2-stable**（`project.godot` 钉定）
> 落地：程基岩（engineering-lead）· 主理人游承峰调度
> 日期：2026-10-10

---

## 0. 一句话结论

**基础设施全部落地、退化守护全绿（52/0）、默认回归逐位不变、radial8 8-8 PASS、实机截帧 5 态落盘**；
但 **上线门禁（全开 MC · 多塔 B 起飞率 ≥ 0.80）破线：B(n_slots=6)=0.677 < 0.80**
→ 🔴 **本轮不得上线**（如实上报，未调任何数值 / 未下调任何阈值）。

---

## 1. 改动清单（逐项 ↔ 规格节号）

| # | 文件 | 改动 | 规格节号 |
|---|---|---|---|
| **A-1** | `scripts/ui/boot.gd`（L41–50） | 窗口分支注入 `bs.wave_director.tower_aggro_enabled = true`（在第 4 刀 proto/elite 注入之后）；注释由"aggro 保持 false"改为"第五刀已开 aggro"；新增 `print("[boot] aggro ON（仇恨锁塔 · 塔可受损/Disabled）")`。**未触碰** `repair_on_disable`（仍 0）、**未触碰** headless 分支。 | §2.1 / §2.2 |
| **A-2** | `scripts/engine/wave_sim_proto_aggro.gd`（新）<br>`scripts/engine/run_loop_proto_aggro.gd`（新） | 三轴合并批处理镜像（proto+elite+aggro），逐相位镜像真身 `WaveDirector._substep`：① 生成 → ② DPS 分配 → ③ 前进/漏怪/锁定即停 → ④ 仇恨 → ⑤ 复活 tick（默认 no-op）。**② 相位 = 恒大 assign**（见 §4-1）。 | §3.2 |
| **A-3** | `tests/test_suite_aggro_golive.gd`（新）<br>`tests/run_tests.gd`（接线：`-- aggro_golive`） | 四条退化逐位守护：① `aggro=false` → `== run_loop_proto`；② `proto/elite=false`+aggro → **`== 真身`**；③ 三轴全 OFF → `== 金标本 run_loop`；④ 全开 → **`== 真身`**。另有 Sapper 交叉 + aggro 生效自检 + 旧镜像偏差登记（INFO）。 | §3.2-3 / D6 |
| **A-4** | `tests/run_slice_aggro_golive_mc.gd`（新） | 全开 MC（RADIAL+proto+elite+aggro · repair=0 · WARMUP=2 · seed=20260930），300 局 × 4 臂（n_slots 6/8 × A/B）。输出起飞率/存活率/中位起飞波/平均结算波/核心 HP 分布/Disabled 塔数分布。门禁：B@6 ≥ 0.80。 | §4.2 |
| **A-5** | `.github/workflows/ci.yml` | 新增两步：`aggro_golive 退化逐位守护`（`-- aggro_golive`，日志 `ci-logs/aggro_golive_guards.log`）；`实机全开 MC`（`run_slice_aggro_golive_mc.gd`，日志 `ci-logs/aggro_golive_mc.log`）。 | §4.2 / §5.3 |
| **A-6** | `docs/phase3/aggro-0*.png`（5 张 · 临时脚本 `tests/_tmp_aggro_shots.gd` 驱动，**已删除**） | 窗口模式实机截帧 5 态（起手保护 / 锁定即停 / 塔 Disabled / 处置弹窗 / Sapper 锁塔）。 | §5.2 |
| **A-7** | `docs/phase3/tower-aggro-golive-impl.md`（本文件） | 落地记录。 | §5.3 |

> 🔴 **未改动**：一切定稿数值（`ATTRITION=1.50` / `AGGRO_R=9.0` / `AGGRO_EXIT=10.8` / `HP0=120` /
> `tower_stack_exp=0.6` / `WARMUP=2` / `SAPPER_DMG_MULT=3.0` / 塔位6 / `SLOTS6` / `SPAWN_RADIUS=55` /
> 核心 HP 1000 / 漏怪 50 / `hp_growth=1.42` / 三原型表 / `ELITE_*` / `κ_r=0.050` / 三条守恒）。
> 🔴 **金标本 `wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` 一字未改。**

---

## 2. 关键架构决策

- **合并镜像 = 逐位忠实真身**：三轴合并镜像存在的意义是"实机全开口径的可复现批处理镜像"，
  故 ② 集火相位**恒 assign**（= 真身 `_stable_sort_by_remain` 原地排序语义），**不**按轴条件归约。
- **退化守护 = 对标真身**：②（proto OFF + aggro ON）与 ④（全开）两条守护用 **headless 驱动真实
  `WaveDirector`** 逐波比对，而非与旧镜像 `run_loop_aggro` 相等（后者 ② 不忠实，见 §4-1）。
- **`core_hp` 场景隔离**：逐波比对时把核心 HP 抬高（`BIG_CORE=1e9`）以隔离真身"核心归零即中断
  本波"（run-loop 层行为）与批处理"跑满本波"的固有差异 —— 直测**战斗口径**（kills/leaked/scrap/
  dps/towers_disabled）。`core_hp` 不参与 `dps_only` / 任何乘区，零战斗影响。

---

## 3. 验收证据（原始输出）

### 3.1 默认回归（逐位不变）— ✅

```
汇总：通过 222 项 / 失败 0 项        （切片1）
汇总：通过 2228 项 / 失败 0 项       （切片2）
汇总：通过 142 项 / 失败 0 项        （切片3）
汇总：通过 123 项 / 失败 0 项        （切片4）
汇总：通过 302 项 / 失败 0 项        （切片5）
汇总：通过 41 项 / 失败 0 项         （切片6）
汇总：通过 31 项 / 失败 0 项         （切片7）
切片8 合计：PASS=92  FAIL=0          （切片8）
T1 仇恨 汇总：通过 216 项 / 失败 0 项 （T1）
EXIT=0
```
九段聚合 `222/2228/142/123/302/41/31/92/216` **逐位一致**（spec §5.1）。

### 3.2 radial8 聚合闸门 — ✅

```
[PASS] geo8(套件) / radial(套件) / geo8_smoke / geo8_golden / expo / bulwark8 / panorama8 / attrition8
radial8 结论：PASS（exit 0）
```
8/8 子套件 PASS（spec §5.1）。

### 3.3 退化逐位守护（A-3）— ✅ 52 项通过 / 0 失败

```
守护①  aggro=false → == run_loop_proto（A/B 逐位 |d|=0；且 dis_new 合计=0）
守护②  proto/elite=false + aggro → == 真身（PATH/geo6 · RADIAL/geo6 · RADIAL/geo8 × A/B × W3/W5/W8，逐位 |d|=0）
守护③  三轴全 OFF → == 金标本 run_loop（A/B 逐位 |d|=0）
守护④  全开 → == 真身（同上矩阵，逐位 |d|=0）       ← 上线门禁可信度地基
交叉    Sapper（elite 驱动）== 真身（W5/W10，逐位 |d|=0）
交叉    全开 B：40 局 dis_new 合计=188（仇恨/塔损耗确在用）
自检    守护②/④场景确曾出现 towers_disabled>0（非空转）
汇总：通过 52 项 / 失败 0 项   EXIT=0
```
> 说明：逐波比对时若核心 HP=1000，真身会在"第 20 次漏怪（=1000/50）"时 `run_failed` 中断本波，
> 而批处理跑满本波 → 出现 `真身 leaked=20 vs 合并 leaked>20` 的 **run_loop 层**差。抬高核心
> （`BIG_CORE`）消除该差异后，两口径逐位一致（kills/leaked/scrap/dps/towers_disabled）。

### 3.4 全开 MC（A-4）— 🔴 门禁破线

口径：`SpaceModel.mode=RADIAL` + `prototype_split_enabled` + `elite_waves_enabled` +
`tower_aggro_enabled`（`repair_on_disable=0`）；`seed=20260930`；每点 300 局。

```
---- n_slots=6（实机默认 · 门禁臂）----
  [A 单核] 起飞率=0.217  存活率=0.217  中位起飞波=8.0   平均结算波=8.87  (起飞 65/300)
       核心 HP 分布  0(失守):235  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:65  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:65  1塔:0  2塔:235  3塔:0  4塔:0  5塔:0  6塔:0   均值=1.567
  [B 多塔] 起飞率=0.677  存活率=0.787  中位起飞波=13.0  平均结算波=17.41  (起飞 203/300)
       核心 HP 分布  0(失守):64  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:2  hp==1000(满):234
       末波 Disabled 塔数分布  0塔:18  1塔:53  2塔:77  3塔:68  4塔:18  5塔:3  6塔:63   均值=2.920

---- n_slots=8（八槽径向 · 参考臂 · Q-R9 未批准为出货配置）----
  [A 单核] 起飞率=0.187  存活率=0.187  中位起飞波=8.0   平均结算波=8.48  (起飞 56/300)
  [B 多塔] 起飞率=0.773  存活率=0.893  中位起飞波=13.0  平均结算波=18.91  (起飞 232/300)
       末波 Disabled 塔数分布  0塔:0  1塔:34  2塔:94  3塔:73  4塔:37  5塔:18  6塔:12  7塔:1  8塔:31   均值=3.353

门禁判定（spec §4.2 · 多塔 B 起飞率 ≥ 0.80 · n_slots=6）
  [FAIL] B(n_slots=6) 起飞率 0.677 < 0.80  🔴 破线 → 不得上线，如实上报，禁止自行改数值
  [INFO] B(n_slots=8) 起飞率 0.773 / A 起飞率 0.187（八槽参考臂）
EXIT=1
```

### 3.5 实机截帧（A-6 · 窗口模式 1920×1080）— ✅ 5 态落盘

驱动：`tests/_tmp_aggro_shots.gd`（**临时脚本，用后删除**，见 §3.5.3）；环境 NVIDIA RTX 5060 / OpenGL 3.3 / 视口 1920×1080。
产出目录 `docs/phase3/`：

| 文件 | 场景 | 观察点 | 结果 |
|---|---|---|---|
| `aggro-06-warmup-w1-no-lock.png` | W1（WARMUP=2 保护窗内） | 起手保护：怪物**未被锁定** | `locked=false` ✅ |
| `aggro-01-02-monster-stop-orange-ring.png` | W3 · 单塔 `[2]`（`_wd.dps=0` 诊断让怪行军至塔环） | ① 机会仇恨锁定 + ② 锁定怪**停止前进**（`t_remain` 冻结）；橙环提示 | `locked=true` · 推进 57 step ✅ |
| `aggro-03-tower-disabled.png` | 塔被击破进入 Disabled 中间态 | ③ 塔 Disabled（仍占位） | `disabled=true` · 9 step ⚠️（见 §4-3：战场视觉不可辨） |
| `aggro-04-safe-window-repair-dialog.png` | 波间安全窗 · 触发处置弹窗 | ④ 「受损塔处置（2 座 · 波次间安全窗）」弹窗 | 弹窗正常显示 ⚠️（文案 `%d` 未转义 bug，见 §4-3/§4-4） |
| `aggro-05-sapper-elite-lock.png` | W5 精英/Sapper 波 | ⑤ Sapper 无视 `AGGRO_R` 锁最近塔 | `sapper_locked=true` · 31 step ✅ |

日志片段：
```
[shot] aggro-04-safe-window-repair-dialog → …/aggro-04-safe-window-repair-dialog.png (1920×1080) err=0
ERROR: String formatting error: unsupported format character. at: _make_row (res://scripts/ui/disabled_tower_dialog.gd:155)
```

**诚实备注（①②③ 视觉）**：锁定怪的"停止前进"以**冻结位置**呈现（蓝环为主，橙环在 W3 场景较微弱）；
③ 的 Disabled 塔因 `revive_ui=false`（`repair_on_disable=0`）**战场外观与正常塔一致**——即 A-6 在实机上
**证实了 §4-3 的视觉耦合问题**，非渲染失败。

#### 3.5.3 临时脚本处置

`tests/_tmp_aggro_shots.gd` 与 `tests/_tmp_win_probe.gd` **已删除**（主理人裁定：`tests/_tmp_*` 与
`scripts/engine/_tmp_*` 收尾必须删除；跨断言若需 assign 版镜像，用正式（非 `_tmp_`）夹具或内联）。

---

## 4. 偏差登记（🔴 不判等 · 供后续 ADR）

### 4-1. `wave_sim_aggro.gd:189` ② 相位 = no-op（**既有缺陷**，非本刀引入）

- **根因**：`wave_sim_aggro.gd:189` 写的是 `_stable_sort_by_time(monsters)`——**丢弃返回值** →
  恒 no-op（保持插入序）；而真身 `_substep:365` 是 `_stable_sort_by_remain()`（**原地排序** =
  assign 语义）。无 aggro 冻结时，插入序 ≡ 升序（等价）；一旦 aggro 冻结某些怪的 `t_remain`，
  插入序不再升序 → 分歧显现。
- **可观测影响**（早期会话，300 局整局对拍 · 见 spec §3.4）：A 路径 **0 格**；B 路径 **129 格**
  （首个分歧 run34 W19）；B + Sapper 开 **9570 格**。
- **本刀复现（40 局 · `-- aggro_golive` 登记 INFO）**：旧 `run_loop_aggro`(②no-op) vs 合并
  `run_loop_proto_aggro`(②assign) —— A：0 格；B：4 格；B+Sapper：4 格。（规模随局数缩放。）
- **裁决（主理人 2026-10-10）**：合并镜像 ② 恒 assign（统一语义优先）；守护②改对标真身；
  🔴 **`wave_sim_aggro` 本刀不动**（改它会漂移 T1 聚合读数、且属定稿件 → 超范围）。
- 🔴 **债务（务必登记）**：**T1 既有 aggro 定稿读数**（A 无保护 **0.393** / A 保主力塔 **0.583** /
  A 理想肉盾 0.623 / B **0.883** / Sapper 对照 A 0.393→0.400、B 0.883→0.857）**是在这份"不忠实于
  真身"的旧镜像上测得 → 不能直接作为上线预期**。**权威口径 = 本刀新的忠实 all-ON MC**。
- **建议**：后续单独立 **ADR** 修 `wave_sim_aggro` ②（改 assign）+ 重扫 T1 定稿（含 V-1
  `ATTRITION=1.50`）—— 🔴 **本刀不开工**。

### 4-2. 上线门禁破线（B@6 = 0.677 < 0.80）

- **不是 bug**：新忠实口径与旧镜像读数（B=0.883）本就**预期不同**（见 §4-1 债务）；本读数是在
  **忠实真身**的三轴合并镜像上测得 → 可信。
- **画像**：B@6 存活 0.787（234/300 满血），但**起飞率**仅 0.677——大量局**存活但未起飞**
  （ratio 未达 1.0）。末波 **63/300 局 6 塔全 Disabled**（仇恨把多塔流打残）+ 均值 2.920 座受损。
- 🔴 **处置 = 如实上报、停下**（未调数值 / 未下调阈值）。等主理人 / 用户裁决。

### 4-3. Disabled 塔战场视觉（A-6 观察）

- `monster_layer.gd` 的停机压暗（`_draw_radial_towers` / `_draw_towers` 的 `if _revive_on() and
  _is_disabled(slot)`）**仅当 `revive_ui` 为真**（= 仇恨开 **且** `repair_on_disable >= 9`）才绘制。
- 上线口径 `repair_on_disable=0` → `revive_ui` 恒 false → **战场上一座 Disabled 塔与正常塔外观一致**
  （"仍占塔位"成立，但"Disabled 视觉"不可辨）。可将"停机仍有视觉"从 `revive_ui` 解耦（仅由
  `tower_aggro_enabled` 门控）—— **属新工作，本刀未做**（§5 未决）。
- 现阶段 Disabled 态的可读性由 **安全窗「处置受损塔 (N)」弹窗**（`disabled_tower_dialog`）承担。

### 4-4. `disabled_tower_dialog.gd:155` 字符串格式化错误（**既有缺陷**，A-6 实机暴露）

- **现象**：安全窗处置弹窗中"被动拆除"行的 `%d` **未被替换**，直接以字面 `%d` 显示；运行时打印
  `ERROR: String formatting error: unsupported format character`。
- **根因**：L155 `hint.text = "修复 %d 分（回满 HP · 保留装配卡）｜ 被动拆除（返还 0% · 销毁 %d 层）"`
  —— 文案里的字面 **`0%`** 未转义成 `%%`，被 Godot `String % [...]` 当作格式符 → 整串格式化失败。
- **范围**：**本刀之外**（属既有 UI 文案缺陷，非仇恨上线引入）；🔴 **未修改**，仅登记。
- **修法建议**：将 `返还 0%` 改为 `返还 0%%`（或改用 `%s` 占位 / 直接内插）。

---

## 5. 未决项 / 待主理人裁决

> 🔵 状态更新（B 轮 · 2026-10-10，见 §7）：1 已处置、3 明确不修、5 已修；2 / 4 维持未决。

1. ✅ **已处置（B 轮）** ~~🔴 **上线门禁破线**（§4-2）：B@6 = 0.677 < 0.80，是否 (a) 保持不上线、(b) 调平衡底盘、(c) 修订门禁口径。~~
   → 用户拍板（D7）：**(a) 不上线**（回退 `boot.gd` 开关）+ **补全「玩家安全窗修复口径」并重测**。
   口径矩阵（§7.4）证：OFF(下界) **0.677** / FREE(上界) **0.877** / **PRICED(最接近产品) 0.850 ≥ 0.80 ✅**。
   🔴 **不得自行上线**，待主理人向用户呈请后再定。**仍未动任何数值 / 阈值。**
2. 🟡 `wave_sim_aggro` ② 修复 + T1 定稿重扫（§4-1）—— 是否立项单独 ADR。**（仍未决）**
3. 🔴 **明确不修（B 轮）**：Disabled 塔战场视觉与 `revive_ui` 解耦（§4-3）—— 用户明确选「不做」
   （Disabled 态可读性由安全窗「处置受损塔 (N)」弹窗承担）。
4. 🟡 n_slots=6 在 RADIAL 下仍用 `Geo6.SLOTS6`（PATH 塔位坐标）；八槽才用 `Geo8`（径向坐标）。
   门禁臂（6 槽）几何口径是否需与径向一致 —— 已与第 4 刀 MC 保持一致（未改）。**（仍未决）**
5. ✅ **已修（B 轮 · B-4）**：~~`disabled_tower_dialog.gd:155` 文案 `%` 未转义（§4-4）~~
   → 已改 `返还 0%` 为 `返还 0%%`（see §7.2 / §7.3.4），消除 `String formatting error` 与 `%d` 残留。

---

## 6. 回滚

- A-1：删除 `boot.gd` 窗口分支的 `tower_aggro_enabled = true`（或设回 false）+ 删对应 print。一行回退。
- A-2/A-3/A-4/A-5/A-6：均为**新增**文件 / 新增步骤，删除即回退，不影响既有路径。
- 🔴 三条零扰动路径（aggro OFF / proto OFF / `repair_on_disable=0`）**逐位保持**（§3.1 默认回归已证）。

---

## 7. B 轮（2026-10-10）· 门禁破线后的处置（不上线 + 补全口径 + 修 bug）

> 工单来源：用户 2026-10-10 拍板（spec §7 **D7**）；前接 §4-2（门禁破线 B@6 = 0.677 < 0.80）。
> 落地：程基岩（engineering-lead）· 主理人游承峰调度。

### 7.1 一句话结论

**第五刀 aggro 不上线**（回退窗口开关 → 实机保持第四刀口径）；
**「玩家安全窗修复口径」补全后达标**：实机全开口径下 **PRICED（最接近产品）B@6 = 0.850 ≥ 0.80**
（FREE 上界 0.877 / OFF 下界 0.677）。
🔴 **不得自行上线**（待主理人向用户呈请）。零定稿数值改动 / **未下调阈值** / **未挑口径**。
🟢 零扰动已**端到端**证实：`repair_on_disable=0` 基线臂本脚本自检**逐位复现** 203/300 = 0.677。

### 7.2 改动清单（B-1 ~ B-5）

| # | 文件:行 | 改动 | 工单 |
|---|---|---|---|
| **B-1** | `scripts/ui/boot.gd`（L35–55） | **删除**窗口分支的 `bs.wave_director.tower_aggro_enabled = true` 与 `print("[boot] aggro ON…")`；注释明确「第五刀 aggro **未上线**（B@6=0.677<0.80，见本文件 §4-2），待玩家修复口径补全后重评」；新增运行期 `print("[boot] aggro OFF（第五刀未上线 …）")` + 一行回滚说明。🔴 `prototype_split_enabled` / `elite_waves_enabled` 保持 `true`。 | B-1 |
| **B-2** | `.github/workflows/ci.yml`（step L122–129 · 头注 L9–17） | 「实机全开 MC」步加 `continue-on-error: true`（**非阻断诊断**）+ 显式注释「🔴 当前已知破线（B@6=0.677<0.80，见 tower-aggro-golive-impl.md §4-2）→ 本步为诊断（不阻断）；待达标后转回硬门禁」。🔴 默认回归 / radial8 / aggro_golive 守护 / 实机口径 MC(proto/elite) **四步保持阻断**。 | B-2 |
| **B-3a** | `scripts/engine/run_loop_proto_aggro.gd` | 补 V-7 修复接线（**逐字移植**自 `run_loop_aggro.gd`）：`diag_out` 参数 + diag 注入守卫 + `repair_on_disable==1`（FREE）波次间全修 + `[4]/[5]` 计数；新增 `_WaveSimAggro` preload。🔴 `shop_ai.gd` / `wave_sim.gd` / `run_loop.gd` / `wave_sim_aggro.gd` **一字未改**。 | B-3 |
| **B-3a′** | `tests/test_suite_aggro_golive.gd` | 新增**守护⑤**（repair=0 零扰动）：全开 · repair=0「传 diag 容器 vs 不传」逐位一致 + diag 容器全程零写入。 | B-3 |
| **B-3b** | `tests/run_slice_aggro_golive_mc.gd` | 扩成**口径矩阵**：`repair_on_disable ∈ {0,1,2}` × `n_slots {6,8}` × `A/B`（12 臂 × 300 局，seed=20260930）；逐臂输出 + 修复成交次数 + OFF 基线自检 + PRICED 主判。 | B-3 |
| **B-4** | `scripts/ui/disabled_tower_dialog.gd:155` | `返还 0%` → `返还 0%%`（字面 `%` 转义）。🔴 未动「Disabled 塔战场视觉与 `revive_ui` 解耦」（用户选「不做」）。 | B-4 |
| **B-5** | 本文件 | 追加 §7（B 轮）+ 原始读数 + 更新 §5。 | B-5 |

> 🔴 **未改动任何定稿数值**：`ATTRITION=1.50` / `AGGRO_R=9.0` / `AGGRO_EXIT=10.8` / `HP0=120` /
> `tower_stack_exp=0.6` / `WARMUP=2` / `SAPPER_DMG_MULT=3.0` / 塔位6 / `SLOTS6` / `SPAWN_RADIUS=55` /
> 核心 HP 1000 / 漏怪 50 / `hp_growth=1.42` / 三原型表 / `ELITE_*` / `κ_r=0.050` / 三条守恒 /
> **门禁阈值 0.80**。
> 🔴 **金标本 `wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` 一字未改**；`wave_sim_aggro.gd` **未动**。

### 7.3 验收证据（原始输出）

命令（Windows + Git Bash）：
```
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
```

#### 7.3.1 默认回归（逐位不变）— ✅ EXIT=0

```
汇总：通过 222 项 / 失败 0 项        （切片1）
汇总：通过 2228 项 / 失败 0 项       （切片2）
汇总：通过 142 项 / 失败 0 项        （切片3）
汇总：通过 123 项 / 失败 0 项        （切片4）
汇总：通过 302 项 / 失败 0 项        （切片5）
汇总：通过 41 项 / 失败 0 项         （切片6）
汇总：通过 31 项 / 失败 0 项         （切片7）
切片8 合计：PASS=92  FAIL=0          （切片8）
T1 仇恨 汇总：通过 216 项 / 失败 0 项 （T1）
EXIT=0
```
九段聚合 `222/2228/142/123/302/41/31/92/216` **逐位一致**（spec §4.1 / §5.1）。

#### 7.3.2 `-- aggro_golive` 退化逐位守护（含守护⑤）— ✅ 56 项通过 / 0 失败 · EXIT=0

```
守护①  aggro=false → == run_loop_proto（A/B 逐位 |d|=0；dis_new 合计=0）
守护②  proto/elite=false + aggro → == 真身（PATH/geo6 · RADIAL/geo6 · RADIAL/geo8 × A/B × W3/W5/W8，逐位 |d|=0）
守护③  三轴全 OFF → == 金标本 run_loop（A/B 逐位 |d|=0）
守护④  全开 → == 真身（同上矩阵，逐位 |d|=0）
守护⑤  repair=0 零扰动（B 轮新增）：
   [PASS] 守护⑤ A（全开 · repair=0 · 传 diag 容器 vs 不传）（40 局 × ≤20 波 · 逐位 |d|=0）
   [PASS] 守护⑤ A：repair=0 → diag 容器全程零写入（注入守卫生效 · 0 档零扰动）
   [PASS] 守护⑤ B（全开 · repair=0 · 传 diag 容器 vs 不传）（40 局 × ≤20 波 · 逐位 |d|=0）
   [PASS] 守护⑤ B：repair=0 → diag 容器全程零写入（注入守卫生效 · 0 档零扰动）
交叉    Sapper（elite 驱动）== 真身（W5/W10，逐位 |d|=0）
交叉    全开 B：40 局 dis_new 合计=188
自检    守护②/④场景确曾出现 towers_disabled>0（非空转）
aggro_golive 退化守护 汇总：通过 56 项 / 失败 0 项   EXIT=0
```
> 说明：守护⑤ 钉死 B-3 新增修复接线在 `repair_on_disable=0` 时**零扰动**（不注入 diag、不挂
> FREE 清塔）→ 全开跑序与「无接线」逐位一致；配合 §7.4 的 OFF 基线端到端复现（203/300），
> 「0 档零扰动」由**结构 + 数值**双重证据支撑。

#### 7.3.3 `-- radial8` 聚合闸门 — ✅ 8-8 PASS · EXIT=0

```
[PASS] geo8(套件) / radial(套件) / geo8_smoke / geo8_golden / expo / bulwark8 / panorama8 / attrition8
radial8 汇总（8 项 · 总耗时 123.5 s）
radial8 结论：PASS（exit 0）
```
（`attrition8` 仍走旧 `run_loop_aggro`，B 起飞率 0.913 —— 与 B 轮无关，未动 `wave_sim_aggro`。）

#### 7.3.4 B-4 `%` 转义修复 — ✅（临时自检脚本，已删除）

```
  [修复串] [修复 4 分（回满 HP · 保留装配卡）｜ 被动拆除（返还 0% · 销毁 2 层）]
  [修复串] 含字面 %d ? false
ERROR: String formatting error: unsupported format character.   ← 旧串对照，复现原缺陷
  [旧串·对照] [修复 %d 分（回满 HP · 保留装配卡）｜ 被动拆除（返还 0% · 销毁 %d 层）]
  [弹窗实际文本] [塔位 S3 · 累计投入 20 分 · 装配 2 层 || 修复 4 分（回满 HP · 保留装配卡）｜ 被动拆除（返还 0% · 销毁 2 层） || ]
  [弹窗] 含字面 %d ? false
  [弹窗] 含『返还 0%』? true
```
> 真实弹窗组件（`DisabledTowerDialog.show_towers` → `_make_row`）实际渲染文本：
> hint `%d` 全部正确替换、无字面 `%d` 残留、无 `String formatting error`；旧串对照精确复现原缺陷。

### 7.4 口径矩阵原始读数（B-3b · 12 臂 × 300 局 · seed=20260930 · EXIT=0）

口径：`RADIAL + prototype_split_enabled + elite_waves_enabled + tower_aggro_enabled`；
`warmup=2`；`κ_r=KR_FINAL=0.050`；`ATTRITION=1.50`。

```
---- n_slots=6（实机默认 · 门禁臂）----
  [repair=0 OFF(基线·下界) · A 单核] 起飞率=0.217  存活率=0.217  中位起飞波=8.0   平均结算波=8.87  (起飞 65/300 · 修复成交 0 次)
       核心 HP 分布  0(失守):235  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:65  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:65  1塔:0  2塔:235  3塔:0  4塔:0  5塔:0  6塔:0   均值=1.567
  [repair=0 OFF(基线·下界) · B 多塔] 起飞率=0.677  存活率=0.787  中位起飞波=13.0  平均结算波=17.41  (起飞 203/300 · 修复成交 0 次)
       核心 HP 分布  0(失守):64  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:2  hp==1000(满):234
       末波 Disabled 塔数分布  0塔:18  1塔:53  2塔:77  3塔:68  4塔:18  5塔:3  6塔:63   均值=2.920
  [repair=1 FREE(上界) · A 单核] 起飞率=0.613  存活率=0.613  中位起飞波=10.0  平均结算波=15.46  (起飞 184/300 · 修复成交 978 次)
       核心 HP 分布  0(失守):116  0<hp<=250:8  250<hp<=500:33  500<hp<=750:92  750<hp<1000:51  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:184  1塔:0  2塔:116  3塔:0  4塔:0  5塔:0  6塔:0   均值=0.773
  [repair=1 FREE(上界) · B 多塔] 起飞率=0.877  存活率=0.980  中位起飞波=14.0  平均结算波=19.83  (起飞 263/300 · 修复成交 944 次)
       核心 HP 分布  0(失守):6  0<hp<=250:1  250<hp<=500:0  500<hp<=750:9  750<hp<1000:36  hp==1000(满):248
       末波 Disabled 塔数分布  0塔:286  1塔:5  2塔:3  3塔:0  4塔:0  5塔:0  6塔:6   均值=0.157
  [repair=2 PRICED(最接近产品) · A 单核] 起飞率=0.650  存活率=0.650  中位起飞波=8.0   平均结算波=15.70  (起飞 195/300 · 修复成交 876 次)
       核心 HP 分布  0(失守):105  0<hp<=250:42  250<hp<=500:20  500<hp<=750:70  750<hp<1000:63  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:195  1塔:1  2塔:104  3塔:0  4塔:0  5塔:0  6塔:0   均值=0.697
  [repair=2 PRICED(最接近产品) · B 多塔] 起飞率=0.850  存活率=0.990  中位起飞波=14.0  平均结算波=19.90  (起飞 255/300 · 修复成交 902 次)
       核心 HP 分布  0(失守):3  0<hp<=250:1  250<hp<=500:0  500<hp<=750:6  750<hp<1000:43  hp==1000(满):247
       末波 Disabled 塔数分布  0塔:277  1塔:11  2塔:9  3塔:0  4塔:1  5塔:0  6塔:2   均值=0.150

---- n_slots=8（八槽径向 · 参考臂 · Q-R9 未批准为出货配置）----
  [repair=0 OFF(基线·下界) · A 单核] 起飞率=0.187  存活率=0.187  中位起飞波=8.0   平均结算波=8.48  (起飞 56/300 · 修复成交 0 次)
       核心 HP 分布  0(失守):244  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:56  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:56  1塔:0  2塔:244  3塔:0  4塔:0  5塔:0  6塔:0  7塔:0  8塔:0   均值=1.627
  [repair=0 OFF(基线·下界) · B 多塔] 起飞率=0.773  存活率=0.893  中位起飞波=13.0  平均结算波=18.91  (起飞 232/300 · 修复成交 0 次)
       核心 HP 分布  0(失守):32  0<hp<=250:0  250<hp<=500:0  500<hp<=750:0  750<hp<1000:3  hp==1000(满):265
       末波 Disabled 塔数分布  0塔:0  1塔:34  2塔:94  3塔:73  4塔:37  5塔:18  6塔:12  7塔:1  8塔:31   均值=3.353
  [repair=1 FREE(上界) · A 单核] 起飞率=0.623  存活率=0.623  中位起飞波=9.0   平均结算波=15.81  (起飞 187/300 · 修复成交 847 次)
       核心 HP 分布  0(失守):113  0<hp<=250:8  250<hp<=500:41  500<hp<=750:75  750<hp<1000:63  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:187  1塔:4  2塔:109  3塔:0  4塔:0  5塔:0  6塔:0  7塔:0  8塔:0   均值=0.740
  [repair=1 FREE(上界) · B 多塔] 起飞率=0.883  存活率=0.993  中位起飞波=13.0  平均结算波=19.95  (起飞 265/300 · 修复成交 1034 次)
       核心 HP 分布  0(失守):2  0<hp<=250:0  250<hp<=500:6  500<hp<=750:2  750<hp<1000:12  hp==1000(满):278
       末波 Disabled 塔数分布  0塔:281  1塔:7  2塔:9  3塔:1  4塔:0  5塔:0  6塔:0  7塔:0  8塔:2   均值=0.147
  [repair=2 PRICED(最接近产品) · A 单核] 起飞率=0.603  存活率=0.603  中位起飞波=8.0   平均结算波=15.35  (起飞 181/300 · 修复成交 876 次)
       核心 HP 分布  0(失守):119  0<hp<=250:34  250<hp<=500:21  500<hp<=750:69  750<hp<1000:57  hp==1000(满):0
       末波 Disabled 塔数分布  0塔:181  1塔:5  2塔:114  3塔:0  4塔:0  5塔:0  6塔:0  7塔:0  8塔:0   均值=0.777
  [repair=2 PRICED(最接近产品) · B 多塔] 起飞率=0.840  存活率=0.993  中位起飞波=13.0  平均结算波=19.94  (起飞 252/300 · 修复成交 1093 次)
       核心 HP 分布  0(失守):2  0<hp<=250:1  250<hp<=500:0  500<hp<=750:5  750<hp<1000:17  hp==1000(满):275
       末波 Disabled 塔数分布  0塔:258  1塔:17  2塔:13  3塔:6  4塔:1  5塔:2  6塔:0  7塔:1  8塔:2   均值=0.327

===============================================================
  门禁判定（spec §4.2 + D7-③ · 主判 = 口径补全后 PRICED 多塔 B 起飞率 ≥ 0.80 · n_slots=6）
===============================================================
  B@6 跨 repair 档位：
    repair=0 OFF(基线·下界)              B@6 = 0.677  (起飞 203/300 · 存活 236/300)
    repair=1 FREE(上界)                  B@6 = 0.877  (起飞 263/300 · 存活 294/300)
    repair=2 PRICED(最接近产品)          B@6 = 0.850  (起飞 255/300 · 存活 297/300)
  [自检] OFF B@6 复现基线 203/300=0.677 ✅（repair 接线零扰动）
  [PASS] 主判 · PRICED B@6 起飞率 0.850 ≥ 0.80  → 口径补全后达标（🔴 不得自行上线，待主理人呈请用户）
  [INFO] FREE   B@6 = 0.877 ／ OFF B@6 = 0.677（口径上/下界）
  [INFO] PRICED B@8 = 0.840 ／ A@8 = 0.603（八槽参考臂）
===============================================================
EXIT=0
```

### 7.5 判读（B-3 · PRICED 臂）

| 口径（B@6） | 起飞率 | 存活率 | 修复成交 / 300 局 | 判定 |
|---|---|---|---|---|
| **OFF**（基线 · 下界 · 从不修塔） | **0.677** | 0.787 | 0 | 破线（原 §4-2 读数，**自检逐位复现**） |
| **FREE**（上界 · 波次间无条件全修） | **0.877** | 0.980 | 944 | ≥ 0.80 ✅（上界） |
| **PRICED**（最接近产品 · `ceil(0.30·(12h+9L))`） | **0.850** | 0.990 | 902 | **≥ 0.80 ✅（主判 · 口径补全后达标）** |

**结论**：
1. ✅ **口径伪影已被排除**：原 §4-2 的 0.677 是「从不使用修复机制的玩家」下界；补全产品实际提供的
   安全窗修复后，**PRICED（最接近产品）B@6 = 0.850 ≥ 0.80**，**FREE 上界 0.877**，二者同向、量级一致
   → 修复机制**确实**是「塔死亡循环」存活率的关键，**不是**靠 FREE 硬抬。
2. 🟢 **修复确在起作用**：PRICED 臂 300 局修复成交 **902 次**（均值 ≈3 次/局），且末波 Disabled 塔数
   分布从 OFF 的「0塔:18 / 6塔:63（崩）」变为 PRICED 的「0塔:277 / 6塔:2」——塔不再成片停机。
3. 🔴 **不上线**（B-1 已回退）；**不得自行上线**——本结论仅表示「口径补全后门禁达标」，
   上线与否**由主理人向用户呈请后拍板**。
4. 🟡 **方向性偏差提示（带着读）**：PRICED 臂的 `repair_cost` 用 AI 侧累计投入**估算**
   `invested_est = 12h + 9L`（`shop_ai.gd:364`，不含涨价/reroll/卸塔历史投入）→ **偏低**近似 →
   PRICED 臂结论**偏乐观**（`v7-repair-on-disable-spec §2.5` 已登记）。真实玩家修复更贵 → 实际可能
   略低于 0.850，但仍在 FREE 上界 0.877 与 OFF 下界 0.677 之间，**与 0.80 的距离需用户知悉**。
5. 🔴 **禁止**：调任何数值 / 改 0.80 阈值 / 为过线挑口径（本轮未做）。

### 7.6 B 轮红线核对

| # | 红线 | 声明 |
|---|---|---|
| 1 | 零定稿数值改动 | ✅ 未动任何定稿数值（含门禁阈值 0.80） |
| 2 | 三条零扰动路径逐位保持 | ✅ aggro OFF（守护①）/ proto OFF（守护③）/ `repair_on_disable=0`（守护⑤ + OFF 基线复现） |
| 3 | 不改判据阈值、不削 B 抬 A、不挑口径 | ✅ 三档全跑、如实上报；主判 = 最接近产品的 PRICED |
| 4 | 金标本零改动 | ✅ `wave_sim.gd` / `run_loop.gd` / `shop_ai.gd` 一字未改；`wave_sim_aggro.gd` 未动 |
| 5 | 双模可回滚 | ✅ `boot.gd` 加回一行即回退；B-2 转回硬门禁删 `continue-on-error` 一行 |
| 6 | 临时脚本收尾删除 | ✅ `tests/_tmp_b4_check.gd` 已删（`**/_tmp_*` 零命中） |
| 7 | 不改 Disabled 塔视觉解耦 | ✅ 用户选「不做」，未动 |
