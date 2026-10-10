# 体验层**第三刀 · 视觉氛围刀** —— Godot 实现记录

> 项目：**《守核 Corebound》** · Godot **4.7.2-stable** · PC Steam · 肉鸽塔防 + 卡牌构筑
> blueprint：`docs/phase3/ux-p0p1c-spec.md`（**spec-v1.0**，权威，616 行）；上刀记录：`docs/phase3/ux-p0p1b-impl.md`
> 落地：程基岩（Engineering）· 交付裁决：主理人 · 用户拍板：2026-10-10（spec §0.5）
> 状态：**已实现 + 已自验（未提交，待用户复跑验收后由主理人提交）**
> Godot 可执行：`C:\Users\junhewang\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`

---

## 0. 范围与红线（与规格 §0.2 / 任务书一致）

- **落地范围 = spec §C.1 MVP 四项**：① 环境换装（T0→T4 五档 + §A.3 hex + §A.2 映射 + §A.5 3s smoothstep）
  ② 威胁方位楔形·扇区去重（§B.1.3）③ 核心呼吸（§B.2）④ 怪物 squash&stretch 摆动（§B.3）。
- 🔴 **不含** §B.1.4「下一波预告楔形」（用户拍板③延后）——**未新增任何 snapshot 字段**。
- **只改 3 个文件**：新建 `scripts/ui/env_palette.gd`；改 `scripts/ui/battlefield_placeholder.gd`、`scripts/ui/monster_layer.gd`。
- 渲染层**只读** `WaveDirector.snapshot()` / `TimeDirector.snapshot()`（经既有注入）；**不写玩法状态、不新增玩法信号**。
- 本地状态**仅**纯演出计时器 `_env_tier/_env_prev/_env_t`（换装过渡）；核心呼吸**复用既有 `_vfx_t`**、怪摆动**纯由 `pos` 派生** → **零新增状态**。
- **不碰**：`scripts/{geo,engine,gameplay,data}/*`、`design/*`、金标本 JSON、任何定稿数值。
- **PATH 模式渲染逐位不变**：所有新增绘制只落 `_draw_radial*` 分支；`_draw_legacy()` 一行未改。
- 🔴 纯 2D 立即模式：只用既有 `draw_*`；**未引入** 3D / `ShaderMaterial` / 后处理 / 外部依赖。
- 🔴 `monster_layer.gd` 代码行**无** `draw_string` / `Label` / `progress`（见 §4 验收 #4）。

---

## 1. 逐文件改动清单（带行数）

| 文件 | 类型 | 行数 | 改动摘要 |
|---|---|---|---|
| `scripts/ui/env_palette.gd` | **新建** | **54** | 纯静态色表 + 档位分派（§A.2/§A.3/§A.6）。`extends RefCounted`，**无 `class_name`**（headless 无 global_script_class_cache）；只有 `static func tier_of(w)` 与 `static func get_color(tier,key)` + `const _T`。 |
| `scripts/ui/battlefield_placeholder.gd` | 改 | 122 → **174**（+60 行改动） | 场底层换装：`_draw_radial_ground()` 背景/场地圆改按档取色 + 3s 过渡；新增 `_current_wave()` / `_update_env()` / `_env_col()` + 3 个本地计时器 var + `ENV_FADE_SEC`。 |
| `scripts/ui/monster_layer.gd` | 改 | 1041 → **1157**（+148 行改动） | 环境层换装（field/ring 取档 + 出生环固定）+ 威胁楔形扇区去重 + 核心盘级呼吸 + 怪 squash&stretch 摆动；新增 helpers `_update_env/_env_col/_core_breath/_sway_amp/_sway_phase/_sway_rot` + 常量。 |

`git diff --stat`：`2 files changed, 188 insertions(+), 20 deletions(-)`（+ 1 新增文件 `env_palette.gd`）。

**新增符号一览**

- `monster_layer.gd`：`const _EnvPalette` `ENV_FADE_SEC=3.0` `SWAY_K_RHO=0.50` `CORE_BREATH_AMP=0.025` `CORE_BREATH_SEC=2.4`；
  `var _env_tier/-1` `_env_prev/-1` `_env_t/1.0`；`func _update_env/_env_col/_core_breath/_sway_amp/_sway_phase/_sway_rot`。
- `battlefield_placeholder.gd`：`const _EnvPalette` `ENV_FADE_SEC=3.0`；`var _env_tier/_env_prev/_env_t`；`func _current_wave/_update_env/_env_col`。

---

## 2. 逐项落地 ↔ 规格节号对照

| # | 交付项 | 规格节号 | 落点（函数 / 行区） | 落地结果 |
|---|---|---|---|---|
| ① | 档位分派 `tier_of(w)` | §A.2 | `env_palette.gd: tier_of` | 纯函数，`w≤0→0 / 1-5→1 / 6-10→2 / 11-15→3 / ≥16→4` 逐字一致 |
| ① | 5 档 4 元素 hex 表 | §A.3 | `env_palette.gd: const _T` | 15 个 hex 逐位对照**全 PASS**（§4 证据 #7） |
| ① | 背景 + 场地圆按档取色 | §A.6 / §A.7 | `battlefield_placeholder.gd: _draw_radial_ground` | `C_BG_R/C_FIELD_R` → `_env_col("bg"/"field",1.0)` |
| ① | 场地/同心环/放射刻度按档取色 | §A.3 / §A.6 | `monster_layer.gd: _draw_radial_ground` | field←`_env_col("field",1.0)`；环×3←`_env_col("ring",0.5)`；刻度×8←`_env_col("ring",0.35)` |
| ① | 出生环**固定** `#3A4257` | §A.3 / 拍板② | `monster_layer.gd: _draw_radial_ground` | 恒用 `P_SPAWN_EDGE`，**不换色**（含 8 方位刻度） |
| ① | 3.0s smoothstep 过渡 | §A.5 | 两文件 `_update_env` + `_env_col` | `e(t)=t²(3−2t)` + 线性 RGB `Color.lerp`；首次直接落位（无过渡） |
| ② | 威胁楔形扇区去重 | §B.1.3 | `monster_layer.gd: _draw_threat_wedges` | 8 扇区吸附 + ±11°弧 + α`0.35+0.05·min(count,5)`上限0.60 + **≤8 段** |
| ③ | 核心盘级呼吸 | §B.2.2/§B.2.3 | `monster_layer.gd: _draw_radial_core` + `_draw_all_shadows` | `rc = U_CORE·sc·_core_breath()`（±2.5% @2.4s）；内芯保留 ±6% @1.6s；核心影同步缩放 |
| ④ | 怪 squash&stretch 摆动 | §B.3 | `monster_layer.gd: _draw_radial_monsters` | `ph=θ+(−ρ)·0.50+φ_proto`；`rs'=rs(1+A·sw)` `ts'=ts(1−A·sw)` `rot'=rot_amp·cos(ph)`；A=稀.10/群.06/坦.04 |

---

## 3. 明确不做（登记原因，未扩范围）

| 不做项 | 归属 / 原因 |
|---|---|
| **下一波预告楔形**（`next_wave` 字段） | 🔴 用户拍板③**延后**；**未新增 snapshot 字段**（spec §0.5/§B.1.4） |
| Boss 压暗 / 血夜边光 / 虚空星点 / 出生环档色微染 | spec §A.9/§C.2 列**延后可选**，非 MVP |
| 3D 管线 / `ShaderMaterial` / 后处理 / Boss 骨骼 / 伤害数字 / 卡牌插图 / 超载 | spec §C.3 明列不做 |
| 单位配色改动（塔青/怪橙） | 🔴 红线（§0.2-5），未动 |

---

## 4. 验收证据（逐条自跑 · 最终冻结代码）

| # | 项 | 命令 | 原始结果 |
|---|---|---|---|
| 1 | **默认回归**（改前基线） | `godot --headless --path D:/roguedemo --script res://tests/run_tests.gd` | **EXIT=0** · `[FAIL]`=0 · 汇总：**222 / 2228 / 142 / 123 / 302 / 41 / 31 / 切片8=92 / T1=216** |
| 1 | **默认回归**（改后） | 同上 | **EXIT=0** · `[FAIL]`=0 · 汇总：**222 / 2228 / 142 / 123 / 302 / 41 / 31 / 切片8=92 / T1=216** → **与改前逐项逐位一致** |
| 2 | **径向一键聚合** | `… --script res://tests/run_tests.gd -- radial8` | **EXIT=0** · **8-8 PASS**（geo8/radial/geo8_smoke/geo8_golden/expo/bulwark8/panorama8/attrition8）· 结论 PASS |
| 3 | **git diff --stat 范围** | `git diff --stat` | 仅 `scripts/ui/battlefield_placeholder.gd`、`scripts/ui/monster_layer.gd`（+ 新增 `scripts/ui/env_palette.gd` 未跟踪）。**唯一旁项** = `.workbuddy/memory/2026-10-08.md`（**改前基线即已 dirty，非本次改动**，见 §5-D5）。 |
| 4 | **禁区令牌 grep** | `grep -nE "draw_string\|Label\|progress" scripts/ui/monster_layer.gd` | **代码行 0 处**。仅命中 **1 行既有注释**（L52：`🔴 因此本文件用 draw_arc / draw_circle 画，🈚 draw_string、🈚 Label`）—— **HEAD 已存在、非本次新增**（`git diff` 新增行 0 处，见 §5-D3）；T1 测试按「代码行」判定，216 项全绿。 |
| 5 | **受保护路径零改动** | `git diff --stat -- scripts/geo scripts/engine scripts/gameplay scripts/data design/` | **空**（`_draw_legacy()` diff 亦为空） |
| 6 | **实机截帧 · 环境换装** | 非 headless `--script res://tests/_tmp_env_shots.gd` | 见下「截帧读数」；4 档 bg+field 采样 **全 PASS** |
| 7 | **色表精确性**（离线） | `--script tests/_tmp_check_palette.gd`（临时件） | 15 个 hex **全 PASS**；`tier_of` 11 例全 PASS；smoothstep 端点 0/0.5/1 正确 |

### 截帧读数（实机 RADIAL · 1920×1080 · DisplayServer=Windows）

**四档 bg / field 采样 ↔ spec §A.3（PASS）**

```
[PASS] W1  bg #111a2b want #111a2b | field #1f2e48 want #1f2e48   (T1 晨雾)
[PASS] W6  bg #1b1026 want #1b1026 | field #2f1f44 want #2f1f44   (T2 黄昏)
[PASS] W11 bg #200c12 want #200c12 | field #3e1c27 want #3e1c27   (T3 血夜)
[PASS] W16 bg #120a1e want #120a1e | field #2a1748 want #2a1748   (T4 虚空)
→ 环境换装截帧汇总：失败 0 项
```

**W1→W6 过渡逐 0.4s 采样（场地像素，单调平滑 = 无突变）**

```
t=0.4s #202d48  _env_t=0.136
t=0.8s #222b47  _env_t=0.275
t=1.2s #252846  _env_t=0.414
t=1.6s #282546  _env_t=0.553
t=2.0s #2b2245  _env_t=0.686
t=2.4s #2d2044  _env_t=0.819
t=2.8s #2f1f44  _env_t=0.958
t=3.2s #2f1f44  _env_t=1.000   ← 到 T2 端色，此后恒定
```

> 采样点：field = 圆心 + `(field_r−4)` @22.5°（避开放射刻度/出生环/单位）；bg = 圆心 + `(field_r+10)` @0°（场地圆外 10px，且距 4 边 >56px → **避开 `ThreatPulse` 的 56px 红边光带**）。
> 首轮采样曾在屏幕角 (5,5) 取 bg → 命中 `ThreatPulse` 红边光带（红通道 +11~22），属**采样点选择问题**，非换装缺陷；改点后 bg 精确匹配（见 §5-D4）。

**截图路径（`docs/phase3/`）**

- `ux-p0p1c-w1-20261010.png`（T1 晨雾 · 冷蓝场地 #1f2e48）
- `ux-p0p1c-w6-20261010.png`（T2 黄昏 · 紫暮场地 #2f1f44）
- `ux-p0p1c-w11-20261010.png`（T3 血夜 · 赤夜场地 #3e1c27）
- `ux-p0p1c-w16-20261010.png`（T4 虚空 · 深紫场地 #2a1748）
- `ux-p0p1c-w6-motion-20261010.png`（W6 第二帧，相隔 ≈0.7s — 供人工看怪摆动/核心呼吸）

**人工可见项（截帧文字描述）**：W6/W16 图可见「紫暮/深紫场地 + 出生环（固定冷灰蓝 `#3A4257`）+ 同心环×3 + 放射刻度×8 + 青色核心盘+8 刻齿 + 青塔 + 橙怪 + **12 点方向扇区去重威胁弧**」；W1/W6/W16 三档场地色**肉眼显著不同**。

> 临时截帧/校验脚本（`tests/_tmp_env_shots.gd`、`tests/_tmp_check_palette.gd`、探针 `tests/_tmp_probe_env.gd`）**跑完已删除**（含 `.uid`）。

---

## 5. 偏差登记（deviation）

| # | 项 | 规格 / 任务书 | 实际处置与理由 |
|---|---|---|---|
| **D1** | 🔴 **`battlefield_placeholder` 的 `w` 取数来源** | spec §A.6 写「`battlefield_placeholder` 经 `director.snapshot()["w"]`」（暗指 director = WaveDirector） | 实际接线（`scripts/ui/battle_shop.gd:59`）把 `Battlefield` 绑到 **`TimeDirector`**（键 `"wave"`），**非 WaveDirector**；且 `battle_shop.gd` 不在本刀可改的 3 文件内。**处置**：`_current_wave()` 写成**键兼容** `s.get("w", s.get("wave", 0))` —— TD 与 WaveDirector 的波号**同源**（皆 `sm.wave`，同帧同步）。**探针实证**：首帧起 `TD.snapshot().wave == WaveDirector.w == 1`，故两渲染器**同帧同档**，满足 §A.6「同源同帧」。 |
| **D2** | T0 基线在实机不可见 | §A.2「T0 = w≤0（未开波/备战）」 | 实机 scene 一 `_ready` 即 `call_deferred("start_run",1)` → 首帧波号即为 1 → 实机首帧即 T1；**T0 仅出现在未开波（headless / 未启动）**。与规格语义一致（T0 = w≤0），**非缺陷**，登记以免误判「T0 没画出来」。 |
| **D3** | 禁区令牌 grep 命中 1 行 | 任务书验收 #4「grep 确认无 `draw_string/Label/progress`」 | 命中项为 **HEAD 既有注释**（L52），**非本次新增**（`git diff` 新增行 0 处，`grep -c` HEAD=1 / 现=1）。按 T-E1③ 的「代码行」口径（T1 测试）**合规**。**未删该注释**（删既有注释属越界改动）。 |
| **D4** | 首轮截帧 bg 采样「不合」 | 任务书验收 #6 | 根因 = 采样点落在 `ThreatPulse`（层120）**56px 红边光带**（`EDGE=56`，红通道 +11~22），**非换装缺陷**。改采样点后 **bg 精确匹配**。登记采样方法学。 |
| **D5** | `.workbuddy/memory/2026-10-08.md` 为 dirty | 任务书「只改 3 文件」 | **该文件在开工前基线 `git status` 即已 `M`**（非本次改动，未触碰）。仅登记澄清，不改动。 |
| **D6** | T0 常量保留 | spec §A.6「`C_BG_R`/`C_FIELD_R` 改为取色」 | `battlefield_placeholder.gd` 的 `C_BG_R`/`C_FIELD_R` **保留为 T0 基线参考值**（注释标明已被换装取代），绘制改用 `_env_col()`。与既有 `P_BG` 保留风格一致；避免无谓删除。 |
| **D7** | 过渡计时器不跨文件共享 | 登记 spec §E **G-11** | `monster_layer`=ALWAYS / `battlefield`=PAUSABLE → 暂停期二者过渡进度可差数帧。过渡**只在开波瞬间（战斗期、未暂停）触发** → 实际偏差可忽略。**沿用 spec 裁决**，本刀不引入共享 autoload（会破坏父先子后结构）。 |

---

## 6. 未决项 / 无法完全自证的点（如实报告）

| # | 项 | 说明 |
|---|---|---|
| U1 | **核心呼吸「±2.5% @2.4s」的实机可见性** | @1080p 核心半径 `U_CORE·sc ≈ 16.1px` → 呼吸幅度 ≈ **±0.4px**（亚像素）。**这是规格刻意设计的「极小幅」**，无法从 1080p 截帧上可靠量测。**已证**：代码为纯 `sin`（`_core_breath()`），数值区间 `[0.975, 1.025]`；实机渲染随 `_vfx_t` 连续变化（结构决定）。**未能证**：像素级幅度（需放大到 4K/录屏逐帧量测）。**建议用户以录屏（0.5× 慢放）目视确认「有极轻呼吸但读不出是缩放」。** |
| U2 | **怪 squash&stretch 的实机静态证据** | 挤压幅度 A≤0.10 → `rs/ts` 波动 ≤±10%（Rush R≈5.5px → ≈±0.55px，亦近亚像素）；**可肉眼察觉的主要是「体摆动」`rot'=rot_amp·cos(ph)`（Rush ±0.18rad ≈ ±10°）**。**已证**：摆动**零时间项、纯由 `pos` 派生** → 同 `pos` 必同渲染 ⇒ **帧间稳定、暂停/重放不抖（结构性保证）**；`_sway_*` 表与 spec §B.3.3 逐值一致。**未能证**：单帧内的「挤压」形变大小时序（需两帧对照录屏目视）。 |
| U3 | **「暂停/重放不抖」的逐像素对照** | 未做「帧 A vs 暂停后帧 B 像素差 == 0」的严格对照：因 `monster_layer` 为 ALWAYS，暂停期 `_vfx_t` 仍推进 → 核心呼吸像素会变（**这是应有的呼吸**），无法用整帧 diff 干净隔离「怪摆动稳定性」。以 U2 的结构性论证替代。 |
| U4 | **PATH 分支逐位不变** | 未做 PATH 模式截帧对照（默认实机 = RADIAL）。**以 `_draw_legacy()` git diff 为空 + 默认回归 3305 项全绿 + radial8 8-8 PASS 三重佐证**。 |
| U5 | **过渡期「无突变」** | 已用 9 点采样证明端到端**单调平滑**（§4）；未做「逐帧帧间色差上限」量化（可视「无阶跃」已足够，且 smoothstep 起止导数为 0）。 |

---

## 7. 零扰动保障复核

- 3 个改动脚本**只在窗口模式**（`battle_shop.tscn` / `main.tscn`→boot）装载；headless `run_tests.gd` **不渲染** → 改渲染**不可能**触碰金标本。
  **实证**：改后默认回归 EXIT=0、0 FAIL，**逐项与改前一致**（§4 #1）；radial8 8-8 PASS（§4 #2）。
- **PATH 模式渲染逐位不变**：`_draw_legacy()` 一行未改（`git diff` 空）；新增绘制**全部**落在 `_draw_radial*` 与 `_draw_all_shadows`（径向专用）。
- **只读纪律**：`_snap["w"]` / `director.snapshot()` 只读；**无新增信号**、**无反向写路径**；本地状态仅 3 个演出计时器。
- `monster_layer.gd` 仍满足 T-E1③（代码行无 `draw_string`/`Label`/`progress`）→ T1 仇恨 216 项全绿。
- `env_palette.gd` **无 `class_name`** → headless 无 `global_script_class_cache` 亦可用（`preload` 同款 `_SpaceModel`）。
- **未触碰**：`scripts/{geo,engine,gameplay,data}/*`、`design/*`、金标本 JSON、任何定稿数值（`git diff` 空）。
- `project.godot` 本次**未被引擎重写**（`git status` 无该项）；临时脚本已删除，工作区仅余 **2 个目标脚本改动 + 1 个新增脚本 + 5 张截图**（+ 引擎自动生成的 `.gd.uid`）。

---

## 8. 交付物 / 待审批

- **代码改动（3）**：新增 `scripts/ui/env_palette.gd`（54 行）；改 `scripts/ui/battlefield_placeholder.gd`（122→174）、`scripts/ui/monster_layer.gd`（1041→1157）。
- **记录**：本文件 `docs/phase3/ux-p0p1c-impl.md`。
- **截图（5）**：`docs/phase3/ux-p0p1c-w{1,6,11,16}-20261010.png` + `ux-p0p1c-w6-motion-20261010.png`。
- **均未提交** —— 等主理人 / 用户复跑验收后再走提交。
- **待用户目视确认**：§6-U1（核心呼吸）、§6-U2（怪挤压/摆动）—— 静态截帧不足，请以 0.5× 录屏目视。
