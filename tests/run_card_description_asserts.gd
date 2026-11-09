extends SceneTree
const Text := preload("res://scripts/data/card_text.gd")
const TD := preload("res://scripts/data/tower_data.gd")
const Hover := preload("res://scripts/ui/card_hover.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	for table in [TD.TOWERS,TD.TOWERS_EXT]:
		for name in table:
			var definition: Dictionary = table[name]
			var summary := Text.describe(name)
			var detail := Text.details(name)
			check(not summary.is_empty() and not detail.is_empty(),name+" 有摘要与详情")
			check(summary.split("\n").size()==3,name+" 摘要保留三行")
			if String(definition["tag"])=="fire" and float(definition["dps"])>0.0:
				check(summary.contains("火焰") and summary.contains("引爆"),name+" 主效果未被冰冻覆盖")
				check(detail.contains("火焰：") and detail.contains("魔法伤害") and detail.contains("射程"),name+" 详情包含点火、引爆和基础属性")
			if float(definition["slow"])>0.0 and float(definition["dps"])>0.0:
				check(detail.contains("附加冰冻") and detail.contains("每层减速 10%") and detail.contains("10层冻结 2 秒"),name+" 如实显示当前附加冰冻机制")
				check(detail.contains("冻结时被击杀"),name+" 显示冻结击杀效果")
	check(Text.describe("Blaze").contains("近距范围点火"),"Blaze 不再被描述为纯减速塔")
	check(Text.details("Wildfire").contains("持续伤害") and Text.details("Wildfire").contains("火焰："),"复合火焰建筑不遗漏持续伤害")
	check(Text.details("Coil").contains("弹射 2 次"),"冰冻不覆盖弹射信息")
	check(Text.details("Avalanche").contains("溅射 1 个"),"冰冻不覆盖溅射信息")
	check(Text.details("Pyroclasm").contains("不自动攻击") and Text.details("Pyroclasm").contains("12") and Text.details("Pyroclasm").contains("半径 28"),"充能塔独立说明触发与范围")
	check(Text.details("Unknown")=="" and Text.details("")=="","未知卡不编造效果")
	var hover := Hover.new()
	root.add_child(hover)
	await process_frame
	for viewport in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size = viewport
		await process_frame
		var size: Vector2 = root.get_visible_rect().size
		var anchor := Rect2(size.x*0.5-130.0,90.0,260.0,280.0)
		hover.show_card("Blaze",anchor,"价格：12 废料",false,true)
		await process_frame
		hover.show_card("Blaze",anchor,"价格：12 废料",false,true)
		check(hover.body.text.contains(Text.details("Blaze")),"真实悬停面板使用完整详情")
		check(hover.panel.position.y>=0.0 and hover.panel.position.y+hover.panel.size.y<=size.y,"详情面板不超出窗口：%s" % viewport)
		if DisplayServer.get_name()!="headless" and viewport==Vector2i(1600,900):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://art/_review/card-description-blaze.png")
	hover.queue_free()
	await process_frame
	print("Card descriptions: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
