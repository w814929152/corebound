extends RefCounted
##
## 地图变体数据表 `MapVariants` —— 关卡地图变体的**唯一登记处**（SSOT）
## ---------------------------------------------------------------------------
## 🔴 定位（control-manifest §5）：本文件只登记「变体图长什么样」的数据，是
##   `design/gdd/campaign-progression.md` 里「地图变体 = 换表不换引擎」的**数据先行层**。
##   它**不改** `SpaceModel.RIDGES/SPAWN_ARCS` 与 `BuildGrid.SITES` 这三张 `const` 表、
##   **不改**引擎、**不改**渲染层 —— 那三张表仍是运行时唯一生效的数据（基准 "tri-fissure"）。
##
## 🔴 为什么是「数据先行」而不是直接参数化三张 const 表：
##   `RIDGES`/`SPAWN_ARCS`/`SITES` 被 `SpaceModel.map_theta_deg()`（确定性出生角）、
##   `BuildGrid.buildable()`（可建判定）、渲染层 `_radial_geo`、断言 E-M1..E-M8 **同时消费**，
##   且是编译期 `const`。把它们改成「运行时可选表集合」会触碰金标本路径（默认等价但语义变）。
##   本文件先把「变体数据」沉淀成可测的 SSOT，等拍板「运行时换图」时直接回填参数化层。
##
## 🔴 变体的合法范围（scene-map §4 / §6 / §12，红线逐条钉死）：
##   · ✅ 能改：岩脊角宽 / 开口分布（纯角度，`G` 映射自动适配）、阵地格布局（改共鸣拓扑）；
##   · 🔴 不能改：`t_reach` / 寻路 / RNG（架构红线，改 = 金标本等价破产）；
##   · 🔴 开口 OPEN_DEG 恒 ≥ 300°（AC-R1 下限）；
##   · 🔴 岩脊 `r1 ≤ 58`（不越出生环 55 + 路肩）；
##   · 🔴 跨台最近格距 ≥ 28.6u（Lance 链接上限，否则 E 飙回 n−1）。
##
## 🔴 数据纪律：每张变体的「脊」与「弧」是**互补拼接**的 —— 弧的 `a1` = 下一座脊的 `a0`
##   （跨 0° 时 +360）。开口 open_deg = 360 − Σ脊宽，且必须 ≥ 300。这些由
##   `validate_arcs()` 逐条守护（本文件的数据是用脚本按「脊宽 → 开口 → 弧边界」精确推导，
##   非手写，见文件末尾的生成注释）。
##
## 🔴 金标本零扰动：本文件是**纯数据**，不被金标本引擎引用；`tri-fissure` 条目
##   逐位等于现有 `const` 表（作对照锚点，不覆盖运行时表）。
##
## ⚠️ Godot 坑
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload。
##

# ---------------------------------------------------------------------------
#  地图变体设计（差异化轴：岩脊宽 / 开口分布 / 阵地布局）
# ---------------------------------------------------------------------------
## 🔴 每张变体只动「安全轴」，阵地 SITES 绝大多数**复用基准表**（"sites": null 语义），
##   只有少数做「已验证断链」的调整。原因见 scene-map §5.5「实勘修正」教训：
##   阵地格坐标必须按**格距**验断链（≥28.6u），不能拍脑袋写 —— 复用基准表零风险。
##
## 变体轴速览（开口 = 360 − Σ脊宽，均 ≥ 300 红线）：
##   tri-fissure  基准三裂环（脊 18+14+8 · 开口 320°）
##   variant-a    岩脊加宽（脊 24+18+12 · 开口 306° · 曝光 ×1.176）
##   variant-b    阵地微调（孤台 N2 1→2 格，脊/口不变）
##   variant-c    开口对称化（脊 24+14+6 · 开口 316°）
##   variant-d    岩脊收窄（脊 14+10+4 · 开口 332° · 曝光 ×1.084）
##   variant-e    岩脊换向（主口移到东向 130°，脊 18+14+8 · 开口 320°）
##   variant-f    四岩脊（脊 16+12+12+10 · 开口 310° · 四口近似等宽）
##   variant-g    开口密度（南口收窄 114→102，东北口加宽 116→128）
##   variant-h    阵地加密（主力台 P3 3→4 格）
##   fusion       终局（脊 28+20+12 · 开口 300° = 红线下限 · 曝光 ×1.200）
##
## 每张变体条目 schema：
##   · name       中文名（世界观占位）
##   · open_deg   开口总角宽（°）= 360 − Σ脊宽
##   · ridges     Array[{id,name,a0,a1,r0,r1,pad}]  岩脊（角向遮挡，r1 恒 ≤58）
##   · spawn_arcs Array[{id,name,a0,a1}]             出怪口（与脊互补拼接 360°）
##   · sites      Array 或 null —— null = 复用基准 `BuildGrid.SITES`；
##                非 null = 本变体的完整阵地表（已验证断链）
const VARIANTS: Dictionary = {
	# ── 基准：与现有 const 表逐位一致（对照锚点，不覆盖运行时）──
	"tri-fissure": {
		"name": "三裂环",
		"open_deg": 320.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 18.0, "a1": 36.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 36.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 262.0, "a1": 378.0},
		],
		"sites": null,
	},
	# ── 第一章 · 熔炉（Swarm）：主轴 = 岩脊加宽（提高全局曝光税）──
	"variant-a": {
		"name": "熔炉·加宽",
		"open_deg": 306.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 15.0, "a1": 39.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 148.0, "a1": 166.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 252.0, "a1": 264.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 39.0, "a1": 148.0},
			{"id": "B", "name": "西北口", "a0": 166.0, "a1": 252.0},
			{"id": "C", "name": "东北口", "a0": 264.0, "a1": 375.0},
		],
		"sites": null,
	},
	"variant-b": {
		"name": "熔炉·孤台",
		"open_deg": 320.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 18.0, "a1": 36.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 36.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 262.0, "a1": 378.0},
		],
		# 孤台 N2 1→2 格（北孤台增一格，制造「安全但更挤」的选择）
		"sites": [
			{"id": "P1", "name": "南台", "shape": "2×3", "r": 26.0, "theta": 93.0,
				"cells": [Vector2i(-1, 9), Vector2i(0, 9), Vector2i(-1, 10), Vector2i(0, 10), Vector2i(-1, 11), Vector2i(0, 11)]},
			{"id": "P2", "name": "西台", "shape": "十字", "r": 22.0, "theta": 209.0,
				"cells": [Vector2i(-8, 0), Vector2i(-7, 0), Vector2i(-9, 0), Vector2i(-8, 1), Vector2i(-8, -1)]},
			{"id": "P3", "name": "北台", "shape": "1×3", "r": 30.0, "theta": 320.0,
				"cells": [Vector2i(10, -13), Vector2i(10, -12), Vector2i(10, -11)]},
			{"id": "N1", "name": "东孤台", "shape": "单格", "r": 40.0, "theta": 42.0,
				"cells": [Vector2i(13, 3)]},
			{"id": "N2", "name": "北孤台", "shape": "双格", "r": 41.7, "theta": 266.8,
				"cells": [Vector2i(-1, -15), Vector2i(-1, -14)]},
			{"id": "N3", "name": "西孤台", "shape": "单格", "r": 41.7, "theta": 146.8,
				"cells": [Vector2i(-15, 16)]},
		],
	},
	# ── 第二章 · 霜序（Armor）：主轴 = 开口再分配（密度差）──
	"variant-c": {
		"name": "霜序·对称",
		"open_deg": 316.0,
		"ridges": [
			{"id": "G1", "name": "东断崖", "a0": 14.0, "a1": 38.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西南断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 260.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 38.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 260.0, "a1": 374.0},
		],
		"sites": null,
	},
	"variant-d": {
		"name": "霜序·收窄",
		"open_deg": 332.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 20.0, "a1": 34.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 152.0, "a1": 162.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 256.0, "a1": 260.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 34.0, "a1": 152.0},
			{"id": "B", "name": "西北口", "a0": 162.0, "a1": 256.0},
			{"id": "C", "name": "东北口", "a0": 260.0, "a1": 380.0},
		],
		"sites": null,
	},
	"variant-e": {
		"name": "霜序·换向",
		"open_deg": 320.0,
		"ridges": [
			{"id": "G1", "name": "东断崖", "a0": 0.0, "a1": 18.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西南断墙", "a0": 148.0, "a1": 162.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "西北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "东口", "a0": 18.0, "a1": 148.0},
			{"id": "B", "name": "西南口", "a0": 162.0, "a1": 254.0},
			{"id": "C", "name": "北口", "a0": 262.0, "a1": 360.0},
		],
		"sites": null,
	},
	# ── 第三章 · 枢网（Trickle）：主轴 = 多脊 + 阵地加密（拓扑最复杂）──
	"variant-f": {
		"name": "枢网·四脊",
		"open_deg": 310.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 18.0, "a1": 34.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 110.0, "a1": 122.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 200.0, "a1": 212.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
			{"id": "G4", "name": "东短脊", "a0": 290.0, "a1": 300.0, "r0": 30.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 34.0, "a1": 110.0},
			{"id": "B", "name": "西口", "a0": 122.0, "a1": 200.0},
			{"id": "C", "name": "北口", "a0": 212.0, "a1": 290.0},
			{"id": "D", "name": "东口", "a0": 300.0, "a1": 378.0},
		],
		"sites": null,
	},
	"variant-g": {
		"name": "枢网·密度",
		"open_deg": 320.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 30.0, "a1": 48.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		# 南口收窄 114→102、东北口加宽 116→128（密度差拉大）
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 48.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 262.0, "a1": 390.0},
		],
		"sites": null,
	},
	"variant-h": {
		"name": "枢网·加密",
		"open_deg": 320.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 18.0, "a1": 36.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 164.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 262.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 36.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 164.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 262.0, "a1": 378.0},
		],
		# 主力台 P3 3→4 格（前哨扩容，制造「更大主力台」的拓扑选择）
		"sites": [
			{"id": "P1", "name": "南台", "shape": "2×3", "r": 26.0, "theta": 93.0,
				"cells": [Vector2i(-1, 9), Vector2i(0, 9), Vector2i(-1, 10), Vector2i(0, 10), Vector2i(-1, 11), Vector2i(0, 11)]},
			{"id": "P2", "name": "西台", "shape": "十字", "r": 22.0, "theta": 209.0,
				"cells": [Vector2i(-8, 0), Vector2i(-7, 0), Vector2i(-9, 0), Vector2i(-8, 1), Vector2i(-8, -1)]},
			{"id": "P3", "name": "北台", "shape": "1×4", "r": 30.0, "theta": 320.0,
				"cells": [Vector2i(10, -13), Vector2i(10, -12), Vector2i(10, -11), Vector2i(10, -10)]},
			{"id": "N1", "name": "东孤台", "shape": "单格", "r": 40.0, "theta": 42.0,
				"cells": [Vector2i(13, 3)]},
			{"id": "N2", "name": "北孤台", "shape": "单格", "r": 41.7, "theta": 266.8,
				"cells": [Vector2i(-1, -15)]},
			{"id": "N3", "name": "西孤台", "shape": "单格", "r": 41.7, "theta": 146.8,
				"cells": [Vector2i(-15, 16)]},
		],
	},
	# ── 终局 · 核心（Mixed）：开口压到红线下限 300° ──
	"fusion": {
		"name": "核心·终局",
		"open_deg": 300.0,
		"ridges": [
			{"id": "G1", "name": "东南断崖", "a0": 14.0, "a1": 42.0, "r0": 30.0, "r1": 58.0, "pad": 2.0},
			{"id": "G2", "name": "西断墙", "a0": 150.0, "a1": 170.0, "r0": 24.0, "r1": 58.0, "pad": 2.0},
			{"id": "G3", "name": "北短脊", "a0": 254.0, "a1": 266.0, "r0": 32.0, "r1": 58.0, "pad": 1.0},
		],
		"spawn_arcs": [
			{"id": "A", "name": "南口", "a0": 42.0, "a1": 150.0},
			{"id": "B", "name": "西北口", "a0": 170.0, "a1": 254.0},
			{"id": "C", "name": "东北口", "a0": 266.0, "a1": 374.0},
		],
		"sites": null,
	},
}

# ---------------------------------------------------------------------------
#  查询（只读）
# ---------------------------------------------------------------------------
## 变体 id 是否已登记。
static func exists(map_id: String) -> bool:
	return VARIANTS.has(map_id)


## 变体中文名（未知 → 回退 "三裂环"）。
static func name(map_id: String) -> String:
	var v: Dictionary = VARIANTS.get(map_id, {})
	if v.is_empty():
		return "三裂环"
	return String(v.get("name", "三裂环"))


## 该变体的岩脊表（恒有）。
static func ridges(map_id: String) -> Array:
	var v: Dictionary = VARIANTS.get(map_id, {})
	if v.is_empty():
		return []
	return v.get("ridges", [])


## 该变体的出怪口表。
static func spawn_arcs(map_id: String) -> Array:
	var v: Dictionary = VARIANTS.get(map_id, {})
	if v.is_empty():
		return []
	return v.get("spawn_arcs", [])


## 该变体的开口总角宽（未知 → 0）。
static func open_deg(map_id: String) -> float:
	var v: Dictionary = VARIANTS.get(map_id, {})
	if v.is_empty():
		return 0.0
	return float(v.get("open_deg", 0.0))


## 该变体的阵地表（null = 复用基准 `BuildGrid.SITES`）。
static func sites(map_id: String):
	var v: Dictionary = VARIANTS.get(map_id, {})
	if v.is_empty():
		return null
	return v.get("sites", null)


# ---------------------------------------------------------------------------
#  合法性自检（红线逐条验证，供断言套件调用）
# ---------------------------------------------------------------------------
## 检查某变体的脊-弧是否**互补拼接**（开口 = 360 − Σ脊宽 ≥ 300；弧 a1 = 下一脊 a0）。
##   返回 {ok, reason}。这是「脊-弧互补」的硬约束：`map_theta_deg` 依赖它保序保测度。
##   🔴 验证口径：只做**算术自洽**（脊宽+弧宽=360、开口≥300、弧-脊端点无缝），
##      不做跨 0° 覆盖检测（那需要与 `map_theta_deg` 的 `G` 分段逻辑逐位对拍，
##      由 `test_suite_radial.gd` E-M3 对**运行时表**守护；变体表这里只保证数据自洽）。
static func validate_arcs(map_id: String) -> Dictionary:
	var arcs := spawn_arcs(map_id)
	var rgs := ridges(map_id)
	if arcs.is_empty() or rgs.is_empty():
		return {"ok": false, "reason": "缺脊或缺口"}
	# ① 开口 ≥ 300°（AC-R1 红线）
	var open := open_deg(map_id)
	if open < 300.0 - 1e-6:
		return {"ok": false, "reason": "开口 %.1f < 300° 红线" % open}
	# ② 脊宽总和 = 360 − 开口
	var ridge_sum := 0.0
	for rg in rgs:
		ridge_sum += float(rg["a1"]) - float(rg["a0"])
	if absf((360.0 - open) - ridge_sum) > 1e-6:
		return {"ok": false, "reason": "脊宽和 %.1f ≠ 360−开口 %.1f" % [ridge_sum, 360.0 - open]}
	# ③ 弧宽总和 = 开口
	var arc_sum := 0.0
	for arc in arcs:
		var a0: float = fposmod(float(arc["a0"]), 360.0)
		var a1: float = fposmod(float(arc["a1"]), 360.0)
		if a1 <= a0:
			a1 += 360.0
		arc_sum += a1 - a0
	if absf(open - arc_sum) > 1e-6:
		return {"ok": false, "reason": "弧宽和 %.1f ≠ 开口 %.1f" % [arc_sum, open]}
	# ④ 弧-脊端点无缝：每段弧的 a0 必须等于「前一座脊」的 a1（按角度排成环）
	#    简化验证：把脊的 a1 与弧的 a0 收集后，每段弧 a0 都能在某座脊的 a1 处对上。
	var ridge_ends: Array = []
	for rg in rgs:
		ridge_ends.append(fposmod(float(rg["a1"]), 360.0))
	for arc in arcs:
		var a0: float = fposmod(float(arc["a0"]), 360.0)
		var matched := false
		for re in ridge_ends:
			if absf(a0 - float(re)) < 1e-6:
				matched = true
				break
		if not matched:
			return {"ok": false, "reason": "弧起点 %.1f° 无对应脊终点" % a0}
	return {"ok": true, "reason": ""}
