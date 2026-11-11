extends Control
## Read-only bestiary. Combat values always come from the owning data tables.
signal back_requested

const _Style := preload("res://scripts/ui/ui_style.gd")
const _Monsters := preload("res://scripts/data/monster_data.gd")
const _Combat := preload("res://scripts/data/combat_types.gd")
const NAMES := {"Rush": "疾行者", "Swarm": "集群体", "Tank": "重装体"}
const ROLES := {"Rush": "快速突进 · 低生命", "Swarm": "集群推进 · 基准单位", "Tank": "重甲攻坚 · 高生命"}
const TIPS := {
	"Rush": "移动迅速，优先用物理火力配合减速拦截，避免突破防线。",
	"Swarm": "双抗为零，成群接近时可用范围攻击清理。",
	"Tank": "生命高、物理抗性强，适合用魔法或真实伤害持续集火。"
}
var _scroll: ScrollContainer
var entries: Array = []

func _ready() -> void:
	build()

func build() -> void:
	if _scroll != null:
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(_Style.C_BG, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var title := _Style.label("怪 物 图 鉴", 34, _Style.C_GOLD)
	title.position = Vector2(72, 34)
	add_child(title)
	var subtitle := _Style.label("三种基础原型 · 精英变体 · 了解来敌，规划防线", 18, _Style.C_TEXT)
	subtitle.position = Vector2(72, 90)
	add_child(subtitle)
	var back := Button.new()
	back.text = "返回主菜单"
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.offset_left = -260
	back.offset_right = -72
	back.offset_top = 42
	back.offset_bottom = 90
	_Style.button(back, "ghost")
	back.pressed.connect(func() -> void: back_requested.emit())
	add_child(back)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 72
	_scroll.offset_right = -72
	_scroll.offset_top = 148
	_scroll.offset_bottom = -40
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	_scroll.add_child(list)
	for proto in _Monsters.PROTOS:
		list.add_child(_entry(String(proto)))
	var elite := _Style.label("精英变体", 26, _Style.C_GOLD)
	list.add_child(elite)
	var note := _Style.label("精英沿用基础原型的速度和抗性，生命为当波基准的 %.1f 倍（不再乘原型生命倍率）。\n精英波通常每 %d 波出现；具体出怪以关卡预告为准。精英破坏者会直奔防御塔，请留意防线耐久。" % [_Monsters.ELITE_HP_MULT, _Monsters.ELITE_EVERY], 18, _Style.C_TEXT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)
	var foot := _Style.label("以上为基础属性，实际生命与速度受波次、关卡构成及精英配置影响。滚轮浏览 · Esc 返回", 16, _Style.C_STEEL)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(foot)

func _entry(proto: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _Style.panel(_Style.C_ENEMY, 0, 24, 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(190, 190)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://art/2d/monsters/machines_v1/%s.png" % proto.to_lower()
	if not ResourceLoader.exists(path):
		path = "res://art/2d/sprites/sp_mon_%s_v1.png" % proto.to_lower()
	if ResourceLoader.exists(path):
		art.texture = load(path)
	row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 10)
	row.add_child(text)
	text.add_child(_Style.label("%s  /  %s" % [NAMES[proto], proto], 26, _Style.C_ENEMY))
	text.add_child(_Style.label(ROLES[proto], 18, _Style.C_GOLD))
	var stats := _Style.label("生命 ×%.2f    移速 ×%.2f    建筑伤害 %.0f / 秒\n物理抗性 %.0f%%    魔法抗性 %.0f%%" % [
		_Monsters.M_HP[proto], _Monsters.M_SPD[proto],
		_Monsters.STRUCTURE_ATTACK_DPS * float(_Monsters.M_DPS[proto]),
		_Combat.monster_resist(proto, _Combat.PHYSICAL) * 100,
		_Combat.monster_resist(proto, _Combat.MAGIC) * 100], 18, _Style.C_TEXT)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(stats)
	var tip := _Style.label(TIPS[proto], 18, _Style.C_TEXT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(tip)
	entries.append({"proto": proto, "stats": stats, "art": art})
	return panel

func reset_scroll() -> void:
	if _scroll != null:
		_scroll.scroll_vertical = 0
