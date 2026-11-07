# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.18：P4 构成感知 AI（让 AI 估卡时折入本波构成）**

================================================================================
它要回答的问题
================================================================================
v17（keyword P0）证伪了一个关键前提：贪心 AI 会「折叠时机维度」，任何叠上去的
词条都零增量。技术根因被精确定位——**AI 的估值函数（action_value → dps_only_v8）
里根本没有「本波构成（wave_tag）」这个输入**，所以 AI 是「盲买」的：
它不知道当前是 Swarm（该堆 Cannon 溅射）还是 Armor（该转 Frost 减速）。

faction-decks.md §5.5 早就点名了这个缺口：「AI 无阵营意识——贪心 + 固定权重，
只会算单卡 ΔDPS/价格，没有『这一局押哪个阵营』的全局概念」。P4 就是补它。

本脚本做 P4 的最小实现：
  给 AI 的估值函数加「构成感知」—— 买卡时用带构成调制的 DPS（v13._eff_dps）
  替代裸 DPS（dps_only_v8），让 AI 在 Swarm 波「看到」Cannon 溅射的额外价值、
  在 Armor 波「看到」Frost 减速的额外价值，从而产生阵营切换的决策。

================================================================================
★ 方法学前提
================================================================================
1. 现状 AI 估值链：shop_phase_v08 → _action_value_v8 → sv.action_value → sv.dps_only
   （= dps_only_v8 = compute_dps_v8）。这条链**完全不含 wave_tag 构成因子**。
2. 构成因子只存在于 v13._eff_dps（= compute_dps_v11 × composition_factor），
   仅用于「计算本波胜负」，没进「买卡估值」→ AI 盲买。
3. 本脚本 monkey-patch sv.action_value，估值时用 _eff_dps（含构成）而非 dps_only。
   关闭感知时必须逐位一致（金标本零偏移）。
================================================================================
用法
================================================================================
  python corebound_sim_v18_perceive.py selfcheck   # 关闭感知 → 与 v13 逐位一致
  python corebound_sim_v18_perceive.py diag        # 决定性：感知 AI 是否转向对应塔
  python corebound_sim_v18_perceive.py mc 200      # MC：感知 AI 对起飞率的影响
"""

from __future__ import annotations

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6  # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v11_chain as v11  # noqa: F401
import corebound_sim_v13_wavetag as v13

# =============================================================================
# 0. 构成感知：monkey-patch sv.action_value
# =============================================================================
# 当前波次 tag（由 run_v18 在每波商店前设置）。感知打开时，估值用 _eff_dps（含构成）。
_ACTIVE_TAG = None
_PERCEIVE_ON = False

_orig_action_value = sv.action_value


def _perceive_action_value(player, act, cfg, geo):
    """构成感知版估值：wave_tag 打开时用带构成调制的 DPS，否则退回裸 DPS。"""
    if not _PERCEIVE_ON or _ACTIVE_TAG is None:
        return _orig_action_value(player, act, cfg, geo)
    # 用 v13._eff_dps（含 composition_factor）估 ΔDPS
    before = v13._eff_dps(player, cfg, geo, _ACTIVE_TAG)[0]
    s = player.snap()
    cost = sv.apply_action(player, act, cfg)
    if cost is None:
        player.rest(s)
        return None
    after = v13._eff_dps(player, cfg, geo, _ACTIVE_TAG)[0]
    player.rest(s)
    return after - before, cost


sv.action_value = _perceive_action_value


def set_perceive(on, tag=None):
    global _PERCEIVE_ON, _ACTIVE_TAG
    _PERCEIVE_ON = on
    _ACTIVE_TAG = tag


# =============================================================================
# 1. 主循环：复刻 v13，但每波商店前设置 _ACTIVE_TAG（让 AI 感知构成）
# =============================================================================
def run_v18(path, cfg, perceive=False, max_wave=20, geo=None, rng=None):
    """在 v13 之上叠加「构成感知 AI」。perceive=False 时与 v13 逐位一致。"""
    cfg = dict(cfg)
    if geo is None:
        geo = sv.GEO6 if cfg["n_slots"] >= 6 else sv.GEO4
    player = sv.new_player(path, cfg, geo)
    player.charge_cond = {}
    player.last_share = {}
    st = dict(free_layers={0: 1}, n_hist_max=len(player.towers), salvages=0, log=[])
    player.n_hist_max = st["n_hist_max"]
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0

    for w in range(1, max_wave + 1):
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]

        tag = v13.wave_tag_of(w, cfg)
        cfg2 = v13._apply_tag_to_monsters(cfg, w, tag)

        res = sv.simulate_wave(player, w, cfg2, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income

        # ★ 关键：商店前设置当前 tag，让 AI 的估值感知构成
        set_perceive(perceive, tag)
        try:
            budget, rr = v8.shop_phase_v08(player, cum, w, cfg, geo, rng, st)
        finally:
            set_perceive(False, None)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]

        eff, info = v13._eff_dps(player, cfg, geo, tag)
        ratio = eff / res["total_hp"] if res["total_hp"] > 0 else 0.0
        rows.append(dict(
            w=w, n=res["n"], hp_each=round(res["hp_each"], 1),
            total_hp=round(res["total_hp"], 1), eff_dps=round(eff, 1),
            ratio=round(ratio, 3), core_hp=round(max(0.0, core_hp), 1),
            income=round(income, 1), rerolls=rr, cum_rerolls=cum_rerolls,
            towers=len(player.towers), slots=len(player.cards),
            build=player.build_str(), tag=tag,
        ))
        if core_hp <= 0:
            break
    return rows, player, st


# =============================================================================
# 2. 校验与实验
# =============================================================================
def selfcheck():
    """关闭感知时，v18 必须与 v13 逐位一致（wave_tag 开/关两种都要查）。"""
    worst = 0.0
    for path in ("A", "B"):
        for tag_on in (False, True):
            cfg = v8.cfg_of(path)
            cfg["wave_tag_on"] = tag_on
            if tag_on:
                cfg["wave_tag_seq"] = v13._default_tag_seq()
            r18, _, _ = run_v18(path, cfg, perceive=False, max_wave=20, geo=sv.GEO6, rng=None)
            r13, _, _ = v13.run_v13(path, cfg, 20, geo=sv.GEO6, rng=None)
            if len(r18) != len(r13):
                return float("inf")
            for x, y in zip(r18, r13):
                worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def _det(path, cfg, perceive):
    """决定性终局（rng=None 无限商店）。"""
    rows, p, st = run_v18(path, cfg, perceive, 20, geo=sv.GEO6, rng=None)
    towers = [(t.slot, t.ctype, t.h, dict(t.attach)) for t in p.towers]
    return towers, p.cards, st


def diag():
    """决定性诊断：感知 AI 是否在 Armor 波转向 Frost、在 Swarm 波堆 Cannon。"""
    print("=" * 96)
    print("P4 diag · 构成感知 AI 的决定性终局对照")
    print("=" * 96)

    # 熔炉 A：wave_tag on，感知开/关
    cfgA = v8.cfg_of("A")
    cfgA["wave_tag_on"] = True
    cfgA["wave_tag_seq"] = v13._default_tag_seq()
    cfgA["max_actions"] = 12
    t_on, c_on, _ = _det("A", cfgA, True)
    t_off, c_off, _ = _det("A", cfgA, False)
    print(f"熔炉 A（wave_tag on）：")
    print(f"  感知 ON  塔: {t_on}  卡组: {c_on}")
    print(f"  感知 OFF 塔: {t_off}  卡组: {c_off}")
    print()

    # 霜序 B：wave_tag on，感知开/关（看是否转向 Frost）
    cfgB = v8.cfg_of("B")
    cfgB["wave_tag_on"] = True
    cfgB["wave_tag_seq"] = v13._default_tag_seq()
    cfgB["max_actions"] = 12
    tb_on, cb_on, _ = _det("B", cfgB, True)
    tb_off, cb_off, _ = _det("B", cfgB, False)
    print(f"霜序 B（wave_tag on）：")
    print(f"  感知 ON  塔: {tb_on}  卡组: {cb_on}")
    print(f"  感知 OFF 塔: {tb_off}  卡组: {cb_off}")


def _mc_cell(path, kw, runs, seed, perceive):
    rng = random.Random(seed)
    cfg = v8.cfg_of(path)
    cfg.update(kw)
    cfg["max_actions"] = cfg.get("max_actions") or 12
    hits = 0
    tos = []
    for _ in range(runs):
        rows, p, st = run_v18(path, cfg, perceive, 20, geo=sv.GEO6, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            hits += 1
            tos.append(tw)
    return hits / runs, tos


def run_mc(runs=200):
    """MC：感知 AI 对起飞率的影响（3 seed 均值）。"""
    seeds = [v8.SEED1, v8.SEED2, v8.SEED3]
    cells = [
        ("熔炉A 感知off", "A", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()), False),
        ("熔炉A 感知on", "A", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()), True),
        ("霜序B 感知off", "B", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()), False),
        ("霜序B 感知on", "B", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()), True),
    ]
    print(f"P4 MC（{runs} 局/格 × {len(seeds)} seed）—— 构成感知 AI 对起飞率的影响")
    print("=" * 96)
    print(f"{'实验格':<16} {'起飞率(3seed)':>14} {'中位起飞':>10}")
    print("-" * 96)
    for name, path, kw, perceive in cells:
        rates, to_all = [], []
        for seed in seeds:
            r, tos = _mc_cell(path, kw, runs, seed, perceive)
            rates.append(r)
            to_all.extend(tos)
        mean = statistics.mean(rates)
        sd = statistics.stdev(rates) if len(rates) > 1 else 0.0
        print(f"{name:<16} {mean:.3f}±{sd:.3f}  "
              f"{statistics.median(to_all) if to_all else '—':>10}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 关闭感知时 v18 vs v13 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "diag":
        diag()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
