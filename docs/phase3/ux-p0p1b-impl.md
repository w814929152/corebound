# 体验层**第二刀** · P0/P1 增强集 —— Godot 实现记录

> 项目：**《守核 Corebound》** · Godot **4.7.2-stable** · 落地：程基岩（Engineering）
> blueprint：`docs/phase3/ux-p0p1-spec.md`（**spec-v1.0**，权威）；第一刀记录：`docs/phase3/ux-p0p1-impl.md`
> 状态：**已实现 + 已自验（未提交，待用户复跑验收后由主理人提交）**
> Godot 可执行：`C:\Users\junhewang\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`

---

## 0. 范围与红线（与第一刀完全一致）

- **只改 3 个文件**（全在 `scripts/ui/`）：`monster_layer.gd`、`hud.gd`、`core_hp_bar.gd`。
- 渲染层**只读** `WaveDirector.snapshot()` / `Runtime.snapshot()`（经 `controller.runtime`）/ `TimeDirector.snapshot()`；
  **不写玩法状态、不新增玩法信号**。
- 本地状态**仅限纯演出计时器/差分缓存**（与第一刀 `_revive_flash` / `_vfx_t` 同性质）。
- **不碰**：`scripts/geo|engine|gameplay|data/*`、`design/gdd/*`、金标本 JSON、任何定稿数值。
- **PATH 模式渲染逐位不变**：所有新增绘制只落在 `_draw_radial*` 系列；`_draw_legacy()` 一行未改。
- 第一刀已验收行为**零回退**（暴露图标/被攻击橙环/复活充能/威胁楔形/F3/20×50 血条/CanvasLayer 130）。

---

## 1. 逐文件改动清单

### 1.1 `scripts/ui/monster_layer.gd`（P0 四项增强）

| # | 增强 | 落点 | 说明 |
|---|---|---|---|
| a | **Rim Light 内发光**（spec §A.4） | 新增 `_draw_rim()`；`_draw_radial_towers` / `_draw_radial_monsters` 各调一次 | 本体内侧 `R − 0.55w` 叠一圈阵营色细弧：塔 `#3ED0E8@α0.6`、怪 `#FF6B3D@α0.6`，宽恒定 `0.8px`，`draw_arc(..., antialiased=true)`。塔的弧落在**深色底座环带**上 → 亮环清晰；混乱时分离相邻单位。 |
| b | **塔升级「形态」递进**（spec §A.2.1 增强，**取代**"只堆层数白点"） | 新增 `_draw_tower_form()`；`_draw_radial_towers` 调用 | `h≥2` 内层**深色**细环（`0.46R`，与亮塔身强对比）→ `h≥3` 外圈**亮色**护角×8（长度 `0.10u→0.30u` 随等级增）→ `h≥5` 星紫 `#7A5CFF` 顶点点缀×8 → `h≥8` 星紫外环（满级）。 |
| c | **核心受击闪**（spec §A.2.3 受创） | `_detect_hits()`（检测）+ `_draw_radial_core`（绘制） | `runtime.snapshot()["core_hp"]` **帧间下降** → 核心外环闪 `#FF2E4E@α0.8`，持续 `0.12s`（本地计时器衰减）。 |
| d | **塔受击闪** | `_detect_hits()` + `_draw_radial_towers` | `runtime.player.towers[slot].hp` **帧间下降** → 该塔叠一瞬白闪（`0.15s`，本地计时器）。仅对可见塔。 |

**形态递进的红线遵守**：① 所有附加件都落在八边形 **8 个顶点 / 8 等分角**上 → **严格 8 次旋转对称**；
② 护角尖端 ≤ `R + 0.30u`（`TOWER_CORNER_MAX_U`）→ 不侵占相邻塔位（最近塔间距 10.14u）；
③ **零数字/文本**（无 `draw_string`/`Label`/`progress`，沿用 T-E1③ 口径）；④ 不改塔位坐标/原型语言。

**新增本地状态**（纯演出）：`_core_hp_prev` / `_core_flash` / `_tower_hp_prev` / `_tower_flash`。

### 1.2 `scripts/ui/hud.gd`（P1 五项：积分数字滚动 + 金色粒子）

- **数字滚动**（spec §5.2）：`runtime.snapshot()["scrap"]` 变化 → 显示值从旧值**缓动**到新值
  （`SCORE_ROLL_SEC = 0.25s`，**cubic EASE_OUT** `1-(1-p)^3`，本地 easing）。
- **缩放脉冲 + 金色小粒子**（`#FFC94A`）：仅在积分**增长**时触发（花分不闪）；硬币图标随脉冲放大、
  6 颗金色小粒子从硬币喷出（本地阻尼衰减，上限 48 颗）。
- **不改数据源、不改玩法数值**：`debug` 的 `_run_label` 仍读**真实** `scrap`（未受影响）。
- 新增本地状态（纯演出）：`_score_display/_score_from/_score_to/_score_t/_score_init/_score_pulse/_gold_parts`。

### 1.3 `scripts/ui/core_hp_bar.gd`（P1 六项：段碎裂动画）

- 某段由"满→空"时给短促**碎裂/闪退**演出：按**段索引**记录剩余动画时间（`SHATTER_SEC = 0.18s`），
  该段闪白 `#FFFFFF` 并轻微外扩，然后隐没。
- 仅只读 `runtime.player.core_hp`（单一数据源，`set_hp` 内做满段数下降差分）。
- 新增本地状态（纯演出）：`_prev_filled` / `_shatter`（Dictionary）。
- **保留 CanvasLayer 130**（唯一穿透 UI）。

---

## 2. 明确不做（登记原因，未扩范围）

| 不做项 | 原因 |
|---|---|
| **怪物命中闪 / 死亡碎片** | `snapshot()` **无稳定怪物 id**（第一刀已验证），逐帧重建无法逐只跟踪 → 会抖动。**不做**。 |
| **字体 Theme** | `art/fonts/` 未入库（🔴 不下载字体）。 |
| Boss 骨骼 / 3D / 伤害数字 | spec §C.3 明列不做。 |

---

## 3. 验收原始证据（逐条自跑 · 最终冻结代码）

| # | 项 | 命令 | 原始结果 |
|---|---|---|---|
| 1 | 默认回归 | `godot --headless --path D:/roguedemo --script res://tests/run_tests.gd` | **EXIT=0** · `[FAIL]`=0 · 汇总：222 / 2228 / 142 / 123 / 302 / 41 / 31 / 切片8=92 / T1=216 → **合计 3305 项全通过**（与第一刀逐项一致） |
| 2 | 径向一键聚合 | `… --script res://tests/run_tests.gd -- radial8` | **EXIT=0** · **8-8 PASS**（`geo8(套件)/radial(套件)/geo8_smoke/geo8_golden/expo/bulwark8/panorama8/attrition8`）· 结论 PASS · 失败标记 0 |
| 3 | 实机截帧（RADIAL 战斗） | 非 headless `--script res://tests/_tmp_ux_shot2.gd` | `docs/phase3/ux-p0p1b-20261010.png`（**1920×1080**，可见 **Rim 光 + 塔形态递进（h=8 星紫外环/顶点/护角） + 积分滚动 196/248**） |
| 4 | 实机截帧（**受击瞬间**） | 同上（临时触发：`core_hp 1000→950`、塔 hp `200→150`，2 帧内抓帧） | `docs/phase3/ux-p0p1b-hit-20261010.png`（**1920×1080**，可见 **核心外环红闪 #FF2E4E + 塔白闪 + 血条末段碎裂闪白**，数字 `950 / 1000`） |

> 截帧脚本为临时性（`tests/_tmp_ux_shot2.gd` + 校验用 `tests/_tmp_crop.gd` / `docs/phase3/_tmp_zoom.png`），跑完**已删除**（含 `.uid`）。

---

## 4. 与 spec / 任务书的偏差登记

| # | 项 | spec/任务书 | 实际处置 |
|---|---|---|---|
| Q-1 | 塔升级形态 "`min(h,8)` 个短三角" | 任务书建议写法 | 为**严守红线①"严格 8 次旋转对称"**，护角**恒为 8 个**（落在八边形 8 顶点），用**长度随等级增长**（`0.10u→0.30u`）表达强弱 —— 任何"按 h 取数量"都会破坏 8 重对称。登记为形态实现的判断取舍。 |
| Q-2 | 塔内层细环配色 | spec 未钉色 | 取 **深青 `#1A6B7D`**（塔暗部面）叠在亮塔身上 → 强对比、一眼可辨"多了一层"；若用耀青 `#3ED0E8` 会与塔身同色不可见。 |
| Q-3 | 塔受击闪时长 | 任务书未钉值 | 取 `0.15s`（本地演出；核心受创沿用 spec 的 `0.12s`）。 |
| Q-4 | 积分粒子数量/上限 | spec §5.2"可选" | 每次增长 6 颗，全局上限 48 颗（本地、无玩法含义）。 |

---

## 5. 零扰动保障复核

- 3 脚本**只在窗口模式**（`battle_shop.tscn`）装载；headless `test_suite` **不渲染** → 改渲染不可能触碰金标本
  （实证：改后默认回归 EXIT=0、0 FAIL，逐项与改前一致）。
- **PATH 模式渲染逐位不变**：`_draw_legacy()` 一行未改；新增绘制全部落在 `_draw_radial*` 分支。
- `monster_layer.gd` 仍满足 T-E1③ 限制测试（代码行无 `draw_string` / `Label` / `progress` 令牌）→ T1 仇恨 216 项全绿。
- 副作用处置：运行 Godot 期间 `project.godot` 被引擎自动重写 → 每次跑完已 `git checkout -- project.godot` 还原（非交付内容）。
- 临时截帧/裁剪脚本已删除，工作区仅余 **3 个目标脚本改动 + 2 张截图**。

---

## 6. 交付物 / 待审批

- 改动文件（3）：`scripts/ui/monster_layer.gd`、`scripts/ui/hud.gd`、`scripts/ui/core_hp_bar.gd`。
- 新增记录：本文件 + 2 张截图（`ux-p0p1b-20261010.png`、`ux-p0p1b-hit-20261010.png`）。
- **均未提交** —— 等主理人复跑验收后再走提交。
