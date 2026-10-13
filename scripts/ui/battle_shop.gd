extends Node
##
## 切片3 骨架 / 切片4 接线 / 切片5 真实刷怪 场景根 —— `scenes/battle_shop.tscn`
##
## 职责：把「时钟权威」与「商店运行时」注入各个 UI 子节点（依赖注入，不用 `get_node` 满天飞）。
##       UI 子节点一律**不持有**游戏状态，只读 director 的快照 + runtime 的快照 + 发意图信号
##       （control-manifest §5：`scripts/ui/` 不持有游戏状态）。
##
## 节点分层（GDD §2.4 分层表，层号读 `MvpConfig.LAYER_*`）：
##   战场 3D（后续 SubViewport）· HUD 10 · 商店 100 · 红光脉冲 120 · 核心 HP 130 · 弹窗 140
##
## 切片4 新增：`ShopController`（gameplay 层，Node·ALWAYS）在 `_ready()` 里创建并接线：
##   TimeDirector 的意图信号 → ShopRuntime；Runtime 的只读快照 → UI。
##   🔴 UI 与玩法状态之间**只有这一座桥**（SR-5 / CD-E）。
##
## 切片5 新增：`WaveDirector`（gameplay 层，Node·ALWAYS）= **波次 / 刷怪权威**：
##   · 消费被 `time_scale` 缩放的 delta → 真实刷怪 / 真实移动 / 真实伤害分配；
##   · 打完 → `TimeDirector.wave_end(w)` → 安全窗（替换切片4 的"最小波次驱动器"）。
##   `MonsterLayer`（Node2D，占位渲染）只读它的 snapshot 画怪物与路径。
##
## 🔴 依赖方向：TimeDirector（时钟）← WaveDirector（波次）→ ShopController（经济）
##    UI 全部只读，不反向写。
##

const _TimeDirector := preload("res://scripts/ui/time_director.gd")
const _ShopController := preload("res://scripts/gameplay/shop_controller.gd")
const _WaveDirector := preload("res://scripts/gameplay/wave_director.gd")


var director: Node = null
var controller: Node = null
var wave_director: Node = null


func _ready() -> void:
	director = get_node_or_null("TimeDirector")
	if director == null:
		push_error("battle_shop: 找不到 TimeDirector 子节点")
		return
	director.add_to_group("time_director")

	# ---- 玩法侧：运行时 + 接线层（切片4）----
	controller = _ShopController.new()
	controller.name = "ShopController"
	add_child(controller)
	controller.setup("B")
	controller.bind_director(director)

	# ---- 玩法侧：波次导演（切片5 · 真实刷怪战斗循环）----
	wave_director = _WaveDirector.new()
	wave_director.name = "WaveDirector"
	add_child(wave_director)
	wave_director.bind_runtime(controller.runtime)
	wave_director.bind_director(director)
	controller.bind_wave_director(wave_director)

	var bf := get_node_or_null("Battlefield")
	if bf != null and bf.has_method("bind_director"):
		bf.bind_director(director)
	var ml := get_node_or_null("Battlefield/MonsterLayer")
	if ml != null:
		if ml.has_method("bind_director"):
			ml.bind_director(wave_director)
		if ml.has_method("bind_time_director"):
			ml.bind_time_director(director)
		if ml.has_method("bind_controller"):
			ml.bind_controller(controller)
	# 🟠 T-P6-07 A 档 VFX 层（兄弟于 MonsterLayer，在其之上绘制；只读 + 纯演出）。
	var vfx := get_node_or_null("Battlefield/VfxLayer")
	if vfx != null:
		if vfx.has_method("bind_director"):
			vfx.bind_director(wave_director)
		if vfx.has_method("bind_time_director"):
			vfx.bind_time_director(director)
		if vfx.has_method("bind_controller"):
			vfx.bind_controller(controller)
	var hud := get_node_or_null("HudLayer/Hud")
	if hud != null and hud.has_method("bind_director"):
		hud.bind_director(director)
	var shop := get_node_or_null("ShopLayer/ShopOverlay")
	if shop != null and shop.has_method("bind_director"):
		shop.bind_director(director)
	var pulse := get_node_or_null("PulseLayer/ThreatPulse")
	if pulse != null and pulse.has_method("bind_director"):
		pulse.bind_director(director)
	var hp := get_node_or_null("CoreHpLayer/CoreHpBar")
	if hp != null:
		if hp.has_method("bind_director"):
			hp.bind_director(director)
		if hp.has_method("bind_controller"):
			hp.bind_controller(controller)   # 🟢 切片8续3：核心 HP 单一数据源实时刷新

	# ---- 运行时快照注入 UI（只读）----
	for n in [hud, shop]:
		if n != null and n.has_method("bind_controller"):
			n.bind_controller(controller)

	# ---- 开局：由 `WaveDirector` 发出 W1 的 wave_started ----
	if controller != null:
		controller.call_deferred("start_run", 1)
