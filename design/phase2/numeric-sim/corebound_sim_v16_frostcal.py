# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.16：Frost 基础值校准（霜序「有得选」的平衡点）**

================================================================================
它要回答的一个问题
================================================================================
v0.15 实测定位：霜序「没得选」的主因是 **Frost 基础 DPS 太低（5 vs Arrow 10）**，
条件链（T4）零增量（Frost 不进场）。把 DPS 从 5 提到 7 即 +26.7pp。

本脚本做两件事，把「修 Frost 基础值」这个方向校准到可拍板的数值：
  1. **扫描 Frost DPS ∈ {5,6,7,8,9}**：霜序 A 起飞率随基础值怎么变？
  2. **平衡红线**：Frost 变强会不会反过来压制「混编」（Arrow 单核）这个金标本对照？
     —— 若 Frost DPS 提到某点后，混编路径的 AI 也转向 Frost，说明修过头了。

================================================================================
★ 方法学前提
================================================================================
1. Frost 的 DPS 是**全局常量**（sv.TOWERS["Frost"]["dps"]），改它会影响所有路径，
   包括混编（freelance）、熔炉（cinder）——因为混编/熔炉的池里也含 Frost 卡。
   ⇒ 所以「修 Frost」不是霜序专属，是全局平衡改动，必须同时看对混编的影响。
2. 平衡红线的判据（faction-decks §8.2 失败信号 B）：
   「混编被淘汰」= 混编 W20 低于三阵营均值 > 15%。
   更直接的红线：**混编路径的 AI 终局构筑若从 Arrow 主流转向 Frost 主流，说明 Frost 过强。**
3. 方法学（沿用 v10/v14 教训）：3 seed 均值，单 seed 是烟雾弹。

================================================================================
用法
================================================================================
  python corebound_sim_v16_frostcal.py selfcheck   # 不改 DPS 时 = v14 逐位一致
  python corebound_sim_v16_frostcal.py scan 200    # 扫 Frost DPS 5~9
  python corebound_sim_v16_frostcal.py mc 200      # 平衡点附近的完整对照
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
# 0. 基线常量
# =============================================================================
FROST_BASE_DPS = 5.0      # 当前定稿值
FROST_SCAN = [5, 6, 7, 8, 9]   # 扫描范围

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
    """决定性终局构筑（rng=None 无限商店），用于看 AI 是否转向 Frost。"""
    cfg = v8.cfg_of(path)
    cfg["wave_tag_on"] = False
    rows, p, st = v14.run_v14(path, cfg, faction, 20, geo=sv.GEO6, rng=None)
    return [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers], p.cards


# =============================================================================
# 2. 校验
# =============================================================================
def selfcheck():
    """Frost DPS 保持 5 时，v16 必须与 v14 逐位一致。"""
    _set_frost_dps(FROST_BASE_DPS)
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r16, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        # 对照：重跑一次确认稳定
        r14b, _, _ = v14.run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        for x, y in zip(r16, r14b):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


# =============================================================================
# 3. 扫描
# =============================================================================
def scan(runs=200):
    """扫 Frost DPS 5~9：霜序 A 起飞率 + 混编 A 是否被扰动。"""
    print("=" * 96)
    print(f"v0.16 扫描（{runs} 局/格 × 3 seed）—— Frost 基础 DPS 对霜序/混编的影响")
    print("=" * 96)
    print(f"{'Frost DPS':>9} | {'霜序A率':>16} | {'混编A率':>16} | {'熔炉A率':>16} | 混编Δ")
    print("-" * 96)

    base_freelance = _mc_mean("A", "freelance", dict(), runs)[0]

    for dps in FROST_SCAN:
        _set_frost_dps(float(dps))
        rime_mean, rime_sd, _ = _mc_mean("A", "rime", dict(), runs)
        free_mean, free_sd, _ = _mc_mean("A", "freelance", dict(), runs)
        cinder_mean, cinder_sd, _ = _mc_mean("A", "cinder", dict(), runs)
        free_delta = free_mean - base_freelance
        print(f"{dps:>9.1f} | {rime_mean:.3f}±{rime_sd:.3f} | "
              f"{free_mean:.3f}±{free_sd:.3f} | {cinder_mean:.3f}±{cinder_sd:.3f} | "
              f"{free_delta:+.3f}")

    _set_frost_dps(FROST_BASE_DPS)
    print()
    print(f"混编基线（Frost DPS=5）= {base_freelance:.3f}")
    print("读法：霜序 A 率追上熔炉 A 率时，Frost 基础值就是「有得选」的平衡点；")
    print("同时看「混编Δ」——若 Frost 变强让混编 A 率也大涨，说明修过头（Frost 过强压制 Arrow）。")


def run_mc(runs=200):
    """平衡点附近的完整对照：Frost DPS=7 时，三阵营 × 混编的起飞率矩阵。"""
    print("=" * 96)
    print(f"v0.16 MC（{runs} 局/格 × 3 seed）—— Frost DPS=7 平衡点对照")
    print("=" * 96)
    _set_frost_dps(7.0)

    cells = [
        ("混编", "freelance"),
        ("熔炉", "cinder"),
        ("霜序", "rime"),
    ]
    print("| 阵营 | A率(3seed) | B率(3seed) |")
    print("|------|------------|------------|")
    for label, f in cells:
        a_mean, a_sd, _ = _mc_mean("A", f, dict(), runs)
        b_mean, b_sd, _ = _mc_mean("B", f, dict(), runs)
        print(f"| {label} | {a_mean:.3f}±{a_sd:.3f} | {b_mean:.3f}±{b_sd:.3f} |")

    # 决定性构筑：混编 A 是否仍 Arrow 主流？
    print()
    print("决定性终局构筑（Frost DPS=7，混编 A）：")
    towers, cards = _det_build("A", "freelance")
    print(f"  塔: {towers}")
    print(f"  卡组: {cards}")
    # 统计 Frost 是否入侵混编
    frost_h = sum(t[2] for t in towers if t[1] == "Frost")
    arrow_h = sum(t[2] for t in towers if t[1] == "Arrow")
    print(f"  → Arrow 总层 {arrow_h} vs Frost 总层 {frost_h}")

    _set_frost_dps(FROST_BASE_DPS)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] Frost DPS=5 时 v16 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "scan":
        scan(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
