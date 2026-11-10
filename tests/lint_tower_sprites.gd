extends SceneTree
##
## 塔身贴图 lint（免导入）—— 兜住「新增塔原型没有贴图 / 贴图塌回同一模板」的盲区
##
## 背景：v1 的 15 张 sp_tower_* 由同一八边形模板批量烘焙，只有中心小徽记不同；
##   且 TOWERS_EXT 有 60+ 个可摆放原型没有贴图，运行时静默降级成默认三角（与 Arrow 撞脸）。
##   v2 生成器 tools/gen_tower_sprites_v2.py 按数值 SSOT 一次补齐全部原型，本 lint 守住覆盖率。
##
## 跑法：<godot> --headless --path . --script res://tests/lint_tower_sprites.gd → EXIT=0/1
##   与 lint_audio_assets.gd 同款：只用 FileAccess 裸文件系统 stat + 读 PNG 头，
##   🔴 不依赖 Godot 资源导入（headless --script / CI 未跑 --import 时同样成立）。
##   大小写敏感：Linux CI 上精确匹配，顺带守住 Windows 开发机的路径大小写隐患。
##
## ⚠️ headless --script 无 global_script_class_cache → 一律 preload，无 class_name。
##

const TD := preload("res://scripts/data/tower_data.gd")

const SPRITE_DIR := "res://art/2d/sprites/"
const EXPECT_SIZE := 128
const PNG_SIG := [137, 80, 78, 71, 13, 10, 26, 10]

var _fail := 0
var _checked := 0
var _hashes := {}


func _initialize() -> void:
	quit(0 if run_all() else 1)


## 双入口：直跑走 _initialize() + quit；被 run_tests.gd 进程内聚合时走 .new().run_all()
## （.new() 不触发 _initialize()，故此处绝不能调用 quit）。
func run_all() -> bool:
	_fail = 0
	_checked = 0
	_hashes.clear()
	print("=== 塔身贴图 lint（免导入 · 大小写敏感）===")
	var names: Array = []
	for k in TD.TOWERS.keys():
		names.append(String(k))
	for k in TD.TOWERS_EXT.keys():
		names.append(String(k))

	for ctype in names:
		_check_one(ctype)

	# 反向：目录里不应残留不属于数值 SSOT 的塔贴图（防止原型改名后留垃圾）
	var dir := DirAccess.open(SPRITE_DIR)
	if dir != null:
		for fname in dir.get_files():
			if fname.begins_with("sp_tower_") and fname.ends_with("_v1.png"):
				var stem := fname.substr(9, fname.length() - 9 - 7)
				var known := false
				for ctype in names:
					if ctype.to_lower() == stem:
						known = true
						break
				if not known:
					_fail += 1
					print("[FAIL] 目录中存在无对应原型的贴图：%s" % fname)

	print("汇总：检查 %d 个塔原型 · 贴图 %d 张 · %s（失败 %d）"
		% [names.size(), _checked, "PASS" if _fail == 0 else "FAIL", _fail])
	return _fail == 0


func _check_one(ctype: String) -> void:
	var path := SPRITE_DIR + "sp_tower_" + ctype.to_lower() + "_v1.png"
	if not FileAccess.file_exists(path):
		_fail += 1
		print("[FAIL] %s：缺少 %s" % [ctype, path])
		return
	_checked += 1

	var f := FileAccess.open(path, FileAccess.READ)
	var head := f.get_buffer(24)
	f.close()
	if head.size() < 24:
		_fail += 1
		print("[FAIL] %s：PNG 头不足 24 字节" % ctype)
		return
	for i in range(8):
		if head[i] != PNG_SIG[i]:
			_fail += 1
			print("[FAIL] %s：不是合法 PNG" % ctype)
			return
	var w := (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19]
	var h := (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23]
	if w != EXPECT_SIZE or h != EXPECT_SIZE:
		_fail += 1
		print("[FAIL] %s：尺寸 %dx%d，契约要求 %dx%d（monster_layer 的 tsize=4.0*sc）"
			% [ctype, w, h, EXPECT_SIZE, EXPECT_SIZE])

	# 视觉区分度的最小守卫：任意两张塔贴图不得逐字节相同。
	var md5 := FileAccess.get_md5(path)
	if _hashes.has(md5):
		_fail += 1
		print("[FAIL] %s：与 %s 的贴图完全相同（塌回同一模板）"
			% [ctype, String(_hashes[md5])])
	else:
		_hashes[md5] = ctype
