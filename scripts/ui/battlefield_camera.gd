extends RefCounted
## 战场镜头状态；单位、命中特效、拖放与地面共用唯一变换。
const Maps := preload("res://scripts/data/battlefield_maps.gd")
const MIN_ZOOM := 0.6
const MAX_ZOOM := 2.4
const DEFAULT_ZOOM := 1.0
const CLOSE_VIEW := 1.5
static var zoom := DEFAULT_ZOOM
static var focus := Maps.CORE

static func reset() -> void:
	zoom = DEFAULT_ZOOM
	focus = Maps.CORE

static func view_rect(viewport: Vector2) -> Rect2:
	return Rect2(48.0,140.0,maxf(240.0,viewport.x-96.0),maxf(240.0,viewport.y-310.0))

static func _scale(viewport: Vector2) -> float:
	var rect := view_rect(viewport)
	return minf(rect.size.x/(Maps.CAMERA_EXTENT.x*2.0),rect.size.y/(Maps.CAMERA_EXTENT.y*2.0))*CLOSE_VIEW*zoom

static func _clamp_focus(viewport: Vector2) -> void:
	var half_view := view_rect(viewport).size / (2.0*_scale(viewport))
	var limit := (Maps.CAMERA_EXTENT-half_view+Vector2(12,12)).max(Vector2.ZERO)
	focus = Maps.CORE + (focus-Maps.CORE).clamp(-limit,limit)

static func pan(screen_delta: Vector2, viewport: Vector2) -> void:
	focus -= screen_delta/_scale(viewport)
	_clamp_focus(viewport)

static func zoom_at(factor: float, anchor: Vector2, viewport: Vector2) -> void:
	var rect := view_rect(viewport)
	var world_anchor := focus+(anchor-rect.get_center())/_scale(viewport)
	zoom = clampf(zoom*factor,MIN_ZOOM,MAX_ZOOM)
	focus = world_anchor-(anchor-rect.get_center())/_scale(viewport)
	_clamp_focus(viewport)

static func overview() -> void:
	zoom = 1.0/CLOSE_VIEW
	focus = Maps.CORE

static func terrain_transform(viewport: Vector2) -> Dictionary:
	_clamp_focus(viewport)
	var scale := _scale(viewport)
	var center := view_rect(viewport).get_center()
	return {"sc":scale,"ox":center.x-focus.x*scale,"oy":center.y-focus.y*scale}
