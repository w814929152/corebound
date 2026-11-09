extends SceneTree
##
## 卡面资产全量探针（headless · 批次①–⑪ 收官 / 2026-11-09）
##   遍历 art/2d/cards/*_v1_460.png，验证 ui_style.card_art() 能加载每一张、
##   引擎导入后的纹理尺寸为 460×460，且「不存在的卡 → null」的判空降级仍成立。
##   🔴 与 probe_card_art_v2.gd 的区别：v2 只查 Vanguard 单张，本探针查全部卡面。
##   2026-11-09 补入第 81 张（cinder 额外卡位 Pyroclasm）→ 期望数 80 → 81。
## 运行：<godot> --headless --path . --script res://tools/probe_card_art_all.gd
##
const _Style := preload("res://scripts/ui/ui_style.gd")

const EXPECT_COUNT := 81
const EXPECT_SIZE := Vector2(460.0, 460.0)


func _initialize() -> void:
	pass


func _process(_d: float) -> bool:
	var dir := DirAccess.open("res://art/2d/cards/")
	if dir == null:
		printerr("[probe] FAIL: 无法打开 res://art/2d/cards/")
		quit(1)
		return true
	var names: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("card_") and f.ends_with("_v1_460.png"):
			names.append(f.trim_prefix("card_").trim_suffix("_v1_460.png"))
	names.sort()
	print("[probe] 卡面文件数 = ", names.size(), "（期望 ", EXPECT_COUNT, "）")
	var fail: int = 0
	for nm in names:
		var tex := _Style.card_art(nm)
		if tex == null:
			printerr("[probe] FAIL 未加载: ", nm)
			fail += 1
			continue
		var sz: Vector2 = tex.get_size()
		if not sz.is_equal_approx(EXPECT_SIZE):
			printerr("[probe] FAIL 尺寸异常: ", nm, " ", sz)
			fail += 1
	if _Style.card_art("NoSuchCardXYZ") != null:
		printerr("[probe] FAIL: 缺图未降级为 null")
		fail += 1
	if names.size() != EXPECT_COUNT:
		printerr("[probe] FAIL: 卡面数量不是 ", EXPECT_COUNT)
		fail += 1
	print("[probe] 纹理样例 = ", names[0] if names.size() > 0 else "N/A",
			" | 加载成功 = ", names.size() - fail, " / ", names.size())
	print("[probe] ", "PASS" if fail == 0 else "FAIL", " · 失败项 = ", fail)
	quit(0 if fail == 0 else 1)
	return true
