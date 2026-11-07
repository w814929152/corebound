extends SceneTree
##
## 🟠 伤害数字视觉探针（非 CI · 手动跑 · **必须非 headless**）
##
## 目的：给「伤害数字显示优化」留**改前 / 改后同一脚本的对照帧**——
##   用真实 `VfxLayer` + 受控 snapshot 喂伤害，逐帧步进后截屏，并打印同屏条目/
##   文本/位置，便于人工判读「是否还散落一圈 1、是否压怪、同怪是否重复占格」。
##
## 跑法（🔴 不能加 --headless，否则拿不到纹理）：
##   <godot> --path . --script res://tests/probe_dmg_visual.gd -- <tag>
##   产物：G:/AI Demo/shots_dmg/<tag>-NN.png + 控制台条目转储
##

const _VFX := preload("res://scripts/ui/vfx_layer.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const OUT_DIR := "G:/AI Demo/shots_dmg"
const VIEW := Vector2i(1600, 900)
const DT := 1.0 / 60.0
const TICK := 0.1          # 与 `_WaveSim.DT` 同
const DPS := 22.0          # 全体池 dps（≈ 开局 1–2 座初级塔）

var tag := "before"


class StubDirector extends Node:
	signal monster_killed(m)
	var snap: Dictionary = {}
	var v0_ := 10.10
	func snapshot() -> Dictionary:
		return snap


class StubMonster extends RefCounted:
	var index: int
	var hp: float
	var hp_max: float
	var wpos: Vector2
	var t_remain: float
	var proto: String = "Swarm"
	var elite: bool = false
	func _init(i: int, h: float, p: Vector2, tr: float) -> void:
		index = i
		hp = h
		hp_max = h
		wpos = p
		t_remain = tr
	## 与 `monster.gd :: pos(v0)` 同签名（击杀反馈只读位置）
	func pos(_v0: float) -> Vector2:
		return wpos


## 只画"怪 + 血条"，用于判读数字与怪的相对位置（是否压怪 / 是否跟丢）。
class Ghosts extends Node2D:
	var vfx
	var mons: Array = []
	func _draw() -> void:
		if vfx == null:
			return
		for m in mons:
			var p: Vector2 = vfx._to_screen(m.wpos)
			draw_circle(p, 9.0, Color(1.0, 0.42, 0.24))
			draw_circle(p, 4.5, Color(0.541, 0.184, 0.110))
			var w := 34.0
			var f := clampf(float(m.hp) / maxf(1.0, float(m.hp_max)), 0.0, 1.0)
			draw_rect(Rect2(p.x - w * 0.5, p.y - 19.0, w, 3.0), Color(0.0, 0.0, 0.0, 0.55))
			draw_rect(Rect2(p.x - w * 0.5, p.y - 19.0, w * f, 3.0), Color(1.0, 0.35, 0.25))


var _monsters: Array = []
var _director: StubDirector
var _vfx
var _sv: SubViewport
var _ghosts: Ghosts
var _t := 0.0
var kills := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = String(args[0])
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_SpaceModel.mode = 1     # RADIAL
	_run()


func _sleep(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = _sv.get_texture().get_image()
	var p := "%s/%s-%s.png" % [OUT_DIR, tag, name]
	img.save_png(p)
	var n := 0
	var texts: Array = []
	for e in _vfx._dmg:
		n += 1
		if n <= 12:
			texts.append("%s(t%d,%.0f,%.0f)" % [String(e["text"]), int(e["tier"]),
				Vector2(e["base"]).x, Vector2(e["base"]).y])
	print("[dmg-probe] %s  dmg=%d  grid=%d  kills=%d  %s" % [p, n, _vfx._dmg_grid.size(), kills, ", ".join(texts)])
	if _vfx._dmg_grid.size() > n:
		print("            grid keys: %s" % str(_vfx._dmg_grid.keys()))
	var gs: Array = []
	for m in _monsters:
		gs.append("i%d@(%.0f,%.0f)" % [m.index, _vfx._to_screen(m.wpos).x, _vfx._to_screen(m.wpos).y])
	print("            ghosts: %s" % ", ".join(gs))


func _run() -> void:
	var sv := SubViewport.new()
	sv.size = VIEW
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	root.add_child(sv)
	_sv = sv

	_director = StubDirector.new()
	sv.add_child(_director)
	_ghosts = Ghosts.new()
	sv.add_child(_ghosts)
	_vfx = _VFX.new()
	sv.add_child(_vfx)
	_vfx.set_process(false)     # 手动步进 → 帧间可复现
	_vfx.bind_director(_director)
	_ghosts.vfx = _vfx
	_ghosts.mons = _monsters

	# 6 只怪：沿径向由外向内，t_remain 决定位置；最前者挨打（与 hitscan 口径同）。
	var dirs := [0.0, 0.9, 1.9, 3.0, 4.0, 5.2]
	for i in dirs.size():
		var a := float(dirs[i])
		var tr := 9.0 - float(i) * 0.55
		var p := _SpaceModel.RADIAL_CORE + Vector2(cos(a), sin(a)) * _SpaceModel.SPAWN_RADIUS * (tr / 10.0)
		_monsters.append(StubMonster.new(i, 26.0 + float(i) * 6.0, p, tr))
	_sync_snap()

	await _sleep(0.35)
	await _shot("00-idle")
	for step in range(1, 5):
		_sim(1.2)
		await _shot("%02d" % step)
	_sim(1.2)
	await _shot("05-late")
	sv.queue_free()
	await _sleep(0.2)
	quit(0)


func _sync_snap() -> void:
	var arr: Array = []
	for m in _monsters:
		arr.append({
			"index": m.index, "hp": m.hp, "hp_max": m.hp_max,
			"pos": m.wpos, "t_remain": m.t_remain, "proto": m.proto, "elite": m.elite,
		})
	_director.snap = {"w": 1, "dps": DPS, "monsters": arr}
	if _ghosts != null:
		_ghosts.queue_redraw()


## 以 60fps 步进 `sec` 秒；每 0.1s 走一次伤害分配（对齐 `_WaveSim.DT`）。
func _sim(sec: float) -> void:
	var acc := 0.0
	var steps := int(round(sec / DT))
	for _i in steps:
		_t += DT
		acc += DT
		while acc >= TICK - 1e-9:
			acc -= TICK
			_tick()
		_vfx._process(DT)


func _tick() -> void:
	for m in _monsters:
		m.t_remain -= TICK
	# hitscan：按 t_remain 升序填满（与 ② 同口径）
	var sorted := _monsters.duplicate()
	sorted.sort_custom(func(a, b): return a.t_remain < b.t_remain)
	var pool := DPS * TICK
	var killed_idx: Array = []
	for m in sorted:
		if pool <= 0.0:
			break
		if m.hp <= pool:
			pool -= m.hp
			m.hp = 0.0
			_monsters.erase(m)
			kills += 1
			killed_idx.append(m.index)
			_director.emit_signal("monster_killed", m)
		else:
			m.hp -= pool
			pool = 0.0
	_sync_snap()
	# 击杀分支留证：击杀帧应立即产出一个"升档"数字（§2.1 escalate）
	if not killed_idx.is_empty():
		_vfx._process(0.0)
		for e in _vfx._dmg:
			if killed_idx.has(int(e.get("owner", -1))):
				print("[kill-dmg] owner=%d tier=%d text=%s count=%d age=%.2f" % [
					int(e["owner"]), int(e["tier"]), String(e["text"]),
					int(e["count"]), float(e["age"])])
	# 走到头的补新怪，保持画面有受击目标（纯演出取样，不代表真实波次）
	if _monsters.size() < 3:
		var a := fmod(_t * 1.7, TAU)
		var tr := 9.5
		var p := _SpaceModel.RADIAL_CORE + Vector2(cos(a), sin(a)) * _SpaceModel.SPAWN_RADIUS * (tr / 10.0)
		_monsters.append(StubMonster.new(100 + int(_t * 10.0), 34.0, p, tr))
