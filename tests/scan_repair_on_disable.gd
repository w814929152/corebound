extends SceneTree
##
## headless V-7 repair_on_disable three-arm scan (QG-RADIAL-01) -- ADD-RUN / TWO-SIDED edition
##
## Mission: is GDD 2.3 "you can still repair a dead tower in the safe window" a real
## design or a paper design?  Three arms x N games x path A.
##   arm0 OFF    (repair_on_disable=0)  baseline replication (must be bit-identical)
##   arm1 FREE   (=1)  unconditional full repair between waves, no budget cost (structural probe)
##   arm2 PRICED (=2)  repair as a shop_ai candidate, priced ceil(0.30*invested_est), competes for budget
##
## ---------------------------------------------------------------------------
## ADD-RUN spec (2026-10-09, per design-strategist verdict; the 300-game first round
## was INCONCLUSIVE: delta<0 but within 1 SE of 0).
##   1. N = 1480 games/arm (two-sided alpha=0.05, power=80%, detect delta=0.05, p~0.642).
##   2. PRIMARY criterion is now `hit_surv > 0`: does any game that LOST a tower climb
##      back?  Structural, binary, needs no effect-size gate.  Delta is demoted to a
##      co-equal reading.  Also report `n_rescue`.
##   3. TWO-SIDED tests (the one-sided justification died with the snap/rest fix).
##   4. Parameters frozen: SpaceModel.mode=RADIAL | n_slots=8 | max_actions=12 |
##      aggro=true | exp=0.6 | attrition=1.50 | warmup=2 | rng=PyRandom(20261002)
##      (same seed as baseline -> pairing premise) | max_wave=20 | restore mode after run.
##   5. Keep the 3.7 diagnostic counters + n_identical pairing check.
##
## Tower-death definitions (BOTH are printed; the FORM one is the baseline口径 and is PRIMARY):
##   X_form  = sum(dis_new) over waves W6..W12   <- run_slice_attrition8._collect() "xf"
##             (this is the quantity behind baseline hit=0.1900 / hit_fail=0.4711 / hit_surv=0/179)
##   X_any   = sum(dis_new) over all waves W1..20 (broader; catches late snowball deaths)
## Per game:
##   survived  = last row core_hp > 0
##   rescued   = (X_form >= 1) AND survived   -> hit_surv numerator ("lost a tower and climbed back")
##   rescued_a = (X_any  >= 1) AND survived   -> same, any-wave reading
##   restored  = exists w: towers_disabled drops vs previous wave -> the tower itself came back
##   hit_surv  = n_rescue / n_surv    (r2-criteria-revision 4.4 definition: P(X_form>=1 | survived))
##   rescue_rt = n_rescue / n_td      (the "0/57" reading: P(survived | X_form>=1))
##
## Output discipline: ASCII only (Windows GBK mangles CJK on the console).
## Markers: [sig]/[ns]/[PASS]/[FAIL]/[INFO].
##
## Run:
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_repair_on_disable.gd
##   <godot> --headless --path D:/roguedemo --script res://tests/scan_repair_on_disable.gd RUNS=1480
##
const _RunLoopAggro := preload("res://scripts/engine/run_loop_aggro.gd")
const _Cfg := preload("res://scripts/engine/mvp_config.gd")
const _PyRandom := preload("res://scripts/engine/py_random.gd")
const _SpaceModel := preload("res://scripts/geo/space_model.gd")

const RUNS_DEFAULT := 300
const MAX_WAVE := 20
const ATTRITION := 1.50
const WARMUP := 2
const SEED := 20261002
const DELTA_GATE := 0.05        # product-level "design significance" gate for delta (co-equal reading)
const TD_UPPER_OLD := 0.2933    # STALE: pre-fix 88/300. Dead after snap/rest fix (see 3.2 refutation).
const Z_CRIT := 1.959964        # two-sided alpha=0.05
const ALPHA := 0.05
# tower-death window (run_slice_attrition8: W_SURV_END=5 < w <= W_FORM_END=12)
const W_SURV_END := 5
const W_FORM_END := 12
# baseline window used for the zero-perturbation assertion (run_slice_attrition8 post-fix)
const BASE_N := 300
const BASE_SURV := 179
const BASE_FAIL := 121
const BASE_TD_FORM := 57

# cmdline-overridable
var RUNS := RUNS_DEFAULT

# ---- log-factorial cache (Fisher exact) ----
static var _lf: Array = []


func _lfact(n: int) -> float:
	while _lf.size() <= n:
		var k: int = _lf.size()
		if k <= 1:
			_lf.append(0.0)
		else:
			_lf.append(float(_lf[k - 1]) + log(float(k)))
	return float(_lf[n])


func _lchoose(n: int, k: int) -> float:
	if k < 0 or k > n or n < 0:
		return -INF
	return _lfact(n) - _lfact(k) - _lfact(n - k)


## Fisher exact two-sided p for the 2x2 table [[a,b],[c,d]] (rows = arms).
func _fisher2(a: int, b: int, c: int, d: int) -> float:
	var n0: int = a + b
	var n1: int = c + d
	var tot: int = n0 + n1
	var s: int = a + c
	if tot <= 0 or s < 0 or s > tot:
		return 1.0
	var lo: int = maxi(0, s - n1)
	var hi: int = mini(n0, s)
	var den: float = _lchoose(tot, s)
	var p_obs: float = exp(_lchoose(n0, a) + _lchoose(n1, s - a) - den)
	var acc := 0.0
	for k in range(lo, hi + 1):
		var pk: float = exp(_lchoose(n0, k) + _lchoose(n1, s - k) - den)
		if pk <= p_obs * (1.0 + 1e-9):
			acc += pk
	return mini(1.0, acc)


## Wald two-proportion two-sided z (unpooled SE).
func _wald_z(x0: int, n0: int, x1: int, n1: int) -> float:
	if n0 <= 0 or n1 <= 0:
		return 0.0
	var p0: float = float(x0) / float(n0)
	var p1: float = float(x1) / float(n1)
	var se: float = sqrt(p0 * (1.0 - p0) / float(n0) + p1 * (1.0 - p1) / float(n1))
	if se <= 0.0:
		return 0.0
	return (p1 - p0) / se


## McNemar exact two-sided p on paired booleans (b = 0->1 discordant, c = 1->0).
func _mcnemar2(b: int, c: int) -> float:
	var n: int = b + c
	if n <= 0:
		return 1.0
	var m: int = maxi(b, c)
	var acc := 0.0
	for k in range(m, n + 1):
		acc += exp(_lchoose(n, k) - float(n) * log(2.0))
	return mini(1.0, 2.0 * acc)


## paired discordance counts between two arms' per-game booleans
func _discordant(a_recs: Array, b_recs: Array, key: String) -> Array:
	var b01 := 0
	var b10 := 0
	for i in range(mini(a_recs.size(), b_recs.size())):
		var va: bool = bool(a_recs[i][key])
		var vb: bool = bool(b_recs[i][key])
		if (not va) and vb:
			b01 += 1
		elif va and (not vb):
			b10 += 1
	return [b01, b10]


# ─────────────────────────────────────────────────────────────────────────────
# one arm: N games, path A.  mode_val: 0=OFF 1=FREE 2=PRICED
# ─────────────────────────────────────────────────────────────────────────────
func _run_arm(mode_val: int) -> Dictionary:
	var rng := _PyRandom.new(SEED)
	var cfgA := _Cfg.cfg_of("A")
	cfgA["n_slots"] = 8
	cfgA["max_actions"] = 12
	cfgA["repair_on_disable"] = mode_val
	# diag container (injected on every non-OFF arm):
	#   [0]=n_repair_enumerated [1]=n_repair_fired [2]=n_no_money
	#   [3]=spend_repair_total  [4]=n_repair_eligible [5]=n_repair_then_redied
	var diag := [0, 0, 0, 0.0, 0, 0]
	var recs: Array = []
	var n_surv := 0
	var n_fail := 0
	var n_td := 0            # X_form >= 1  (baseline口径, PRIMARY)
	var n_td_any := 0        # X_any  >= 1  (any wave)
	var n_rescue := 0        # X_form>=1 AND survived
	var n_rescue_any := 0    # X_any >=1 AND survived
	var n_restored := 0
	var n_restored_events := 0
	# zero-perturbation window: first BASE_N games must replicate the baseline exactly
	var b_surv := 0
	var b_fail := 0
	var b_td := 0
	for _i in range(RUNS):
		var per_diag := [0, 0, 0, 0.0, 0, 0]
		var out := _RunLoopAggro.run("A", cfgA, MAX_WAVE, null, rng, true, 0.6, ATTRITION, WARMUP, false, false, false, 0.0, per_diag)
		var rows: Array = out["rows"]
		var survived := (not rows.is_empty()) and float(rows[-1]["core_hp"]) > 0.0
		var xf := _run_xform(rows)
		var xa := _run_td_any(rows)
		var ndrop: int = _run_dis_drop_events(rows)
		if survived:
			n_surv += 1
		else:
			n_fail += 1
		if xf > 0:
			n_td += 1
		if xa > 0:
			n_td_any += 1
		if xf > 0 and survived:
			n_rescue += 1
		if xa > 0 and survived:
			n_rescue_any += 1
		if ndrop > 0:
			n_restored += 1
			n_restored_events += ndrop
		recs.append({
			"fail": not survived,
			"td": xf,
			"td_any": xa,
			"rescued": (xf > 0 and survived),
			"rescued_any": (xa > 0 and survived),
			"restored": (ndrop > 0),
			"sig": _rows_sig(rows),
		})
		if _i < BASE_N:
			if survived:
				b_surv += 1
			else:
				b_fail += 1
			if xf > 0:
				b_td += 1
		if mode_val != 0:
			diag[0] = int(diag[0]) + int(per_diag[0])
			diag[1] = int(diag[1]) + int(per_diag[1])
			diag[2] = int(diag[2]) + int(per_diag[2])
			diag[3] = float(diag[3]) + float(per_diag[3])
			diag[4] = int(diag[4]) + int(per_diag[4])
			diag[5] = int(diag[5]) + int(per_diag[5])
	return {
		"surv": float(n_surv) / float(RUNS),
		"n_surv": n_surv,
		"n_fail": n_fail,
		"n_td": n_td,
		"n_td_any": n_td_any,
		"n_rescue": n_rescue,
		"n_rescue_any": n_rescue_any,
		"n_restored": n_restored,
		"n_restored_events": n_restored_events,
		"hit_surv": (float(n_rescue) / float(n_surv)) if n_surv > 0 else 0.0,
		"rescue_rt": (float(n_rescue) / float(n_td)) if n_td > 0 else 0.0,
		"hit_surv_any": (float(n_rescue_any) / float(n_surv)) if n_surv > 0 else 0.0,
		"rescue_rt_any": (float(n_rescue_any) / float(n_td_any)) if n_td_any > 0 else 0.0,
		"diag": diag,
		"recs": recs,
		"b_surv": b_surv,
		"b_fail": b_fail,
		"b_td": b_td,
	}


## X_form: tower deaths inside the formation window W6..W12 (baseline口径)
func _run_xform(rows: Array) -> int:
	var xf := 0
	for r in rows:
		var wn: int = int(r["w"])
		if wn > W_SURV_END and wn <= W_FORM_END:
			xf += int(r.get("dis_new", 0))
	return xf


## X_any: tower deaths over the whole run W1..20
func _run_td_any(rows: Array) -> int:
	var tot := 0
	for r in rows:
		tot += int(r.get("dis_new", 0))
	return tot


## number of waves where the Disabled-tower count DROPPED vs the previous wave.
## OFF arm: disabled is permanent -> count is monotone non-decreasing -> structurally 0.
## Any drop is direct proof a repair fired and the tower survived to the end of a wave.
## CONSERVATIVE: misses "repaired and re-killed inside the very next wave" (E-V3), i.e. it
## is a lower bound on repair events.  The exact count is diag[1] (n_repair_fired).
func _run_dis_drop_events(rows: Array) -> int:
	var n := 0
	for i in range(rows.size() - 1):
		if int(rows[i + 1].get("towers_disabled", 0)) < int(rows[i].get("towers_disabled", 0)):
			n += 1
	return n


## per-wave bit-exact signature (three-arm pairing check)
func _rows_sig(rows: Array) -> String:
	var parts: Array = []
	for r in rows:
		parts.append("%d|%d|%d|%d|%d|%d" % [
			int(r["w"]), int(r.get("dis_new", 0)), int(r.get("towers", 0)),
			int(r.get("towers_disabled", 0)), int(r.get("rerolls", 0)),
			int(round(float(r.get("core_hp", 0.0))))])
	return ";".join(parts)


func _se(p: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return sqrt(maxf(0.0, p * (1.0 - p)) / float(n))


func _parse_runs() -> int:
	var v: int = RUNS_DEFAULT
	for a in OS.get_cmdline_args():
		var s := String(a)
		if s.begins_with("--runs="):
			v = int(s.substr(7))
		elif s.begins_with("RUNS="):
			v = int(s.substr(5))
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--runs="):
			v = int(s.substr(7))
		elif s.begins_with("RUNS="):
			v = int(s.substr(5))
	return maxi(1, v)


func _pflag(p: float) -> String:
	return "sig" if p < ALPHA else "ns"


func _zflag(z: float) -> String:
	return "sig" if absf(z) >= Z_CRIT else "ns"


func _initialize() -> void:
	RUNS = _parse_runs()
	print("===================================================================")
	print("V-7 repair_on_disable ADD-RUN (path A | N=%d/arm | seed %d | TWO-SIDED)" % [RUNS, SEED])
	print("primary = hit_surv / n_rescue (any game that lost a tower and climbed back)")
	print("tower-death primary口径 = X_form (W%d..W%d, run_slice_attrition8 xf)" % [W_SURV_END + 1, W_FORM_END])
	print("===================================================================")

	# RADIAL for this scan only; restored to PATH afterwards
	_SpaceModel.mode = _SpaceModel.Mode.RADIAL

	var arm_off := _run_arm(0)
	var arm_free := _run_arm(1)
	var arm_priced := _run_arm(2)

	# ---- pairing check ----
	var n_identical := 0
	for i in range(RUNS):
		if arm_off["recs"][i]["sig"] == arm_free["recs"][i]["sig"] \
				and arm_off["recs"][i]["sig"] == arm_priced["recs"][i]["sig"]:
			n_identical += 1
	var n_discordant: int = RUNS - n_identical
	var pairing_ok: bool = n_identical >= int(0.5 * float(RUNS))

	# ---- delta ----
	var d_free: float = float(arm_free["surv"]) - float(arm_off["surv"])
	var d_priced: float = float(arm_priced["surv"]) - float(arm_off["surv"])
	# independent two-proportion SE (conservative)
	var se_free_indep: float = sqrt((arm_off["surv"]*(1.0-arm_off["surv"]) + arm_free["surv"]*(1.0-arm_free["surv"])) / float(RUNS))
	var se_priced_indep: float = sqrt((arm_off["surv"]*(1.0-arm_off["surv"]) + arm_priced["surv"]*(1.0-arm_priced["surv"])) / float(RUNS))
	# paired SE (same-seed discordance only on tower-death games)
	var r_free: float = (d_free * float(RUNS)) / float(maxi(1, arm_off["n_td"]))
	var r_priced: float = (d_priced * float(RUNS)) / float(maxi(1, arm_off["n_td"]))
	var se_free_pair: float = sqrt(float(arm_off["n_td"]) * r_free * (1.0 - r_free)) / float(RUNS) if arm_off["n_td"] > 0 else 0.0
	var se_priced_pair: float = sqrt(float(arm_off["n_td"]) * r_priced * (1.0 - r_priced)) / float(RUNS) if arm_off["n_td"] > 0 else 0.0
	var se_free: float = se_free_pair if pairing_ok else se_free_indep
	var se_priced: float = se_priced_pair if pairing_ok else se_priced_indep
	var z_free: float = d_free / se_free if se_free > 0.0 else 0.0
	var z_priced: float = d_priced / se_priced if se_priced > 0.0 else 0.0
	var mde_free: float = (Z_CRIT + 0.8416) * se_free
	var mde_priced: float = (Z_CRIT + 0.8416) * se_priced

	print("")
	print("---- arm summary ----")
	for pair in [["OFF   ", arm_off], ["FREE  ", arm_free], ["PRICED", arm_priced]]:
		var a: Dictionary = pair[1]
		print("  [arm %s] surv=%.4f (%d/%d)  n_fail=%d  n_td_form=%d  n_td_any=%d  n_rescue=%d  n_rescue_any=%d  n_restored=%d"
			% [String(pair[0]), float(a["surv"]), int(a["n_surv"]), RUNS, int(a["n_fail"]),
				int(a["n_td"]), int(a["n_td_any"]), int(a["n_rescue"]), int(a["n_rescue_any"]), int(a["n_restored"])])

	print("")
	print("---- PRIMARY: hit_surv / n_rescue (lost a tower and climbed back) ----")
	print("  arm      n_td_form  n_rescue  hit_surv=n_rescue/n_surv  rescue_rt=n_rescue/n_td  | n_td_any  n_rescue_any  rescue_rt_any")
	for pair in [["OFF   ", arm_off], ["FREE  ", arm_free], ["PRICED", arm_priced]]:
		var a: Dictionary = pair[1]
		print("  %s  %8d  %8d   %.4f (%d/%d)            %.4f (%d/%d)         | %8d  %8d      %.4f"
			% [String(pair[0]), int(a["n_td"]), int(a["n_rescue"]), float(a["hit_surv"]), int(a["n_rescue"]), int(a["n_surv"]),
				float(a["rescue_rt"]), int(a["n_rescue"]), int(a["n_td"]),
				int(a["n_td_any"]), int(a["n_rescue_any"]), float(a["rescue_rt_any"])])

	# pairwise tests vs OFF
	print("")
	print("---- tests vs OFF (two-sided, alpha=0.05) ----")
	print("  (Fisher = exact two-sided on the 2x2; Wald z = unpooled two-proportion;")
	print("   McNemar = exact conditional on same-seed paired games, b=0->1, c=1->0)")
	for tag in ["rescued", "rescued_any", "restored"]:
		for pair in [["FREE", arm_free], ["PRICED", arm_priced]]:
			var nm := String(pair[0])
			var arm: Dictionary = pair[1]
			var x0: int = int(arm_off["n_rescue"]) if tag == "rescued" else (int(arm_off["n_rescue_any"]) if tag == "rescued_any" else int(arm_off["n_restored"]))
			var x1: int = int(arm["n_rescue"]) if tag == "rescued" else (int(arm["n_rescue_any"]) if tag == "rescued_any" else int(arm["n_restored"]))
			var y0: int = int(arm_off["n_surv"]) if tag != "restored" else int(arm_off["n_td_any"])
			var y1: int = int(arm["n_surv"]) if tag != "restored" else int(arm["n_td_any"])
			var z0: int = int(arm_off["n_td"]) if tag == "rescued" else int(arm_off["n_td_any"])
			var z1: int = int(arm["n_td"]) if tag == "rescued" else int(arm["n_td_any"])
			var pf_surv: float = _fisher2(x0, y0 - x0, x1, y1 - x1)
			var pf_td: float = _fisher2(x0, z0 - x0, x1, z1 - x1)
			var zs: float = _wald_z(x0, y0, x1, y1)
			var dsc: Array = _discordant(arm_off["recs"], arm["recs"], tag)
			var pm: float = _mcnemar2(int(dsc[0]), int(dsc[1]))
			print("  [%-11s/%-6s] OFF %d/%d vs %s %d/%d | Fisher p(hit_surv)=%.5f [%s]  Fisher p(n_td den)=%.5f [%s]  Wald z=%+.2f [%s]  McNemar p=%.5f [%s] (b=%d,c=%d)"
				% [tag, nm, x0, y0, nm, x1, y1, pf_surv, _pflag(pf_surv), pf_td, _pflag(pf_td), zs, _zflag(zs), pm, _pflag(pm), int(dsc[0]), int(dsc[1])])

	# rule-of-three upper bound when the count is 0
	print("")
	print("---- rule-of-three (95% upper bound on the rescue rate when 0 events) ----")
	for pair in [["OFF   ", arm_off], ["FREE  ", arm_free], ["PRICED", arm_priced]]:
		var a: Dictionary = pair[1]
		var k: int = int(a["n_rescue"])
		var nt: int = int(a["n_td"])
		print("  [%s] n_rescue=%d / n_td_form=%d -> upper = %.5f%s"
			% [String(pair[0]), k, nt, (3.0 / float(maxi(1, nt))) if k == 0 else float(k) / float(maxi(1, nt)),
				"   (0 events: rate < 3/n)" if k == 0 else "   (observed)"])

	print("")
	print("---- CO-EQUAL: delta = surv_arm - surv_off (two-sided) ----")
	print("  pairing      n_identical=%d  n_discordant=%d  -> SE model: %s"
		% [n_identical, n_discordant, ("PAIRED (%.5f/%.5f)" % [se_free_pair, se_priced_pair]) if pairing_ok else ("INDEP (%.5f/%.5f)" % [se_free_indep, se_priced_indep])])
	print("  d_free   = %+.5f  SE=%.5f  z=%+.2f [%s]  95%%CI [%+.5f, %+.5f]  MDE80=%.5f"
		% [d_free, se_free, z_free, _zflag(z_free), d_free - Z_CRIT * se_free, d_free + Z_CRIT * se_free, mde_free])
	print("  d_priced = %+.5f  SE=%.5f  z=%+.2f [%s]  95%%CI [%+.5f, %+.5f]  MDE80=%.5f"
		% [d_priced, se_priced, z_priced, _zflag(z_priced), d_priced - Z_CRIT * se_priced, d_priced + Z_CRIT * se_priced, mde_priced])
	print("  gate      DELTA_GATE=%.2f ; CI upper vs gate: free %s / priced %s"
		% [DELTA_GATE,
			("below gate" if (d_free + Z_CRIT * se_free) < DELTA_GATE else "at/above gate"),
			("below gate" if (d_priced + Z_CRIT * se_priced) < DELTA_GATE else "at/above gate")])
	print("  [INFO] 3.2 'delta cannot be negative' is REFUTED (snap/rest fix): repair is a")
	print("         two-sided operation (+DPS restored, -the tower is re-exposed to aggro).")
	print("         Monotonicity 0 <= d_priced <= d_free <= %.4f is NO LONGER a gate (stale bound)." % TD_UPPER_OLD)
	print("  [INFO] ordering d_priced <= d_free (priced costs budget): %s" % ("OK" if d_priced <= d_free + 1e-9 else "VIOLATED (d_priced > d_free: unconditional repair is the worse arm)"))

	print("")
	print("---- 3.7 diagnostic counters ----")
	for pair in [["FREE", arm_free], ["PRICED", arm_priced]]:
		var dg: Array = pair[1]["diag"]
		print("  [%-6s] n_repair_eligible=%d  enumerated=%d  fired=%d  no_money=%d  then_redied=%d  spend=%.1f  (structural restore-events=%d)"
			% [String(pair[0]), int(dg[4]), int(dg[0]), int(dg[1]), int(dg[2]), int(dg[5]), float(dg[3]), int(pair[1]["n_restored_events"])])
	print("  [INFO] n_repair_lost_to_drop: structurally 0 -- AI route drop_from() removes")
	print("         CARDS, never towers, so a Disabled tower is never removed from player.towers.")
	print("  [INFO] FREE then_redied / eligible = %.4f  (share of tower-death runs where a"
		% [(float(arm_free["diag"][5]) / float(maxi(1, int(arm_free["diag"][4]))))])
	print("         repaired tower was knocked out again in a LATER wave -- E-V3 'repaired for nothing')")

	# ---- verdict (two-sided reading; final adjudication stays with design-strategist) ----
	print("")
	print("---- verdict (TWO-SIDED, preliminary; final call: design-strategist) ----")
	var fr: int = int(arm_free["n_rescue"])
	var pr: int = int(arm_priced["n_rescue"])
	var frr: int = int(arm_free["n_restored"])
	var prr: int = int(arm_priced["n_restored"])
	var pf_free: float = _fisher2(int(arm_off["n_rescue"]), int(arm_off["n_td"]) - int(arm_off["n_rescue"]), fr, int(arm_free["n_td"]) - fr)
	var pf_priced: float = _fisher2(int(arm_off["n_rescue"]), int(arm_off["n_td"]) - int(arm_off["n_rescue"]), pr, int(arm_priced["n_td"]) - pr)
	var pm_free: float = _mcnemar2(int(_discordant(arm_off["recs"], arm_free["recs"], "rescued")[0]), int(_discordant(arm_off["recs"], arm_free["recs"], "rescued")[1]))
	var pm_priced: float = _mcnemar2(int(_discordant(arm_off["recs"], arm_priced["recs"], "rescued")[0]), int(_discordant(arm_off["recs"], arm_priced["recs"], "rescued")[1]))
	var free_sig: bool = (fr > 0) and (pf_free < ALPHA) and (pm_free < ALPHA)
	var priced_sig: bool = (pr > 0) and (pf_priced < ALPHA) and (pm_priced < ALPHA)
	print("  PRIMARY (hit_surv, X_form口径):")
	print("    OFF    n_rescue=%d/%d  rate=%.5f  (structural 0: disabled is permanent)"
		% [int(arm_off["n_rescue"]), int(arm_off["n_td"]), float(arm_off["rescue_rt"])])
	print("    FREE   n_rescue=%d/%d  rate=%.5f  Fisher p=%.5f [%s]  McNemar p=%.5f [%s]  -> %s"
		% [fr, int(arm_free["n_td"]), float(arm_free["rescue_rt"]), pf_free, _pflag(pf_free), pm_free, _pflag(pm_free),
			("EXISTENCE ESTABLISHED (sig > 0)" if free_sig else ("NO game ever climbed back (0 events, 95%% upper < %.5f)" % (3.0 / float(maxi(1, int(arm_free["n_td"]))))))])
	print("    PRICED n_rescue=%d/%d  rate=%.5f  Fisher p=%.5f [%s]  McNemar p=%.5f [%s]  -> %s"
		% [pr, int(arm_priced["n_td"]), float(arm_priced["rescue_rt"]), pf_priced, _pflag(pf_priced), pm_priced, _pflag(pm_priced),
			("EXISTENCE ESTABLISHED (sig > 0)" if priced_sig else "NOT established (0 or ns)")])
	print("    n_restored (tower literally came back for >=1 full wave): FREE=%d  PRICED=%d" % [frr, prr])
	print("")
	print("  DELTA (co-equal, two-sided):")
	print("    FREE   d=%+.5f  z=%+.2f [%s]  CI [%+.5f, %+.5f]  -> %s"
		% [d_free, z_free, _zflag(z_free), d_free - Z_CRIT * se_free, d_free + Z_CRIT * se_free,
			("C1: significantly HARMFUL (CI upper < 0, |z|>=1.96)" if ((d_free + Z_CRIT * se_free) < 0.0 and absf(z_free) >= Z_CRIT) else ("not significant -> branch C NOT established" if absf(z_free) < Z_CRIT else "significant, direction positive/other"))])
	print("    PRICED d=%+.5f  z=%+.2f [%s]  CI [%+.5f, %+.5f]  -> %s"
		% [d_priced, z_priced, _zflag(z_priced), d_priced - Z_CRIT * se_priced, d_priced + Z_CRIT * se_priced,
			("C2: significantly BELOW the +%.2f gate" % DELTA_GATE if ((d_priced + Z_CRIT * se_priced) < DELTA_GATE and absf(z_priced) >= Z_CRIT) else ("not significant two-sided -> branch C NOT established (falls to B)" if absf(z_priced) < Z_CRIT else "significant, above gate"))])
	print("")
	var vline := ""
	if free_sig and priced_sig:
		vline = "A* -- existence established on BOTH arms (magnitude still gated by delta: PRICED CI upper = %+.5f vs gate +%.2f)" % [d_priced + Z_CRIT * se_priced, DELTA_GATE]
	elif priced_sig and (not free_sig):
		vline = "SPLIT -- existence established ONLY on PRICED (%d/%d), NOT on FREE (0/%d); delta: PRICED %+.5f (ns), FREE %+.5f (sig negative)" % [pr, int(arm_priced["n_td"]), int(arm_free["n_td"]), d_priced, d_free]
	elif free_sig and (not priced_sig):
		vline = "SPLIT -- existence on FREE only; PRICED = 0 -> pricing/budget kills it (C' reading)"
	else:
		vline = "B / C-FATAL -- no arm produced a single rescued game (FREE 0/%d, PRICED 0/%d)" % [int(arm_free["n_td"]), int(arm_priced["n_td"])]
	print("  PRELIMINARY READING: %s" % vline)
	print("  [NOTE] branch C requires two-sided significance (|z| >= 1.96) on delta.")
	print("         Final adjudication: design-strategist.")

	# ---- zero-perturbation (B-2) ----
	print("")
	print("---- zero-perturbation (B-2) ----")
	if RUNS >= BASE_N:
		var off_ok: bool = (int(arm_off["b_surv"]) == BASE_SURV) and (int(arm_off["b_fail"]) == BASE_FAIL) and (int(arm_off["b_td"]) == BASE_TD_FORM)
		print("  OFF arm first %d games: surv=%d  fail=%d  n_td_form=%d   vs post-fix baseline %d/%d/%d -> %s"
			% [BASE_N, int(arm_off["b_surv"]), int(arm_off["b_fail"]), int(arm_off["b_td"]),
				BASE_SURV, BASE_FAIL, BASE_TD_FORM, "PASS" if off_ok else "FAIL (switch-off path polluted -> whole round void)"])
		print("  (baseline 0.617/185/88 in spec 1.2 is the PRE-FIX snap/rest bug value; post-fix = 0.597/179/57)")
	else:
		print("  SKIPPED (RUNS=%d < %d, baseline window not covered)" % [RUNS, BASE_N])

	print("")
	print("  [fact] B path n_repair_eligible = 0 (radial multi-tower flow never loses a tower)")
	print("  [fact] OFF arm n_restored must be 0 by construction (disabled is permanent): %d" % int(arm_off["n_restored"]))

	# restore PATH mode
	_SpaceModel.mode = _SpaceModel.Mode.PATH

	print("")
	print("===================================================================")
	print("V-7 ADD-RUN done (diagnostic artifact | always exit 0 | verdict: design-strategist)")
	print("===================================================================")
	quit(0)
