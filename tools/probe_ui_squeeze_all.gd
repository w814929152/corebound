extends SceneTree
##
## 全页面 UI 排版体检（窗口模式 · 2026-11-09）
## ---------------------------------------------------------------------------
## 这不是截图脚本，是**判据脚本**：逐个搭起真实页面，递归检查
##   「容器给子项的尺寸 < 子项自身需要的最小尺寸」
## ⇒ 该子项的文本一定会被裁掉或溢出到邻居。这是「卡宽不齐」「卡名穿到隔壁」
##   「长文案顶破卡片」这一整类缺陷的共同真因，比肉眼看截图可靠。
##
## 另外顺带统计每页低于 FONT_MIN(16) 的字号 —— §5.4 规定正文不得低于 16。
##
## 运行：<godot> --path . --script res://tools/probe_ui_squeeze_all.gd
## 产物：纯 stdout 报告（无 PNG）。
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")
const _PackSelect := preload("res://scripts/ui/pack_select_overlay.gd")
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")
const _Result := preload("res://scripts/ui/result_overlay.gd")
const _TowerDialog := preload("res://scripts/ui/disabled_tower_dialog.gd")
const _SalvageDialog := preload("res://scripts/ui/salvage_confirm_dialog.gd")
const _Campaign := preload("res://scripts/gameplay/campaign.gd")

## 每页：建页 → 等 SETTLE 帧让容器排版完成 → 检测 → 清场。
const SETTLE := 24

var _page := 0
var _wait := 0
var _phase := 0            # 0 = 待建页 / 1 = 待检测
var _host: Node = null     # 当前页根节点（检测起点）
var _label := ""
var _fails := 0

var _pages := ["主菜单", "图鉴", "卡包选择", "战斗商店", "选关航图",
	"结算·胜", "结算·负", "禁用塔弹窗", "拆除回收弹窗"]


func _initialize() -> void:
	pass


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < SETTLE:
		return false
	_wait = 0
	if _phase == 0:
		if _page >= _pages.size():
			_summary()
			return true
		_build(_page)
		_label = _pages[_page]
		_phase = 1
		return false
	# 检测
	_check()
	_clear()
	_page += 1
	_phase = 0
	return false


func _build(i: int) -> void:
	match i:
		0:
			var m = _MainMenu.new()
			root.add_child(m)
			m.open()
			_host = m
		1:
			var m = _MainMenu.new()
			root.add_child(m)
			m.open()
			m.show_library()
			_host = m
		2:
			var p = _PackSelect.new()
			root.add_child(p)
			p.open()
			_host = p
		3:
			var ps: PackedScene = load("res://scenes/battle_shop.tscn")
			var inst := ps.instantiate()
			root.add_child(inst)
			var dir := _find_with_method(inst, "open_shop")
			if dir != null:
				dir.call("open_shop")
			_host = inst
		4:
			var s = _StageSelect.new()
			root.add_child(s)
			var c = _Campaign.new()
			s.open(c)
			_host = s
		5:
			var r = _Result.new()
			root.add_child(r)
			r.show_result(true, 12, 780.0, 1000.0, 640.0)
			_host = r
		6:
			var r = _Result.new()
			root.add_child(r)
			r.show_result(false, 8, 0.0, 1000.0, 320.0)
			_host = r
		7:
			var d = _TowerDialog.new()
			root.add_child(d)
			d.show_towers([
				{"slot": 1, "invested": 240.0, "repair_cost": 60, "attach_layers": 2, "can_repair": true},
				{"slot": 3, "invested": 80.0, "repair_cost": 20, "attach_layers": 0, "can_repair": false},
				{"slot": 6, "invested": 520.0, "repair_cost": 130, "attach_layers": 4, "can_repair": true},
			])
			_host = d
		8:
			var d = _SalvageDialog.new()
			root.add_child(d)
			d.show_confirm("拆除回收", "拆掉 Frost（等级 3）返还 42 废料，占用的塔位会一并释放。")
			_host = d


func _check() -> void:
	var hits := PackedStringArray()
	_walk(_host, "", hits)
	var fonts := {}
	_walk_font(_host, fonts)
	var low := PackedStringArray()
	for k in fonts.keys():
		if int(k) < 16:
			low.append("%dpx×%d" % [int(k), int(fonts[k])])
	var tag := "✅" if hits.is_empty() and low.is_empty() else "🔴"
	if tag == "🔴":
		_fails += 1
	print("\n[%s] %s" % [tag, _label])
	for h in hits:
		print("   被压  ", h)
	if not low.is_empty():
		print("   小字号 ", ", ".join(low))


func _walk(n: Node, path: String, hits: PackedStringArray) -> void:
	if n is ScrollContainer:
		return
	var c := n as Control
	if c != null:
		for ch in c.get_children():
			var k := ch as Control
			if k == null or not k.is_visible_in_tree():
				continue
			var need := k.get_combined_minimum_size()
			var got := k.size
			if need.x > got.x + 1.0 or need.y > got.y + 1.0:
				hits.append("%s/%s  需要 %.0fx%.0f 实得 %.0fx%.0f" % [
					path, k.name, need.x, need.y, got.x, got.y])
	for ch in n.get_children():
		_walk(ch, path + "/" + String(n.name), hits)


func _walk_font(n: Node, seen: Dictionary) -> void:
	if n is Label or n is Button:
		var c: Control = n
		if c.is_visible_in_tree():
			var fs := c.get_theme_font_size("font_size")
			seen[fs] = int(seen.get(fs, 0)) + 1
	for ch in n.get_children():
		_walk_font(ch, seen)


func _summary() -> void:
	print("\n================ 合计 %d / %d 页有问题 ================" % [_fails, _pages.size()])


func _clear() -> void:
	for ch in root.get_children():
		root.remove_child(ch)
		ch.free()
	_host = null


func _find_with_method(n: Node, m: String) -> Node:
	if n.has_method(m):
		return n
	for ch in n.get_children():
		var r := _find_with_method(ch, m)
		if r != null:
			return r
	return null
