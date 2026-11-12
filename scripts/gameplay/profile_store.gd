extends RefCounted

const Campaign := preload("res://scripts/gameplay/campaign.gd")
const RunMeta := preload("res://scripts/gameplay/run_meta.gd")
const RunSave := preload("res://scripts/gameplay/run_save.gd")
const PATH := "user://profiles.save"
const SLOT_COUNT := 3
const VERSION := 1

var active := -1
var slots: Array = [{}, {}, {}]
var load_error: Error = OK
var _path: String


func _init(path: String = PATH) -> void:
	_path = path


func load_profiles(import_legacy: bool = true) -> void:
	if not FileAccess.file_exists(_path):
		if import_legacy and (FileAccess.file_exists(Campaign.SAVE_PATH)
				or FileAccess.file_exists(RunMeta.SAVE_PATH) or FileAccess.file_exists(RunSave.PATH)):
			var campaign := Campaign.new()
			campaign.load_save()
			var legacy := {
				"campaign": campaign.progress_snapshot(),
				"meta": RunMeta.progress_snapshot(),
				"run": RunSave.read(),
			}
			load_error = put(0, legacy, true)
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		load_error = FileAccess.get_open_error()
		return
	if file.get_length() > 4 * RunSave.MAX_BYTES:
		load_error = ERR_FILE_CORRUPT
		return
	var data = file.get_var(false)
	if file.get_error() != OK or not _valid(data):
		load_error = ERR_FILE_CORRUPT
		return
	active = data.active
	slots = data.slots


func get_slot(index: int) -> Dictionary:
	return slots[index].duplicate(true)


func put(index: int, profile: Dictionary, select: bool = false) -> Error:
	var updated := slots.duplicate()
	updated[index] = profile
	return _commit(updated, index if select else active)


func activate(index: int) -> Error:
	if slots[index].is_empty():
		return ERR_DOES_NOT_EXIST
	return _commit(slots, index)


func erase(index: int) -> Error:
	var updated := slots.duplicate()
	updated[index] = {}
	return _commit(updated, -1 if index == active else active)


func _commit(updated: Array, selected: int) -> Error:
	if load_error != OK:
		return load_error
	var data := {"version": VERSION, "active": selected, "slots": updated}
	if not _valid(data):
		return ERR_INVALID_DATA
	var result := RunSave.write_variant(data, _path)
	if result == OK:
		slots = updated
		active = selected
	return result


static func _valid(data) -> bool:
	if not data is Dictionary or data.get("version") != VERSION:
		return false
	if not data.get("slots") is Array or data.slots.size() != SLOT_COUNT:
		return false
	var selected = data.get("active")
	if not selected is int or selected < -1 or selected >= SLOT_COUNT:
		return false
	for profile in data.slots:
		if not profile is Dictionary:
			return false
		if profile.is_empty():
			continue
		var campaign = profile.get("campaign")
		var meta = profile.get("meta")
		var run = profile.get("run")
		if not campaign is Dictionary or not meta is Dictionary or not run is Dictionary:
			return false
		if not campaign.get("version") is int or not campaign.get("current_stage") is String \
			or not campaign.get("cleared") is Dictionary or not campaign.get("decks") is Dictionary \
			or not campaign.get("ember") is int:
			return false
		if not meta.is_empty() and (not meta.get("runs") is int or not meta.get("wins") is int
				or not meta.get("best_wave") is int or not meta.get("packs") is Array):
			return false
		if not run.is_empty() and not RunSave.is_valid(run):
			return false
	return selected == -1 or not data.slots[selected].is_empty()
