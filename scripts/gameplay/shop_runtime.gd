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
const _DE := preload("res://scripts/engine/damage_engine.gd")
const _TD := preload("res://scripts/data/tower_data.gd")
## 🆕 卡包表（数据层）：本局卡池 = 所选卡包的并集（见文件下半「卡包模式」）
const _Packs := preload("res://scripts/data/card_packs.gd")
const _WaveSim := preload("res://scripts/engine/wave_sim.gd")
const _Geo6 := preload("res://scripts/geo/geo6.gd")
const _Geo := preload("res://scripts/geo/geo.gd")
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
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

## 🆕 扩展包卡序（显式数组 → 抽卡池顺序确定、可测；不用 Dictionary 遍历顺序）。
##   与 `TowerData.EXT_WEIGHTS` 的键集合必须一一对应（自测断言）。
const EXT_CARD_ORDER: Array = ["Lance", "Tesla", "PirUp", "ShkUp", "Sunder", "Hex", "SunUp", "HexUp", "Oblivion", "TrueUp"]

## 🆕 扩展包开关。🔴 默认 `false` = 产品未启用口径 ⇒ 玩家池仍是 6 张，
##    与改动前逐位一致；`true` 时玩家池 = 6 + 4 = 10 张（AI 池恒不变）。
static var extended_pack: bool = false

## 🆕 卡包模式（2026-11-07）· 本局所选卡包 id 列表。
##   · **空 = 未启用卡包模式** ⇒ `_build_player_pool()` 走老口径（6 张 / 扩展包 10 张），
##     与改动前**逐位一致**（headless 自测 / 金标本 / MC 都不经过这里）。
##   · 非空 ⇒ 玩家池 = 所选卡包的并集（每包 2 张，选 3 包 = 6 张，见 `card_packs.gd`）。
##   🔴 静态量：跨"再来一局"保持同一套包；换包必须重新 `set_active_packs()`。
static var active_packs: Array = []

static var _pool_names: Array = []
static var _pool_weights: Array = []
static var _pool_total := 0.0


## 🆕 设定本局卡包。传空数组 = 退回老口径。
##   🔴 必须清缓存：`_build_player_pool()` 开头的 `if not _pool_names.is_empty(): return`
##      会让"换包"静默失效（与 `set_extended_pack()` 同一个坑）。
static func set_active_packs(ids: Array) -> void:
	var norm: Array = []
	for nm in ids:
		var s := String(nm)
		if s == "" or norm.has(s):
			continue
		if not _Packs.has_pack(s):
			continue                       # 未知包 id 直接丢弃（不让它进池）
		norm.append(s)
	if norm == active_packs:
		return
	# 🔴 池序只由包序决定（不随"玩家点选顺序"漂）：同一套包必须抽出同一序列。
	active_packs = _Packs.sort_by_pack_order(norm)
	_invalidate_player_pool()


static func active_pack_ids() -> Array:
	return active_packs.duplicate()


static func _invalidate_player_pool() -> void:
	_pool_names.clear()
	_pool_weights.clear()
	_pool_total = 0.0


## 🆕 切换扩展包。🔴 必须清静态缓存，否则 `_build_player_pool()` 的
##   `if not _pool_names.is_empty(): return` 会让切换静默失效。
static func set_extended_pack(on: bool) -> void:
	if extended_pack == on:
		return
	extended_pack = on
	_invalidate_player_pool()


## 🔴 扩展包兼容层：卡种判定**先查扩展表，再回落金标本** `ShopAI.card_kind()`。
##    ⚠️ 刻意**不修改** `shop_ai.gd`（金标本镜像文件）：
##      默认 7 张卡走末尾分支，结果与改动前逐位一致；扩展卡只影响玩家路线。
##    ⚠️ 必须包这一层，否则 `Lance` / `Tesla` 会被金标本判成 `"econ"`
##      （`card_kind` 只认 `TOWERS` / `REINF`）→ 买建筑卡走成全局卡分支：扣钱、不落塔。
static func _card_kind(nm: String) -> String:
	if _TD.TOWERS_EXT.has(nm):
		return "tower"
	if _TD.REINF_EXT.has(nm):
		return "reinforce"
	if _TD.REINF_EXT2.has(nm):
		return "reinforce"
	return _ShopAI.card_kind(nm)


## 玩家路线卡池（6 张）：`Arrow / Cannon / Frost / FireUp / FrostUp / ScrapUp`
static func player_card_names() -> Array:
	_build_player_pool()
	return _pool_names


## 玩家路线权重（取 `ShopAI.WEIGHTS` 对应项，排除 RerollD 的 0.095）
static func player_card_weights() -> Array:
	_build_player_pool()
	return _pool_weights


## 🆕 商店槽位数（card-packs v0.2）：卡包模式仍恒 3 位（614px 抽屉放不下第 4 位）。
##   🔴 槽位扩容已否决（见 card-packs.md §对冲）：改用「刷新保底」对冲 18 张池稀释，
##      商品位恒 3，UI 零改动，`cfg["shop_offers"]`（=3）与改动前逐位一致。
static func shop_slot_count() -> int:
	return 3


## 玩家池权重之和：`PyRandom.choices()` 用它归一（control-manifest P3）。
##   · 扩展包关：= 1 − 0.095 = **0.905**（6 张，与改动前一致）
##   · 扩展包开：= 0.905 + Σ`EXT_WEIGHTS` = **1.245**（10 张）
## 🔴 N2：float 序列求和走 `FpSum.sum_py()`（control-manifest §2）。
static func player_pool_total() -> float:
	_build_player_pool()
	return _pool_total


static func _build_player_pool() -> void:
	if not _pool_names.is_empty():
		return
	# 🆕 卡包模式（优先级最高）：卡池 = 所选卡包并集，顺序 = 包序 → 包内序。
	#   🔴 走这条分支时**不再看** `extended_pack` —— 卡包表本身已经覆盖全部 10 张卡，
	#      两个开关同时开会变成"同一张卡进池两次"（PyRandom 的累积区间被重复占用）。
	if not active_packs.is_empty():
		for pid in active_packs:
			for nm in _Packs.cards_of(String(pid)):
				var s := String(nm)
				if _pool_names.has(s):
					continue
				_pool_names.append(s)
				_pool_weights.append(_Packs.card_weight(s))
		_pool_total = _FpSum.sum_py(_pool_weights)
		return
	for nm in _ShopAI.CARD_NAMES:
		var s := String(nm)
		if PLAYER_EXCLUDED_CARDS.has(s):
			continue                          # 🔴 D-4：RerollD 不进玩家池
		_pool_names.append(s)
		_pool_weights.append(float(_ShopAI.WEIGHTS[s]))
	# 🆕 扩展包：**追加在末尾**。`PyRandom.choices()` 用累积权重 + `bisect_right`，
	#    末尾追加不改变既有元素的区间起点 ⇒ 老卡的相对稀有度关系保持
	#    （绝对值因总和变大而等比下降，这是"池变大"的应有表现）。
	if extended_pack:
		for nm in EXT_CARD_ORDER:
			var s := String(nm)
			_pool_names.append(s)
			_pool_weights.append(float(_TD.EXT_WEIGHTS[s]))
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
## 🔴 切片8续3（可玩 MVP）：核心 HP 不再是本类独立账本 —— 一律读写 `player.core_hp`
##   （单一数据源，与 WaveDirector 战斗侧共用）。本类只保留 `scrap` 经济账。

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
## 🟡 切片8·I-7 · 玩家点选的塔位（-1 = 未点选）。单塔效果卡（reinforce）购买时：
##   · 有点选且该塔合法接收此卡 → 投该塔（2 次输入：先点塔再买）；
##   · 否则 → 投主塔 `core_tower_slot()`（1 次输入默认）；
##   · 主塔也不合法接收 → 无合法宿主（D-TB-6 强制点选 / H8 置灰）。
## 🔴 仅玩家路线状态；金标本 AI 路线恒不点选（apply_action 恒投传入的 slot）。
var selected_tower_slot: int = -1

## 🆕 自由摆放（玩家路线）：塔位置由玩家在网格上点选，不再限于 `SLOTS6` 六个固定点。
##   🔴 默认 true；置 false 可一键回退到"六固定塔位"（回归对照 / 出问题时切回）。
##   🔴 金标本引擎（`run_loop` / `wave_sim` / `shop_ai` + 300 局 MC）**从不经过本文件**
##      → 无论这里怎么设，金标本读数都不受影响。
var free_placement: bool = true

## 最近一次成功落子占用的槽位（`confirm_placement_at` 的返回值出口）。
##   GDScript 不能 out 参数，控制器要用 slot 去 `exit_placement(true, slot)` → 走字段。
var last_placed_slot: int = -1


# ---------------------------------------------------------------------------
#  开局
# ---------------------------------------------------------------------------
func setup(p_path: String, seed_value: int, overrides: Dictionary = {}) -> void:
	path = p_path
	cfg = _Cfg.cfg_of(p_path)
	for k in overrides:
		cfg[k] = overrides[k]
	# 🆕 自由摆放：几何从**空槽位表**起步 —— 没有预置塔位，位置由玩家点选后追加。
	#   🔴 起手塔（`SimPlayer.new_player` 送的 Arrow@slot0）随后补一个格点坐标，
	#      否则 `geo.slots[0]` 不存在 → `damage_engine` / `_tower_world` 越界。
	if free_placement:
		geo = _Geo.new([])
	else:
		geo = _Geo6.build_by_slots(int(cfg["n_slots"]))
	player = _SimPlayer.new_player(p_path, cfg, geo)
	if free_placement and player != null and not player.towers.is_empty():
		# 起手位置沿用改造前的 S0 坐标（吸附到格点）→ 老玩家的手感不变。
		# 🆕 阵地化（RADIAL + 布局开启）：S0 (6,33) 落在圆盘内但**不属于任何阵地** ——
		#    起手塔会站在不可建的地上（点它升级 / 拆塔都还正常，但读起来是 bug）。
		#    改落 P1 南台的锚点格：玩家开局就有一座塔在南面主口，正好对上「主口」叙事。
		#    PATH 模式 `sites_active()` 恒 false → 逐位不变。
		if _BuildGrid.sites_active():
			geo.add_slot(_BuildGrid.site_anchor("P1"))
		else:
			geo.add_slot(_BuildGrid.snap(_Geo6.SLOTS6[0]))
	rng = _PyRandom.new(seed_value)
	wave = 0
	scrap = 0.0
	# 🔴 切片8续3：核心 HP 初值由 SimPlayer.new_player 按（可能被 overrides 覆盖的）
	#   cfg.core_hp 设定 → 这里不再重复赋值，只确保与 cfg 一致（幂等）。
	if player != null:
		player.core_hp_max = float(cfg["core_hp"])
		player.core_hp = player.core_hp_max
	rerolls = 0
	lock_index = -1
	offers = []
	pending = []
	pending_cost = []
	counts = {}
	_placing_index = -1
	selected_tower_slot = -1
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
	selected_tower_slot = -1        # I-7：点选每波清空（避免跨波残留误投）
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
	# 🔴 卡包模式：保底卡必须**在本局池内**，否则写进去等于发了一张理论上买不到的卡
	#    （玩家看到的池子和实际发牌不一致）。老口径下 FireUp/FrostUp 恒在池内 → 本判定恒真，
	#    与改动前逐位一致；`pity_card()` 也只可能返回这两张（它只查 `REINF` 主表）。
	if not player_card_names().has(f):
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
##   🔴 槽位数恒 3（`shop_slot_count()`），卡池深度对冲走「刷新保底」而非扩容（见 reroll）。
func deal_initial_shop() -> Array:
	var force = pity_force()
	var out := _draw_offers_player(shop_slot_count())
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
	var fresh := _draw_offers_player(shop_slot_count())
	scrap -= cost
	rerolls += 1
	offers = _merge_with_lock(lock_index, kept, fresh, offers.size())
	# 🆕 刷新保底（card-packs v0.2）：卡包模式（18 张池）下，若刷新结果里一张「骨架卡」都没有，
	#   强制补一张骨架卡（核心塔/强化），对冲大池稀释 —— 让玩家刷新也能稳定拿到 build 骨架。
	_apply_reroll_pity()
	last_error = ""
	return true


## 🆕 刷新保底（card-packs v0.2 · 卡池深度对冲）：
##   仅卡包模式生效（`active_packs` 非空）；若当前 3 位里没有任何「骨架卡」
##   （所选包的核心塔 + 强化卡），把 1 个未锁定位改写为骨架卡池的随机一张。
##   🔴 空选包（老口径 6 张池）不生效 → 与改动前逐位一致；AI 路线（金标本）不经过这里。
##   🔴 不覆盖锁定位（同 `_apply_pity` 的 SR-R4）；锁定位若已是骨架卡则不干预。
func _apply_reroll_pity() -> void:
	if active_packs.is_empty():
		return                                   # 老口径：不引入刷新保底，逐位不变
	var skel := _Packs.skeleton_cards(active_packs)
	if skel.is_empty():
		return
	# 若当前已有骨架卡 → 不干预（玩家已经刷到 build 骨架）
	for nm in offers:
		if skel.has(String(nm)):
			return
	var unlocked: Array = []
	for i in offers.size():
		if i != lock_index:
			unlocked.append(i)
	if unlocked.is_empty():
		return                                   # 全部锁定 → 不干预（E15 / SR-R4）
	offers[int(rng.choice(unlocked))] = String(rng.choice(skel))


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
	return _card_kind(offer_at(slot))


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
	var kind := _card_kind(nm)
	match kind:
		"tower":
			# 建筑卡：买的时候**不落塔**（买/放解耦），落子走 `confirm_placement()`
			return ["build", nm, null, null]
		"reinforce":
			# 🟡 I-7：宿主 = 点选合法塔 → 主塔 → 无合法宿主（D-TB-6 强制点选前置）
			var host := _reinforce_host(nm)
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


# ---------------------------------------------------------------------------
#  切片8·I-7 · 单塔效果卡装配合法性（D-8①：禁止异 Tag；中性塔可接收任意 Tag）
#  与 tower-build TB-7 `can_attach` / D-TB-6 `get_legal_hosts` 同口径。
# ---------------------------------------------------------------------------
## 某座塔能否接收这张单塔效果卡（Tag 匹配：塔中性 "" 收任意；否则需同 Tag）。
func tower_accepts_tag(slot: int, card_name: String) -> bool:
	for t in player.towers:
		if int(t.slot) == slot:
			var ctag := _TD.tower_tag(String(t.ctype))
			if ctag == "":
				return true                          # 中性塔（Arrow/Beacon）收任意 Tag
			return ctag == _TD.reinf_tag(card_name)
	return false


## 该卡能否装配到指定塔（塔存在 + Tag 合法）。
func can_attach_card(slot: int, card_name: String) -> bool:
	if _tower_index(slot) < 0:
		return false
	return tower_accepts_tag(slot, card_name)


## D-TB-6 强制点选用：所有能接收该卡的塔位（Array[int]）。
func get_legal_hosts(card_name: String) -> Array:
	var out: Array = []
	for t in player.towers:
		var s := int(t.slot)
		if tower_accepts_tag(s, card_name):
			out.append(s)
	return out


## I-7 点选/取消点选一座塔（供战场点击接线）。返回是否成功（塔位存在才可点）。
func select_tower(slot: int) -> bool:
	if _tower_index(slot) < 0:
		last_error = "塔位 %d 不存在" % slot
		return false
	selected_tower_slot = slot
	last_error = ""
	return true


func clear_selection() -> void:
	selected_tower_slot = -1


## 单塔效果卡的**实际宿主**：点选合法 → 用点选塔；否则 → 主塔（1 次输入默认）。
## 返回 -1 = 无合法宿主（D-TB-6 强制点选 / H8 置灰的前置判据）。
func _reinforce_host(card_name: String) -> int:
	if selected_tower_slot >= 0 and can_attach_card(selected_tower_slot, card_name):
		return selected_tower_slot
	var core := core_tower_slot()
	if core >= 0 and can_attach_card(core, card_name):
		return core
	return -1


## H8「无合法目标」的判定（E1 建筑卡 / E9 单塔效果卡）；全局卡恒 true。
func legal_at(slot: int) -> bool:
	return legal_note(slot) == ""


func legal_note(slot: int) -> String:
	var nm := offer_at(slot)
	if nm == "":
		return "此位无卡"
	match _card_kind(nm):
		"tower":
			# E1：塔位已满且场上无同原型塔 → 无合法目标（H8 置灰）
			for t in player.towers:
				if String(t.ctype) == nm:
					return ""                                  # 同原型 → 升级（合法）
			if free_placement:
				# 🆕 自由摆放：几何合法性由网格在**落子时**判（点哪判哪），
				#   商店阶段不枚举全盘 ~900 格。这里唯一会挡住的闸门是塔数上限。
				if player.towers.size() >= tower_cap():
					return "塔位已满"
				return ""
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
			# 🟡 I-7：合法 = **存在任一塔可接收**（不只看主塔）。
			#    · 主塔接收 → 1 次输入默认投主塔（legal_note=""）；
			#    · 主塔不接收但有副塔接收 → D-TB-6 强制点选（仍 legal，只是要 2 次输入）；
			#    · 无任何塔接收 → H8 置灰。
			var hosts := get_legal_hosts(nm)
			if hosts.is_empty():
				return "无塔接收该 Tag"                   # H8：无任何合法宿主
			if _reinforce_host(nm) < 0:
				return "选择宿主塔"                       # D-TB-6：主塔不接收，需点选副塔
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

	match _card_kind(nm):
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
	if _card_kind(nm) != "econ":
		return false
	return not (nm == "ScrapUp" and float(player.income_mult) < 1.0)


# ---------------------------------------------------------------------------
#  切片8·C2 · 智能高亮 H2/H3/H5/H6/H7/H9（🔴 只标事实，SR-R2；H1/H4/H8 已在 snapshot）
# ---------------------------------------------------------------------------
## 🔴 口径来源：`shop-reroll` §2.3 规则表（H1–H9，H10 暴露度 T1 不做）。
##   · H2 Tag 协同：卡 Tag ∈ {主塔 Tag, 全场已投 Tag}（脉冲，视觉在 overlay）
##   · H3 +1 档位阈值：再投 1 层跨 κ_tag/κ_r 档位（角标，视觉在 overlay）
##   · H5 层数→下一层：单塔效果卡当前宿主层数 → +1（复利读数）
##   · H6 κ 折价预告：建筑卡建造新塔时的 κ 变化（🔴 强制披露不可逆性，兜底①）
##   · H7 槽位占用事实：{强化槽 x/5, 全局槽 y/3, 塔位 z/6}
##   · H9 ΔDPS 事实：读 `action_value`（= damage_engine 纯函数，SR-1），只给相对增量 %
## 🔴 全部**只读**：不改任何状态；SR-6 由 overlay 事件驱动调一次，不每帧重算。
func highlights() -> Dictionary:
	var info: Dictionary = _engine_info()
	var out: Dictionary = {}
	for i in range(offers.size()):
		var nm := offer_at(i)
		if nm == "":
			out[i] = {"tag_synergy": false, "plus_one": false, "layer_next": "", "kappa_preview": "", "delta_pct": 0.0}
			continue
		var kind := _card_kind(nm)
		var act := _action_for(nm)
		out[i] = {
			"tag_synergy": _h2_tag_synergy(nm, kind, info),
			"plus_one": _h3_plus_one_tier(nm, kind, act, info),
			"layer_next": _h5_layer_next(nm, kind, act),
			"kappa_preview": _h6_kappa_preview(nm, kind, act, info),
			"delta_pct": _h9_delta_pct(act),
		}
	return out


## H7 槽位占用事实（强化槽 / 全局槽 / 塔位）。
func slot_usage() -> Dictionary:
	var enh: int = player.cards.size()
	var tower_n: int = player.towers.size()
	# 🆕 自由摆放：塔位上限 = `tower_cap`（塔数旋钮），与金标本槽位数 `n_slots` 解耦。
	var slots_max: int = tower_cap()
	# 全局槽：ScrapUp 计数（income_mult 每 +0.20 占 1 槽，cap 见 cfg）
	var glob_max := 3
	var glob_used := 0
	if float(player.income_mult) > 0.0:
		glob_used = mini(int(float(player.income_mult) / 0.20), glob_max)
	return {
		"enh": enh, "enh_max": int(cfg["backpack"]),
		"global": glob_used, "global_max": glob_max,
		"tower": tower_n, "tower_max": slots_max,
	}


## 取当前构筑的 damage_engine info（kappa/kr/tag_invest/tag_tower_lv/n_for_kappa）。
func _engine_info() -> Dictionary:
	return _DE.compute_dps(player, cfg, geo).get("info", {})


## H2：卡 Tag 是否与主塔 Tag 或全场已投 Tag 协同。
func _h2_tag_synergy(nm: String, kind: String, info: Dictionary) -> bool:
	var card_tag := ""
	match kind:
		"tower":
			card_tag = _TD.tower_tag(nm)              # 建筑卡原型 Tag
		"reinforce":
			card_tag = _TD.reinf_tag(nm)              # 单塔效果卡 Tag
		_:
			return false
	if card_tag == "":
		return false                                  # 中性（Arrow）不产 Tag 协同脉冲
	var tag_invest: Dictionary = info.get("tag_invest", {})
	if float(tag_invest.get(card_tag, 0.0)) >= 1.0:
		return true                                   # 全场已投该 Tag
	# 主塔 Tag
	var core := core_tower_slot()
	if core >= 0:
		for t in player.towers:
			if int(t.slot) == core:
				if _TD.tower_tag(String(t.ctype)) == card_tag:
					return true
	return false


## H3：再投 1 层是否跨 κ 档位（κ_tag 档 0→3→20 / κ_r 档 0→3→20）。
func _h3_plus_one_tier(nm: String, kind: String, act: Array, info: Dictionary) -> bool:
	if kind != "reinforce" and kind != "tower":
		return false
	# 该卡贡献的 Tag 投入层数（reinforce=1 层；tower 新建=h=1）
	var tag := ""
	if kind == "reinforce":
		tag = _TD.reinf_tag(nm)
	else:
		tag = _TD.tower_tag(nm)
	if tag == "":
		return false                                  # 中性塔/无 Tag 不参与 κ 档位
	var tag_invest: Dictionary = info.get("tag_invest", {})
	var cur := float(tag_invest.get(tag, 0.0))
	# κ_tag 档位阈值 3；κ_r 档位阈值 3 / 20。跨任一阈值即 +1 档位。
	return (cur < 3.0 and cur + 1.0 >= 3.0) or (cur < 20.0 and cur + 1.0 >= 20.0)


## H5：单塔效果卡当前宿主层数 → 下一层（复利读数）。
func _h5_layer_next(nm: String, kind: String, act: Array) -> String:
	if kind != "reinforce" or act.is_empty():
		return ""
	var host: int = int(act[2])
	for t in player.towers:
		if int(t.slot) == host:
			var cur := int(t.attach.get(nm, 0))
			return "Lv %d → %d" % [cur, cur + 1]
	return ""


## H6：κ 折价预告（🔴 强制披露不可逆性，兜底①）。仅建筑卡**新建**塔时触发。
##   κ = κ_tag − disc；disc = 0.01×clamp(N−2,0,4)。新建 → N+1 → disc +0.01 → κ 降。
func _h6_kappa_preview(nm: String, kind: String, act: Array, info: Dictionary) -> String:
	if kind != "tower" or String(act[0]) != "build":
		return ""                                      # 只有新建塔才改广度折价
	var cur_n: int = player.towers.size()
	var k_now := _current_effective_kappa(info)
	var disc_now := 0.01 * float(mini(maxi(cur_n - 2, 0), 4))
	var disc_new := 0.01 * float(mini(maxi(cur_n + 1 - 2, 0), 4))
	var k_new := maxf(0.02, k_now - (disc_new - disc_now))
	if k_new >= k_now - 1e-9:
		return ""                                      # κ 未降（已触下限或广度档未变）
	return "建造新塔：κ %.2f → %.2f（拆除塔不会让 κ 回升）" % [k_now, k_new]


func _current_effective_kappa(info: Dictionary) -> float:
	var kappa: Array = info.get("kappa", [])
	if kappa.is_empty():
		return 0.0
	# 取主塔（或首塔）的 κ（1+κ 形式 → 减 1）
	var core := core_tower_slot()
	var idx := 0
	for i in range(player.towers.size()):
		if int(player.towers[i].slot) == core:
			idx = i
	if idx >= kappa.size():
		idx = 0
	return maxf(0.0, float(kappa[idx]) - 1.0)


## H9：ΔDPS 相对增量 %（读 damage_engine 纯函数，SR-1；只给 % 不给多步预演）。
func _h9_delta_pct(act: Array) -> float:
	if act.is_empty():
		return 0.0
	var before := _DE.dps_only(player, cfg, geo)
	if before <= 0.0:
		return 0.0
	# 试算：快照 → apply → 算 after → 回滚（复用金标本 action_value 的 snap/rest 范式）
	var snap := _SimPlayer.snap(player)
	var cost = _ShopAI.apply_action(player, act, cfg)
	var after := _DE.dps_only(player, cfg, geo)
	_SimPlayer.rest(player, snap)
	if cost == null or after <= before:
		return 0.0
	return (after - before) / before


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


## ---------------------------------------------------------------------------
#  🆕 自由摆放（坐标驱动落子）
# ---------------------------------------------------------------------------
## 塔数上限。自由摆放后「槽位数」与「塔数」不再等价，故独立成字段。
func tower_cap() -> int:
	return int(cfg.get("tower_cap", cfg.get("n_slots", 6)))


## 该格点已占用的槽位号（含拆塔后的空槽）；无则 -1。
## 🔴 复用空槽很重要：拆塔只清 `player.towers` 不缩 `geo.slots`，
##    若每次都 `add_slot` 新槽，槽位表会随「拆 / 建」无限增长。
func _slot_at(p: Vector2) -> int:
	if geo == null:
		return -1
	for i in range(geo.slots.size()):
		if _BuildGrid.same_cell(geo.slots[i], p):
			return i
	return -1


## 🆕 自由摆放预览：某格点的落子结果（**只读**，不改任何状态）。
##   返回 `{mode, slot, reason}`，`mode` ∈ {"", "new", "upgrade", "invalid", "blocked"}：
##     · ""        当前不在放置模式 → 渲染层不画标记
##     · "new"     可新建（空格，塔数未满）
##     · "upgrade" 可升级（同格已有同原型塔）
##     · "invalid" 有卡在放但这一格不能落（塔数已满 / 已有别的原型）
##     · "blocked" 几何上不可建（核心禁建区 / 战场外）—— 与"有卡"无关，恒定显示
##   🔴 渲染层每帧对**鼠标所指那一格**调一次（不是全盘 ~900 格），成本 O(塔数)。
func placement_mode_at(pos: Vector2) -> Dictionary:
	var gpos := _BuildGrid.snap(pos)
	if not _BuildGrid.buildable(gpos):
		return {"mode": "blocked", "slot": -1, "reason": "此处不可建"}
	if _placing_index < 0 or _placing_index >= pending.size():
		return {"mode": "", "slot": -1, "reason": ""}
	var nm := String(pending[_placing_index])
	var existing := _slot_at(gpos)
	if existing >= 0:
		var ti := _tower_index(existing)
		if ti >= 0:
			if String(player.towers[ti].ctype) == nm:
				return {"mode": "upgrade", "slot": existing, "reason": ""}
			return {"mode": "invalid", "slot": existing, "reason": "这格已有「%s」" % String(player.towers[ti].ctype)}
		return {"mode": "new", "slot": existing, "reason": ""}
	if player.towers.size() >= tower_cap():
		return {"mode": "invalid", "slot": -1, "reason": "塔数已满 %d / %d" % [player.towers.size(), tower_cap()]}
	return {"mode": "new", "slot": -1, "reason": ""}


## 🆕 自由摆放落子：世界坐标 → 吸附格点 → 新建 / 升级 / 拒绝。
##
## 返回 true = 已落子（槽位见 `last_placed_slot`）；false = 未落子（原因见 `last_error`）。
##
## 🔴 与 `confirm_placement(slot)` 的分工：
##   · `confirm_placement` = 「槽位已确定」的旧入口（回归对照 / 无网格的老路径）；
##   · `confirm_placement_at` = 「玩家点了地图某处」的新入口 —— 吸附、查重、必要时建槽。
##   两者共用同一条 `_ShopAI.apply_action` 执行路径 → 成本 / 层数 / invested 口径完全一致。
func confirm_placement_at(pos: Vector2) -> bool:
	last_placed_slot = -1
	if _placing_index < 0 or _placing_index >= pending.size():
		last_error = "当前没有正在放置的卡"
		return false
	if geo == null:
		last_error = "战场几何未初始化"
		return false

	var gpos := _BuildGrid.snap(pos)
	if not _BuildGrid.buildable(gpos):
		# 🆕 阵地化后两种"不可建"的成因不同，文案要分开：一个是圈，一个是台。
		if _BuildGrid.sites_active():
			last_error = "这里不是阵地 —— 塔只能建在青色台子上"
		else:
			last_error = "这里不能建塔（核心 %.0fu 内 / 战场外圈）" % _BuildGrid.CORE_BAN_R
		return false

	var nm := String(pending[_placing_index])
	var existing := _slot_at(gpos)
	var mode := "new"
	if existing >= 0:
		var ti := _tower_index(existing)
		if ti >= 0:
			if String(player.towers[ti].ctype) != nm:
				last_error = "这格已有「%s」，不能改建为「%s」" % [String(player.towers[ti].ctype), nm]
				return false
			mode = "upgrade"
		# ti < 0 = 拆塔残留的空槽 → 直接复用（mode 保持 "new"）
	elif player.towers.size() >= tower_cap():
		last_error = "塔数已满（%d / %d）" % [player.towers.size(), tower_cap()]
		return false

	var slot := existing
	if slot < 0:
		slot = geo.add_slot(gpos)

	var act := ["build", nm, slot, null] if mode == "new" else ["up", nm, slot, null]
	if _ShopAI.apply_action(player, act, cfg) == null:
		last_error = "落子失败：%s" % nm
		return false

	# 建筑卡成本（build / up 同价）计入**这座塔**的 invested（拆除返还 50% 的依据）
	var paid := 0.0
	if _placing_index < pending_cost.size():
		paid = float(pending_cost[_placing_index])
	_add_invested(slot, paid)

	pending.remove_at(_placing_index)
	pending_cost.remove_at(_placing_index)
	_placing_index = -1
	last_placed_slot = slot
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


# ---------------------------------------------------------------------------
#  T1 · 修复入口（波次间安全窗对 Disabled 塔的三选一处置 · Q-T4/Q-T8 定稿）
# ---------------------------------------------------------------------------
## 🔴 定稿口径（一字不改）：
##   · Q-T4 = ①：Disabled 塔在**下一个波次间安全窗**玩家三选一：修复 / 拆除 / 放着不管。
##   · Q-T8：**修复** `repair_cost = ceil(0.30 × 该塔累计投入)`（PLACEHOLDER，待 V-1 扫参）
##     → HP 回满、塔恢复输出、**装配卡全部保留**（区别于主动拆除的全销毁）。
##     **被动拆除**（Disabled 塔的拆除）返还 **0%**（区别主动移除的 50%）→ 保塔的经济动机。
##     **放着不管** = 继续占塔位、不输出、仍吃 κ 折价（隐性持续惩罚）→ 本方法不实现（no-op）。
##   · E-T4：没钱修复 → 允许「放着不管」或「0 返还拆除」释放塔位 → **永不死锁**。
##   · E-T6：修复**只恢复 HP，不改任何层数**；repair_cost 按**当前**累计投入算。
##   · E-T2：多座同时停机合并为一个列表弹窗（`list_disabled_towers()` 供 UI 组装）。
##
## 🔴 金标本零改动：修复/被动拆除只在玩家路线（本文件）；`shop_ai.gd` 不读不写。
##    κ 口径不动（Disabled 塔仍占塔位供 h_j → N_tower 不变；修复后恢复输出）。
##
## 🔴 仅 SafeWindow 可操作（T-C1 / E16）；非安全窗直接拒绝。

## 修复费用系数（Q-T8 = ceil(0.30 × 累计投入)）。
const REPAIR_RATE := 0.30

## 🔒 T1 玩法③ 献祭 `Salvage Rite`：献祭收益系数 = floor(累计投入 / 该除数) 的 StackCap+。
##   GDD §3 玩法③「收益 ∝ 被献祭塔的累计投入」（例 floor(投入/10)）→ 先投入才能献祭（earned），
##   刷塔要真花钱 → 投入产出守恒、天然防刷（收益∝投入即设限，无需额外计数闸）。
const RITE_STACKCAP_DIVISOR := 10.0


## 🔴 只读预览：给献祭二次确认弹窗组装文案用（**不改动任何状态**）。
##   返回 {ok, reason, invested, stackcap_gain, cards_destroyed, layers_destroyed}。
##   与 `salvage_rite()` 同判据，但纯读 → UI 可先预览再让玩家确认。
func preview_rite(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "invested": 0.0, "stackcap_gain": 0.0,
		"cards_destroyed": 0, "layers_destroyed": 0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可献祭（T-C1 / E16）"
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
	result["invested"] = invested
	result["stackcap_gain"] = floorf(float(invested) / RITE_STACKCAP_DIVISOR)
	result["cards_destroyed"] = n_cards
	result["layers_destroyed"] = n_layers
	return result


## 献祭 `Salvage Rite(tower)` —— 🔒 T1 玩法③ 定稿（主动移除的**第二出口**，与回收二选一）：
##   · 返还 **0%**（区别回收的 50% → 献祭是"沉没成本变现为 StackCap"，不是拿回积分）；
##   · 该塔装配的**全部单塔效果卡及层数销毁**（同回收：attach 清空，卡从 player.cards 移除）；
##   · **塔位释放**（从 player.towers 删除）；
##   · 🔴 **换取一次性增益**：`player.stackcap_bonus += floor(累计投入 / 10)`（收益 ∝ 投入 = earned，
##     兑现 P2；刷塔要真花钱 → 天然防刷）。StackCap+ 让层数最集中的主塔受益最多 → 耦合单核流。
##   · 🔴 **κ 不回升**（兜底①：本方法不动 n_hist_max）；
##   · 返回结算字典供 UI 二次确认弹窗披露「献祭得 StackCap +N / 销毁 N 张（M 层）」。
## 🔴 仅 SafeWindow 可操作（T-C1 / E16）；非安全窗直接拒绝。
## 🔴 金标本零改动：金标本 AI 不献祭（shop_ai 不读不写 stackcap_bonus）→ 判据链不受影响。
func salvage_rite(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "invested": 0.0, "stackcap_gain": 0.0,
		"cards_destroyed": 0, "layers_destroyed": 0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可献祭（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	var invested := floorf(float(t.invested))
	# ① 装配卡全销毁（同回收）
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
	# ③ 献祭换 StackCap+（收益 ∝ 投入；返还 0% 积分）
	var gain := floorf(float(invested) / RITE_STACKCAP_DIVISOR)
	player.stackcap_bonus = float(player.stackcap_bonus) + gain
	result["ok"] = true
	result["invested"] = invested
	result["stackcap_gain"] = gain
	result["cards_destroyed"] = n_cards
	result["layers_destroyed"] = n_layers
	last_error = ""
	return result


## 🔴 只读预览：给处置弹窗组装「修复」文案用（**不改动任何状态**）。
##   返回 {ok, reason, cost, invested, hp_max}。仅对 **Disabled 塔**有意义。
func preview_repair(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "cost": 0, "invested": 0.0, "hp_max": 0.0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可修复（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	if not bool(t.disabled):
		result["reason"] = "塔未受损，无需修复"
		return result
	var invested := floorf(float(t.invested))
	result["ok"] = true
	result["cost"] = int(ceilf(float(invested) * REPAIR_RATE))
	result["invested"] = invested
	result["hp_max"] = float(t.hp_max)
	return result


## 修复 `Repair(tower)` —— Q-T8 定稿（仅 Disabled 塔）：
##   · 花费 `ceil(0.30 × 累计投入)` 分 → HP 回满 → 塔恢复输出（`disabled = false`）；
##   · 🔴 **装配卡全部保留**（与主动拆除的全销毁相反）；层数不变（E-T6）。
##   · 返回 {ok, reason, cost, invested}（供 UI 披露花费）。
##   · 🔴 积分不足 → ok=false（E-T4：玩家可改「放着不管」或「0 返还拆除」→ 永不死锁）。
func repair_tower(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "cost": 0, "invested": 0.0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可修复（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	if not bool(t.disabled):
		result["reason"] = "塔未受损，无需修复"
		return result
	var invested := floorf(float(t.invested))
	var cost := int(ceilf(float(invested) * REPAIR_RATE))
	if scrap < float(cost):
		result["reason"] = "积分不足（需 %d，现有 %d）→ 可「放着不管」或「拆除」" % [cost, int(scrap)]
		result["cost"] = cost
		result["invested"] = invested
		return result
	# ① 扣分 ② 回满 HP ③ 恢复输出（装配卡不动、层数不动）
	scrap -= float(cost)
	t.hp = float(t.hp_max)
	t.disabled = false
	result["ok"] = true
	result["cost"] = cost
	result["invested"] = invested
	last_error = ""
	return result


## 被动拆除 `Salvage(Disabled tower)` —— Q-T4/Q-T8 定稿（仅 Disabled 塔）：
##   · 返还 **0%**（区别主动移除的 50% → 保塔的经济动机）；
##   · 装配卡**全销毁**（同主动拆除）+ **塔位释放**（同主动拆除）；
##   · 🔴 κ 不回升（兜底①：`n_hist_max` 只增不减，E11）→ 本方法不动 `n_hist_max`。
##   · 返回 {ok, reason, cards_destroyed, layers_destroyed}。
##   · 🔴 仅 SafeWindow；非安全窗直接拒绝。
func salvage_disabled_tower(slot: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "cards_destroyed": 0, "layers_destroyed": 0}
	if not _in_safe_window():
		result["reason"] = "仅波次间安全窗可拆除（T-C1 / E16）"
		return result
	var idx := _tower_index(slot)
	if idx < 0:
		result["reason"] = "塔位 %d 不存在" % slot
		return result
	var t = player.towers[idx]
	if not bool(t.disabled):
		result["reason"] = "该塔未受损；如需主动拆除请走「拆除并回收」（返还 50%）"
		return result
	# ① 装配卡全销毁（同主动拆除）
	var n_cards := 0
	var n_layers := 0
	for cname in _keys(t.attach):
		var layers := int(t.attach[cname])
		n_cards += 1
		n_layers += layers
		player.cards.erase(cname)
	# ② 塔位释放（返还 0% → 不加 scrap）
	player.towers.remove_at(idx)
	result["ok"] = true
	result["cards_destroyed"] = n_cards
	result["layers_destroyed"] = n_layers
	last_error = ""
	return result


## 列出所有 **Disabled 塔**的处置信息（E-T2：多座同时停机合并为一个列表弹窗的数据源）。
##   返回 Array[Dictionary]：{slot, invested, repair_cost, attach_layers}。
func list_disabled_towers() -> Array:
	var out: Array = []
	for t in player.towers:
		if bool(t.disabled):
			var invested := floorf(float(t.invested))
			var n_layers := 0
			for _k in t.attach:
				n_layers += int(t.attach[_k])
			out.append({
				"slot": int(t.slot),
				"invested": invested,
				"repair_cost": int(ceilf(float(invested) * REPAIR_RATE)),
				"attach_layers": n_layers,
			})
	return out


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


## R3：收入 = 本波击杀废铁 × (1 + income_mult)。
## 🔴 切片8续3（可玩 MVP）：核心 HP 扣减**不再**在此处 —— 实时战斗里 `WaveDirector`
##   已在漏怪当刻把 `player.core_hp` 扣到单一数据源上（E-W3 实时失败判定 + HUD 实时读数）。
##   若此处再按 `core_damage` 扣一次就是**双重扣血**（金标本 `run_loop` 是独立本地变量、
##   不走本函数，故不受影响）。本函数只入积分账。
func grant_wave_result(res: Dictionary) -> void:
	scrap += float(res["scrap_earned"]) * (1.0 + float(player.income_mult))


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
	while names.size() < shop_slot_count():
		names.append("")
		kinds.append("")
		prices.append(0.0)
		affordable.append(false)
		legal.append(false)
		notes.append("此位无卡")
		caps.append(false)
	# ---- 塔位事实（H7 槽位占用 / 放置模式高亮：New = 青 / Upgrade = 金）----
	# 🆕 自由摆放：遍历 `geo.slots`（运行时增长的槽位表），而不是 `range(n_slots)`。
	#   改造前槽位表恒 6 个 → 建到第 7 座塔就完全不可见。现在槽位数随摆塔增长，
	#   渲染层按 `slot` 索引取 `geo.slots[slot]` 的世界坐标，两边天然对齐。
	#   🔴 拆塔会留下空槽（`empty: true`）—— 保留它在表里是为了「槽位号 = 索引」不失效，
	#      渲染层跳过空槽即可（自由摆放没有「虚位以待的空塔位」这个概念）。
	var slots: Array = []
	var place_modes: Array = []
	var by_slot := {}
	for t in player.towers:
		by_slot[int(t.slot)] = t
	var slot_n: int = geo.slots.size() if geo != null else 0
	# 🔴 防御：某座塔的 slot 若超出槽位表（手工构造场景 / 极端边缘），仍要出现在快照里，
	#   否则 UI 的塔数统计与「处置受损塔」红点会静默漏塔。正常路径不会走到这个分支
	#   —— 所有建塔都经 `confirm_placement_at → geo.add_slot`，slot 必然 < slots.size()。
	for t in player.towers:
		slot_n = maxi(slot_n, int(t.slot) + 1)
	for i in range(slot_n):
		if by_slot.has(i):
			var t2 = by_slot[i]
			# 🔒 T1 修复入口 UI：暴露 disabled 状态供重决策面板红点计数（有受损塔才亮「处置受损塔」按钮）
			slots.append({"slot": i, "ctype": String(t2.ctype), "h": int(t2.h),
				"empty": false, "disabled": bool(t2.disabled)})
		else:
			slots.append({"slot": i, "ctype": "", "h": 0, "empty": true, "disabled": false})
		place_modes.append(placement_mode_for(i) if _placing_index >= 0 else "")

	return {
		"wave": wave,
		"scrap": scrap,
		"core_hp": player.core_hp,
		"core_hp_max": player.core_hp_max,
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
		# 🆕 卡包模式：本局卡包 / 卡池张数（UI 只读，用来解释"这局为什么只有这些卡"）
		"card_packs": active_pack_ids(),
		"card_pool_size": player_card_names().size(),
		"towers": player.towers.size(),
		# 🆕 自由摆放：上限取 `tower_cap`（玩家路线塔数上限），不是 `n_slots`（金标本槽位数）。
		"towers_max": tower_cap(),
		"income_mult": float(player.income_mult),
		"reroll_disc": float(player.reroll_disc),
		"core_tower_slot": core_tower_slot(),
		"selected_tower_slot": selected_tower_slot,   # I-7：点选塔位（-1=无）
		"slot_usage": slot_usage(),                    # C2·H7 槽位占用事实
		"highlights": highlights(),                    # C2·H2/H3/H5/H6/H9 每商品位事实
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
