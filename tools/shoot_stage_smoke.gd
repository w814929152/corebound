extends SceneTree
##
## 实机截图冒烟（非 CI · 窗口模式）：选关航图贴图包（资产包 v3）目检
##   ① 初期全锁 —— 节点贴图（白环染章节色）+ 锁定专件 + 章节徽记目录
##   ② 中期进度 —— 已通关辉金染色 + 金色推进链 + 当前节点章节色光环
##   ③ 悬停     —— 白光环 tint（α0.65）+ 悬停放大 1.08
## 运行：<godot> --path . --script res://tools/shoot_stage_smoke.gd
## 产物：art/_review/smoke_stage_map_lock.png / _progress.png / _hover.png
##
## 🔴 选关画布没有 per-frame 重绘：直接改 `_hovered` 后必须手动 queue_redraw，
##    否则拍到的是旧帧（与 shoot_hud_smoke 血条同款坑）。
## 🔴 窗口偶发前 N 帧不渲染（与并行 Godot 实例抢焦点时实测复现），拍到 Godot
##    默认清屏灰 (0.3,0.3,0.3) 就顺延下一帧再试，不落盘。
## 🔴 时序用「链式驱动」：拍到上一张 → 立刻切换剧情态 → 排队下一张。
##    （定时注入有竞态：灰帧顺延会让截图跨过注入点，拍到错误状态。）
##
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")

var _f := 0
var _ss: Node
var _camp: RefCounted
var _pending: Array = []     # [{name, min_f}]（链式：拍到一张才挂下一张）


func _initialize() -> void:
	_camp = load("res://scripts/gameplay/campaign.gd").new()
	_ss = _StageSelect.new()
	root.add_child(_ss)
	_pending.append({"name": "smoke_stage_map_lock.png", "min_f": 25})
	# 🔴 并行 Godot 实例在跑时本窗口可能被压着不渲染 → 强制前台
	DisplayServer.window_move_to_foreground()


## 拍完 `fname` 后切换到下一剧情态并排队下一张截图。
func _advance(fname: String) -> void:
	match fname:
		"smoke_stage_map_lock.png":
			# 中期进度：第一章前三关通关（辉金 + 金链）→ 2-1 解锁
			#   🔴 第一章只有 3 关（3+3+3+1=10），"1-4" 不存在会被 set_current_stage 拒绝
			for sid in ["1-1", "1-2", "1-3"]:
				_camp.call("mark_cleared", sid)
			_camp.call("set_current_stage", "2-1")   # 解锁且未通关 → 当前态
			_ss.call("open", _camp)   # 重开刷新（open 内部会 _refresh + redraw）
			_pending.append({"name": "smoke_stage_map_progress.png", "min_f": _f + 8})
		"smoke_stage_map_progress.png":
			_ss.set("_hovered", "1-1")   # 悬停已通关节点：白光环压在辉金节点上
			_ss.call("_refresh_detail")
			_ss._canvas.queue_redraw()   # 🔴 无 per-frame 重绘，必须手动刷
			_pending.append({"name": "smoke_stage_map_hover.png", "min_f": _f + 8})


func _process(_d: float) -> bool:
	_f += 1
	# 🔴 open() 必须在树跑起来之后调（_initialize 里调会被随后触发的 _ready
	#    visible=false 盖掉 —— 与 shoot_main_menu 同款坑）；第 5 帧最稳。
	if _f == 5:
		_ss.call("open", _camp)
	if _pending.size() > 0:
		var job: Dictionary = _pending[0]
		if _f >= int(job["min_f"]):
			var img := root.get_viewport().get_texture().get_image()
			var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var is_clear_gray := c.r > 0.29 and c.r < 0.31 and c.g > 0.29 and c.g < 0.31 and c.b > 0.29 and c.b < 0.31
			if not is_clear_gray:
				_pending.pop_front()
				var fname := String(job["name"])
				img.save_png("res://art/_review/" + fname)
				print("[shot] art/_review/", fname, " @frame ", _f)
				_advance(fname)
	if _f > 600 or (_f > 90 and _pending.size() == 0):
		if _pending.size() > 0:
			print("[WARN] 截图未完成：", _pending)
		return true
	return false
