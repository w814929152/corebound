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
##    J 放置入口：⑤ 态落子必须有可达路径（不能是抽屉里的死按钮）
##    K 自由摆放：网格几何与落子判定共用一份定义；核心禁建、塔数上限、同格升级、
##      槽位表增长 —— 全部按玩家点选的**坐标**判定，而不是 6 个固定槽位号
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
const _BuildGrid := preload("res://scripts/geo/build_grid.gd")
const _Runtime := preload("res://scripts/gameplay/shop_runtime.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _StageSelect := preload("res://scripts/ui/stage_select_overlay.gd")
const _MainMenu := preload("res://scripts/ui/main_menu_overlay.gd")
const _Packs := preload("res://scripts/data/card_packs.gd")

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
	_test_j_placement_entry()
	_test_k_free_placement()
	_test_l_main_menu()

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

	# 🆕 大地图选关（裂隙航图）：全部文字走 `_Style.label` ⇒ 同样受 16px 下限约束。
	#   画布上的节点名 / 章名是 `draw_string`（非 Label），字号由绘制常量钉死见下条。
	var stage = _StageSelect.new()
	stage._build()
	var glabels: Array = _collect(stage, [], "label")
	var gsmall: Array = []
	for l in glabels:
		var fs := int((l as Label).get_theme_font_size("font_size"))
		if fs > 0 and fs < FONT_MIN:
			gsmall.append("%s=%d" % [String((l as Label).text).substr(0, 10), fs])
	_check("【航图】%d 个 Label 全部 ≥16px%s" % [glabels.size(), "" if gsmall.is_empty() else " → " + str(gsmall)],
		gsmall.is_empty())
	_check("【航图】零系统默认控件（画布自绘，不含 Button）",
		_collect(stage, [], "button").is_empty())
	_check("【航图】画布节点文字 ≥16px",
		float(_StageSelect.NODE_LABEL_FONT) >= float(FONT_MIN)
		and float(_StageSelect.CHAPTER_FONT) >= float(FONT_MIN))
	stage.free()


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
	for nm in _TD.REINF_EXT2:
		cards.append(String(nm))
	cards.append("ScrapUp")
	# 🔴 卡数随数据表增长（并行会话可能继续加卡），不硬编码，只校验「每张都有描述」
	_check("待验卡全部就位（≥ 20，实际 %d）" % cards.size(), cards.size() >= 20)

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

	# ---- 强化卡「可强化 X 系塔」派生自 tag（v0.2：同 tag 双塔，改为按 tag 中文而非点名）----
	for pair in [["FireUp", "火"], ["FrostUp", "冰"], ["PirUp", "穿甲"], ["ShkUp", "电"]]:
		var card := String(pair[0])
		var tag_cn := String(pair[1])
		var d2 := _CardText.describe(card)
		_check("%s 的「可强化」标注 %s 系塔" % [card, tag_cn],
			d2.find("可强化 %s 系塔" % tag_cn) >= 0)
	_check("FireUp 不会误标冰系（tag 不同）", _CardText.describe("FireUp").find("冰 系塔") < 0)
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
#  [J] 放置模式入口可达性（「买了建筑卡却放不下塔」的回归钉）
#  ---------------------------------------------------------------------------
## 🔴 背景（本轮修的 P0 主循环断链）：
##   ⑤ 态按 GDD §2.1 **抽屉收起、战场全屏** → `_refresh_mode()` 的
##   `visible = drawer != CLOSED` 会把整棵控件树隐藏，抽屉里那 6 个塔位按钮
##   **永远不可达**；战场侧又要求「抽屉展开」且只命中**已建塔** ⇒ 两条路同时断。
##   ⇒ 本段把「落子必须有真实入口」钉成断言，防止再改回抽屉按钮。
##
## 口径：源码级 grep（headless 可判）+ 信号存在性。端到端点击见
##   `tests/probe_placement.gd`（需窗口，非 CI）。
func _test_j_placement_entry() -> void:
	_log("")
	_log("--- [J] 放置入口：⑤ 态落子必须有可达路径（不能是抽屉里的死按钮）---")

	var td_src := FileAccess.get_file_as_string("res://scripts/ui/time_director.gd")
	var ctl_src := FileAccess.get_file_as_string("res://scripts/gameplay/shop_controller.gd")
	var ml_src := FileAccess.get_file_as_string("res://scripts/ui/monster_layer.gd")
	var shop_src := FileAccess.get_file_as_string("res://scripts/ui/shop_overlay.gd")
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")

	_check("TimeDirector 声明 slot_place_requested 信号",
		td_src.find("signal slot_place_requested") >= 0)
	_check("ShopController 连接并处理 slot_place_requested",
		ctl_src.find("_on_slot_place_requested") >= 0
		and ctl_src.find("slot_place_requested.connect") >= 0)
	_check("ShopController 非 ⑤ 态丢弃落子请求（T-C1 / E16 兜底）",
		ctl_src.find("State.PLACEMENT_MODE") >= 0 and ctl_src.find("placement_mode_for") >= 0)

	_check("MonsterLayer 由**状态机**判定放置态（不是抽屉）",
		ml_src.find("func _in_placement()") >= 0
		and ml_src.find("State.PLACEMENT_MODE") >= 0)
	_check("MonsterLayer ⑤ 态发 place_at_requested（**坐标驱动**，不是槽位号）",
		ml_src.find("place_at_requested") >= 0
		and ml_src.find("emit_signal(\"place_at_requested\"") >= 0)
	_check("MonsterLayer 点击先吸附格点（渲染层与 runtime 共用 BuildGrid.snap）",
		ml_src.find("_BuildGrid.snap") >= 0)
	_check("MonsterLayer ⑤ 态绘制网格（grid_edges，不是只画 6 个点）",
		ml_src.find("grid_edges()") >= 0)
	_check("网格一次 draw_multiline 画完（逐段 draw_line × 3660 段不可接受）",
		ml_src.find("draw_multiline(") >= 0)
	_check("悬停格按**六边形**高亮（corners + draw_colored_polygon，不是屏幕对齐方框）",
		ml_src.find("_BuildGrid.corners(") >= 0
		and ml_src.find("draw_colored_polygon(") >= 0)
	_check("MonsterLayer 不再引用已删除的方格常量 CELL",
		ml_src.find("_BuildGrid.CELL") < 0)
	_check("MonsterLayer 只对鼠标所指格查落子模式（不遍历全盘 960 格）",
		ml_src.find("placement_mode_at") >= 0)
	_check("MonsterLayer 点选发到 time_director（信号声明方）",
		ml_src.find("time_director.emit_signal(\"tower_select_requested\"") >= 0)
	_check("MonsterLayer 命中判定走**屏幕距离**（旧实现先转世界坐标 + sc*1.6 当半径 → 300+px 串味）",
		ml_src.find("func _hit_slot_screen") >= 0
		and ml_src.find("distance_to(_to_screen(") >= 0
		and ml_src.find("_hit_tower_slot") < 0)
	_check("MonsterLayer 保持零文本（AC-T1-24：无 draw_string 调用）",
		ml_src.find("draw_string(") < 0)

	_check("ShopOverlay 已移除不可达的 _place_box（死代码清除）",
		shop_src.find("_place_box") < 0 and shop_src.find("_refresh_placement") < 0)
	_check("HUD ⑤ 态有放置专属提示（不再误导「Tab 商店 / R 刷新」）",
		hud_src.find("HINT_DEFAULT") >= 0 and hud_src.find("点地图上的格子落子") >= 0)

	# 「进入 ⑤」与「在 ⑤ 里落子」是两个入口，一个都不能少：
	#   进 ⑤ = 抽屉里的待放置队列（抽屉展开时可见）；落子 = 战场（抽屉已收起）。
	_check("待放置队列入口仍在（进 ⑤ 靠它，落子靠战场）",
		shop_src.find("_pending_box") >= 0 and shop_src.find("request_placement") >= 0)


# ---------------------------------------------------------------------------
#  [K] 自由摆放：六边形网格几何 + 坐标驱动落子
# ---------------------------------------------------------------------------
## 🔴 这一节钉的是「自由摆放」的五条不变量：
##   ① 吸附正确（轴向取整 / 幂等 / 不超过外接圆半径）—— 否则同一视觉位置会落出两个槽
##   ①b 格子是**正**六边形：6 邻格等距、顶点构成正六边形 —— 否则"改方格"只是换了个贴图
##   ② 可建区正确（核心禁建 / 外径封顶）—— 否则玩家能贴脸堆塔，策略坍缩成唯一解
##   ③ 网格与判定共用同一份几何（`BuildGrid`）—— 否则"看到能建、点下去不能建"
##   ④ 落子按**坐标**判定：同格升级、异原型拒绝、塔数封顶、槽位表增长
func _test_k_free_placement() -> void:
	_log("")
	_log("--- [K] 自由摆放：六边形网格几何 + 坐标落子（核心禁建 / 塔数上限 / 同格升级）---")

	var core: Vector2 = _BuildGrid.core()

	# ---- ① 吸附（六边形 = 轴向取整，不是"除以格距再四舍五入"）----
	var p := Vector2(31.3, 20.8)
	var k: Vector2i = _BuildGrid.cell_of(p)
	var s: Vector2 = _BuildGrid.snap(p)
	_check("snap 输出 = cell(cell_of(p))（吸附规则只有一份）",
		s == _BuildGrid.cell(k.x, k.y))
	_check("cell_of 往返一致（格心再取整仍是同一格）", _BuildGrid.cell_of(s) == k)
	_check("snap 幂等（对已吸附点再吸附不漂移）", _BuildGrid.snap(s) == s)
	# 六边形内任一点到最近格心的距离上界 = 外接圆半径 R（最远点就是顶点）。
	# 🔴 方格时代这条是"半格对角线 0.707a"；直接照搬会在六边形上误判。
	_check("snap 就近（偏移 ≤ 外接圆半径 R = %.2f，实测 %.3f）" % [
		_BuildGrid.HEX_R, s.distance_to(p)],
		s.distance_to(p) <= _BuildGrid.HEX_R + 0.001)

	# ---- ①b 六边形本身（改方格 → 六边形必须钉死的两条）----
	var eq := true
	var dmin := 1.0e9
	var dmax := 0.0
	for nb in _BuildGrid.neighbors():
		var d: float = _BuildGrid.cell(nb.x, nb.y).distance_to(core)
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
		if not is_equal_approx(d, _BuildGrid.ROW_STEP):
			eq = false
	_check("6 个邻格与中心距离全等 = √3R（方格 1.414a 的\"斜向便宜格\"已消失；实测 %.3f ~ %.3f）"
		% [dmin, dmax], eq and is_equal_approx(dmin, dmax))
	var vc: PackedVector2Array = _BuildGrid.corners(core)
	var regular := vc.size() == 6
	for i in range(6):
		if not is_equal_approx(vc[i].distance_to(core), _BuildGrid.HEX_R):
			regular = false
		if not is_equal_approx(vc[i].distance_to(vc[(i + 1) % 6]), _BuildGrid.HEX_R):
			regular = false
	_check("corners() 返回**正**六边形（6 顶点等距 R、相邻顶点距亦为 R）", regular)
	_check("同格判定按格划分，不按距离容差（邻格不算同格）",
		_BuildGrid.same_cell(p, s) and not _BuildGrid.same_cell(s, _BuildGrid.cell(k.x + 1, k.y)))

	# ---- ② 可建区 ----
	_check("核心所在格不可建（CORE_BAN_R 内）", not _BuildGrid.buildable(core))
	_check("核心禁建圈外、可建外径内 可建",
		_BuildGrid.buildable(core + Vector2(_BuildGrid.CORE_BAN_R + _BuildGrid.ROW_STEP, 0.0)))
	_check("可建外径外 不可建",
		not _BuildGrid.buildable(core + Vector2(_BuildGrid.FIELD_R + _BuildGrid.ROW_STEP, 0.0)))
	_check("战场外（远离核心）不可建",
		not _BuildGrid.buildable(Vector2(-500.0, -500.0)))

	# ---- ③ 枚举与网格线 ----
	var cells: Array = _BuildGrid.all_cells()
	var all_ok := true
	for c in cells:
		if not _BuildGrid.buildable(c):
			all_ok = false
			break
	_check("all_cells() 每一格都通过 buildable()", all_ok)
	# 圆环面积 π(44² − 4²) ≈ 6032 u² ÷ 6.24 u²/格（= 改前方格 2.5²，容量刻意不变）≈ 966
	_check("all_cells() 数量在合理量级（500 ~ 1300，实测 %d）" % cells.size(),
		cells.size() > 500 and cells.size() < 1300)

	var edges: PackedVector2Array = _BuildGrid.grid_edges()
	_check("网格线段成对给出且非空（%d 段，供 draw_multiline 一次画完）" % (edges.size() / 2),
		edges.size() >= 120 and edges.size() % 2 == 0)
	var clipped := true
	var max_len := 0.0
	var i := 0
	while i < edges.size():
		var a: Vector2 = edges[i]
		var b: Vector2 = edges[i + 1]
		if a.distance_to(core) > _BuildGrid.FIELD_R + 0.01 \
			or b.distance_to(core) > _BuildGrid.FIELD_R + 0.01:
			clipped = false
		max_len = maxf(max_len, a.distance_to(b))
		i += 2
	_check("网格线段全部裁剪在可建圆内（不会画到出生环外）", clipped)
	_check("网格线段长度 ≤ 六边形边长 R = %.2f（实测最长 %.3f）" % [_BuildGrid.HEX_R, max_len],
		max_len <= _BuildGrid.HEX_R + 0.01)

	# ---- ④ 配置：塔数上限与槽位数语义分离 ----
	var cfg: Dictionary = _Cfg.cfg_of("B")
	_check("cfg 同时有 n_slots 与 tower_cap（%d / %d）且 tower_cap 更大" % [
		int(cfg["n_slots"]), int(cfg.get("tower_cap", -1))],
		int(cfg.get("tower_cap", -1)) > int(cfg["n_slots"]))

	# ---- ⑤ 坐标落子：新建 / 升级 / 拒绝 ----
	var rt = _Runtime.new()
	rt.setup("B", 1234, {"tower_cap": 3})
	_check("玩家路线几何从空槽起步，只含起手塔那一个槽（got=%d）" % rt.geo.slots.size(),
		rt.geo.slots.size() == 1)
	_check("起手塔所在格可建（坐标落在格点上，与网格对齐）",
		_BuildGrid.buildable(rt.geo.slots[0]))

	# 🆕 点位用**轴向坐标**显式取格心，不再写 `core + Vector2(10.0, 0.0)` 这类"随手偏一点"：
	#    六边形吸附会把任意偏移拉到最近的格心，靠手写的偏移量去赌"落在不同格"是不可靠的。
	var p_new: Vector2 = _BuildGrid.cell(4, -2)          # 正右方 9.30u：y 恒等于 core.y
	_check("测试点位 1 在可建区（dist=%.2f）" % p_new.distance_to(core),
		_BuildGrid.buildable(p_new))
	rt.pending = ["Cannon"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	var ok_new: bool = rt.confirm_placement_at(p_new)
	_check("核心外格点落子成功（%s）" % rt.last_error, ok_new)
	_check("落子后槽位表 1 → %d（新格即新槽）" % rt.geo.slots.size(), rt.geo.slots.size() == 2)
	_check("落子后场上 2 座塔", rt.player.towers.size() == 2)

	# 同格同原型 → 升级（不新增槽、不新增塔）
	rt.pending = ["Cannon"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	var ok_up: bool = rt.confirm_placement_at(p_new + Vector2(0.7, -0.6))   # 故意偏移 → 吸附同格
	_check("同格再次落同原型卡 = 升级（%s）" % rt.last_error, ok_up)
	_check("升级不新增槽（仍 %d）" % rt.geo.slots.size(), rt.geo.slots.size() == 2)
	_check("升级不新增塔（仍 %d 座）" % rt.player.towers.size(), rt.player.towers.size() == 2)

	# 同格异原型 → 拒绝
	rt.pending = ["Frost"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	var ok_bad: bool = rt.confirm_placement_at(p_new)
	_check("同格异原型被拒绝且不消耗卡", not ok_bad and rt.pending.size() == 1)
	rt.pending = []
	rt.pending_cost = []
	rt.cancel_placement()

	# 核心禁建区 → 拒绝
	rt.pending = ["Frost"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	_check("在核心禁建区落子被拒绝", not rt.confirm_placement_at(core))
	rt.pending = []
	rt.cancel_placement()

	# 塔数上限：tower_cap=3，已有 2 座 → 第 3 座可建，第 4 座被拒
	rt.pending = ["Frost"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	var ok_third: bool = rt.confirm_placement_at(_BuildGrid.cell(-4, 2))      # 正左方 9.30u
	_check("第 3 座塔可建（未超上限 3）", ok_third)
	rt.pending = ["Frost"]
	rt.pending_cost = [12.0]
	rt.begin_placement(0)
	var ok_fourth: bool = rt.confirm_placement_at(_BuildGrid.cell(0, 5))      # 正下方 13.42u
	_check("第 4 座塔被塔数上限拒绝（tower_cap=3）", not ok_fourth)
	_check("被拒后槽位表不变（仍 %d）" % rt.geo.slots.size(), rt.geo.slots.size() == 3)

	# 快照与槽位表一致（渲染层按 slot 索引取 geo.slots）
	var snap: Dictionary = rt.snapshot()
	_check("snapshot 槽位数 = geo.slots 数（%d）" % int(snap["slots"].size()),
		int(snap["slots"].size()) == rt.geo.slots.size())
	_check("snapshot 的 towers_max 取 tower_cap（%d）" % int(snap["towers_max"]),
		int(snap["towers_max"]) == 3)

# ---------------------------------------------------------------------------
#  L 主界面 + 卡组图鉴（2026-11-07）
# ---------------------------------------------------------------------------
## 🔴 三条口径（缺一条主界面就会退化成"装饰页"）：
##   ① 三个入口都存在，且按钮四态走 `ui_style`（§5.1 禁止系统默认控件）；
##   ② 图鉴必须**一遍看到全部**：8 包 × 6 张 = 48 个卡位、覆盖 `all_cards()` 的每一张，
##      未解锁包压暗但仍可见（解锁是节奏阀，不是内容保密）；
##   ③ 每张卡的说明非空 —— 图鉴若只有卡名，等于把商店卡面的「这张卡干什么」又丢一次。
func _test_l_main_menu() -> void:
	_log("")
	_log("--- [L] 主界面 / 卡组图鉴：入口可达 · 全部卡包可浏览 · 样式同口径 ---")

	var menu: CanvasLayer = _MainMenu.new()
	menu._build()

	_check("【主界面】默认页 = 菜单", menu.current_page() == _MainMenu.PAGE_MENU)
	_check_int("【主界面】三个入口（开始 / 图鉴 / 退出）", menu._menu_buttons.size(), 3)
	var texts: Array = []
	for b in menu._menu_buttons:
		texts.append(String((b as Button).text))
	_check("【主界面】入口文案 = 开始游戏 / 卡组图鉴 / 退出游戏",
		texts == ["开始游戏", "卡组图鉴", "退出游戏"])
	_check_all_buttons("主界面", menu)

	# 字号（两个页面的 Label 一起查）
	var small: Array = []
	var labels: Array = _collect(menu, [], "label")
	for l in labels:
		var fs := int((l as Label).get_theme_font_size("font_size"))
		if fs > 0 and fs < FONT_MIN:
			small.append("%s=%d" % [String((l as Label).text).substr(0, 8), fs])
	_check("【主界面】%d 个 Label 全部 ≥16px%s" % [labels.size(), "" if small.is_empty() else " → " + str(small)],
		small.is_empty())

	# 走「卡组图鉴」按钮路径（不是绕过 UI 直接调 show_library）
	menu._activate(1)
	_check("【图鉴】点击入口后切到图鉴页", menu.current_page() == _MainMenu.PAGE_LIBRARY)
	_check_int("【图鉴】卡包块数 = PACKS 数", menu._pack_blocks.size(), _Packs.PACKS.size())

	var want_slots := _Packs.PACKS.size() * _Packs.CARDS_PER_PACK
	_check_int("【图鉴】卡位数 = 8 包 × 每包 6 张", menu._card_entries.size(), want_slots)

	# 每个卡包块 = 6 张卡（结构对齐，不靠总数碰巧相等）
	var bad_block: Array = []
	for blk in menu._pack_blocks:
		var n := ((blk as Dictionary)["cards"] as Array).size()
		if n != _Packs.CARDS_PER_PACK:
			bad_block.append("%s=%d" % [String((blk as Dictionary)["id"]), n])
	_check("【图鉴】每包块恰好 %d 张卡%s" % [_Packs.CARDS_PER_PACK,
		"" if bad_block.is_empty() else " → " + str(bad_block)], bad_block.is_empty())

	# 覆盖全部玩家卡 + 每张卡有说明
	var shown := {}
	var empty_desc: Array = []
	for e in menu._card_entries:
		var nm := String((e as Dictionary)["card"])
		shown[nm] = true
		if String((e as Dictionary)["label"].text).strip_edges() == "":
			empty_desc.append(nm)
	var missing: Array = []
	for nm in _Packs.all_cards():
		if not shown.has(String(nm)):
			missing.append(String(nm))
	_check("【图鉴】覆盖全部 %d 张玩家卡%s" % [_Packs.all_cards().size(),
		"" if missing.is_empty() else " → 缺 " + str(missing)], missing.is_empty())
	_check("【图鉴】每张卡都有非空说明%s" % ("" if empty_desc.is_empty() else " → 空: " + str(empty_desc)),
		empty_desc.is_empty())

	menu.back_to_menu()
	_check("【图鉴】返回后回到菜单页", menu.current_page() == _MainMenu.PAGE_MENU)

	# 入口信号链路：开始游戏只发 `start_requested`（真正的流程由 boot.gd 决定）
	var got_start := [false]
	menu.start_requested.connect(func() -> void: got_start[0] = true)
	menu._activate(0)
	_check("【主界面】开始游戏发出 start_requested（不自己开流程）", got_start[0])

	# 玩家界面不得残留开发占位
	var all_text: Array = []
	for b in _collect(menu, [], "button"):
		all_text.append(String((b as Button).text))
	for l in _collect(menu, [], "label"):
		all_text.append(String((l as Label).text))
	var hits: Array = []
	for t in all_text:
		for bad in ["后续切片", "🟡", "TODO", "占位", "[接口]"]:
			if String(t).find(bad) >= 0:
				hits.append(t)
	_check("【主界面】文案零开发占位%s" % ("" if hits.is_empty() else " → " + str(hits)), hits.is_empty())

	menu.free()


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
