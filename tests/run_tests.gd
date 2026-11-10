extends SceneTree
##
## headless 自测入口（无图形界面也能跑纯计算单测）。
##
## 选型说明（为什么不用 GdUnit）：
##   · 本切片的被测对象是**纯计算类**（RefCounted，无 Node / 无生命周期 / 无信号），
##     不需要 GdUnit 的 fixture / 参数化 / watcher 那些重量级能力；
##   · 引入 GdUnit 会往 `addons/` 塞一个外部依赖，且它自己也要在 headless 下先跑通插件初始化，
##     反而给「引擎有没有跑起来」增加一层不确定性；
##   · MVP 首要目标是 **CI 可一行命令跑通 + 失败即非零退出码**。
##     `SceneTree` 脚本 + `quit(exit_code)` 天然满足，且 Godot 4 原生支持。
##   · 后续切片一旦涉及 Node / 场景 / 信号的集成测试，再引入 GdUnit 并保留本入口做冒烟。
##
## 跑法：
##   <godot> --headless --path D:/roguedemo --script res://tests/run_tests.gd
##
## 切片开关（默认全跑）：
##   <godot> ... --script res://tests/run_tests.gd -- slice1       # 只跑切片1（快）
##   <godot> ... --script res://tests/run_tests.gd -- slice2       # 只跑切片2（含 MC 300）
##
## 径向聚合入口（R-1，质量门 P1 放行前置项）：
##   <godot> ... --script res://tests/run_tests.gd -- radial8      # 一键跑完径向全部验证脚本
##   <godot> ... --script res://tests/run_tests.gd -- radial8diag  # 同上 + 三个重型诊断件
##
##   ⚠️ 两个入口**都不在默认无参回归里**：默认仍只跑 slice1~8 + t1aggro（PATH 口径金标本，
##      3280 断言，快）。radial8 含 300 局 MC，全跑数分钟，故独立成一键入口而非默认项。
##
##   被聚合的脚本见下方 RADIAL8_GATES / RADIAL8_DIAG / RADIAL8_DIAG_HEAVY。
##   统一 exit code：任一子脚本非零退出 → radial8 整体非零退出。
##
##   子进程用哪个 Godot：优先环境变量 GODOT_BIN，否则 OS.get_executable_path()。
##
##   ⚠️ 已知限制（Windows）：Godot 4.7.2 的 OS.execute 用**系统 ANSI 代码页（GBK）**解码
##      子进程 stdout，而不是 UTF-8，且属有损转换 → 被聚合进来的子脚本输出里**中文会乱码**
##      （父进程自己 print 的部分正常）。`[PASS]` / `[FAIL]` / 数值 / 末尾汇总表都是 ASCII，
##      不受影响；故 CI 判定与失败定位仍然可用。需要读中文原文时，单独直接跑那个脚本即可。
##      为便于定位，聚合器会额外统计每段子脚本输出里的 `[FAIL]` 出现次数（纯 ASCII）。
##

const TestSuite := preload("res://tests/test_suite.gd")
const TestSuiteSlice2 := preload("res://tests/test_suite_slice2.gd")
const TestSuiteSlice3 := preload("res://tests/test_suite_slice3.gd")
const TestSuiteSlice4 := preload("res://tests/test_suite_slice4.gd")
const TestSuiteSlice5 := preload("res://tests/test_suite_slice5.gd")
const TestSuiteSlice6 := preload("res://tests/test_suite_slice6.gd")
const TestSuiteSlice7 := preload("res://tests/test_suite_slice7.gd")
const TestSuiteSlice8 := preload("res://tests/test_suite_slice8.gd")
const TestSuiteT1Aggro := preload("res://tests/test_suite_t1_aggro.gd")
const TestSuiteAggroGolive := preload("res://tests/test_suite_aggro_golive.gd")
const TestSuiteRadial := preload("res://tests/test_suite_radial.gd")
const TestSuiteGeo8 := preload("res://tests/test_suite_geo8.gd")
const TestSuiteTutorial := preload("res://tests/run_tutorial_asserts.gd")
const TestSuiteExtPack := preload("res://tests/run_ext_pack_asserts.gd")
const TestSuiteUIStyle := preload("res://tests/run_ui_style_asserts.gd")
const TestSuiteTowerLevel := preload("res://tests/run_tower_level_asserts.gd")
const TestSuiteCardPack := preload("res://tests/run_card_pack_asserts.gd")
const TestSuiteCampaign := preload("res://tests/run_campaign_asserts.gd")
const TestSuiteIcehunter := preload("res://tests/run_icehunter_asserts.gd")
const TestSuiteFrost := preload("res://tests/run_frost_asserts.gd")
const TestSuiteFireCharge := preload("res://tests/run_fire_charge_asserts.gd")
const TestSuiteCombatTypes := preload("res://tests/run_combat_types_asserts.gd")
const TestSuiteStageWaves := preload("res://tests/run_stage_waves_asserts.gd")
const TestSuiteTowerSprites := preload("res://tests/lint_tower_sprites.gd")
const _Geo := preload("res://scripts/geo/geo.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

# V-0′ 只在显式参数 v0radial 下注入；默认六槽地图、金标本及运行参数均不改变。
const R2_SLOTS: Array = [
	Vector2(19.311233999284, 18.999172034807),
	Vector2(18.623983886996, 34.771066884092),
	Vector2(39.826948899491, 31.441118431717),
	Vector2(40.835990264792, 44.197489325769),
	Vector2(33.044493270216, 15.409846273352),
	Vector2(37.364641401712, 53.728611961036),
]

# ---------------------------------------------------------------------------
# radial8 聚合入口（R-1）
# ---------------------------------------------------------------------------
# 径向验证脚本按「能否在进程内当函数调用」分成两类，分别沿用两套机制：
#   A. 套件（extends RefCounted + run_all() -> bool）→ 进程内 preload 直调，
#      与既有 geo8 / radial 分支完全同款。
#   B. 独立脚本（extends SceneTree，在 _initialize() 内自行 quit(code)）→ 无法当函数调
#      （quit() 打在非主循环的 SceneTree 实例上不会传播退出码），故用 OS.execute 串行
#      拉起子进程，收集各自 exit code。
#
# ① 闸门件：脚本内部有真实 PASS/FAIL 语义（quit(0/1)），参与成败判定。
const RADIAL8_GATES: Array = [
	{"name": "geo8_smoke", "script": "res://tests/run_slice_geo8_smoke.gd"},
	{"name": "geo8_golden", "script": "res://tests/run_slice_geo8_golden.gd"},
	{"name": "expo", "script": "res://tests/run_slice_expo.gd"},
	{"name": "bulwark8", "script": "res://tests/run_slice_bulwark8.gd"},
	{"name": "panorama8", "script": "res://tests/run_slice_panorama8.gd"},
	{"name": "attrition8", "script": "res://tests/run_slice_attrition8.gd"},
	# 🟠 VFX-C3-01 永久守卫（quality-lead 复核增量）：C3 几何缓存「抽屉开合」cross-state 断言。
	#   慢件（SubViewport + 纯逻辑，无真实帧等待）· 快；headless 可跑。
	{"name": "vfx_cache_guard", "script": "res://tests/run_vfx_cache_guard.gd"},
]

# ② 轻量诊断件：脚本内部恒 quit(0)，无 PASS/FAIL 闸门语义（结果供人工判读）。
#    仍纳入 radial8 以便一键复现；退出码同样纳入聚合（非零 = 脚本崩了，也是真信号），
#    但在汇总表里标 INFO，提醒读者"它不会主动报错"。
#
#    🟡 **当前为空（R-2 · QG-RADIAL-01）**：原唯一的轻量诊断件 `geo8_mc` 已下放至
#    RADIAL8_DIAG_HEAVY —— 它恒 quit(0)（零闸门价值），却占 172 s ≈ 一键回归 61% 耗时。
#    保留本空表是为了不动聚合骨架：将来若有新的轻量诊断件，直接往这里加即可。
const RADIAL8_DIAG: Array = [
]

# ③ 重型诊断件：多点扫描器 / 探针 / 大样本 MC，恒 quit(0)。
#    **不进 radial8**（零闸门价值 + 耗时数十秒~数分钟），只在 `radial8diag` 下额外拉起，
#    保证它们仍然"一行命令可复现"，不游离在入口之外。
#    "args" 会作为**用户参数**传给子脚本（Godot 需要 `--` 分隔）—— 这里给 scan_attrition8
#    配粗扫档（60 局 × 步长 1.0 ≈ 6 个点），把 radial8diag 压到十分钟量级；
#    需要 300 局 × 0.5 步长的定稿级扫描时，仍请直接跑该脚本（默认档）。
const RADIAL8_DIAG_HEAVY: Array = [
	{"name": "geo8_mc", "script": "res://tests/run_slice_geo8_mc.gd"},
	{"name": "scan_attrition8", "script": "res://tests/scan_attrition8.gd", "args": ["60", "1.0"]},
	{"name": "probe_radial_aggro", "script": "res://tests/probe_radial_aggro.gd"},
]

# ---------------------------------------------------------------------------
# 实机关卡验证（world）· 2026-11-09 关卡实装
# ---------------------------------------------------------------------------
# 地形 / 镜头导航 / 结构攻防 / 建筑卡商店 / 准备阶段 / 卡面详情 / 关卡推进……
# 这些脚本一律 `extends SceneTree` + `call_deferred("run")`（要真帧），**进程内调不动**
# （`run_all()` 是异步的）→ 与 radial8 闸门同款：用 OS.execute 拉起子进程收集 exit code。
# 默认无参回归与 `-- world` 都会跑这一组。
const WORLD_GATES: Array = [
	{"name": "building_only", "script": "res://tests/run_building_only_shop_asserts.gd"},
	{"name": "shop_overlay", "script": "res://tests/run_shop_overlay_asserts.gd"},
	{"name": "shop_interaction", "script": "res://tests/run_shop_interaction_asserts.gd"},
	{"name": "battle_start", "script": "res://tests/run_battle_start_asserts.gd"},
	{"name": "preparation", "script": "res://tests/run_preparation_asserts.gd"},
	{"name": "card_description", "script": "res://tests/run_card_description_asserts.gd"},
	{"name": "placement_range", "script": "res://tests/run_placement_range_asserts.gd"},
	{"name": "stage_implementation", "script": "res://tests/run_stage_implementation_asserts.gd"},
	{"name": "structure_attacks", "script": "res://tests/run_structure_attacks_asserts.gd"},
	{"name": "battlefield_maps", "script": "res://tests/run_battlefield_maps_asserts.gd"},
	{"name": "battlefield_nav", "script": "res://tests/run_battlefield_navigation_asserts.gd"},
]


## 串行拉起 WORLD_GATES；任一子进程非零退出 = 闸门红。
func _run_world_gates() -> bool:
	print("===================================================================")
	print("world 入口 · 关卡实装 / 地形 / 镜头 / 结构攻防 / 建筑卡商店")
	print("===================================================================")
	var ok := true
	var t_all := Time.get_ticks_msec()
	for item in WORLD_GATES:
		var r: Dictionary = _subproc(item)
		if int(r["code"]) != 0:
			ok = false
	print("world 结论：%s（%.1f s）" % ["PASS" if ok else "FAIL", (Time.get_ticks_msec() - t_all) / 1000.0])
	return ok


## 聚合 `run_*_asserts.gd`（tutorial / extpack / uistyle / tlv / cardpack / campaign / combat_types）。
##   🔴 这些套件 `extends SceneTree`（为了 `--script` 能直跑，见各自文件头），所以聚合时
##   必须显式 `free()` —— `SceneTree` 带 root Window 等重资源，只 `.new()` 不释放会堆泄漏告警。
##   `var s` 刻意**不标类型**：标成 SceneTree 会让 `s.run_all()` 静态报「方法不存在」。
func _run_suite(suite: Script) -> bool:
	var s = suite.new()
	var ok: bool = s.run_all()
	s.free()
	return ok


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if (a.begins_with("slice") or a.begins_with("t1") or a == "v0radial"
				or a == "radial" or a == "geo8" or a == "radial8" or a == "radial8diag"
				or a == "repair8" or a == "aggro_golive" or a == "tutorial"
				or a == "extpack" or a == "uistyle" or a == "tlv"
				or a == "cardpack" or a == "campaign" or a == "combat_types"
				or a == "stagewaves" or a == "firecharge" or a == "frost"
				or a == "towersprites" or a == "world"):
			only = a

	var ok := true

	# 🔒 V-7 repair_on_disable 三臂诊断入口（QG-RADIAL-01 · B-3）：独立入口，
	#   🔴 **不进默认无参回归**（默认仍只跑 slice1~8 + t1aggro）。repair8 跑 3 臂 × 300 局
	#   A 路径 MC（数分钟），故单独成一键入口。子进程用 OS.execute 拉起 scan 脚本，
	#   该脚本恒 quit(0)（诊断件，判读留文策渊）；非零退出 = 脚本崩溃（真信号）。
	if only == "repair8":
		ok = _run_repair8() and ok

	# 🔴 径向一键全跑（R-1）：独立入口，不进默认无参回归。
	if only == "radial8":
		ok = _run_radial8(false) and ok
	if only == "radial8diag":
		ok = _run_radial8(true) and ok

	# 🔴 径向冒烟（阶段0 运动学）：默认 PATH 口径不变；仅 `radial` 入口切 RADIAL，
	#   跑完立即设回 PATH（SpaceModel 是全局开关，防止污染后续默认回归）。
	if only == "radial":
		_SpaceModel.mode = _SpaceModel.Mode.RADIAL
		ok = TestSuiteRadial.new().run_all() and ok
		_SpaceModel.mode = _SpaceModel.Mode.PATH
	if only == "geo8":
		ok = TestSuiteGeo8.new().run_all() and ok
	if only == "" or only == "slice1":
		ok = TestSuite.new().run_all() and ok
	if only == "" or only == "slice2":
		ok = TestSuiteSlice2.new().run_all() and ok
	if only == "" or only == "slice3":
		ok = TestSuiteSlice3.new().run_all() and ok
	if only == "" or only == "slice4":
		ok = TestSuiteSlice4.new().run_all() and ok
	if only == "" or only == "slice5":
		ok = TestSuiteSlice5.new().run_all() and ok
	if only == "" or only == "slice6":
		ok = TestSuiteSlice6.new().run_all() and ok
	if only == "" or only == "slice7":
		ok = TestSuiteSlice7.new().run_all() and ok
	if only == "" or only == "slice8":
		ok = TestSuiteSlice8.new().run_all() and ok
	if only == "" or only == "t1aggro":
		ok = TestSuiteT1Aggro.new().run_all() and ok
	# 🔴 B-1 零教学浮层（2026-11-06 · backlog ⑭）：纯 UI 状态机，进默认回归（无 MC、秒级）。
	if only == "" or only == "tutorial":
		ok = _run_suite(TestSuiteTutorial) and ok
	# 🆕 扩展包：新塔 / 新强化 / 玩家卡池开关（金标本 TOWERS / CARD_NAMES 零污染）
	if only == "" or only == "extpack":
		ok = _run_suite(TestSuiteExtPack) and ok
	# 🆕 UI 样式一致性（2026-11-07 · UI 优化轮）：面板/按钮/字号/调色板结构断言。
	if only == "" or only == "uistyle":
		ok = _run_suite(TestSuiteUIStyle) and ok
	# 🆕 塔等级牌（2026-11-07）：等级可读 + 只读快照 + 层序（纯逻辑，秒级）。
	if only == "" or only == "tlv":
		ok = _run_suite(TestSuiteTowerLevel) and ok
	# 🆕 卡包（2026-11-07）：分池 / 选包 / 解锁 / 发牌域（纯逻辑 + 一次真 runtime，秒级）。
	if only == "" or only == "cardpack":
		ok = _run_suite(TestSuiteCardPack) and ok
	# 🆕 关卡推进（2026-11-07）：推进链 / 解锁 / Ember / 存档（纯逻辑，秒级）。
	if only == "" or only == "campaign":
		ok = _run_suite(TestSuiteCampaign) and ok
	# 🆕 战斗类型（2026-11-07）：物理/魔法/真实三类型 + 抗性 + 破甲（纯逻辑 + 一次真 runtime，秒级）。
	if only == "":
		ok = _run_suite(TestSuiteIcehunter) and ok
	if only == "" or only == "frost":
		ok = _run_suite(TestSuiteFrost) and ok
	if only == "" or only == "firecharge":
		ok = _run_suite(TestSuiteFireCharge) and ok
	if only == "" or only == "combat_types":
		ok = _run_suite(TestSuiteCombatTypes) and ok
	# 🆕 关卡波表（2026-11-08）：波型串 / 守恒律 / S 加压 / 精英 / 三原型 / 导演接线
	#   （纯逻辑 + 4 次导演建表，无 MC，秒级）。🔴 默认回归含它：
	#   V-5「0-1 每一波必中性」是整条回归链的锚点，必须每次都被检查到。
	if only == "" or only == "stagewaves":
		ok = _run_suite(TestSuiteStageWaves) and ok
	# 🆕 塔身贴图（2026-11-10）：免导入 lint，守住「82 个塔原型都有 128² 贴图且互不雷同」。
	if only == "" or only == "towersprites":
		ok = _run_suite(TestSuiteTowerSprites) and ok
	# 🆕 关卡实装（2026-11-09）：地形 / 镜头 / 结构攻防 / 建筑卡商店 / 准备阶段 …
	#   进默认回归（子进程串行，约 20–40 s）；只想跑这一组时用 `-- world`。
	if only == "" or only == "world":
		ok = _run_world_gates() and ok
	# 🔴 第五刀 · 三轴合并镜像退化逐位守护（独立入口，**不进**默认无参回归 → 九段聚合读数逐位不变）。
	if only == "aggro_golive":
		ok = TestSuiteAggroGolive.new().run_all() and ok
	if only == "v0radial":
		var candidate = _Geo.new(R2_SLOTS)
		ok = TestSuite.new().run_radial_golden(candidate) and ok
		ok = TestSuiteSlice2.new().run_v0_radial(candidate) and ok

	quit(0 if ok else 1)


# ─────────────────────────────────────────────────────────────────────────────
# radial8 聚合入口实现
# ─────────────────────────────────────────────────────────────────────────────

## 子进程用哪个 Godot：优先环境变量 GODOT_BIN（CI 或本机与 IDE 版本不一致时可钉死），
## 否则 OS.get_executable_path()。注意 headless --script 下它返回的是 GUI 版 exe
## （非 _console.exe），但 --headless 下 stdout 仍可被 OS.execute 捕获（已实测）。
func _godot_bin() -> String:
	var env := OS.get_environment("GODOT_BIN")
	if env != "" and FileAccess.file_exists(env):
		return env
	return OS.get_executable_path()


## 串行拉起一个独立 SceneTree 验证脚本（radial8 / world 共用），收集 exit code / 耗时 / 输出。
## 返回值：{"name": String, "code": int, "ms": int, "marks": int}
##   marks = 该子脚本输出中 "[FAIL]" 标记出现次数（进程内套件没有这一项，记 -1）。
func _subproc(item: Dictionary) -> Dictionary:
	var name := String(item["name"])
	var script := String(item["script"])
	var exe := _godot_bin()
	var argv: Array = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", script,
	]
	# 可选用户参数（Godot 需要 `--` 分隔符才会把它们交给脚本的 get_cmdline_user_args()）。
	if item.has("args") and (item["args"] as Array).size() > 0:
		argv.append("--")
		argv.append_array(item["args"])

	# 路径写错要响亮地失败，而不是让 Godot 静默退出 0 —— 否则聚合网会假绿。
	if not FileAccess.file_exists(exe):
		print("[gate] 失败：%s · Godot 可执行文件不存在：%s" % [name, exe])
		return {"name": name, "code": 1, "ms": 0}
	if not FileAccess.file_exists(script):
		print("[gate] 失败：%s · 验证脚本不存在：%s" % [name, script])
		return {"name": name, "code": 1, "ms": 0}

	print("")
	print("[gate] ────────── %s ──────────" % name)
	var out: Array = []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(exe, argv, out, true)
	var dt := Time.get_ticks_msec() - t0

	# 统计子脚本输出里的 [FAIL] 标记数（ASCII，不受中文乱码影响，便于快速定位失败段）。
	var fail_marks := 0
	var blob := ""
	for chunk in out:
		blob += String(chunk)
	fail_marks = blob.count("[FAIL]")

	for chunk in out:
		print(String(chunk))
	# 注意：本行**故意不写 "[FAIL]"** —— 让 `[FAIL]` 在聚合日志里只可能来自子脚本真实断言失败，
	# 便于 CI 直接 grep `[FAIL]` 而不被聚合器自身标签误报。
	print("[gate] ────────── %s 结束 · exit=%d · %d ms · 失败标记 %d 处 ──────────"
		% [name, code, dt, fail_marks])
	return {"name": name, "code": code, "ms": dt, "marks": fail_marks}


## 🔒 V-7 repair8 入口（QG-RADIAL-01 · B-3）：单跑三臂诊断扫描（子进程，恒 exit 0 语义）。
func _run_repair8() -> bool:
	print("===================================================================")
	print("repair8 入口 · V-7 repair_on_disable 三臂诊断扫描")
	print("===================================================================")
	var item := {"name": "scan_repair_on_disable", "script": "res://tests/scan_repair_on_disable.gd"}
	var r: Dictionary = _subproc(item)
	# scan 脚本是诊断件（恒 quit 0）；非零退出 = 脚本崩溃（真信号 → 计失败）。
	return int(r["code"]) == 0


## radial8 / radial8diag 主体。
## include_heavy=true 时额外拉起 RADIAL8_DIAG_HEAVY（重型扫描器/探针）。
func _run_radial8(include_heavy: bool) -> bool:
	var results: Array = []
	var ok := true
	var t_all := Time.get_ticks_msec()

	print("===================================================================")
	print("radial8 聚合入口 · 径向验证脚本一键全跑")
	print("  include_heavy_diag = %s" % str(include_heavy))
	print("===================================================================")

	# ---- ① 进程内套件（沿用 geo8 / radial 既有 preload 机制）----
	print("\n[radial8] ────────── geo8（八槽几何 E8-A，进程内套件）──────────")
	var t1 := Time.get_ticks_msec()
	var ok_geo8 := TestSuiteGeo8.new().run_all()
	results.append({
		"name": "geo8(套件)", "code": 0 if ok_geo8 else 1,
		"ms": Time.get_ticks_msec() - t1,
	})
	ok = ok_geo8 and ok

	print("\n[radial8] ────────── radial（阶段0 运动学，进程内套件）──────────")
	var t2 := Time.get_ticks_msec()
	# SpaceModel 是全局开关：跑完立即设回 PATH，防止污染同进程内后续默认回归。
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL
	var ok_radial := TestSuiteRadial.new().run_all()
	_SpaceModel.mode = _SpaceModel.Mode.PATH
	results.append({
		"name": "radial(套件)", "code": 0 if ok_radial else 1,
		"ms": Time.get_ticks_msec() - t2,
	})
	ok = ok_radial and ok

	# ---- ② 闸门件（子进程）----
	for item in RADIAL8_GATES:
		var r: Dictionary = _subproc(item)
		results.append(r)
		if int(r["code"]) != 0:
			ok = false

	# ---- ③ 轻量诊断件（子进程，恒 exit 0）----
	for item in RADIAL8_DIAG:
		var rd: Dictionary = _subproc(item)
		rd["diag"] = true
		results.append(rd)
		if int(rd["code"]) != 0:
			ok = false

	# ---- ④ 重型诊断件（仅 radial8diag）----
	if include_heavy:
		for item in RADIAL8_DIAG_HEAVY:
			var rh: Dictionary = _subproc(item)
			rh["diag"] = true
			results.append(rh)
			if int(rh["code"]) != 0:
				ok = false

	# ---- 汇总 ----
	var total_ms: int = Time.get_ticks_msec() - t_all
	print("")
	print("===================================================================")
	print("radial8 汇总（%d 项 · 总耗时 %.1f s）" % [results.size(), total_ms / 1000.0])
	print("===================================================================")
	for r in results:
		var name := String(r.get("name", "?"))
		var code := int(r.get("code", 0))
		var ms := int(r.get("ms", 0))
		var status := "PASS"
		if code != 0:
			status = "FAIL"
		elif bool(r.get("diag", false)):
			status = "INFO"
		var marks := int(r.get("marks", -1))
		var marks_s := "   -" if marks < 0 else str(marks).lpad(4)
		# 同上：汇总表也不用 "[FAIL]" 字面量，避免污染 grep。
		print("  [%s] %s exit=%d %s ms  失败标记x%s" % [
			status, name.rpad(22), code, str(ms).lpad(7), marks_s,
		])
	print("===================================================================")
	print("radial8 结论：%s（exit %d）" % ["PASS" if ok else "FAIL", 0 if ok else 1])
	print("===================================================================")
	return ok
