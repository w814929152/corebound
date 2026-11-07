extends Node
##
## 最小启动场景（MVP 切片1 → 切片3）。
## · headless（CI / --quit）下自动跑测试套件，失败则非零退出码；
## · 窗口模式下装载切片3 骨架场景（战场占位 + 商店抽屉占位），不跑自测。
##
## 🔴 G6：headless `--script` 没有 global_script_class_cache → 一律 preload。
##

const TestSuite := preload("res://tests/test_suite.gd")
const TestSuiteSlice3 := preload("res://tests/test_suite_slice3.gd")
const TestSuiteSlice4 := preload("res://tests/test_suite_slice4.gd")
const BattleShop := preload("res://scenes/battle_shop.tscn")
const SpaceModel := preload("res://scripts/geo/space_model.gd")
const ShopRuntime := preload("res://scripts/gameplay/shop_runtime.gd")
## 🆕 卡包（2026-11-07）：开局选包界面 + 局外进度（最佳波次 / 上次选包 / 存档）
const PackSelect := preload("res://scripts/ui/pack_select_overlay.gd")
const RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const CardPacks := preload("res://scripts/data/card_packs.gd")
## 🆕 关卡推进（2026-11-07）：关卡进度 + 存档（与卡包两条线，见 campaign-progression.md）
const Campaign := preload("res://scripts/gameplay/campaign.gd")
const CampaignData := preload("res://scripts/data/campaign_data.gd")
const StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")

## 🆕 关卡推进总开关（默认关 = 与「无 meta」完全等价，金标本逐位不变）。
##    🔴 打开后：实机按「当前关卡」注入波数（wave_count）并在通关/失败时记账；
##        关闭时：不注入波数（= 20 波金标本口径）、不记账。一行回滚 = 改回 false。
const CAMPAIGN_ENABLED := false

var _bs: Node = null
var _pack_select: CanvasLayer = null
var _campaign = null
var _stage_select: CanvasLayer = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		var ok := TestSuite.new().run_all()
		ok = TestSuiteSlice3.new().run_all() and ok
		ok = TestSuiteSlice4.new().run_all() and ok
		get_tree().quit(0 if ok else 1)
	else:
		# 🔴 径向迁移收官：实机运行时默认 = RADIAL（径向核心围攻）。
		#    注入点选在这里而非 `space_model.gd:40` 的全局默认值，是因为：
		#      · `SpaceModel.mode` 是全局静态变量，被 PATH 口径金标本回归（run_tests.gd
		#        默认无参 = slice1~8 + t1aggro）**隐式依赖**——它们自身不碰 mode，但
		#        依赖的引擎（wave_sim / monster / wave_director）用 is_radial() 分派。
		#        改全局默认会让 PATH 金标本全部分派到 RADIAL 分支而全挂。
		#      · 本分支只在**窗口模式**执行；headless 分支（跑测试套件）与
		#        `--script res://tests/run_tests.gd` 两条路径都**永不进入这里**
		#        （后者根本不装载 main.tscn）→ 金标本零扰动。
		#    回滚：把下面这行删掉 / 改回 `Mode.PATH` 即可（一行回退，双模设计本就为此）。
		SpaceModel.mode = SpaceModel.Mode.RADIAL
		# 🆕 扩展包（2026-11-06 · 「丰富玩法」）：把 Lance / Tesla / PirUp / ShkUp
		#    放进**玩家路线**商店卡池（6 张 → 10 张）。
		#    🔴 为什么安全：金标本 `ShopAI.CARD_NAMES` / `WEIGHTS` **一字不动**，
		#       扩展卡只经 `shop_runtime._build_player_pool()` 追加 ⇒ AI 路线 / MC / 金标本零扰动。
		#    🔴 为什么在这里开：本分支只在**窗口模式**执行；headless 自测与
		#       `--script` 测试路径永不进入 ⇒ 任何断言读数不受影响。
		#    一行回滚：改成 `set_extended_pack(false)` 或删掉本行（回到 6 张卡口径）。
		ShopRuntime.set_extended_pack(true)
		print("[boot] 扩展包 ON —— 玩家卡池 6 → 10（+Lance/Tesla/PirUp/ShkUp）")
		# 🔴 第四 / 第五刀：原型 / 精英波 + 仇恨（tower_aggro）**上线**
		#    （原型/精英：`docs/phase3/proto-elite-golive-spec.md` §2.2；
		#     仇恨：`docs/phase3/tower-aggro-golive-spec.md` + `...-impl.md` §7）。
		# 🔴 第五刀上线口径（2026-10-10 用户裁决「上线 + CI 转硬门禁」）：实机**全开**——
		#    RADIAL + 三原型 + Elite + 仇恨（塔可受损 / Disabled 中间态 / 安全窗三选一修复）。
		#    上线门禁：实机全开 MC **PRICED（最接近产品）多塔 B@6 = 0.850 ≥ 0.80 达标**
		#    （FREE 上界 0.877 / OFF 下界 0.683〔P2②翻参后 · 原 0.677〕；口径矩阵见 impl §7.4）。
		#    注入点必须在 `add_child(bs)` **之后**（battle_shop._ready() 同步建好 wave_director，
		#    见 battle_shop.gd:50）、`controller.call_deferred("start_run", 1)` **之前**（deferred →
		#    下一帧才开波，见 battle_shop.gd:91）→ 此处设开关安全、早于首局。
		#    🔴 headless 分支与 `tests/run_tests.gd` 路径**永不进入**本分支 → 金标本零扰动。
		#    🔴 反制窗口 M-1 上线（阶段 B）：塔死亡产品路径 = **战斗中即时被动复活**
		#       （`combat_revive_enabled`，见下行新增代码）；`repair_on_disable` 仍保持 0
		#       （诊断枚举不占用，扫描/测试路径保持纯净）。
		#    一行回滚（关闭 aggro）：删掉下面 `tower_aggro_enabled = true` 那一行即可
		#    → 回到第四刀口径（RADIAL + 三原型 + Elite，仇恨关闭 / 塔不可受损 / 无 Disabled）。
		var bs = BattleShop.instantiate()
		# 🆕 卡包：本场景**不再自动开波**，改由下面 `_open_pack_select()` 在选包后开局。
		#    🔴 一行回滚：删掉本行 → 退回"进场景立刻 W1"的老行为（卡包不生效）。
		bs.auto_start_run = false
		add_child(bs)
		_bs = bs
		bs.wave_director.prototype_split_enabled = true
		bs.wave_director.elite_waves_enabled = true
		bs.wave_director.tower_aggro_enabled = true
		# 🔒 反制窗口 M-1（产品开关 · 与上面三开关同族）：战斗中即时被动复活。
		#    🔴 一行回滚：删掉下一行即退回默认（塔死亡只走安全窗三选一）。
		bs.wave_director.combat_revive_enabled = true
		# 🆕 战斗类型系统（物理/魔法 × 物抗/魔抗 · design/gdd/combat-types.md v0.1）。
		#    🔴 默认 false = 旧聚合池口径（金标本零扰动）；打开后塔按攻击类型拆分 DPS 池、
		#       怪物按原型抗性分别结算（Rush 魔抗 0.20 / Tank 物抗 0.30 / Swarm 双抗 0）。
		#    🔴 一行回滚：删掉下一行即退回旧口径。
		bs.wave_director.combat_types_enabled = true
		print("[boot] proto/elite/aggro/revive/combat_types 全 ON（战斗类型系统 · RADIAL 实机口径）")
		print("[boot] SpaceModel.mode = RADIAL（径向核心围攻 · 实机默认）")
		print("[boot] Corebound MVP · 切片4（实时商店覆盖层 + 完整商店逻辑接线）")
		print("[boot] Tab 开关抽屉 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位")
		print("[boot] 商品位显示真实卡名/价格；建筑卡买入后入待放置队列 → 点「放置」→ 点地图格子落子")
		print("[boot] 自测只在 headless 下执行（<godot> --headless --script res://tests/run_tests.gd）")

		# ---- 🆕 卡包：选包界面 + 局外进度接线（2026-11-07）----
		#   ① 一局结束 → 记录最佳波次（解锁卡包；失败也推进，见 `run_meta.gd`）；
		#   ② 结算"再来一局" → 先回选包界面（换构筑），选完再 `start_new_run()`；
		#   ③ 首次进入 → 已解锁 ≤3 包直接开局（无选择余地），>3 包才弹界面。
		bs.controller.run_finished.connect(_on_run_finished)
		bs.controller.restart_hook = Callable(self, "_open_pack_select")
		_pack_select = PackSelect.new()
		add_child(_pack_select)
		_pack_select.packs_confirmed.connect(_on_packs_confirmed)
		# 🆕 关卡推进：加载存档（默认关 = 不注入波数，见 CAMPAIGN_ENABLED）。
		if CAMPAIGN_ENABLED:
			_campaign = Campaign.new()
			_campaign.load_save()
			print("[boot] 关卡推进 ON · 当前关卡 %s · Ember %d" % [
				_campaign.current_stage(), _campaign.ember()])
			_stage_select = StageSelect.new()
			add_child(_stage_select)
			_stage_select.stage_selected.connect(_on_stage_selected)
			call_deferred("_open_stage_select")
		else:
			call_deferred("_open_pack_select")


# ---------------------------------------------------------------------------
#  卡包：开局 / 再来一局的选包流程
# ---------------------------------------------------------------------------
## 关卡推进：开局前先选关卡（选完再走选包 → 开局）。🔴 仅在 CAMPAIGN_ENABLED 时被调。
func _open_stage_select() -> void:
	if _bs == null or _stage_select == null or _campaign == null:
		return
	_stage_select.open(_campaign)


func _on_stage_selected(sid: String) -> void:
	# 选完关卡 → 继续走卡包选择流程（带当前关卡进局）。
	_open_pack_select()


## 需要选包 → 弹界面；不需要（已解锁 ≤ 必须选的数）→ 全带，直接开局。
func _open_pack_select() -> void:
	if _bs == null or _pack_select == null:
		return
	if RunMeta.needs_selection():
		_pack_select.open()
	else:
		_begin_run(RunMeta.unlocked_ids())


func _on_packs_confirmed(packs: Array) -> void:
	_begin_run(packs)


## 卡包生效 + 开新一局。🔴 卡池在 `ShopRuntime` 的静态缓存里，必须先设包再开局。
func _begin_run(packs: Array) -> void:
	# 🔴 兜底关闭：正常路径由选包界面自己隐藏；若走"直接开局"（未解锁 ≤3 包）
	#    或外部直接调用本函数，也必须保证界面不压在新一局上面。
	if _pack_select != null:
		_pack_select.close()
	ShopRuntime.set_active_packs(packs)
	# 🆕 关卡推进：开波前按「当前关卡」注入波数（不注入 = 20 波金标本口径）。
	if CAMPAIGN_ENABLED and _campaign != null:
		var sid: String = _campaign.current_stage()
		var st: Dictionary = CampaignData.STAGES.get(sid, {})
		var wc: int = int(st.get("wave_count", 20))
		if _bs != null and _bs.wave_director != null:
			_bs.wave_director.set_max_wave(wc)
		# 🆕 运行时换图：按当前关卡注入活动地图（未实现自动回落 tri-fissure）。
		var mid: String = CampaignData.resolve_map_id(sid)
		SpaceModel.set_active_map(mid)
		print("[boot] 本局关卡 %s（%s）· %d 波 · 地图 %s" % [
			sid, String(st.get("name", "")), wc, SpaceModel.active_map_id])
	var names: Array = []
	for pid in packs:
		names.append(CardPacks.pack_name(String(pid)))
	print("[boot] 本局卡包：%s（卡池 %d 张）" % [_join(names, "、"), ShopRuntime.player_card_names().size()])
	_bs.controller.start_new_run()


func _on_run_finished(won: bool, wave: int) -> void:
	var fresh: Array = RunMeta.record_run(won, wave)
	var best := RunMeta.best_wave()
	var names: Array = []
	for pid in fresh:
		names.append(CardPacks.pack_name(String(pid)))
	if fresh.is_empty():
		print("[boot] 本局结束（%s W%d）· 最佳波次 W%d · 无新卡包" % [
			"胜" if won else "负", wave, best])
	else:
		print("[boot] 本局结束（%s W%d）· 最佳波次 W%d · 新卡包解锁：%s" % [
			"胜" if won else "负", wave, best, _join(names, "、")])
	# 🆕 关卡推进：通关/失败记账（解锁下一关 + Ember；不碰卡包逻辑）。
	if CAMPAIGN_ENABLED and _campaign != null:
		var sid: String = _campaign.current_stage()
		if won:
			var r: Dictionary = _campaign.on_cleared(sid)
			if r.get("ok", false):
				var bits: Array = []
				bits.append("Ember +%d" % int(r.get("ember_gained", 0)))
				if String(r.get("unlocked_stage", "")) != "":
					bits.append("解锁 %s" % String(r.get("unlocked_stage", "")))
				if String(r.get("unlocked_deck", "")) != "":
					bits.append("解锁卡组 %s" % String(r.get("unlocked_deck", "")))
				print("[boot] 关卡推进 · %s · %s" % [sid, _join(bits, " · ")])
		else:
			var r: Dictionary = _campaign.on_failed(sid, wave)
			if r.get("ok", false):
				print("[boot] 关卡推进 · %s 失败 · Ember +%d" % [sid, int(r.get("ember_gained", 0))])


## 字符串拼接（`String.join` 只吃 PackedStringArray，这里避开隐式转换坑）
func _join(arr: Array, sep: String) -> String:
	var s := ""
	for i in arr.size():
		if i > 0:
			s += sep
		s += String(arr[i])
	return s
