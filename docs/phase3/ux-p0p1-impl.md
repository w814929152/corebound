# 体验层第一刀 · P0 战场可读性 + P1 HUD 重做 —— Godot 实现记录

> 项目：**《守核 Corebound》** · Godot **4.7.2-stable** · 落地：程基岩（Engineering）
> blueprint：`docs/phase3/ux-p0p1-spec.md`（**spec-v1.0**，权威）
> 状态：**已实现 + 已自验（未提交，待用户审批）**
> Godot 可执行：`C:\Users\junhewang\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`

---

## 0. 范围与红线

- **只改 4 个文件**（全在 `scripts/ui/`）；零玩法 / 零定稿数值 / 零金标本改动。
- 渲染层**只读** `WaveDirector.snapshot()` / `Runtime.snapshot()`（经 `controller.runtime`）/ `TimeDirector.snapshot()`；
  不写玩法状态、不新增玩法信号。
- **不碰**：`scripts/geo/*`、`scripts/engine/*`、`scripts/gameplay/*`、`scripts/data/*`、`design/gdd/*`、
  金标本 JSON、任何定稿数值（ATTRITION=1.50、κ_r=0.050、AGGRO_R=9.0、塔位6/SLOTS6、SPAWN_RADIUS=55、core HP 1000、漏怪伤害 50）。
- **未改 `design/art/art-bible.md`**（spec §D 只登记）。
- 本地状态仅限**纯演出**：`_debug_visible`（F3 开关）、`_banner_end_ms`（WAVE 横幅计时）、`_vfx_t`（核心呼吸相位）。

---

## 1. 逐文件改动清单

### 1.1 `scripts/ui/monster_layer.gd`（P0 核心）

- **新增常量**：阵营配色（spec §A.1 精确 hex → Color）、形状尺寸（`U_TOWER/U_SLOT/U_CORE/U_OUTLINE/BODY_*/ELITE_SCALE/SPIKE_SPREAD`）、
  `CONCENTRIC_U=[15,30,45]`、确定性扰动表 `BLOB_R12[12]`。
- **新增纯函数工具**（无状态、无随机、帧间稳定，spec §A.9）：`_dir` / `_oct8` / `_closed` / `_blob12` / `_body_units` / `_blob_shadow`。
- **`_draw()` 改为双模分派**：
  - `RADIAL` → `_draw_radial(sc)`（新分层）；
  - 否则 → `_draw_legacy(sc)`（**原 `_draw()` 函数体逐字保留**）→ **PATH 模式输出逐位不变**。
- **`_draw_radial` 严格按 spec §A.6 渲染顺序**：
  1. 层1 场地圆(`#232838`) + 同心环×3(`#1B2030 @0.5`) + 放射刻度×8(`@0.35`)；
  2. 层2 出生环(`#3A4257` @0.28u) + 方位刻度；
  3. 层3 **全单位投影**（核心/塔/怪统一 `_blob_shadow` **先画全部影**）；
  4. 层4 塔位层：空槽八边形环(钢灰) + 威胁方位楔形(`#FF6B3D @0.45`) + `_draw_under_attack` + `_draw_exposure_icons`；
  5. 层5 核心：外环(深青) + 中盘(耀青) + 8 刻齿 + 内芯(`#EAFBFF` 呼吸±6%) + 外描边；
  6. 层6 塔：合法宿主高亮 + 底座八边形(深青) + 塔身八边形(耀青,旋转22.5°) + 中心圆 + 左上高光 + 外扩描边(`#0E2430`) + 主塔(星紫)/选中(耀青)/停机压暗/充能点亮 + 层数刻度点；
  7. 层7 怪：`_blob12` 12 边不规则主体(熔橙, Rush 径向拉长 / Tank 宽扁+焦褐内环) + 朝核心尖刺扇(焦褐) + 外扩描边(`#2E1008`) + 精英环(`#E8437F`)；
  8. 层8 投射物：`snapshot` 无 `projectiles` 字段 → **零绘制**（未新增字段）；
  9. 层9 `_draw_revive_flash`（沿用既有）。
- **保留（原样调用，未改一行）**：`_draw_exposure_icons`（红X/绿盾）、`_draw_under_attack`（橙环）、`_draw_revive_charge`、
  `_draw_revive_flash`、选中/合法宿主高亮，全部 `_SpaceModel`/`_slot_rows`/`_xform`/命中判定逻辑。

### 1.2 `scripts/ui/battlefield_placeholder.gd`

- `_draw()` 顶部新增 RADIAL 分派：`_draw_radial_ground()` = 全屏背景 `#141726` + 场地圆 `#232838`（`r=(SPAWN_RADIUS+2)*sc`，圆心=视口中心）。
- **PATH 分支一行未改**（原「跳过横带」逻辑被前置 return 取代，PATH 下等价）。

### 1.3 `scripts/ui/hud.gd`（P1 重写）

- **删除**「HUD（骨架占位）…」标题。
- 新增**真 HUD**：左上 L0 积分（硬币图标 + 辉金 `#FFC94A` 数字，千分位）、顶部中央 `WAVE n` + 进度条(`spawned/n`, 熔橙) 、底部 L3 快捷键提示、1.2s WAVE 大字横幅（缩放+淡出）。
- **F3 可切换 debug 层（默认关闭）**：完整保留全部验证读数 → `_battle_label / _run_label / _state_label / _clock_label / _budget_label / _gain_label / _layout_label`（§B.4 一表不落）。
- 3 个按钮功能保留：「开始下一波」移至波次条右端、仅 `SAFE_WINDOW` 可用；「开关抽屉 / 放置」降为 L3 提示文本
  （抽屉 `shop_overlay.gd` 内已有「放置」入口 + Tab 开关，功能不丢）。
- **缺陷修复**：`hud.gd` 原 `bool(wd.run_won)` 对**信号**调 `bool()` → 结束帧报 `Nonexistent 'bool' constructor`；
  改为读只读快照布尔字段 `snapshot()["won"]`。
- 布局用**绝对 position/size**（`_layout()`）：4.7.2 实测 `set_anchors_preset(PRESET_CENTER_*)` 静默失效（同 `battle_shop.tscn` 顶部说明）。

### 1.4 `scripts/ui/core_hp_bar.gd`（P1 重写）

- 改为**底部中央 20 段 × 50 点**分段血条（段 22×28、间距 3；底槽 `#141726@92%` + 3px `#3ED0E8` 描边；`≤25%` 段转 `#FF2E4E`）。
- 与漏怪伤害 50 逐位对齐 → **每碎一段 = 漏一只怪**；20 段见底 = 失败。
- **保留 CanvasLayer 130**（唯一穿透 UI，GDD §10.1 断言 12 仍可验）。数据源：只读 `runtime.player.core_hp`（单一数据源）。

---

## 2. 验收原始证据（逐条自跑）

| # | 项 | 命令 | 原始结果 |
|---|---|---|---|
| 1 | **改前基线** 默认回归 | `godot --headless --path D:/roguedemo --script res://tests/run_tests.gd` | **EXIT=0** · `[FAIL]`=0 |
| 2 | **改后** 默认回归 | 同上 | **EXIT=0** · `[FAIL]`=0 · 汇总：222 / 2228 / 142 / 123 / 302 / 41 / 31 / T1=216 → **合计 3305 项全通过** |
| 3 | 八槽径向 V-1′ | `… --script res://tests/run_slice_attrition8.gd` | **EXIT=0** · 「八槽径向 V-1′ 判据验收汇总：失败 0 项」· 失败标记 0 |
| 4 | 径向一键聚合 | `… --script res://tests/run_tests.gd -- radial8` | **EXIT=0** · 8 项全 PASS（`geo8(套件)/radial(套件)/geo8_smoke/geo8_golden/expo/bulwark8/panorama8/attrition8`）· 结论 PASS |
| 5 | **实机截帧（默认 HUD）** | 窗口模式（非 headless）实例化 `battle_shop.tscn`(RADIAL) → 推进 W1 战斗波 | `docs/phase3/ux-p0p1-20261010.png`（**1920×1080**） |
| 6 | **实机截帧（F3 debug 层）** | 同上 + F3 | `docs/phase3/ux-p0p1-debug-20261010.png`（**1920×1080**，含全部验证读数） |

> 截帧脚本为临时性（`tests/_tmp_ux_shot.gd`），跑完**已删除**（含 `.uid`）。

---

## 3. 与 spec / 任务书的偏差登记

| # | 项 | spec/任务书 | 实际处置 |
|---|---|---|---|
| P-1 | 验收项 `tests/run_slice_radial8.gd` | 任务书列此文件 | **该文件不存在**；径向一键入口实为 `run_tests.gd -- radial8`（聚合 8 项，含 `attrition8`）→ 已按后者验收。 |
| P-2 | spec §A.6「层0 背景」落在 `monster_layer` | — | 改由**父节点 `Battlefield`** 承担（父先子后）；否则子节点不透明全屏底会盖住父节点的场地圆。`monster_layer` 仍画**场地圆**（幂等同色）。净视觉 = spec 意图。 |
| P-3 | spec §A.2.4 投射物层 | 「落地需 snapshot 增 `projectiles`」 | 依任务书**不新增字段**（属玩法侧）→ 字段缺失时该层**零绘制**。 |
| P-4 | 尖刺扇 `SPIKE_SPREAD` | spec 未给数值 | 取 `0.40` rad（定性观感值，登记）。 |
| P-5 | 波次「Boss 警示」 | spec §B.1a 写 Boss | snapshot **无 boss 字段** → 以 `is_elite_wave` 承担（条变红 + 「精英波」），**未虚标 BOSS**。 |
| P-6 | spec §B.2 WAVE 动效「提前 2s 预告」 | 需玩法侧预告信号 | 本次触发于 `TimeDirector.wave_started`（1.2s 缩放+淡出）；「提前 2s」不做。 |
| P-7 | 字体（art/fonts Poppins/Inter/思源黑体） | spec §B.5 列出 | `art/fonts/` 不存在 → 用 **Godot 内置默认字体** + spec 字号/色值；**未下载任何字体**。后续只换 Theme、不改布局。 |
| P-8 | 投影 | 用户已拍板**正交俯视 2D** | 全程正圆、零 Y 压缩；未改 art-bible。 |

---

## 4. 零扰动保障复核

- 4 脚本**只在窗口模式**（`battle_shop.tscn`）装载；headless `test_suite` **不渲染** → 改渲染不可能触碰金标本（实证：改后默认回归 EXIT=0、0 FAIL）。
- 单向依赖：渲染层无反向写路径；未新增任何信号。
- **PATH 模式渲染逐位不变**：`_draw_legacy()` = 原 `_draw()` 函数体（含 PATH 折线/路径点/核心方块/塔位/暴露图标/被攻击环/塔/怪）。
- `monster_layer.gd` 仍满足既有限制测试（T-E1③：代码行无 `draw_string` / `Label` / `progress` 令牌 —— 三词仅出现在整行注释）。
- **副作用处置**：运行 Godot 期间 `project.godot` 被引擎自动重写（注释与 `[physics]/[debug]` section 丢失）→ 已 `git checkout -- project.godot` **还原**（非本次交付内容）。

---

## 5. 交付物 / 待审批

- 改动文件（4）：`scripts/ui/monster_layer.gd`、`scripts/ui/battlefield_placeholder.gd`、`scripts/ui/hud.gd`、`scripts/ui/core_hp_bar.gd`。
- 新增记录：本文件 + 2 张截图（`docs/phase3/ux-p0p1-20261010.png`、`docs/phase3/ux-p0p1-debug-20261010.png`）。
- **均未提交** —— 等用户批准后再走提交。
- 知识缺口：引擎字体资源缺失（P-7，已用内置字体规避，不阻塞）。
