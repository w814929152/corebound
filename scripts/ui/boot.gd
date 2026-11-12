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
const StageExit := preload("res://scripts/ui/stage_exit_overlay.gd")
const MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")
const RunSave := preload("res://scripts/gameplay/run_save.gd")
const Profiles := preload("res://scripts/gameplay/profile_store.gd")
const ProfileOverlay := preload("res://scripts/ui/profile_overlay.gd")
const Confirm := preload("res://scripts/ui/salvage_confirm_dialog.gd")

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

var _stage_exit: CanvasLayer = null
var _bs: Node = null
var _pack_select: CanvasLayer = null
var _campaign = null
var _stage_select: CanvasLayer = null
var _main_menu: CanvasLayer = null
var _profiles: Profiles
var _profile_overlay: CanvasLayer
var _suspended_run: Dictionary = {}
var _settling_result := false
var _profile_write_failed := false
var _replace_dialog: CanvasLayer


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
		SpaceModel.terrain_enabled = true
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
		bs.wave_director.structure_attacks_enabled = true
		# 🔒 反制窗口 M-1（产品开关 · 与上面三开关同族）：战斗中即时被动复活。
		#    🔴 一行回滚：删掉下一行即退回默认（塔死亡只走安全窗三选一）。
		bs.wave_director.combat_revive_enabled = true
		# 🆕 战斗类型系统（物理/魔法 × 物抗/魔抗 · design/gdd/combat-types.md v0.1）。
		#    🔴 默认 false = 旧聚合池口径（金标本零扰动）；打开后塔按攻击类型拆分 DPS 池、
		#       怪物按原型抗性分别结算（Rush 魔抗 0.20 / Tank 物抗 0.30 / Swarm 双抗 0）。
		#    🔴 一行回滚：删掉下一行即退回旧口径。
		bs.wave_director.combat_types_enabled = true
		bs.wave_director.tactical_combat_enabled = CAMPAIGN_ENABLED
		bs.wave_director.mechanical_siege_enabled = CAMPAIGN_ENABLED
		print("[boot] proto/elite/aggro/revive/combat_types 全 ON（战斗类型系统 · RADIAL 实机口径）")
		print("[boot] SpaceModel.mode = RADIAL（径向核心围攻 · 实机默认）")
		print("[boot] Corebound MVP · 切片4（实时商店覆盖层 + 完整商店逻辑接线）")
		print("[boot] Tab 开关抽屉 · Esc 关闭/取消 · R 刷新 · 点击卡牌购买 · Space 锁定焦点位")
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
		bs.director.set_external_pause(true)
		add_child(_main_menu)
		_main_menu.start_requested.connect(_on_main_start)
		_main_menu.resume_requested.connect(_on_resume_run)
		_replace_dialog = Confirm.new()
		add_child(_replace_dialog)
		_replace_dialog.layer = MainMenu.LAYER + 1
		_replace_dialog.cancelled.connect(_open_main_menu)
		_main_menu.quit_requested.connect(_on_main_quit)
		# 🆕 关卡推进：加载存档（默认关 = 不注入波数，见 CAMPAIGN_ENABLED）。
		if CAMPAIGN_ENABLED:
			_profiles = Profiles.new()
			_profiles.load_profiles()
			_load_active_profile()
			_profile_overlay = ProfileOverlay.new()
			add_child(_profile_overlay)
			_profile_overlay.closed.connect(_open_main_menu)
			_profile_overlay.selected.connect(_on_profile_selected)
			_profile_overlay.save_requested.connect(_on_profile_saved)
			_profile_overlay.delete_requested.connect(_on_profile_deleted)
			_main_menu.profiles_requested.connect(_open_profiles)
			_main_menu.set_profiles_enabled(true)
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
			_stage_select.back_requested.connect(_on_stage_back)
		# 🔴 启动第一屏一律是主界面（选关 / 选包由「开始游戏」触发）。
		_stage_exit = StageExit.new()
		_stage_exit.director = bs.director
		add_child(_stage_exit)
		_stage_exit.exit_confirmed.connect(_on_stage_exit)
		_stage_exit.can_save = _can_save_run
		_stage_exit.save_requested.connect(_on_save_and_exit)
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
		_main_menu.menu_blocked = false
		_main_menu.open()
		_refresh_save_status()


func _refresh_save_status() -> void:
	var data := _suspended_run
	_main_menu.set_active_profile(_profiles.active if _profiles != null else -1, _profile_write_failed)
	if not data.is_empty():
		var stage: Dictionary = CampaignData.STAGES[data.stage]
		_main_menu.set_save_status("%s · 准备第 %d / %d 波" % [
			stage.name, data.next_wave, CampaignData.wave_count(data.stage)], true)
	else:
		_main_menu.set_save_status("", false)


func _open_profiles() -> void:
	_main_menu.menu_blocked = true
	_profile_overlay.open(_profiles)


func _load_active_profile() -> void:
	_profile_write_failed = false
	var profile := _profiles.get_slot(_profiles.active) if _profiles.active >= 0 else {}
	_campaign = Campaign.new()
	_campaign.restore_progress(profile.get("campaign", {}))
	_campaign.save_hook = _persist_profile
	RunMeta.use_profile(profile.get("meta", {}), _persist_profile)
	_suspended_run = profile.get("run", {})
	_sync_deck_unlock()


func _profile_snapshot() -> Dictionary:
	return {"campaign": _campaign.progress_snapshot(),
		"meta": RunMeta.progress_snapshot(), "run": _suspended_run}


func _persist_profile(_progress: Dictionary = {}) -> Error:
	if _settling_result:
		return OK
	if _profiles.active < 0:
		return ERR_UNCONFIGURED
	var result := _profiles.put(_profiles.active, _profile_snapshot())
	_profile_write_failed = result != OK
	return result


func _on_profile_selected(slot: int) -> void:
	if _profile_write_failed and _persist_profile() != OK:
		_profile_overlay.open(_profiles, "当前进度还未写入，请检查存档目录后重试。")
		return
	var result: Error
	if _profiles.get_slot(slot).is_empty():
		result = _profiles.put(slot, {"campaign": Campaign.new().progress_snapshot(), "meta": {}, "run": {}}, true)
	else:
		result = _profiles.activate(slot)
	if result != OK:
		_profile_overlay.open(_profiles, "无法读取或创建该存档，请检查存档目录。")
		return
	_load_active_profile()
	_profile_overlay.hide()
	_open_main_menu()


func _on_profile_saved(slot: int) -> void:
	var result := _persist_profile() if slot == _profiles.active else _profiles.put(slot, _profile_snapshot())
	_refresh_save_status()
	_profile_overlay.open(_profiles, "已保存到存档 %d。" % (slot + 1) if result == OK else "保存失败，请检查存档目录。")


func _on_profile_deleted(slot: int) -> void:
	var was_active := slot == _profiles.active
	var result := _profiles.erase(slot)
	if result == OK and was_active:
		_load_active_profile()
		_refresh_save_status()
	_profile_overlay.open(_profiles, "已删除存档 %d。" % (slot + 1) if result == OK else "删除失败，请检查存档目录。")


func _has_cmd_flag(flag: String) -> bool:
	return OS.get_cmdline_args().has(flag) or OS.get_cmdline_user_args().has(flag)


func _on_main_start() -> void:
	if _profiles != null and _profiles.active < 0:
		_open_profiles()
		return
	if not _suspended_run.is_empty():
		_main_menu.menu_blocked = true
		_replace_dialog.show_confirm("开始新挑战？",
			"新关卡开始时会清除当前的局内存档。",
			_open_new_run_selection, "开始新挑战")
		return
	_open_new_run_selection()


func _open_new_run_selection() -> void:
	if _main_menu != null:
		_main_menu.menu_blocked = false
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


func _on_stage_back() -> void:
	if _stage_select != null:
		_stage_select.close()
	if _main_menu != null:
		_open_main_menu()


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
	if not _suspended_run.is_empty() and _set_suspended_run({}) != OK:
		_open_main_menu()
		_main_menu.set_save_status("无法清除旧关卡记录，请检查存档目录。", true)
		return
	if CAMPAIGN_ENABLED and _campaign != null:
		_configure_battle(_campaign.current_stage(), _campaign.regions_cleared())
	ShopRuntime.set_active_packs(packs)
	_bs.director.set_external_pause(false)
	_bs.controller.start_new_run()
	if _stage_exit != null:
		_stage_exit.set_active(true)


func _configure_battle(sid: String, escalation: int) -> void:
	var wc := CampaignData.wave_count(sid)
	var wave_director = _bs.wave_director
	wave_director.stage_waves_enabled = STAGE_WAVES_ENABLED
	if not wave_director.set_stage(sid, escalation):
		wave_director.set_max_wave(wc)
	SpaceModel.set_active_map(CampaignData.resolve_map_id(sid))


func _can_save_run() -> bool:
	if _profiles == null or _profiles.active < 0 or _bs.controller.over:
		return false
	var wave_director = _bs.wave_director
	var next_wave: int = _bs.director.sm.wave + 1
	return next_wave <= CampaignData.wave_count(_campaign.current_stage()) and (
		wave_director.state == wave_director.State.IDLE
		or wave_director.state == wave_director.State.SAFE_WINDOW)


func _on_save_and_exit() -> void:
	if not _can_save_run():
		return
	var data := RunSave.capture(_bs.controller.runtime, _campaign.current_stage(),
		ShopRuntime.active_pack_ids(), _bs.director.sm.wave + 1, _bs.wave_director.escalation)
	if _set_suspended_run(data) != OK:
		_stage_exit.show_error("存档写入失败，请检查存档目录后重试。")
		return
	_bs.controller.abandon_run()
	_stage_exit.set_active(false)
	_open_main_menu()


func _set_suspended_run(data: Dictionary) -> Error:
	var previous := _suspended_run
	_suspended_run = data
	var result := _persist_profile()
	if result != OK:
		_suspended_run = previous
	return result


func _on_resume_run() -> void:
	var data := _suspended_run
	if data.is_empty():
		_refresh_save_status()
		return
	if _set_suspended_run({}) != OK:
		_main_menu.set_save_status("无法读取并移交存档，请检查存档目录后重试。", true)
		return
	_campaign.set_current_stage(data.stage)
	_sync_deck_unlock(data.stage)
	_configure_battle(data.stage, data.escalation)
	ShopRuntime.set_active_packs(data.packs)
	_main_menu.close()
	_bs.controller.restore_run(data)
	_bs.director.set_external_pause(false)
	_stage_exit.set_active(true)



func _on_run_finished(won: bool, wave: int) -> void:
	if _stage_exit != null:
		_stage_exit.set_active(false)
	_settling_result = _profiles != null
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
			_bs.controller.campaign_result = r.duplicate(true)
			if r.get("ok", false):
				var bits: Array = []
				bits.append("余烬 +%d" % int(r.get("ember_gained", 0)))
				if String(r.get("unlocked_stage", "")) != "":
					bits.append("解锁 %s" % String(r.get("unlocked_stage", "")))
				if String(r.get("unlocked_deck", "")) != "":
					bits.append("解锁卡组 %s" % String(r.get("unlocked_deck", "")))
				print("[boot] 关卡推进 · %s · %s" % [sid, _join(bits, " · ")])
		else:
			var r: Dictionary = _campaign.on_failed(sid, wave)
			_bs.controller.campaign_result = r.duplicate(true)
			if r.get("ok", false):
				print("[boot] 关卡推进 · %s 失败 · 余烬 +%d" % [sid, int(r.get("ember_gained", 0))])
		# 🆕 守住新地区 → 立刻把它并入卡包判据（下一局选包 / 图鉴都读同一份）。
		_sync_deck_unlock()
	if _settling_result:
		_settling_result = false
		_persist_profile()


## 字符串拼接（`String.join` 只吃 PackedStringArray，这里避开隐式转换坑）
func _join(arr: Array, sep: String) -> String:
	var s := ""
	for i in arr.size():
		if i > 0:
			s += sep
		s += String(arr[i])
	return s


func _on_stage_exit() -> void:
	if _bs == null:
		return
	_bs.controller.abandon_run()
	if _stage_exit != null:
		_stage_exit.set_active(false)
	if CAMPAIGN_ENABLED:
		_open_stage_select()
	else:
		_open_main_menu()
