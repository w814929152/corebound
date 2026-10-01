class_name Softcap
extends RefCounted
##
## 叠层复利 + 软 cap 分段衰减
##   移植自 design/phase2/numeric-sim/corebound_sim_v03.py:273-277
##
##       def softcap_pow(lv, kappa, cap, decay):
##           if lv <= cap:  return kappa ** lv
##           return (kappa ** cap) * (decay ** (lv - cap))
##
## 🔴 定稿：MVP `cap=100`、`decay=1.03`（衰减不归零）。
##    陷阱 3（damage-pipeline §10.1 验收 3）：
##      softcap_pow(101, 1.10, 100, 1.03) == 1.10^100 × 1.03   （不是 1.10^100）
##
## ⚠️ Godot 坑：`pow()` 的实参必须是 float。`lv - cap` 若两边都是 int 会走整数运算，
##    这里入参统一声明为 float，调用方也须显式 cast。
##
## 🔴 末位对齐（切片2 联调发现，见 fp_pow.gd 文件头）
##    Godot 的 `pow()` 在**整数指数**上与 Python 的 `**` 差 1 ULP（采样 1731/2025 不一致），
##    而这里的 lv / cap / lv−cap **恒为整数** → 必须走 `FpPow.pow_int()`（正确舍入），
##    否则软 cap 复利的末位噪声会在贪心 AI 的并列动作上翻转选择，
##    把 MC B 起飞率从 91.3% 拖到 89.3%。
##

const _FpPow := preload("res://scripts/engine/fp_pow.gd")

static func pow_sc(lv: float, kappa: float, cap: float, decay: float) -> float:
	if lv <= cap:
		return _FpPow.pow_int(kappa, int(lv))
	return _FpPow.pow_int(kappa, int(cap)) * _FpPow.pow_int(decay, int(lv - cap))
