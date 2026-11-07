extends RefCounted
##
## 卡面文案表 —— 「这张卡到底干什么」（纯文案层 / **只读**数值 SSOT）
## ---------------------------------------------------------------------------
## 🔴 为什么卡面需要这一层：
##    改造前商品位只有「卡名 + 卡种（建筑卡 / 单塔效果卡）」，
##    玩家看得出 Cannon 和 FireUp 名字不同，但**看不出它们干什么**。
##
## 🔴 为什么不把描述写进 `TowerData`：
##    `TOWERS` / `REINF` / `PRICE` / `CARD_NAMES` 是金标本逐位对齐的**数值** SSOT
##    （control-manifest §1），任何字段增删都要走 ADR + 重签基线。
##    本文件对它们**只读不写**，数值全部现场派生 ⇒ 改了数值描述自动跟着变，
##    不可能出现「卡面写 dps 10、引擎跑 11」这种漂移。
##
## 🔴 版式硬约束（实测，不是估算）：
##    商品位实际内宽只有 **155px**（抽屉 614.4 − 面板内边距 32 − 抽屉边距 36
##    − 卡片间距 20，再 ÷3 = 175 卡宽，减卡片内边距 20）。16px 汉字 ≈ 16px/字
##    ⇒ **一行只放得下约 9 个汉字**。
##    ⇒ 每行必须 ≤9 汉字（或 ≤14 半角），否则会二次换行 —— 描述块从 3 行涨到 7 行，
##      卡片被撑高、三张卡的文字块高低不齐，直接违反 X3 的「三位同构」。
##    加文案前先数一遍字数。
##
## 🔴 C-3 / SR-R2 合规：本文件**禁止**出现 推荐 / 最优 / best / recommend / suggest。
##    文案只说机制事实（打几个、多远、减多少速），**不做强弱评价、不给取舍建议**
##    —— GDD §10.1 断言 10 会 grep 商店链路源码，`tests/run_ui_style_asserts.gd` §I 也 grep 本文件。
##
## 🔴 art-bible §9.2 红线1：颜色不得为唯一信息通道 ⇒ 本层只负责**文字**，
##    可购性仍由 ✓/✗ 字形 + 颜色双通道表达（见 `shop_overlay.gd`）。
##
## ⚠️ G6：headless 无 `global_script_class_cache` → **不写 `class_name`**，
##    调用方一律 `const _CardText := preload("res://scripts/data/card_text.gd")`。
##

const _TD := preload("res://scripts/data/tower_data.gd")
const _ShopAI := preload("res://scripts/engine/shop_ai.gd")


# ---------------------------------------------------------------------------
#  文案表（手写；只讲机制，不讲强弱。🔴 每行 ≤9 汉字，见文件头版式约束）
# ---------------------------------------------------------------------------
## 金标本 tag 是英文内部标识，玩家不该看到 —— 这里给中文名
const TAG_CN := {
	"": "无",
	"fire": "火",
	"frost": "冰",
	"pierce": "穿甲",
	"shock": "电",
	"sunder": "破甲",
	"hex": "咒术",
	"true": "真",
}

## 第 1 行：这张卡**做什么**（机制，不含数值）
const ROLE := {
	# ---- 建筑卡（塔）：L1 机制 / L2 数值 / L3 标记 ----
	"Arrow": "单体，无附加",
	"Cannon": "溅射：一次打一片",
	"Frost": "命中减速 30%",
	"Lance": "远程单体",
	"Tesla": "近身溅射 + 减速",
	"Sunder": "削弱全场物抗",
	"Hex": "削弱全场魔抗",
	# ---- 🆕 流派第二塔（2026-11-07 · card-packs v0.2）----
	"Ember": "近身灼烧：一片",
	"Icicle": "单体强减速",
	"Javelin": "近身连射",
	"Bolt": "单体电弧直击",
	"Maul": "群体物理压制",
	"Rune": "群体魔法清场",
	# ---- 🆕 真实伤害流派（2026-11-07 · combat-types GDD v0.3）----
	"Oblivion": "真实单体：无视抗性",
	"Void": "真实群伤：无视抗性",
	# ---- 🆕 触发型建筑（2026-11-07）：登场 / 整备 / 阵亡 加等级 ----
	"Vanguard": "登场：自身 +1 级",
	"Drillmaster": "整备：全场 +1 级",
	"Martyr": "阵亡：全场 +1 级",
	# ---- 🆕 卡包扩充（2026-11-07 · 48 张卡）----
	"Scout": "击杀赏金",
	"Mortar": "超远程溅射",
	"Foundry": "经济：每波产废料",
	"Blaze": "近距持续灼烧",
	"Cinder": "单体点火",
	"Pyre": "群伤：升级增强",
	"Glacier": "强减速",
	"Hail": "范围减速",
	"Permafrost": "持续减速",
	"Frostbite": "减速 + 单体",
	"Storm": "范围电击",
	"Arc": "群伤：电弧",
	"Spark": "快速单体",
	"Thunder": "高伤单体",
	"Ballista": "超远程单体",
	"Sniper": "最远射程",
	"Harpoon": "近身穿刺",
	"Breaker": "削物抗：群伤",
	"Shatter": "削物抗：单体",
	"Ruin": "削物抗：重击",
	"Cleave": "横扫群伤",
	"Quake": "防御光环 +15%",
	"Curse": "削魔抗：单体",
	"Plague": "全场持续掉血",
	"Wither": "每秒回复塔生命",
	"Omen": "攻击光环 +10%",
	"Exile": "真实单体",
	"Null": "击杀升级",
	"Rift": "真实：升级增强",
	"Abyss": "真实群伤 + 减速",
	# ---- 单塔效果卡：L1 强化谁 / L2 点名 / L3 叠层规则 ----
	"FireUp": "强化「火」系塔",
	"FrostUp": "强化「冰」系塔",
	"PirUp": "强化「穿甲」系塔",
	"ShkUp": "强化「电」系塔",
	"SunUp": "强化「破甲」系塔",
	"HexUp": "强化「咒术」系塔",
	"TrueUp": "强化「真」系塔",
	# ---- 🆕 流派第二强化（与第一强化同 tag，可再叠一层）----
	"FireUp2": "强化「火」系塔",
	"FrostUp2": "强化「冰」系塔",
	"PirUp2": "强化「穿甲」系塔",
	"ShkUp2": "强化「电」系塔",
	"SunUp2": "强化「破甲」系塔",
	"HexUp2": "强化「咒术」系塔",
	"TrueUp2": "强化「真」系塔",
	# ---- 全局效果卡 ----
	"ScrapUp": "提高废料收入",
}

## 🔴 购买流程提示：**按卡种**统一，不写在卡上。
##   理由：同一卡种的三张卡流程完全一样，写进卡面等于三条重复文案白占三行高度；
##   放在三张卡下方一行说清三种卡种，反而更好读。
##   ⚠️ 每行 ≤30 汉字（抽屉内宽 546px ÷ 17px/字），写超了会出现「生效」这种孤字尾行。
const FLOW_HINT := "建筑卡：买后进待放置队列，安全窗点地图格子落子\n" \
	+ "单塔效果卡：投给点选的塔（未选投主塔），同卡再买叠层\n" \
	+ "全局卡：买入立即生效，占 1 个全局槽"

## 强化卡第 3 行（叠层规则，与 `ShopAI.apply_action` 的「同卡再买 = 层数 +1」一致）
const REINF_FLOW := "同卡再买叠层"
## 全局卡收益步长（= `shop_ai.gd` econ 分支 `income_mult += 0.20`）
const INCOME_STEP := 0.20
## 全局槽上限（= `shop_runtime.slot_usage()` 的 `glob_max`）
const GLOBAL_SLOT_MAX := 3


# ---------------------------------------------------------------------------
#  查表 / 格式化
# ---------------------------------------------------------------------------
## 卡 → 第 1 行定位；未知卡返回 ""（UI 侧据此整块留白，不塞「—」之类噪声）
static func role(nm: String) -> String:
	return String(ROLE.get(nm, ""))


## 数值格式化：整数不带小数点（10 而非 10.0），非整数保一位（7.5）
static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.0001:
		return "%.0f" % v
	return "%.1f" % v


## tag → 玩家可见字
static func tag_cn(tag: String) -> String:
	return String(TAG_CN.get(tag, tag))


## 用指定分隔符连接（Godot 的 `String.join` 只吃 PackedStringArray，
##   这里手动拼，避免 Array → PackedStringArray 的隐式转换坑）
static func _join_sep(arr: Array, sep: String) -> String:
	var s := ""
	for i in arr.size():
		if i > 0:
			s += sep
		s += String(arr[i])
	return s


static func _tower_def(nm: String) -> Dictionary:
	if _TD.TOWERS.has(nm):
		return _TD.TOWERS[nm]
	if _TD.TOWERS_EXT.has(nm):
		return _TD.TOWERS_EXT[nm]
	return {}


## 卡 → tag 内部标识（建筑卡 = 塔表 tag；强化卡 = `reinf_tag`；全局卡 / 未知卡 = ""）。
##   🆕 蓝图卡面（art-bible §5.5）「Tag 电路符号」的数据源 —— 只读 SSOT 派生，
##   与 `mark_line` / `describe` 同一口径，改表自动跟随。
static func tag_of(nm: String) -> String:
	var d := _tower_def(nm)
	if not d.is_empty():
		return String(d["tag"])
	if _TD.REINF.has(nm) or _TD.REINF_EXT.has(nm) or _TD.REINF_EXT2.has(nm):
		return String(_TD.reinf_tag(nm))
	return ""


## 某 tag 下**现存所有塔**（先主表、再扩展表 —— 与 `TowerData._tower_def()` 同序）。
##   🔴 派生而非手写：新增塔且复用既有 tag 时，「可强化」自动包含它，不会漏。
static func hosts_of_tag(tag: String) -> Array:
	var out: Array = []
	if tag == "":
		return out
	for nm in _TD.TOWERS:
		if String(_TD.TOWERS[nm]["tag"]) == tag:
			out.append(String(nm))
	for nm in _TD.TOWERS_EXT:
		if String(_TD.TOWERS_EXT[nm]["tag"]) == tag:
			out.append(String(nm))
	return out


## ---------------------------------------------------------------------------
##  稀有度派生（art-bible §2.3 五级色阶 · P1-6 · 2026-11-07 落地）
## ---------------------------------------------------------------------------
## 🔴 **只读派生，不写任何数值**：稀有度由商店抽取权重（SSOT = `shop_ai.WEIGHTS`
##    + `tower_data.EXT_WEIGHTS`）机械映射，改权重卡面自动跟随 —— 与 stat_line 同一管法。
##    映射口径（展示层约定 · 2026-11-07，调档只动本函数）：
##      w ≥ 0.13         → common   石灰（基础 5 卡：三主塔 + 双强化）
##      0.095 ≤ w < 0.13 → uncommon 苔绿（ScrapUp / RerollD 0.095 + 第二塔 0.10）
##      w < 0.095        → rare     湖蓝（Lance/Sunder/Hex/Oblivion/Void 0.09 + 扩展强化 0.075）
##      epic / legendary → 暂无对应卡（色阶与角标系统已就位，新卡按 w 自动落档）
##    金标本零改动：本函数只读 WEIGHTS / EXT_WEIGHTS，不参与抽取（`draw_offers` 不经此处）。
static func weight_of(nm: String) -> float:
	if _ShopAI.WEIGHTS.has(nm):
		return float(_ShopAI.WEIGHTS[nm])
	if _TD.EXT_WEIGHTS.has(nm):
		return float(_TD.EXT_WEIGHTS[nm])
	return -1.0


static func rarity(nm: String) -> String:
	var w := weight_of(nm)
	if w < 0.0:
		return "common"                # 未登记权重（异常/新卡未接）→ 按最常见处理
	if w >= 0.13:
		return "common"
	if w >= 0.095:
		return "uncommon"
	return "rare"


## ---------------------------------------------------------------------------
#  逐行派生
# ---------------------------------------------------------------------------
## 建筑卡第 2 行：`伤害 7 · 射程 18`
##   🔴 全部现取自 `TOWERS` / `TOWERS_EXT`，不在此层二次定义任何数字。
##   🔴 **不追加**溅射 / 减速 / 标记 —— 加上去这一行就超过 9 汉字必然二次换行。
##      溅射与减速已写在第 1 行（`ROLE`），标记写在第 3 行（`mark_line`）。
static func stat_line(nm: String) -> String:
	var d := _tower_def(nm)
	if d.is_empty():
		return ""
	return "伤害 %s · 射程 %s" % [_num(float(d["dps"])), _num(float(d["rng"]))]


## 建筑卡第 3 行：`标记：火`（tag 是强化卡「可强化」与 H2「◈协同」的判定依据，
##   玩家必须能看到，否则搞不懂 FireUp 为什么能强化 Cannon）
static func mark_line(nm: String) -> String:
	var d := _tower_def(nm)
	if d.is_empty():
		return ""
	return "标记：%s" % tag_cn(String(d["tag"]))


## 卡面完整描述（恒 3 行，`\n` 分隔）。
##   🔴 恒 3 行 ⇒ 三个商品位的描述块**等高同构**（X3：不得用布局差异暗示）。
##   未知卡 / 空卡名返回 ""（UI 侧整块留白，卡片尺寸不变）。
static func describe(nm: String) -> String:
	var r := role(nm)
	if r == "":
		return ""
	# 🆕 经济建筑：不攻击，每波按比例补贴废料（不能用「伤害 0 · 射程 0」那行）。
	if _TD.tower_income(nm) > 0.0:
		return "%s\n每波 +%d%% 废料\n占 1 个塔位" % [r, int(round(_TD.tower_income(nm) * 100.0))]
	# 🆕 赏金建筑：存活时全队累计击杀到阈值就发废料（第 3 行写清进度口径）。
	if _TD.tower_bounty_kills(nm) > 0:
		return "%s\n%s\n每 %d 杀 +%d 废料" % [
			r, stat_line(nm), _TD.tower_bounty_kills(nm), int(_TD.tower_bounty_scrap(nm))]
	# 🆕 溅射：命中后波及周围 N 个敌人（优先于弹射/贯穿显示 —— 它是最强的范围加成）。
	if _TD.tower_splash(nm) > 0:
		return "%s\n%s\n溅射 %d 个" % [r, stat_line(nm), _TD.tower_splash(nm)]
	# 🆕 弹射：第 3 行写跳弹次数（替代「标记」行，因为弹跳是更关键的取舍信息）。
	if _TD.tower_bounce(nm) > 0:
		return "%s\n%s\n弹射 %d 次" % [r, stat_line(nm), _TD.tower_bounce(nm)]
	# 🆕 贯穿：子弹可穿透的敌人数。
	if _TD.tower_pierce(nm) > 0:
		return "%s\n%s\n贯穿 %d 个" % [r, stat_line(nm), _TD.tower_pierce(nm)]
	if _TD.TOWERS.has(nm) or _TD.TOWERS_EXT.has(nm):
		return "%s\n%s\n%s" % [r, stat_line(nm), mark_line(nm)]
	if _TD.REINF.has(nm) or _TD.REINF_EXT.has(nm) or _TD.REINF_EXT2.has(nm):
		# 🔴 v0.2：同 tag 现有两座塔（核心塔 + 第二塔），列出具体塔名会让
		#   「可强化 Cannon、Ember」超 9 汉字（版式硬约束 → 二次换行）。
		#   改为按 tag 中文（第 1 行 ROLE 已写「强化「火」系塔」，tag 信息不丢），
		#   字数固定不随塔数量增长。
		var tg_cn := tag_cn(_TD.reinf_tag(nm))
		return "%s\n可强化 %s 系塔\n%s" % [r, tg_cn, REINF_FLOW]
	if nm == "ScrapUp":
		return "%s\n每层 +%.0f%% 废料\n占1槽，上限%d层" % [
			r, INCOME_STEP * 100.0, GLOBAL_SLOT_MAX]
	return r
