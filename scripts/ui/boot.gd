extends Node
##
## 最小启动场景（MVP 切片1 → 切片3）。
## · headless（CI / --quit）下自动跑测试套件，失败则非零退出码；
## · 窗口模式下装载切片3 骨架场景（战场占位 + 商店抽屉占位），不跑自测。
##
## 🔴 G6：headless `--script` 没有 global_script_class_cache → 一律 preload。
##

const TestSuite := preload("res://tests/test_suite.gd")
const TestSuiteSlice3 := preload("res://tests/test_suite_slice3.gd")
const TestSuiteSlice4 := preload("res://tests/test_suite_slice4.gd")
const BattleShop := preload("res://scenes/battle_shop.tscn")
const SpaceModel := preload("res://scripts/geo/space_model.gd")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		var ok := TestSuite.new().run_all()
		ok = TestSuiteSlice3.new().run_all() and ok
		ok = TestSuiteSlice4.new().run_all() and ok
		get_tree().quit(0 if ok else 1)
	else:
		# 🔴 径向迁移收官：实机运行时默认 = RADIAL（径向核心围攻）。
		#    注入点选在这里而非 `space_model.gd:40` 的全局默认值，是因为：
		#      · `SpaceModel.mode` 是全局静态变量，被 PATH 口径金标本回归（run_tests.gd
		#        默认无参 = slice1~8 + t1aggro）**隐式依赖**——它们自身不碰 mode，但
		#        依赖的引擎（wave_sim / monster / wave_director）用 is_radial() 分派。
		#        改全局默认会让 PATH 金标本全部分派到 RADIAL 分支而全挂。
		#      · 本分支只在**窗口模式**执行；headless 分支（跑测试套件）与
		#        `--script res://tests/run_tests.gd` 两条路径都**永不进入这里**
		#        （后者根本不装载 main.tscn）→ 金标本零扰动。
		#    回滚：把下面这行删掉 / 改回 `Mode.PATH` 即可（一行回退，双模设计本就为此）。
		SpaceModel.mode = SpaceModel.Mode.RADIAL
		add_child(BattleShop.instantiate())
		print("[boot] SpaceModel.mode = RADIAL（径向核心围攻 · 实机默认）")
		print("[boot] Corebound MVP · 切片4（实时商店覆盖层 + 完整商店逻辑接线）")
		print("[boot] Tab 开关抽屉 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位")
		print("[boot] 商品位显示真实卡名/价格；建筑卡买入后入待放置队列 → 点「放置」→ 点塔位落子")
		print("[boot] 自测只在 headless 下执行（<godot> --headless --script res://tests/run_tests.gd）")
