extends SceneTree
##
## 音频资产 lint（免导入）—— 兜住「SFX_FILES 打错 key/路径 → 运行时静默 null」盲区
##
## 依据：`docs/phase6/audio-verify.md` G-6（team-lead 2026-10-13 批准补门禁）
## 跑法：`<godot> --headless --path . --script res://tests/lint_audio_assets.gd` → EXIT=0/1
##
## 机理：对 `audio_director.gd` 的 `SFX_FILES` / `STEM_FILES` **逐条**做
##   `FileAccess.file_exists(AUDIO_DIR + rel)`（裸文件系统 stat）——
##   🔴 **不依赖资源导入**（不用 ResourceLoader / 不查 `.godot/imported`），故任何环境可跑，
##      且天然覆盖 `--headless --script` 无导入的真实场景（CI 与本地一致）。
## 🔴 大小写敏感：本 lint 在 Linux CI 上是精确大小写匹配 → 顺带守住 Windows 开发机上
##    「大小写不符但本地恰好能过」的路径隐患（已人工核对 25 条 0 mismatch）。
##
## ⚠️ G6：headless `--script` 无 global_script_class_cache → 一律 preload，无 class_name。
##

const AD := preload("res://scripts/audio/audio_director.gd")

var _fail := 0
var _checked := 0


func _initialize() -> void:
	print("=== 音频资产 lint（免导入 · 大小写敏感）===")
	var ok := true
	ok = _check_map("SFX_FILES", AD.SFX_FILES) and ok
	ok = _check_list("STEM_FILES", AD.STEM_FILES) and ok

	# 机制自证：`_src/` 带 `.gdignore`（Godot 永不导入）→ FileAccess 仍可读
	#   ⇒ 证明本 lint 走的是裸文件系统（与导入状态无关），而非资源导入库。
	var probe := String(AD.AUDIO_DIR) + "_src/manifest.json"
	print("[info] 机制自证：FileAccess 读 _src/（.gdignore · Godot 不导入）= %s"
		% str(FileAccess.file_exists(probe)))

	print("汇总：检查 %d 条 · %s（缺失 %d）" % [_checked, "PASS" if ok else "FAIL", _fail])
	quit(0 if ok else 1)


func _check_map(label: String, d) -> bool:
	var ok := true
	if not (d is Dictionary):
		print("[FAIL] %s 不是 Dictionary（源码结构变了？）" % label)
		_fail += 1
		return false
	var keys: Array = (d as Dictionary).keys()
	keys.sort()
	for k in keys:
		var rel := String((d as Dictionary)[k])
		if not _probe(label, "key=%s" % String(k), rel):
			ok = false
	print("[info] %s：%d 条" % [label, keys.size()])
	return ok


func _check_list(label: String, arr) -> bool:
	var ok := true
	if not (arr is Array):
		print("[FAIL] %s 不是 Array（源码结构变了？）" % label)
		_fail += 1
		return false
	var a: Array = arr
	for i in range(a.size()):
		if not _probe(label, "idx=%d" % i, String(a[i])):
			ok = false
	print("[info] %s：%d 条" % [label, a.size()])
	return ok


func _probe(label: String, who: String, rel: String) -> bool:
	_checked += 1
	if rel == "":
		print("[FAIL] %s  %s → 空路径" % [label, who])
		_fail += 1
		return false
	var path := String(AD.AUDIO_DIR) + rel
	if FileAccess.file_exists(path):
		print("[ ok ] %s  %s → %s" % [label, who, path])
		return true
	print("[FAIL] %s  %s → %s （文件不存在 / 大小写不符）" % [label, who, path])
	_fail += 1
	return false
