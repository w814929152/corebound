# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.21：定稿基准上的霜序甜点重扫（Cannon=6.0 固定）**

================================================================================
它要回答的一个问题
================================================================================
v0.20（D-5 复跑）确认：塔基础 DPS 的定稿口径是 **Cannon 6 / Frost 4**，
而 v16/v19 的「霜序甜点 Frost 5→6」是在**遗留值 Frost=5.0 / Cannon=7.0** 上做的
→ 基准错了，数值结论必须回到 Frost=4.0 的起点重算。

本脚本在**正确基准**（Cannon 固定 6.0）上重扫：
  1. Frost DPS 从 4.0 起步，细扫找「霜序涨、混编不塌」的甜点窗口；
  2. 确认进场断崖（Frost 从「AI 不建」到「AI 建」的跃迁点）落在哪；
  3. 确认修过头悬崖（混编被 Frost 单核反噬的崩点）落在哪。

================================================================================
方法学
================================================================================
- Cannon 固定 6.0（D-5 定稿），只扫 Frost。
- 3 seed 均值，单 seed 是烟雾弹。
- 混编被淘汰红线 = 混编 A 率相对基线下降 > 3pp（v19 口径）。
================================================================================
用法
================================================================================
  python corebound_sim_v21_rescan.py selfcheck   # 遗留 7/5 时 = v14 逐位一致
  python corebound_sim_v21_rescan.py rescan 200  # 定稿基准扫 Frost 4.0~6.5
  python corebound_sim_v21_rescan.py bpath 200   # B 路径复核（定稿基准）
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
FROST_FINAL_BASE = 4.0     # D-5 定稿起点
CANNON_FINAL = 6.0         # D-5 定稿（固定，不扫）

# 扫描范围：从定稿起点 4.0 起到 6.5（覆盖可能的进场断崖与过载悬崖）
FROST_SCAN = [4.0, 4.25, 4.5, 4.75, 5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5]

# 遗留口径（selfcheck 用）
LEGACY = dict(cannon=7.0, frost=5.0)

SEEDS = [v8.SEED1, v8.SEED2, v8.SEED3]


def _apply_dps(cannon, frost):
    sv.TOWERS["Cannon"]["dps"] = cannon
    sv.TOWERS["Frost"]["dps"] = frost


# =============================================================================
# 1. 测量工具
# =============================================================================
def _mc(path, faction, kw, runs, seed):
    rng = random.Random(seed)
    cfg = v8.cfg_of(path)
    cfg.update(kw)
    cfg["max_actions"] = cfg.get("max_actions") or 12
    hits = 0
    to_list = []
    for _ in range(runs):
        rows, _, _ = v14.run_v14(path, cfg, faction, 20, geo=sv.GEO6, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            hits += 1
            to_list.append(tw)
    return hits / runs, to_list


def _mc_mean(path, faction, kw, runs):
    rates, tos = [], []
    for seed in SEEDS:
        r, to = _mc(path, faction, kw, runs, seed)
        rates.append(r)
        tos.extend(to)
    return statistics.mean(rates), statistics.stdev(rates) if len(rates) > 1 else 0.0, tos


def _det_build(path, faction):
    cfg = v8.cfg_of(path)
    cfg["wave_tag_on"] = False
    rows, p, st = v14.run_v14(path, cfg, faction, 20, geo=sv.GEO6, rng=None)
    return [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers], p.cards


# =============================================================================
# 2. 校验
# =============================================================================
def selfcheck():
    """遗留 7/5 时，v21 必须与 v14 逐位一致。"""
    _apply_dps(LEGACY["cannon"], LEGACY["frost"])
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r21, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        r14b, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        for x, y in zip(r21, r14b):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


# =============================================================================
# 3. 定稿基准重扫
# =============================================================================
def rescan(runs=200):
    print("=" * 104)
    print(f"v0.21 定稿基准重扫（{runs} 局/格 × 3 seed）—— Cannon 固定 6.0，扫 Frost 4.0~6.5")
    print("=" * 104)

    _apply_dps(CANNON_FINAL, FROST_FINAL_BASE)
    base_free = _mc_mean("A", "freelance", dict(), runs)[0]
    cinder_base = _mc_mean("A", "cinder", dict(), runs)[0]   # 目标追平值（熔炉池不含 Frost）

    print(f"{'Frost':>6} | {'霜序A率':>16} | {'混编A率':>16} | {'混编Δ':>8} | {'熔炉A率':>8} | 判定")
    print("-" * 104)

    for dps in FROST_SCAN:
        _apply_dps(CANNON_FINAL, float(dps))
        rime_mean, rime_sd, _ = _mc_mean("A", "rime", dict(), runs)
        free_mean, free_sd, _ = _mc_mean("A", "freelance", dict(), runs)
        free_delta = free_mean - base_free
        if free_delta < -0.03:
            verdict = "🔴 混编塌"
        elif rime_mean >= cinder_base - 0.03:
            verdict = "🟢 追平熔炉"
        else:
            verdict = "🟡 甜点内"
        print(f"{dps:>6.2f} | {rime_mean:.3f}±{rime_sd:.3f} | "
              f"{free_mean:.3f}±{free_sd:.3f} | {free_delta:+.3f} | "
              f"{cinder_base:.3f}  | {verdict}")

    # 决定性终局：看 Frost 在哪个 DPS 起真正「进场」
    print()
    print("决定性终局（霜序 A）：Frost 是否进场？")
    for dps in (4.0, 4.75, 5.25, 5.75, 6.5):
        _apply_dps(CANNON_FINAL, float(dps))
        towers, cards = _det_build("A", "rime")
        frost_h = sum(t[2] for t in towers if t[1] == "Frost")
        arrow_h = sum(t[2] for t in towers if t[1] == "Arrow")
        cannon_h = sum(t[2] for t in towers if t[1] == "Cannon")
        mark = "✅进场" if frost_h > 0 else "❌零冰系"
        print(f"  Frost={dps:>4.2f}: Arrow {arrow_h:>3} / Cannon {cannon_h:>3} / "
              f"Frost {frost_h:>3}  {mark}   卡组={sorted(cards)}")

    _apply_dps(CANNON_FINAL, FROST_FINAL_BASE)
    print()
    print(f"混编基线（Cannon=6, Frost=4）= {base_free:.3f}，熔炉 A 基准 = {cinder_base:.3f}")


# =============================================================================
# 4. B 路径复核
# =============================================================================
def bpath(runs=200):
    print("=" * 96)
    print(f"v0.21 B 路径复核（{runs} 局/格 × 3 seed）—— 定稿基准下霜序 B 是否敏感")
    print("=" * 96)
    print(f"{'Frost':>6} | {'霜序B率':>16} | {'混编B率':>16} | {'熔炉B率':>16}")
    print("-" * 96)
    for dps in (4.0, 4.75, 5.25, 6.0):
        _apply_dps(CANNON_FINAL, float(dps))
        rb, rbs, _ = _mc_mean("B", "rime", dict(), runs)
        fb, fbs, _ = _mc_mean("B", "freelance", dict(), runs)
        cb, cbs, _ = _mc_mean("B", "cinder", dict(), runs)
        print(f"{dps:>6.2f} | {rb:.3f}±{rbs:.3f} | {fb:.3f}±{fbs:.3f} | {cb:.3f}±{cbs:.3f}")
    _apply_dps(CANNON_FINAL, FROST_FINAL_BASE)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 遗留 7/5 时 v21 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "rescan":
        rescan(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    elif mode == "bpath":
        bpath(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
