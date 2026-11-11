extends SceneTree

const Combat := preload("res://scripts/gameplay/tactical_combat.gd")
const Director := preload("res://scripts/gameplay/wave_director.gd")
const Runtime := preload("res://scripts/gameplay/shop_runtime.gd")
const Geo := preload("res://scripts/geo/geo.gd")
const Player := preload("res://scripts/engine/player_state.gd")
const Config := preload("res://scripts/engine/mvp_config.gd")
const CardText := preload("res://scripts/data/card_text.gd")
const Style := preload("res://scripts/ui/ui_style.gd")

class FixedMonster extends "res://scripts/gameplay/monster.gd":
	var location := Vector2.ZERO
	func pos(_speed: float, _length: float = 101.0) -> Vector2:
		return location

var failed := 0

func _initialize() -> void:
	quit(0 if run_all() else 1)

func check(label: String, ok: bool) -> void:
	print("[PASS] " if ok else "[FAIL] ", label)
	if not ok:
		failed += 1

func run_all() -> bool:
	failed = 0
	var runtime := Runtime.new()
	var director := Director.new()
	var player := Player.new()
	player.towers.append(Player.make_tower(0, "Scrapcannon", 1))
	runtime.player = player
	runtime.cfg = Config.cfg_of("B")
	runtime.geo = Geo.new([Vector2(12, 25)])
	director.bind_runtime(runtime)
	var target := FixedMonster.new()
	target.setup(0, "Swarm", false, 1000.0, 1.0, 10.0)
	target.location = Vector2(200, 25)
	var shots: Array = []
	director.scrap_shot.connect(func(_s, _p, _q, index): shots.append(index))
	director.monsters = [target]
	runtime.scrap = 3.0
	Combat.apply(director, 0.05)
	check("无射程内目标不扣费", runtime.scrap == 3.0 and shots.is_empty())
	target.location = Vector2(13, 25)
	Combat.apply(director, 0.05)
	var hp := target.hp
	check("一次重击只扣 2 废料且只发出一条弹道", runtime.scrap == 1.0 and hp < 970.0 and shots == [0])
	Combat.apply(director, 2.0)
	check("冷却完毕但余额不足时不扣费、不打伤害", runtime.scrap == 1.0 and target.hp == hp and shots.size() == 1)
	runtime.scrap = 4.0
	target.hp = 1.0
	var second := FixedMonster.new()
	second.setup(1, "Swarm", false, 1000.0, 1.0, 10.0)
	second.location = target.location
	director.monsters.append(second)
	Combat.apply(director, 0.05)
	check("补足废料后恢复开火；单体伤害不溢出", runtime.scrap == 2.0 and target.hp == 0.0 and second.hp == 1000.0 and shots == [0, 0])
	Combat.apply(director, 0.05)
	check("有余额也必须等冷却", runtime.scrap == 2.0 and second.hp == 1000.0)
	check("卡面有重炮贴图，悬停写明废料消耗", Style.card_art("Scrapcannon") != null and CardText.details("Scrapcannon").contains("2 废料"))
	director.free()
	return failed == 0
