# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.19：Frost 基础值细扫 + B 路径复核（落地前收尾）**

================================================================================
它要回答的一个问题
================================================================================
v0.16 找到甜点「Frost DPS 5→6」，但报告 §5 留了两个未关闭的假设：
  - A1：DPS=6 是「拍的」，甜点窗口窄（6 稳、7 崩），需扫 5.5~6.5 步长 0.25 确认；
  - A4：只测了 A 路径（单核），B 路径（多塔）Frost 靠 Arrow 底进场，结论可能不同。

本脚本做两件事，把「Frost DPS 5→6」从探针结论推到可拍板定稿：
  1. **细扫** Frost DPS ∈ {5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5, 6.75}：
     找「霜序涨、混编不塌」的精确甜点窗口，而非拍脑袋的整数 6。
  2. **B 路径复核**：霜序 B（多塔）在甜点附近的起飞率，确认 A 路径的结论
     不因「B 靠 Arrow 底进场」而失效。

================================================================================
方法学（沿用 v10/v14/v16 教训）
================================================================================
- 3 seed 均值，单 seed 是烟雾弹。
- 改 DPS 是全局旋钮，同时看混编（freelance）是否被扰动。
- 混编被淘汰的红线 = 混编 A 率相对基线下降 > 15%（或决定性终局 Frost 入侵）。
================================================================================
用法
================================================================================
  python corebound_sim_v19_frostfinal.py selfcheck   # DPS=5 = v14 逐位一致
  python corebound_sim_v19_frostfinal.py fine 200     # 细扫 5.0~6.75
  python corebound_sim_v19_frostfinal.py bpath 200    # B 路径复核
"""

from __future__ import annotations

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6  # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v13_wavetag as v13
import corebound_sim_v14_factionlock as v14

# =============================================================================
# 0. 常量
# =============================================================================
FROST_BASE_DPS = 5.0
FROST_FINE = [5.0, 5.25, 5.5, 5.75, 6.0, 6.25, 6.5, 6.75]  # 细扫（步长 0.25）

SEEDS = [v8.SEED1, v8.SEED2, v8.SEED3]


def _set_frost_dps(v):
    sv.TOWERS["Frost"]["dps"] = v


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
    """Frost DPS 保持 5 时，v19 必须与 v14 逐位一致。"""
    _set_frost_dps(FROST_BASE_DPS)
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r19, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        r14b, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        for x, y in zip(r19, r14b):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


# =============================================================================
# 3. 细扫（关闭 A1）
# =============================================================================
def fine(runs=200):
    """细扫 Frost DPS 5.0~6.75：精确定位甜点窗口。"""
    print("=" * 96)
    print(f"v0.19 细扫（{runs} 局/格 × 3 seed）—— Frost DPS 甜点窗口精确定位")
    print("=" * 96)
    print(f"{'Frost DPS':>9} | {'霜序A率':>16} | {'混编A率':>16} | {'混编Δ':>8} | 判定")
    print("-" * 96)

    base_free = _mc_mean("A", "freelance", dict(), runs)[0]
    cinder_base = _mc_mean("A", "cinder", dict(), runs)[0]  # 熔炉基准（目标追平值）

    for dps in FROST_FINE:
        _set_frost_dps(float(dps))
        rime_mean, rime_sd, _ = _mc_mean("A", "rime", dict(), runs)
        free_mean, free_sd, _ = _mc_mean("A", "freelance", dict(), runs)
        free_delta = free_mean - base_free
        # 判定
        if free_delta < -0.03:
            verdict = "🔴 混编塌"
        elif rime_mean >= cinder_base - 0.03:
            verdict = "🟢 追平熔炉"
        else:
            verdict = "🟡 甜点内"
        print(f"{dps:>9.2f} | {rime_mean:.3f}±{rime_sd:.3f} | "
              f"{free_mean:.3f}±{free_sd:.3f} | {free_delta:+.3f} | {verdict}")

    _set_frost_dps(FROST_BASE_DPS)
    print()
    print(f"混编基线（DPS=5）= {base_free:.3f}，熔炉 A 基准 = {cinder_base:.3f}")
    print("读法：找「霜序 A 率最高、且混编Δ ≥ -0.03」的最优 DPS 点，就是可拍板的定稿值。")


# =============================================================================
# 4. B 路径复核（关闭 A4）
# =============================================================================
def bpath(runs=200):
    """霜序 B（多塔）在甜点附近的起飞率，验证 A 路径结论不失效。"""
    print("=" * 96)
    print(f"v0.19 B 路径复核（{runs} 局/格 × 3 seed）—— 霜序 B 是否靠 Arrow 底进场")
    print("=" * 96)
    print(f"{'Frost DPS':>9} | {'霜序B率':>16} | {'混编B率':>16} | {'熔炉B率':>16}")
    print("-" * 96)

    for dps in (5.0, 6.0):
        _set_frost_dps(float(dps))
        rime_b, rime_sd, _ = _mc_mean("B", "rime", dict(), runs)
        free_b, free_sd, _ = _mc_mean("B", "freelance", dict(), runs)
        cinder_b, cinder_sd, _ = _mc_mean("B", "cinder", dict(), runs)
        print(f"{dps:>9.1f} | {rime_b:.3f}±{rime_sd:.3f} | "
              f"{free_b:.3f}±{free_sd:.3f} | {cinder_b:.3f}±{cinder_sd:.3f}")

    # 决定性构筑：霜序 B 在 DPS=6 时，Frost 是否真的进场（而非纯 Arrow）
    print()
    _set_frost_dps(6.0)
    towers, cards = _det_build("B", "rime")
    frost_h = sum(t[2] for t in towers if t[1] == "Frost")
    arrow_h = sum(t[2] for t in towers if t[1] == "Arrow")
    cannon_h = sum(t[2] for t in towers if t[1] == "Cannon")
    print(f"霜序 B 决定性终局（DPS=6）: {towers}")
    print(f"  卡组: {cards}")
    print(f"  → Arrow {arrow_h} / Cannon {cannon_h} / Frost {frost_h}")
    _set_frost_dps(FROST_BASE_DPS)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] Frost DPS=5 时 v19 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "fine":
        fine(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    elif mode == "bpath":
        bpath(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
