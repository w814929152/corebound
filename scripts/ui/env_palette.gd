extends RefCounted
##
## 环境换装色表 + 档位分派（**纯静态助手**）
## ---------------------------------------------------------------------------
## 依据：`docs/phase3/ux-p0p1c-spec.md` **§A.2 / §A.3 / §A.6**（spec-v1.0）。
##
## 🔴 定位：**纯函数、无状态、无 RNG、无玩法耦合**。唯一职责 = 把「波号 w」映射到
##    「档位 tier」，并给出该档的环境色（背景 / 场地圆 / 同心环）。
##
## 🔴 两渲染器一致性：`battlefield_placeholder.gd`（层0 背景 + 场地圆）与
##    `monster_layer.gd`（场地圆幂等 + 同心环 + 放射刻度）**preload 本文件共用**
##    → 保证「同档同色」（spec §A.6）。
##
## ⚠️ G6：项目 headless 无 `global_script_class_cache` → **不写 `class_name`**；
##    两文件用 `const _EnvPalette := preload("res://scripts/ui/env_palette.gd")`
##    （与既有 `_SpaceModel` 同款）。
##

## 档位 ↔ 波次映射（spec §A.2，唯一分派）。纯函数，只在跨档边界迁移。
##   w ≤ 0        → T0 夜幕（基线 = 现状配色）
##   1 ≤ w ≤ 5    → T1 晨雾
##   6 ≤ w ≤ 10   → T2 黄昏
##   11 ≤ w ≤ 15  → T3 血夜
##   w ≥ 16       → T4 虚空
static func tier_of(w: int) -> int:
	if w <= 0:   return 0
	if w <= 5:   return 1
	if w <= 10:  return 2
	if w <= 15:  return 3
	return 4


## 5 档 × 3 元素色表（spec §A.3，精确 hex → `Color`）。
##   `bg`    背景（全屏底）· `field` 场地圆（径向战场底）· `ring` 同心环/放射刻度基色。
##   🔴 α 由调用方按元素施加（同心环 0.5 / 放射刻度 0.35，沿用现状），本表只存 RGB。
##   T0 = 现状基线（`#141726` / `#232838` / `#1B2030`）→ w ≤ 0 零变化。
const _T: Array = [
	# T0 夜幕（现状基线）
	{"bg": Color(0.078, 0.090, 0.149), "field": Color(0.137, 0.157, 0.220), "ring": Color(0.106, 0.125, 0.188)},
	# T1 晨雾（色相锚 #2A3550）
	{"bg": Color(0.0667, 0.1019, 0.1686), "field": Color(0.1216, 0.1804, 0.2824), "ring": Color(0.0902, 0.1333, 0.2196)},
	# T2 黄昏（色相锚 #4A2E52）
	{"bg": Color(0.1059, 0.0627, 0.1490), "field": Color(0.1843, 0.1216, 0.2667), "ring": Color(0.1412, 0.0824, 0.2078)},
	# T3 血夜（色相锚 #5A1E32）
	{"bg": Color(0.1255, 0.0471, 0.0706), "field": Color(0.2431, 0.1098, 0.1529), "ring": Color(0.1725, 0.0706, 0.0980)},
	# T4 虚空（色相锚 #2A1240）
	{"bg": Color(0.0706, 0.0392, 0.1176), "field": Color(0.1647, 0.0902, 0.2824), "ring": Color(0.1137, 0.0627, 0.1922)},
]


## 取某档某元素色（`key ∈ {"bg","field","ring"}`）。tier 夹在 `0..4`
##   → 越界（含首帧 `-1`）落在 T0 基线，行为确定。
static func get_color(tier: int, key: String) -> Color:
	return _T[clampi(tier, 0, 4)][key]
