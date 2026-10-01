class_name Geo6
extends RefCounted
##
## 🔴 定稿地图 = 方案 A（damage-pipeline v1.0.4 D-11）
##   沿用 sim 真身坐标 `corebound_sim_v03.py:71 SLOTS6`，核心在路径终点 (55,25)、塔堆一侧。
##   0.65 口径下 k=3.67 / k_deep=3.56 / 枢纽 S1·S2（度 5）→ 保住 P1「位置即策略」。
##
## ⚠️ 塔位编号与 v03 一致（0-based）：
##     S0(6,33)  S1(22,40)  S2(30,33)  S3(45,33)  S4(18,16)  S5(48,42)
##
## ⚠️ 用 `preload` 而不是 `class_name Geo`：headless 跑 `--script` 时不会先做编辑器导入，
##    全局类名表（.godot/global_script_class_cache.cfg）可能还没生成 → 类型解析失败。
##

const _Geo := preload("res://scripts/geo/geo.gd")

const SLOTS6: Array = [
	Vector2(6.0, 33.0), Vector2(22.0, 40.0), Vector2(30.0, 33.0),
	Vector2(45.0, 33.0), Vector2(18.0, 16.0), Vector2(48.0, 42.0),
]

const SLOTS4: Array = [
	Vector2(6.0, 33.0), Vector2(22.0, 40.0), Vector2(30.0, 33.0),
	Vector2(45.0, 33.0),
]


static func build():
	return _Geo.new(SLOTS6)


static func build4():
	return _Geo.new(SLOTS4)
