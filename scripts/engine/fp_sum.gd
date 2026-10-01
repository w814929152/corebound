class_name FpSum
extends RefCounted
##
## 🔴 与 Python `sum()` **逐位对齐** 的浮点求和
##
## 为什么需要它
## ----------------
## 切片2 联调，继 fp_pow.gd 之后发现的**第二个**末位分歧源：
##
##   Python 3.12+ 的 `sum()` 对 float 有**专用快路径**——走
##   **Neumaier 补偿求和**（bltinmodule.c 里的 `f_result` / `f_result_err` 双累加器），
##   最后返回 `f_result + f_result_err`。
##   而 GDScript 的 `subtotal += x` 是**朴素左结合累加**。
##
##   二者最要命的差别：补偿求和**对同一多重集与次序无关**（误差项被单独累计），
##   朴素累加则不然。金标本里 `subtotal = sum(p["dps"] for p in per_tower)`，
##   而贪心 AI 会给「升级 S3」和「升级 S5」这两种状态各算一次 subtotal ——
##   两个状态的逐塔 dps 是**同一多重集、只换了位置**。
##
##   实测（B 局第 18 局 W4 step2，四个并列候选 ΔDPS）：
##     Python（补偿求和）  up@0/@3/@4/@5 → 全部 9.406670173149649  → max 取第一个 @0
##     GDScript（朴素）    up@0/@3/@4    → 9.406670173149635
##                         up@5          → 9.406670173149649   ← 大了 1.4e-14，被选中
##   → 又是一次「并列被末位噪声翻转」，起飞波 13 → 15。
##
## 验证：FP 快路径只在**每一项都是 float** 时启用；本工程 `sum(p["dps"] ...)`
##       的每一项都是 `base*stack*...*cov` 的结果，恒为 float → 快路径必生效。
##
## ⚠️ Godot 坑
##   G1 `absf()` 的返回类型推不出来 → 比较结果必须显式 `: bool` 或就地用。
##   G2 不要用 `+=` 的链式写法，会被读成整数运算；这里全是 float 局部变量。
##   G3 Python 的 `sum()` 起始值是 **int 0**（等价于 0.0），第一次迭代走 else 分支，
##      补偿项 += 0 —— 与下面的实现一致。
##

# ---------------------------------------------------------------------------
# CPython `sum()` float 快路径（Neumaier）的逐行移植
# ---------------------------------------------------------------------------
static func sum_py(values: Array) -> float:
	var s := 0.0
	var err := 0.0
	for v in values:
		var x := float(v)
		var t := s + x
		if absf(s) >= absf(x):
			err += (s - t) + x
		else:
			err += (x - t) + s
		s = t
	return s + err
