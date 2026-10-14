# 反制窗口 T1 批次 · 阶段 B（T-CP-02）**独立复核报告**

| 项 | 内容 |
|---|---|
| 复核对象 | `098c89d`（feat C-1~C-7 · 5 文件）· `1b4dabd`（C-8/C-9 + 3 文档）· `4aa8b33`（doc-debt 口径回写） |
| 复核人 | 严守真（quality-lead · QA） |
| 日期 | 2026-10-12 |
| 性质 | 🔴 **独立复核**：逐位 diff 审计 + 独立跑全量回归 + 判别性反证（临时改后立即还原）；**只读源码，不修改任何交付** |
| 引擎 | Godot `v4.7.2.stable`（`Godot_v4.7.2-stable_win64_console.exe` · headless · 串行） |
| 结论 | ✅ **PASS（附 3 项 MINOR + 3 项遗留风险）** —— 工程自报的**每一项读数均被独立复现**，判别性反证**按预期翻红**，零残留 |

> ⚠️ 复核期间工作树有**并发队友提交**（design-strategist 的 `0524f55` docs-only + 后续 review 编辑）。已核：`0524f55` 仅动 `docs/`，**未触碰任何源码**；本报告复核的 5 个源码/测试文件 md5 与复核起点**完全一致**（见 §3 末）。

---

## 0. 逐项判定总表

| # | 复核项 | 判定 | 一句话证据 |
|---|---|---|---|
| 1 | 逐位不变（除新增成员/键/分支/注释外无既有数值或逻辑改动） | ✅ **PASS** | 删除的非注释行仅 = 声明的 C-4/C-5/C-6 UI 重接 + 一行 boot 文案；`wave_director` 无任何既有数值/逻辑行被删改 |
| 2 | 独立跑全量回归 | ✅ **PASS** | `EXIT 0` · `[FAIL]×0` · 九段 `222/2228/142/123/302/41/31/92 + T1 234` = **3415** |
| 3 | 判别性反证（撤 C-2 分支 → AC-CP-1 翻红 → 还原零残留） | ✅ **PASS** | 撤分支 → `EXIT 1` · T1 `231/3` · 3 条 FAIL；还原 → md5 逐位相同 · 复跑 `234/0` |
| 4 | `revive_misq ≡ 0`（三处同读 `_revive_mode()`；off/on 两态恒 0） | ✅ **PASS** | 三处均读 `_revive_mode()`（:239 / :533 / :594）；misq 自增式结构上不可达 → 恒 0 |
| 5 | MC 门禁复算 | ✅ **PASS** | `OFF B@6 = 203/300 = 0.677`（复现基线）· `REVIVE(9) B@6 = 252/300 = 0.840 ≥ 0.80` |
| 6 | UI 数据源与解耦 | ✅ **PASS** | `aggro_ui == tower_aggro_enabled` · `next_is_elite_wave == elite ∧ is_elite(w+1)`；停机压暗挂 `_aggro_ui()`，充能点仍挂 `_revive_on()`（爬起环为事件驱动，见 §6 精确化注） |
| 7 | C-6 分态取源 | ✅ **PASS** | 横幅用**入参 w**；波次条 `st∈{1,2}`(战斗) 用当前波 `is_elite_wave`，否则用 `next_is_elite_wave`；`w` 仅 `start_wave` 自增 → 无 stale |
| 8 | 产物 | ✅ **PASS** | 本文件 |

**总判定：PASS。** 工程三项自报（3415 断言 / 0.840 / 0.677）与 C-9 区间 `[0.747, 0.813]` **均逐位复现**，无一不符。

---

## 1. 复核项 ① · 逐位不变（diff 审计）

命令：`git diff 098c89d~1 098c89d`（5 文件 · +132/−15）。

**删除的非注释行全量清单**（`git diff … | grep '^-' | grep -v '^-#'`，共 9 行）：

```
-  print("[boot] proto/elite/aggro 全 ON（第五刀上线 · RADIAL 实机口径）")   # C-2 文案
-  if _wave_elite:                                                          # C-6
-  _wave_elite = bool(s.get("is_elite_wave", false))                        # C-6
-  draw_string(font, …, "精英波", …)                                          # C-6
-  if _revive_on() and _is_disabled(slot):            （×2 · C-4 停机压暗重接）
-  var icon_r := maxf(5.0, sc * 0.62)                                       # C-5 内联
-  if occupied.has(slot): continue                                          # C-5
-  var ip := Vector2(sp.x, sp.y - maxf(11.0, sc * 1.5))                     # C-5 内联
```

→ **全部为声明的 C-2/C-4/C-5/C-6 UI 改动**，**无一行属于既有玩法数值或逻辑**。

**新增内容确认**（仅四类，与任务口径一致）：
- 新成员 `combat_revive_enabled: bool = false`（默认 off）。
- 新 snapshot 键 `aggro_ui` / `next_is_elite_wave`（**只增**，不改既有键语义；`snapshot()` line 898/899）。
- 新分支：`_revive_mode()` 首行 `if combat_revive_enabled: return 9`；`boot.gd` 窗口分支 `combat_revive_enabled = true`。
- 注释。

**关键常量逐一核验（未被触碰）**：

| 常量 | 位置 | 值 | 判定 |
|---|---|---|---|
| `revive_n_seconds` | `mvp_config.gd:201` | `0.5` | ✅ 未动 |
| `revive_k_per_wave` | `mvp_config.gd:202` | `1` | ✅ 未动 |
| `ATTRITION` | `monster_data.gd:74` | `1.5` | ✅ 未动 |
| `HP0` | `monster_data.gd:107` | `120.0` | ✅ 未动 |
| `SPAWN_RADIUS` | `space_model.gd:58` | `55.0` | ✅ 未动 |
| `core_hp` | `mvp_config.gd:127` | `1000.0` | ✅ 未动 |
| 塔位/槽位 | `n_slots` 仅 MC/扫描脚本按臂设；**源码默认未改** | — | ✅ 未动 |

🔴 **判定 PASS。** 附带说明（诚实口径）：`monster_layer.gd` / `hud.gd` 存在**声明内的既有渲染/文案行为变更**（C-4 停机压暗门控、C-5 占用塔位新增图标、C-6 横幅/波次条取源）。这些是**纯 UI**、不属"既有数值或逻辑"，且**不在 headless 回归覆盖面内**（见 §8 遗留风险 R-3）。

---

## 2. 复核项 ② · 独立全量回归

命令（串行 · 日志重定向）：
```
<godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd  > /tmp/qa_regression.log
```

原始证据：
```
EXIT=0
[FAIL] 计数 = 0
汇总：通过 222   项 / 失败 0 项
汇总：通过 2228  项 / 失败 0 项
汇总：通过 142   项 / 失败 0 项
汇总：通过 123   项 / 失败 0 项
汇总：通过 302   项 / 失败 0 项
汇总：通过 41    项 / 失败 0 项
汇总：通过 31    项 / 失败 0 项
切片8 合计：PASS=92  FAIL=0
T1 仇恨 汇总：通过 234 项 / 失败 0 项
```

| 段 | slice1 | slice2 | slice3 | slice4 | slice5 | slice6 | slice7 | slice8 | T1 |
|---|---|---|---|---|---|---|---|---|---|
| 本次 | 222 | 2228 | 142 | 123 | 302 | 41 | 31 | 92 | **234** |

- **非 T1 八段合计 = 3181** → 与 `.workbuddy/memory/2026-09-30.md:544` 记录的基线 **`222+2228+142+123+302+41+31+92` 逐位相同**。✅
- **T1 = 234 = 220 + 14**。旧值 220 见 `.workbuddy/memory/2026-10-12.md:11`（上批 `216→220`）与 `docs/phase3/counterplay-t1-spec.md:214`（"除 T1 段已知 220 外"）。新增 14 条 = AC-CP-1。✅
- **合计 3415** = 自报值。✅

🔴 **判定 PASS。**

---

## 3. 复核项 ③ · 判别性反证

**操作**：把 `wave_director.gd::_revive_mode()` 首行改为 `if false and combat_revive_enabled:`（撤掉 C-2 关键分支），跑 `run_tests.gd -- t1aggro`。

**原始证据（撤分支后）**：
```
FALSIFY_EXIT=1
[FAIL] combat_revive_enabled=true → _revive_mode()==9      got=0    want=9
[FAIL] 产品开：snapshot revive_ui == true（aggro ∧ ≥9）    got=false want=true
[FAIL] 产品开（cfg 档 0）：revive_fired ≥ 1（M-1 确发生）   got=false want=true
T1 仇恨 汇总：通过 231 项 / 失败 3 项
```
→ **AC-CP-1 按预期翻红**（尤其"产品开视同档 9"与"revive_fired ≥ 1"）。✅ **该守护确具判别性，非橡皮图章。**

**还原与零残留校验**：
```
$ git checkout -- scripts/gameplay/wave_director.gd
$ md5sum scripts/gameplay/wave_director.gd
957766ae0d8167646d102798caed8f94   ← 与复核起点（/tmp/qa_md5_before.txt）逐位相同
$ git diff -- scripts/gameplay/wave_director.gd tests/test_suite_t1_aggro.gd   →  空
$ grep -rn "QA-FALSIFY" scripts/ tests/                                          →  NO RESIDUE
$ <godot> … run_tests.gd -- t1aggro   →  POSTRESTORE_EXIT=0 · [FAIL]×0 · T1 234/0
```
5 个复核文件 md5（还原后 = 起点）：
```
957766ae0d8167646d102798caed8f94  scripts/gameplay/wave_director.gd
eb0398bbfba8e5e91f4c701866e323b8  scripts/ui/hud.gd
a090d3ee0fedfc47471a192251cec6e8  scripts/ui/monster_layer.gd
f37b172de1f25e21407491ff36ce2d60  scripts/ui/boot.gd
58013cd55cfa35fb35fe39db1d7bea4e  tests/test_suite_t1_aggro.gd
```

🔴 **判定 PASS。零残留、零污染。**

---

## 4. 复核项 ④ · `revive_misq ≡ 0`

**三处"同读 `_revive_mode()`"**（`wave_director.gd`）：

| 环节 | 行 | 代码 |
|---|---|---|
| 复位 | 239 | `if _revive_mode() >= 9:`（清 `revive_t_disabled` / `revive_used_w`） |
| 快照取资格 | 533 | `if _revive_mode() >= 9: _death_snapshot(t)`（在 `disabled=true` **之前**） |
| tick | 594 | `var rm := _revive_mode()` → `if … rm < 9 or rm == 11: return` |

（另 `_death_snapshot:672` 读 `_revive_mode()` 仅用于 `revive_elig` 诊断计数 —— 同源，不影响一致性。）

→ 产品开时**三处一致返回 9**；产品关时三处一致返回 cfg（默认 0）。**不会出现"半吊子解耦"分岔**（技术评估 T-CP-R2 风险点被结构性规避）。✅

**misq 恒 0 的结构性理由**（`_try_revive:630-651`）：自增行
```gdscript
if (not bool(t.death_exposed)) or bool(t.death_carry) or (not bool(t.death_valid)):
        revive_diag["revive_misq"] += 1.0
```
位于进入条件 `if death_valid and death_exposed and (not death_carry):` **之内**，其条件恰为该门控的**逻辑取反** → **恒假、不可达**。因此 misq 对 off/on 两态**结构上恒为 0**。

**实跑证据**：全量回归中
```
[PASS] AC-8 硬断言 revive_misq = 0（已落地重启无一违反资格）  got=0.000000 want=0.000000
[PASS] 产品开：revive_misq ≡ 0（硬断言不破）               got=0.000000 want=0.000000
```

🔴 **判定 PASS。** 🟡 精确化注：misq 是**一致性**守护（"启用后的重启未违反资格"），**非激活**守护 —— 撤分支使 revive 完全不发生时它仍是绿的（见 §3）。**"复活真的发生"由独立断言 `revive_fired ≥ 1` 守护**，二者不可互替。

---

## 5. 复核项 ⑤ · MC 门禁复算（C-8）

命令：`<godot> … --script res://tests/run_counterplay_mc.gd`（300 局/臂 · RADIAL · proto+elite+aggro 全开）。

原始证据：
```
[repair=0 OFF(基线·下界) · B 多塔]  起飞率=0.677  (起飞 203/300)
[repair=9 REVIVE(M-1·战斗内复活) · B 多塔]  起飞率=0.840  (起飞 252/300)
    repair=0 OFF(基线·下界)      B@6 = 0.677  (起飞 203/300 · 存活 236/300)
    repair=1 FREE(上界)          B@6 = 0.877  (起飞 263/300 · 存活 294/300)
    repair=2 PRICED(安全窗修复)  B@6 = 0.850  (起飞 255/300 · 存活 297/300)
    repair=9 REVIVE(M-1·战斗内复活)  B@6 = 0.840  (起飞 252/300 · 存活 272/300)
[自检] OFF B@6 复现基线 203/300=0.677 ✅（M-1 接线零扰动）
[PASS] 主判 · REVIVE(9) B@6 起飞率 0.840 ≥ 0.80 → 达标
MC_EXIT=0
```

| 判据 | 期望 | 实测 | 判定 |
|---|---|---|---|
| 自检 OFF B@6 | 复现 `203/300=0.677` | `203/300=0.677` | ✅ |
| 主判 REVIVE(9) B@6 | `≥ 0.80` | `252/300 = 0.840` | ✅ **成立** |

🔴 **判定 PASS。** `0.840 ≥ 0.80` 成立；自检复现基线，接线零扰动。**（🔴 门禁是建议性放行前置——是否上线须用户呈请，非工程自决。脚本自身亦打印此限制。）**

---

## 6. 复核项 ⑥ · UI 数据源与解耦

**数据源**（`wave_director.gd::snapshot()`）：
```gdscript
"aggro_ui": tower_aggro_enabled,                                          # :898
"next_is_elite_wave": elite_waves_enabled and _MonsterData.is_elite_wave(w + 1),  # :899
```
→ 与任务口径**逐字一致**。✅

**C-4 门控换绑**（`monster_layer.gd`，改动前后对比 `git show 098c89d~1:…`）：
- 停机压暗**两处**（`:466` 塔体 / `:1077` 径向）：`_revive_on()` → `_aggro_ui()`。✅
- `_draw_revive_charge`（`:485-487`）：仍 `if not _revive_on(): return`。✅ **未动**。
- `_draw_revive_flash`（`:539`）：本就不挂 `_revive_on()`（见下）。

🟡 **精确化注（与自报措辞的差异）**：任务/技术评估称"充能点 **/** 爬起环**仍挂 `_revive_on()`**"。**充能点正确**；但**爬起环从来不是 `_revive_on()` 门控** —— 它由**事件字典** `_revive_flash` 驱动（`_on_tower_revived` 订阅 `tower_revived` 信号，`:187`），而该信号**只在真实复活发生时**发出。故爬起环在功能上**仍仅随"复活启用"出现**（语义正确），但**字面口径"挂 `_revive_on()`"不准确**。对 C-4 的**实质要求**（"只把停机压暗改挂 `_aggro_ui()`，充能点/爬起环保持复活依赖"）**成立** → 判定 PASS。

🔴 **判定 PASS**（附上述措辞精确化）。

---

## 7. 复核项 ⑦ · C-6 分态取源（无 stale）

`hud.gd`：

- **横幅**（`_on_wave_started(w)`）：用**入参 `w`** + `snapshot().elite_waves_enabled` 现算 `is_elite`，**不再读上一帧残留 `_wave_elite`**。✅（消除技术评估 T-CP-R5 的刷新时序窗口。）
- **波次条**（`_refresh_wave_progress`）：
  ```gdscript
  var st := int(s.get("state", 0))
  _wave_in_combat = (st == 1 or st == 2)      # SPAWNING/FIGHTING
  _wave_elite = (is_elite_wave if _wave_in_combat else next_is_elite_wave)
  ```
  `State`：`IDLE=0 / SPAWNING=1 / FIGHTING=2 / SAFE_WINDOW=3`。战斗态用**当前波**，决策期（IDLE/SAFE_WINDOW）用**下一波预告**。✅

**无 stale 依据**：`w` 仅在 `start_wave`（`:234`）自增 → 安全窗/决策期 `w` 仍指向"刚打完那波"，若读 `is_elite_wave` 会显示残留旗；改读 `next_is_elite_wave`（=`is_elite(w+1)`）**正确回避**。文案亦分态：战斗态 `"精英波"`、决策期 `"下一波：精英波"`，**无数字/无倒计时/无进度条**（T-E1③ / T-C2）。✅

🔴 **判定 PASS。**

---

## 8. 与工程自报的差异 · 遗留风险（诚实登记）

**差异**：无。三项自报（**3415** / **0.840** / **0.677**）与 C-9 区间 **`[0.747, 0.813]`**（`T0=0.747 · T1=0.813 · T2=0.680 · T3=0.777 · T4=0.683`；A `0.203→0.517`）**全部逐位复现**。

**MINOR（非功能 · 建议清理）**：

| ID | 发现 | 影响 |
|---|---|---|
| **MINOR-1** | **ID 命名冲突**：代码守护名为 **`[AC-CP-1]`**，但 `counterplay-t1-spec.md §5.1` 的 **AC-CP-1 = "默认回归零扰动"**（回归级）；该守护的内容实为 spec 的 **AC-CP-2/AC-CP-3**（`revive_ui==true` / `revive_misq≡0`）+ 解耦。 | 🟡 文档/追溯歧义（不影响运行）。建议改名或对齐 spec。 |
| **MINOR-2** | **措辞不精确**：自报/技术评估称爬起环"仍挂 `_revive_on()`"；实为**事件字典驱动**（见 §6）。 | 🟡 语义正确、字面不符；建议订正注释。 |
| **MINOR-3** | **口径框定**：`counterplay-player-arm.md §3.3` 写"实机门禁 = 六槽 B@6 = **0.850**"。`0.850` 实为 **PRICED 臂读数**（亦是 sapper-review §2.3 的"B 无 Sapper"参考臂值），**门禁阈值是 `0.80`**。 | 🟡 易被误读为"阈值=0.850"。建议改为"参考臂读数 0.850 / 门禁阈值 0.80"。 |

**R（遗留风险 · 供后续批次）**：

| ID | 风险 | 说明 / 建议 |
|---|---|---|
| **R-1** | **MC/扫描未直接驱动产品开关** | `run_counterplay_mc.gd` 与 `scan_counterplay_player_arm.gd` 均经**批处理镜像**（`run_loop_proto_aggro`）+ `cfg["repair_on_disable"]=9` 表达"复活"，**不认识** `combat_revive_enabled`（两脚本文档均已明示）。→ 门禁证的是**"机制@档9"**；"产品开关≡档9"的等价性**仅靠 AC-CP-1 一条 `_check_int`** 建立。建议（可选）：未来补一版**实时版 MC** 直接以 `combat_revive_enabled` 驱动，闭合该等价链。 |
| **R-2** | **MC/扫描不在默认回归内** | 二者是独立入口（`run_counterplay_mc.gd` / `scan_counterplay_player_arm.gd`），CI 默认无参回归**不会**跑到。属既有模式；若要求持续守护，需纳入 CI 或门禁入口。 |
| **R-3** | **UI 改动无自动化覆盖** | C-4/C-5/C-6 均为渲染/文案，headless 回归**不覆盖**（依赖人工截帧核验，见 spec AC-CP-5/6/7/11）。C-5 中**占用塔位**由"不画"改为"画小号偏移图标"，为**唯一**既有渲染行为变更点。建议试玩/截帧阶段重点核验。 |
| **R-4** | **misq 非激活守护** | misq 恒 0 是**一致性**保证，不能替代"复活发生"的验证（由 `revive_fired ≥ 1` 承担）。后续评审勿以"misq 绿"当作"复活已被验证"。 |

---

## 9. 复核边界（本报告不做什么）

- 🔴 **未修改任何交付源码/测试**（唯一临时改动 = 判别性反证，已 `git checkout` 还原，md5 与起点逐位相同，无残留）。
- 🔴 **未 push / 未部署**。
- 🟡 **未采信任何工程自报**：全部关键读数由本报告独立实跑生成（原始日志：`/tmp/qa_regression.log`、`/tmp/qa_mc.log`、`/tmp/qa_c9.log`、`/tmp/qa_falsify.log`、`/tmp/qa_t1_postrestore.log`）。
- 🟢 **质量门为建议性（advisory）**：本轮判定 PASS，但"**是否上线 / 发布签字**"由**用户**决定。

---

## 10. 追加复核（T-CP-05 补测 · 另立文档）

`297e558`（T-CP-05）新增的两组测量（③ 六槽定因 `scan_bulwark` 第五臂 · ② N=1000 上限 CI `scan_counterplay_upper_ci`）**晚于本报告原复核范围**，已另立独立复算报告：**`docs/phase3/counterplay-t05-verify.md`**。

要点（详见该文档）：点估计与 CI **全部逐位复现**；z 算法**正确**；发现 **1 项文档转录错误**（② T0 `SE=0.0126` 应为 `0.0134`，脚本无误）+ **1 项判读过度**（③「反向=结构与几何无关」应降级为「倾向结构、幅度几何调制、未确证」）。**均不翻转上游事实层结论。**

---

*报告结束 · 严守真（quality-lead）· T-CP-03（+ T-CP-05 追加见 §10）· 判定：✅ PASS（3 MINOR + 4 遗留风险，均非阻断）*
