class_name FpPow
extends RefCounted
##
## 🔴 与 Python `x ** y` **逐位对齐** 的幂运算
##
## 为什么需要它
## ----------------
## 切片2 联调时发现：MC 300 局的 B 起飞率是 **89.3%** 而金标本是 **91.3%**。
## 逐层二分定位到 B 局第 18 局 W4 商店的第 4 个动作：
##   · 候选 `up Arrow@3 / @4 / @5` 在 Python 里 ΔDPS **精确并列**（9.406670173149649），
##     贪心 `max` 取第一个 → @3；
##   · GDScript 里 `up Arrow@5` 大了 **2.9e-14**（9.406670173149678）→ 取了 @5；
##   · 一个塔位的差别被后续 16 波复利放大 → 该局起飞波 13 → 15。
##
## 再往下挖，1 ULP 的来源是 **`pow()`**：
##   Python `1.06 ** 6` = 1.4185191122560004
##   Godot  `pow(1.06, 6.0)` = 1.4185191122560006        ← 差 1 ULP（2.2e-16）
## 而 `1.06^6` 的真值**恰好** = 1418519112256 / 10^12 = 1.418519112256（有限小数）。
##
## 采样统计（tools/ 下临时脚本，已删）：
##   · 整数指数、底数 1.000~1.120、指数 0~80：Godot 与 Python **1731/2025 不一致（85%）**；
##   · 同一批点：Python 与「用 Fraction 精确计算后舍入」的结果 **0/2025 不一致** →
##     **Python 侧恒为正确舍入**（CPython 走 MSVC libm，这些点全部正确舍入）；
##   · 非整数指数（如 `h ** 0.6`，h=1..200）：Godot 与 Python **200/200 一致**。
##
## 结论：只要把**整数指数**的幂改成「正确舍入」实现，就能与 Python 逐位对齐；
##       非整数指数继续用 `pow()`。
##
## 实现
## ----------------
## double-double（Dekker two_prod + two_sum）做二进制快速幂，中间精度 ~106 bit，
## 最后一次加法完成**单次舍入** → 结果即真值的正确舍入（除真值恰落在半值点 ±2^-107 内，
## 概率 ~2^-51，本域内不会发生）。
##
## ⚠️ Godot 坑
##   G1 `static var` 在 `--script` headless 下可用，但脚本是**跨场景共享**的；
##      这里只缓存纯函数结果，无副作用。
##   G2 热路径里**不分配 Array**：dd_mul 全部内联成局部变量，否则 MC 300 局会慢到分钟级。
##   G3 Dekker 分裂常数 = 2^27 + 1 = 134217729.0，要求 |x| < 2^996（本域远小于此）。
##
## 🔴 用法约定
##   · 指数**一定**是整数（软 cap 的 lv/cap/lv-cap、共振的 E、血量的 w-1）→ `pow_int()`；
##   · 指数可能是小数（塔层 `h ** 0.6`）→ `pow_py()`，它只在指数确为整数时才改道。
##

## Dekker 分裂常数 2^27 + 1
const SPLIT := 134217729.0

## 缓存：{ 底数(float) : { 指数(int) : 结果(float) } }
## 底数在本工程里只有十来个取值（κ 档位 / 1+κ_r 档位 / decay / hp_growth / 10 / 2），
## 命中率极高 → 把 dd 快速幂从热路径上彻底摘掉。
static var _cache: Dictionary = {}


# ---------------------------------------------------------------------------
# 正确舍入的整数幂（Python `x ** n`，n 为整数）
# ---------------------------------------------------------------------------
static func pow_int(x: float, n: int) -> float:
	if n == 0:
		return 1.0
	if x == 0.0:
		return 0.0
	var inner = _cache.get(x)
	if inner == null:
		inner = {}
		_cache[x] = inner
	var hit = inner.get(n)
	if hit != null:
		return float(hit)
	var v := _pow_int_raw(x, n)
	inner[n] = v
	return v


# ---------------------------------------------------------------------------
# Python `x ** y` 的等价物：y 是整数时走 pow_int，否则退回 pow()
# ---------------------------------------------------------------------------
static func pow_py(x: float, y: float) -> float:
	if y == floor(y) and absf(y) <= 1024.0:
		return pow_int(x, int(y))
	return pow(x, y)


# ---------------------------------------------------------------------------
# double-double 二进制快速幂（无分配）
# ---------------------------------------------------------------------------
static func _pow_int_raw(x: float, n: int) -> float:
	if n < 0:
		# 真值可精确表示时（如 2^-52）取倒数仍是正确舍入；本工程只用到 2^-52
		return 1.0 / _pow_int_raw(x, -n)

	# (rh, rl) = 结果； (bh, bl) = 底数的当前平方次
	var rh := 1.0
	var rl := 0.0
	var bh := x
	var bl := 0.0
	var e := n

	while e > 0:
		if e & 1:
			# ---- (rh, rl) *= (bh, bl) ----
			var p := rh * bh
			var ca := SPLIT * rh
			var ah := ca - (ca - rh)
			var al := rh - ah
			var cbb := SPLIT * bh
			var bh_h := cbb - (cbb - bh)
			var bh_l := bh - bh_h
			var err := ((ah * bh_h - p) + ah * bh_l + al * bh_h) + al * bh_l
			var t := err + (rh * bl + rl * bh)
			var s := p + t
			rl = t - (s - p)
			rh = s
		e = e >> 1
		if e > 0:
			# ---- (bh, bl) = (bh, bl)² ----
			var p2 := bh * bh
			var c2 := SPLIT * bh
			var a2h := c2 - (c2 - bh)
			var a2l := bh - a2h
			var err2 := ((a2h * a2h - p2) + a2h * a2l + a2l * a2h) + a2l * a2l
			var t2 := err2 + (bh * bl + bl * bh)
			var s2 := p2 + t2
			bl = t2 - (s2 - p2)
			bh = s2

	# 单次舍入
	return rh + rl
