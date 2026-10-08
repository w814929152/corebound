extends SceneTree
##
## headless 八槽端到端冒烟（`geo8smoke` 入口）—— 阶段1 接入验证
##
## 🔴 使命：证明 n_slots=8 能端到端跑通（Geo8 → RunLoop → shop AI 落 8 塔 →
##    波次跑完 → DPS 正常 → 无数组越界），为 #74 数值扫参铺路。
##    这是**冒烟**（能跑通、不崩、8 槽被真正使用），不是**平衡定稿**。
##
## 判据：
##   S-G8-1  geo.n == 8
##   S-G8-2  RunLoop.run 八槽能跑完（rows 非空、波次推进）
##   S-G8-3  shop AI 落塔用到 slot 6/7（八槽被真正使用，非退化成六槽）
##   S-G8-4  所有塔位索引落在 [0,8)（无越界）
##   S-G8-5  DPS 为正、核心 HP 未归零（能打出伤害）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_geo8_smoke.gd
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _RunLoop = preload("res://scripts/engine/run_loop.gd")
const _Geo6 = preload("res://scripts/geo/geo6.gd")
const _PyRandom = preload("res://scripts/engine/py_random.gd")
var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段1 · 八槽端到端冒烟（n_slots=8）")
	print("===================================================================")

	# 构造八槽 cfg：先取 B 路径定稿 cfg，再改 n_slots=8（n_slots 非冻结项）
	var cfg: Dictionary = _Cfg.cfg_of("B")
	cfg["n_slots"] = 8
	print("  cfg.n_slots = %d · max_towers = %s" % [int(cfg["n_slots"]), str(cfg.get("max_towers"))])

	var geo = _Geo6.build_by_slots(int(cfg["n_slots"]))
	_ok("S-G8-1 geo.n == 8", geo.n == 8)
	print("  geo.slots.size() = %d" % geo.slots.size())

	var rng := _PyRandom.new(20260930)
	var res: Dictionary = _RunLoop.run("B", cfg, 20, geo, rng)
	var rows: Array = res["rows"]
	_ok("S-G8-2 RunLoop 八槽跑完（rows 非空）", rows.size() > 0)
	print("  跑完波数 = %d" % rows.size())

	# 收集所有出现过的塔位索引
	var used_slots: Array = []
	var max_towers_seen: int = 0
	var last_row: Dictionary = rows[rows.size() - 1]
	for row in rows:
		max_towers_seen = maxi(max_towers_seen, int(row.get("towers", 0)))
	var player = res["player"]
	for t in player.towers:
		var s: int = int(t.slot)
		if not used_slots.has(s):
			used_slots.append(s)
	used_slots.sort()
	print("  用到的塔位索引 = %s" % str(used_slots))
	print("  最大同时塔数 = %d" % max_towers_seen)

	# S-G8-3 用到 slot 6/7（八槽被真正使用）
	_ok("S-G8-3 shop AI 落塔用到 slot 6", used_slots.has(6))
	_ok("S-G8-3 shop AI 落塔用到 slot 7", used_slots.has(7))

	# S-G8-4 所有塔位索引落在 [0,8)
	var in_range_ok := true
	for s in used_slots:
		if s < 0 or s >= 8:
			in_range_ok = false
	_ok("S-G8-4 塔位索引全在 [0,8)（无越界）", in_range_ok)

	# S-G8-5 DPS 为正、核心未归零
	var last_dps: float = float(last_row.get("eff_dps", 0.0))
	var last_core_hp: float = float(last_row.get("core_hp", 0.0))
	_ok("S-G8-5 末波 DPS 为正", last_dps > 0.0)
	_ok("S-G8-5 末波核心 HP 未归零", last_core_hp > 0.0)
	print("  末波 eff_dps=%.1f · core_hp=%.1f" % [last_dps, last_core_hp])

	print("\n===================================================================")
	print("八槽端到端冒烟汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)
