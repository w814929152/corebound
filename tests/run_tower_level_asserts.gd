extends SceneTree
##
## headless 断言 —— 塔等级牌（`scripts/ui/tower_level_layer.gd`）
##
## 背景：等级此前**只靠形态暗示** —— `monster_layer._draw_tower_form` 在 h≥2/3/5/8
##   跳四档装饰，之后封顶。后果两条：
##     · h=9 与 h=99 画面**完全一样** → 满级之后买卡没有任何视觉反馈；
##     · 形态是**冗余通道**（环 / 护角 / 星点），新玩家无法反解"这是几级"。
##   商店 H5 提示已经写 `Lv 3 → 4`，战场上却没有对应读数 → 买卡前后无法自证。
##
## 本套件把「等级必须可读」钉成可回归断言，同时守三条纪律：
##   · **只读**：数据源 = `runtime.snapshot().slots[].h`，不复制、不写玩法状态、不发信号；
##   · **分层**：文本不得写回 `monster_layer.gd`（该文件的**零文本**红线 AC-T1-24 仍在）；
##   · **位序**：等级牌在 `MonsterLayer` 之上、`VfxLayer`（伤害数字）之下。
##
## 🔴 为什么判据是「造桩」而不是截帧：headless 无纹理、CI 不该依赖人眼。这里只验
##   「条目 = 快照里的非空塔 / h 逐位对齐（含 >8 的高等级，证明没被形态档位截断）/
##    坐标确实来自世界层换算 / 变换变了会重排」；版式（圆角、字号、摆位）由
##   `tests/probe_tower_level.gd` 的截帧取证。
##
## 🔴 有效性自证（负向验证）：把 `_rebuild` 的 h 改成 `mini(h, 8)`（模拟"等级被形态档位
##   截断"）→ 本套件 L11 必 FAIL；把 `bind_controller` 里的信号连接删掉、只留轮询 →
##   L15 必 FAIL（抽屉展开后签名不更新，正是实测截图里"牌飘到塔右侧 500px 外"的那个缺陷）。
##
## 跑法（本文件 `extends SceneTree`，故两种入口等价）：
##   <godot> --headless --path . --script res://tests/run_tower_level_asserts.gd    # 只跑本套件
##   <godot> --headless --path . --script res://tests/run_tests.gd -- tlv           # 聚合入口
##

const _TowerLevel := preload("res://scripts/ui/tower_level_layer.gd")

var _pass := 0
var _fail := 0


# ---------------------------------------------------------------------------
#  桩：只实现被读取的那几个成员（多一个都算"测试跟着实现走"）
# ---------------------------------------------------------------------------
class _LvGeo extends RefCounted:
	var slots: Array = []


class _LvRuntime extends RefCounted:
	var geo := _LvGeo.new()
	var rows: Array = []
	var core := -1

	func snapshot() -> Dictionary:
		return {"slots": rows, "core_tower_slot": core}


class _LvCtl extends Node:
	signal shop_changed
	signal run_changed
	var runtime := _LvRuntime.new()


class _LvWorld extends Node:
	## 假变换：等比 ×K 再平移 OFF —— 足够验"坐标确实来自世界层，不是自己算的"。
	var k := 2.0
	var off := Vector2(5.0, 7.0)

	func world_to_screen(p: Vector2) -> Vector2:
		return p * k + off

	func world_scale() -> float:
		return k


## 🔴 双入口（2026-11-08）：`extends SceneTree` 才能被 `--script` 直跑；
##   `run_tests.gd` 聚合走 `.new().run_all()`，`.new()` 不触发 `_initialize()`，不会双跑。
func _initialize() -> void:
	quit(0 if run_all() else 1)


func run_all() -> bool:
	_log("")
	_log("=".repeat(78))
	_log("塔等级牌（tower_level_layer：等级可读 · 只读快照 · 层序正确）")
	_log("基准：control-manifest §5 只读 · AC-T1-24 零文本 · art-bible §9.1 最小字号")
	_log("=".repeat(78))

	_test_source_discipline()
	_test_scene_wiring()
	_test_entries_from_snapshot()
	_test_retransform_on_drawer()
	_test_degenerate()

	_log("")
	_log("-".repeat(78))
	_log("塔等级牌：PASS=%d  FAIL=%d" % [_pass, _fail])
	return _fail == 0


# ---------------------------------------------------------------------------
#  [1] 源码纪律：只读 / 分层 / 不自算坐标
# ---------------------------------------------------------------------------
func _test_source_discipline() -> void:
	_log("")
	_log("--- [1] 源码纪律：只读快照 / 文本分层 / 坐标借用 ---")
	var src := FileAccess.get_file_as_string("res://scripts/ui/tower_level_layer.gd")
	var ml_src := FileAccess.get_file_as_string("res://scripts/ui/monster_layer.gd")

	_check("等级牌读 `snapshot()` 的 `slots[].h`（单一数据源，零新增快照字段）",
		src.find("snapshot()") >= 0 and src.find("\"slots\"") >= 0 and src.find("\"h\"") >= 0)
	_check("等级牌不直接摸 `player.towers`（不复制玩法状态）", src.find("player.") < 0)
	_check("等级牌**不发**信号（emit_signal 不出现，只做单向订阅）",
		src.find("emit_signal") < 0)
	_check("等级牌不调玩法动作（apply_action / buy / salvage 均不出现）",
		src.find("apply_action") < 0 and src.find(".buy(") < 0 and src.find("salvage") < 0)

	# 分层红线：文本不进 world 形状层（AC-T1-24 不放宽）
	_check("monster_layer 仍**零文本**（无 draw_string，等级牌另开一层）",
		ml_src.find("draw_string(") < 0)

	# 坐标：必须借世界层，不能自写第二份换算（手抄第二份网格数字的坑）
	_check("坐标经 `world_layer.world_to_screen()` 换算（不自己复写变换）",
		src.find("world_to_screen") >= 0 and src.find("func _xform") < 0)

	# 几何：牌挂在塔身**外侧**（对角），不与塔身/正上方徽标抢位
	_check("牌锚点按塔外接圆 R 对角外扩（不压在塔身上）",
		src.find("0.72 * R") >= 0 and src.find("- 0.72 * R") >= 0)

	# 字号：不低于 art-bible §9.1 的可读下限（本项目基准屏实测 14px 起）
	_check("字号下限 ≥ 14px（1080p 基准屏 sc≈8.5 下 1.75×sc≈15px）",
		int(_TowerLevel.FS_MIN) >= 14 and float(_TowerLevel.FS_K) >= 1.5)
	_check("字号上限封顶（高 DPI 下不至于溢出塔位）", int(_TowerLevel.FS_MAX) <= 24)


# ---------------------------------------------------------------------------
#  [2] 场景挂载 / 层序 / 装配
# ---------------------------------------------------------------------------
func _test_scene_wiring() -> void:
	_log("")
	_log("--- [2] 场景挂载 + 层序 + 装配 ---")
	var scene_src := FileAccess.get_file_as_string("res://scenes/battle_shop.tscn")
	var bs_src := FileAccess.get_file_as_string("res://scripts/ui/battle_shop.gd")

	var i_ml := scene_src.find("name=\"MonsterLayer\"")
	var i_tlv := scene_src.find("name=\"TowerLevelLayer\"")
	var i_vfx := scene_src.find("name=\"VfxLayer\"")

	_check("battle_shop.tscn 挂载 TowerLevelLayer（Battlefield 下）",
		i_tlv >= 0 and scene_src.find("path=\"res://scripts/ui/tower_level_layer.gd\"") >= 0)
	# 🔴 顺序不是审美：MonsterLayer 画塔身 → 等级牌才压得住塔；VfxLayer 画伤害数字
	#    → 必须压得住等级牌（战斗时可读性优先级：伤害 > 等级）。
	_check("层序：MonsterLayer < TowerLevelLayer < VfxLayer",
		i_ml >= 0 and i_tlv > i_ml and i_vfx > i_tlv)

	_check("battle_shop 三绑齐（世界层 / 时钟 / 控制器）",
		bs_src.find("bind_world_layer") >= 0
		and bs_src.find("bind_time_director") >= 0
		and bs_src.find("bind_controller") >= 0)


# ---------------------------------------------------------------------------
#  [3] 条目 = 快照里的非空塔（h 逐位对齐，含 >8 的高等级）
# ---------------------------------------------------------------------------
func _test_entries_from_snapshot() -> void:
	_log("")
	_log("--- [3] 条目：只画非空塔 · 等级逐位对齐 · 坐标来自世界层 ---")
	var ctl := _LvCtl.new()
	ctl.runtime.geo.slots = [Vector2(0.0, 0.0), Vector2(10.0, -4.0), Vector2(20.0, 8.0)]
	ctl.runtime.rows = [
		{"slot": 0, "ctype": "Arrow", "h": 3, "empty": false, "disabled": false},
		{"slot": 1, "ctype": "Frost", "h": 12, "empty": false, "disabled": true},
		{"slot": 2, "ctype": "", "h": 0, "empty": true, "disabled": false},
	]
	var lv = _TowerLevel.new()
	lv.bind_world_layer(_LvWorld.new())
	lv.bind_controller(ctl)

	var n: int = lv._entries.size()
	_check_int("条目数 = 非空塔数（空槽跳过）", n, 2)
	if n == 2:
		_check_int("座 0 等级 = 快照 h（低等级）", int(lv._entries[0]["h"]), 3)
		# 🔴 关键：h=12 必须原样显示。形态档位封顶在 8，若把 h 截断到 8，
		#    这条会 FAIL —— 那正是本次要治的缺陷本身。
		_check_int("座 1 等级 = 快照 h（h=12，**未被形态档位截断到 8**）",
			int(lv._entries[1]["h"]), 12)
		_check("屏幕坐标来自世界层换算（×2 + (5,7)）",
			Vector2(lv._entries[0]["pos"]) == Vector2(5.0, 7.0)
			and Vector2(lv._entries[1]["pos"]) == Vector2(25.0, -1.0))
		_check("停机塔仍保留等级牌（disabled 透传 → 绘制时压暗）",
			not bool(lv._entries[0]["disabled"]) and bool(lv._entries[1]["disabled"]))
		_check("条目带槽位号（拆塔/换卡后可按槽定位，不依赖数组下标）",
			int(lv._entries[0]["slot"]) == 0 and int(lv._entries[1]["slot"]) == 1)

	# 无变化 → 签名不变（15Hz 轮询不会每帧重排文字）
	var sig_before: String = lv._sig
	lv._rebuild()
	_check("几何与等级都没变 → 签名不变（不重复重绘）", lv._sig == sig_before)

	# 升级（h 3→4）→ 签名必须变
	ctl.runtime.rows[0]["h"] = 4
	lv._rebuild()
	_check("买卡升级后签名变化（Lv 3 → 4 会立即重绘）", lv._sig != sig_before)

	# 信号驱动：shop_changed 直接触发（不依赖 _process，暂停态也生效）
	var sig2: String = lv._sig
	ctl.runtime.rows[0]["h"] = 5
	ctl.shop_changed.emit()
	_check("`shop_changed` 信号即触发重排（暂停态下轮询停摆时仍有更新）", lv._sig != sig2)

	lv.free()
	ctl.free()


# ---------------------------------------------------------------------------
#  [4] 变换变化必须重排（抽屉展开 → 战场变窄 → 全部塔位位移）
# ---------------------------------------------------------------------------
## 🔴 缺陷复现条件：抽屉开合发生在**安全窗（`get_tree().paused`）**里 → 本节点
##   PAUSABLE → `_process` 不跑；只有信号能把它拉回来。而抽屉展开还会改可视宽
##   （`MonsterLayer._field_width`）→ 战场重新居中 → **所有塔位坐标整体位移**。
func _test_retransform_on_drawer() -> void:
	_log("")
	_log("--- [4] 抽屉开合：塔位整体位移 → 必须重排（不能留旧坐标）---")
	var ctl := _LvCtl.new()
	ctl.runtime.geo.slots = [Vector2(4.0, 4.0)]
	ctl.runtime.rows = [{"slot": 0, "ctype": "Arrow", "h": 7, "empty": false, "disabled": false}]
	var world := _LvWorld.new()
	var lv = _TowerLevel.new()
	lv.bind_world_layer(world)
	lv.bind_controller(ctl)

	var p_open: Vector2 = lv._entries[0]["pos"]
	var sig_a: String = lv._sig
	# 抽屉展开：世界层换算变了（缩放 + 平移都变）
	world.k = 3.0
	world.off = Vector2(-11.0, 2.0)
	lv._on_state_changed(0, 1)
	var p_after: Vector2 = lv._entries[0]["pos"]
	_check("`state_changed` 后坐标按**新**变换重算（不留旧战场宽度的坐标）",
		p_after == Vector2(1.0, 14.0) and p_after != p_open)
	_check("抽屉开合会改变坐标签名", lv._sig != sig_a)

	# 自愈兜底：`_draw` 开头按当前变换重算（信号漏接时不至于整局错位）
	var src := FileAccess.get_file_as_string("res://scripts/ui/tower_level_layer.gd")
	var i_draw := src.find("func _draw()")
	var i_fix := src.find("_rebuild(true)", i_draw if i_draw >= 0 else 0)
	_check("`_draw()` 开头先 `_rebuild(true)` 自愈（信号漏接兜底）",
		i_draw >= 0 and i_fix > i_draw)

	lv.free()
	ctl.free()
	world.free()


# ---------------------------------------------------------------------------
#  [5] 退化态：世界层/控制器缺失不崩、空快照不画
# ---------------------------------------------------------------------------
func _test_degenerate() -> void:
	_log("")
	_log("--- [5] 退化态：绑定不全不崩 ---")
	var lv = _TowerLevel.new()
	lv._rebuild()                                  # 两者皆 null
	_check("未绑定世界层/控制器时条目为空且不崩", lv._entries.is_empty())

	var ctl := _LvCtl.new()
	ctl.runtime.rows = []
	lv.bind_world_layer(_LvWorld.new())
	lv.bind_controller(ctl)
	_check("空快照（0 座塔）→ 条目为空", lv._entries.is_empty())

	lv.free()
	ctl.free()


# ---------------------------------------------------------------------------
#  断言助手
# ---------------------------------------------------------------------------
func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		_log("   [PASS] %s" % name)
	else:
		_fail += 1
		_log("   [FAIL] %s" % name)


func _check_int(name: String, got: int, want: int) -> void:
	_check("%s（got=%d want=%d）" % [name, got, want], got == want)


func _log(s: String) -> void:
	print(s)
