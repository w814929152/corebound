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
## 🆕 主界面（2026-11-07）：启动第一屏 —— 开始游戏 / 卡组图鉴 / 退出。
const MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")

## 🆕 关卡推进总开关（2026-11-07 起**实机默认开**：开局先在「裂隙航图」大地图选关）。
##    🔴 打开后：实机按「当前关卡」注入波数（wave_count）并在通关/失败时记账；
##        关闭时：不注入波数（= 20 波金标本口径）、不记账、不弹选关。一行回滚 = 改回 false。
##    🔴 金标本零扰动：本开关只影响**窗口模式**的玩家路线；headless 分支与
##        `--script` 测试路径永不进入 `_ready` 的 else 分支（见上）。
const CAMPAIGN_ENABLED := true
## 🆕 关卡波表开关（`scripts/data/stage_waves.gd` · `design/gdd/stage-waves.md`）。
##   true  → 每波按该关波表覆盖 `n` / `hp_unit`（**整关总血量守恒**，只改形状）
##   false → 走金标本曲线（`monster_stats(w)`），与改前逐位相同
##   🔴 一行回滚：改回 false。金标本引擎从不读这条路径（它走 `wave_sim`）→ 零扰动。
##   🔴 前提：`CampaignData` 必须已是 v2 的十关（同名不同义的 id 会套错波表）。
##      当前 `CampaignData.STAGES` 已是 v2，且 `tests/run_campaign_asserts.gd` 会断言
##      「每关 wave_count == StageWaves.wave_count(id)」→ 两者漂移会直接红。
const STAGE_WAVES_ENABLED := true

## 🆕 科技包解锁判据（`design/gdd/campaign-v2-overseer.md` §9 第 4 项 · 2026-11-08）
##   true  → **守住地区 → 入手该地区科技**（`card_packs.unlock_by_region`）。
##           进关时该地区包「借用」可用，通关后永久入手 —— 这是剧情的核心闭环。
##   false → 老口径（`all_packs_open` 全开 / 最佳波次逐包解锁），一行回滚。
##   🔴 只在玩家路线（窗口模式）打开；headless 与 `--script` 路径永不进入 `_ready` 的
##      else 分支 → 金标本 / MC 逐位不变。
##   🔴 打开后 `best_wave` 不再驱动解锁（`RunMeta.next_unlock_wave()` 返回 -1）：
##      存档里那半条线保留不删，只是不再当判据。
const DECK_BY_REGION_ENABLED := true

var _bs: Node = null
var _pack_select: CanvasLayer = null
var _campaign = null
var _stage_select: CanvasLayer = null
var _main_menu: CanvasLayer = null


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
		# 🆕 再来一局：关卡推进 ON → 先回「裂隙航图」重新选关（顺带看到新解锁的关）；
		#    OFF → 老口径（直接回选包）。改动前二者都是直接选包。
		bs.controller.restart_hook = Callable(self,
			"_open_stage_select" if CAMPAIGN_ENABLED else "_open_pack_select")
		_pack_select = PackSelect.new()
		add_child(_pack_select)
		_pack_select.packs_confirmed.connect(_on_packs_confirmed)
		# ---- 🆕 主界面（2026-11-07）：启动第一屏 ----
		#   流程：主界面 →（开始游戏）→ 选关 → 选包 → 开局。
		#   🔴 主界面自己**不写任何玩法状态**：只发 `start_requested`，由本文件决定
		#      下面走哪条既有流程 —— 与 pack_select / stage_select 同一分层纪律。
		_main_menu = MainMenu.new()
		add_child(_main_menu)
		_main_menu.start_requested.connect(_on_main_start)
		_main_menu.quit_requested.connect(_on_main_quit)
		# 🆕 关卡推进：加载存档（默认关 = 不注入波数，见 CAMPAIGN_ENABLED）。
		if CAMPAIGN_ENABLED:
			_campaign = Campaign.new()
			_campaign.load_save()
			# 🆕 把「已守地区」注入卡包判据，并设好本关的「借用科技」。
			#    🔴 必须在主界面打开**之前**同步：图鉴页会读解锁态，晚一帧就会先闪一遍
			#       "全部锁着"再跳成正确状态。
			_sync_deck_unlock()
			print("[boot] 关卡推进 ON · 当前关卡 %s · Ember %d · 已守地区 %d · 科技包 %d" % [
				_campaign.current_stage(), _campaign.ember(),
				_campaign.regions_cleared(), CardPacks.unlocked_ids(RunMeta.best_wave()).size()])
			_stage_select = StageSelect.new()
			add_child(_stage_select)
			_stage_select.stage_selected.connect(_on_stage_selected)
		# 🔴 启动第一屏一律是主界面（选关 / 选包由「开始游戏」触发）。
		call_deferred("_open_main_menu")


# ---------------------------------------------------------------------------
#  主界面：启动第一屏
# ---------------------------------------------------------------------------
## 打开主界面。🔴 `--open-library` 是 UI 截帧探针（窗口模式直接落在图鉴页），
##   不影响正常启动路径（不传参数时行为与改前逐位一致）。
func _open_main_menu() -> void:
	if _main_menu == null:
		return
	# 🔴 探针参数可能出现在 `--` 之后（此时只在 `get_cmdline_user_args()` 里），
	#    所以两个列表都要查 —— 否则「传了参数却按默认路径走」，很难查。
	if _has_cmd_flag("--open-library"):
		_main_menu.show_library()
	else:
		_main_menu.open()


func _has_cmd_flag(flag: String) -> bool:
	return OS.get_cmdline_args().has(flag) or OS.get_cmdline_user_args().has(flag)


func _on_main_start() -> void:
	if _main_menu != null:
		_main_menu.close()
	if CAMPAIGN_ENABLED:
		_open_stage_select()
	else:
		_open_pack_select()


func _on_main_quit() -> void:
	get_tree().quit(0)


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
	# 🆕 先按新关卡重算「借用科技」：换一张图不刷新，玩家会带着上一关的借用包进局
	#    （= 白拿一包，且守住后才发现「这包本来就是我的」）。
	_sync_deck_unlock(String(sid))
	_open_pack_select()


## 🆕 科技包解锁判据同步（**唯一写入点**）。
##   `stage_id` = 即将进入的关卡（"" → 用 `campaign.current_stage()`）。
##   🔴 关掉 `DECK_BY_REGION_ENABLED` 时必须显式清空注入态：`card_packs` 的注入变量是
##      静态的，会跨局 / 跨测试残留 —— 老口径下读到一个残留的地区表就是"幽灵解锁"。
func _sync_deck_unlock(stage_id: String = "") -> void:
	# 🔴 必须 `and _campaign != null`：`CAMPAIGN_ENABLED=false` 时没有 `_campaign`，
	#    此时若仍把 region 口径打开，玩家只剩 core 一包且**没有任何途径**解锁其余 7 包
	#    （解锁数据源整个不存在）→ 内容全部不可达。没有关卡系统就必须退回全开。
	CardPacks.unlock_by_region = DECK_BY_REGION_ENABLED and _campaign != null
	if not CardPacks.unlock_by_region:
		CardPacks.set_region_progress([], "")
		return
	var sid: String = stage_id if stage_id != "" else _campaign.current_stage()
	CardPacks.set_region_progress(_campaign.cleared_regions(), CampaignData.region_of(sid))


## 需要选包 → 弹界面；不需要（已解锁 ≤ 必须选的数）→ 全带，直接开局。
func _open_pack_select() -> void:
	if _bs == null or _pack_select == null:
		return
	# 🔴 兜底同步：`restart_hook` / 主界面路径也可能走到这里，缺一次同步就会用旧地区表。
	_sync_deck_unlock()
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
		var wc: int = CampaignData.wave_count(sid)
		if _bs != null and _bs.wave_director != null:
			# 🆕 关卡波表：`set_stage` 成功 = 它已按**波表长度**接管波数控制；
			#    失败（开关关 / 无表）→ 退回按关卡表注入波数（旧行为）。
			_bs.wave_director.stage_waves_enabled = STAGE_WAVES_ENABLED
			if not _bs.wave_director.set_stage(sid, _campaign.regions_cleared()):
				_bs.wave_director.set_max_wave(wc)
		# 🆕 运行时换图：按当前关卡注入活动地图（未实现自动回落 tri-fissure）。
		var mid: String = CampaignData.resolve_map_id(sid)
		SpaceModel.set_active_map(mid)
		print("[boot] 本局关卡 %s（%s）· %d 波 · 地图 %s · S=%d%s" % [
			sid, String(st.get("name", "")), wc, SpaceModel.active_map_id,
			_campaign.regions_cleared(),
			"" if not STAGE_WAVES_ENABLED else "（波表）"])
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
		# 🆕 守住新地区 → 立刻把它并入卡包判据（下一局选包 / 图鉴都读同一份）。
		_sync_deck_unlock()


## 字符串拼接（`String.join` 只吃 PackedStringArray，这里避开隐式转换坑）
func _join(arr: Array, sep: String) -> String:
	var s := ""
	for i in arr.size():
		if i > 0:
			s += sep
		s += String(arr[i])
	return s
