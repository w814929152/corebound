extends SceneTree
const Camera := preload("res://scripts/ui/battlefield_camera.gd")
const Maps := preload("res://scripts/data/battlefield_maps.gd")
const Space := preload("res://scripts/geo/space_model.gd")
const Grid := preload("res://scripts/geo/build_grid.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func motion(point: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = mask
	root.push_input(event,true)
	await process_frame

func button(point: Vector2, which: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = which
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame

func run() -> void:
	Space.mode = Space.Mode.RADIAL
	Space.terrain_enabled = true
	Space.set_active_map("tri-fissure")
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	scene.auto_start_run = false
	root.add_child(scene)
	scene.controller.start_new_run()
	scene.director.close_shop()
	scene.get_node("TutorialLayer/TutorialOverlay")._on_skip_pressed()
	await process_frame
	var nav = scene.get_node("BattlefieldNavigation")
	var ml = scene.get_node("Battlefield/MonsterLayer")
	var vfx = scene.get_node("Battlefield/VfxLayer")
	check(Maps.boundary("tri-fissure")[0].distance_to(Maps.CORE)>100,"场地的实际世界尺寸已扩大")
	check(Grid.all_cells().size()>1800,"扩大后的地面可以布防")
	for viewport in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size = viewport
		await process_frame
		nav.reset_view()
		var size: Vector2 = root.get_visible_rect().size
		var center := Camera.view_rect(size).get_center()
		var anchor := center+Vector2(60,-40)
		await motion(anchor)
		var world_anchor: Vector2 = ml.screen_to_world_position(anchor)
		await button(anchor,MOUSE_BUTTON_WHEEL_UP,true)
		check(Camera.zoom>Camera.DEFAULT_ZOOM,"滚轮放大：%s" % viewport)
		check(ml.world_to_screen(world_anchor).distance_to(anchor)<0.01,"鼠标所指地面缩放时保持原位")
		check(ml.world_to_screen(world_anchor).distance_to(vfx._to_screen(world_anchor))<0.01,"缩放后特效与地形一致")
		var before: Dictionary = ml._xform()
		scene.director.open_shop()
		check(before==ml._xform(),"开商店保留平移和缩放")
		await process_frame
		var shop_panel = scene.get_node("ShopLayer/ShopOverlay")._panel
		var shop_point: Vector2 = shop_panel.get_global_rect().get_center()
		await motion(shop_point)
		var shop_zoom := Camera.zoom
		await button(shop_point,MOUSE_BUTTON_WHEEL_DOWN,true)
		check(Camera.zoom==shop_zoom,"商店浮层上的滚轮不缩放地图")
		scene.director.close_shop()
		await motion(center)
		var initial: Vector2 = ml.world_to_screen(Maps.CORE)
		await button(center,MOUSE_BUTTON_LEFT,true)
		await motion(center+Vector2(70,30),MOUSE_BUTTON_MASK_LEFT)
		await button(center+Vector2(70,30),MOUSE_BUTTON_LEFT,false)
		check(ml.world_to_screen(Maps.CORE).distance_to(initial+Vector2(70,30))<0.01,"左键拖动地图")
		check(nav._drag_button==0,"松开鼠标结束拖动")
		# 背包区域的滚轮不缩放地图。
		var backpack = scene.tower_backpack
		var over_bag: Vector2 = backpack.position+Vector2(170,55)
		var saved_zoom := Camera.zoom
		await motion(over_bag)
		await button(over_bag,MOUSE_BUTTON_WHEEL_DOWN,true)
		check(Camera.zoom==saved_zoom,"背包滚轮不传给地图")
		# 镜头变动也要重投影已经出现的伤害数字。
		vfx._spawn_dmg(Maps.CORE,10.0,100.0)
		var damage_entry: Dictionary = vfx._dmg.back()
		var damage_world: Vector2 = ml.screen_to_world_position(damage_entry["base"])
		nav._zoom(1.15,center)
		check(Vector2(damage_entry["base"]).distance_to(ml.world_to_screen(damage_world))<0.01,"已有伤害数字跟随镜头")
		# 镜头边界和缩放上限，避免拖丢地图或无限放大。
		Camera.zoom_at(100.0,center,size)
		Camera.pan(Vector2(100000,-100000),size)
		nav._refresh()
		check(Camera.zoom==Camera.MAX_ZOOM and Camera.focus.distance_to(Maps.CORE)<150,"缩放和平移上限有效")
		Camera.zoom_at(0.00001,center,size)
		check(Camera.zoom==Camera.MIN_ZOOM,"缩放下限有效")
		nav.reset_view()
		check(Camera.focus==Maps.CORE and Camera.zoom==Camera.DEFAULT_ZOOM,"回到核心恢复初始视角")
	# 在缩放和平移后，从真实背包拖卡到扩展区域。
	scene.controller.runtime.scrap = 100.0
	scene.controller._on_buy_requested(0)
	await process_frame
	var rt = scene.controller.runtime
	var backpack = scene.tower_backpack
	await motion(backpack.position+Vector2(150,60))
	await button(backpack.position+Vector2(150,60),MOUSE_BUTTON_LEFT,true)
	check(ml._in_placement(),"拖出卡牌进入放置状态")
	var focus_before := Camera.focus
	var place_center := Camera.view_rect(root.get_visible_rect().size).get_center()
	await motion(place_center)
	await button(place_center,MOUSE_BUTTON_MIDDLE,true)
	await motion(place_center+Vector2(-170,0),MOUSE_BUTTON_MASK_MIDDLE|MOUSE_BUTTON_MASK_LEFT)
	await button(place_center+Vector2(-170,0),MOUSE_BUTTON_MIDDLE,false)
	check(Camera.focus!=focus_before and ml._in_placement(),"放置中可用中键平移，不取消卡牌")
	var target := Grid.snap(Maps.CORE+Vector2(73,2))
	check(Grid.buildable(target),"原场地以外的新区域可建塔")
	var count: int = rt.player.towers.size()
	await motion(ml.world_to_screen(target),MOUSE_BUTTON_MASK_LEFT)
	await button(ml.world_to_screen(target),MOUSE_BUTTON_LEFT,false)
	check(rt.player.towers.size()==count+1 and rt.pending.is_empty(),"镜头移动后拖放仍精确落子并消费背包卡")
	check(Vector2(rt.geo.slots[rt.player.towers.back().slot]).distance_to(target)<0.01,"建塔位置与鼠标所指格点一致")
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	root.push_input(key,true)
	await process_frame
	check(Camera.focus==Maps.CORE and Camera.zoom==Camera.DEFAULT_ZOOM,"F 快捷键回到核心")
	# 结束手势的边界：失去窗口焦点后，移动鼠标不能继续拖动。
	await motion(place_center)
	await button(place_center,MOUSE_BUTTON_MIDDLE,true)
	nav._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var stopped_focus := Camera.focus
	await motion(place_center+Vector2(50,50))
	check(nav._drag_button==0 and Camera.focus==stopped_focus,"失去焦点结束地图拖动")
	await button(place_center,MOUSE_BUTTON_MIDDLE,false)
	# 清理测试注入的伤害数字，预览只展示真实场景。
	vfx._dmg.clear()
	vfx._dmg_grid.clear()
	vfx._dmg_by_owner.clear()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/_review/navigation-default.png")
		nav._bar.get_child(3).pressed.emit()
		check(is_equal_approx(Camera.zoom,1.0/Camera.CLOSE_VIEW),"总览按钮显示完整地图")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/_review/navigation-overview.png")
		nav._zoom(2.0,place_center)
		Camera.pan(Vector2(-180,80),root.get_visible_rect().size)
		nav._refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/_review/navigation-zoomed.png")
		nav._bar.get_child(4).pressed.emit()
		check(Camera.focus==Maps.CORE and Camera.zoom==Camera.DEFAULT_ZOOM,"回到核心按钮复位镜头")
	# 新开一局复位，波次和买卖等普通刷新不复位。
	nav._zoom(1.5,place_center)
	var kept := Camera.zoom
	scene.controller._emit_run()
	check(Camera.zoom==kept,"普通游戏刷新保留镜头")
	scene.controller.start_new_run()
	check(Camera.focus==Maps.CORE and Camera.zoom==Camera.DEFAULT_ZOOM,"新一局重置镜头")
	scene.queue_free()
	paused = false
	Space.terrain_enabled = false
	Camera.reset()
	await process_frame
	print("Battlefield navigation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
