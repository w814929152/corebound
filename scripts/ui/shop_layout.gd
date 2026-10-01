extends RefCounted
##
## C3 双焦点布局的唯一算尺（GDD §2.4）。
##
## 🔴 两条约束同时生效，本文件是唯一裁决点：
##   · 抽屉宽度 = 屏宽 × `OVERLAY_WIDTH_RATIO`（0.32，基准 1080p/1920 → 614px）
##   · 抽屉宽度 **不得 < 560px**（`OVERLAY_MIN_WIDTH_PX`，WCAG AA 可访问性红线）
##   → 取 **max()**，两条都满足。
##
## ✅ Q-S3-C 已拍板（主理人 2026-10-01，GDD v1.2）：视口提到 **1920×1080**（GDD §2.4 基准屏）。
##    基准屏下两条约束正好一致：0.32 × 1920 = **614.4px** → 抽屉 32% / 战场 68%，与 GDD 完全吻合。
##
## ⚠️ `maxf()` 仍然保留 —— 它是**非基准屏的安全网**：
##    窗口 resize + `stretch/aspect=expand` 会让视口宽偏离 1920（例如缩到 1280 时
##    0.32×1280 = 409.6px < 560px → 最小宽压过比例，抽屉占 43.75%）。
##    这是**有意行为**（WCAG AA 可访问性红线优先），不是 bug。
##

const _Cfg := preload("res://scripts/engine/mvp_config.gd")


## 抽屉宽度（px）。
static func drawer_width(viewport_w: float) -> float:
	return maxf(_Cfg.OVERLAY_MIN_WIDTH_PX, viewport_w * _Cfg.OVERLAY_WIDTH_RATIO)


## 战场可视宽度（px）—— 抽屉展开时战场被压到的那部分；抽屉收起时为全屏。
static func battlefield_width(viewport_w: float, drawer_visible: bool) -> float:
	if not drawer_visible:
		return viewport_w
	return maxf(0.0, viewport_w - drawer_width(viewport_w))


## 抽屉占屏比（给自测 / 文档打印用）。
static func drawer_ratio(viewport_w: float) -> float:
	return drawer_width(viewport_w) / viewport_w
