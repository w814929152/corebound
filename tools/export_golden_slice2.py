# -*- coding: utf-8 -*-
"""
切片2 金标本导出器 —— 把 Python 金标本（v03 战斗循环 + v06/v07 口径）跑出的
**全精度**逐波 rows / 判据统计 / 蒙特卡洛起飞率 / RNG 参考序列，导出成
GDScript 常量文件 `tests/golden_slice2.gd` + 人类可读的 JSON 存档。

用法：
  <python> tools/export_golden_slice2.py
"""
from __future__ import annotations

import os
import sys
import json
import random
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIM_DIR = os.path.join(ROOT, "design", "phase2", "numeric-sim")
if SIM_DIR not in sys.path:
    sys.path.insert(0, SIM_DIR)

import corebound_sim_v03 as sv          # noqa: E402
import corebound_sim_v06_synergy as v6  # noqa: E402
import corebound_sim_v07_mapA as v7     # noqa: E402

OUT_GD = os.path.join(ROOT, "tests", "golden_slice2.gd")
OUT_JSON = os.path.join(ROOT, "docs", "phase3", "slice2-golden.json")

MC_RUNS = 300
SEED1 = 20260930


# ---------------------------------------------------------------------------
# 配置：与 mvp_config.gd :: cfg_of() 对齐（kr_mode 由参数给）
# ---------------------------------------------------------------------------
def cfg_for(path, kr_mode="tier", rule="substantial", kappa_r=0.045):
    return v7.cfg_of(path, kappa_r=kappa_r, rule=rule, kr_mode=kr_mode,
                     kr_tiers=v7.KR_TIERS_T1)


def row_dump(row):
    """全精度导出（Python 真值，未做 CSV 的 round）。"""
    return dict(
        w=row["w"], n=row["n"],
        hp_each=row["hp_each_raw"], total_hp=row["total_hp_raw"],
        eff_dps=row["eff_dps_raw"], ratio=row["ratio_raw"],
        core_hp=row["core_hp_raw"], income=row["income_raw"],
        rerolls=row["rerolls"], cum_rerolls=row["cum_rerolls"],
        towers=row["towers"], slots=row["slots"], build=row["build"],
        kills=row["kills"], leaked=row["leaked"],
        # round 后的列（与 CSV 同名同值）：校验 GDScript 的 pround 与 Python round 一致
        hp_each_r=row["hp_each"], total_hp_r=row["total_hp"],
        eff_dps_r=row["eff_dps"], ratio_r=row["ratio"],
        core_hp_r=row["core_hp"], income_r=row["income"],
    )


def run_rows(path, cfg, waves=20, rng=None):
    """复刻 sv.run()，但保留**未 round**的真值（CSV 里是 round 过的）。"""
    cfg = dict(cfg)
    geo = sv.GEO6
    player = sv.new_player(path, cfg, geo)
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0
    for w in range(1, waves + 1):
        res = sv.simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income
        budget, rr = sv.shop_phase(player, cum, w, cfg, geo, rng)
        cum = budget
        cum_rerolls += rr
        dps = sv.dps_only(player, cfg, geo)
        ratio = dps / res["total_hp"] if res["total_hp"] > 0 else 0.0
        rows.append(dict(
            w=w, n=res["n"],
            hp_each_raw=res["hp_each"], total_hp_raw=res["total_hp"],
            eff_dps_raw=dps, ratio_raw=ratio,
            core_hp_raw=max(0.0, core_hp), income_raw=income,
            # ★ 与 sv.run() 完全同名的 round 后的列：v06.summarize / stage_health 只读这些
            hp_each=round(res["hp_each"], 1), total_hp=round(res["total_hp"], 1),
            eff_dps=round(dps, 1), ratio=round(ratio, 3),
            core_hp=round(max(0.0, core_hp), 1), income=round(income, 1),
            rerolls=rr, cum_rerolls=cum_rerolls,
            towers=len(player.towers), slots=len(player.cards),
            build=player.build_str(),
            kills=res["kills"], leaked=res["leaked"],
        ))
        if core_hp <= 0:
            break
    return rows, player


def takeoff_rate_full(path, cfg, runs=MC_RUNS, max_wave=20, actions=12, seed=SEED1,
                      trace_runs=0):
    """trace_runs>0 时额外导出前 N 局的完整 rows（用于定位 GDScript 端口的发散点）。"""
    rng = random.Random(seed)
    takeoffs, survives, hits = 0, 0, []
    trace, trace_rows = [], []
    for i in range(runs):
        cfgx = dict(cfg)
        cfgx["max_actions"] = actions
        rows, _ = run_rows(path, cfgx, max_wave, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp_raw"] > 0
        if alive:
            survives += 1
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            takeoffs += 1
            hits.append(tw)
        if i < trace_runs:
            trace.append(tw if tw is not None else -1)
            trace_rows.append([row_dump(r) for r in rows])
    return dict(rate=round(takeoffs / runs, 3), surv=round(survives / runs, 3),
                med=statistics.median(hits) if hits else None,
                n_takeoff=takeoffs, n_surv=survives,
                trace=trace, trace_rows=trace_rows)


def rng_reference(seed=SEED1, n_random=24, n_choices=8):
    """导出 Python random.Random(seed) 的参考序列，用于校验 GDScript MT19937 端口。
    ★ 每条序列都用**独立的** Random(seed)：否则 offers 会落在 random() 之后的状态，
      校验时必须先空跑 24 次 random()，既难写又容易错。"""
    r1 = random.Random(seed)
    rnd = [r1.random() for _ in range(n_random)]
    r2 = random.Random(seed)
    ch = [sv.draw_offers(r2, 3, None) for _ in range(n_choices)]
    r3 = random.Random(seed)
    chf = [sv.draw_offers(r3, 3, "FireUp") for _ in range(n_choices)]
    r4 = random.Random(seed)
    rr = [r4.randrange(7) for _ in range(12)]

    # pround 对照样本：GDScript 的半值取偶实现 vs Python 的 round(x, nd)
    xs = [0.5, 1.5, 2.5, 3.5, -0.5, -1.5, 2.675, 2.665, 0.125, 0.135,
          43.86150000000001, 21.772336336660626, 9.966458268882315,
          1234.565, 0.0, 1.0, 4991135.6102341395]
    rc = [[x, nd, round(x, nd)] for x in xs for nd in (0, 1, 2, 3)]
    return dict(random=rnd, offers=[sorted(x) for x in ch],
                offers_forced=[sorted(x) for x in chf],
                randrange7=rr, round_cases=rc)


def gd_float(v):
    """🔴 必须用 `%.17e`（= **18 位有效数字**），不能用 `%.17g`（17 位）。

    实测（切片2 联调）：Godot 的浮点**字面量解析**在部分 17 位十进制上差 1ULP：
        Python float('186.26806084384762') = 0x1.74893f455b53dp+7
        Godot  字面量 186.26806084384762   = 0x1.74893f455b53cp+7   ← 低 1ULP
    而写成 18 位有效数字（1.86268060843847620e+02）就能正确解析。
    推测：Godot 内部解析用了近似算法（很可能复用了那条 1ULP 偏的 pow(10,n)）。

    这不是"差不多就行"——金标本期望值若自带 1ULP 误差，逐位判等就会假失败，
    掩盖真正的分歧。所以这里统一写成 18 位有效数字。
    """
    if v is None:
        return "null"
    return "%.17e" % float(v)


def main():
    out = {"runs": {}, "stats": {}, "mc": {}, "rng": rng_reference()}

    for label, kr_mode, rule in (("tier", "tier", "substantial"),
                                 ("flat045", "flat", "substantial")):
        st = {}
        for path in ("A", "B"):
            cfg = cfg_for(path, kr_mode=kr_mode, rule=rule)
            rows, player = run_rows(path, cfg, 20)
            dps, info = v6.compute_dps_v6(player, cfg, sv.GEO6)
            st[path] = dict(rows=[row_dump(r) for r in rows],
                            s=v6.summarize(rows), dps=dps)
        cross, lead, flips, fa, fb = v6.cross_lead(st["A"]["rows"], st["B"]["rows"])
        w20A = st["A"]["s"]["w20"] or 0.0
        w20B = st["B"]["s"]["w20"] or 0.0
        ba = round(w20B / w20A, 3) if w20A else 0.0
        out["runs"][label] = st
        out["stats"][label] = dict(
            toA=st["A"]["s"]["takeoff"], toB=st["B"]["s"]["takeoff"],
            w20A=round(w20A, 2), w20B=round(w20B, 2), ba=ba,
            leadA=lead["A"], leadB=lead["B"], flips=flips, firstA=fa, firstB=fb,
            hA=v6.stage_health(st["A"]["rows"]), hB=v6.stage_health(st["B"]["rows"]),
            cross=[[w, a, b, who] for w, a, b, who in cross],
        )
        print("[%s] A起飞W%s B起飞W%s W20 %.2f/%.2f B/A %.3f 交叉%d 领先%d/%d"
              % (label, st["A"]["s"]["takeoff"], st["B"]["s"]["takeoff"],
                 w20A, w20B, ba, flips, lead["A"], lead["B"]))

    # 蒙特卡洛（只跑定稿口径 tier/0.65）；前 3 局导全量 rows，前 25 局导起飞波
    for path in ("A", "B"):
        cfg = cfg_for(path, kr_mode="tier", rule="substantial")
        r = takeoff_rate_full(path, cfg, trace_runs=25)
        r["trace20"] = r["trace"][:25]
        out["mc"][path] = r
        print("[MC %s] rate=%.3f surv=%.3f med=%s  前3局起飞=%s"
              % (path, r["rate"], r["surv"], r["med"], r["trace"]))

    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("JSON ->", OUT_JSON)

    # ---------------- GDScript 常量文件 ----------------
    L = []
    L.append("class_name GoldenSlice2")
    L.append("extends RefCounted")
    L.append("##")
    L.append("## 切片2 金标本期望值 —— 由 tools/export_golden_slice2.py 从 Python 金标本实跑导出。")
    L.append("##   金标本：corebound_sim_v03.py（战斗/商店/主循环） + v06（判据统计） + v07（0.65 口径）")
    L.append("##")
    L.append("## ⚠️ 本文件是**生成物**，不要手改。改口径请改 tools/export_golden_slice2.py 后重跑。")
    L.append("## ⚠️ 这些是**未 round 的全精度真值**（CSV 里的值是 round 过的，不能直接当期望）。")
    L.append("##")
    L.append("")
    for label in ("tier", "flat045"):
        L.append("# ---- %s 决定性跑（rng=null）----" % label)
        for path in ("A", "B"):
            rows = out["runs"][label][path]["rows"]
            L.append("const ROWS_%s_%s: Array = [" % (label.upper(), path))
            for r in rows:
                L.append("\t{ \"w\": %d, \"n\": %d, \"hp_each\": %s, \"total_hp\": %s,"
                         % (r["w"], r["n"], gd_float(r["hp_each"]), gd_float(r["total_hp"])))
                L.append("\t  \"eff_dps\": %s, \"ratio\": %s, \"core_hp\": %s, \"income\": %s,"
                         % (gd_float(r["eff_dps"]), gd_float(r["ratio"]),
                            gd_float(r["core_hp"]), gd_float(r["income"])))
                L.append("\t  \"rerolls\": %d, \"cum_rerolls\": %d, \"towers\": %d, \"slots\": %d,"
                         % (r["rerolls"], r["cum_rerolls"], r["towers"], r["slots"]))
                L.append("\t  \"kills\": %d, \"leaked\": %d,"
                         % (r["kills"], r["leaked"]))
                L.append("\t  \"hp_each_r\": %s, \"total_hp_r\": %s,"
                         % (gd_float(r["hp_each_r"]), gd_float(r["total_hp_r"])))
                L.append("\t  \"eff_dps_r\": %s, \"ratio_r\": %s,"
                         % (gd_float(r["eff_dps_r"]), gd_float(r["ratio_r"])))
                L.append("\t  \"core_hp_r\": %s, \"income_r\": %s,"
                         % (gd_float(r["core_hp_r"]), gd_float(r["income_r"])))
                L.append("\t  \"build\": \"%s\" }," % r["build"])
            L.append("]")
        L.append("")

    for label in ("tier", "flat045"):
        s = out["stats"][label]
        L.append("const STATS_%s: Dictionary = {" % label.upper())
        L.append("\t\"toA\": %s, \"toB\": %s, \"w20A\": %s, \"w20B\": %s, \"ba\": %s,"
                 % (s["toA"] if s["toA"] is not None else -1,
                    s["toB"] if s["toB"] is not None else -1,
                    gd_float(s["w20A"]), gd_float(s["w20B"]), gd_float(s["ba"])))
        L.append("\t\"leadA\": %d, \"leadB\": %d, \"flips\": %d, \"firstA\": %d, \"firstB\": %d,"
                 % (s["leadA"], s["leadB"], s["flips"],
                    s["firstA"] or -1, s["firstB"] or -1))
        L.append("\t\"growA\": %s, \"growB\": %s, \"riseA\": %s, \"riseB\": %s,"
                 % (gd_float(s["hA"]["grow"]), gd_float(s["hB"]["grow"]),
                    str(bool(s["hA"]["rise"])).lower(), str(bool(s["hB"]["rise"])).lower()))
        L.append("\t\"survA\": %s, \"survB\": %s,"
                 % (str(bool(s["hA"]["survive"])).lower(), str(bool(s["hB"]["survive"])).lower()))
        L.append("\t\"w20A_raw\": %s, \"w20B_raw\": %s,"
                 % (gd_float(out["runs"][label]["A"]["dps"]),
                    gd_float(out["runs"][label]["B"]["dps"])))
        L.append("}")
        L.append("")

    s_tier = out["stats"]["tier"]
    L.append("# ---- tier 口径逐波领先表 [w, A_ratio, B_ratio, 领先方] ----")
    L.append("const CROSS_TIER: Array = [")
    for w, a, b, who in s_tier["cross"]:
        L.append("\t[%d, %s, %s, \"%s\"]," % (w, gd_float(a), gd_float(b), who))
    L.append("]")
    L.append("")

    L.append("const MC_TIER: Dictionary = {")
    for path in ("A", "B"):
        m = out["mc"][path]
        L.append("\t\"%s\": { \"rate\": %s, \"surv\": %s, \"n_takeoff\": %d, \"n_surv\": %d },"
                 % (path, gd_float(m["rate"]), gd_float(m["surv"]),
                    m["n_takeoff"], m["n_surv"]))
    L.append("}")
    L.append("")
    L.append("# ---- MC 前 25 局的起飞波（-1 = 未起飞/阵亡），用于定位发散点 ----")
    for path in ("A", "B"):
        L.append("const MC_TRACE_%s: Array = [" % path)
        L.append("\t" + ", ".join(str(x) for x in out["mc"][path]["trace20"]))
        L.append("]")
    L.append("")
    L.append("# ---- MC 指定局的完整 rows（rng 已消耗；逐位对齐用）----")
    L.append("#      run18 是 B 路径首个与 GDScript 分歧的局（A 前 25 局全对得上）")
    for path, idx in (("A", 0), ("B", 0), ("A", 17), ("B", 17)):
        rows = out["mc"][path]["trace_rows"][idx]
        L.append("const MC_RUN%d_%s: Array = [" % (idx + 1, path))
        for r in rows:
            L.append("\t{ \"w\": %d, \"n\": %d, \"hp_each\": %s, \"total_hp\": %s,"
                     % (r["w"], r["n"], gd_float(r["hp_each"]), gd_float(r["total_hp"])))
            L.append("\t  \"eff_dps\": %s, \"ratio\": %s, \"core_hp\": %s, \"income\": %s,"
                     % (gd_float(r["eff_dps"]), gd_float(r["ratio"]),
                        gd_float(r["core_hp"]), gd_float(r["income"])))
            L.append("\t  \"rerolls\": %d, \"cum_rerolls\": %d, \"towers\": %d, \"slots\": %d,"
                     % (r["rerolls"], r["cum_rerolls"], r["towers"], r["slots"]))
            L.append("\t  \"kills\": %d, \"leaked\": %d, \"build\": \"%s\" },"
                     % (r["kills"], r["leaked"], r["build"]))
        L.append("]")
    L.append("")

    L.append("const RNG_RANDOM: Array = [")
    L.append("\t" + ", ".join(gd_float(x) for x in out["rng"]["random"]))
    L.append("]")
    L.append("")
    L.append("const RNG_OFFERS: Array = [")
    for o in out["rng"]["offers"]:
        L.append("\t[%s]," % ", ".join('"%s"' % x for x in o))
    L.append("]")
    L.append("")
    L.append("# ---- draw_offers(rng, 3, force=\"FireUp\")：校验保底挤掉逻辑 ----")
    L.append("const RNG_OFFERS_FORCED: Array = [")
    for o in out["rng"]["offers_forced"]:
        L.append("\t[%s]," % ", ".join('"%s"' % x for x in o))
    L.append("]")
    L.append("")
    L.append("const RNG_RANDRANGE7: Array = [")
    L.append("\t" + ", ".join(str(x) for x in out["rng"]["randrange7"]))
    L.append("]")
    L.append("")
    L.append("# ---- pround 对照：[x, nd, Python round(x, nd)] ----")
    L.append("const ROUND_CASES: Array = [")
    for x, nd, v in out["rng"]["round_cases"]:
        L.append("\t[%s, %d, %s]," % (gd_float(x), nd, gd_float(v)))
    L.append("]")

    with open(OUT_GD, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("GD   ->", OUT_GD)


if __name__ == "__main__":
    main()
