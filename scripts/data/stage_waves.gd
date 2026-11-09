extends RefCounted
##
## 关卡波表 `StageWaves` —— 每关「波次构成」的**唯一登记处**（SSOT）
## ---------------------------------------------------------------------------
## 🔴 来源：`design/gdd/stage-waves.md`（v1 · 10 关 149 波逐波表）
##   本文件只回答一个问题：**第 w 波长什么样**（只数 / 单只 HP / 三原型构成 / 精英只数）。
##   它不回答「第 w 波有多强」—— 那是 `WaveSim.monster_stats` 的事，本文件只做**重排**。
##
## 🔴 最重要的一条纪律：**整关总血量守恒**
##   Σ(本关各波 n×hp) ≡ Σ(基准曲线各波 n×hp)，逐位相同（误差 < 1e-9）。
##   波表只决定「这份血量分成几份、每份多重、多快到场」，绝不改变总量。
##   → 于是"这关变难了"永远只能归因于**形状**，不能归因于暗改数值。
##   → 要加难度请加波数（+1 波 = 末波贵 42%），要调节奏请换波型。两条路分开走。
##
## 🔴 引擎里真正能改的只有三条通道（`design/gdd/stage-waves.md` §1 的结论）：
##   ① 只数 n       → 废料经济（`scrap_per_kill` 按只发）+ 漏怪致死
##                     （核心 1000 ÷ 每只 50 = **恒 20 只预算**：任何一波 n>20 全漏必死）
##   ② 三原型构成   → 对塔伤害（`M_DPS`：Tank 2.20 / Swarm 0.60，铁壁波 1.59×）
##   ③ 速度分布     → 到场节奏
##   ⚠️ 现有结算 = 全场聚合池 + 溢出结转 + **不判射程** → 「考 AoE」「考爆发」在机制上不存在。
##      同样总血量下，1 只肥怪和 10 只瘦怪逐位同结果。所以本文件**不承诺**这两件事。
##
## 🔴 与 `MonsterData` 的分工（不许互相覆盖）：
##   · `MonsterData` = 三原型基数（`M_HP` / `M_SPD` / `M_DPS`）与 Elite 公式 —— **不改**；
##   · `StageWaves` = 每波取什么构成、只数乘多少、血量偏置多少 —— **只读基数**。
##   · 构成归一化（`proto_mult`）保 C-1 总 HP 守恒与 C-3 在场时间守恒；
##     `M_DPS` **故意不归一化** —— 它就是「重甲占比 → 对塔伤害」这条通道本身。
##
## 🔴 金标本零扰动：
##   · 本文件是**纯数据 + 纯函数**，不持有运行时状态，不被金标本引擎引用；
##   · `WaveDirector` 侧由 `stage_waves_enabled`（默认 false）控制是否生效；
##   · `"0-1"` 全表中性（只有 `n` / `E`），`wave_spec()` 对它恒返回 `{"neutral": true}`
##     → 调用方**不得覆盖任何值** → 0-1 与金标本逐位等价（回归锚点，见 V-5）。
##
## ⚠️ Godot 坑
##   G6 headless 无 global_script_class_cache → 不写 `class_name`，一律 preload。
##   G1 `int / int` 整数除法 → 浮点除法两侧显式 float()。
##   G2 `**` 不是运算符 → 幂运算一律走 `_WaveSim.monster_stats`（内部 `_FpPow.pow_py`）。
##

const _MonsterData := preload("res://scripts/data/monster_data.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _MvpConfig := preload("res://scripts/engine/mvp_config.gd")

## 全项目唯一有 MC 支撑的波数上限（= 金标本 `run_loop` 的 max_wave）。
##   波表长度**不得**超过它：`1.42` 指数下多打一波，末波就贵 42%。
const MAX_WAVE_LIMIT := 20

# ---------------------------------------------------------------------------
#  波型表（6 + 1 型）
# ---------------------------------------------------------------------------
## 每型三个旋钮：
##   · n     只数乘数（× 基准 N(w)）—— 直接改经济与漏怪预算，**最锋利的那个**
##   · bias  血量偏置（× 基准 total_hp(w)）—— 只改「这一波的血量集中度」，
##           整关归一化系数 k 会把它抵回来，所以它只在**关内**重新分配血量
##   · comp  三原型构成（R 疾行 / S 群集 / T 重甲），只影响对塔伤害与到场节奏
##
## 🔴 `bias` 不是难度旋钮：Σ 被 k 吃掉，它只决定"这波的血比平均多还是少"。
const ARCH: Dictionary = {
	"p": {"label": "试探", "n": 0.70, "bias": 0.85, "comp": {"R": 0.40, "S": 0.40, "T": 0.20}},
	"n": {"label": "常规", "n": 1.00, "bias": 1.00, "comp": {"R": 0.40, "S": 0.40, "T": 0.20}},
	"s": {"label": "潮涌", "n": 1.45, "bias": 1.00, "comp": {"R": 0.55, "S": 0.35, "T": 0.10}},
	"b": {"label": "铁壁", "n": 0.65, "bias": 1.10, "comp": {"R": 0.15, "S": 0.25, "T": 0.60}},
	"t": {"label": "涓流", "n": 0.40, "bias": 1.05, "comp": {"R": 0.10, "S": 0.30, "T": 0.60}},
	"e": {"label": "处刑", "n": 1.00, "bias": 1.15, "comp": {"R": 0.40, "S": 0.40, "T": 0.20}},
	# 0-1 专用「处刑·基准」：与常规同参，只用来标记精英波 → 保证锚点不偏
	"E": {"label": "处刑·基准", "n": 1.00, "bias": 1.00, "comp": {"R": 0.40, "S": 0.40, "T": 0.20}},
}

## 合法波型字符（V-1 断言用）。
const CODES := "npsbtEe"

## comp 的短键 → `MonsterData` 的长键。
##   🔴 波表用 R/S/T 写（表窄、易读），基数表用 Rush/Swarm/Tank，本映射是唯一桥梁。
const PROTO_OF: Dictionary = {"R": "Rush", "S": "Swarm", "T": "Tank"}

# ---------------------------------------------------------------------------
#  关卡顺序 / 波型串 / 设计波数（三者必须闭合，见 V-2）
# ---------------------------------------------------------------------------
## 关卡稳定序 = `design/gdd/campaign-v2-overseer.md` 的十关（图状解锁，序仅用于测试与展示）。
const STAGE_ORDER: Array = [
	"0-1",
	"1-1", "2-1", "3-1",
	"4-1", "5-1", "6-1", "7-1",
	"8-1", "9-1",
]

## 波型串即表：第 i 个字符 = 第 i+1 波。长度 = 该关波数，**完全闭合**（不做"不够就补常规波"）。
##   n 常规 / p 试探 / s 潮涌 / b 铁壁 / t 涓流 / e 处刑 / E 处刑·基准
const PATTERN: Dictionary = {
	"0-1": "nnnnEnnnnE",             # 铁砧·中继站 · 10 波（全中性 → 锚点）
	"1-1": "nnsnespsbses",           # 灰烬熔炉 · 12 波 · 首铁壁 W9
	"2-1": "ppnnsenbsbeb",           # 永冻科考站 · 12 波 · 首铁壁 W8（原 W3）
	"3-1": "pntsebsnbtebt",          # 磁轨长廊 · 13 波 · 首铁壁 W6
	"4-1": "psnsesbssesnbsn",        # 雷暴电网 · 15 波 · 首铁壁 W7（原**零铁壁**）
	"5-1": "pnnsenbsbestbeb",        # 锻造联合体 · 15 波 · 首铁壁 W7（原 W3）
	"6-1": "pnstebstsebstebs",       # 生物研究所 · 16 波 · 首铁壁 W6 · 中段留恢复窗口（W8=潮涌）
	"7-1": "pstsebtsetbstebtb",      # 湮灭实验场 · 17 波 · 首铁壁 W6（原 W3）
	"8-1": "nsssbessbsesbsebsbe",    # 主脑·外围 · 19 波 · 首铁壁 W5（原 W3）· 末波处刑收尾
	"9-1": "pstssbetsbetsbetbsbe",   # 主脑·核心 · 20 波 · 首铁壁 W6（原 W2）
}

## 🔒 v2 修订（2026-11-08 · MC 实测驱动的重排）
##   **问题**：产品口径 MC（aggro + 战斗内复活 + 战斗类型 · 100 局/关）读出
##     基准 20 波 62%，但 5-1..9-1 只有 0–9%。同臂、同 AI、同 seed → 差异只能来自波表。
##     与「首个铁壁波的位置」单调相关：无铁壁 73–75% / W9 64% / W6 47% / W3 0–9% / W2 0%。
##   **根因**：`b`（铁壁）60% Tank → `Σp·M_DPS = 1.59` → 对塔伤害 1.59×。
##     W3 时玩家只有一两座塔、无修复手段 → 一次铁壁 = 「塔被打停 → 输出归零 → 漏怪 → 死」。
##   **处方（本表）**：只重排**时机**，不改守恒 ——
##     ① 首个铁壁 **一律 ≥ W5**（W5 前只出 p/n/s，让玩家先立起来）；
##     ② 铁壁数量随章**递增**：外环 1–3 → 中环 2–4 → 内环 5–7（压力来自「越来越常来」）；
##     ③ 4-1 原**一个铁壁都没有**（75% 的绿洲）→ 补 2 个（W7/W13），消掉章内锯齿；
##     ④ 处刑波与铁壁**不相邻**（相邻 = 双精英尖峰），且首个处刑不早于 W5。
##   🔴 守恒：总血量由 `stage_k` 动态归一（`Σtarget = Σbase`），本表改的是**形状**，
##     不是血量 —— 跑 `run_stage_waves_asserts` 的 V-3 会逐关复核（误差须为 0）。
##   🔴 `PATTERN` 长度必须等于 `WAVES`（V-1/V-2 守着）：本次十个串长度**一个没变**。
##
## 🔴 6-1 的病灶（2026-11-08 · 已验证部分）
##   原版 0%（100 局 MC），逐波 dump 显示死因**不是"太难"，是 DPS 归零**：
##   处刑波一波打停 4~5 座塔（`dis_new` 4→5），下一波 `kills=0 / leaked=全量`，核心一波归零。
##   机制：`e` 是满只数（n×1.00）+ 1.15 血 + 2~k 只精英 → 单只活很久 → 塔被持续啃；
##   若处刑**紧跟在涓流/铁壁之后**（那两种波先把塔磨薄），就会一次拆完。
##   本串把 W8 留成潮涌（杀得快、留场短 = 塔的恢复窗口），W5/W13 两处仍紧贴涓流。
##   ⇒ 结果：0% → 36%（100 局 MC）。
##
## ⚠️ 方法论教训（我自己踩的，写下来防止再犯）
##   期间的 `probe_stage_death.gd` 曾把 `rng` 建在循环**内** → 每局同一条随机流，
##   「24 局」实为同一局跑 24 次，于是把 n=1 的读数当成了通过率，一度得出
##   "0% 与 100% 双稳态、没有中间带"的错误结论。修好后同一版本是 27.5%（11/40），
##   与 MC 的 36% 一致。**任何"通过率"必须确认 rng 在循环外，n≥40。**

## 设计波数（**与 PATTERN 长度冗余登记，专门用来抓"手滑截断一个字符"**）。
##   🔴 这是 V-2 的唯一意义：串长本身不可证伪，只有和"设计意图"对撞才能发现丢波。
const WAVES: Dictionary = {
	"0-1": 10,
	"1-1": 12, "2-1": 12, "3-1": 13,
	"4-1": 15, "5-1": 15, "6-1": 16, "7-1": 17,
	"8-1": 19, "9-1": 20,
}

# ---------------------------------------------------------------------------
#  查询（纯函数）
# ---------------------------------------------------------------------------
static func has_stage(stage_id: String) -> bool:
	return PATTERN.has(stage_id)


## 该关波数（= 波型串长度；未知 → 0）。
static func wave_count(stage_id: String) -> int:
	return String(PATTERN.get(stage_id, "")).length()


## 第 w 波的波型字符（越界 → ""）。
static func code_at(stage_id: String, w: int) -> String:
	var pat := String(PATTERN.get(stage_id, ""))
	if w < 1 or w > pat.length():
		return ""
	return pat[w - 1]


## 该关是否「全中性」——只有 `n` / `E` 两种波型。
##   🔴 0-1 必须是中性：它是整条回归链与金标本的对照锚点（V-5）。
static func is_neutral_stage(stage_id: String) -> bool:
	var pat := String(PATTERN.get(stage_id, ""))
	if pat.is_empty():
		return false
	for i in pat.length():
		var c := pat[i]
		if c != "n" and c != "E":
			return false
	return true


# ---------------------------------------------------------------------------
#  `S` 加压：换形状，不换长度
# ---------------------------------------------------------------------------
## k = floor(S / 3)，S = 已守地区数。
##   🔴 为什么不是"加波数"：`hp` 是 16×1.42^(w−1)，多打一波末波就贵 42%，
##      S=7 时 +3 波 = 同关末波 ×2.86 —— 那不是递增，是同一关换了个 Boss。
##      而且波表会从「闭合」退回「前 N 波」，第 N+1 波没有形状可依，只能回落常规波。
static func escalation_k(escalation: int) -> int:
	return int(floor(float(maxi(0, escalation)) / 3.0))


## 施加 `S` 加压后的波型：把该关**最早的 k 个「试探」波**升级为「潮涌」波。
##   🔴 潮涌波同时是 1.45× 只数 → 1.45× 废料产出 → **加压与加收益是同一个动作**，
##      于是"救得多 = 被惩罚"在机制上不成立（见 stage-waves.md §5）。
static func upgraded_code(stage_id: String, w: int, escalation: int) -> String:
	var code := code_at(stage_id, w)
	if code != "p":
		return code
	var k := escalation_k(escalation)
	if k <= 0:
		return code
	var pat := String(PATTERN.get(stage_id, ""))
	var cnt := 0
	for i in range(mini(w, pat.length())):
		if pat[i] == "p":
			cnt += 1
	return "s" if cnt <= k else code


# ---------------------------------------------------------------------------
#  整关归一化系数 k
# ---------------------------------------------------------------------------
## k = Σ基准总血 / Σ(基准总血 × bias)  → 让「按 bias 重分配后」的整关总量回到基准。
##
## 🔴 `escalation` 必须传进来：`S` 加压会把「试探」升成「潮涌」，而两者的 bias 不同
##    （0.85 → 1.00）。若 k 按升级前的 bias 算，升级后整关总量就会**偷偷变多** ——
##    那正是本设计最不能破的一条（守恒律是"难度只能归因于形状"的地基）。
##    所以 k 必须与 `wave_spec` 用同一套（升级后的）波型算。
##
## 🔴 不做缓存：W ≤ 20，重算成本可忽略（每关一次，全部走 `monster_stats`）。
##    缓存反而有真坑 —— 扫参脚本换 `hp_growth` / `num_base` 后会读到旧 k（stage-waves.md §8.3）。
static func stage_k(stage_id: String, cfg: Dictionary, escalation: int = 0) -> float:
	var pat := String(PATTERN.get(stage_id, ""))
	if pat.is_empty():
		return 1.0
	var tot_base := 0.0
	var tot_raw := 0.0
	for i in pat.length():
		var ms := _WaveSim.monster_stats(i + 1, cfg)
		var base := float(int(ms["n"])) * float(ms["hp"])
		var code := upgraded_code(stage_id, i + 1, escalation)
		tot_base += base
		tot_raw += base * float(ARCH[code]["bias"])
	if tot_raw <= 0.0:
		return 1.0
	return tot_base / tot_raw


# ---------------------------------------------------------------------------
#  🔴 对外主函数：第 w 波长什么样
# ---------------------------------------------------------------------------
## 返回：
##   {}                       表不存在 / w 越界
##   {"neutral": true, ...}   中性波（0-1）→ 调用方**不得覆盖任何值**
##   {"n", "hp", "total", "comp", "elite", "code", "label", "w", "k"}
##
## 🔴 这里的 `hp` 是**单只**血量（不是整波），直接喂 `WaveDirector.hp_unit`。
## 第 w 波的完整 spec（`neutral` 波只有标记、没有数值改动）。
## 🔴 `force_neutral`（诊断用，默认 false）：置 true 后一律返回 `{}` = 该关**长度不变、波型全中性**。
##    用途只有一个：`run_stage_mc` 的**同长度对照臂** —— 用来把「这关难」拆成
##    「它长」与「它的形状难」两部分。十关波数 10–19 不同，直接拿 20 波基准比是跨长度比较。
##    🔴 正式代码永不置位；置位后 `wave_spec` 退化为「无波表」，与金标本路径逐位一致。
static var force_neutral: bool = false

static func wave_spec(stage_id: String, w: int, cfg: Dictionary, escalation: int = 0) -> Dictionary:
	if force_neutral:
		return {}
	var pat := String(PATTERN.get(stage_id, ""))
	if pat.is_empty() or w < 1 or w > pat.length():
		return {}
	if is_neutral_stage(stage_id):
		return {"neutral": true, "w": w, "code": pat[w - 1]}
	var code := upgraded_code(stage_id, w, escalation)
	var arch: Dictionary = ARCH[code]
	var ms := _WaveSim.monster_stats(w, cfg)
	var n0 := int(ms["n"])
	var base := float(n0) * float(ms["hp"])
	var n := maxi(1, int(round(float(arch["n"]) * float(n0))))
	var k := stage_k(stage_id, cfg, escalation)
	var target := base * float(arch["bias"]) * k
	var hp := target / float(n)
	return {
		"w": w,
		"code": code,
		"label": String(arch["label"]),
		"n": n,
		"hp": hp,
		"total": target,
		"comp": (arch["comp"] as Dictionary).duplicate(true),
		"elite": elite_for(code, n, escalation),
		"k": k,
	}


## 处刑波的精英只数。
##   🔴 **必须**沿用引擎现有那条式子，不许另造一个新的：
##      elite = clamp( max(2, round(0.10·n)) + k , 2 , floor(n/4) )
##   · `+k` 只在 `e`（处刑）上加；`E`（0-1 的基准处刑）**不加**，否则锚点漂移。
##   · 上限 `floor(n/4)` 的来源：`elite_conserve(n, n_e) = (n − 2.5·n_e) / (n − n_e)`
##     在 `n_e ≥ n/2.5` 时变负 → 必须 n_e < 0.4n，取 0.25n 更稳。
##   · 历史坑：第一版草稿用 `2 + floor((w−1)/7)`，在 0-1 的 W10（n=24）算出 3 只，
##     而 `MonsterData.elite_count` 给的是 2 —— **一只精英的差就让 0-1 不再逐位等价**。
static func elite_for(code: String, n: int, escalation: int = 0) -> int:
	if code != "e" and code != "E":
		return 0
	var ne := maxi(_MonsterData.ELITE_MIN, int(round(_MonsterData.ELITE_SHARE * float(n))))
	if code == "e":
		ne += escalation_k(escalation)
	var cap := maxi(_MonsterData.ELITE_MIN, int(floor(float(n) / 4.0)))
	return mini(clampi(ne, _MonsterData.ELITE_MIN, cap), n)


# ---------------------------------------------------------------------------
#  三原型：构成 → 单只乘数
# ---------------------------------------------------------------------------
## 归一化口径：`k_hp = 1 / Σ(p·M_HP)`、`k_spd = Σ(p/M_SPD)`。
##   前者保 **C-1 总 HP 守恒**，后者保 **C-3 在场时间守恒**。
##   🔴 `M_DPS` **故意不归一化** —— 归一化掉等于废掉「重甲 → 对塔伤害」这条通道。
##
## 🔴 基准构成（40/40/20）走**短路**，直接返回 `MonsterData` 原值：
##   浮点下 `0.4×0.6 + 0.4×0.4 + 0.2×3.0 = 1.0000000000000002`，
##   除下来会得到 0.5999999999999999 而非 0.6 —— 差 1 ULP 就够毁掉逐位等价。
static func proto_mult(comp: Dictionary) -> Dictionary:
	var is_base := absf(float(comp.get("R", 0.0)) - 0.40) < 1e-9 \
		and absf(float(comp.get("S", 0.0)) - 0.40) < 1e-9 \
		and absf(float(comp.get("T", 0.0)) - 0.20) < 1e-9
	if is_base:
		return {"hp": _MonsterData.M_HP.duplicate(), "spd": _MonsterData.M_SPD.duplicate()}
	var kh := 0.0
	var ks := 0.0
	for short in comp:
		var p := String(PROTO_OF.get(short, ""))
		if p == "":
			continue
		kh += float(comp[short]) * float(_MonsterData.M_HP[p])
		ks += float(comp[short]) / float(_MonsterData.M_SPD[p])
	var hp := {}
	var spd := {}
	for short in comp:
		var p := String(PROTO_OF.get(short, ""))
		if p == "":
			continue
		hp[p] = float(_MonsterData.M_HP[p]) / kh
		spd[p] = float(_MonsterData.M_SPD[p]) * ks
	return {"hp": hp, "spd": spd}


## 三原型只数（按构成取整）。
##   🔴 取整顺序与 `MonsterData.composition` 一致：Tank → Rush → Swarm 兜底，
##      保证 Σ ≡ n（C-2 只数守恒）。
static func composition_counts(n: int, comp: Dictionary) -> Dictionary:
	var tank := int(round(float(comp.get("T", 0.0)) * float(n)))
	var rush := int(round(float(comp.get("R", 0.0)) * float(n)))
	var swarm := n - rush - tank
	if swarm < 0:
		swarm = 0
	return {"Rush": rush, "Swarm": swarm, "Tank": tank}


## 出生序列（按构成比例轮转，纯确定性无 RNG）。
##   轮转顺序固定 `Swarm → Rush → Tank`（与 `MonsterData.spawn_sequence` 同序）：
##   三原型均匀铺开，而不是先来 4 只 Rush 再来 4 只 Swarm。
##   🔴 基准构成直接委托 `MonsterData.spawn_sequence` → 逐位一致。
static func spawn_sequence(n: int, comp: Dictionary) -> Array:
	if absf(float(comp.get("R", 0.0)) - 0.40) < 1e-9 \
		and absf(float(comp.get("S", 0.0)) - 0.40) < 1e-9 \
		and absf(float(comp.get("T", 0.0)) - 0.20) < 1e-9:
		return _MonsterData.spawn_sequence(n)
	var cnt := composition_counts(n, comp)
	var rem := {
		"Rush": int(cnt["Rush"]),
		"Swarm": int(cnt["Swarm"]),
		"Tank": int(cnt["Tank"]),
	}
	var out: Array = []
	out.resize(n)
	var pos := 0
	var guard := 0
	while pos < n and guard < n * 4:
		guard += 1
		for p in _MonsterData.PROTOS:
			if int(rem[p]) > 0 and pos < n:
				out[pos] = p
				pos += 1
				rem[p] = int(rem[p]) - 1
	return out


# ---------------------------------------------------------------------------
#  整合自查（CI 用）
# ---------------------------------------------------------------------------
## 返回错误列表，空 = 通过。
##   V-1 波型串只含 `npsbtEe`                    —— 防拼写漂移
##   V-2 len(pattern) == WAVES[stage] 且 ≤ 20      —— 波表必须闭合
##   V-3 整关总血守恒（|Σ/Σ基准 − 1| < 1e-9）**且**单波偏离 ≤ 25%  —— 守恒律
##   V-4 全场单只 HP ≤ 1.10 × hp(20)               —— 不越过唯一有 MC 支撑的上限
##   V-5 0-1 每一波都 `neutral`                    —— 回归锚点不被污染
static func validate(cfg: Dictionary = {}) -> Array:
	var errs: Array = []
	var c := cfg if not cfg.is_empty() else _MvpConfig.cfg_of()

	for sid in STAGE_ORDER:
		if not PATTERN.has(sid):
			errs.append("V-0 %s 缺波型串" % sid)
			continue
		var pat := String(PATTERN[sid])
		# V-1
		for i in pat.length():
			if not CODES.contains(pat[i]):
				errs.append("V-1 %s W%d 非法波型 '%s'" % [sid, i + 1, pat[i]])
		# V-2
		var want := int(WAVES.get(sid, -1))
		if pat.length() != want:
			errs.append("V-2 %s 波数 %d ≠ 设计 %d" % [sid, pat.length(), want])
		if pat.length() > MAX_WAVE_LIMIT:
			errs.append("V-2 %s 波数 %d 超上限 %d" % [sid, pat.length(), MAX_WAVE_LIMIT])
		# V-3
		if pat.length() > 0 and not is_neutral_stage(sid):
			var k := stage_k(sid, c)
			var tot_base := 0.0
			var tot_act := 0.0
			for i in pat.length():
				var ms := _WaveSim.monster_stats(i + 1, c)
				var base := float(int(ms["n"])) * float(ms["hp"])
				var spec := wave_spec(sid, i + 1, c, 0)
				var act := float(spec["n"]) * float(spec["hp"])
				tot_base += base
				tot_act += act
				if base > 0.0 and absf(act / base - 1.0) > 0.25:
					errs.append("V-3 %s W%d 单波偏离 %.1f%% 超 ±25%%" % [sid, i + 1, (act / base - 1.0) * 100.0])
			if tot_base > 0.0 and absf(tot_act / tot_base - 1.0) > 1e-9:
				errs.append("V-3 %s 整关总血偏离 %.6f%%（k=%.6f）" % [sid, (tot_act / tot_base - 1.0) * 100.0, k])
		# V-4
		var cap := 1.10 * float(_WaveSim.monster_stats(MAX_WAVE_LIMIT, c)["hp"])
		for i in pat.length():
			var sp := wave_spec(sid, i + 1, c, 0)
			if sp.is_empty() or bool(sp.get("neutral", false)):
				continue
			if float(sp["hp"]) > cap:
				errs.append("V-4 %s W%d 单只 HP %.1f > 上限 %.1f" % [sid, i + 1, float(sp["hp"]), cap])

	# V-5：0-1 锚点
	var anchor := "0-1"
	if PATTERN.has(anchor):
		for i in wave_count(anchor):
			var sp := wave_spec(anchor, i + 1, c, 0)
			if not bool(sp.get("neutral", false)):
				errs.append("V-5 %s W%d 非中性（锚点会被污染）" % [anchor, i + 1])
	elif not errs.has("V-0 %s 缺波型串" % anchor):
		errs.append("V-5 缺锚点关卡 %s" % anchor)
	return errs
