extends RefCounted
##
## 切片4 · 商店运行时（**玩家手动路线**）
##
## 🔴 定位：**接线，不是重写**。pity / 扣费 / 执行 / 结算全部复用 `scripts/engine/shop_ai.gd`
##   （金标本 `corebound_sim_v03.py` 的逐位端口），本文件只做四件新事：
##     ① 把「3 商品位 + 锁定 + 刷新次数 + 积分」这套 **UI 侧状态** 落到一处（UI 不持有游戏状态，
##        control-manifest §5）；
##     ② 把 GDD §2.7 的 **三类卡分流** 落到一个 `buy()` 里（建筑卡入待放置队列 /
##        单塔效果卡投主塔 / 全局卡立即生效）；
##     ③ 把 GDD §2.8.2 的 **P1–P4 兜底链** 接到 `pity_card()` 上（**只每波初始商店保底**，
##        手动 reroll 走纯随机）；
##     ④ 🆕 **玩家路线自己的发牌**（D-2 / D-4，v1.3）：金标本 `draw_offers()` 是 **AI 路线**的
##        去重集合发牌（MC 判据链来源，🔴 一字不许改）→ 玩家路线**不再复用它**，改走本文件的
##        `_draw_offers_player()`（6 张池 · 有放回 · 恒 3 位）。
##
## 上游 GDD：`design/gdd/shop-reroll.md` **v1.3**（§2.5 刷新经济 · §2.6 锁定 · §2.7 三类分流 ·
##           §2.8 pity · 🔴 §9.2 拍板留档 D-1~D-7）· `design/gdd/card-system.md`
##           （§4.5 pity · §3.6 5槽=5卡种非5层 · A4 卡池 13→12）
## 下游：`scripts/gameplay/shop_controller.gd`（接线层）· `scripts/ui/shop_overlay.gd`（只读渲染）
##
## 🔴 与金标本的已知分歧（**未擅改口径**；🔴 拍板留档见 `design/gdd/shop-reroll.md` §9.2 v1.3，
##    本文件按 v1.3 落地，金标本 `shop_ai.gd` **零修改**）：
##   D-1 金标本 `shop_phase()` 的**每次**刷新都带 pity；GDD §2.8 定「手动 reroll 不保底」。
##       本文件按 GDD 走（reroll 用 `force = null`），**不动 `shop_phase()`** → MC 判据链不受影响。
##   D-2 金标本 `draw_offers()` 返回**去重集合** → 位数可能 < 3（实测约 4 成波次）；
##       GDD A4 / A4b 定「玩家路线**恒发 3 张**（有放回，可重复，如 3×Cannon）」。
##       ✅ 已落地：本文件**不再复用 `draw_offers()`**，改走 `_draw_offers_player()`；
##       🔴 `draw_offers()` 本身一字未改（AI 路线仍去重）。
##   D-4 金标本 `reroll_disc` 恒为 0（无任何代码路径增加它）→ **RerollD 是空卡**（= G2 供应链）。
##       ✅ 已落地：玩家路线发牌池**排除 RerollD**（实际 6 张），商店**永不发它**；
##       🔴 金标本 `CARD_NAMES` / `WEIGHTS` 不动（AI 路线仍保留 RerollD，MC 不变）。
##
## ⚠️ Godot 坑（沿用 control-manifest §4）
##   G6 headless `--script` 无 `global_script_class_cache` → 本文件**不写 `class_name`**，一律 preload。
##   G1 `int / int` 是整数除法 → 所有期望 float 的除法两侧显式 float()。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")
const _SimPlayer := preload("res://scripts/engine/sim_player.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _FpSum := preload("res://scripts/engine/fp_sum.gd")
const _TD := preload("res://scripts/data/tower_data.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _TSM := preload("res://scripts/engine/time_state_machine.gd")


# ---------------------------------------------------------------------------
#  🆕 玩家路线卡池（D-4 / D-2 · 拍板留档 `shop-reroll` §9.2 v1.3）
# ---------------------------------------------------------------------------
## 🔴 D-4：RerollD（= G2 供应链 `SupplyChain`）在金标本里 `reroll_disc` **无任何增加路径**
##   → 买后 +0%，扣 10 分零收益是**纯负体验**（违反 P4）→ **玩家路线发牌池排除它**。
##   🔴 金标本 `ShopAI.CARD_NAMES` / `WEIGHTS` **一字不动**（AI 路线仍 7 张含 RerollD，MC 不变）；
##      玩家池是金标本卡池的**派生**（去掉 RerollD 后的 6 张），不在本层二次定义
##      （control-manifest §5：数值只在 `scripts/data/` 与金标本里定义一次）。
const PLAYER_EXCLUDED_CARDS: Array = ["RerollD"]

static var _pool_names: Array = []
static var _pool_weights: Array = []
static var _pool_total := 0.0


## 玩家路线卡池（6 张）：`Arrow / Cannon / Frost / FireUp / FrostUp / ScrapUp`
static func player_card_names() -> Array:
	_build_player_pool()
	return _pool_names


## 玩家路线权重（取 `ShopAI.WEIGHTS` 对应项，排除 RerollD 的 0.095）
static func player_card_weights() -> Array:
	_build_player_pool()
	return _pool_weights


## 玩家池权重之和（= 1 − 0.095 = 0.905）：`PyRandom.choices()` 用它归一（control-manifest P3）。
## 🔴 N2：float 序列求和走 `FpSum.sum_py()`（control-manifest §2）。
static func player_pool_total() -> float:
	_build_player_pool()
	return _pool_total


static func _build_player_pool() -> void:
	if not _pool_names.is_empty():
		return
	for nm in _ShopAI.CARD_NAMES:
		var s := String(nm)
		if PLAYER_EXCLUDED_CARDS.has(s):
			continue                          # 🔴 D-4：RerollD 不进玩家池
		_pool_names.append(s)
		_pool_weights.append(float(_ShopAI.WEIGHTS[s]))
	_pool_total = _FpSum.sum_py(_pool_weights)


# ---- 运行时状态（🔴 唯一持有处；UI 只读 `snapshot()`）----
var cfg: Dictionary = {}
var geo = null
var player = null
var rng = null
## 🟡 切片8：时钟权威（TimeDirector）引用，仅供重决策入口（salvage/discard/unequip）
##   做 **SafeWindow 守卫**（T-C1 / E16：战斗内禁止塔操作）。headless 单测可不绑定（放行）。
var director: Node = null

var path: String = "B"
var wave: int = 0
var scrap: float = 0.0          # 积分（🔴 M5：仅击杀获得；商店不产出、不回收）
var core_hp: float = 0.0
var core_hp_max: float = 0.0

var rerolls: int = 0            # n：本波已刷新次数（每波重置）
var lock_index: int = -1        # 锁定的商品位（-1 = 无；3 位中可锁 1，每波重置）
var offers: Array = []          # Array[String]，长度恒 = MvpConfig.SHOP_SLOTS（D-2：有放回抽 3，可重复）
var pending: Array = []         # 待放置队列 Array[String]（建筑卡；Q-SR5 跨波保留，无上限）
## 🟡 切片8 · 与 `pending` **平行**的待放置成本数组（拆除回收 `Salvage` 逐塔投入追踪前提）：
##   建筑卡买时入 `pending`（未落塔、未记投入），成本先记在这里；`confirm_placement`
##   落子时把对应成本累加到**具体塔**的 `invested`。与 `pending` 同下标、同增删节奏。
var pending_cost: Array = []    # Array[float]，建筑卡买入时锁定的实付分
var counts: Dictionary = {}     # 卡名 → 本波已买次数（`action_cost` 的 wave_price_step 用）

var last_error: String = ""

var _placing_index: int = -1    # 正在放置的待放置队列下标（-1 = 不在放置中）


# ---------------------------------------------------------------------------
#  开局
# ---------------------------------------------------------------------------
func setup(p_path: String, seed_value: int, overrides: Dictionary = {}) -> void:
	path = p_path
	cfg = _Cfg.cfg_of(p_path)
	for k in overrides:
		cfg[k] = overrides[k]
	geo = _Geo6.build() if int(cfg["n_slots"]) >= 6 else _Geo6.build4()
	player = _SimPlayer.new_player(p_path, cfg, geo)
	rng = _PyRandom.new(seed_value)
	wave = 0
	scrap = 0.0
	core_hp_max = float(cfg["core_hp"])
	core_hp = core_hp_max
	rerolls = 0
	lock_index = -1
	offers = []
	pending = []
	pending_cost = []
	counts = {}
	_placing_index = -1
	last_error = ""


# ---------------------------------------------------------------------------
#  I-1 波次开始：n ← 0 / 锁定清空 / 发初始商店（🔴 走 pity）
#      （减速预算 `budget ← 20` 在 `TimeStateMachine.wave_start()` 里，不归本文件）
# ---------------------------------------------------------------------------
func start_wave(w: int) -> void:
	wave = w
	rerolls = 0
	lock_index = -1                 # Q-SR4：锁定每波重置
	counts = {}
	_placing_index = -1
	last_error = ""
	offers = deal_initial_shop()


## 🔴 玩家路线**自己的发牌**（D-2 / D-4 · `shop-reroll` §9.2 v1.3 · GDD §2.8.3 伪代码
##   `_draw_random_offers(count)` 的语义）：
##     · 池 = `player_card_names()`（6 张，已排除 RerollD）；
##     · 🔴 **有放回**抽 k 张 = k 个**独立**加权抽样 → **允许重复**（如 3×Cannon），恒返回 k 个卡名；
##     · RNG 走 `_PyRandom.choices()`（control-manifest P1–P3：累积权重 + `bisect_right(cum, u, 0, n-1)`，
##       与 Python `random.choices` 逐位同）。
## 🔴 **不复用**金标本 `ShopAI.draw_offers()` —— 那是 **AI 路线**的去重集合发牌（MC 判据链来源，
##    改一字要重跑 MC）。玩家路线与 AI 路线的发牌分歧**全部收敛在本文件**。
func _draw_offers_player(k: int) -> Array:
	var picks = rng.choices(player_card_names(), player_card_weights(), k)
	var out: Array = []
	for nm in picks:
		out.append(String(nm))
	return out


## GDD §2.8.3 `_apply_pity()`：把保底卡写进商店（🔴 不新增第 4 个位 · 🔴 不覆盖锁定位）。
##   · 3 张里已含 force → **不干预**；
##   · 否则改写 **1 个未锁定**的商品位（`rng.choice` = Python `pick_random` 的 PyRandom 等价物）；
##   · 全部位都被锁定 → 不干预（E15 / SR-R4）。
func _apply_pity(shop: Array, force) -> void:
	if force == null:
		return
	var f := String(force)
	if f == "":
		return
	for nm in shop:
		if String(nm) == f:
			return                                  # 已含 ≥1 张 force → 不干预
	var unlocked: Array = []
	for i in shop.size():
		if i != lock_index:                         # 🔴 SR-R4：锁定位不得被改写
			unlocked.append(i)
	if unlocked.is_empty():
		return
	shop[int(rng.choice(unlocked))] = f


## GDD §2.8.3 `deal_initial_shop()` —— 纯随机 3 张 → 再按 `_apply_pity` 写 force（P1–P4）。
func deal_initial_shop() -> Array:
	var force = pity_force()
	var out := _draw_offers_player(int(cfg["shop_offers"]))
	_apply_pity(out, force)
	return out


## P1–P4 兜底链的**入口**：直接复用金标本 `pity_card()`。
##   · P4（场上无塔）→ `pity_card()` 返回 null（金标本 `if towers.is_empty(): return null`）；
##   · P1（主塔原型有 Tag）→ 返回该 Tag 的单塔效果卡；
##   · P3（主塔无 Tag 且全场 Tag 投入 0）→ 主塔 tag 为 "" → 返回 null；
##   · 🟡 P2（主塔无 Tag 但全场有 Tag 投入 → 出 argmax_Tag 的卡）**金标本未实现**，
##     本文件照金标本走（= P2 与 P3 合并为"不保底"），未擅自补逻辑（补了会改 MC）。
func pity_force():
	if not bool(cfg.get("pity", false)):
		return null
	return _ShopAI.pity_card(player)


## 本波 pity 会保底哪张卡（HUD / 自测显示用；"" = 本波不保底）。
func pity_card_name() -> String:
	var f = pity_force()
	return "" if f == null else String(f)


# ---------------------------------------------------------------------------
#  §2.5 刷新：Cost(n) = max(1, 5 + 3n − discount)
# ---------------------------------------------------------------------------
## 🔴 复用 `shop_phase()` 里 S6 的同一条表达式（金标本口径）：
##   `rc = max(1.0, reroll_base + reroll_growth*rerolls − reroll_disc)`
##   🟡 与 GDD §2.5 的 `max(1, floor((5+3n)×(1−discount)))` 在 discount > 0 时不同
##      （减法 vs 乘法折扣）。discount = 0 时二者逐位相同 → 待主理人拍板，见 verify §5。
func reroll_cost() -> float:
	return maxf(float(_Cfg.MIN_REROLL_COST),
		float(cfg["reroll_base"]) + float(cfg["reroll_growth"]) * float(rerolls)
		- float(player.reroll_disc))


## 手动 reroll：扣费 → n+1 → 🔴 **纯随机不保底**（GDD §2.8.1）；锁定位保留在原位。
func reroll() -> bool:
	var cost := reroll_cost()
	if cost > scrap:
		last_error = "刷新需要 %.0f 分，当前 %.0f 分" % [cost, scrap]
		return false
	var kept := ""
	if lock_index >= 0 and lock_index < offers.size():
		kept = String(offers[lock_index])
	# 🔴 无 force（D-1：手动 reroll 纯随机不保底）+ 玩家路线自己的发牌（D-2 有放回 · D-4 无 RerollD）
	var fresh := _draw_offers_player(int(cfg["shop_offers"]))
	scrap -= cost
	rerolls += 1
	offers = _merge_with_lock(lock_index, kept, fresh, offers.size())
	last_error = ""
	return true


## 锁定位**原样保留**，其余位用新抽的卡填（🔴 锁定位不参与刷新，GDD §2.6）。
## 位数保持 ≤ SHOP_SLOTS；新抽的牌不够填时，多余位留空（不凭空造卡）。
static func _merge_with_lock(kept_index: int, kept_card: String, fresh: Array, n: int) -> Array:
	var out: Array = []
	out.resize(n)
	for i in range(n):
		out[i] = ""
	if kept_index >= 0 and kept_index < n and kept_card != "":
		out[kept_index] = kept_card
	var q: Array = []
	for nm in fresh:
		if String(nm) != kept_card:
			q.append(String(nm))
	var qi := 0
	for i in range(n):
		if i == kept_index:
			continue
		if qi < q.size():
			out[i] = String(q[qi])
			qi += 1
	return out


# ---------------------------------------------------------------------------
#  §2.6 锁定：3 商品位中可锁 1（MAX_LOCK）；每波重置；锁定永远作用于**单个**位
# ---------------------------------------------------------------------------
## 🟡 次级口径（GDD 未定义"已锁 A 位时再按 Space 锁 B 位"）：**改锁 B 位**（旧位自动解锁）。
##    理由：MAX_LOCK=1 约束的是"同时最多 1 张"，改锁比"必须先解锁"少一次输入（P4）。
func toggle_lock(slot: int) -> bool:
	if slot < 0 or slot >= offers.size():
		last_error = "商品位 %d 不存在" % slot
		return false
	if lock_index == slot:
		lock_index = -1
		return true
	lock_index = slot
	return true


# ---------------------------------------------------------------------------
#  §2.7 三类卡购买后分流
# ---------------------------------------------------------------------------
func offer_at(slot: int) -> String:
	if slot < 0 or slot >= offers.size():
		return ""
	return String(offers[slot])


func card_kind(slot: int) -> String:
	return _ShopAI.card_kind(offer_at(slot))


## 卡种 → GDD §2.7 的三类中文名（建筑卡 / 单塔效果卡 / 全局效果卡）
func kind_label(slot: int) -> String:
	match card_kind(slot):
		"tower":
			return "建筑卡"
		"reinforce":
			return "单塔效果卡"
		"econ":
			return "全局效果卡"
	return ""


## 价格：走 `ShopAI.action_cost()`（= PRICE[kind] + wave_price_step × 本波已买次数）。
##   PRICE：建筑卡 12 / 单塔效果卡 9 / 全局效果卡 10（= `_Cfg.PRICE_*`，GDD §3.1 A1）
func price_at(slot: int) -> float:
	var nm := offer_at(slot)
	if nm == "":
		return 0.0
	var act := _action_for(nm)
	if act.is_empty():
		return 0.0
	return _ShopAI.action_cost(act, cfg, counts)


## 三类卡各自**将要执行**的金标本动作（供 `action_cost` / `apply_action` 复用）
func _action_for(nm: String) -> Array:
	if nm == "":
		return []
	var kind := _ShopAI.card_kind(nm)
	match kind:
		"tower":
			# 建筑卡：买的时候**不落塔**（买/放解耦），落子走 `confirm_placement()`
			return ["build", nm, null, null]
		"reinforce":
			var host := core_tower_slot()
			if host < 0:
				return []
			if player.cards.has(nm):
				return ["reinf", nm, host, null]            # 同卡再买 = 层数 +1（不占新槽）
			if player.cards.size() < int(cfg["backpack"]):
				return ["reinf_new", nm, host, null]        # 新占 1 个强化槽（计"卡种"）
			var drop = _ShopAI.weakest_card(player, cfg, geo)
			if drop == null or String(drop) == nm:
				return []
			return ["reinf_swap", nm, host, String(drop)]
		"econ":
			return ["econ", nm, null, null]
	return []


## 主塔 `CoreTower`：🔴 与 `ShopAI.pity_card()` 的 S2 同一判据（max(Σattach, h)，并列取靠前）。
##   这里**不改** `pity_card()`，只按同样口径另取一次，自测里断言二者指向同一座塔（§1）。
func core_tower_slot() -> int:
	if player.towers.is_empty():
		return -1
	var top = -1
	var top_l := -1.0
	var top_h := -1.0
	for t in player.towers:
		var li := _SimPlayer.layers_of(t)
		var hi := float(t.h)
		if top < 0 or li > top_l or (li == top_l and hi > top_h):
			top = int(t.slot)
			top_l = li
			top_h = hi
	return top


## H8「无合法目标」的判定（E1 建筑卡 / E9 单塔效果卡）；全局卡恒 true。
func legal_at(slot: int) -> bool:
	return legal_note(slot) == ""


func legal_note(slot: int) -> String:
	var nm := offer_at(slot)
	if nm == "":
		return "此位无卡"
	match _ShopAI.card_kind(nm):
		"tower":
			# E1：塔位已满且场上无同原型塔 → 无合法目标（H8 置灰）
			for t in player.towers:
				if String(t.ctype) == nm:
					return ""                                  # 同原型 → 升级（合法）
			var mt = cfg.get("max_towers")
			if mt == null:
				mt = {"A": 2, "B": int(cfg["n_slots"])}       # 同 `enumerate_actions()` 的口径
			if player.towers.size() >= int(mt[path]):
				return "塔位已满"
			if not _ShopAI.free_map_slots(player, cfg).is_empty():
				return ""                                      # 有空位 → 新建（合法）
			return "无可放置目标"
		"reinforce":
			if player.towers.is_empty():
				return "需先建造一座塔"                     # E9
			var host := core_tower_slot()
			if host < 0:
				return "需先建造一座塔"
			var ctag := ""
			for t in player.towers:
				if int(t.slot) == host:
					ctag = _TD.tower_tag(String(t.ctype))
			# D-8①：禁止异 Tag 装配；🔴 中性塔（tag == ""）可接收任意 Tag 卡
			if ctag != "" and ctag != _TD.reinf_tag(nm):
				return "主塔不接收该 Tag"                   # 🟡 点选副塔 = 2 次输入，后续切片
			return ""
		"econ":
			return ""
	return "此位无卡"


## H1 买得起（`scrap >= price`）且 H8 有合法目标。
func can_buy(slot: int) -> bool:
	var nm := offer_at(slot)
	if nm == "":
		return false
	if not legal_at(slot):
		return false
	return scrap >= price_at(slot)


## 购买：扣费 → 按 GDD §2.7 三类分流。返回是否成功。
func buy(slot: int) -> bool:
	var nm := offer_at(slot)
	if nm == "":
		last_error = "商品位 %d 无卡" % slot
		return false
	if not legal_at(slot):
		last_error = "无合法目标：%s" % legal_note(slot)
		return false
	var cost := price_at(slot)
	if scrap < cost:
		last_error = "买不起：需要 %.0f 分，当前 %.0f 分" % [cost, scrap]
		return false

	match _ShopAI.card_kind(nm):
		"tower":
			# ① 建筑卡 → **入待放置队列**（买 / 放解耦，GDD §2.7；不占塔位、不占强化槽）
			#    🟡 切片8：同时锁定**本次实付分**到平行数组 `pending_cost`（落子时才计入塔 invested）
			pending.append(nm)
			pending_cost.append(cost)
		"reinforce":
			# ② 单塔效果卡 → 投主塔（`apply_action` 内部处理 层数+1 / 新占槽 / 换掉最弱卡）
			var act := _action_for(nm)
			if act.is_empty() or _ShopAI.apply_action(player, act, cfg) == null:
				last_error = "装配失败：%s" % nm
				return false
			#    🟡 切片8：装配卡成本直接计入**宿主塔** invested（返还 50% 累计投入的来源之一）
			_add_invested(int(act[2]), cost)
		"econ":
			# ③ 全局效果卡 → 立即生效
			#    ScrapUp：`income_mult += 0.20`（金标本 `apply_action` 的 econ 分支）
			#    RerollD：🟡 **已在 D-4（v1.3）从玩家路线卡池移除**，玩家商店**永不发它**
			#      （金标本 `reroll_disc` 无任何增加路径 → 买后 +0%，是纯负体验）。
			#      → 本分支**不需要**为它写任何执行逻辑；全局卡现在实际只剩 ScrapUp 一种。
			if nm == "ScrapUp" and float(player.income_mult) < 1.0:
				_ShopAI.apply_action(player, ["econ", nm, null, null], cfg)
	scrap -= cost
	counts[nm] = int(counts.get(nm, 0)) + 1
	last_error = ""
	return true


## H4：买下后**实际收益为 0** 的卡（全局卡饱和）→ 卡面标「已达上限 (+0%)」。
##   （🟡 原 RerollD 也走这条分支；D-4（v1.3）已把它从玩家路线卡池移除 → 玩家商店不再发它，
##    本函数保留给 ScrapUp 的 `income_mult` 饱和判定。）
## 🔴 仍可购买（GDD E7 / H4：保底是"买得到"不是"有收益"），且**不新增第三种植灰理由**（X6）。
func at_cap(slot: int) -> bool:
	var nm := offer_at(slot)
	if _ShopAI.card_kind(nm) != "econ":
		return false
	return not (nm == "ScrapUp" and float(player.income_mult) < 1.0)


# ---------------------------------------------------------------------------
#  I-8 放置（建筑卡落子）—— CD-D：`New` / `Upgrade` / `Invalid`
# ---------------------------------------------------------------------------
func begin_placement(pending_index: int) -> bool:
	if pending_index < 0 or pending_index >= pending.size():
		last_error = "待放置队列无此下标"
		return false
	_placing_index = pending_index
	return true


func cancel_placement() -> void:
	# 🔴 取消**不退款**（GDD §2.1 / Q-S3-A 同口径）；卡留在队列里
	_placing_index = -1


## 落子：空塔位 = 新建（build）· 同原型 = 升级（up）· 其余 = Invalid（不落子、不退卡）
func placement_mode_for(slot: int) -> String:
	if _placing_index < 0 or _placing_index >= pending.size():
		return "invalid"
	var nm := String(pending[_placing_index])
	for t in player.towers:
		if int(t.slot) == slot:
			return "upgrade" if String(t.ctype) == nm else "invalid"
	return "new"


func confirm_placement(slot: int) -> bool:
	if _placing_index < 0 or _placing_index >= pending.size():
		last_error = "当前没有正在放置的卡"
		return false
	var nm := String(pending[_placing_index])
	var mode := placement_mode_for(slot)
	if mode == "invalid":
		last_error = "非法目标：%s 不能落在塔位 %d" % [nm, slot]
		return false
	var act := ["build", nm, slot, null] if mode == "new" else ["up", nm, slot, null]
	if _ShopAI.apply_action(player, act, cfg) == null:
		last_error = "落子失败：%s → 塔位 %d" % [nm, slot]
		return false
	# 🟡 切片8：建筑卡成本（build/upgrade 同价）计入**这座塔**的 invested（拆除返还 50% 依据）
	var paid := 0.0
	if _placing_index < pending_cost.size():
		paid = float(pending_cost[_placing_index])
	_add_invested(int(slot), paid)
	pending.remove_at(_placing_index)
	pending_cost.remove_at(_placing_index)
	_placing_index = -1
	last_error = ""
	return true


# ---------------------------------------------------------------------------
#  切片8 · 拆除回收 `Salvage` / 弃卡 `discard` / 卸下改投 `unequip`
#  （card-system §4.3 / §7.2.2 / E8 / Q-C3 原文，一字不改）
# ---------------------------------------------------------------------------
## 🔴 三条红线（本区块全部遵守）：
##   ① Q-C3 原文：返还 **50% 累计投入**（向下取整）· 装配卡**全销毁** · **二次确认** · 仅**安全窗**；
##   ② T-R1 反通胀：返还系数 = 50% ≤ 100%，且不存在「买入折扣 × 移除返还」组合（本游戏无买入折扣 → 安全）；
##   ③ T-C1 / E16：战斗内**禁止任何塔相关操作** → 本区块三个方法**入口即校验**当前必须 SafeWindow，
##      否则直接拒绝（战斗中入口在 UI 层置灰，本层再兜底一次，防绕过 UI 直接调）。
##
## 🔴 金标本零改动：`invested` 只在**玩家路线**（本文件）记录；`shop_ai.gd apply_action`
##    不读不写它。κ 口径不动（兜底①：`N_tower_histmax` 只增不减 → 拆塔**不回升** κ，E11）。

## 逐塔累计投入累加器：找不到该塔位则忽略（防御；正常路径塔已由 build/reinf 建好）。
func _add_invested(slot: int, amount: float) -> void:
	for t in player.towers:
		if int(t.slot) == slot:
			t.invested = float(t.invested) + amount
			return


## 🔴 只读预览：给 I-9 二次确认弹窗组装文案用（**不改动任何状态**）。
##   返回 {ok, reason, refund, cards_destroyed, layers_destroyed, invested}。
##   与 `salvage_tower()` 同判据，但纯读 → UI 可先预览再让玩家确认。
func preview_salvage(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "refund": 0.0, "cards_destroyed": 0, "layers_destroyed": 0, "invested": 0.0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可拆除（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	var invested := floorf(float(t.invested))
	var n_cards := 0
	var n_layers := 0
	for cname in _keys(t.attach):
		n_cards += 1
		n_layers += int(t.attach[cname])
	result["ok"] = true
	result["refund"] = floorf(invested * 0.5)
	result["cards_destroyed"] = n_cards
	result["layers_destroyed"] = n_layers
	result["invested"] = invested
	return result


## 塔位上**装配卡总层数**（弃卡/卸下判据用；salvage 时用于弹窗披露销毁规模）。
func tower_attach_layers(slot: int) -> int:
	for t in player.towers:
		if int(t.slot) == slot:
			var n := 0
			for _k in t.attach:
				n += int(t.attach[_k])
			return n
	return 0


## 拆除回收 `Salvage(tower)` —— Q-C3 定稿（主动移除，✅ MVP）：
##   · 返还 **50% 累计投入**（`invested`，向下取整）到 `scrap`；
##   · 该塔装配的**全部单塔效果卡及层数销毁**（`attach` 清空，卡从 `player.cards` 移除）；
##   · **塔位释放**（从 `player.towers` 删除）；
##   · 🔴 **κ 不回升**（兜底①：`n_hist_max` 只增不减，E11）→ 本方法**不动** `n_hist_max`；
##   · 返回结算字典（供 UI 二次确认弹窗披露「返还 X 分 / 销毁 N 张（M 层）」；E8 确认项）。
## 🔴 仅 SafeWindow 可操作（T-C1 / E16）；非安全窗直接拒绝。
func salvage_tower(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "refund": 0.0, "cards_destroyed": 0, "layers_destroyed": 0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可拆除（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	var invested := floorf(float(t.invested))
	# ① 装配卡全销毁：从 player.cards 移除该塔持有的所有卡（含层数）
	var n_cards := 0
	var n_layers := 0
	for cname in _keys(t.attach):
		var layers := int(t.attach[cname])
		n_cards += 1
		n_layers += layers
		player.cards.erase(cname)
	t.attach = {}
	# ② 塔位释放
	player.towers.remove_at(idx)
	# ③ 返还 50% 累计投入（向下取整）
	var refund := floorf(invested * 0.5)
	scrap += refund
	result["ok"] = true
	result["refund"] = refund
	result["cards_destroyed"] = n_cards
	result["layers_destroyed"] = n_layers
	result["invested"] = invested
	last_error = ""
	return result


## 弃卡 `discard_card(card_name)` —— 弃掉整张单塔效果卡（腾槽，§4.3）：
##   该卡及其**全部层数**从**所有塔**上销毁，槽位释放（`player.cards` 移除）。
##   🔴 不可回收（无返还）；仅 SafeWindow。
##   🟡 MVP 说明：本方法销毁该卡在**全部宿主塔**上的层数（卡名全局唯一归属，
##      与 `drop_from` 同口径）；「换宿主塔」的卸下改投见 `unequip_downgrade`。
func discard_card(card_name: String) -> Dictionary:
	var result := {"ok": false, "reason": "", "layers_destroyed": 0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可弃卡（§4.3）"
		return result
	var nm := String(card_name)
	if nm == "" or not player.cards.has(nm):
		result["reason"] = "未持有该卡：%s" % nm
		return result
	var n_layers := 0
	for t in player.towers:
		if t.attach.has(nm):
			n_layers += int(t.attach[nm])
			t.attach.erase(nm)
	player.cards.erase(nm)
	result["ok"] = true
	result["layers_destroyed"] = n_layers
	last_error = ""
	return result


## 卸下改投 `unequip_downgrade(card_name)` —— 卸下**降 1 层**（§4.3 / Q8 / §2.4.2 已定）：
##   该卡在**主塔**（或指定 slot 的塔）上**降 1 层**；降到 0 层则整卡销毁、槽位释放。
##   🔴 不返还（卸下是「改投」不是「售卖」，层数损失即代价）；仅 SafeWindow。
func unequip_downgrade(card_name: String, slot: int = -1) -> Dictionary:
	var result := {"ok": false, "reason": "", "remaining": 0, "destroyed": false}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可卸下（§4.3）"
		return result
	var nm := String(card_name)
	if nm == "":
		result["reason"] = "未指定卡名"
		return result
	# 目标塔：指定 slot 优先；否则主塔
	var target_slot := slot
	if target_slot < 0:
		target_slot = core_tower_slot()
	if target_slot < 0:
		result["reason"] = "无宿主塔"
		return result
	for t in player.towers:
		if int(t.slot) == target_slot and t.attach.has(nm):
			var layers := int(t.attach[nm]) - 1
			if layers <= 0:
				t.attach.erase(nm)
				player.cards.erase(nm)
				result["destroyed"] = true
				result["remaining"] = 0
			else:
				t.attach[nm] = layers
				result["remaining"] = layers
			result["ok"] = true
			last_error = ""
			return result
	result["reason"] = "该塔未持有 %s" % nm
	return result


## 塔位在 `player.towers` 中的下标（找不到 −1）。
func _tower_index(slot: int) -> int:
	for i in range(player.towers.size()):
		if int(player.towers[i].slot) == slot:
			return i
	return -1


## 🔴 T-C1 / E16：本层重决策入口的统一安全窗守卫。
##   `director` 为 null（headless 单测直接调 runtime）时**放行**（由调用方/单测保证时机）；
##   有 director 时读其状态机，非 SafeWindow 一律拒绝。
func _in_safe_window() -> bool:
	if director == null:
		return true
	return int(director.sm.state) == _TSM.State.SAFE_WINDOW


# ---------------------------------------------------------------------------
#  波次结算（最小波次驱动器用；🔴 收入只来自击杀，M5）
# ---------------------------------------------------------------------------
## R1：本波打的是**上波买出来的构筑** → 在 `wave_start` 时用战前 DPS 结算一次并存起来。
func simulate_wave_result(w: int) -> Dictionary:
	return _WaveSim.simulate_wave(player, w, cfg, geo)


## R3：收入 = 本波击杀废铁 × (1 + income_mult)；漏怪扣核心 HP。
func grant_wave_result(res: Dictionary) -> void:
	scrap += float(res["scrap_earned"]) * (1.0 + float(player.income_mult))
	core_hp = maxf(0.0, core_hp - float(res["core_damage"]))


# ---------------------------------------------------------------------------
#  只读快照（UI / HUD / 自测一律读这个，不得直接改状态）
# ---------------------------------------------------------------------------
func snapshot() -> Dictionary:
	var names: Array = []
	var prices: Array = []
	var affordable: Array = []
	var legal: Array = []
	var notes: Array = []
	var kinds: Array = []
	var caps: Array = []
	for i in range(offers.size()):
		var nm := offer_at(i)
		names.append(nm)
		kinds.append(kind_label(i))
		prices.append(price_at(i))
		affordable.append(scrap >= price_at(i))
		legal.append(legal_at(i))
		notes.append(legal_note(i))
		caps.append(at_cap(i))
	while names.size() < _Cfg.SHOP_SLOTS:
		names.append("")
		kinds.append("")
		prices.append(0.0)
		affordable.append(false)
		legal.append(false)
		notes.append("此位无卡")
		caps.append(false)
	# ---- 塔位事实（H7 槽位占用 / I-8 放置模式高亮：New = 绿 / Upgrade = 金）----
	var slots: Array = []
	var place_modes: Array = []
	var by_slot := {}
	for t in player.towers:
		by_slot[int(t.slot)] = t
	for i in range(int(cfg["n_slots"])):
		if by_slot.has(i):
			var t2 = by_slot[i]
			slots.append({"slot": i, "ctype": String(t2.ctype), "h": int(t2.h), "empty": false})
		else:
			slots.append({"slot": i, "ctype": "", "h": 0, "empty": true})
		place_modes.append(placement_mode_for(i) if _placing_index >= 0 else "")

	return {
		"wave": wave,
		"scrap": scrap,
		"core_hp": core_hp,
		"core_hp_max": core_hp_max,
		"rerolls": rerolls,
		"reroll_cost": reroll_cost(),
		"lock_index": lock_index,
		"offers": names,
		"kinds": kinds,
		"prices": prices,
		"affordable": affordable,
		"legal": legal,
		"notes": notes,
		"at_cap": caps,
		"offer_count": offers.size(),
		"pending": pending.duplicate(),
		"placing_index": _placing_index,
		"pity_card": pity_card_name(),
		"cards": player.cards.size(),
		"cards_max": int(cfg["backpack"]),
		"towers": player.towers.size(),
		"towers_max": int(cfg["n_slots"]),
		"income_mult": float(player.income_mult),
		"reroll_disc": float(player.reroll_disc),
		"core_tower_slot": core_tower_slot(),
		"slots": slots,
		"place_modes": place_modes,
		"build": _SimPlayer.build_str(player),
		"last_error": last_error,
	}


# ---------------------------------------------------------------------------
#  工具
# ---------------------------------------------------------------------------
static func _keys(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append(String(k))
	return out
