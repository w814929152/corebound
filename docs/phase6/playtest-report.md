# Phase 6 · 可玩性验证（Playtest ≥3 轮 + 逐波截帧）（T-P6-01）

> **性质**：真实帧可玩性验证（read-only）。本轮**未改动任何生产代码 / 数值 / 口径**（`scripts/`、`scenes/`、`design/` 生产路径零改动）；仅新增诊断驱动 `tests/playtest_driver.gd`（与 T-P6-02 的 `tests/perf_profile.gd` 同族，均为**未跟踪的诊断脚本**）+ 截图 `docs/phase6/shots/` + 本文档。
> **红线核对**：见 §7 —— 结论为**未触碰红线**。
> **负责人**：quality-lead（严守真） · **引擎**：Godot 4.7.2-stable(official) · **日期**：Phase 6 打磨期

---

## 0. 环境与口径

| 项 | 值 |
|---|---|
| 引擎 | Godot **4.7.2-stable** |
| 渲染后端 | **gl_compatibility**（OpenGL） |
| DisplayServer | **Windows**（窗口模式 · 真实帧；非 headless 逻辑子步） |
| 分辨率 | **1920×1080**（product 目标分辨率） |
| 场景 | `scenes/battle_shop.tscn`（完整战斗 + 商店覆盖层） |
| 玩法口径 | **RADIAL + proto + elite + aggro + combat_revive（全 ON · 对齐 `boot.gd` 窗口分支）** |
| 驱动 | `tests/playtest_driver.gd`（`extends SceneTree` · 窗口模式 `godot --path . --script res://tests/playtest_driver.gd -- <scenario>`） |
| 场景枚举 | `product`（全开 · 贪心自动建造+修复）/ `fail`（不建塔）/ `uic4`（aggro 开 · revive 关 · 单塔）/ `revive`（全开 · 真实帧轮询捕获**爬起环**） |

### 0.1 口径注入的一个关键坑（本轮修正）

第一版驱动把产品口径开关（`prototype_split_enabled` / `elite_waves_enabled` / `tower_aggro_enabled` / `combat_revive_enabled`）写在 `SceneTree._initialize()` 里 `add_child(scene)` **之后**抢设。**该注入全部静默失效**——原因：`WaveDirector` 并非场景文件里的节点，而是 `battle_shop._ready()` **动态 `add_child`** 创建的；`_initialize()` 阶段场景 `_ready()` 尚未执行 → `get_node_or_null("WaveDirector")` 返回 `null` → `if wd != null` 整块跳过 → 「产品局」实际跑在**默认口径（aggro/elite/revive 全 OFF）**下（表现为：塔永不受损、核心满血、无 Disabled —— 与实机不符）。

**修正**：把开关注入挪到 `Driver.run()`（`scene._ready` 已跑完、`wd` 为真节点）之后，并用 `wd.start_wave(1)` 以产品口径**重建 W1 刷新表**（不发波信号、零副作用）。修正后日志：`proto=true elite=true aggro=true revive=true` ✅，塔开始受损、出现 Disabled —— 与实机一致。**此坑对「按实机口径做可玩性验证」是前提性的**，特此记录。

> ⚠️ 注：本项不影响生产代码 —— `boot.gd` 在同一时序（`add_child(bs)` 后设 `bs.wave_director.*`）**是安全的**，因为它在 main 场景 `_ready()` 内执行（`_ready` 已同步跑完），与 `SceneTree._initialize()` 早期阶段不同。

---

## 1. 真实帧跑通（Win + Loss）

### 1.1 胜利局 · `product`（全开 · 贪心建造 + 安全窗修复）

命令：`godot --path D:/roguedemo --script res://tests/playtest_driver.gd -- product` → **EXIT=0**，无运行期错误。

| 波次 | 核心 HP | 积分 | 塔数 | Disabled | 备注 |
|---|---|---|---|---|---|
| W1 | 1000/1000 | 25 | 1 | 0 | 首波无压 |
| W5 | **850/1000** | 99 | 3 | **3** | 🔴 **首精英波 = 全场唯一掉血波**（-150），3 塔全被打停 |
| W6 | 850/1000 | 144 | 3 | 0 | W5 安全窗修复 3 塔后**零漏怪** |
| W10 / W15 / W20 | 850/1000 | — | 3 | 0 | 精英波 W10/15/20 **零核心伤害** |
| **W20 结束时** | **850/1000** | **960** | 3 | 0 | `victory=true` |

**结论**：完整跑通 **W1 → W20 通关**，核心 850/1000，结算覆盖层弹出「通关胜利」。全流程无脚本错误、无崩溃。

### 1.2 失败局 · `fail`（不建塔）

命令：`... -- fail` → **EXIT=0**。

| 波次 | 核心 HP | 结果 |
|---|---|---|
| W1 | 1000 | — |
| W2 | 950 | 首漏怪 -50 |
| W3 | 650 | -300 |
| **W4** | **0** | `run_lost` → 结算覆盖层「核心归零 · 失败」弹出 |

**结论**：失败路径（E-W3 核心归零立即失败）与失败结算覆盖层**均正常**。

### 1.3 C-4 专项局 · `uic4`（aggro 开 / revive 关 · 单塔）

命令：`... -- uic4` → **EXIT=0**。落 1 座 Arrow 塔于 **slot 0**；分帧推进，W3 第 801 子步首现 Disabled（核心 950）。`runtime.snapshot().slots` 实测：

```
[slot 0 empty=false ctype=Arrow h=1 disabled=true] [slot 1..5 empty=true]
selected=-1 core_slot=0 towers=1 disabled=1
```

→ 该局**单塔被打停**，用于对照「停机压暗」视觉（见 §3.1）。

---

## 2. 逐波截帧清单（`docs/phase6/shots/` · 全部 1920×1080 · err=0）

| 文件 | 内容 | 用途 |
|---|---|---|
| `W1-battle.png` | W1 战斗 | 逐波基线 |
| `W1-safe-window.png` | W1 安全窗（决策期） | 决策期槽位/图标 |
| `W3-safe-window.png` / `W3-shop-open.png` | W3 安全窗 + 商店抽屉展开 | 商店抽屉 / 决策期 |
| `W4-safe-elite-preview.png` | W4 安全窗（**下一波 W5 精英预告**） | **C-6** |
| `W5-battle.png` | W5 首精英波战斗 | **C-6**（当前精英波条） |
| `W5-safe-window.png` | W5 安全窗（修复前） | 塔损 → 修复 |
| `W10-battle.png` / `W10-safe-window.png` | W10 精英波 + 安全窗 | **C-5**（占用槽暴露图标） |
| `W15-battle.png` / `W15-safe-window.png` | W15 精英波 + 安全窗 | 逐波 |
| `W20-battle.png` | W20 终波战斗 | 逐波 |
| `VICTORY.png` | 通关结算覆盖层 | Win 路径 |
| `DEFEAT-overlay.png` | 失败结算覆盖层 | Loss 路径 |
| `uic4-tower-placed.png` | 单塔落子（决策期） | 塔态对照 |
| `uic4-w3-tower-disabled.png` | 单塔被打停 | **C-4**（停机压暗 · 二态对照） |
| `revive-flash-ring.png` | 塔自动爬起瞬间（revive ON · W5 slot2） | **C-4b**（爬起环） |

---

## 3. 🔴 反制窗口 UI 专项核对（C-4 / C-5 / C-6）

### 3.1 C-4 · 停机压暗（Disabled 塔视觉可辨）

**代码事实**（`scripts/ui/monster_layer.gd`）：
- RADIAL 分支 `:1077-1078`：`if _aggro_ui() and _is_disabled(slot): draw_circle(c, R, Color(0.06,0.07,0.09,0.62))`
- PATH 分支 `:466-469`：同式压暗 + 灰弧 `Color(0.55,0.57,0.62,0.55)`
- 门控 `_aggro_ui()`（`:515`）= snapshot `aggro_ui`（= `tower_aggro_enabled`）→ **与「复活档位是否开」解耦**（T1 修复点）。

**实测**（`uic4-w3-tower-disabled.png` 近景放大）：slot 0 的 Arrow 塔呈**明显压暗/去饱和**（塔色 `C_TOWER_ARROW` 绿 + 压暗层 + 灰弧），与同屏其余 **5 个空槽（钢灰空心八边形）** 形成清晰二态；对照 `uic4-tower-placed.png`（同局、未受损）塔身为**常亮绿**。

**判定**：✅ **C-4 PASS** —— aggro 开而 revive 关时，停机塔**可被一眼看出「倒下了」**（此前绑 `revive_ui` 的产品可见性缺口已修复）。

### 3.2 C-5 · 占用槽暴露图标（重叠核对）

**代码事实**（`monster_layer.gd._draw_exposure_icons` `:582-604`）：仅**决策期**（`state != COMBAT`）绘制；**空槽 + 占用槽都画**（T1 复用 ⚔/🛡 语义）；占用槽 **上抬 `sp.y - max(18, sc*2.4)` + 缩小 `×0.8`**（`icon_r`/`ip`）以避开塔身。红 X = 暴露位（`d_path ≤ 9`），绿盾 = 安全位。

**实测**（`W10-safe-window.png` 近景放大，决策期 · 3 占用槽 + 2 空槽）：每个占用塔的暴露图标均**抬到塔体正上方**（红 X / 绿盾），**塔身与图标无像素重叠**；空槽图标为原始偏移/尺寸（逐像素不变）。`W3-shop-open.png` 复现同一形态。

**判定**：✅ **C-5 PASS** —— 占用槽暴露图标**未与塔身叠图**，红 X / 绿盾语义可读。

### 3.3 C-6 · 波次条精英预告（无数字 / 无倒计时）

**代码事实**（`scripts/ui/hud.gd` `:525-530` + `:390-395`）：精英标记**分态取源** ——
- **战斗态** = 当前波 `is_elite_wave(w)` → 文案 `"精英波"`；
- **决策期** = snapshot `next_is_elite_wave` 预告 → 文案 `"下一波：精英波"`（修 stale：`w` 在 `start_wave` 才自增，安全窗直接读会残留刚打完那波的旗）。

**实测**：
- `W4-safe-elite-preview.png`（决策期）：波次条下方红字 **`下一波：精英波`** —— 正确预告 W5 精英（`_MonsterData.is_elite_wave(5)=true`）。
- `W5-battle.png`（战斗态）：波次条左端红块 + **`精英波`** 文案 + 中央大字 `精英波 5`。

**判定**：✅ **C-6 PASS** —— 预告**可读**（纯文字，红色高辨识），且**零数字、零倒计时、零进度读数**（符合 T-E1③「不含择时读数」）。

### 3.4 C-4b · 复活充能点 / 爬起环（revive ON 时的呈现）

**代码事实**（`monster_layer.gd`）：
- **充能点** `_draw_revive_charge :485-501`：门控 `_revive_on()`（snapshot `revive_ui` = `tower_aggro_enabled and _revive_mode() ≥ 9`）**且仅战斗态（state 1/2）**；沿用亮/灭二态 —— 亮 = 暖金 `C_REVIVE_LIT(1.0,0.86,0.35)` + 外晕，灭 = 暗点 `C_REVIVE_SPENT(0.30,0.31,0.35)`。**零数字、零倒计时**。
- **爬起环** `_draw_revive_flash :539-545`：由 `tower_revived(slot)` 信号（`wave_director:642`）驱动 → `_revive_flash[slot]=REVIVE_FLASH_SEC`，播一圈高亮扩散环（运动+亮度，不依赖色相）。

**实测（revive ON · 场景 `revive`）**：
- 战斗态每座塔**塔底均有暖金充能点**（`W10-battle.png` 近景：塔身下方金点 + 外晕）。证据帧：`W10-battle.png`。
- W5 真实帧推进到 **slot 2 塔被仇恨打停后自动爬起**（`tower_revived` 触发）→ 抓得 `revive-flash-ring.png`：该塔呈**亮白扩散光环**（明显亮于同屏其余塔），core=1000、disabled 归 0。证据帧：`revive-flash-ring.png`。

**实测（revive OFF · 场景 `uic4`）**：停机塔**无暖金充能点**（`uic4-w3-tower-disabled.png` 近景：塔底无金点）—— 证实「停机压暗（挂 aggro）与 充能点/爬起环（挂 revive）**已解耦**」。

**判定**：✅ **C-4b PASS** —— 充能点 / 爬起环**按预期呈现**：revive 开则战斗态可见（充能点稳态 + 爬起环事件态），revive 关则**正确地零绘制**。

---

## 4. Playtest 记录（≥3 轮）

> 每轮 = 目标 → 观察 → 发现 → 严重度。数据来自 §1 真实帧跑通。

### R1 · 新手首局（`fail`｜无塔）
- **目标**：验证「不建塔」的失败路径与结算手感。
- **观察**：W1 无损 → W2 950 → W3 650 → **W4 核心 0**，失败覆盖层「核心在 W4 被击穿 / 构筑强度不足」。
- **发现**：失败**在 4 波内**到来，节奏不拖沓；结算覆盖层文案清晰、提供「再来一局 / 退出」。但**游戏内零教学**：首局玩家极可能不知道「要建塔 / 要修复」，W4 崩时无从归因。
- **严重度**：**Minor**（失败路径本身 OK；缺的是一段最简引导）。

### R2 · 贪心 3 塔 · 不修复（`product` 修前对照）
- **目标**：验证 aggro 塔损 + 「修 or 死」的强度墙。
- **观察**：W5 精英波**打停全部 3 塔**（核心 1000→850）；因不修复，Disabled 塔持续失能 → **W6 核心 200 → W7 核心 0（失败）**。
- **发现**：🔴 **W5 是硬墙**——首精英波即可让「同波全额买入」的构筑崩盘；且「不修复 = 必崩」（W5→W7 三波内连锁）。`repair_on_disable=0`（AI 从不修）本就是 MC 口径里真实玩家的**下界**，实测吻合。
- **严重度**：**Major**（难度 + 引导）：玩家若不懂「安全窗修复」，会在同一处反复受挫且看不出原因。

### R3 · 贪心 3 塔 · 安全窗修复（`product` 正式局）
- **目标**：验证「修复循环」能否把 R2 的失败翻成通关。
- **观察**：W5 安全窗**修复 3 塔**（花光 99 积分）后，**W6→W20 核心恒定 850**（零漏怪），**W1→W20 通关**；终局剩 960 积分。
- **发现**：**修复循环有效**（"修了有用"，非"修了也白修"）。但暴露两条曲线问题：① 修 1 次即"一劳永逸"——W5 后**再无压力**（含 W10/W15/W20 三个精英波**零核心伤害**），难度曲线**前重后轻**；② 3 塔即通关、终局溢出 960 积分 → **经济过宽**，构筑深度未被逼出。
- **严重度**：**Major**（难度曲线 / 经济平衡，交文策渊裁决）。

### R4 · 反制窗口 UI 专项（`uic4`）
- **目标**：C-4 / C-5 / C-6 逐项核对。
- **观察 / 发现 / 判定**：见 §3.1–3.3，**C-4 / C-5 / C-6 全部 PASS**。
- **严重度**：**None**（验证通过）。

---

## 5. 可玩性盲区清单（Blind Spots）

| # | 盲区 | 证据 | 建议方向 |
|---|---|---|---|
| B-1 | **零教学 / 零新手指引**：建塔、放置、安全窗修复、暴露度图标均无引导；首局玩家易 W4 崩且不知为何 | R1；`uic4` 需脚本注入才建塔 | 加一段最简 in-game 引导（3~4 步：买→放→跑→修） |
| B-2 | **精英波无强度可估**：条上只有「精英波」/「下一波：精英波」文字，玩家**无法预估其强度**（W5 即打停全塔，其余精英波零威胁） | §1.1 表；C-6 | 预告可加**非读数**的强度提示（如分级色/图标档位，仍不违反"无数字/倒计时"） |
| B-3 | **难度曲线前重后轻**：W5 后无压力，W10/15/20 精英波零核心伤害 | §1.1（核心 850 恒定） | 逐波抬升压力曲线 |
| B-4 | **经济过宽**：3 塔即通关、终局溢出 960 积分；无消费压力、构筑深度未被逼出 | §1.1 | 收紧收入 / 抬高强敌或强化项价格 |
| B-5 | **暴露度"可读但不可解释"**：红 X / 绿盾可读，但「为什么这个位暴露」缺因果线索，依赖玩家的径向直觉 | §3.2 | 可选：暴露位加一线「威胁来源」指引 |
| B-6 | **主塔位语义未明示**：面板写「主塔位 0」，玩家难懂其含义与价值 | `W3-shop-open.png` 面板 | 提供悬停说明/图示 |
| B-7 | **战斗期与决策期割裂**：战斗中只能观察，唯一决策点=安全窗；实时商店可缓解但仍是"看—停—改" | §1.1 全流程 | 评估节奏（后续批次） |
| B-8 | **结算"本局积分"语义模糊**：胜利局显示 0，且与左上"积分"不一致 | §6 BUG-1 | 修正口径 + 文案 |

### 5.1 headless 盲区（本阶段**仅真实帧可验** / headless 盖不到的项）

> headless（`--headless` / `--script`）跑的是**逻辑子步 + 批处理镜像**，**不创建真实渲染帧、不装载 `main` 场景的窗口分支**。下列项**只能窗口真实帧**验，headless 无从覆盖：

| # | 仅真实帧可验的项 | 原因 |
|---|---|---|
| H-1 | **停机压暗 C-4** / **暴露图标 C-5** / **充能点·爬起环 C-4b** | 均绘制在 `MonsterLayer._draw_*`，headless 不渲染 → 画面为空 |
| H-2 | **波次条精英预告 C-6** / 中央大字横幅 | `HUD` 的 `draw_string` / Label 仅真实帧可见 |
| H-3 | **结算覆盖层**（`ResultOverlay` · 150 层）布局 / 可点性 | headless 下 `_on_quit_requested` 只打印，不建真实窗口 |
| H-4 | **真实帧性能**（FPS / 帧时间 p50/p99） | headless 无真实帧（见 T-P6-02 §0） |
| H-5 | **输入链路**（Tab/Esc/R/1-2-3/Space、鼠标放置） | headless 无窗口输入事件 |
| H-6 | **窗口分支产品口径**（`boot.gd` 的 RADIAL + proto/elite/aggro/revive 注入） | `boot.gd` 窗口分支在 headless 下**永不进入**（其注释明载） |
| H-7 | **1920×1080 布局 / HUD `_layout`** | headless 不实例化 HUD；本轮窗口跑通时观察到 `hud.gd:96 _layout` 一条非致命告警（**仅真实帧出现**，见 §7 备注） |

> 反向：**金标本逐位等价（9 段）/ MC 门禁 / C-1·C-2 开关解耦单测** 只在 headless（自测）跑；真实帧只做**冒烟**，不替代这些断言。

---

## 6. 发现的问题与建议

### BUG-1（Minor · UI/口径）· 胜利结算"本局积分"读在最终波收入入账**之前** → 显示 0

**现象**：`VICTORY.png` 结算覆盖层显示 **「本局积分 0」**，而同屏左上积分角标为 **605**、W20 结束实测 `runtime.scrap=960`。失败局则正常（`DEFEAT-overlay.png` 显示「本局积分 80」，与左上/HUD 一致）。

**根因**（代码事实）：`wave_director._end_wave()` **先** `emit_signal("run_won", w)`（`:820`）**再** `emit_signal("wave_result", …)`（`:826`）与 `director.wave_end(w)`（`:829`）；而积分的真实入账发生在 `wave_ended → shop_controller:367 → runtime.grant_wave_result()`（`shop_runtime.gd:1168` `scrap += …`）。`shop_controller._on_run_won → _show_result` 在 `run_won` 时刻读 `float(runtime.scrap)`（`shop_controller.gd:145`）→ 读到的是**最终波收入入账前的余额**（本例玩家恰在 W19 安全窗花光 → 读到 0）。

**仪器证据**（本轮驱动挂钩）：
```
[P6][run_won] w=20 runtime.scrap=0 core=850 scrap_earned(this)=480
[P6] W20 结束: core=850/1000 scrap=960 ... victory=true     # run_won 之后才 += 480×(1+income_mult)
```
失败路径对照：`[P6][run_lost] w=4 runtime.scrap=80 core=0` → 覆盖层显示 80（= HUD），**一致** → 说明差异**仅存在于胜利路径**。

**建议**：`run_won` 的结算读数改用「本波 `wave_result` 入账后」的 scrap（例如把胜利判定/结算挪到 `wave_result` 之后，或让 `_show_result` 延迟到 `wave_ended` 后取数）；同时澄清文案——"本局积分"若意指"剩余积分"应改名，若意指"本局累计收入"应改为 `scrap_earned` 累计。**属工程件 + 文案口径，建议排期修正（不阻塞本阶段）**。

### OBS-2（Info · 平衡）· W5 后零核心伤害 / 精英波无梯度
见 §4 R3、§5 B-2/B-3/B-4。**属数值口径，交 design-strategist（文策渊）裁决**，非工程缺陷。

---

## 7. 红线核对

| 红线 | 结论 |
|---|---|
| 只读、不改生产代码/数值/口径 | ✅ 未改（`scripts/`、`scenes/`、`design/` 生产路径零改动） |
| 只写自己的产出 | ✅ 仅新增 `docs/phase6/playtest-report.md`、`docs/phase6/shots/*.png`、诊断驱动 `tests/playtest_driver.gd` |
| 不 push / 不部署 | ✅ 未 push、未部署（全部为工作区未提交文件） |
| 临时件零残留 | ✅ 一次性探针 `tests/_qa_p6_probe.gd(.uid)` 已删除；可复用驱动已从 `_qa_p6_play.gd` 提名为 `tests/playtest_driver.gd`（与 T-P6-02 `perf_profile.gd` 同族，未跟踪） |
| 避免 `.godot` 实例锁 | ✅ 全流程**串行**执行（每次仅一个 Godot 实例），无并发冲突 |

**备注（非致命告警 · 仅真实帧可见）**：窗口跑通时每次启动打印一条 `hud.gd:96 _layout` 的 GDScript backtrace（`_ready :77` → `_layout :96`）。**非致命**（不中断运行、EXIT=0、画面正常），且**仅在真实帧出现**（headless 不实例化 HUD）。不在本任务红线范围内改动，仅登记供工程侧查看（与 §5.1 H-7 呼应）。

---

## 8. 复现方式

```bash
GODOT="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
# 胜利局（全开 · 建造+修复）→ EXIT=0，产出 W*-battle / W*-safe / VICTORY.png
"$GODOT" --path D:/roguedemo --script res://tests/playtest_driver.gd -- product
# 失败局（不建塔）→ EXIT=0，产出 DEFEAT-overlay.png
"$GODOT" --path D:/roguedemo --script res://tests/playtest_driver.gd -- fail
# C-4 专项（aggro 开 / revive 关 · 单塔）→ EXIT=0，产出 uic4-*.png
"$GODOT" --path D:/roguedemo --script res://tests/playtest_driver.gd -- uic4
# C-4b 专项（全开 · 真实帧轮询捕获爬起环）→ EXIT=0，产出 revive-flash-ring.png
"$GODOT" --path D:/roguedemo --script res://tests/playtest_driver.gd -- revive
```

> ⚠️ 窗口模式（非 `--headless`）。三条命令**串行**执行（`.godot` 实例锁）。

---

## 9. 结论（🟢/🟡/🔴 分档 · 每条附证据帧）

| 档 | 项 | 判定 | 证据帧 / 数据 |
|---|---|---|---|
| 🟢 | 核心循环真实帧**跑通 W1→W20 胜利** | 通过 | `VICTORY.png`（通关结算 · 核心 850/1000） |
| 🟢 | **失败路径 + 失败结算**正常收口 | 通过 | `DEFEAT-overlay.png`（核心 W4 归零） |
| 🟢 | **C-4 停机压暗**可辨（aggro 开 / revive 关） | 通过 | `uic4-w3-tower-disabled.png`（对照 `uic4-tower-placed.png`） |
| 🟢 | **C-5 占用槽暴露图标**不叠图 | 通过 | `W10-safe-window.png` |
| 🟢 | **C-6 精英预告**可读 · 无数字/倒计时 | 通过 | `W4-safe-elite-preview.png`（"下一波：精英波"）、`W5-battle.png` |
| 🟢 | **C-4b 充能点 / 爬起环**按预期呈现 | 通过 | `W10-battle.png`（暖金充能点）、`revive-flash-ring.png`（爬起环） |
| 🟡 | **BUG-1 胜利结算"本局积分"读数错**（显示 0，实为最终波入账前余额） | 待修（Minor） | `VICTORY.png` + 仪器日志 `[run_won] scrap=0` vs `W20 结束 scrap=960` |
| 🟡 | **OBS-2 难度曲线前重后轻**（W5 后零核心伤害 / W10·15·20 精英波零威胁） | 待裁决（Major） | §1.1 数据 + `W5-battle.png`（唯一掉血波） |
| 🟡 | **OBS-2 经济过宽**（3 塔即通关 · 终局溢出 960 积分） | 待裁决（Major） | `VICTORY.png`（面板）+ W20 `scrap=960` |
| 🟡 | **B-1 零教学**（不知建塔/修复 → 易 W4 崩） | 待裁决（Minor） | `W1-battle.png`（开局即战斗·无引导）、`DEFEAT-overlay.png`（W4 崩） |
| 🟡 | **B-2 精英波无强度可估**（仅文字预告，无强度档） | 待裁决（Minor） | `W4-safe-elite-preview.png` |
| 🔴 | — | **无**（本轮未发现 🔴 级：阻塞/崩溃/口径破坏项） | — |

- **可玩性层面总评**：🟢 **通过（可玩）**；带 🟡 **改进项**（1 处 UI/口径读数 BUG + 5 处平衡/引导）。
- **质量门判定**：**PASS（附 CONCERNS）** —— 核心循环、胜/败路径、反制窗口 UI（C-4/C-5/C-6/C-4b）全部达标；CONCERNS = **BUG-1** + **OBS-2 / B-1 / B-2**。
- **待用户拍板项**：
  1. **BUG-1**（胜利结算积分读数）是否排入工程件修正队列？（修法二选一：结算改到 `wave_result` 入账后取数 / 或文案改为"剩余积分"）
  2. **OBS-2**（难度曲线 · 经济 · 精英波梯度）是否交 design-strategist 出调参单？
  3. **B-1**（新手引导）是否立项？
- 本报告为**建议性质量门**，最终放行由用户裁定；**🔴 本轮无阻塞项**。

