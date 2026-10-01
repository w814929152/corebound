extends SceneTree
##
## Godot 4.7.2 API 探针（一次性调研工具，不进产品代码、不进自测套件）
##
## 目的：程基岩的训练数据只到 Godot 4.3。本探针在**本机 4.7.2 真机**上实测切片3
##       （实时商店覆盖层）要用到的全部时钟 / 暂停 / 布局 / 输入 API 的真实行为，
##       避免臆造 API —— 实测结果写进
##       `docs/architecture/slice3-shop-ui-architecture.md` 的「API 参考」一节。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tools/probe_godot47.gd
##
## 覆盖：
##   A. `_process(delta)` 是否被 `Engine.time_scale` 缩放（决定 `delta / time_scale` 是否成立）
##   B. `Time.get_ticks_usec()` 是否 unscaled、暂停时是否仍走
##   C. `get_tree().paused` × `process_mode` 的组合行为
##   D. `Engine.time_scale = 0.0` 的除零后果（🔴 SR-R5 红线的实测依据）
##   E. `Control` 锚点：`set_anchors_preset()` vs 直接赋值 `anchors_preset`（4.7 已知坑）
##   F. 容器布局：MarginContainer / HBoxContainer 的实际 size 计算
##   G. 暂停 + `PROCESS_MODE_ALWAYS` 节点能否收到 `_unhandled_key_input`
##

const FRAMES := 200
const WARMUP := 20
const ZERO_FRAMES := 60


class PausableKid extends Node:
	## process_mode = PAUSABLE 的子节点：用来验证「暂停时子节点确实停了」
	var calls := 0

	func _process(_delta: float) -> void:
		calls += 1


class ProbeNode extends Node:
	## 所有测量都在这个节点里做（SceneTree 脚本不覆写 _process，避免干扰节点帧循环）
	var delta_sum := 0.0          # Σ delta（引擎给的）
	var unscaled_sum := 0.0       # Σ delta / Engine.time_scale
	var real_sum := 0.0           # Σ 真实秒（Time.get_ticks_usec 差值）
	var frames := 0
	var input_hits := 0
	var _last_usec := 0

	# 阶段表：[名称, time_scale, paused, 帧数, 是否发一次 TAB 键]
	var phases: Array = []
	var phase_idx := -1
	var phase_frames := 0
	var results: Array = []
	var done := false

	func _ready() -> void:
		var kid := PausableKid.new()
		kid.name = "PausableKid"
		kid.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(kid)
		phases = [
			["WARMUP(丢弃)      ts=1.00 paused=false", 1.0, false, WARMUP, false],
			["Combat            ts=1.00 paused=false", 1.0, false, FRAMES, false],
			["ShopDilated       ts=0.35 paused=false", 0.35, false, FRAMES, false],
			["PlacementMode     ts=0.25 paused=false", 0.25, false, FRAMES, false],
			["SafeWindow        ts=1.00 paused=true ", 1.0, true, FRAMES, true],
			["ZeroScale         ts=0.00 paused=false", 0.0, false, ZERO_FRAMES, false],
		]
		_last_usec = Time.get_ticks_usec()
		_next_phase()

	func _next_phase() -> void:
		phase_idx += 1
		if phase_idx >= phases.size():
			_finish()
			return
		var p: Array = phases[phase_idx]
		Engine.time_scale = float(p[1])
		get_tree().paused = bool(p[2])
		delta_sum = 0.0
		unscaled_sum = 0.0
		real_sum = 0.0
		frames = 0
		input_hits = 0
		_last_usec = Time.get_ticks_usec()
		var kid := get_node_or_null("PausableKid")
		if kid != null:
			kid.calls = 0
		phase_frames = int(p[3])
		if bool(p[4]):
			# 暂停阶段发一次 TAB，验证 ALWAYS 节点能否收到输入
			var ev := InputEventKey.new()
			ev.keycode = KEY_TAB
			ev.physical_keycode = KEY_TAB
			ev.pressed = true
			Input.parse_input_event(ev)

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		delta_sum += float(delta)
		real_sum += float(now - _last_usec) / 1000000.0
		if Engine.time_scale > 0.0:
			unscaled_sum += float(delta) / float(Engine.time_scale)
		_last_usec = now
		frames += 1
		if not done and frames >= phase_frames:
			_record()
			_next_phase()

	func _unhandled_key_input(_event: InputEvent) -> void:
		input_hits += 1

	func _record() -> void:
		if phase_idx == 0:      # 预热帧丢弃
			return
		var p: Array = phases[phase_idx]
		var kid := get_node_or_null("PausableKid")
		results.append({
			"name": String(p[0]),
			"ts": float(p[1]),
			"paused": bool(p[2]),
			"frames": frames,
			"delta_sum": delta_sum,
			"unscaled_sum": unscaled_sum,
			"real_sum": real_sum,
			"kid_calls": (kid.calls if kid != null else -1),
			"input_hits": input_hits,
		})

	func _finish() -> void:
		done = true
		Engine.time_scale = 1.0
		get_tree().paused = false
		_report()

	func _report() -> void:
		var v := Engine.get_version_info()
		print("=" .repeat(96))
		print("Godot ", v["string"], " (", String(v["hash"]).substr(0, 9), ") · DisplayServer=", DisplayServer.get_name())
		print("=" .repeat(96))
		print("")
		print("---- A/B/C/D. 五态时钟口径实测 ----")
		print("阶段                                 | ts  |paused|帧数|  Σdelta |  Σ(δ/ts) |  Σ真实秒 | Σdelta/Σ真实秒 | PAUSABLE子节点帧数")
		print("-" .repeat(140))
		for r in results:
			var ratio := -1.0
			if float(r["real_sum"]) > 0.0:
				ratio = float(r["delta_sum"]) / float(r["real_sum"])
			print("%-35s |%.2f | %-5s|%4d| %7.4f | %8.4f | %8.4f | %14.4f | %d" % [
				String(r["name"]),
				float(r["ts"]),
				("true " if bool(r["paused"]) else "false"),
				int(r["frames"]),
				float(r["delta_sum"]),
				float(r["unscaled_sum"]),
				float(r["real_sum"]),
				ratio,
				int(r["kid_calls"]),
			])
		print("")
		print("判读：")
		print("  · 若 Σdelta/Σ真实秒 ≈ ts  → `_process(delta)` 的 delta **被 time_scale 缩放**")
		print("  · 若 Σ(δ/ts) ≈ Σ真实秒     → `delta / Engine.time_scale` = 真实秒，unscaled 计时成立")
		print("  · paused=true 行：PAUSABLE 子节点帧数应为 0，ALWAYS 节点（探针自己）仍在跑")
		print("  · ts=0.00 行：Σdelta 应为 0 → δ/ts = 0/0 = NaN → 预算被 NaN 污染（🔴 SR-R5）")
		for r in results:
			if float(r["ts"]) == 0.0:
				var nan := float(r["delta_sum"]) / 0.0
				print("  [ts=0 实测] Σdelta=", float(r["delta_sum"]),
					" · δ/ts=", nan,
					" · is_nan(δ/ts)=", is_nan(nan),
					" · Time.get_ticks_msec 仍在走=", Time.get_ticks_msec() > 0)
		print("")
		print("---- G. 暂停 + ALWAYS 节点的输入 ----")
		for r in results:
			if bool(r["paused"]):
				print("  paused=true 阶段 _unhandled_key_input 命中 ", int(r["input_hits"]), " 次（该阶段开头发了 1 次 TAB）")
		print("")
		_layout_probe()

	# -----------------------------------------------------------------------
	#  E/F. 静态探针：Control 锚点 + 容器布局（布局要在树里等一帧才算得出来）
	# -----------------------------------------------------------------------
	func _layout_probe() -> void:
		print("---- E. Control 锚点：set_anchors_preset() vs 直接赋值 anchors_preset ----")
		var c1 := Control.new()
		c1.set_anchors_preset(Control.PRESET_FULL_RECT)
		print("  c1.set_anchors_preset(PRESET_FULL_RECT) → anchor_right=", c1.anchor_right,
			" anchor_bottom=", c1.anchor_bottom, " layout_mode=", c1.layout_mode)
		var c2 := Control.new()
		c2.anchors_preset = Control.PRESET_FULL_RECT
		print("  c2.anchors_preset = PRESET_FULL_RECT   → anchor_right=", c2.anchor_right,
			" anchor_bottom=", c2.anchor_bottom, " layout_mode=", c2.layout_mode)
		var c3 := Control.new()
		c3.set_anchor(SIDE_RIGHT, 1.0)
		c3.set_anchor(SIDE_BOTTOM, 1.0)
		print("  c3.set_anchor(SIDE_RIGHT/BOTTOM, 1.0)  → anchor_right=", c3.anchor_right,
			" anchor_bottom=", c3.anchor_bottom)
		print("  常量 PRESET_FULL_RECT=", Control.PRESET_FULL_RECT,
			" PRESET_RIGHT_WIDE=", Control.PRESET_RIGHT_WIDE,
			" PRESET_TOP_LEFT=", Control.PRESET_TOP_LEFT,
			" SIZE_EXPAND_FILL=", Control.SIZE_EXPAND_FILL,
			" SIZE_SHRINK_END=", Control.SIZE_SHRINK_END)
		print("  全局 Side 枚举：SIDE_LEFT=", SIDE_LEFT, " SIDE_TOP=", SIDE_TOP,
			" SIDE_RIGHT=", SIDE_RIGHT, " SIDE_BOTTOM=", SIDE_BOTTOM)
		print("  → 代码建 Control 必须走 set_anchors_preset()/set_anchor()；直接赋值 anchors_preset 是否失效见上方数字。")

		print("")
		print("---- F. 容器布局实测（根 Control 铺满视口，抽屉 min 560）----")
		var rootc := Control.new()
		rootc.name = "LayoutProbeRoot"
		rootc.set_anchors_preset(Control.PRESET_FULL_RECT)
		get_tree().root.add_child(rootc)
		var mc := MarginContainer.new()
		mc.set_anchors_preset(Control.PRESET_FULL_RECT)
		mc.add_theme_constant_override("margin_left", 16)
		mc.add_theme_constant_override("margin_right", 16)
		mc.add_theme_constant_override("margin_top", 16)
		mc.add_theme_constant_override("margin_bottom", 16)
		rootc.add_child(mc)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		mc.add_child(hb)
		var left := ColorRect.new()
		left.custom_minimum_size = Vector2(100.0, 100.0)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var drawer := Panel.new()
		drawer.custom_minimum_size = Vector2(560.0, 100.0)
		drawer.size_flags_horizontal = Control.SIZE_SHRINK_END
		hb.add_child(left)
		hb.add_child(drawer)
		await get_tree().process_frame
		await get_tree().process_frame
		var vis: Rect2 = get_viewport().get_visible_rect()
		print("  viewport 可见矩形         = ", vis)
		print("  根 Control                = pos ", rootc.position, " size ", rootc.size)
		print("  MarginContainer           = pos ", mc.position, " size ", mc.size)
		print("  HBoxContainer             = pos ", hb.position, " size ", hb.size)
		print("  左(战场 EXPAND_FILL)      = pos ", left.position, " size ", left.size)
		print("  右(抽屉 min 560 SHRINK_END)= pos ", drawer.position, " size ", drawer.size)
		var vw := float(vis.size.x)
		print("  → 1280 视口下：GDD 的 32% = ", 0.32 * vw, "px，最小宽约束 = 560px → 抽屉实际占 ",
			(560.0 / vw * 100.0), "% 屏宽（🔴 两条约束在 1280 宽下互相顶牛，见架构文档「待拍板」）")
		rootc.free()
		c1.free(); c2.free(); c3.free()
		print("")
		print("=" .repeat(96))
		print("探针结束")
		print("=" .repeat(96))
		get_tree().quit(0)


func _initialize() -> void:
	Engine.time_scale = 1.0
	self.paused = false
	var p := ProbeNode.new()
	p.name = "Probe"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(p)
