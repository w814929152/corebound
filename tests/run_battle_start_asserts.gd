extends SceneTree

const Runtime := preload("res://scripts/gameplay/shop_runtime.gd")

func _initialize() -> void:
	var rt = Runtime.new()
	for seed_value in range(50):
		rt.setup("B", seed_value)
		assert(rt.player.towers.is_empty())
		assert(rt.player.cards.is_empty())
		assert(rt.geo.slots.is_empty())
		assert(rt.scrap == 30.0)
		rt.start_wave(1)
		var building := -1
		for i in rt.offers.size():
			if Runtime._card_kind(String(rt.offers[i])) == "tower":
				building = i
				break
		assert(building >= 0)
		var cost: float = rt.price_at(building)
		assert(rt.buy(building))
		assert(rt.scrap == 30.0 - cost)
		assert(rt.player.towers.is_empty())
		assert(rt.begin_placement(0))
		assert(rt.confirm_placement_at(Vector2(6, 33)))
		assert(rt.player.towers.size() == 1)
		assert(rt.pending.is_empty())
	print("Battle start: 50 seeds passed (core only, gold, purchase, placement, reset)")
	quit()
