extends "res://tests/run_tests.gd"
## 聚合回归会写测试存档；在同一进程中备份并恢复，避免覆盖玩家关卡进度。
func _initialize() -> void:
	var files := ["user://save.json", "user://card_packs.json"]
	var backups: Dictionary = {}
	for path in files:
		if FileAccess.file_exists(path):
			backups[path] = FileAccess.get_file_as_bytes(path)
	super._initialize()
	for path in files:
		if backups.has(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backups[path])
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("[stage regression] Player save files restored")
