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


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		var ok := TestSuite.new().run_all()
		ok = TestSuiteSlice3.new().run_all() and ok
		ok = TestSuiteSlice4.new().run_all() and ok
		get_tree().quit(0 if ok else 1)
	else:
		add_child(BattleShop.instantiate())
		print("[boot] Corebound MVP · 切片4（实时商店覆盖层 + 完整商店逻辑接线）")
		print("[boot] Tab 开关抽屉 · Esc 关闭/取消 · R 刷新 · 1/2/3 选中即买 · Space 锁定焦点位")
		print("[boot] 商品位显示真实卡名/价格；建筑卡买入后入待放置队列 → 点「放置」→ 点塔位落子")
		print("[boot] 自测只在 headless 下执行（<godot> --headless --script res://tests/run_tests.gd）")
