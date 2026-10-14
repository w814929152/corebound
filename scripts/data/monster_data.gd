class_name MonsterData
extends RefCounted
##
## 怪物原型 / Elite 三张表 —— **GDD `wave-spawner` v0.2 §2.5 / §2.5.4** 的唯一登记处
##
## 🔴 定位（control-manifest §5）：`scripts/data/` = SSOT。工程层禁止就地写这些字面量，
##    一律 `MonsterData.*` 读取。本文件**只登记 GDD 定稿值 + 派生函数**，不新增任何数值。
##
## 🔴 W-C1 三条守恒（GDD §2.5.2）—— 本文件的取值必须全部满足：
##   C-1 总 HP 守恒   Σ p_i · m_hp_i  = 0.40×0.60 + 0.40×0.40 + 0.20×3.00 = 1.000 ✓
##   C-2 只数守恒     Σ p_i            = 0.40 + 0.40 + 0.20                = 1.000 ✓
##   C-3 在场时间守恒 Σ p_i / m_spd_i  = 0.30 + 0.40 + 0.30                = 1.000 ✓
##   （`m_dps` 同族：0.40×0.80 + 0.40×0.60 + 0.20×2.20 = 1.000 ✓ —— 🔒 T1 才用）
##
## 🟡 待拍板 **S5-D1**（见 `docs/phase3/slice5-verify.md` §5）：
##    GDD §2.5 的三原型分化 + §2.5.4 的 Elite **与金标本 `WaveSim.simulate_wave` 不等价**
##    （金标本是「单一基准怪」：全体 `hp = HP_unit(w)`、`t_remain = t_reach`）。
##    实测偏离见 verify §5 的对照表（W10 @1.0×threshold：金标本 7 杀 / 17 漏，
##    三原型 17 杀 / 7 漏）→ 会改动起飞率判据链。
##    → 本文件照 GDD **完整登记**，`WaveDirector` 侧由 `prototype_split_enabled`
##      / `elite_waves_enabled` 两个开关控制是否生效；**MVP 默认 false = 金标本等价口径**。
##
## ⚠️ Godot 坑
##   G1 `int / int` 整数除法 → 所有期望 float 的除法两侧显式 `float()`。
##   G2 `**` 不是运算符；本文件无幂运算（`HP_unit` 由 `WaveSim.monster_stats` 给出）。
##

# ---- GDD §2.5.3 定稿构成（唯一同时满足 C-1/C-2/C-3 的整洁解）----
const PROTOS: Array = ["Rush", "Swarm", "Tank"]

## 只数占比 p
const P: Dictionary = {"Rush": 0.40, "Swarm": 0.40, "Tank": 0.20}
## HP 乘数 m_hp（× HP_unit(w)）
const M_HP: Dictionary = {"Rush": 0.60, "Swarm": 0.40, "Tank": 3.00}
## 速度乘数 m_spd（× v₀ = 10.10 u/s）
const M_SPD: Dictionary = {"Rush": 4.0 / 3.0, "Swarm": 1.0, "Tank": 2.0 / 3.0}
## 对塔伤害系数 m_dps（🔒 T1 才消费；MVP 塔不死 → 不生效）
const M_DPS: Dictionary = {"Rush": 0.80, "Swarm": 0.60, "Tank": 2.20}

# ---- GDD §2.5.4 Elite 波（词缀版，非新原型）----
const ELITE_EVERY := 5              # Elite 波 = {5,10,15,20,…}
const ELITE_SHARE := 0.10           # n_e = max(2, round(0.10·N))
const ELITE_MIN := 2
const ELITE_HP_MULT := 2.5          # m_hp_elite（浓缩口径：Elite 单只 = 2.5 × HP_unit）

## 🔒 T1 ⑤ Sapper 精英（Q-T11 顺序3「锁定增伤流」）：Sapper 对塔伤害倍率 ×3。
##   Sapper = Elite 波（每5波）里的精英怪 —— 无视距离直奔最近的塔并锁定攻击。
##   对塔 DPS = `ATTRITION × HP0 × m_dps × sapper_dmg_mult(w)`（W≥10 走随波梯度；见下方 P2-Sapper SSOT）。
##   🔴 金标本零改动：Sapper 由 elite_waves_enabled 诊断开关控制，MVP 恒 false → 本值不消费。
const SAPPER_DMG_MULT := 3.0        # Sapper 对塔伤害 ×3（塔杀手）

# ---- 🟠 P2-Sapper 对塔倍率梯度（W≥10）SSOT：sapper_dmg_mult(w) ----
## spec `docs/phase6/balance-p2-spec.md` §1.2。`sapper_dmg_mult(w) = SAPPER_DMG_MULT × g(w)`；
## `w < SAPPER_RAMP_W0` → `g≡1`（W5 教学墙逐位不变）。
## 🟢 提交①「落机制」中性值 `G0=1.0 / SLOPE=0.0` ⇒ `g(w)≡1.0`（全 w）⇒ 返回值逐位 == `SAPPER_DMG_MULT`（3.0）；
##    中性值同时是 kill-switch：翻参后把 `G0/SLOPE` 退回中性值即零代码回滚（spec §6.1 第 1 档）。
## 🔴 放本文件（非 `mvp_config.gd`）→ 零 cfg-shape 变更（`cfg_of()` 金标本对象形状不动）。
const SAPPER_RAMP_W0 := 10          # 梯度开启波（唯一已定值 · GRADIENT_ON_WAVE）
const SAPPER_RAMP_G0 := 1.0         # 🟡 中性值（提交①）· W0 处梯度基线 g(W0)
const SAPPER_RAMP_SLOPE := 0.0      # 🟡 中性值（提交①）· 每波线性增量（≥0）
const SAPPER_RAMP_CAP := 3.0        # g 上限（clampf 上界 ≥ G0）


static func sapper_dmg_mult(w: int) -> float:
	if w < SAPPER_RAMP_W0:                      # w ∈ {1..9}（含 W5）→ 逐位保留现行 3.0
		return SAPPER_DMG_MULT
	var g := SAPPER_RAMP_G0 + SAPPER_RAMP_SLOPE * float(w - SAPPER_RAMP_W0)
	g = clampf(g, SAPPER_RAMP_G0, SAPPER_RAMP_CAP)
	return SAPPER_DMG_MULT * g


# ---- GDD §2.6 仇恨（🔒 T1 生效；MVP 骨架登记，不进判定）----
const AGGRO_R := 9.0                # R1 转向半径（水平面 XZ，不判 Y）
const AGGRO_TICK := 0.10            # R3 判定频率（与 sim 真身 dt=0.1 对齐）
const AGGRO_EXIT := 10.8            # R4 迟滞带退出阈值 = 9.0 × 1.2

## 🔒 T1（Q-T2/Q-T3 已定稿冻结 · V-1 扫参定稿）：ATTRITION = 怪物对塔 DPS ÷ HP0。
##   GDD §2.1/§4.2 明确：塔死亡频率由**复合比** `ATTRITION = 怪物对塔DPS ÷ HP0`
##   决定（HP0 与对塔 DPS 是一对共轭参数，只扫这一个复合比）。
##   · 塔受到的对塔 DPS = `ATTRITION × HP0 × m_dps(proto)` —— m_dps 提供原型分化
##     （Rush 0.80 / Swarm 0.60 / Tank 2.20，§2.5.2 冻结），ATTRITION 是唯一的扫描基比。
##   · ✅ **V-1 定稿 = 1.50**（300 局 MC 扫参，2026-10-03）：扫参区间 [0.5, 8] 步长 0.5，
##     本值 = 首个全判据通过点（对起飞率冲击最小的甜点）：
##       T-A 苟活期 W1-5 = 1.81（≥1 机制可感知）✓ / T-B 成型期 W6-12 = 0.46（≤2 不失控）✓ /
##       T-C 雪崩期 W13-20 = 0.0（≈0 自然退场）✓ / 起飞率 B = 0.883（≥0.80 红线，余量 +8.3pp）✓
##     🔴 **起手保护耦合**：本值在「W1–2 起手单塔期仇恨不激活」（`WARMUP=2`，见下）前提下定稿；
##       无保护时起手塔 W1 必死、起飞率 0%（对照诊断证实）→ 二者必须成对生效。
##     🟡 **遗留（✅ V-2 已定稿关闭 · 2026-10-04）**：起飞率 A 全程 0.29–0.46 < 0.60 红线
##       （金标本 A 主塔也站暴露区，与起手崩盘同源）→ V-2 根因诊断定稿：根因 = 单核零冗余 ×
##       全暴露位 × 金标本 AI 不保塔 三重结构性碰撞（非数值失衡）。300 局 protect_core 对照：
##       A 无保护 0.393 / A 保主力塔 0.583（仍破线）/ B 0.883。处置 = 承认"单核高风险画像"为
##       设计预期（60% 红线针对会保塔的玩家，AI 的 0.393 是不保塔下限、0.583 是半保塔上限），
##       不动红线 / 金标本；真实可行性由暴露度 UI（玩法①）支撑。详见 GDD §4.2 V-2 定稿行。
const ATTRITION := 1.5              # ✅ V-1 定稿（300 局 MC）· 怪物对塔 DPS ÷ HP0（基比）

## 🔒 T1 V-1 定稿：起手保护波数 = 2（与 ATTRITION 成对生效）。
##   W1..WARMUP 期间仇恨不激活（塔不会被打死），让"起手单暴露塔"金标本配置有喘息期，
##   机制从 W(WARMUP+1)=W3 起才致命——贴合 GDD「苟活期可感知、成型期才致命」的意图。
##   🔴 无此保护则起手塔 W1 必死、起飞率 0%（对照诊断）→ 与 ATTRITION 成对，不得单独关闭。
const WARMUP := 2                   # ✅ V-1 定稿 · 起手保护波数（仇恨 W3 起生效）

## 🔒 T1 V-1 扫参：解析生效的 ATTRITION。
##   · `override < 0`（默认）→ 返回定稿常量 `ATTRITION`（金标本零改动：运行时/单测
##     不传覆盖值时行为完全不变，判据链与逐位对齐基线不受影响）。
##   · `override >= 0` → 返回覆盖值（仅供扫参脚本遍历 [0.5, 8] 用；扫参定稿后回写常量）。
##   🔴 两处消费点（`WaveDirector._damage_tower` / `WaveSimAggro._damage_tower`）
##     一律经此函数取值，禁止就地读 `ATTRITION`，否则扫参覆盖失效。
static func resolve_attrition(override: float = -1.0) -> float:
	return override if override >= 0.0 else ATTRITION

const _FpPow := preload("res://scripts/engine/fp_pow.gd")

# ---- GDD §2.2.1 派生基准速度 ----
## v₀ = L / t_reach = 101.0 / 10.0 = 10.10 unit/s
static func v0(total_len: float, t_reach: float) -> float:
	return total_len / t_reach


# ---- GDD §2.1 塔被攻击死亡（🔒 T1 生效；Q-T2 = ① 已定稿冻结）----
## 🔴 定稿：`HP_i = HP0 × h_i^0.6`（Q-T2 = ①）。
##   · HP0 = 120（全场统一，不按原型区分——刻意只开 1 个新参数）。
##   · 指数 0.6 复用 `tower_stack_exp`（与 `Base_i = base_dps × h^0.6` 同一指数）
##     → 「塔的等级同时决定输出与耐久，都是次线性 ∝ h^0.6」。
##   · 🔴 浮点口径与 `damage_engine` 的 Base 计算**逐位同**（都走 `_FpPow.pow_py`
##     + 同一个 `tower_stack_exp`）→ 金标本零改动、判据链不受影响。
##   · MVP 恒不开数值（塔不死）；本函数只在 T1 仇恨激活后被 `WaveDirector` 消费。
const HP0 := 120.0
static func tower_hp(h: int, exp: float = 0.6) -> float:
	return HP0 * _FpPow.pow_py(float(h), exp)


# ---------------------------------------------------------------------------
# 构成取整（复现 GDD §5.2 波次节奏表的「构成 R/S/T」列）
# ---------------------------------------------------------------------------
## 🔴 口径（GDD 未写死取整顺序，本文件给唯一自洽解）：
##   tank  = round(0.20·N)
##   rush  = round(0.40·N)
##   swarm = N − rush − tank          ← 兜住 C-2 只数守恒（Σ ≡ N，恒等成立）
##
## 与 GDD §5.2 表逐波比对：W1 4/4/2 · W3 5/5/3 · W5 6/7/3 · W10 10/9/5 ·
## W15 13/13/6 · W20 16/16/8 全部逐位一致。
## 🟡 GDD 表自身在 W4（6/6/3 = 15 ≠ N=14）、W7（8/8/4 = 20 ≠ 19）、
##    W19（15/16/8 = 39 ≠ 38）三行有加总笔误 —— 本函数按 **C-2 守恒** 取正确解
##    （详见 verify §5「S5-F1」）。
static func composition(n: int) -> Dictionary:
	var tank := int(round(0.20 * float(n)))
	var rush := int(round(0.40 * float(n)))
	var swarm := n - rush - tank
	if swarm < 0:
		swarm = 0
	return {"Rush": rush, "Swarm": swarm, "Tank": tank}


## 出生序列（**按构成比例轮转**，GDD §4.1「每 interval 秒生成 1 只（按构成比例轮转原型）」）。
## 轮转顺序固定 `Swarm → Rush → Tank`（Swarm 是基准怪，先出；Tank 最慢，压后），
## 逐轮依次取一只、取空即跳过 → 三原型**均匀铺开**而不是先来 4 只 Rush 再来 4 只 Swarm。
## 🔴 纯确定性（无 RNG）：同一 N 恒得同一序列。
static func spawn_sequence(n: int) -> Array:
	var c := composition(n)
	var rem := {"Rush": int(c["Rush"]), "Swarm": int(c["Swarm"]), "Tank": int(c["Tank"])}
	var out: Array = []
	out.resize(n)
	var wpos := 0
	var guard := 0
	while wpos < n and guard < n * 4:
		guard += 1
		for p in PROTOS:
			if int(rem[p]) > 0 and wpos < n:
				out[wpos] = p
				wpos += 1
				rem[p] = int(rem[p]) - 1
	return out


# ---------------------------------------------------------------------------
# Elite 波（GDD §2.5.4）
# ---------------------------------------------------------------------------
static func is_elite_wave(w: int) -> bool:
	return w % ELITE_EVERY == 0


## n_e(w) = max(2, round(0.10 × N(w)))   → W5 2 / W10 2 / W15 3 / W20 4
static func elite_count(w: int, n: int) -> int:
	if not is_elite_wave(w):
		return 0
	return maxi(ELITE_MIN, int(round(ELITE_SHARE * float(n))))


## 守恒系数 c(w) = (N − 2.5·n_e) / (N − n_e)
##   → W5 0.7857 / W10 0.8636 / W15 0.8448 / W20 0.8333（GDD §2.5.4 表）
## 🔴 保证：n_e 只数吃掉 2.5×，其余 (N−n_e) 只按 c(w) 等比下调 →
##    总 HP 与只数**双守恒**；速度沿用宿主原型 → C-3 自动成立。
static func elite_conserve(n: int, n_e: int) -> float:
	if n_e <= 0:
		return 1.0
	return (float(n) - ELITE_HP_MULT * float(n_e)) / (float(n) - float(n_e))


## Elite 词缀落在哪几个出生序号上：**沿波次均匀铺开**（GDD 只定只数，未定位置）。
## 🔴 纯确定性：idx_j = floor(N·(j+0.5)/n_e)，j ∈ [0, n_e)。
static func elite_indices(n: int, n_e: int) -> Array:
	var out: Array = []
	if n_e <= 0:
		return out
	for j in range(n_e):
		var idx := int(floor(float(n) * (float(j) + 0.5) / float(n_e)))
		idx = clampi(idx, 0, maxi(0, n - 1))
		if not out.has(idx):
			out.append(idx)
	return out


## 单只 HP 乘数（相对 `HP_unit(w)`）
##   Elite      → 2.5（GDD：浓缩口径，不再乘宿主原型的 m_hp）
##   普通怪     → m_hp(proto) × c(w)
static func hp_mult(proto: String, is_elite: bool, c: float) -> float:
	if is_elite:
		return ELITE_HP_MULT
	return float(M_HP[proto]) * c


## 单只速度乘数：🔴 Elite **沿用宿主原型**（C-3 自动成立）
static func spd_mult(proto: String) -> float:
	return float(M_SPD[proto])
