extends SceneTree
##
## 类表面探针：列出切片3 用到的类在 4.7.2 上的真实方法 / 属性 / 常量。
## 跑法：<godot> --headless --path D:/roguedemo --script res://tools/introspect47.gd
##


func _initialize() -> void:
	var v := Engine.get_version_info()
	print("Godot ", v["string"])
	print("")

	_dump_class("Engine", ["time_scale", "get_process", "delta", "frame", "physics"])
	_dump_class("Time", ["tick", "unix"])
	_dump_class("SceneTree", ["paused", "process", "timer", "quit"])
	_dump_class("Node", ["process_mode", "process_priority"])
	_dump_class("Control", ["anchor", "offset", "preset", "size_flag", "layout", "grow"])
	_dump_class("MarginContainer", ["margin"])
	_dump_class("HBoxContainer", ["separation"])
	_dump_class("CanvasLayer", ["layer", "follow", "visible"])
	_dump_class("SubViewport", ["render", "update", "size"])
	print("---- @GlobalScope 的 Side / Inherit 枚举 ----")
	for c in ["SIDE_LEFT", "SIDE_TOP", "SIDE_RIGHT", "SIDE_BOTTOM"]:
		print("  ", c, " = ", ClassDB.class_get_integer_constant("@GlobalScope", c) if ClassDB.class_has_integer_constant("@GlobalScope", c) else "N/A")
	print("")
	print("---- Control.LayoutPreset 常量 ----")
	for c in ["PRESET_TOP_LEFT", "PRESET_FULL_RECT", "PRESET_RIGHT_WIDE", "PRESET_LEFT_WIDE", "PRESET_CENTER"]:
		print("  Control.", c, " = ", ClassDB.class_get_integer_constant("Control", c))
	print("")
	print("---- Node.ProcessMode 常量 ----")
	for c in ["PROCESS_MODE_INHERIT", "PROCESS_MODE_PAUSABLE", "PROCESS_MODE_WHEN_PAUSED", "PROCESS_MODE_ALWAYS", "PROCESS_MODE_DISABLED"]:
		print("  Node.", c, " = ", ClassDB.class_get_integer_constant("Node", c))
	print("")
	print("---- Control.SizeFlags 常量 ----")
	for c in ["SIZE_SHRINK_BEGIN", "SIZE_FILL", "SIZE_EXPAND", "SIZE_EXPAND_FILL", "SIZE_SHRINK_END"]:
		print("  Control.", c, " = ", ClassDB.class_get_integer_constant("Control", c))
	print("")
	print("---- Control.MouseFilter / LayoutMode ----")
	for c in ["MOUSE_FILTER_STOP", "MOUSE_FILTER_PASS", "MOUSE_FILTER_IGNORE", "LAYOUT_MODE_POSITION", "LAYOUT_MODE_ANCHORS", "LAYOUT_MODE_CONTAINER", "LAYOUT_MODE_UNCONTROLLED"]:
		print("  Control.", c, " = ", ClassDB.class_get_integer_constant("Control", c))
	quit(0)


func _dump_class(cls: String, keywords: Array) -> void:
	print("==== ", cls, " ====")
	var methods := ClassDB.class_get_method_list(cls, true)
	for m in methods:
		var n := str(m.get("name"))
		var hit := false
		for k in keywords:
			if n.to_lower().find(str(k).to_lower()) >= 0:
				hit = true
				break
		if hit:
			print("  fn  ", n, "(", _args(m), ")")
	var props := ClassDB.class_get_property_list(cls, true)
	for p in props:
		var n := str(p.get("name"))
		var hit := false
		for k in keywords:
			if n.to_lower().find(str(k).to_lower()) >= 0:
				hit = true
				break
		if hit:
			print("  prop ", n, " : ", p.get("type"), "  (usage ", p.get("usage"), ")")
	print("")


func _args(m: Dictionary) -> String:
	var out: Array = []
	for a in m.get("args", []):
		out.append(str(a.get("name")))
	return ", ".join(out)
