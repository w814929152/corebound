extends RefCounted
## A single suspended run. The permanent campaign and card-pack saves are separate.

const PATH := "user://suspended_run.save"
const VERSION := 1
const MAX_BYTES := 1024 * 1024
const CampaignData := preload("res://scripts/data/campaign_data.gd")
const Packs := preload("res://scripts/data/card_packs.gd")
const Player := preload("res://scripts/engine/player_state.gd")
const Geo := preload("res://scripts/geo/geo.gd")
const TowerData := preload("res://scripts/data/tower_data.gd")
const Rng := preload("res://scripts/engine/py_random.gd")
const Config := preload("res://scripts/engine/mvp_config.gd")

const SHOP_FIELDS := ["wave", "scrap", "rerolls", "lock_index", "offers", "pending",
	"pending_cost", "counts"]
const PLAYER_FIELDS := ["n_hist_max", "income_mult", "bounty_scrap", "stackcap_bonus",
	"reroll_disc", "cards", "core_hp_max", "core_hp"]
const TOWER_FIELDS := ["slot", "ctype", "h", "range_merges", "range_facing", "attach",
	"disabled", "hp", "hp_max", "invested", "bounty_progress", "revive_t_disabled",
	"revive_used_w", "revived_ever", "death_exposed", "death_carry", "death_valid"]


static func capture(runtime, stage: String, packs: Array, next_wave: int, escalation: int) -> Dictionary:
	var towers: Array = []
	for tower in runtime.player.towers:
		towers.append(_capture_fields(tower, TOWER_FIELDS))
	return {
		"version": VERSION, "stage": stage, "packs": packs, "next_wave": next_wave,
		"escalation": escalation,
		"shop": _capture_fields(runtime, SHOP_FIELDS),
		"player": _capture_fields(runtime.player, PLAYER_FIELDS),
		"slots": runtime.geo.slots, "towers": towers,
		"rng": runtime.rng.mt, "rng_index": runtime.rng.mti,
	}


static func restore(runtime, data: Dictionary) -> void:
	# Caller has configured the map and initialized the runtime with the saved packs.
	runtime.geo = Geo.new(data.slots)
	_restore_fields(runtime, data.shop, SHOP_FIELDS)
	_restore_fields(runtime.player, data.player, PLAYER_FIELDS)
	for row in data.towers:
		var tower := Player.TowerState.new()
		_restore_fields(tower, row, TOWER_FIELDS)
		runtime.player.towers.append(tower)
	runtime.rng.mt = data.rng
	runtime.rng.mti = data.rng_index


static func read(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var data = file.get_var(false)
	if file.get_error() != OK or not data is Dictionary or not is_valid(data):
		return {}
	return data


static func write(data: Dictionary, path: String = PATH) -> Error:
	if not is_valid(data):
		return ERR_INVALID_DATA
	return write_variant(data, path)


static func write_variant(data: Dictionary, path: String) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_var(data, false)
	file.flush()
	var result := file.get_error()
	file.close()
	if written and result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	elif result == OK:
		result = ERR_FILE_CANT_WRITE
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result


static func clear(path: String = PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


static func _capture_fields(source: Object, fields: Array) -> Dictionary:
	var values := {}
	for field in fields:
		values[field] = source.get(field)
	return values


static func _restore_fields(target: Object, values: Dictionary, fields: Array) -> void:
	for field in fields:
		target.set(field, values[field])


static func _matches(values, sample: Object, fields: Array) -> bool:
	if not values is Dictionary:
		return false
	for field in fields:
		var value = values.get(field)
		if typeof(value) != typeof(sample.get(field)):
			return false
		if value is float and not is_finite(value):
			return false
	return true


static func is_valid(data: Dictionary) -> bool:
	if data.get("version") != VERSION or not data.get("stage") is String:
		return false
	if not CampaignData.has_stage(data.stage) or not data.get("next_wave") is int:
		return false
	if data.next_wave < 1 or data.next_wave > CampaignData.wave_count(data.stage):
		return false
	if not data.get("escalation") is int or data.escalation < 0:
		return false
	if not data.get("packs") is Array or data.packs.is_empty() or data.packs.size() > Packs.PICKS_PER_RUN:
		return false
	for pack in data.packs:
		if not pack is String or not Packs.has_pack(pack) or data.packs.count(pack) != 1:
			return false
	if not data.get("rng") is PackedInt64Array or data.rng.size() != Rng.N:
		return false
	if not data.get("rng_index") is int or data.rng_index < 0 or data.rng_index > Rng.N:
		return false
	if not _matches(data.get("player"), Player.new(), PLAYER_FIELDS) or not _valid_shop(data):
		return false
	if not data.get("slots") is Array or not data.get("towers") is Array:
		return false
	for position in data.slots:
		if not position is Vector2 or not position.is_finite():
			return false
	var occupied := {}
	for row in data.towers:
		if not _matches(row, Player.TowerState.new(), TOWER_FIELDS):
			return false
		if row.slot < 0 or row.slot >= data.slots.size() or occupied.has(row.slot):
			return false
		if not _is_tower(row.ctype) or row.h < 1:
			return false
		occupied[row.slot] = true
	return true


static func _valid_shop(data: Dictionary) -> bool:
	var shop = data.get("shop")
	if not shop is Dictionary or not shop.get("wave") is int:
		return false
	if shop.wave != maxi(1, data.next_wave - 1):
		return false
	if not shop.get("scrap") is float or not is_finite(shop.scrap):
		return false
	if not shop.get("rerolls") is int or shop.rerolls < 0 or not shop.get("counts") is Dictionary:
		return false
	if not shop.get("lock_index") is int or shop.lock_index < -1 or shop.lock_index >= Config.SHOP_SLOTS:
		return false
	if not shop.get("offers") is Array or shop.offers.size() != Config.SHOP_SLOTS:
		return false
	if not shop.get("pending") is Array or not shop.get("pending_cost") is Array:
		return false
	if shop.pending.size() != shop.pending_cost.size():
		return false
	for card in shop.offers + shop.pending:
		if not card is String or not _is_tower(card):
			return false
	for cost in shop.pending_cost:
		if not cost is float or not is_finite(cost):
			return false
	return true


static func _is_tower(card: String) -> bool:
	return TowerData.TOWERS.has(card) or TowerData.TOWERS_EXT.has(card)
