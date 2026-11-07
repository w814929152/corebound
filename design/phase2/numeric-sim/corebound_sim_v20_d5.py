# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.20：D-5 塔基础 DPS 口径复跑（Cannon 7/5 → 6/4）**

================================================================================
它要回答的一个问题
================================================================================
damage-pipeline.md §9 D-5 裁定：塔基础 DPS 的权威定稿是 **Cannon 6 / Frost 4**
（card-system §7.3 与 core-defense §8.1 两份设计文档一致），而 sim 引擎的
`TOWERS` 用 **Cannon 7.0 / Frost 5.0**（「早期遗留」，v0.4 全套标定跑的是 7/5）。

D-5 明确标注「🟡 需复跑」：把 7/5 改成 6/4 后，要确认 **A 起飞率仍 ≥ 60%**，
且 **B/A 仍 < 1**（单核仍是后期 carry）。

本脚本就是做这个复跑：在「混编」（金标本基线，7 张卡全开）路径上，把 TOWERS
切到 6/4，复跑 A/B 两条路径的金标本指标，判定 D-5 口径是否安全。

================================================================================
方法学（沿用 v10/v14 教训）
================================================================================
- 3 seed 均值，单 seed 是烟雾弹。
- 金标本 = 混编路径（freelance = 全部 7 张卡），不是阵营锁池。
- 改 TOWERS 是全局改动，同时看 A 路径（Cannon 主核）和 B 路径（Arrow 主核）。
================================================================================
用法
================================================================================
  python corebound_sim_v20_d5.py selfcheck   # 7/5 时 = v14 逐位一致
  python corebound_sim_v20_d5.py rerun 300   # 切 6/4 后复跑金标本 A/B
"""

from __future__ import annotations

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6  # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v14_factionlock as v14

# =============================================================================
# 0. 常量
# =============================================================================
# D-5 定稿口径（card-system §7.3 / core-defense §8.1）
FINAL_TOWER_DPS = {"Cannon": 6.0, "Frost": 4.0}
# sim 当前（早期遗留）
LEGACY_TOWER_DPS = {"Cannon": 7.0, "Frost": 5.0}

SEEDS = [v8.SEED1, v8.SEED2, v8.SEED3]


def _set_tower_dps(cannon, frost):
    sv.TOWERS["Cannon"]["dps"] = cannon
    sv.TOWERS["Frost"]["dps"] = frost


def _apply_dps(mapping):
    """按 {'Cannon': x, 'Frost': y} 映射设 DPS。"""
    _set_tower_dps(mapping["Cannon"], mapping["Frost"])


# =============================================================================
# 1. 测量工具（混编金标本基线）
# =============================================================================
def _mc_mix(path, kw, runs, seed):
    """混编（freelance）路径的 MC：起飞率 + 中位起飞波次。"""
    rng = random.Random(seed)
    cfg = v8.cfg_of(path)
    cfg.update(kw)
    cfg["max_actions"] = cfg.get("max_actions") or 12
    hits = 0
    to_list = []
    for _ in range(runs):
        rows, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            hits += 1
            to_list.append(tw)
    return hits / runs, to_list


def _mc_mean(path, kw, runs):
    rates, tos = [], []
    for seed in SEEDS:
        r, to = _mc_mix(path, kw, runs, seed)
        rates.append(r)
        tos.extend(to)
    return statistics.mean(rates), statistics.stdev(rates) if len(rates) > 1 else 0.0, tos


def _final_dps(path):
    """决定性终局（rng=None）的 W20 倍数（DPS/HP 比）。"""
    cfg = v8.cfg_of(path)
    cfg["wave_tag_on"] = False
    rows, p, st = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
    if not rows:
        return None
    last = rows[-1]
    return last["ratio"], last["w"], last["eff_dps"]


# =============================================================================
# 2. 校验
# =============================================================================
def selfcheck():
    """7/5（遗留值）时，v20 必须与 v14 逐位一致。"""
    _apply_dps(LEGACY_TOWER_DPS)
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r20, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        r14b, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        for x, y in zip(r20, r14b):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


# =============================================================================
# 3. D-5 复跑
# =============================================================================
def rerun(runs=300):
    print("=" * 96)
    print(f"v0.20 D-5 复跑（{runs} 局/格 × 3 seed）—— Cannon/Frost 基础 DPS 7/5 → 6/4")
    print("=" * 96)

    # 基线（遗留 7/5）
    _apply_dps(LEGACY_TOWER_DPS)
    a_rate_l, a_sd_l, a_to_l = _mc_mean("A", dict(), runs)
    b_rate_l, b_sd_l, b_to_l = _mc_mean("B", dict(), runs)
    a_final_l = _final_dps("A")
    b_final_l = _final_dps("B")
    ba_l = (b_final_l[0] / a_final_l[0]) if a_final_l and b_final_l and a_final_l[0] > 0 else None

    # 定稿 6/4
    _apply_dps(FINAL_TOWER_DPS)
    a_rate_f, a_sd_f, a_to_f = _mc_mean("A", dict(), runs)
    b_rate_f, b_sd_f, b_to_f = _mc_mean("B", dict(), runs)
    a_final_f = _final_dps("A")
    b_final_f = _final_dps("B")
    ba_f = (b_final_f[0] / a_final_f[0]) if a_final_f and b_final_f and a_final_f[0] > 0 else None

    print()
    print("| 口径 | A起飞率 | B起飞率 | A中位起飞 | B中位起飞 | A W20倍数 | B W20倍数 | B/A |")
    print("|------|---------|---------|-----------|-----------|-----------|-----------|-----|")
    print(f"| 7/5（遗留） | {a_rate_l:.3f}±{a_sd_l:.3f} | {b_rate_l:.3f}±{b_sd_l:.3f} | "
          f"{statistics.median(a_to_l) if a_to_l else '—':>9} | {statistics.median(b_to_l) if b_to_l else '—':>9} | "
          f"{a_final_l[0]:.2f} | {b_final_l[0]:.2f} | {ba_l:.3f} |")
    print(f"| 6/4（定稿） | {a_rate_f:.3f}±{a_sd_f:.3f} | {b_rate_f:.3f}±{b_sd_f:.3f} | "
          f"{statistics.median(a_to_f) if a_to_f else '—':>9} | {statistics.median(b_to_f) if b_to_f else '—':>9} | "
          f"{a_final_f[0]:.2f} | {b_final_f[0]:.2f} | {ba_f:.3f} |")

    print()
    print("=" * 96)
    print("D-5 判决：")
    # 判据 1：A 起飞率 ≥ 60%
    a_ok = a_rate_f >= 0.60
    print(f"  ① A 起飞率 ≥ 60%：{a_rate_f:.3f} → {'✅ 通过' if a_ok else '🔴 破线（需重标定）'}")
    # 判据 2：B/A < 1（单核仍是后期 carry）
    ba_ok = ba_f is not None and ba_f < 1.0
    print(f"  ② B/A < 1：{ba_f:.3f} → {'✅ 通过（单核仍后期 carry）' if ba_ok else '🔴 违反概念 §2.4.5'}")

    # 还原
    _apply_dps(LEGACY_TOWER_DPS)

    if a_ok and ba_ok:
        print("\n✅ D-5 口径安全：6/4 可落地，金标本需按新口径更新指标。")
    else:
        print("\n🔴 D-5 口径破线：6/4 落地前需重标定 hp_growth 等，不能直接改。")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 7/5 时 v20 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "rerun":
        rerun(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
