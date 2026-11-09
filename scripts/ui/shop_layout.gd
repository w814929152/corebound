extends RefCounted
## 商店为顶部横向卡牌浮层，地图始终按完整视口绘制。
## 面板宽度保留比例与最小宽度约束；HUD、背包单独避让浮层。

const _Cfg := preload("res://scripts/engine/mvp_config.gd")


## 抽屉宽度（px）。
static func drawer_width(viewport_w: float) -> float:
	return maxf(_Cfg.OVERLAY_MIN_WIDTH_PX, viewport_w * _Cfg.OVERLAY_WIDTH_RATIO)


## 商店覆盖在地图上，开关商店不改变地图与特效的坐标映射。
static func battlefield_width(viewport_w: float, _drawer_visible: bool) -> float:
	return viewport_w


## 抽屉占屏比（给自测 / 文档打印用）。
static func drawer_ratio(viewport_w: float) -> float:
	return drawer_width(viewport_w) / viewport_w


## HUD、背包、教学共用商店之外的安全区域。
static func content_width(viewport_w: float, _director: Node) -> float:
	return viewport_w
