extends SceneTree

const Space := preload("res://scripts/geo/space_model.gd")
const TSM := preload("res://scripts/engine/time_state_machine.gd")

func _initialize() -> void:
	call_deferred("run")

func key_tab() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	root.push_input(key, true)

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func run() -> void:
	Space.mode = Space.Mode.RADIAL
	var scene = load("res://scenes/battle_shop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var rt = scene.controller.runtime
	var td = scene.director
	var shop = scene.get_node("ShopLayer/ShopOverlay")
	var backpack = scene.tower_backpack
	var ml = scene.get_node("Battlefield/MonsterLayer")
	rt.scrap = 100.0
	rt.toggle_lock(0)
	var before: Array = rt.offers.duplicate()
	var cost: float = rt.price_at(0)
	shop._slot_buy[0].grab_focus()
	shop._slot_buy[0].pressed.emit()
	assert(rt.offers[0] != before[0])
	assert(rt.offers.slice(1) == before.slice(1))
	assert(rt.scrap == 100.0 - cost and rt.rerolls == 0)
	assert(rt.lock_index == -1)
	assert(rt.pending == [before[0]])
	assert(backpack._pending == rt.pending)
	# 焦点在购买按钮时，真实输入分发仍应优先执行商店开关。
	key_tab()
	assert(not shop.visible)
	assert(td.sm.state == TSM.State.SAFE_WINDOW and paused)
	key_tab()
	assert(shop.visible)
	shop._slot_buy[0].pressed.emit()
	assert(rt.pending.size() == 2 and backpack._pending.size() == 2)
	# 从关闭的商店状态拖放，成功后仅消费所拖的那一张，界面同步更新。
	key_tab()
	var remaining: String = String(rt.pending[1])
	mouse_button(backpack.position + Vector2(150,60), true)
	assert(backpack._drag_index == 0)
	assert(td.sm.state == TSM.State.PLACEMENT_MODE)
	mouse_button(ml.world_to_screen(Vector2(12,33)), false)
	assert(rt.pending == [remaining])
	assert(backpack._pending == [remaining])
	assert(rt.pending_cost.size() == 1)
	assert(rt.player.towers.size() == 1 and rt.player.towers[0].h == 1)
	assert(rt.last_error == "")
	assert(backpack._drag_index == -1 and td.sm.state == TSM.State.SAFE_WINDOW)
	# 核心禁建区落子失败必须退卡，不能误消费。
	mouse_button(backpack.position + Vector2(150,60), true)
	mouse_button(ml.world_to_screen(Space.RADIAL_CORE), false)
	assert(rt.pending == [remaining] and backpack._pending == [remaining])
	assert(rt.player.towers.size() == 1)
	# 再买一张同类塔，拖到已有塔升级；保留另一商品位的锁定。
	rt.offers[0] = rt.player.towers[0].ctype
	rt.lock_index = 2
	rt.scrap = 100.0
	scene.controller._on_buy_requested(0)
	assert(rt.lock_index == 2)
	assert(backpack._pending.size() == 2)
	mouse_button(backpack.position + Vector2(112 + backpack.CARD_W + backpack.GAP + 30,60), true)
	assert(backpack._drag_index == 1)
	mouse_button(ml.world_to_screen(Vector2(12,33)), false)
	assert(rt.player.towers.size() == 1 and rt.player.towers[0].h == 2)
	assert(rt.pending == [remaining] and backpack._pending == [remaining])
	assert(rt.pending_cost.size() == 1 and rt.last_error == "")
	# 买不起时不换牌、不扣费、不改变背包。
	rt.scrap = 0.0
	before = rt.offers.duplicate()
	assert(not rt.buy(0))
	assert(rt.offers == before and rt.pending == [remaining])
	print("Shop interactions passed: replacement, focused Tab, real drag/drop, view sync, invalid drop, failed purchase")
	paused = false
	quit()
