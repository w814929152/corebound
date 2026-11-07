# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.14：P5 阵营锁定（开局选阵营 + 池过滤）**

================================================================================
它要回答的一个问题
================================================================================
v0.13（wave_tag）已经证明：敌人构成能当阵营的定价器（三行全绿），但**差一块**——
AI 无阵营意识，wave_tag 只能给固定路线一个全局税/补贴，不能让它「切换阵营」。

faction-decks.md §5.5 的结论：要先补 **P5 阵营锁定**（开局选阵营 + 池过滤），
让「阵营」成为真实的前置决策，而不是 AI 贪心的副产品。P4（构成感知 AI）是第二步。

本脚本做 P5 的最小实现：
  - 定义「阵营 → 卡池」的映射（复用现有 7 张卡，零新卡）；
  - 开局锁定一个阵营，商店池过滤为「中立 + 本阵营」；
  - 验证：锁池后，AI 在自己阵营擅长的 wave_tag 下是否相对混编有分化。

================================================================================
★ 方法学前提（必须先讲清）
================================================================================
1. sim 的卡池只有 7 张（Arrow/Cannon/Frost + FireUp/FrostUp + ScrapUp/RerollD），
   faction-decks §3 的 T1–T6/L1–L4 细分卡在 sim 里**不存在**。所以 P5 的阵营映射是
   「粗到只有火/冰/中立三族」的最小抽象，不是 16 张库的完整实现。
2. 池过滤用 monkey-patch 打 `sv.draw_offers`，**不改 v03–v13 任何原文件**。
   锁「混编」池（= 全开 7 张）时必须与 v13 逐位一致 —— 这是守住金标本的唯一方式。
3. A/B 是两条**策略路径**（A=单核火、B=多塔分散），阵营是**正交的前置选择**。
   本脚本把「阵营锁池」叠加在 A/B 路径之上：锁熔炉 → 池里只有火+中立；
   锁霜序 → 池里只有冰+中立。验证「锁池」是否让对应路径在对应波构成下更稳。

================================================================================
用法
================================================================================
  python corebound_sim_v14_factionlock.py selfcheck   # 锁混编池 = v13 逐位一致
  python corebound_sim_v14_factionlock.py pools       # 打印各阵营锁池后的卡池
  python corebound_sim_v14_factionlock.py mc 300      # 阵营 × wave_tag 矩阵 MC
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

# =============================================================================
# 0. 阵营 → 卡池映射（复用现有 7 张卡，零新卡）
# =============================================================================
# 中立卡 = 通用卡（初始塔 Arrow + 两张经济卡）。
# 熔炉 = 火系（Cannon + FireUp），霜序 = 冰系（Frost + FrostUp）。
# 枢网在 sim 里无专属卡（Arrow 是中立/初始塔），P5 先只做熔炉 + 霜序 + 混编，
# 这正是 faction-decks.md §10 Q-F1 的建议：「先做 2 个，都是零新卡」。

NEUTRAL = {"Arrow", "ScrapUp", "RerollD"}

FACTION_POOLS = {
    # name         专属卡              说明
    "cinder":   {"Cannon", "FireUp"},   # 熔炉（火/溅射）
    "rime":     {"Frost", "FrostUp"},   # 霜序（冰/减速）
    "freelance": None,                  # 混编（全开 7 张 = 金标本）
}

FACTION_LABEL = {
    "cinder": "熔炉", "rime": "霜序", "freelance": "混编",
}


def pool_of(faction):
    """返回某阵营锁池后的可见卡集合。freelance = None（全开）。"""
    if faction == "freelance":
        return None
    return NEUTRAL | FACTION_POOLS[faction]


# =============================================================================
# 1. 池过滤：monkey-patch sv.draw_offers + sv.ALLOWED（不碰原文件）
# =============================================================================
# 关键：阵营锁池必须**同时**约束两处，否则 AI 会「想买抽不到」死锁：
#   ① draw_offers —— 商店里能**抽到**什么卡；
#   ② ALLOWED     —— AI 能**考虑**买什么卡。
# 若只过滤 ① 不过滤 ②，AI 会反复想买池里不存在的卡（白白消耗动作预算）。
# 模块级「当前锁池」。锁池时 draw_offers 只从池内抽卡；None = 全开（金标本）。
_ACTIVE_POOL = None
_ALLOWED_ORIG = {p: set(sv.ALLOWED[p]) for p in sv.ALLOWED}


def _draw_offers_pooled(rng, k=3, force=None):
    if _ACTIVE_POOL is None:
        return _draw_offers_orig(rng, k, force)
    names = [n for n in _CARD_NAMES_ORIG if n in _ACTIVE_POOL]
    weights = [_WEIGHTS_ORIG[n] for n in names]
    s = set(rng.choices(names, weights=weights, k=k))
    if force:
        if force in _ACTIVE_POOL:
            s.add(force)
            while len(s) > k:
                s.discard(rng.choice(sorted(s - {force})))
        # force 不在池内 → 不发保底（阵营池本来就小，pity 命中率已上升）
    return s


_CARD_NAMES_ORIG = list(sv._CARD_NAMES)
_WEIGHTS_ORIG = dict(sv.WEIGHTS)
_draw_offers_orig = sv.draw_offers
sv.draw_offers = _draw_offers_pooled


def set_faction_pool(faction):
    """切换全局锁池（None / "freelance" = 混编/全开）。同时过滤 ALLOWED。"""
    global _ACTIVE_POOL
    if faction is None or faction == "freelance":
        _ACTIVE_POOL = None
        for p in _ALLOWED_ORIG:
            sv.ALLOWED[p] = set(_ALLOWED_ORIG[p])
    else:
        _ACTIVE_POOL = pool_of(faction)
        # 阵营锁池 → AI 的可用卡 = 池内卡（替换 A/B 路径原有的 ALLOWED）
        for p in sv.ALLOWED:
            sv.ALLOWED[p] = set(_ACTIVE_POOL)


# =============================================================================
# 2. 主循环（复用 v13 的 run_v13，只加锁池）
# =============================================================================
def run_v14(path, cfg, faction, max_wave=20, geo=None, rng=None):
    """在 v13 之上叠加「阵营锁池」。锁 freelancer 时与 v13 逐位一致。"""
    set_faction_pool(faction)
    try:
        return v13.run_v13(path, cfg, max_wave, geo=geo, rng=rng)
    finally:
        set_faction_pool(None)


# =============================================================================
# 3. 校验与实验
# =============================================================================
def selfcheck():
    """锁「混编」池（全开）时，v14 必须与 v13 逐位一致。"""
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r14, _, _ = run_v14(path, cfg, "freelance", 20, geo=sv.GEO6, rng=None)
        r13, _, _ = v13.run_v13(path, cfg, 20, geo=sv.GEO6, rng=None)
        if len(r14) != len(r13):
            return float("inf")
        for x, y in zip(r14, r13):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def pool_scan():
    """打印各阵营锁池后的可见卡集合，验证过滤正确。"""
    print("=" * 96)
    print("P5 · 阵营锁池一览（复用现有 7 张卡，零新卡）")
    print("=" * 96)
    print(f"{'阵营':<12} {'可见卡':<40} {'张数'}")
    print("-" * 96)
    for f in FACTION_POOLS:
        p = pool_of(f)
        if p is None:
            cards = "全开 7 张（金标本）"
            n = len(sv.WEIGHTS)
        else:
            cards = ", ".join(sorted(p))
            n = len(p)
        print(f"{FACTION_LABEL[f]:<12} {cards:<40} {n}")
    print()
    print("注：中立卡 = Arrow（初始塔）+ ScrapUp/RerollD（经济）。")
    print("枢网无 sim 专属卡（Arrow 是中立初始塔），P5 先只做熔炉 + 霜序 + 混编（Q-F1）。")


def run_mc(runs=300, seed=None):
    """MC：阵营锁池 × wave_tag 开/关 的起飞率矩阵（多 seed 均值）。

    方法学（沿用 v10/v12/v13 的教训）：单 seed 对照不是 A/B，是换轨迹。
    本函数用 3 个 seed 取均值，避免「锁池改变 rng 消耗次数 → 单 seed 假信号」。
    """
    seeds = [v8.SEED1, v8.SEED2, v8.SEED3]

    factions = ["freelance", "cinder", "rime"]
    tag_modes = [("no-tag", dict(wave_tag_on=False)),
                 ("wavetag", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()))]

    print(f"P5 MC（{runs} 局/格 × {len(seeds)} seed）—— 阵营锁池 × wave_tag 对起飞率的影响")
    print("=" * 96)
    print("| 阵营    | tag       | A率(3seed) | B率(3seed) | A中位起飞 | B中位起飞 |")
    print("|---------|-----------|------------|------------|-----------|-----------|")
    for f in factions:
        for tname, kw in tag_modes:
            a_rates, b_rates = [], []
            a_to_all, b_to_all = [], []
            for path in ("A", "B"):
                rates, to_all = [], []
                for seed in seeds:
                    rng = random.Random(seed)
                    cfg = v8.cfg_of(path)
                    cfg.update(kw)
                    cfg["max_actions"] = cfg.get("max_actions") or 12
                    hits = 0
                    to_list = []
                    for _ in range(runs):
                        rows, _, _ = run_v14(path, cfg, f, 20, geo=sv.GEO6, rng=rng)
                        alive = bool(rows) and rows[-1]["core_hp"] > 0
                        tw = sv.takeoff_wave(rows)
                        if alive and tw is not None:
                            hits += 1
                            to_list.append(tw)
                    rates.append(hits / runs)
                    to_all.extend(to_list)
                if path == "A":
                    a_rates, a_to_all = rates, to_all
                else:
                    b_rates, b_to_all = rates, to_all
            a_mean = statistics.mean(a_rates)
            b_mean = statistics.mean(b_rates)
            a_sd = statistics.stdev(a_rates) if len(a_rates) > 1 else 0.0
            b_sd = statistics.stdev(b_rates) if len(b_rates) > 1 else 0.0
            print(f"| {FACTION_LABEL[f]:<7} | {tname:<9} | "
                  f"{a_mean:.3f}±{a_sd:.3f} | {b_mean:.3f}±{b_sd:.3f} | "
                  f"{statistics.median(a_to_all) if a_to_all else '—':>9} | "
                  f"{statistics.median(b_to_all) if b_to_all else '—':>9} |")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 锁混编池时 v14 vs v13 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "pools":
        pool_scan()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
