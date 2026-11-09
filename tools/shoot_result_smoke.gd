extends SceneTree
##
## shoot_stage_result_smoke.gd —— 结算页两态冒烟截图（asset-pack-v4-result 验证）
##
## 拍 2 张（链式驱动防竞态，拍到一张才排下一张）：
##   art/_review/smoke_result_won.png   胜利态（金核辉光 + 金横幅）
##   art/_review/smoke_result_lost.png  失败态（红裂纹 + 红横幅）
##
## 🔴 坑（历次会话沉淀）：
##   · 窗口偶发前 N 帧不渲染（灰帧 0.3,0.3,0.3）→ 拍前校验非灰，灰则顺延重试；
##   · 灰帧重试会让截图跨过剧情注入点 → 「拍到一张才切态」的链式驱动。
##

var _f := 0
var _ov: CanvasLayer = null
const _ResultOverlay := preload("res://scripts/ui/result_overlay.gd")

# 待拍队列：min_f = 最早帧（防 0 帧未渲染）
var _pending: Array = [
	{"name": "smoke_result_won.png", "min_f": 30},
	{"name": "smoke_result_lost.png", "min_f": 30},
]


func _initialize() -> void:
	_ov = _ResultOverlay.new()
	root.add_child(_ov)
	# 🔴 open/show 在 _initialize 里调会被随后 _ready 的 visible=false 盖掉 → 挪到 _process 第 5 帧


func _process(_d: float) -> bool:
	_f += 1
	if _f == 5:
		_ov.call("show_result", true, 20, 640.0, 1000.0, 318.0)
	if _pending.is_empty():
		if _f > 120:
			return true                      # 收尾退出
		return false
	var item: Dictionary = _pending[0]
	if _f < int(item["min_f"]):
		return false
	# 拍前校验：中心像素若为 Godot 默认清屏灰 → 顺延 5 帧重试
	var img := root.get_viewport().get_texture().get_image()
	var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	if c.is_equal_approx(Color(0.3, 0.3, 0.3)):
		item["min_f"] = _f + 5
		return false
	img.save_png("res://art/_review/" + String(item["name"]))
	print("[shot] ", item["name"], " f=", _f)
	_pending.pop_front()
	# 拍到一张才切下一态（链式防竞态）
	if _pending.size() > 0:
		_ov.call("show_result", false, 12, 0.0, 1000.0, 512.0)
	return false
