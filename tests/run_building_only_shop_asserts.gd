extends SceneTree

const RT := preload("res://scripts/gameplay/shop_runtime.gd")
const Packs := preload("res://scripts/data/card_packs.gd")
const PS := preload("res://scripts/engine/player_state.gd")

func _initialize() -> void:
	for mode in range(3):
		RT.set_active_packs(Packs.all_ids() if mode == 2 else [])
		RT.set_extended_pack(mode == 1)
		for nm in RT.player_card_names():
			assert(RT._card_kind(String(nm)) == "tower")
		assert(not RT.player_card_names().is_empty())
		var rt = RT.new()
		for seed_value in range(50):
			rt.setup("B", seed_value)
			# 有元素主塔时也不能通过波首保底重新注入效果卡。
			rt.player.towers.append(PS.make_tower(0, "Cannon", 1))
			for wave in range(1, 6):
				rt.start_wave(wave)
				assert(rt.pity_card_name() == "")
				check_offers(rt)
				rt.scrap = 1000.0
				for attempt in range(3):
					assert(rt.reroll())
					check_offers(rt)
	RT.set_active_packs([])
	RT.set_extended_pack(false)
	print("Building-only shop passed: base, extended, packs; 50 seeds x 5 waves x 4 deals")
	quit()

func check_offers(rt) -> void:
	assert(rt.offers.size() == 3)
	for nm in rt.offers:
		assert(RT._card_kind(String(nm)) == "tower")
