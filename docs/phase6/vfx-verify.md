# T-P6-07 · VFX A 档 + 性能伴随 · 独立功能复核

> **复核人**：严守真（quality-lead）· **性质**：独立只读复核（自行重跑/自行写探针，**不采信实现方结论**）
> **被测提交（钉死 `b18aedb`）**：`05da822`(R1) → `99028bb`(VFX) → `32cb1dc`(C3/C4) → `b18aedb`(S5)
> **本轮我未改任何生产代码**（`scripts/**`、`scenes/**`、`project.godot` 零改动、未 push）。
> 新增只读探针：`tests/_qa_vfx_probe.gd`、`tests/_qa_vfx_lifecycle_probe.gd`。原始日志：`ci-logs/_qa_vfx_*.log`。

---

## §0 结论速览

**总体判定：✅ PASS（增量复核后 · 2026-10-13）**

> 首轮复核判 🟡 CONDITIONAL（唯一实质缺陷 `VFX-C3-01`）；工程已修 `633187e`(C3-01) + `9c598af`(PATH-01)，**增量复核通过**（见 §9）。降级为 ✅ PASS。

- ✅ VFX 层（A1/A2/A3）功能正确、零信号、零玩法写入、**零 RNG 消费**、零 `Engine.time_scale` 写、PATH 恒惰性；
- ✅ R1 是**唯一** gameplay 触碰，additive 只读，金标本逐位零扰动；
- ✅ 判据：**默认（PATH）+ `-- radial8`（含 `--radial` 48/0）** 全绿（EXIT=0, `[FAIL]`=0）；**门 = 默认 + `--radial8`**（裁定）；CI 第 1/4 步已硬覆盖；
- ✅ **`VFX-C3-01` 已修复**（`633187e`：键 `(c.x,c.y,sc)`）+ 已修复 `VFX-PATH-01`（`9c598af`：守卫 5→7 容器）；**均为永久 cross-state 守卫覆盖（在 CI 第 4 步内）**，且**负向验证已由我独立复现**（旧码 → 守卫 FAIL）；
- ⚠️ **残余（唯一）缺口**：`vfx_layer._draw()` 的**像素输出**在任何自动门禁之外 → 「未证实（图形路径）· 由 art-director 独立截帧覆盖」。详见 §4。

| # | 项 | 判定 | 关键读数 |
|---|---|---|---|
| 1 | 零扰动回归（PATH 默认 + RADIAL 显式 + 场景 smoke） | ✅ PASS | 默认=**PATH-only**；另补 `-- radial`/`-- radial8`/场景 smoke 全 EXIT=0 |
| 2 | R1 只读键（唯一 gameplay 触碰） | ✅ PASS | 仅 `wave_director.gd` +6，全在 `snapshot()` |
| 3 | PATH 恒不生效 | ✅ PASS | 探针：PATH 下 A3 不生成 · 7 容器全清空 · **`snapshot()` 不被调用**（`_draw` 像素=未证实→art-director） |
| 4 | 零 RNG 消费 | ✅ PASS | 探针：全局 RNG 流跑 VFX 前后**逐位一致** |
| 5 | `Engine.time_scale` 零写 | ✅ PASS | 全仓唯一写 = `time_director.gd:96` |
| 6 | C4 去重等价 / C3 逐帧等价 / 帧时 | ✅ PASS（增量后） | C4 ✅（c/sc 逐位同）· C3 ✅（键充要 + 跟随时序）· `VFX-C3-01` **已修并复核** |
| 7 | S5 徽记 +19% | ✅ PASS | 仅 `R*0.26→R*0.31`；轮廓/半径/色相未动 |
| 8 | 提交洁净 | ✅ PASS | 4 提交仅 ui/scenes/gameplay（修复 2 提交仅 ui/tests） |
| 附 | `_dmg` 生命周期（披露 bug 修复） | ✅ PASS | 上限 40 生效 · 清空无泄漏 · 单条寿命 14 帧 |
| 附2 | `VFX-C3-01` / `VFX-PATH-01` 修复 | ✅ PASS（增量） | 守卫 19/0 exit0；**旧码负向 12→10/2 与 19→17/2 均 EXIT=1**（我独立复现） |

---

## §1 被测范围与提交洁净（项 ⑧）

```
05da822 feat(gameplay) R1
  scripts/gameplay/wave_director.gd | 6 ++++++          (唯一 gameplay 触碰)
99028bb feat(vfx) A 档 VFX 层
  scenes/battle_shop.tscn   |   6 +-                    (load_steps 9→10 + ext_resource + 节点)
  scripts/ui/battle_shop.gd |   9 +                     (_ready 绑定 vfx)
  scripts/ui/vfx_layer.gd   | 579 ++++++++++++ (新增)
32cb1dc perf(ui) C4 描画去重 + C3 几何缓存
  scripts/ui/monster_layer.gd | 63 +++ / 15 ---
b18aedb polish(ui) S5 徽记 +19%
  scripts/ui/monster_layer.gd | 10 +++ / 1 ---
```

- 逐提交 `--name-only` 核过：**仅** `ui/`、`scenes/`、`gameplay/`；**未触碰** `project.godot` / `boot.gd` / `scripts/audio/**` / `tests/**`。✅
- 我**订正**了自查时的一处范围错误（曾用 `git diff 5304edd..b18aedb` 误把音频提交纳入，已改为**逐提交**核验）。

---

## §2 逐项证据

### [1] 零扰动回归（最关键）· ✅ PASS

> 🔴 **口径修正（team-lead 交底 · 我独立复跑确认）**：`run_tests.gd` 有**显式入口分派**（`:110-162`）——**无参默认 = `slice1..slice8 + t1aggro`，全程 PATH 模式**；RADIAL 相关（`-- radial` / `-- radial8` / `-- radial8diag`）**默认不跑**（文件头 `:26` 自注：radial8 含 300 局 MC，独立成一键入口）。⇒ 下表「九段一致」是 **PATH-only** 结论；**故我另跑 RADIAL 两入口**。

| 入口 | 命令 | 读数 |
|---|---|---|
| 默认全量回归（**PATH-only**） | `--headless … --script res://tests/run_tests.gd` | **EXIT=0**，`[FAIL]`=**0**，九段 222/2228/142/123/302/41/31/92/234（与基线**逐位一致**） |
| PATH 金标本（slice1） | 同上次全量 | `[逐波] 原始列最大相对偏差 = 1.712e-16 @ tierB W17`（验收线 1e-6）✅ |
| PATH 金标本（slice2 MC） | 同上 | A：起飞率 69.3% / 中位 W8.0；B：起飞率 91.3% / 存活 100.0% / 中位 W13.0 ✅ |
| PATH MC 前 20 局 | 同上 | A/B `got[0:20] == want[0:20]` 逐局一致 ✅ |
| **RADIAL 阶段0 运动学** | `… run_tests.gd -- radial` | **EXIT=0**（48/0）✅ |
| **RADIAL 聚合闸门** | `… run_tests.gd -- radial8` | **EXIT=0**（33/0 + 48/0）✅ |
| RADIAL 场景 smoke | `… run_slice_radial_smoke.gd` | **EXIT=0**（9/0）✅ **实例化 battle_shop.tscn（含 VfxLayer）** |

| PATH 场景 smoke | `… run_slice3_scene_smoke.gd` | **EXIT=0**（25/0）✅ |

> 结论：PATH 金标本逐位**零变动**（红线守）；RADIAL 逻辑与**场景级**均绿。

### [2] R1 只读键（唯一 gameplay 触碰）· ✅ PASS

`git show 05da822` = `scripts/gameplay/wave_director.gd` **+6**，全在 `snapshot()` 的 `monsters` 循环内（5 行注释 + 1 行代码）：

```gdscript
"index": int(m.index),
```

- 源 = `monster.gd:35` 既有字段（非新增状态）；**0-based、波内唯一、波间重置**（波间重置由 `vfx_layer._update_dmg` 以 `_snap["w"]` 变化清缓存反证）。
- additive + 只读 → 金标本零扰动**实测一致**（见 [1]）；与 `sapper`/`revive_charged`/`aggro_ui` 同族。

### [3] PATH 恒不生效 · ✅ PASS（**运行期证伪**，非读码判定）

> 口径依 team-lead 修正：`is_radial()` 是**纯 static mode 判断**（`space_model.gd:88-89`，默认 `mode=PATH` 见 `:40`），与视口/渲染**无关** ⇒ 本项**可**运行期证伪，不必写"读码判定"。

探针 `tests/_qa_vfx_lifecycle_probe.gd`（设 `mode=PATH` → 注入假数据 → 步进 `_process`）：

```
[probe] (E) PATH: kill 未生成 A3 碎片/环? true
[probe] (E) PATH: 注入 7 容器后 _process → 全清空? true
[probe] (E) PATH: _process 未调用 director.snapshot()? true (before=94 after=94)
```

- **①** `_on_monster_killed` 在 PATH 不生成 A3；
- **②** 向 **7 个状态容器**（`_bolts/_dmg/_dmg_grid/_kf_parts/_kf_rings/_hp_cache/_kill_set`）各注入 1 条假数据 → `_process` 后**全清空**；
- **③（会失败的检验）** PATH 下 `_process` **一次都不读 `snapshot()`**（替身计数器 before==after==94）—— 因 `:174-175` 的 `_snap = director.snapshot()` 在 PATH 早退（`:162-173`）**之后**。
- 读码佐证：`vfx_layer.gd` 三处 `_SpaceModel.is_radial()` 门控 —— `:151`(`_on_monster_killed`)、`:162`(`_process` 早退+清池)、`:496`(`_draw` 早退)。

- 场景级：`run_slice3_scene_smoke.gd`（PATH，含 VfxLayer）25/0。

> **⚠️ 与 engineering-lead 交底的订正**：其表述「headless 下不绘制」**不准确**。我在探针（SubViewport + headless）中**实测 `_draw` 仍被调用**（观测到 `monster_layer._draw` → `_draw_radial_slot_layer` 在 headless 执行）。准确表述应为：**`run_tests.gd` 不加载 `battle_shop.tscn` → 故不覆盖 VfxLayer 的绘制/生命周期路径**（与视口无关）。这不影响本项结论。

> **🔎 边界探察（探针 (E)③ · 信息性 MINOR）**：`_process` 的 PATH 清池**守卫条件只测 5 个容器**（`_bolts/_dmg/_kf_parts/_kf_rings/_hp_cache`），`_dmg_grid`/`_kill_set` **不在守卫**内。探针构造「仅 `_kill_set` 非空」→ 守卫不触发 → **`_kill_set` 残留**（实测 `残留=true (size=1)`）。**危害评估**：`_kill_set` 键为 `int(m.index)`（每波 0-based）→ 集合大小受「单波最大怪数」约束，**有界、不增长无界**；PATH 下**从不被读**（绘制被门控）；生产运行 `mode` 不运行时切换 ⇒ **不可达、不构成缺陷**。仅登记备查。

> **⚠️ 残余未覆盖（**`_draw()` 像素路径**）**：`_process` 状态逻辑由本探针覆盖；但 **`_draw()` 的真实像素输出在任何自动门禁之外**（headless 无真实渲染后端 / 无视觉断言）→ 标 **「未证实（图形路径）」**，**由 art-director 独立截帧覆盖**（**不采信 engineering-lead 自截图作独立证据**）。


### [4] 零 RNG 消费 · ✅ PASS（运行期探针）

`tests/_qa_vfx_lifecycle_probe.gd`（(F) 段）：`seed(424242)` 抽 12 个 `randi()` → 跑 **60 帧** VFX（含 A2 伤害差分 + A3 击杀反馈）→ 再抽 12 个 `randi()`：

```
before=[1748751541, 820756337, 4134149008, …]
after =[1748751541, 820756337, 4134149008, …]     一致? true
```

- 静态：`vfx_layer.gd` **零** `randi/randf/randomize/RandomNumberGenerator/shuffle/pick_random`。
- ⇒ VFX **不消费任何 RNG 流**（全局/实例皆然）→ 玩法随机流不受污染。

### [5] `Engine.time_scale` 零写 · ✅ PASS

- 全仓 `grep -rnE "Engine\.time_scale\s*=" scripts/` → **唯一写 = `scripts/ui/time_director.gd:96`**（时间权威）。
- `audio_director.gd:21`、`vfx_layer.gd:20/:559` 命中均为**注释/文档**（非写）。VFX 层无写。

### [6] C3/C4 等价性 + 帧时 · 🟡 CONDITIONAL（首轮）→ ✅ 修复后 PASS（见 §9）

**(a) C4 去重前提 —— ✅ 成立**（探针 (B)，真代码 `_xform`/`_to_screen`）：

```
viewport (1920,1080): drawer0 本层 c=(960.0,540.0) sc=8.4827586207 | 父层 c=(960.0,540.0) sc=8.4827586207
                     同中心? true   同缩放(逐位)? true
viewport (1920,1920): 同中心? true   同缩放(逐位)? true
```

- 抽屉**收起**时本层 `(c, sc)` 与父层 `battlefield_placeholder._draw_radial_ground` 的 `(vs/2, min((vs.x-96)/116,(vs.y-96)/116))` **逐位相同** → 去掉重复画圆 = **像素等价**。
- 颜色等价前提：两文件 `_env_col` 实现**逐字节相同**（`monster_layer.gd:849-854` ≡ `battlefield_placeholder.gd:115-120`），且 `_env_tier/_env_prev/_env_t` 推进逻辑同构（`:836-844` ≡ `:102-110`）。✅

**(b) C3 逐帧等价 —— ✅ 成立**（探针 (C)：同输入两次重建 `ring0`/`spawn` **顶点逐位一致**；无随机、无漂移）。

**(c) 🔴 缺陷：缓存键漏抽屉维 → 过期（错位）** —— 探针 (A)：

```
viewport (1920,1080): drawer0 sc=8.4827586207 c=(960.0000,540.0000)
                      drawer1 sc=8.4827586207 c=(652.8000,540.0000)   ← sc 逐位相等, c.x 位移 −307.2
                      drawer1 调用后 缓存 spokes[0] 基点=(960.0000,540.0000)
                        跟随 c1(=重建)? false   停在 c0(=过期)? true
viewport (1920,1920): drawer0 sc=15.7241 → drawer1 sc=10.4276（sc 变 → 键变 → 正确重建）
```

见 §3。

**(d) 帧时（窗口模式实测）**：

| 波次 | p50 before（T-P6-02 doc） | p50 **after（我实测）** | Δ |
|---|---|---|---|
| W1 | 3.223 ms | **3.650 ms** | +0.427 |
| W5 | 3.968 ms | **4.151 ms** | +0.183 |
| W10 | 3.322 ms | **3.407 ms** | +0.085 |
| W15 | 2.900 ms | **3.058 ms** | +0.158 |
| W20 | 2.802 ms | **3.022 ms** | +0.220 |
| FPS | 301/255/298/336/349 | 270/243/291/322/328 | — |

- 命令：`<godot> --path . --script res://tests/perf_profile.gd -- 6.0 waves`（DisplayServer=Windows，vsync OFF，Intel Core Ultra 7 265）。
- **⚠️ 口径诚实**：after 略慢，但 **before 与 after 是两次不同 session**（非受控 A/B），差异含机器噪声 + VFX 层新增开销，**不可单独归因 C3/C4**。两轮最坏帧均 ≫ 60Hz 预算（最低 243 FPS）。
- **局限**：帧时探针 in-process 单次采样，C3/C4 的省量（论 ~500 顶点三角重算/帧）**落在噪声带内，未能独立分辨** → 见 §5「未证实」。
- **🔴 成本/收益对照（如实留档）**：**C3/C4 的性能收益「未证实」**（无受控 A/B、落噪声带）；而**同一提交批次引入了缺陷 `VFX-C3-01`**（见 §3）。换言之，**为本批次"性能伴随"支付了 1 个真实缺陷的代价，却未取得可证的收益**。这不是否决（缺陷纯演出、可 1 行修复），但**"更快"在证据上不成立，不应写进本批次的交付理由**。

### [7] S5 徽记 +19% · ✅ PASS

`git show b18aedb` 唯一代码改动（`monster_layer.gd:1176`）：

```gdscript
-	var pts := _ngon(c, R * 0.26, n, rot)
+	var pts := _ngon(c, R * 0.31, n, rot)      # +19.2%
```

- **只动半径**；`n`/`rot`（Arrow=3 / Cannon=4 / Frost=6 原型形）一字未动 → 原型编码不变。
- **外轮廓 8 重对称未触碰**：`_oct8(c, R, 0.0)`、`_oct8(c, R*0.66, PI/8)`、外扩描边 `_oct8(c, R+0.5*U_OUTLINE*sc, 0)` 均未改（本提交仅动 `_draw_radial_tower_glyph`）。
- **塔位半径未动**：`R = U_TOWER*sc`（`U_TOWER=1.70` `:98`）；徽记 0.31R = 0.527u < 塔身 0.66R → 不越剪影；< h≥2 内层细环 0.46R → 不撞内环。
- **色相语言未动**（徽记仍为**形状**第二通道）。

### [附-9] `_dmg` 生命周期（engineering-lead 披露的真实 bug 修复）· ✅ PASS

**🔴 关键订正**：该修复**可在 headless 验证**（`_process`→`_update_dmg` 仅受 `is_radial` 门控，**不**受视口门控）。**且本验证走的是 `_process` 集成路径**（每步调用 `vfx._process(0.05)`，即引擎同款入口 → `_snap=director.snapshot()` → `_update_dmg` **整链**），**非**直调 `_update_dmg`（直调只证"函数对"，不证"调用链对"）。探针 `tests/_qa_vfx_lifecycle_probe.gd`：

```
(D) 单帧 60 个 Δ 后 _dmg.size()=40 (上限 40)
(D) 持续注入 5 帧 峰值 _dmg.size()=40  ≤40? true
(D) 停注入后 …最终 _dmg.size()=0   _dmg_grid.size()=0   →  到期清空(无泄漏)? true
(D) 单条数字: 生成数=1  存活帧数=14 (期望 floor(0.7/0.05)=14)  →  寿命正确? true
```

- 回收路径正确：到期释放、**无泄漏**（`_dmg` 与 `_dmg_grid` 均归零）、**上限 40 生效**（观测峰值恰 40，从不越界）。
- **不提前回收**：单条数字存活 **14 帧** = `floor(DMG_LIFE/dt)`（0.05s/帧）→ 寿命推进精确，非"堆积在 40 上限"。

---

## §3 缺陷报告

### ✅ `VFX-C3-01` — C3 几何缓存键漏「抽屉」维 → 地面几何过期错位（**已修复 `633187e` · 增量复核通过 §9**）

| 字段 | 内容 |
|---|---|
| **严重度** | **Minor**（纯演出/渲染层；**零玩法**、零数值、零信号） |
| **类型** | 缓存失效不完整 → 视觉错位（非"少画"，是"画错位置"） |
| **引入** | `32cb1dc`（C3 几何缓存）—— C3 前每帧用实时 `c` 绘制，无此问题 |
| **环境** | 产品默认档 **1920×1080**（`project.godot` `viewport_width/height=1920/1080`） |

**根因**：
- 缓存键 = `Vector3(sc, vs.x, vs.y)`（`monster_layer.gd:987-988`）；
- 但几何依赖 `c`，而 `c = _to_screen(RADIAL_CORE) = (_field_width()/2, vh/2)`（`:949` + `:318-323`）→ **`c.x` 依赖抽屉开合**；
- `1920×1080` 下 `sc = min((vw-96)/116, (vh-96)/116)` 恒由**高度**项决定（8.4827586207）→ 抽屉开合 **`sc` 不变** → **键不变 → 缓存不重建**。

**影响**：抽屉开合时 `c.x` 位移 **−307.2px**（960→652.8，`drawer_width(1920)=max(560, 614.4)=614.4`），`_radial_geo` 却返回旧中心几何 → **同心环×3 / 放射刻度×8 / 出生环 / 方位刻度**整体错位；因 `sc` 整局恒定，`_geo_sig` 首次绘制后**锁定全程**（首次绘制的抽屉态即"永久中心"）。**未触发条件**：宽度受限窗口（如 1920×1920）——此时 `sc` 随抽屉变 → 键变 → 正确重建。

**证据**：探针 `_qa_vfx_probe.gd` (A) 输出（上 §2[6]）；代码 `monster_layer.gd:987`（键）/`:949`（c）/`:318-323`（`_field_width` 抽屉依赖）。

**建议修法（仅报告，交 engineering-lead）**：把 `c` 纳入键，例如 `Vector3(c.x, c.y, sc)`（几何完全由 `(c, sc)` 决定，且 `c` 已含视口/抽屉信息）或 `Vector4(sc, c.x, c.y, 0)`。

---

## §4 验收门判断（team-lead 请判「run_tests 全量是否足够」）

**判定：`run_tests` 默认入口不足以充当 VFX 批次验收门。**

**理由 1 —— 默认只跑 PATH**：`run_tests.gd` **无参默认 = `slice1..slice8 + t1aggro`，全程 PATH**；`vfx_layer` 只在 RADIAL 生效 ⇒ 默认回归**不覆盖 VFX 批次的作用面**。
⇒ **门定义 = `默认` + `-- radial8`**（team-lead 裁定 · 2026-10-13）。**`-- radial` 冗余**：实测 `--radial8` = **33/0 + 48/0**，其 **48/0 即 radial 阶段0 套件**（`-- radial` 单跑也只是 48/0）⇒ 无需单独步。**已确认 CI 分别覆盖**：第 1 步「默认回归」(`ci.yml:104`) + 第 4 步「radial8 聚合闸门」(`ci.yml:142`)，均**硬门禁（无 continue-on-error）**。✅

**理由 2 —— 都是纯逻辑入口，零覆盖绘制层**：`run_tests.gd`（含 `--radial8`）**不实例化 `battle_shop.tscn`** ⇒

- ❌ **零覆盖 VfxLayer**（A1/A2/A3 的 `_process`、`_update_dmg`、`_draw`）；
- ❌ **零覆盖 C3/C4**（属 `monster_layer` **绘制路径**）；
- ✅ 覆盖 R1（additive 键的金标本零扰动）。

**🔴 残余缺口（须显式登记，勿被"radial8 全绿"掩盖）**（⚠️ 下表为**首轮**快照；**修复后状态见 §9.6**）：
| 面 | 谁覆盖 | 状态（首轮） |
|---|---|---|
| `vfx_layer` **`_process` 对局逻辑** | **仅**本复核探针 `tests/_qa_vfx_probe.gd` / `_qa_vfx_lifecycle_probe.gd` | 自动门禁**之外**（未入 CI） |
| `vfx_layer` **`_draw()` 像素输出** | **仅** art-director 独立截帧 | **任何自动门禁之外** → 标「未证实（图形路径）」 |
| C3/C4 缓存/去重 | 探针（含缺陷 `VFX-C3-01`） | 未入 CI |

> **✅ 修复后更新（§9.5/§9.6）**：第 1、3 行已由 **`vfx_cache_guard`（注册进 `RADIAL8_GATES` → CI 第 4 步）** 覆盖；**仅 `_draw()` 像素行保持"未证实"**。

**建议补齐（非阻塞，可并行）**（更新于 §9）：
1. 🟡 **可不做**：`run_slice_radial_smoke.gd` 入 CI —— 对新守卫**已无必要**（§9.5）；仅"场景实例化不崩"的回归价值，建议 **backlog**（详见 §9.6 意见）。
2. ✅ **已落地**：`VFX-C3-01` 的「抽屉开合 → 几何跟随」headless 断言 = `tests/run_vfx_cache_guard.gd`（cross-state · 2 档视口）。
3. ✅ **已落地**：`_dmg` 生命周期 / PATH 惰性（7 容器判据≡动作）断言已并入 `run_vfx_cache_guard.gd`（[B] 段）。

---

## §5 未证实项（明确标注）

1. **`vfx_layer._draw()` 的真实像素输出** —— **未证实（图形路径）**：headless 无真实渲染后端 + 无视觉断言；**由 art-director 独立截帧覆盖**（**不采信 engineering-lead 自截图**）。
2. **`draw_arc`(128/160) vs `_circle_pts(seg=128/160)` 顶点数是否逐点相同** —— 未独立比对（Godot 内部实现）：几何参数（中心/半径/角度步）一致，差异即使存在亦不可见。**未证实**。
3. **帧时 after/before 的归因** —— 跨 session、非受控 A/B，**C3/C4 省量未独立分辨**。**未证实（需同 session A/B）**。
4. **C4 颜色等价** —— 以「两 `_env_col` 实现逐字节相同 + 同源换装档推进」为读码依据，**未做窗口逐像素比对**。
5. **窗口下 `VFX-C3-01` 的可见幅值** —— 由探针给出**机制与位移量**（307.2px），未在真窗口真帧截图比对观感。

---

## §6 复现（全部命令）

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# [1] 全量回归（PATH 金标本 + 九段）—— ⚠️ 默认只跑 PATH
"$GODOT" --headless --path . --script res://tests/run_tests.gd
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial      # 阶段0 运动学
"$GODOT" --headless --path . --script res://tests/run_tests.gd -- radial8     # 聚合闸门
"$GODOT" --headless --path . --script res://tests/run_slice_radial_smoke.gd
"$GODOT" --headless --path . --script res://tests/run_slice3_scene_smoke.gd

# [3][4][附-9] 独立探针（我新增 · 只读）
"$GODOT" --headless --path . --script res://tests/_qa_vfx_probe.gd            # (A)(B)(C)
"$GODOT" --headless --path . --script res://tests/_qa_vfx_lifecycle_probe.gd  # (D)(E)(F)

# [6] 帧时（窗口模式）
"$GODOT" --path . --script res://tests/perf_profile.gd -- 6.0 waves
```

> ⚠️ 单实例锁：`.godot/` 同刻仅一个 Godot；失败请等 5–10s 重试。

---

## §7 返工建议汇总（交 engineering-lead，我未改生产代码）

| ID | 严重度 | 项 | 建议 | 状态 |
|---|---|---|---|---|
| `VFX-C3-01` | Minor | C3 缓存键漏抽屉维 | 键改为 `(c.x, c.y, sc)` 或含 `c` 的签名；修后补 cross-state 断言 | ✅ **已修 `633187e` + 复核 §9.1/§9.2** |
| `VFX-PATH-01` | 信息性 → 本轮顺手修 | PATH 清池守卫判据≠动作（5 vs 7） | 守卫按复位动作的 **7 容器**同序补齐 | ✅ **已修 `9c598af` + 复核 §9.3/§9.2** |
| G-VFX-1 | 建议 → **降级为 backlog** | CI 覆盖"场景实例化" | `run_slice_radial_smoke.gd` 入 CI —— 对新守卫**已无必要**（§9.5）；价值仅"实例化不崩"回归 | 🟡 **backlog（非阻塞）**，意见见 §9.6 |
| G-VFX-2 | 建议 | `_dmg` 生命周期 / PATH 惰性 / 零 RNG 回归 | 固化探针断言（上限 40 / 无泄漏 / 14 帧 / `snapshot` 不被调用 / `_kill_set` 残留**必须为 false**） | ✅ **已落地 `run_vfx_cache_guard.gd`（入 CI 第 4 步）** |
| G-VFX-3 | **已采纳** | 验收门定义 | = **默认 + `--radial8`**（`--radial` 冗余）；C3/C4 另立断言 | ✅ 已确认（§9.5） |
| D-1 | 表述 | "headless 不绘制" | 已订正并入 §4 覆盖缺口表 | ✅ 已办 |
| D-2 | **Nit（文档）** | `monster_layer.gd:170/:172/:963` 旧注释仍写 `(sc, 视口)`/`(sc, vw, vh) 签名` | 顺手改正为 `(c.x, c.y, sc)`（`:985/:993` 已正确）；**纯注释零行为** | 🟡 待顺手修 |

**放行口径（advisory · 更新）**：`VFX-C3-01` 与本轮新增的 `VFX-PATH-01` **均已修复并被永久守卫覆盖**（§9 增量复核 PASS）⇒ **本批次功能层面可放行**。残留仅 `_draw()` 像素（art-director 截帧）与可选场景 smoke（backlog）。**最终放行由用户决定。**

---

## §8 team-lead 裁定与后续（2026-10-13）

| 项 | 裁定 | 后续 |
|---|---|---|
| `VFX-C3-01` | **本轮修**（本批次引入的**回归**、每次开商店命中、修法 1 行、纯演出零玩法） | 工程落地中：新键 **`Vector3(c.x, c.y, sc)`** + 新增 **`tests/run_vfx_cache_guard.gd`** 并接入 **`run_tests -- radial8`**（cross-state 永久回归网——根因是"无任何 cross-state 检查"）。**待其回报 → 我做增量复核** |
| `VFX-PATH-01` | **本轮顺手修**（判据 `:163-164` 测 5 容器 vs 复位 `:165-171` 重置 7 → **内部矛盾**，非理论风险） | 已派工程；须核 **RADIAL 行为零变化**，有差异则报告而非硬改。我的探针 `残留=true` 反例**须翻为必须 false 的断言**（并入 G-VFX-2） |
| 验收门 | 「不足」**采纳**；门 = **默认 + `--radial8`**（`--radial` **冗余**：radial8 已内含其 48/0） | **批准**加 `run_slice_radial_smoke.gd` 入 CI，**排在修复之后、同批验证**；届时我判「是否还需独立"抽屉开合"步 or 由新断言覆盖即可」 |
| 「headless 不绘制」表述 | **采纳订正**（亦订正 team-lead 说法）→ 正式表述：*要**看见**像素需窗口；`_draw` 的**执行**本身 headless 可观测；真正缺口是 `run_tests.gd` **不加载 `battle_shop.tscn`*** | 已并入 §4 覆盖缺口表（team-lead 采纳为**标准写法**，保留） |
| `_dmg` 生命周期 | **采纳，修复成立** | 固化建议见 G-VFX-2 |
| C3/C4 收益 | 标「**未证实**」获认可；**不额外要求**受控 A/B | 成本/收益对照已留档（§2[6](d)） |
| 音频 [6] | 订正已办；**lint 已入 CI ⇒ 条件关闭** | `audio-verify.md` 条件已关 |

**我的下一步（待命）**：engineering-lead 两项修复（`VFX-C3-01` + `VFX-PATH-01`）落地后，做**增量复核** —— ① 新 key 是否真让缓存随抽屉跟随；② 新 `run_vfx_cache_guard.gd` **能否"抓住旧 bug"**（对着旧代码应 FAIL）；③ `_kill_set` 反例翻为必须 false 的断言是否生效；④ C3/C4 红线项（8 重对称/轮廓/色相/半径）未受影响。**不重跑全量**。

---

## §9 增量复核（`633187e` + `9c598af` · 2026-10-13 · ✅ PASS）

**被测**：`633187e`(VFX-C3-01) + `9c598af`(VFX-PATH-01)。最终 HEAD = `9c598af`，工作区干净（仅未跟踪 `.uid` 与我的探针）。我**未改生产代码、未 push**。

### 9.1 项 ① —— 新键充要性 + 缓存跟随时序 · ✅

- **充要性（读码＋单调用点核）**：`_radial_geo` **完整读入集** = 形参 `{sc, c, rs}` + 常量 `CONCENTRIC_U`（`_circle_pts`/`_dir` 为纯函数）＋自身缓存态 `_geo_sig/_geo` —— **已无任何 `get_viewport()` 读入**（修复删了 `var vs :=` 行）。唯一调用点 `:965` 传 `rs = SPAWN_RADIUS·sc` ⇒ `rs` 对 `sc` 函数依赖被消去。几何 = 环（`_circle_pts(c, ru·sc)`）/ 刻度（`c, rs`）/ 出生环（`c, rs`）/ 方位刻度（`c, rs±0.8·sc`）⇒ **全部由 `(c, sc)` 决定**；`c` 覆盖「视口宽（含抽屉）× 视口高」（`c.y = vh/2` 未丢，故删 `vs` 不丢视口高维）。颜色**不入缓存**（每帧取档）⇒ 无需颜色维。**结论：键 `(c.x,c.y,sc)` 必要且充分，无第三维/第四量在抽屉开合时变化而未进键。**
- **时序（独立探针 `_qa_vfx_probe.gd` 复跑）**：

```
viewport (1920,1080): drawer0 sc=8.4827586207 c=(960,540) | drawer1 sc=8.4827586207 c=(652.8,540)
   drawer1 调用后 缓存 spokes[0] 基点=(652.8,540)  →  跟随 c1(=重建)? true   停在 c0(=过期)? false
viewport (1920,1920): 跟随 c1=true / 停在 c0=false   （B/C 项亦全 true）
```
  ⇒ 修复前 `跟随=false/停c0=true`（首轮读数）→ 现 `跟随=true`。**由我的探针独立确认**（非采信工程）。

### 9.2 项 ② —— 守卫**负向验证**（我独立复现，隔离 worktree）· ✅

用 `git worktree` 建**隔离检出**（不碰主工作区），把 `monster_layer.gd` 退回旧键 / 把 `vfx_layer.gd` 退回旧 5-容器守卫，跑守卫：

| 场景 | 读数 | 期望 | 判定 |
|---|---|---|---|
| **旧键** `Vector3(sc,vs.x,vs.y)` + 守卫[A] | 1080 档 `缓存miss=false · 跟c1=false · 停c0=true` → `G2×2 FAIL` → **10/2** | FAIL | ✅ **EXIT=1**（1920 对照档仍 PASS，与"仅高度受限档复现"机制一致） |
| **旧守卫** 5 容器 + 守卫[A+B] | `[FAIL] 仅 _dmg_grid 非空 → 残留=1` + `[FAIL] 仅 _kill_set 非空 → 残留=1` → **17/2** | FAIL | ✅ **EXIT=1** |
| **修复后全量**（`9c598af`） | **19/0** | PASS | ✅ **EXIT=0** |

> ⇒ 守卫**真能"抓住旧 bug"**（非恒绿/假绿）；engineering-lead 报的 10/2 与 17/2 均被**独立复现**（读数字面一致）。两份原始日志：`ci-logs/_qa_negative_oldkey.log` / `_qa_negative_oldpath.log`。

### 9.3 项 ③ —— `_kill_set` 反例翻为必须 false · ✅

我的探针 `_qa_vfx_lifecycle_probe.gd` (E)③（**我自己写的反例**，非工程的断言）：

- 修复前：`仅 _kill_set 非空 → 残留? true (size=1)`；
- 修复后（`9c598af`）：**`残留? false (size=0)`**。

⇒ 该反例**由 true 翻为 false**，修复生效。**RADIAL 行为零变化**：改动全部位于 `if not _Model.is_radial():` 分支内 ⇒ RADIAL 路径不经此判据；且 `_kill_set` 唯一读点 `_update_dmg` 仅在 RADIAL 调用 ⇒ 仅 PATH 内务改善（有界、从不被读）。

**③ 落位确认（读 `[B]` 段源码 `:151-206`）**：`targets`(`:155`) 含 7 容器含 `_kill_set`；对每个 target **新建独立 VfxLayer 实例**（`set_process(false)` 防引擎补调）→ `_inject_one` **只**置该容器非空（`_kill_set` 注 `{0:true}` `:186-187`）→ `before=_count_nonempty`（须 ==1）→ `_process(0.016)`（PATH）→ `after=_count_nonempty`（须 ==0）。断言 `before==1 and after==0`（`:167`）—— **真 cross-state 反转（1→0），非恒真**；`_count_nonempty`(`:190-206`) 含 `_kill_set`。⇒ 已从"此前无断言"翻成**「步进后必须为空」的硬断言**。

**③′ 内务改善认定（我裁定 · team-lead 请裁项）· ✅ 接受为纯内务改善**
- **零玩法/视觉影响（可证）**：`_kill_set` 唯一读点 = `_update_dmg`，而 `_update_dmg` 只在 RADIAL 分支调用（PATH 早退）⇒ PATH 下**从不被读**；`_dmg_grid` 同理（仅 `_update_dmg` 写）。PATH 走 PATH 分支 → 二者对玩法/渲染无输入。
- **内存**：`_kill_set` 键 = `int(m.index)`，`index` **波内 0-based、波间重置**（R-1 契约）⇒ 键空间受「单波最大怪数」约束 —— **修复前亦非无界**（是"本局内从不回收"，非泄漏）。修复后每帧清空 ⇒ 有界化更彻底。
- **唯一可观测差异**：修复后 PATH 下 `_kill_set` 非空时守卫触发 → 多一次 `queue_redraw()`；而 PATH 的 `_draw` **首行早退**（`vfx_layer.gd:496`）⇒ **零渲染开销**；量级 < 一次 `is_empty()`。**搜索反例未果**（无第三处读 `_kill_set`/`_dmg_grid`）。
- **严格更优**：若将来 PATH→RADIAL 切换，修复**阻止**旧 PATH 段残留 `_kill_set` 污染 RADIAL 首帧差分 ⇒ 无副作用。
- ⇒ **接受**；VFX-PATH-01 定性为**内部一致性/内务修复**（我原判"信息性 MINOR · 不可达/有界/从不读"，team-lead 升级为"本轮顺手修"，**结论一致：零玩法面影响**）。

### 9.4 项 ④ —— C3/C4 红线项未受影响 · ✅

- **默认回归**（我重跑）：**EXIT=0 · `[FAIL]`=0 · 九段 222/2228/142/123/302/41/31/92/234 逐位一致**；golden `1.712e-16 @ tierB W17`；slice2 MC A 69.3%/W8.0 · B 91.3%/W13.0。日志 `ci-logs/_qa_default_post.log`。
- **`-- radial8`**（我重跑）：**EXIT=0 · `[FAIL]`=0 · 9 项**（geo8 33/0 · radial 48/0 · 7 门禁子进程 exit=0，含 **`vfx_cache_guard` exit=0·1636ms**）。日志 `ci-logs/_qa_radial8_post.log`。
- **红线**：两修复**均未触碰** S5/轮廓（`_oct8`）/色相/塔位半径 —— `633187e` 只改键与守卫；`9c598af` 只改 PATH 守卫条件与守卫脚本。

### 9.5 门禁归属确认（回应 team-lead 第三条）· ✅ 成立

- `tests/run_tests.gd` `RADIAL8_GATES`（`:76-86`）含 **`vfx_cache_guard`**；
- `.github/workflows/ci.yml` 第 4 步「radial8 聚合闸门」（`:142-147`）**直接调用** `run_tests.gd -- radial8` ⇒ 该守卫**已落在既有硬门禁内**（无 `continue-on-error`）。
- ⇒ **C3-01 覆盖缺口已由既有 CI 第 4 步关闭，无需新增 CI 步。**（首轮我建议的"加 `run_slice_radial_smoke.gd`"对新守卫**已无必要**。）

### 9.6 残余缺口（更新）

| 面 | 覆盖者 | 状态 |
|---|---|---|
| `vfx_layer._process` 对局逻辑 / PATH 惰性 / `_dmg` 生命周期 | 本复核探针 + **新增 `vfx_cache_guard`（已入 CI 第 4 步）** | ✅ 已进自动门禁 |
| C3 缓存键 cross-state | **`vfx_cache_guard`（已入 CI 第 4 步）** | ✅ 已进自动门禁 |
| `vfx_layer._draw()` **像素输出** | **仅** art-director 独立截帧 | ⚠️ **任何自动门禁之外** → 「未证实（图形路径）」 |
| `battle_shop.tscn` 场景实例化路径 | `run_slice_radial_smoke.gd`（**未入 CI**） | 🟡 **可选、非阻塞** |

> **对"是否值得为场景实例化路径加 CI 步"的意见**：**不值得（本轮）**。理由：① 该 smoke 断言的是**径向逻辑**（v0=5.50 / 朝核心 / 黄金角），已被 `--radial8` 的进程内径向套件（48/0）与 `--radial` 覆盖；② 其**唯一独有价值**是"实例化 `battle_shop.tscn` 不崩"—— 属**回归网**而非**新覆盖面**，且崩溃会以 `exit≠0` 响亮暴露；③ VFX 层已由 `vfx_cache_guard` 直接钉住；④ 成本（CI 时长）与收益不成比例。建议**登记 backlog**，待真引入场景重载/多场景时再评估。

### 9.7 本轮新发现（Nit · 非缺陷）

| ID | 级别 | 位置 | 说明 |
|---|---|---|---|
| `D-2` | Nit（文档） | `monster_layer.gd:170/:172/:963` | 键已改 `(c.x,c.y,sc)`，但三处**旧注释仍写 `(sc, 视口)` / `(sc, vw, vh) 签名`**（`:985/:993` 已正确）。**纯注释、零行为** → 顺手正即可，不阻塞 |

### 9.8 增量复核结论

**✅ PASS** —— ①键充要且跟随正确；②守卫负向**经我隔离复现**（10/2 与 17/2 均 EXIT=1，修复后 19/0 EXIT=0）；③反例已翻为 false；④红线与九段金标本逐位未受影响；⑤守卫已入既有硬门禁。**唯一残余**为 `_draw()` 像素（交 art-director 截帧）与可选场景 smoke（建议 backlog）。**本轮两缺陷均关闭。**
