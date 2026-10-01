class_name PyRandom
extends RefCounted
##
## Python `random.Random` 的**逐位等价**端口（MT19937 + genrand_res53）。
##
## 为什么需要它（而不是直接用 Godot 的 RandomNumberGenerator）：
##   Phase 2 的蒙特卡洛起飞率（A 69.3% / B 91.3%，MC 300 局 seed=20260930）
##   是 Python `random.Random(seed)` 序列的产物。Godot 的 RNG 是 PCG32，
##   序列不同 → 起飞率会漂。为了能在 headless 里**逐位复现**金标本的 MC 结果
##   （而不是"统计上差不多"），必须把 MT19937 搬过来。
##
## 金标本：CPython Modules/_randommodule.c
##   · `random_seed()`   → 把 int seed 拆成小端 32-bit 字数组 → `init_by_array()`
##   · `init_genrand(s)` → mt[0]=s; mt[i] = 1812433253·(mt[i-1]^(mt[i-1]>>30)) + i
##   · `init_by_array()` → 见下（19650218 打底）
##   · `genrand_uint32()`→ 标准 twist + tempering
##   · `random()`        → genrand_res53：(a>>5, b>>6) 拼 53 bit × 2^-53
##
## ⚠️ Godot 坑
##   1) Godot int 是 **64-bit 有符号**二等补码；MT19937 的字是 uint32。
##      所有"回绕"统一用 `& 0xffffffff` —— 对负数也成立（补码按位与）。
##   2) Python 的 `>>` 对非负整数是逻辑右移；这里所有被移的值都 < 2^32，等价。
##   3) `init_by_array` 里 `1566083941 * (...)` 最大 ≈ 6.7e18 < int64 上限 9.22e18，
##      `1812433253 * (...)` 最大 ≈ 7.8e18，都**不会溢出**，不需要 128 位运算。
##   4) `random()` 必须用 `* (1.0 / 9007199254740992.0)`（乘 2^-53），
##      不能写 `/ 9007199254740992.0` —— 虽然 2 的幂除法也精确，但保持与 CPython
##      同一表达式，避免任何 ULP 分歧。
##

const N := 624
const M := 397
const MATRIX_A := 0x9908b0df
const UPPER_MASK := 0x80000000
const LOWER_MASK := 0x7fffffff
const M32 := 0xffffffff

var mt: PackedInt64Array = PackedInt64Array()
var mti: int = 0


# ---------------------------------------------------------------------------
# 构造：seed 为 int（Python `random.Random(seed)`）
# ---------------------------------------------------------------------------
func _init(seed_value: int = 0) -> void:
	mt.resize(N)
	for i in range(N):
		mt[i] = 0
	# Python 的 random_seed：abs(seed) 拆成小端 32-bit 字（seed=20260930 → 1 个字）
	var key := _seed_to_key(seed_value)
	_init_by_array(key)


static func _seed_to_key(seed_value: int) -> Array:
	var n := absi(seed_value)
	var words: Array = []
	if n == 0:
		words.append(0)
	while n > 0:
		words.append(n & M32)
		n = n >> 32
	# _PyLong_AsByteArray(..., PY_LITTLE_ENDIAN) → words[0] 已是低位字，顺序不变
	return words


func _init_genrand(s: int) -> void:
	mt[0] = s & M32
	for i in range(1, N):
		var prev := int(mt[i - 1])
		mt[i] = (1812433253 * (prev ^ (prev >> 30)) + i) & M32
	mti = N


func _init_by_array(key: Array) -> void:
	_init_genrand(19650218)
	var i := 1
	var j := 0
	var k: int = maxi(N, key.size())
	while k > 0:
		var prev := int(mt[i - 1])
		mt[i] = (int(mt[i]) ^ ((prev ^ (prev >> 30)) * 1664525)) + int(key[j]) + j
		mt[i] = int(mt[i]) & M32
		i += 1
		j += 1
		if i >= N:
			mt[0] = mt[N - 1]
			i = 1
		if j >= key.size():
			j = 0
		k -= 1
	k = N - 1
	while k > 0:
		var prev := int(mt[i - 1])
		mt[i] = (int(mt[i]) ^ ((prev ^ (prev >> 30)) * 1566083941)) - i
		mt[i] = int(mt[i]) & M32
		i += 1
		if i >= N:
			mt[0] = mt[N - 1]
			i = 1
		k -= 1
	mt[0] = 0x80000000
	mti = N


# ---------------------------------------------------------------------------
# genrand_uint32（CPython genrand_uint32）
# ---------------------------------------------------------------------------
func genrand_uint32() -> int:
	if mti >= N:
		_twist()
	var y := int(mt[mti])
	mti += 1
	y ^= (y >> 11)
	y ^= (y << 7) & 0x9d2c5680
	y ^= (y << 15) & 0xefc60000
	y ^= (y >> 18)
	return y & M32


func _twist() -> void:
	var mag01 := [0, MATRIX_A]
	var y := 0
	for kk in range(N - M):
		y = (int(mt[kk]) & UPPER_MASK) | (int(mt[kk + 1]) & LOWER_MASK)
		mt[kk] = int(mt[kk + M]) ^ (y >> 1) ^ mag01[y & 0x1]
	for kk in range(N - M, N - 1):
		y = (int(mt[kk]) & UPPER_MASK) | (int(mt[kk + 1]) & LOWER_MASK)
		mt[kk] = int(mt[kk + (M - N)]) ^ (y >> 1) ^ mag01[y & 0x1]
	y = (int(mt[N - 1]) & UPPER_MASK) | (int(mt[0]) & LOWER_MASK)
	mt[N - 1] = int(mt[M - 1]) ^ (y >> 1) ^ mag01[y & 0x1]
	mti = 0


# ---------------------------------------------------------------------------
# random() —— genrand_res53
# ---------------------------------------------------------------------------
func random() -> float:
	var a := genrand_uint32() >> 5
	var b := genrand_uint32() >> 6
	return (float(a) * 67108864.0 + float(b)) * (1.0 / 9007199254740992.0)


# ---------------------------------------------------------------------------
# Python `random.choices(population, weights=..., k=k)` 的逐位等价实现
#   cum = accumulate(weights); total = cum[-1] + 0.0
#   i   = bisect_right(cum, random()*total, 0, n-1)   ← hi = n-1 是关键
# ---------------------------------------------------------------------------
func choices(population: Array, weights: Array, k: int) -> Array:
	var n := population.size()
	var cum: Array = []
	var acc := 0.0
	for w in weights:
		acc += float(w)
		cum.append(acc)
	var total := float(cum[n - 1]) + 0.0
	var out: Array = []
	out.resize(k)
	for _i in range(k):
		var u := random() * total
		# bisect_right(cum, u, 0, n-1)：返回 [0, n-1] 内第一个 cum[i] > u 的 i
		var idx := n - 1
		for i in range(n - 1):
			if float(cum[i]) > u:
				idx = i
				break
		out[_i] = population[idx]
	return out


# ---------------------------------------------------------------------------
# Python `random.choice(seq)` = seq[self._randbelow(len(seq))]
#   ⚠️🔴 **不是** `seq[int(random()*len(seq))]`！
#      `_randbelow` 走 `getrandbits(k)`（n≤4 时 k=2，只吃 **1 个** uint32），
#      而 `random()` 吃 **2 个** uint32。两者消耗序列不同 → 蒙特卡洛会整体漂。
#      （踩过：写成 random() 版本时 MC 起飞率 A 69.3%→67.7%、B 91.3%→88.0%，
#        逐波决定性跑却完全对得上 —— 这类 bug 只有 MC 能抓到。）
# ---------------------------------------------------------------------------
func choice(seq: Array):
	var n := seq.size()
	if n == 0:
		push_error("PyRandom.choice(): 空序列")
		return null
	return seq[randrange(n)]


# ---------------------------------------------------------------------------
# Python `random.getrandbits(k)`（CPython _random_Random_getrandbits_impl）
#   k<=32 → genrand_uint32() >> (32-k)
#   k >32 → words = (k-1)//32+1，逐字左移拼接，最高字右移 (words*32-k)
# ---------------------------------------------------------------------------
func getrandbits(k: int) -> int:
	if k <= 0:
		return 0
	if k <= 32:
		return genrand_uint32() >> (32 - k)
	var words := (k - 1) / 32 + 1
	var res := 0
	for i in range(words):
		var r := genrand_uint32()
		if i == words - 1:
			r = r >> (words * 32 - k)
		res = (res << 32) | r
	return res


# ---------------------------------------------------------------------------
# Python `random.randrange(n)` = `_randbelow_with_getrandbits(n)`：拒绝采样
#   ⚠️ 不是 int(random()*n) —— 序列不同。MVP 定稿 skill=1.0 走不到这条分支，
#      但为了"口径即文档"还是照 CPython 实现。
# ---------------------------------------------------------------------------
func randrange(n: int) -> int:
	if n <= 0:
		return 0
	var k := _bit_length(n)
	while true:
		var r := getrandbits(k)
		if r < n:
			return r
	return 0    # 不可达（GDScript 静态检查要求所有路径都有返回）


static func _bit_length(v: int) -> int:
	if v <= 0:
		return 0
	var n := 0
	var x := v
	while x > 0:
		n += 1
		x = x >> 1
	return n
