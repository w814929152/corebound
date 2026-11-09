extends RefCounted
## 十关的玩家可见目标与战术说明；结构、波数和解锁规则仍以 CampaignData 为准。
const CampaignData := preload("res://scripts/data/campaign_data.gd")

const BRIEFINGS := {
	"0-1": {"terrain": "三面来敌", "hint": "先购买并放置防御塔，准备好后开始。兼顾三个入口，保住核心。", "clear": "铁砧重新上线，外环三座中继站已建立连接。"},
	"1-1": {"terrain": "窄口聚火", "hint": "东南窄口适合集中火力；另两个宽口需要补防，避免只守一侧。", "clear": "熔炉没有熄灭，当地工程师交出了炉心科技。"},
	"2-1": {"terrain": "中环孤墙", "hint": "中环墙阻挡建造。沿墙两端布防，搭配减速延长敌人在射程内的时间。", "clear": "科考站恢复连接，制冷循环已接入战术网络。"},
	"3-1": {"terrain": "双墙走廊", "hint": "两道中环墙夹住狭窄入口；把远程塔布在墙端，兼顾走廊和邻侧来敌。", "clear": "磁轨再次通电，长程武器科技已送达。"},
	"4-1": {"terrain": "四面防线", "hint": "四个入口持续来敌。分配射程覆盖，保留能支援相邻方向的塔位。", "clear": "雷暴电网重新并网，电弧科技已接入。"},
	"5-1": {"terrain": "双口塔阵", "hint": "两侧宽口留出大片空地。围绕辅助建筑组织塔阵，同时守住相对的两个方向。", "clear": "联合体守住了生产线，破甲科技已送达。"},
	"6-1": {"terrain": "宽口消耗", "hint": "三个宽口让敌人分散。把持续伤害塔放在外侧，利用减速争取输出时间。", "clear": "培养舱保住了，生物研究所交出了咒术科技。"},
	"7-1": {"terrain": "五路围攻", "hint": "五个入口分散防线；核心附近还有禁建护壁，需把部分防线提前布在外圈。", "clear": "归零井恢复稳定，湮灭科技已解锁。"},
	"8-1": {"terrain": "旧都突破", "hint": "十九波连续考验，潮涌与重甲交替。用已解锁的地区科技补齐覆盖和伤害类型。", "clear": "旧都外围已突破。重连全部七个地区，即可进入主脑核心。"},
	"9-1": {"terrain": "主脑决战", "hint": "中环墙、核心护壁与极窄入口同时出现。覆盖四个方向，守住全部二十波。", "clear": "统序退向轨道，世界暂时保住了。下一批清扫单元，预计 47 天后抵达。"},
}

static func get_briefing(stage_id: String) -> Dictionary:
	return BRIEFINGS.get(stage_id, {}).duplicate(true)

static func unlock_hint(stage_id: String) -> String:
	var st: Dictionary = CampaignData.STAGES.get(stage_id, {})
	var parts: Array[String] = []
	var prereq: Array = st.get("prereq", [])
	if not prereq.is_empty():
		parts.append("先通关 " + " 或 ".join(prereq))
	var regions := int(st.get("need_regions", 0))
	if regions > 0:
		parts.append("守住 %d 个地区" % regions)
	var required := String(st.get("need_cleared", ""))
	if required != "":
		parts.append("通关 " + required)
	return " 且 ".join(parts) if not parts.is_empty() else "初始开放"
