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

const TestSuite := preload("res://tests/test_suite.gd")
const TestSuiteSlice2 := preload("res://tests/test_suite_slice2.gd")
const TestSuiteSlice3 := preload("res://tests/test_suite_slice3.gd")
const TestSuiteSlice4 := preload("res://tests/test_suite_slice4.gd")
const TestSuiteSlice5 := preload("res://tests/test_suite_slice5.gd")


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("slice"):
			only = a

	var ok := true
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

	quit(0 if ok else 1)
