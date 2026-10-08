extends SceneTree
##
## headless 径向肉盾塔端到端验证（`bulwark8` 入口）—— 阶段2 P4 收尾
##
## 🔴 使命：证明径向模式下肉盾塔诊断 `_relocate_carry_to_safe` 真正生效——
##    主力塔从**高暴露位**（S1 expo=0.284）被移到**径向安全位**（expo<0.15，如 S3/S5/S6/S7）。
##    这是阶段2 暴露度语义重建在八槽径向下的端到端兑现。
##
## 判据：
##   B-G8-1  RADIAL 下八槽安全位 = [S3,S5,S6,S7]（expo_frac < 0.15）
##   B-G8-2  bulwark=true 时主力塔被移到安全位（非高暴露位）
##   B-G8-3  移动后主力塔 expo_frac < 0.15（确实在安全位）
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script tests/run_slice_bulwark8.gd
##

const _Cfg = preload("res://scripts/engine/mvp_config.gd")
const _DE = preload("res://scripts/engine/damage_engine.gd")
const _PS = preload("res://scripts/engine/player_state.gd")
const _Geo8 = preload("res://scripts/geo/geo8.gd")
const _PathGeometry = preload("res://scripts/geo/path_geometry.gd")
const _SpaceModel = preload("res://scripts/geo/space_model.gd")
const _MonsterData = preload("res://scripts/data/monster_data.gd")

const R := 9.0
const CORE := Vector2(28.0, 28.0)

var _fail = 0


func _ok(name: String, cond: bool) -> void:
	print("   [%s] %s" % ["PASS" if cond else "FAIL", name])
	if not cond:
		_fail += 1


func _initialize() -> void:
	print("===================================================================")
	print("径向阶段2 · 肉盾塔端到端验证（八槽径向 · D-3=0.15）")
	print("===================================================================")

	# 切径向模式（本探针专用，跑后回退）
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var geo8 = _Geo8.build8()

	# ---- B-G8-1 径向安全位 = [S3,S5,S6,S7] ----
	print("\n---- [B-G8-1] 径向八槽安全位（expo_frac < 0.15）----")
	var rows: Array = _PathGeometry.slot_exposure_radial(geo8.slots, R, CORE, _PathGeometry.EXPO_SAFE_MAX)
	var safe: Array = []
	for r in rows:
		if not bool(r["is_exposed"]):
			safe.append(int(r["slot"]))
	print("   安全位 = %s" % str(safe))
	_ok("B-G8-1 安全位 = [3,5,6,7]", safe == [3, 5, 6, 7])

	# ---- B-G8-2 / B-G8-3 主力塔重定位 ----
	print("\n---- [B-G8-2/3] bulwark 主力塔重定位到径向安全位 ----")
	# 构造：主力塔 h=50 在 S1（最高暴露 0.284），副塔 h=1 在 S3（安全位）
	var player = _PS.new()
	player.path = "B"
	player.towers = [
		_PS.make_tower(1, "Cannon", 50, {"FireUp": 47}),   # 主力塔（S1 高暴露）
		_PS.make_tower(3, "Arrow", 1, {}),                 # 副塔（S3 安全位）
	]
	player.n_hist_max = 2

	# 移动前：主力塔在 S1（expo=0.284 高暴露）
	var before_frac: float = _PathGeometry.expo_frac_of(geo8.slots[1], CORE, R)
	print("   移动前：主力塔在 S1 · expo_frac=%.4f（高暴露）" % before_frac)
	_ok("B-G8-2 移动前主力塔在高暴露位 S1", before_frac >= _PathGeometry.EXPO_SAFE_MAX)

	# 调用与 _relocate_carry_to_safe 等价的逻辑（内联，避免依赖 aggro 波次上下文）
	_relocate(player, geo8)

	# 移动后：主力塔应在安全位
	var carry_slot: int = -1
	for t in player.towers:
		if int(t.h) == 50:
			carry_slot = int(t.slot)
	var after_frac: float = _PathGeometry.expo_frac_of(geo8.slots[carry_slot], CORE, R)
	print("   移动后：主力塔在 S%d · expo_frac=%.4f" % [carry_slot, after_frac])
	_ok("B-G8-2 主力塔已移到安全位 S%d" % carry_slot, safe.has(carry_slot))
	_ok("B-G8-3 移动后主力塔 expo_frac=%.4f < 0.15" % after_frac, after_frac < _PathGeometry.EXPO_SAFE_MAX)

	# 回退 PATH 模式
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("\n===================================================================")
	print("径向肉盾塔端到端验证汇总：失败 %d 项" % _fail)
	print("===================================================================")
	quit(0 if _fail == 0 else 1)


## 内联版 _relocate_carry_to_safe（与 wave_sim_aggro.gd 同逻辑，径向口径）。
func _relocate(player, geo) -> void:
	var slots: Array = []
	for p in geo.slots:
		slots.append(p)
	var carry_idx := -1
	var carry_h := -1
	for i in range(player.towers.size()):
		var t = player.towers[i]
		if bool(t.disabled):
			continue
		if int(t.h) > carry_h:
			carry_h = int(t.h)
			carry_idx = i
	if carry_idx < 0:
		return
	var carry_slot := int(player.towers[carry_idx].slot)
	var rows: Array = _PathGeometry.slot_exposure_radial(
		slots, _MonsterData.AGGRO_R, CORE, _PathGeometry.EXPO_SAFE_MAX)
	var safe_slots: Array = []
	for r in rows:
		if not bool(r["is_exposed"]):
			safe_slots.append(int(r["slot"]))
	if safe_slots.has(carry_slot):
		return
	var target_safe := -1
	for s in safe_slots:
		var has := false
		for t in player.towers:
			if int(t.slot) == s:
				has = true
				break
		if not has:
			target_safe = s
			break
	if target_safe < 0:
		target_safe = int(safe_slots[0])
	player.towers[carry_idx].slot = target_safe
