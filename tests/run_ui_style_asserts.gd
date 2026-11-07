extends RefCounted
##
## headless 断言 —— UI 样式一致性（`scripts/ui/ui_style.gd` + 三处玩家可见界面）
##
## 背景：UI 优化轮之前，`shop_overlay.gd` **一个 StyleBox 都没有** ——
##   抽屉透明、3 张商品位是"漂浮文字"、十余个按钮走 Godot 默认主题。
##   直接违反 `design/art/art-bible.md` §5.1「禁止使用系统默认控件」。
##   本套件把该缺陷**钉成可回归的断言**，防止以后再退回去。
##
## 🔴 断言口径（全部可 headless 判定，不依赖绘制 / 不需要窗口）：
##    A 面板有底：商店底座与每个商品位都挂了 `panel` StyleBox（原缺陷的直接反证）
##    B 无系统默认控件：所有 Button 的 normal/hover/pressed/disabled 四态都是自定义 StyleBox
##    C 字号下限：玩家可见 Label 一律 ≥16px（F3 调试面板为 dev-only 豁免，跳过其子树）
##    D X3：三个商品位 `custom_minimum_size` 完全相同，且只由 `SLOT_SIZE` 决定
##    E 无占位文案：玩家界面里不得残留「后续切片 / 🟡」这类开发占位
##    F 调色板：`ui_style.gd` 的色值逐字等于 art-bible §2.2 登记值（防二次发明颜色）
##    G 抽屉布局：`drawer_width` 读数不变（32% / 最小 560）—— UI 改版不得动双焦点比例
##    H 弹窗：结算 / 回收确认 / 受损塔处置同样不得用系统默认控件
##    I 卡面描述：每张卡都必须回答「这张卡干什么」——恒 3 行、数值现取自 SSOT、
##      无强弱评价词（C-3 / SR-R2）、无占位痕迹
##
## 跑法：
##   <godot> --headless --path . --script res://tests/run_tests.gd -- uistyle
##

const _Style := preload("res://scripts/ui/ui_style.gd")
const _Shop := preload("res://scripts/ui/shop_overlay.gd")
const _Hud := preload("res://scripts/ui/hud.gd")
const _Hp := preload("res://scripts/ui/core_hp_bar.gd")
const _ShopLayout := preload("res://scripts/ui/shop_layout.gd")
const _Result := preload("res://scripts/ui/result_overlay.gd")
const _Salvage := preload("res://scripts/ui/salvage_confirm_dialog.gd")
const _DisabledDialog := preload("res://scripts/ui/disabled_tower_dialog.gd")
const _CardText := preload("res://scripts/data/card_text.gd")
const _TD := preload("res://scripts/data/tower_data.gd")

const FONT_MIN := 16

var _pass := 0
var _fail := 0


func run_all() -> bool:
	_log("")
	_log("=".repeat(78))
	_log("UI 样式一致性（ui_style + 商店 / HUD / 核心血条）")
	_log("基准：art-bible §2.2 调色板 · §5.1 控件规范 · §5.2 层级 · §9.1 最小字号")
	_log("=".repeat(78))

	_test_a_panels()
	_test_b_no_default_controls()
	_test_c_font_floor()
	_test_d_x3_slot_size()
	_test_e_no_placeholder()
	_test_f_palette()
	_test_g_drawer_layout()
	_test_h_dialogs()
	_test_i_card_text()

	_log("")
	_log("=".repeat(78))
	_log("汇总：通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	if _fail == 0:
		_log("[OK] UI 样式收敛 —— 无系统默认控件、字号达标、三位同构、调色板对齐 art-bible")
	else:
		_log("[NG] 有 %d 项未过 —— 见上方 FAIL 行" % _fail)
	_log("=".repeat(78))
	return _fail == 0


# ---------------------------------------------------------------------------
#  构建助手（不进场景树：只调 `_build()`，不触发 `_ready` / 布局 / 绘制）
# ---------------------------------------------------------------------------
func _make_shop() -> Control:
	var c: Control = _Shop.new()
	c._build()
	return c


func _make_hud() -> Control:
	var c: Control = _Hud.new()
	c._build()
	return c


func _make_hp() -> Control:
	var c: Control = _Hp.new()
	c._build_boxes()
	return c


func _collect(n: Node, out: Array, type_check: String) -> Array:
	for ch in n.get_children():
		if type_check == "button" and ch is Button:
			out.append(ch)
		elif type_check == "label" and ch is Label:
			out.append(ch)
		_collect(ch, out, type_check)
	return out


# ---------------------------------------------------------------------------
#  A 面板有底（原缺陷直接反证）
# ---------------------------------------------------------------------------
func _test_a_panels() -> void:
	_log("")
	_log("--- [A] 面板 / 卡片都挂 StyleBox（改造前商店全透明：零 StyleBox）---")
	var shop := _make_shop()
	_check("商店抽屉底座有 panel StyleBox",
		shop._panel != null and shop._panel.has_theme_stylebox_override("panel"))
	var n_cards := 0
	for p in shop._slots:
		if (p as Control).has_theme_stylebox_override("panel"):
			n_cards += 1
	_check_int("3 个商品位都挂了卡片 StyleBox", n_cards, 3)
	shop.free()

	var hud := _make_hud()
	_check("HUD 缓存了积分卡 StyleBox（不在 _draw 里 new）", hud._box_score != null)
	_check("HUD 缓存了波次条轨道 StyleBox", hud._box_bar_track != null)
	_check("HUD 缓存了波次条填充 StyleBox", hud._box_bar_fill != null)
	hud.free()

	var hp := _make_hp()
	_check("核心血条缓存了底槽 StyleBox", hp._box_slot != null)
	_check("核心血条缓存了分段 StyleBox（圆角段）", hp._box_seg != null)
	hp.free()


# ---------------------------------------------------------------------------
#  B 无系统默认控件（§5.1 硬要求）
# ---------------------------------------------------------------------------
func _test_b_no_default_controls() -> void:
	_log("")
	_log("--- [B] 所有 Button 四态均自定义（§5.1「禁止使用系统默认控件」）---")
	for pair in [["商店", _make_shop()], ["HUD", _make_hud()]]:
		var name := String(pair[0])
		var c: Control = pair[1]
		var btns: Array = _collect(c, [], "button")
		_check("【%s】至少存在按钮（样本有效）" % name, btns.size() > 0)
		var bad: Array = []
		for b in btns:
			for st in ["normal", "hover", "pressed", "disabled"]:
				if not (b as Button).has_theme_stylebox_override(st):
					bad.append("%s/%s" % [String((b as Button).text), st])
		_check("【%s】%d 个按钮 × 4 态全部自定义%s" % [
			name, btns.size(), "" if bad.is_empty() else " → 缺失: " + str(bad)],
			bad.is_empty())
		# 字号：按钮文字同属玩家可见文本
		var small: Array = []
		for b in btns:
			var fs := int((b as Button).get_theme_font_size("font_size"))
			if fs > 0 and fs < FONT_MIN:
				small.append("%s=%d" % [String((b as Button).text), fs])
		_check("【%s】按钮字号 ≥%dpx%s" % [name, FONT_MIN, "" if small.is_empty() else " → " + str(small)],
			small.is_empty())
		c.free()


# ---------------------------------------------------------------------------
#  C 字号下限（§9.1 P0；F3 调试面板 dev-only 豁免）
# ---------------------------------------------------------------------------
func _test_c_font_floor() -> void:
	_log("")
	_log("--- [C] 玩家可见文本 ≥16px（§9.1 P0 · F3 调试面板豁免）---")
	var hud := _make_hud()
	var dev: Node = hud._debug_panel
	var labels: Array = _collect(hud, [], "label")
	var checked := 0
	var small: Array = []
	for l in labels:
		var lb := l as Label
		if dev != null and dev.is_ancestor_of(lb):
			continue                                   # dev-only 豁免（默认隐藏）
		var fs := int(lb.get_theme_font_size("font_size"))
		if fs <= 0:
			continue
		checked += 1
		if fs < FONT_MIN:
			small.append("%s=%d" % [String(lb.text).substr(0, 10), fs])
	_check_int("【HUD】参与判定的玩家可见 Label 数 > 0", 1 if checked > 0 else 0, 1)
	_check("【HUD】%d 个 Label 全部 ≥16px%s" % [checked, "" if small.is_empty() else " → " + str(small)],
		small.is_empty())
	hud.free()

	var shop := _make_shop()
	var slabels: Array = _collect(shop, [], "label")
	var ssmall: Array = []
	for l in slabels:
		var fs := int((l as Label).get_theme_font_size("font_size"))
		if fs > 0 and fs < FONT_MIN:
			ssmall.append("%s=%d" % [String((l as Label).text).substr(0, 10), fs])
	_check("【商店】%d 个 Label 全部 ≥16px%s" % [slabels.size(), "" if ssmall.is_empty() else " → " + str(ssmall)],
		ssmall.is_empty())
	shop.free()


# ---------------------------------------------------------------------------
#  D X3：三位同构
# ---------------------------------------------------------------------------
func _test_d_x3_slot_size() -> void:
	_log("")
	_log("--- [D] X3：三个商品位尺寸完全一致 ---")
	var shop := _make_shop()
	_check_int("商品位数量恒为 3", shop._slots.size(), 3)
	var first := Vector2.ZERO
	var same := true
	for i in shop._slots.size():
		var sz: Vector2 = (shop._slots[i] as Control).custom_minimum_size
		if i == 0:
			first = sz
		elif not sz.is_equal_approx(first):
			same = false
	_check("三个位 custom_minimum_size 完全一致（%s）" % str(first), same)
	_check("商品位尺寸等于 SLOT_SIZE 常量", first.is_equal_approx(_Shop.SLOT_SIZE))
	_check("商品位高度足以容纳 卡名+价格+备注+双按钮（≥220）", first.y >= 220.0)
	shop.free()


# ---------------------------------------------------------------------------
#  E 玩家界面无开发占位
# ---------------------------------------------------------------------------
func _test_e_no_placeholder() -> void:
	_log("")
	_log("--- [E] 玩家界面不得残留开发占位文案 ---")
	var shop := _make_shop()
	var texts: Array = []
	for b in _collect(shop, [], "button"):
		texts.append(String((b as Button).text))
	for l in _collect(shop, [], "label"):
		texts.append(String((l as Label).text))
	var hits: Array = []
	for t in texts:
		for bad in ["后续切片", "🟡", "骨架", "[接口]", "TODO", "占位"]:
			if String(t).find(bad) >= 0:
				hits.append(t)
	_check("商店 UI 文案零占位痕迹%s" % ("" if hits.is_empty() else " → " + str(hits)), hits.is_empty())
	shop.free()


# ---------------------------------------------------------------------------
#  F 调色板与 art-bible 逐字一致
# ---------------------------------------------------------------------------
func _test_f_palette() -> void:
	_log("")
	_log("--- [F] 调色板 = art-bible §2.2 登记值 ---")
	_check("耀青 #3ED0E8", _close(_Style.C_ALLY, Color(0.243, 0.816, 0.910)))
	_check("熔橙 #FF6B3D", _close(_Style.C_ENEMY, Color(1.000, 0.420, 0.239)))
	_check("辉金 #FFC94A", _close(_Style.C_GOLD, Color(1.000, 0.788, 0.290)))
	_check("警报红 #FF2E4E", _close(_Style.C_ALERT, Color(1.000, 0.180, 0.306)))
	_check("钢灰 #9AA5B1", _close(_Style.C_STEEL, Color(0.604, 0.647, 0.694)))
	_check("夜幕紫 #141726", _close(_Style.C_BG, Color(0.078, 0.090, 0.149)))
	_check("正文 #C8CFDA", _close(_Style.C_TEXT, Color(0.784, 0.812, 0.855)))
	_check("辅助 #8B94A5", _close(_Style.C_TEXT_DIM, Color(0.545, 0.580, 0.647)))
	_check_int("最小字号常量 = 16（§9.1 P0）", _Style.FONT_MIN, 16)
	_check("悬停缩放 = 1.05（§5.1）", is_equal_approx(_Style.SCALE_HOVER, 1.05))
	_check("按下缩放 = 0.97（§5.1）", is_equal_approx(_Style.SCALE_PRESS, 0.97))
	_check("缓动时长 = 0.12s（§5.1）", is_equal_approx(_Style.MOTION_SEC, 0.12))


# ---------------------------------------------------------------------------
#  G 双焦点比例不变（回归）
# ---------------------------------------------------------------------------
func _test_g_drawer_layout() -> void:
	_log("")
	_log("--- [G] 抽屉宽度口径不变（UI 改版不得动双焦点比例）---")
	_check("1920 → 614.4（32%）", is_equal_approx(_ShopLayout.drawer_width(1920.0), 614.4))
	_check("1280 → 560（最小宽）", is_equal_approx(_ShopLayout.drawer_width(1280.0), 560.0))
	_check("3840 → 1228.8", is_equal_approx(_ShopLayout.drawer_width(3840.0), 1228.8))


# ---------------------------------------------------------------------------
#  H 弹窗与结算界面同属玩家可见面，样式口径必须一致
# ---------------------------------------------------------------------------
## 结果界面与两个二次确认弹窗原先同样**零 StyleBox**（7 个默认按钮）。
##   🔴 shop-reroll §11 / art-bible §5.1 明确「禁止 AcceptDialog 默认控件」。
func _test_h_dialogs() -> void:
	_log("")
	_log("--- [H] 结算 / 二次确认弹窗同样不得用系统默认控件 ---")

	var res: CanvasLayer = _Result.new()
	res.show_result(true, 20, 1000.0, 1000.0, 120.0)
	_check("【结算】面板有 panel StyleBox", res._panel.has_theme_stylebox_override("panel"))
	_check_all_buttons("结算", res)
	res.free()

	var sal: CanvasLayer = _Salvage.new()
	sal.show_confirm("拆除并回收？", "返还 18 分\n销毁 3 张卡\nκ 不回升")
	_check("【回收确认】面板有 panel StyleBox", sal._panel.has_theme_stylebox_override("panel"))
	_check_all_buttons("回收确认", sal)
	sal.free()

	var dis: CanvasLayer = _DisabledDialog.new()
	dis.show_towers([
		{"slot": 1, "invested": 60.0, "repair_cost": 18, "attach_layers": 2, "can_repair": true},
		{"slot": 3, "invested": 40.0, "repair_cost": 12, "attach_layers": 0, "can_repair": false},
	])
	_check("【受损塔处置】面板有 panel StyleBox", dis._panel.has_theme_stylebox_override("panel"))
	_check_all_buttons("受损塔处置", dis)
	var tiny: Array = []
	for l in _collect(dis, [], "label"):
		var fs := int((l as Label).get_theme_font_size("font_size"))
		if fs > 0 and fs < FONT_MIN:
			tiny.append("%s=%d" % [String((l as Label).text).substr(0, 8), fs])
	_check("【受损塔处置】Label 全部 ≥16px%s" % ("" if tiny.is_empty() else " → " + str(tiny)),
		tiny.is_empty())
	dis.free()


func _check_all_buttons(tag: String, root: Node) -> void:
	var btns: Array = _collect(root, [], "button")
	_check("【%s】至少存在按钮（样本有效）" % tag, btns.size() > 0)
	var bad: Array = []
	for b in btns:
		for st in ["normal", "hover", "pressed", "disabled"]:
			if not (b as Button).has_theme_stylebox_override(st):
				bad.append("%s/%s" % [String((b as Button).text), st])
	_check("【%s】%d 个按钮 × 4 态全部自定义%s" % [
		tag, btns.size(), "" if bad.is_empty() else " → 缺失: " + str(bad)], bad.is_empty())


# ---------------------------------------------------------------------------
#  I 卡面描述（「这张卡干什么」—— 改造前卡上只有卡名 + 卡种，玩家看不出差别）
# ---------------------------------------------------------------------------
## 🔴 三条口径，缺一条就会退回原缺陷：
##   ① **每张会被发出的卡**都必须有非空描述（`RerollD` 被 D-4 排除出玩家池，不在此列）；
##   ② 描述恒 `DESC_LINES` 行 —— 三个商品位的描述块等高，X3「不得用布局暗示」；
##   ③ 数值**现取自 SSOT** 而非手抄 —— 改 `TOWERS` 后卡面自动跟随，不可能写「dps 10」跑「11」。
func _test_i_card_text() -> void:
	_log("")
	_log("--- [I] 卡面描述：每张卡都说明「干什么」（恒 3 行 · 数值派生 · 无评价词）---")

	# 会被玩家看到的全部卡（RerollD 已被 D-4 永久排除出玩家池 → 不要求描述）
	var cards: Array = []
	for nm in _TD.TOWERS:
		cards.append(String(nm))
	for nm in _TD.TOWERS_EXT:
		cards.append(String(nm))
	for nm in _TD.REINF:
		cards.append(String(nm))
	for nm in _TD.REINF_EXT:
		cards.append(String(nm))
	cards.append("ScrapUp")
	_check_int("待验卡数 = 主表 3 + 扩展 2 + 强化 4 + 全局 1", cards.size(), 10)

	var empty: Array = []
	var bad_lines: Array = []
	var banned: Array = []
	for nm in cards:
		var d := _CardText.describe(nm)
		if d.strip_edges() == "":
			empty.append(nm)
			continue
		var n := d.split("\n").size()
		if n != _Shop.DESC_LINES:
			bad_lines.append("%s=%d行" % [nm, n])
		for w in ["推荐", "最优", "必买", "首选", "best", "recommend", "suggest"]:
			if d.findn(w) >= 0:
				banned.append("%s:%s" % [nm, w])
	_check("%d 张卡全部有非空描述%s" % [cards.size(), "" if empty.is_empty() else " → 空: " + str(empty)],
		empty.is_empty())
	_check("描述恒 %d 行（三位等高同构 · X3）%s" % [
		_Shop.DESC_LINES, "" if bad_lines.is_empty() else " → " + str(bad_lines)], bad_lines.is_empty())
	_check("描述零强弱评价词（C-3 / SR-R2）%s" % ("" if banned.is_empty() else " → " + str(banned)),
		banned.is_empty())

	# ---- 数值派生：卡面数字必须就是表里的数字（改表自动跟随，杜绝手抄漂移）----
	var drift: Array = []
	for nm in ["Arrow", "Cannon", "Frost", "Lance", "Tesla"]:
		var def: Dictionary = _TD.TOWERS[nm] if _TD.TOWERS.has(nm) else _TD.TOWERS_EXT[nm]
		var line := _CardText.stat_line(nm)
		var want_dps := "伤害 %s" % _CardText._num(float(def["dps"]))
		var want_rng := "射程 %s" % _CardText._num(float(def["rng"]))
		if line.find(want_dps) < 0 or line.find(want_rng) < 0:
			drift.append("%s→%s" % [nm, line])
	_check("5 张塔卡的伤害 / 射程逐字取自 TOWERS（TOWERS_EXT）%s" % (
		"" if drift.is_empty() else " → " + str(drift)), drift.is_empty())
	# 溅射 / 减速 / 标记分别落在第 1 / 3 行（第 2 行只放伤害·射程，否则超 9 汉字必然二次换行）
	_check("Cannon 描述写明「溅射」（aoe=true）",
		_CardText.describe("Cannon").find("溅射") >= 0)
	_check("Frost 描述写明「减速 30%」（slow=0.30）",
		_CardText.describe("Frost").find("减速 30%") >= 0)
	_check("Tesla 描述写明「减速」（slow=0.10）",
		_CardText.describe("Tesla").find("减速") >= 0)
	_check("Arrow 描述**不含**「溅射」（aoe=false）",
		_CardText.describe("Arrow").find("溅射") < 0)
	_check("塔卡第 2 行只含伤害 / 射程（不含溅射 / 减速 / 标记）",
		_CardText.stat_line("Cannon").find("溅射") < 0
		and _CardText.stat_line("Frost").find("减速") < 0
		and _CardText.stat_line("Cannon").find("标记") < 0)
	# 版式硬约束：每行 ≤9 汉字（实测 155px 内宽 / 16px 字号），否则描述块会二次换行
	var over: Array = []
	for nm in cards:
		for line in _CardText.describe(nm).split("\n"):
			if _display_width(String(line)) > 9.0:
				over.append("%s: 「%s」=%.1f 字" % [nm, String(line), _display_width(String(line))])
	_check("每行 ≤9 汉字（版式硬约束 · 超出即二次换行）%s" % (
		"" if over.is_empty() else " → " + str(over)), over.is_empty())

	# ---- 强化卡「可强化：xxx」也派生自 tag（新增同 tag 塔自动被包含）----
	for pair in [["FireUp", "Cannon"], ["FrostUp", "Frost"], ["PirUp", "Lance"], ["ShkUp", "Tesla"]]:
		var card := String(pair[0])
		var host := String(pair[1])
		var d2 := _CardText.describe(card)
		_check("%s 的「可强化」点名 %s" % [card, host], d2.find(host) >= 0)
	_check("FireUp 不会误点名 Frost（tag 不同）", _CardText.describe("FireUp").find("Frost") < 0)
	_check("全局卡 ScrapUp 写明 +20% 与 3 层上限",
		_CardText.describe("ScrapUp").find("+20%") >= 0
		and _CardText.describe("ScrapUp").find("上限3层") >= 0)

	# ---- 未知卡 / 空位：返回空串（卡片尺寸不变，不塞噪声占位）----
	_check("未知卡描述为空串（不发明内容）", _CardText.describe("NoSuchCard") == "")
	_check("空卡名描述为空串", _CardText.describe("") == "")

	# ---- UI 接线：3 个位都挂了描述 Label，且预留高度一致（等高同构）----
	var shop := _make_shop()
	_check_int("3 个商品位都有描述 Label", shop._slot_desc.size(), 3)
	var h0: float = (shop._slot_desc[0] as Label).custom_minimum_size.y
	var same_h := true
	for l in shop._slot_desc:
		if not is_equal_approx((l as Label).custom_minimum_size.y, h0):
			same_h = false
	_check("3 个描述块预留高度完全一致（%.0fpx）" % h0, same_h)
	_check("描述块预留高度 ≥ %d 行 × %.0fpx" % [_Shop.DESC_LINES, _Shop.DESC_LINE_H],
		h0 >= _Shop.DESC_LINE_H * float(_Shop.DESC_LINES))
	_check("描述块字号 ≥ %dpx（§9.1 P0）" % FONT_MIN,
		int((shop._slot_desc[0] as Label).get_theme_font_size("font_size")) >= FONT_MIN)
	shop.free()


# ---------------------------------------------------------------------------
#  断言助手
# ---------------------------------------------------------------------------
func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002


## 估算显示宽度（单位 = 一个 16px 汉字宽）：CJK / 全角 = 1.0，ASCII = 0.5。
##   用于卡面版式的「每行 ≤9 字」硬约束（商品位内宽实测 155px ÷ 16px ≈ 9.7）。
func _display_width(s: String) -> float:
	var w := 0.0
	for i in s.length():
		w += 0.5 if s.unicode_at(i) < 128 else 1.0
	return w


func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
		_log("   [PASS] %s" % name)
	else:
		_fail += 1
		_log("   [FAIL] %s" % name)


func _check_int(name: String, got: int, want: int) -> void:
	_check("%s（got=%d want=%d）" % [name, got, want], got == want)


func _log(s: String) -> void:
	print(s)
