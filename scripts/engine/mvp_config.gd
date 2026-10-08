class_name MvpConfig
extends RefCounted
##
## MVP 定稿配置工厂 —— 移植自
##   corebound_sim_v03.py `make_cfg()` (L149-197)
## + corebound_sim_v06_synergy.py `v06_cfg()` (L245-270)
## + corebound_sim_v08_salvage.py `cfg_of()` (L297-320)
##
## 🔴 冻结项（一个都不许动）：
##   hp_growth=1.42 / hp_base=16.0 / focus_per_layer=0.06 / focus_full=false / focus_min_h=8.0
##   synergy_on=false（Syn 已摘除）/ softcap_decay=1.03 / reinf_cap=100
##   link_min_level=3 / link_rule="substantial"(0.65) / κ_r=0.050 / pity=true
##   tower_stack_exp=0.6 / allin_mult=1.6 / allin_share=0.60 / crossfire 1.25·1.5
##   aux_tau=8.0 / aux_cap=1.5 / aux_mode="global" / use_empowerment=false
##   coverage_mode="path"（MVP 用路径常量 0.78/0.95，不走几何）
##
## ✅ 口径开关（ADR-0001 已拍板 2026-09-30，主理人签）：
##   kr_mode = "tier" | "flat" —— MVP 唯一默认 = "tier"（下方 kr_mode 默认值已锁定）
##     "tier" = GDD §10.1 金标本 B 的取值口径（中性塔 κ_r 恒取基准档 0.045）→ B=4,991,135.61
##     "flat" = v08 `cfg_of()` 旧默认（全场统一 0.050）                      → B=4,991,174.07
##     两者只差「无 Tag 的 Arrow 那一条 E=9 的共鸣率」，A 路径完全相同（E 全为 0）。
##     🔴 "flat" 仅保留为回归/敏感性口径（一行可切回），生产路径、金标本验收、GDD §10.1 三者统一 tier。
##     拍板依据：主理人回溯 mapA-kappaR-sweep.md §2/§5，§10.1 的 4,991,136 即档位口径产物。
##

# ---- κ_tag 档位（MVP 两档）—— v06 L44 ----
const KTAG_TIERS_MVP: Array = [[0.0, 0.06], [3.0, 0.10]]
# ---- κ_r 档位（GDD §5.4 三档）—— v06 L48 ----
const KR_TIERS_T1: Array = [[0.0, 0.040], [3.0, 0.045], [20.0, 0.050]]
# ---- StackCap 档位（MVP 未启用）—— v06 L50 ----
const STACKCAP_TIERS: Array = [[0.0, 50.0], [3.0, 100.0], [20.0, 150.0]]

const KR_FINAL := 0.050
const KR_NEUTRAL := 0.045
const HP_GROWTH := 1.42
const HP_BASE := 16.0
const FOCUS_PER_LAYER := 0.06
const LINK_RULE := "substantial"
const SALVAGE_REFUND := 0.50

# ---------------------------------------------------------------------------
#  切片3 新增 · 商店 / 时钟口径（`design/gdd/shop-reroll.md` v1.1 §3.1 常量表）
#
#  🔴 两条纪律：
#    1. 全部**只在这里定义一次**，UI / 状态机 / 布局一律 `MvpConfig.*` 读取，禁止就地写字面量；
#    2. 不塞进 `cfg_of()` 的 Dictionary —— 那是切片1/2 金标本的配置对象，
#       新增 key 会改变它的形状（打印 / 序列化 / 遍历都可能受影响）。
#       这些常量与既有冻结项**无交集**，故以模块级 const 形式并列，不触碰冻结清单。
# ---------------------------------------------------------------------------

# ---- 商店 ----
const SHOP_SLOTS := 3                 # 商品位恒为 3（保底不新增第 4 位，A3/A4）
const MAX_LOCK := 1                   # 3 商品位中可锁 1（A3）
const BASE_REROLL := 5                # 刷新成本 5 + 3n 的基数（概念 §8.1）
const REROLL_STEP := 3                # 每次刷新递增（概念 §8.1）
const MIN_REROLL_COST := 1            # 🔴 刷新永不免费（§9 Q-SR9）
const DISCOUNT_CAP := 0.50            # G2 供应链饱和输出上限（card-system §7.3）
const PRICE_STRUCTURE := 12           # 建筑卡（A1）
const PRICE_TOWER_EFFECT := 9         # 单塔效果卡（A1）
const PRICE_GLOBAL_EFFECT := 10       # 全局效果卡（A1）

# ---- 时钟 / 减速预算（🔴 单位 = 实时秒 / 倍）----
const DILATION_SCALE := 0.35            # ② ShopDilated（概念 §8.4）
const DILATION_SCALE_NOVICE := 0.25     # ② 新手保护 W1–5（概念 §2.1 ③）
const PLACEMENT_SCALE := 0.25           # ⑤ PlacementMode（card-system §4.2）
const NOVICE_WAVE_MAX := 5              # W1–W5 为新手保护波（概念 §2.1 ③）
const DILATION_BUDGET := 20.0           # 减速预算 20s 实时秒 / 波（M16）
const TIME_SCALE_COMBAT := 1.0          # ①③ 全速；④ 世界暂停但 time_scale 仍为 1.0（🔴 SR-R5）

# ---- 布局（C3 双焦点）----
const OVERLAY_WIDTH_RATIO := 0.32       # 抽屉基准占屏宽比（锚点 6）
const OVERLAY_MIN_WIDTH_PX := 560.0     # 🔴 最小宽（WCAG AA 可访问性红线，锚点 6 第 3 条）

# ---- CanvasLayer 分层（GDD §2.4 分层表 / 交接点 3）----
const LAYER_BATTLEFIELD_HUD := 10
const LAYER_SHOP_OVERLAY := 100
const LAYER_THREAT_PULSE := 120
const LAYER_CORE_HP := 130              # 🔴 穿透绘制，必须高于商店层
const LAYER_CONFIRM_DIALOG := 140

# ---- 🟡 工程参数（GDD 未定，见架构文档「待主理人拍板」Q-S3-B）----
#  单帧计入预算的实时秒上限：窗口失焦 / 断点调试回来时 `Time` 差值会是一次巨大跳变，
#  若不夹住，玩家一回来预算就被整段吃掉。这里按"超过 250ms 视为没在玩"处理。
const MAX_FRAME_REAL_DT := 0.25


# ---------------------------------------------------------------------------
# 波次时长 / 刷新窗口 —— 金标本 v03 `make_cfg()` L156-157 的两个 lambda
#   wave_dur     = lambda w: 28.0 + 2.2 * w
#   spawn_window = lambda w: 0.30 if w <= 5 else (0.60 if w <= 12 else 1.0)
#
# 🔴 GDScript 的 cfg 是 Dictionary，塞 Callable 会破坏"配置可打印/可序列化"，
#    且 `WaveSim` 每帧要调两次 → 直接落成静态函数（口径完全等价，且无调用开销）。
#    这两条是冻结项：改它们等于改怪物 HP 曲线的分母，全部判据作废。
# ---------------------------------------------------------------------------
static func wave_dur(w: int) -> float:
	return 28.0 + 2.2 * float(w)


static func spawn_window(w: int) -> float:
	if w <= 5:
		return 0.30
	if w <= 12:
		return 0.60
	return 1.0


static func cfg_of(
	path: String = "B",
	kappa_r: float = KR_FINAL,
	rule: String = LINK_RULE,
	kr_mode: String = "tier",
	ntower_mode: String = "current",
	salvage_on: bool = false,
	overrides: Dictionary = {}
) -> Dictionary:
	var c := {
		# ---- 怪物侧（v03 make_cfg）----
		"hp_base": HP_BASE,
		"hp_growth": HP_GROWTH,
		"num_base": 8.0,
		"num_growth": 1.6,
		"scrap_base": 2.0,
		"scrap_growth": 0.5,
		"leak_damage": 50.0,
		"t_reach": 10.0,
		"core_hp": 1000.0,
		# ---- 经济 ----
		"backpack": 5,
		"reroll_base": 5.0,
		"reroll_growth": 3.0,
		"shop_offers": 3,
		# ---- 叠层复利引擎 ----
		"reinf_compound": {"A": 1.10, "B": 1.06},
		"reinf_cap": 100.0,
		"softcap_decay": 1.03,
		"tower_stack_exp": 0.6,
		"synergy_threshold": 3,
		"synergy_mult": 1.5,
		"fire_stock": {"A": 6, "B": 3},
		# ---- 路径修饰 ----
		"path_coverage": {"A": 0.78, "B": 0.95},
		"aoe_cap": {"A": 2.6, "B": 2.2},
		"aoe_per": {"A": 0.24, "B": 0.14},
		# ---- 乘区参数 ----
		"kappa_r": kappa_r,
		"link_min_level": 3,
		"focus_per_layer": FOCUS_PER_LAYER,
		"allin_mult": 1.6,
		"allin_share": 0.60,
		"crossfire_2": 1.25,
		"crossfire_3": 1.5,
		"aux_slow": 0.30,
		# ---- 开关（v06_cfg 定稿）----
		"use_resonance": true,
		"use_focus": true,
		"use_allin": true,
		"use_crossfire": true,
		"use_aux": true,
		"use_empowerment": false,
		"coverage_mode": "path",
		"tower_card_mode": "map",
		"n_slots": 6,
		"link_rule": rule,
		"max_actions": 12,
		"wave_price_step": 0.0,
		"max_towers": null,
		"pity": true,
		"skill": 1.0,
		# 🔒 V-7 repair_on_disable（QG-RADIAL-01 · 诊断开关 · §5-8）：塔死亡后可否在波次间
		#   安全窗修复 Disabled 塔。🔴 **三档枚举，非 bool**（FREE/PRICED 是两个不同的实验臂）：
		#     0 = OFF（默认）—— 金标本等价口径，任何默认/回归/golden_reference 下恒为 0。
		#     1 = FREE —— 结构探针：波次间无条件全修、不占预算（挂 run_loop_aggro，shop_ai 零改动）。
		#     2 = PRICED —— 经济探针：修复作为 shop_ai 候选动作，按 ceil(0.30·invested_est) 定价、
		#                    与 build/up/reinf 竞争同一预算（挂 shop_ai，开关守卫内）。
		#   🔴 与 SpaceModel.mode / elite_waves_enabled 同款哲学：默认 off = 逐位不变；仅显式扫参启用。
		#   🔴 这是诊断工具不是 T1 功能；只在 V-7 三臂扫描（scan_repair_on_disable.gd）里被设非 0。
		"repair_on_disable": 0,
		# ---- v0.6 新增 ----
		"synergy_on": false,          # 🔴 Syn 已摘除（Q-C6）
		"kappa_mode": "tier",
		"ktag_tiers": KTAG_TIERS_MVP,
		"kr_mode": kr_mode,
		"kr_tiers": KR_TIERS_T1,
		"kr_neutral": KR_NEUTRAL,
		"stackcap_tier": false,
		"stackcap_tiers": STACKCAP_TIERS,
		# ---- v0.6 焦点/挂件口径 ----
		"focus_full": false,
		"focus_min_h": 8.0,
		"aux_mode": "global",
		"aux_tau": 8.0,
		"aux_cap": 1.5,
		# ---- v0.8 拆塔 / 兜底① ----
		"ntower_mode": ntower_mode,   # "current"(定稿) | "max"(兜底① N_tower_histmax)
		"salvage_on": salvage_on,
		"salvage_from_wave": 1,
		"salvage_refund": SALVAGE_REFUND,
	}
	for k in overrides:
		c[k] = overrides[k]
	_assert_frozen(c)
	return c


# 🔴 不变量自检：定稿项被改动就当场炸，避免"文档定 A、引擎跑 B"
static func _assert_frozen(c: Dictionary) -> void:
	assert(c["focus_full"] == false, "focus_full 必须保持 false（D-1 定稿 Focus 预热门槛）")
	assert(float(c["focus_min_h"]) == 8.0, "focus_min_h 必须 8.0")
	assert(c["synergy_on"] == false, "synergy_on 必须 false（Syn 已摘除）")
	assert(float(c["focus_per_layer"]) == FOCUS_PER_LAYER, "focus_per_layer 必须 0.06")
	assert(c["pity"] == true, "pity 必须 true")
	assert(float(c["softcap_decay"]) == 1.03, "softcap_decay 必须 1.03")
	assert(float(c["reinf_cap"]) == 100.0, "reinf_cap 必须 100")
	assert(int(c["link_min_level"]) == 3, "link_min_level 必须 3")
	assert(float(c["hp_growth"]) == HP_GROWTH, "hp_growth 必须 1.42")
	assert(float(c["hp_base"]) == HP_BASE, "hp_base 必须 16")
	assert(float(c["tower_stack_exp"]) == 0.6, "tower_stack_exp 必须 0.6")
	assert(float(c["allin_share"]) == 0.60, "allin_share 必须 0.60")
	assert(float(c["crossfire_2"]) == 1.25 and float(c["crossfire_3"]) == 1.5, "crossfire 必须 1.25/1.5")
