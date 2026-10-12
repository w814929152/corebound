# 反制窗口落地 · T1 技术评估（只读）

> **任务**：T-CP-01-TECH · 对「反制窗口落地」（P1）做**只读技术评估**，**不改任何代码 / 数值**。
> **作者**：程基岩（engineering-lead）· 引擎 Godot `v4.7.2.stable`
> **日期**：2026-10-XX（本轮）
> **性质**：🔴 **纯只读评估**。本文档不含任何代码改动，所有"改动面"均为**提案**，逐条标注触碰红线与否。
> **口径来源**：`docs/phase3/sapper-balance-review.md` §4-处置 C（反制窗口 = ①暴露度 UI + ②Elite 波预告 + ③T1 肉盾/复活）· `design/gdd/mechanics-bulwark-cycle.md`（M-1 定稿）· `mechanics-tower-life-death.md` §2.2/§2.2.1 · `docs/architecture/control-manifest.md`

---

## 0. 一句话可行性结论

🟢 **可行，且改动面小** —— 反制窗口三项的**机制代码已全部落地**（复活 M-1 在批处理镜像 + 实时版 + UI 三处齐备），本阶段真正要做的**不是"实现机制"，而是三件"产品化解耦"**：

1. **把 M-1 从诊断枚举 `repair_on_disable` 上摘下来**，给一个与 `prototype_split_enabled` / `elite_waves_enabled` / `tower_aggro_enabled` 同族的**产品开关**（默认 off → 金标本零扰动），再由 `boot.gd` 在产品口径打开；
2. **补两处 UI 数据源**（`snapshot()` 增两个只读布尔）+ **一处渲染解耦**（Disabled 压暗从 `revive_ui` 摘到 `aggro_ui`）+ **一处图标扩展**（暴露度图标从空塔位扩到占用塔位）；
3. **Elite 波预告**：`snapshot()` 增一个 `next_is_elite_wave`，HUD 在安全窗画"下一波：精英"。

🔴 **零触碰**：金标本数值 / 默认回归 / `repair_on_disable` 既有 0/1/2 语义 / `revive_misq ≡ 0` 硬断言 / `revive_n_seconds=0.5`·`revive_k_per_wave=1` 定稿值。
🟡 **需用户/主理人拍板项 2 个**：① M-1 产品开关形态（新增成员 vs 复用枚举档 9）；② Disabled 中间态视觉是否本次解耦（用户此前选"不做"）。

---

## §解耦面 · M-1 复活当前如何挂在 `repair_on_disable`

### 1.1 现状：M-1 落在"诊断枚举"的第 9/11 档上

`repair_on_disable` 是一个**多语义枚举**，历史上承载了**两个不同机制**：

| 档位 | 语义 | 归属 | 落点 |
|---|---|---|---|
| `0` | OFF（默认 · 金标本等价口径） | — | `mvp_config.gd:184` |
| `1` | FREE（波次间无条件全修 · 结构探针） | **V-7 诊断臂** | 挂 `run_loop_aggro.gd:105` |
| `2` | PRICED（修复作 shop_ai 候选 · 经济探针） | **V-7 诊断臂** | 挂 `shop_ai.gd:189` |
| `9` | **战斗内即时重启（M-1）** | **V-8 扫描 + M-1 产品** | 挂 `wave_director._tick_revive` |
| `11` | **波首复活（B3 对照臂）** | **V-8 对照臂** | 挂 `wave_director._wave_start_revive` |

🔴 **冲突点**：`mvp_config.gd:177` 的注释白纸黑字写着「**这是诊断工具不是 T1 功能；只在 V-7 三臂扫描里被设非 0**」——但 `9/11` 恰恰就是 **M-1 产品机制**。同一个枚举里，"诊断探针"（1/2）与"产品特性"（9）**混住**。这是"机制可运行"却"不能当产品开"的根因。

### 1.2 运行时如何读这个开关（三处镜像 + 一处 UI）

| 消费点 | 文件:行 | 读法 | 语义 |
|---|---|---|---|
| 实时版波首复位 + 档 11 | `wave_director.gd:231-237` | `_revive_mode() >= 9` → 清 `revive_t_disabled`/`revive_used_w`；`==11` 且 `w>warmup` → `_wave_start_revive()` | 每波配额重来 |
| 实时版战斗中复活 ⑤ | `wave_director.gd:420` → `:580` | `_tick_revive()` 首行 `if rm < 9 or rm == 11: return` | Disabled 满 `N` 秒自动重启 |
| 实时版死亡快照 | `wave_director.gd:525` | `if _revive_mode() >= 9: _death_snapshot(t)` | 在 `disabled=true` **之前**取资格快照 |
| 批处理镜像（无原型） | `wave_sim_aggro.gd:74,77-85,258-259,830-834` | `int(cfg.get("repair_on_disable",0))` 内联 `>=9` | MC 重扫口径 |
| 批处理镜像（原型+Elite） | `wave_sim_proto_aggro.gd:79-87,198-200` | 同上 | 实机口径 MC 重扫 |
| UI 总闸 | `wave_director.snapshot()["revive_ui"]` = `tower_aggro_enabled and _revive_mode() >= 9`（`:877`）→ `monster_layer._revive_on()`（`:506`） | 渲染层只读 | 门控压暗 / 充能点 / 爬起动效 |

`_revive_mode()` 定义：`wave_director.gd:574` = `int(cfg.get("repair_on_disable", 0))`。

### 1.3 要变成"产品特性"需动的面（改动面清单）

> 🎯 **目标**：产品口径（窗口模式）**默认开 M-1**；headless / 测试 / 金标本路径**逐位不变**（开关默认 off）。

**方案 A（推荐 · 新增产品开关，与既有三开关同族）**

| # | 改动点 | 文件 | 具体 | 触碰红线？ |
|---|---|---|---|---|
| A-1 | 新增产品成员 `combat_revive_enabled: bool = false` | `wave_director.gd`（成员区，紧邻 `tower_aggro_enabled:102`） | 与 proto/elite/aggro 同款"结构落定、默认 false"哲学 | 🟢 无（默认 false） |
| A-2 | `_revive_mode()` 改为：`return 9 if combat_revive_enabled else int(cfg.get("repair_on_disable",0))` | `wave_director.gd:574` | 产品走成员，扫描/测试仍走 cfg | 🟢 无（成员 off → 与今日逐位同） |
| A-3 | 产品口径打开 | `boot.gd:53` 之后 | `bs.wave_director.combat_revive_enabled = true` + 一行回滚注释 | 🟢 无（仅窗口分支；headless/`run_tests.gd` 永不进入） |

**方案 B（最小改动 · 复用枚举档 9）**

| # | 改动点 | 文件 | 具体 | 风险 |
|---|---|---|---|---|
| B-1 | 产品口径设 `repair_on_disable = 9` | `boot.gd` + 需让 cfg 生效到 director | 🔴 产品特性骑在"诊断枚举"上；`mvp_config.gd:177` 注释与现实矛盾 | 🟡 语义污染：后续读者/扫描可能误以为 9 是"诊断档" |

> 🏆 **推荐方案 A**。理由：① 与项目既有"产品开关 = `WaveDirector` 布尔成员"模式**完全一致**（proto/elite/aggro 全在成员区，不在 cfg 枚举里）；② `repair_on_disable` 的 **1/2 是 V-7 实验臂**，把产品特性放进同一枚举 = 让"实验臂"与"产品"共享命名空间 → 未来评审/扫描易混淆；③ 方案 A 让**扫描路径与产品路径彻底分轨**（见下 §1.4），是保住对称性的关键。

### 1.4 批处理镜像与实时版的对称性如何保住（`revive_misq ≡ 0` 的硬断言基础）

**对称性现状（已成立，无需新建）**：

- **同一份诊断 schema**：实时版与批处理镜像共用**同一工厂** `wave_sim_aggro._new_v8_diag()`（`:448`）；实时版 `wave_director` preload 它、只调 static 工厂（`:63`、`:230`）。→ 键名/初值逐位相同，单测可逐键比对。
- **同一子步序**：两侧复活段都落在 **④ 仇恨之后**（实时 `:414→:420`；批处理 `:254→:258`），死亡快照都在 `disabled=true` **之前**取（实时 `:525`；批处理 `:832`）。
- **同一硬断言**：两侧 `_try_revive` 都有"**落地后置守卫**"——清完 `disabled` 后复检 `death_exposed ∧ ¬death_carry ∧ death_valid`，违例 `revive_misq += 1`（实时 `:626-627`；批处理 `:566-567`）。
- **逐位对照钩子**：`simulate_wave_aggro(trace_box=...)`（`:62`）在每个子步末尾压 `disabled` 位掩码；实时版单测采同一掩码（`test_suite_t1_aggro.gd:848-870`），**AC-T1-20** 逐位比对。

🔴 **方案 A 下的对称性论证（关键）**：
- **扫描口径**：测试/扫描不设 `combat_revive_enabled`（默认 false）→ `_revive_mode()` 仍返回 `cfg.repair_on_disable` → **实时↔批处理仍读同一个 cfg** → AC-T1-20 逐位对照**不受影响**。
- **产品口径**：成员打开 → 实时版 `_revive_mode()=9`；**产品不走批处理镜像**（MC 扫描是离线资产，用 cfg）→ 无对称性义务。
- **结论**：方案 A **只影响实时版产品路径**，批处理镜像保持 `cfg` 驱动 → **对称性天然保住**，且 `revive_misq ≡ 0` 的基础（两侧同一后置守卫）一行不动。

⚠️ **风险点（须在实装时守住）**：若采用方案 A，**实时版的"每波复位"（`:231`）与"死亡快照"（`:525`）两处也必须改读 `_revive_mode()`**（它们已读 `_revive_mode()`，✅ 无需额外改）。**禁止**只改 `_tick_revive` 而漏改复位/快照 → 会出现"复活发生了但配额没重置/快照没取"的半吊子状态，`revive_misq` 会当场非 0 报警（这正是硬断言存在的意义）。

### 1.5 解耦面结论

| 项 | 判定 |
|---|---|
| 机制实现 | 🟢 **已全部落地**（批处理 ×2 + 实时 + UI），**不是"从零实现"** |
| 真正工作量 | 🟡 **小**：新增 1 个成员 + `_revive_mode()` 1 行 + `boot.gd` 1 行 + 回归断言 |
| 触碰红线 | 🟢 **不触碰**：金标本（`cfg_of()` 不动）、定稿数值（`N=0.5`/`K=1` 不动）、`repair_on_disable` 0/1/2 语义（不动） |
| 默认回归零扰动 | 🟢 **成立**：新开关默认 false → `_revive_mode()` 与今日逐位同 |
| 🟡 文档债务 | 🔴 **必登记**：`mvp_config.gd:177` 注释（"诊断工具不是 T1 功能"）与现实（9/11 = M-1 产品）冲突；`mechanics-bulwark-cycle.md` §12-6/§12-7 状态仍标"欠账"（代码已实现）→ 两处需回写 |

---

## §UI 挂点

### 2.1 暴露度图标：从「空塔位」扩展到「塔信息」的挂点

**现状**：`monster_layer.gd :: _draw_exposure_icons()`（`:573`）**只标空塔位**——`occupied.has(slot) → continue`（`:587`）。已建塔的暴露事实目前仅由"塔身 + 红环"表达（`:692-693`）。
**设计诉求**（`mechanics-bulwark-cycle.md` §6.2）：塔信息 🟢 可复用暴露度图标（⚔/🛡），帮助玩家理解"为什么它上次起来了"（缓解 R-B20 归因不对称）。

**挂点评估**：

| 挂点 | 位置 | 实现量 | 风险 |
|---|---|---|---|
| **(a) 占用塔位绘制徽标**（推荐） | `monster_layer.gd`：把 `_draw_exposure_icons` 的"跳过占用位"改为"占用位画小一号 ⚔/🛡，偏移到塔体上方" | 🟢 小（复用既有 `_draw_cross`/`_draw_shield`） | 🟡 需避让塔体层数点 / 受击闪 / 被攻击橙环 → 靠偏移 + 尺寸控制 |
| **(b) 重决策面板每塔一行** | `shop_overlay._heavy_panel` / `disabled_tower_dialog` 行内加图标 | 🟡 中（需 runtime 额外暴露 per-tower `is_exposed`） | 🟡 引入新数据面 + 需守 SR-R2 |

> 🏆 **推荐 (a)**：零新数据（`_slot_rows` 已算好 `is_exposed`）、纯渲染、决策期显示（非战斗）。**注意**：项目里**没有**独立的"塔信息面板"这一 UI 面（`shop_overlay` 只有商品位 + 重决策按钮组）——"塔信息"若要成为真实 UI 面，需文策渊先定 UI 规格；本阶段按"塔位徽标"落地即可。
> 🔴 **SR-R2 红线**：图标只回答"**会/不会挨打**"（事实），**不得**写"该保这座"（推荐）。

### 2.2 复活事件（`tower_revived` 单向信号）如何只读接 UI

🟢 **已实现，且是正确范式，无需改动**：

- 信号定义：`wave_director.gd:91` `signal tower_revived(slot: int)`，源码注释明示"**单向通知**（导演 → 画面），🈚 任何反向输入路径"（T-E1 边界二的源码级保证）。
- UI 订阅：`monster_layer.bind_director()`（`:181`）连 `tower_revived → _on_tower_revived`；回调（`:187`）**只写画面本地状态** `_revive_flash[slot]`，`queue_redraw()`。
- 播动效：`_draw_revive_flash()`（`:530`）—— 事后扩散环 + 塔身提亮（**运动 + 亮度**，不依赖色相 → 色觉可访问）。
- 🔴 **只读合规**：UI **不持有玩法状态**（`_revive_flash` 是纯演出计时器，同 `_vfx_t`/`_core_flash`），**不发意图、不回写路由**（control-manifest §5）。

> **评估结论**：此挂点**已达成目标**，且天然规避 R-B12（"做成倒计时 UI"）——信号**不携带任何择时读数**（只有 slot），渲染层**无法**据此画倒计时/进度条。**本次无需动。**

### 2.3 Disabled 中间态视觉现状 —— 与 `revive_ui` 耦合的既有缺陷 + 解耦评估

**现状（🔴 确认是既有缺陷）**：
- 塔身"压暗（倒下了）"仅在两处画，且**都门控在 `_revive_on()`**：
  - 实时 `_draw_radial_towers`（`:1068`）：`if _revive_on() and _is_disabled(slot): draw 压暗`
  - PATH 版 `_draw_towers`（`:465`）：同款
- `_revive_on()`（`:506`）= `snapshot()["revive_ui"]` = `tower_aggro_enabled and _revive_mode() >= 9`。
- 🔴 **后果**：当前**实机产品口径 = aggro ON + `repair_on_disable=0`** → `revive_ui=false` → **塔被打停后（`disabled=true`）画面与活塔几乎无区别**（仅靠 HP 差分白闪 `_tower_flash` 间接感知）。这就是"Disabled 中间态视觉与 revive 耦合"造成的可读性缺陷。
- 🟡 用户此前选"**不做**"（不在本轮解耦）。

**解耦评估（本次是否顺带做？）**：

> 🔑 **关键联动**：**若 §1 的 M-1 产品化落地（`combat_revive_enabled=true`）→ `revive_ui` 天然变 true → 压暗自动恢复** → 该缺陷在**产品口径被顺带修好**。因此：

| 场景 | 缺陷是否仍在 | 是否需解耦 |
|---|---|---|
| 产品化 M-1（§1 方案 A 落地） | 🟢 **被掩盖/修复**（`revive_ui` 变 true） | 🟡 **非必需**（可选，为语义清晰） |
| 不产品化 M-1（revive 恒 off） | 🔴 **仍在** | 🔴 **必需** |

**若决定解耦（推荐"顺手"做，成本极低）**：
- 数据面：`snapshot()` 增只读布尔 `"aggro_ui": tower_aggro_enabled`（或 `disabled_ui`）。
- 渲染面：`monster_layer` 把**压暗**从 `_revive_on()` 改挂 `_aggro_ui()`；**充能点 + 爬起环**仍挂 `_revive_on()`（语义分层：压暗 = "它停机了"（aggro 范畴）；充能点 = "它还能不能爬"（revive 范畴））。
- 🔴 **默认回归零扰动**：aggro OFF（金标本路径）→ 两标志皆 false → 画面逐像素不变 ✅。
- 🔴 **红线**：压暗是"**只标事实**（这座塔停机了）"，**不得**编码倒计时/进度（T-C2）。

> 🏆 **评估结论**：**建议本次解耦**（顺手做，1 个 snapshot 字段 + 2 处渲染判断）——理由：① 即便产品化了 M-1，把"停机态视觉"绑在"复活功能"上仍是**语义耦合**（将来谁把 revive 关了，停机视觉又消失）；② 成本极低、零扰动；③ 兑现 `tower-aggro-golive-impl.md:181` 明确的缺口（"Disabled 态可读性由安全窗弹窗承担"= 战斗中不可读）。**但此项可由主理人裁量**——它不在"反制窗口三项"硬清单内。

---

## §预告数据源 · Elite 波预告

### 3.1 `hud.gd` 波次条现状

| 位置 | 行 | 现状 | 供数 |
|---|---|---|---|
| 波次条绘制 | `hud.gd:502-513` | 顶部中央 320×8 进度条（`_wave_progress` = `spawned/n`）；`_wave_elite` 为真时**加红描边 + 右侧"精英波"文字** | 读 `_wave_elite` |
| 数据刷新 | `hud.gd:374-380` | `_refresh_wave_progress()` 从 `controller.wave_director.snapshot()` 取 `n`/`spawned` → `_wave_progress`；`_wave_elite = snapshot()["is_elite_wave"]` | `snapshot()["is_elite_wave"]` |
| WAVE 横幅 | `hud.gd:151-159` | 波**开始时**中央大字横幅；`_wave_elite` 为真 → "精英波 %d"（红描边）否则 "WAVE %d" | 同上 |

### 3.2 `is_elite_wave` / `elite_waves_enabled` 能否直接供数？

- `wave_director.is_elite_wave()`（`:310`）= `elite_waves_enabled and _MonsterData.is_elite_wave(w)` —— 🔴 **用的是"当前波" `w`**，**不是"下一波"**。
- 因此现有波次条/横幅只能**事后**表达"这一波是精英波"，**没有"下一波是精英"的预告**。设计诉求（处置 C / `sapper-balance-review.md` §4 处置 C）要的是**预判**（玩家提前保塔）。
- 🟢 **可直接供数**：`_MonsterData.is_elite_wave(w)` 是**纯确定性静态函数**（`monster_data.gd:158` = `w % ELITE_EVERY == 0`，`ELITE_EVERY=5`）→ **下一波**预测 = `elite_waves_enabled and _MonsterData.is_elite_wave(w + 1)`。`elite_waves_enabled` 是 director 成员，必须在 **director 侧**算好写进 `snapshot()`（HUD 不得读成员、只能读 snapshot）。
- ⚠️ **边界核验**：`w+1 > MAX_WAVE(=20)` → `21 % 5 ≠ 0` → false，安全；IDLE（`w=0`）→ `is_elite_wave(1)=false`，安全。`v i c t o r y` 在 W20 后不会预告 W21。

### 3.3 预告实现的最小改动面

| # | 改动点 | 文件 | 具体 |
|---|---|---|---|
| P-1 | `snapshot()` 增只读字段 | `wave_director.gd::snapshot()`（`:853` 返回字典内，紧邻 `"is_elite_wave"`） | `"next_is_elite_wave": elite_waves_enabled and _MonsterData.is_elite_wave(w + 1)` |
| P-2 | HUD 增本地态 + 刷新 | `hud.gd:55`（新增 `var _next_elite: bool`）· `:374`（`_refresh_wave_progress` 内 `_next_elite = bool(s.get("next_is_elite_wave", false))`） | 只读 snapshot |
| P-3 | HUD 预告呈现 | `hud.gd::_draw()`（波次条附近） | 安全窗（`state==SAFE_WINDOW`）且 `_next_elite` → 画"下一波：精英波"文字 + 红说明（复用 `C_ALERT`）；🔴 **零数字/倒计时**（T-C2） |

> 🟢 **零玩法耦合**：P-1 纯只读派生（不写任何玩法状态），P-2/P-3 只在 HUD（`CanvasLayer 10`）内。**默认/金标本路径**（`elite_waves_enabled=false`）→ `next_is_elite_wave` 恒 false → 预告零绘制 → **逐像素不变**。
> 🟡 **顺带修**（可选）：`_wave_elite`（`:380`）与 `_on_wave_started`（`:151`）存在**刷新时序**隐患——横幅在信号回调里读 `_wave_elite`，但该值在 `_process` 里刷；波首瞬态可能读到**上一波**的值。预告落地时建议一并把"当前波精英态"在 snapshot 里**按 `state` 明确**（安全窗是否还显示"精英波"需文策渊定口径）。

---

## §工单拆分（C-1..C-7）

> 🔴 **依赖顺序**：C-1 → C-2；C-3 → C-4/C-5/C-6；C-7 收尾（全量回归）。
> 🔴 每项**独立可回滚**（开关式）。全部**只碰 `scripts/` + `tests/`**，不碰 `design/`、不碰金标本。

| # | 目标 | 预估改动文件 | 依赖 | 风险 / 红线 |
|---|---|---|---|---|
| **C-1** | **M-1 产品开关解耦**：`wave_director` 新增 `combat_revive_enabled: bool=false`；`_revive_mode()` 改判（成员优先，否则 cfg） | `scripts/gameplay/wave_director.gd` | — | 🟢 低。默认 false → 逐位不变。🔴 守住：复位（`:231`）/快照（`:525`）/tick（`:580`）三处**同读 `_revive_mode()`**（现已如此）；`revive_misq≡0` 一行不动 |
| **C-2** | **产品口径接线**：窗口模式 `combat_revive_enabled = true` + 一行回滚注释 | `scripts/ui/boot.gd` | C-1 | 🟢 低。仅窗口分支；headless/`run_tests.gd` 永不进入 → 金标本零扰动 |
| **C-3** | **UI 数据源扩展**：`snapshot()` 增 `aggro_ui`（=`tower_aggro_enabled`）与 `next_is_elite_wave`（`elite_waves_enabled ∧ is_elite_wave(w+1)`） | `scripts/gameplay/wave_director.gd` | — | 🟢 低。纯只读派生字段；默认口径下恒 false |
| **C-4** | **Disabled 中间态视觉解耦**：压暗从 `_revive_on()` 改挂 `_aggro_ui()`；充能点/爬起环仍挂 `_revive_on()`（两处绘制） | `scripts/ui/monster_layer.gd`（`:465`、`:1068`） | C-3 | 🟢 低。aggro OFF → 逐像素不变。🔴 只标事实、禁倒计时（T-C2） |
| **C-5** | **暴露度图标扩展到塔信息**：占用塔位也画 ⚔/🛡（决策期，避让塔体） | `scripts/ui/monster_layer.gd`（`:573` `_draw_exposure_icons`） | C-3（若读 `aggro_ui`，否则可独立） | 🟢 低。复用既有图标函数，零新数据。🔴 SR-R2 只标事实 |
| **C-6** | **Elite 波预告**：snapshot 供数（C-3 已含）+ HUD 安全窗"下一波：精英" | `scripts/ui/hud.gd`（`:55/:374/_draw`） | C-3 | 🟢 低。仅 HUD 呈现。🔴 T-C2 禁倒计时 |
| **C-7** | **回归 / 断言补充**：① 默认 off 零扰动（`aggro=false ∧ combat_revive=false` 与改前逐位同）② `restoral_roundtrip`（6 字段 snap→rest 守恒，GDD §12-4 建议项）③ UI 数据源断言（`revive_ui`/`aggro_ui`/`next_is_elite_wave` 取值）④ boot 产品口径探针 | `tests/test_suite_t1_aggro.gd`（+ 如需 `tests/run_slice8_scene_smoke.gd`） | C-1..C-6 | 🟢 低。纯测试新增 |

**映射到"反制窗口三项"**：① 暴露度 UI = **C-5**（空塔位部分 H10 已落地）· ② Elite 波预告 = **C-6** · ③ 肉盾/复活 = **C-1 + C-2**（+ C-4 可读性）。**C-3 是三项共用的数据底座，C-7 是质量闸。**

---

## §风险与红线

### 5.1 🔴 红线核对（逐条）

| 红线 | 触碰？ | 依据 |
|---|---|---|
| **金标本逐位复现**（`cfg_of()` / `wave_sim*.gd` / `shop_ai.gd`） | 🟢 **不触碰** | 全部新增开关默认 off；`cfg_of()` 形状不变；批处理镜像保持 `cfg` 驱动 |
| **默认回归零扰动**（off 路径逐位不变 / 3188 断言全绿） | 🟢 **不触碰** | 新成员默认 false → `_revive_mode()` 与今日同；UI 新字段默认 false → 逐像素不变 |
| **定稿数值不动**（`N=0.5` / `K=1` / `ATTRITION=1.50` / `HP0=120` / `AGGRO_R=9.0` / `WARMUP=2` / `h^0.6` / `wave_dur` / 卡价） | 🟢 **不触碰** | 本评估与工单**零数值改动** |
| **`repair_on_disable` 0/1/2 语义一字不改** | 🟢 **不触碰**（方案 A） | 方案 A 不删不改枚举，仅让实时版**在成员开启时**优先；方案 B 有语义污染风险（见 §1.3） |
| **`revive_misq ≡ 0` 硬断言** | 🟢 **不触碰** | 两侧后置守卫一行不动（`wave_director.gd:626` / `wave_sim_aggro.gd:566`） |
| **T-C1 / T-C2 / T-E1**（战斗内零可操作 / 禁精确读数 / 复活豁免三要件） | 🟢 **不触碰** | 复活仍是系统发起、零输入、单向信号；UI 新增项**全部无数字/无倒计时** |
| **§2.3 / §2.4① / §2.5 定性** | 🟢 **不触碰** | 工单不碰 `design/` |

### 5.2 🟡 风险登记

| ID | 风险 | 级别 | 处置 |
|---|---|---|---|
| **T-CP-R1** | **方案 B 语义污染**：产品特性骑 `repair_on_disable=9`，与 V-7 诊断臂（1/2）同枚举命名空间，未来易误用 | 🟡 中 | 🏆 采用方案 A（新增成员），不用 B |
| **T-CP-R2** | **半吊子解耦**：只改 `_tick_revive` 而漏改"复位/快照" → `revive_misq` 当场报警 | 🔴 高（若发生） | 三处**同读 `_revive_mode()`**（现状已满足）；C-7 加默认 off 零扰动断言 + AC-T1-20 逐位对照 |
| **T-CP-R3** | **UI 图标叠图**：占用塔位加 ⚔/🛡 与塔体/层数点/橙环/受击闪抢位 | 🟡 中 | 徽标偏移塔体上方 + 缩小尺寸；决策期才画（非战斗）；冒烟截帧核验 |
| **T-CP-R4** | **Disabled 视觉解耦改变产品画面** | 🟢 低 | 产品口径 aggro ON → 本就应显示停机；默认/金标本路径两标志皆 false → 逐像素不变 |
| **T-CP-R5** | **HUD 精英态刷新时序**（`_wave_elite` 在 `_process` 刷、横幅在信号回调读） | 🟡 中 | C-6 落地时一并明确 snapshot 语义（当前波 vs 下一波），必要时按 `state` 定口径 |
| **T-CP-R6** | 🔴 **文档债务**：`mvp_config.gd:177` 注释 / `mechanics-bulwark-cycle.md` §12-6·§12-7 状态（代码已实现却标"欠账"）失真 | 🟡 中 | 需**回写**（非本次）：由主理人/文策渊执行；避免后续评审误引 |
| **T-CP-R7** | 🟡 **口径歧义**：项目**无独立"塔信息面板"** UI 面，设计诉求"塔信息 🟢"落点未定 | 🟡 中 | 本阶段按"塔位徽标"落地（§2.1 推荐 (a)）；如需真面板 → 文策渊先出 UI 规格 |

### 5.3 🔴 知识诚实（不确定项登记）

- 🟡 **未跑 Godot 验证**：本阶段**只读评估**，所有"零扰动/逐位同"为**代码级推定**（基于默认值分析 + 既有 AC 断言），**未经本轮 headless 实跑复核**。若要升格为"已证"，需在 C-1..C-7 落地后跑 `run_tests.gd` 全量（切片1–8 + T1 仇恨）确认退出码 0。
- 🟡 **引擎版本**：Godot `v4.7.2.stable`（`control-manifest.md` §适用引擎）。本评估未使用任何超出该版本或训练数据范围的引擎 API（仅 `Node`/`Control`/`Node2D` 绘制 + `Dictionary` 读，均为既有用法）→ **无引擎知识缺口**。
- 🟢 **无臆造 API**：所有改动点均引用仓库现有函数/字段（既存 helper 复用），未引入新引擎 API。

---

## 6. 待主理人 / 用户审批项

| # | 项 | 推荐 | 阻塞谁 |
|---|---|---|---|
| **Q-CP-T1** | M-1 产品开关形态：**方案 A**（新增 `WaveDirector.combat_revive_enabled`）vs 方案 B（复用 `repair_on_disable=9`） | 🏆 **方案 A** | C-1 / C-2 |
| **Q-CP-T2** | Disabled 中间态视觉**本次是否解耦**（用户此前选"不做"） | 🟡 **建议顺手解耦**（成本极低 + 语义清晰）；可裁量 | C-4 |
| **Q-CP-T3** | "塔信息"是否为**新 UI 面板**，还是 = 塔位徽标 | 🟡 塔位徽标（现无独立面板） | C-5 范围 |
| **Q-CP-T4** | 文档债务回写（`mvp_config:177` 注释 / bulwark GDD §12-6·§12-7 状态） | 🟡 **需回写**（由主理人/文策渊执行） | 非本次 |

---

*文档结束 · 程基岩（engineering-lead）· T-CP-01-TECH · 🔴 只读技术评估 · 零代码改动 · 零数值改动 · 未跑 Godot（代码级推定）· 未 commit · 结论：反制窗口三项机制已落地，真正工作量 = M-1 产品化解耦 + 两处 UI 数据源 + 一处渲染解耦 + 一处图标扩展 + Elite 预告；方案 A（新增产品开关）零红线；`revive_misq≡0` 与金标本/默认回归零扰动全程保住。*
