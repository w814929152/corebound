extends SceneTree
##
## UI 全页面截图（窗口模式 · 2026-11-09）
##   一次跑完 9 个页面，各存一张 1600×900，供人工目检 + 接触表拼图。
##   与 probe_ui_squeeze_all.gd 同一套建页逻辑（那边出判据，这边出图）。
## 运行：<godot> --path . --script res://tools/shoot_ui_all.gd
## 产物：art/_review/ui_all/<序号>_<页名>.png
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")
const _PackSelect := preload("res://scripts/ui/pack_select_overlay.gd")
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")
const _Result := preload("res://scripts/ui/result_overlay.gd")
const _TowerDialog := preload("res://scripts/ui/disabled_tower_dialog.gd")
const _SalvageDialog := preload("res://scripts/ui/salvage_confirm_dialog.gd")
const _Campaign := preload("res://scripts/gameplay/campaign.gd")

const SETTLE := 26
const OUT_DIR := "res://art/_review/ui_all/"

var _page := 0
var _wait := 0
var _built := false

var _pages := ["menu", "library", "pack_select", "battle_shop", "stage_map",
	"result_won", "result_lost", "dialog_disabled", "dialog_salvage"]


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < SETTLE:
		return false
	_wait = 0
	if not _built:
		if _page >= _pages.size():
			print("[done] ", _pages.size(), " 页")
			return true
		_build(_page)
		_built = true
		return false
	_shot("%02d_%s.png" % [_page + 1, _pages[_page]])
	_clear()
	_page += 1
	_built = false
	return false


func _build(i: int) -> void:
	match i:
		0:
			var m = _MainMenu.new()
			root.add_child(m)
			m.open()
		1:
			var m = _MainMenu.new()
			root.add_child(m)
			m.open()
			m.show_library()
		2:
			var p = _PackSelect.new()
			root.add_child(p)
			p.open()
		3:
			var ps: PackedScene = load("res://scenes/battle_shop.tscn")
			var inst := ps.instantiate()
			root.add_child(inst)
			var dir := _find_with_method(inst, "open_shop")
			if dir != null:
				dir.call("open_shop")
		4:
			var s = _StageSelect.new()
			root.add_child(s)
			s.open(_Campaign.new())
		5:
			var r = _Result.new()
			root.add_child(r)
			r.show_result(true, 12, 780.0, 1000.0, 640.0)
		6:
			var r = _Result.new()
			root.add_child(r)
			r.show_result(false, 8, 0.0, 1000.0, 320.0)
		7:
			var d = _TowerDialog.new()
			root.add_child(d)
			d.show_towers([
				{"slot": 1, "invested": 240.0, "repair_cost": 60, "attach_layers": 2, "can_repair": true},
				{"slot": 3, "invested": 80.0, "repair_cost": 20, "attach_layers": 0, "can_repair": false},
				{"slot": 6, "invested": 520.0, "repair_cost": 130, "attach_layers": 4, "can_repair": true},
			])
		8:
			var d = _SalvageDialog.new()
			root.add_child(d)
			d.show_confirm("拆除回收", "拆掉 Frost（等级 3）返还 42 废料，占用的塔位会一并释放。")


func _shot(fname: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + fname)
	print("[shot] ", OUT_DIR + fname)


func _clear() -> void:
	for ch in root.get_children():
		root.remove_child(ch)
		ch.free()


func _find_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for ch in n.get_children():
		var r := _find_with_method(ch, m)
		if r != null:
			return r
	return null
