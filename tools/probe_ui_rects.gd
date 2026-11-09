extends SceneTree
##
## UI 排版探针（逻辑视口 1920×1080 下的真实矩形）
##   Ⅰ 图鉴页：每张卡片的 global_rect → 查「同包卡宽不一致 / 溢出格子 / 贴底」
##   Ⅱ 主菜单：三入口按钮矩形 → 查「宽高 / 间距一致性」
##   Ⅲ 字号清单：递归扫 Label / Button 的 font_size → 查低于 FONT_MIN 的漏网
## 运行：<godot> --path . --script res://tools/probe_ui_rects.gd
##
## 🔴 注意：逻辑视口是 1920×1080，窗口 1600×900 只是 canvas_items 等比缩放（×0.833）。
##    若把 get_global_rect() 的数值当成屏幕像素去和窗口比，会误判「溢出屏幕」。
##
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")

var _f := 0
var _menu: CanvasLayer = null
var _hits := PackedStringArray()


func _initialize() -> void:
	_menu = _MainMenu.new()
	root.add_child(_menu)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		_menu.open()
	if _f == 30:
		_probe_menu()
		_menu.show_library()
	if _f == 60:
		_probe_library()
		_probe_fonts()
		_probe_squeeze_report()
		return true
	return false


func _probe_squeeze_report() -> void:
	print("\n=== Ⅳ 内容被压（需要的最小尺寸 > 实得尺寸）===")
	_hits.clear()
	_probe_squeeze(_menu, "menu")
	if _hits.is_empty():
		print("  ✅ 无（图鉴页 + 主菜单页）")
	else:
		for h in _hits:
			print("  🔴 ", h)


## Ⅳ 内容被压检测：容器给子项的宽度 **小于** 子项自身需要的最小宽
##   ⇒ 文本会被裁 / 溢出到邻居。这是「卡宽不齐」「卡名穿到隔壁」的共同真因，
##   图鉴那一批就是从这条判据抓出来的。ScrollContainer 的内容天然超宽，跳过。
func _probe_squeeze(n: Node, path: String) -> void:
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
				_hits.append("%s/%s  需要 %.0fx%.0f 实得 %.0fx%.0f" % [
					path, k.name, need.x, need.y, got.x, got.y])
	for ch in n.get_children():
		_probe_squeeze(ch, path)


func _probe_menu() -> void:
	print("\n=== Ⅰ 主菜单入口按钮 ===")
	var btns: Array = _menu._menu_buttons
	for i in btns.size():
		var b: Button = btns[i]
		var r := b.get_global_rect()
		print("  [%d] %-6s x=%.1f y=%.1f w=%.1f h=%.1f" % [
			i, b.text, r.position.x, r.position.y, r.size.x, r.size.y])
	for i in range(1, btns.size()):
		var a: Button = btns[i - 1]
		var b: Button = btns[i]
		var gap := b.get_global_rect().position.y - a.get_global_rect().end.y
		print("  间距 %d→%d = %.1f" % [i - 1, i, gap])


func _probe_library() -> void:
	print("\n=== Ⅱ 图鉴卡片矩形（按包）===")
	var by_pack := {}
	for e in _menu._card_entries:
		var p := String(e["pack"])
		if not by_pack.has(p):
			by_pack[p] = []
		by_pack[p].append(e)
	for pid in by_pack.keys():
		var entries: Array = by_pack[pid]
		var widths := {}
		var minx := 1e9
		var maxx := -1e9
		var out := PackedStringArray()
		for e in entries:
			var r: Control = e["panel"]
			var gr := r.get_global_rect()
			minx = minf(minx, gr.position.x)
			maxx = maxf(maxx, gr.end.x)
			var w := snappedf(gr.size.x, 0.1)
			widths[w] = int(widths.get(w, 0)) + 1
			out.append("%s:%.1fx%.1f" % [e["card"], gr.size.x, gr.size.y])
		var ws := widths.keys()
		ws.sort()
		var flag := "  ✅ 等宽" if ws.size() == 1 else "  🔴 宽度不齐 %s" % str(ws)
		print("  %-8s 卡数=%2d  x∈[%.1f, %.1f]%s" % [pid, entries.size(), minx, maxx, flag])
		if ws.size() > 1:
			print("           ", ", ".join(out))


func _probe_fonts() -> void:
	print("\n=== Ⅲ 字号清单（低于 16 的漏网）===")
	var seen := {}
	_scan(_menu, seen)
	var keys := seen.keys()
	keys.sort()
	for k in keys:
		var mark := "  🔴 低于 FONT_MIN" if int(k) < 16 else ""
		print("  %2d px × %d%s" % [int(k), int(seen[k]), mark])


func _scan(n: Node, seen: Dictionary) -> void:
	if n is Label or n is Button:
		var c: Control = n
		if c.is_visible_in_tree():
			var fs := c.get_theme_font_size("font_size")
			seen[fs] = int(seen.get(fs, 0)) + 1
	for ch in n.get_children():
		_scan(ch, seen)
