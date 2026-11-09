extends SceneTree
##
## 卡面接入探针（headless）：验证批次② 新卡面能被 ui_style.card_art() 加载，
## 以及「不存在的卡 → 返回 null」的判空降级仍然成立。
## 运行：<godot> --headless --path . --script res://tools/probe_card_art_v2.gd
##
const _Style := preload("res://scripts/ui/ui_style.gd")


func _initialize() -> void:
	pass


func _process(_d: float) -> bool:
	var tex := _Style.card_art("Vanguard")
	print("[probe] Vanguard = ", tex)
	if tex == null:
		printerr("[probe] FAIL: 卡面未加载（检查 .png.import 是否已生成）")
		quit(1)
		return true
	print("[probe] size = ", tex.get_size())
	var missing := _Style.card_art("NoSuchCardBatch2")
	print("[probe] missing fallback = ", missing)
	if missing != null:
		printerr("[probe] FAIL: 缺图未降级为 null")
		quit(1)
		return true
	print("[probe] PASS: 新卡面已接入，判空降级正常")
	quit(0)
	return true
