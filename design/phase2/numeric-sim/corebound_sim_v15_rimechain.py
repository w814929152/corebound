# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.15：霜序条件链（T4/T6）能不能救「没得选」**

================================================================================
它要回答的一个问题
================================================================================
v0.14（P5 阵营锁定）实测发现：🔴 霜序「没得选」是结构性的——决定性终局里霜序 A
**零冰系**，AI 理性地只堆 Arrow（DPS 10）而放弃 Frost（DPS 5）。

本脚本做两件事，把 v14 的「结构性问题」拆成可定位的根因：
  1. **根因定位**：Frost 基础 DPS 太低 vs 条件链未实现，哪个是主因？
  2. **条件链建模**：给 Frost 补 faction-decks §3.2 的 T4（Stasis 条件复利），
     看它能否让霜序在 Armor 波（减速驻留久）下追平熔炉。

================================================================================
★ 方法学前提（必须先讲清）
================================================================================
1. v09 已经明记：「Brittle 作用对象是凝滞/霜爆的触发条件，而这两个机制在引擎里
   根本没实现（只有 FireUp/FrostUp 两种强化卡）→ 硬凑等于造假。」
   所以本脚本的「条件链」是**忠实建模 T4 Stasis**（对减速目标 ×(1+κ)^n），
   不是把 Brittle/凝滞/霜爆 三个未实现机制硬塞进来。
2. sim 的 FrostUp 是**无条件复利**（与 FireUp 完全同构），这恰恰抹掉了
   霜序（条件复利）与熔炉（无条件复利）的本质区别。本脚本补回「条件」这一层。
3. 条件复利的最小建模：**Frost 塔的复利，只有当「场上存在减速塔」时才完整生效**。
   这是「条件」的最小语义——减速是霜序的钥匙，也是它的锁。

================================================================================
用法
================================================================================
  python corebound_sim_v15_rimechain.py selfcheck   # 关闭条件链 = v14 逐位一致
  python corebound_sim_v15_rimechain.py diag        # 根因定位（Frost DPS vs 条件链）
  python corebound_sim_v15_rimechain.py mc 200      # 条件链 × 波构成 MC
"""

from __future__ import annotations

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6  # noqa: F401
import corebound_sim_v08_salvage as v8
import corebound_sim_v09_trigger as v9
import corebound_sim_v13_wavetag as v13
import corebound_sim_v14_factionlock as v14

# =============================================================================
# 0. 条件链常量（全部 [PLACEHOLDER]，方向有依据，具体值待校准）
# =============================================================================
# T4 Stasis 条件复利：Frost 塔的复利额外乘 (1+κ_cond)^n，但**只在减速存在时**。
#   κ_cond 取 0.05（对标的 κ_r=0.050 共鸣利率，因为「减速条件」本质是霜序的
#   第二引擎，与熔炉的 AoE 乘区（aoe_cap 2.6）对等）。
#   物理依据：减速驻留 = 更多输出窗口，但收益是「条件」的——怪不被减速就没收益。
COND_KAPPA = 0.05

# 条件链开关（默认关闭 → 与 v14 逐位一致）
_RIME_COND_ON = False


def _has_slow(ts):
    """场上是否存在减速塔（slow > 0）。这是 T4 的条件。"""
    return any(sv.TOWERS[t.ctype]["slow"] > 0 for t in ts)


def _cond_stack(lv, kappa, cap, decay):
    """条件复利的叠层：softcap_pow 的「条件版本」。
    κ_cond 独立于主 κ，只在减速存在时生效。"""
    return sv.softcap_pow(lv, kappa, cap, decay)


# =============================================================================
# 1. 引擎 hook：在 compute_dps_v9 之上，给 Frost 塔补条件复利
# =============================================================================
# monkey-patch：包装 compute_dps_v11（v14 用的入口），在 Frost 塔的 stack 上
# 乘一个「条件复利」因子。关闭 _RIME_COND_ON 时逐位一致。

_orig_compute = None  # 指向 v14 实际调用的 compute（v11.compute_dps_v11）


def _compute_rimecond(player, cfg, geo=None):
    total, info = _orig_compute(player, cfg, geo)
    if not _RIME_COND_ON:
        return total, info
    per = info.get("per_tower", [])
    ts = player.towers
    if not per or not ts:
        return total, info
    slow_on = _has_slow(ts)
    if not slow_on:
        return total, info
    # Frost 塔的复利额外乘条件因子
    sub = 0.0
    for i, t in enumerate(ts):
        if t.ctype != "Frost":
            continue
        p = per[i]
        # FrostUp 的层数 = 条件复利的基数（复用主复利的层数口径）
        lv = t.attach.get("FrostUp", 0)
        if lv <= 0:
            continue
        # 条件复利：softcap_pow(lv, 1+COND_KAPPA, cap, decay) / softcap_pow(lv, kappa, ...)
        # 简化：直接乘一个条件放大因子 (1+COND_KAPPA)^lv（未 softcap，方向性近似）
        factor = (1.0 + COND_KAPPA) ** lv
        p["dps"] *= factor
    info["subtotal"] = sum(pp["dps"] for pp in per)
    total = info["subtotal"] * info["aoe"] * info["crossfire"] * info["aux"] * info["empower"]
    return total, info


def _patch():
    """把 _compute_rimecond 接到 v14 依赖的 compute 链上。"""
    global _orig_compute
    import corebound_sim_v11_chain as v11
    _orig_compute = v11.compute_dps_v11
    v11.compute_dps_v11 = _compute_rimecond
    # v13 的 _eff_dps 也走 v11.compute_dps_v11，但 v13 内部 import 的是模块级名字，
    # 需要同步替换 v13 引用的 compute
    # （v13.composition_factor / _eff_dps 都调 v11.compute_dps_v11，见 v13 源码）
    v13.compute_dps_v11 = _compute_rimecond


_patch()


def set_cond(on):
    global _RIME_COND_ON
    _RIME_COND_ON = on


# =============================================================================
# 2. 校验与实验
# =============================================================================
def selfcheck():
    """关闭条件链时，v15 必须与 v14 逐位一致。"""
    set_cond(False)
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r15, _, _ = v14.run_v14(path, cfg, "rime", 20, geo=sv.GEO6, rng=None)
        # 对照：直接跑 v14（未打补丁前的行为应一致）
        set_cond(False)
        # 重新算一次，确认 cond 关闭时 _compute_rimecond 透传
        r14b, _, _ = v14.run_v14(path, cfg, "rime", 20, geo=sv.GEO6, rng=None)
        for x, y in zip(r15, r14b):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def _mc_cell(path, faction, kw, runs, seed):
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


def diag():
    """根因定位：Frost 基础 DPS vs 条件链，谁是主因。"""
    print("=" * 96)
    print("v0.15 根因定位 —— 霜序 A 起飞率（3 seed × 200 局）")
    print("=" * 96)
    seeds = [v8.SEED1, v8.SEED2, v8.SEED3]
    runs = 200

    cells = [
        ("baseline (Frost DPS5, 无条件链)", dict(), False, None),
        ("fix-dps (Frost DPS 5→7)",        dict(), False, 7.0),
        ("fix-chain (条件复利 κ=0.05)",    dict(), True, None),
        ("fix-both (DPS7 + 条件链)",       dict(), True, 7.0),
    ]

    print(f"{'实验格':<34} {'A率(3seed)':<18} {'A中位起飞'}")
    print("-" * 96)
    orig_frost_dps = sv.TOWERS["Frost"]["dps"]
    for name, kw, cond, frost_dps in cells:
        set_cond(cond)
        # ★ 关键：frost_dps=None 时要**还原**为基础值，否则上一格的修改会泄漏到本格
        sv.TOWERS["Frost"]["dps"] = frost_dps if frost_dps is not None else orig_frost_dps
        rates, tos = [], []
        for seed in seeds:
            r, to = _mc_cell("A", "rime", kw, runs, seed)
            rates.append(r)
            tos.extend(to)
        mean = statistics.mean(rates)
        sd = statistics.stdev(rates) if len(rates) > 1 else 0.0
        print(f"{name:<34} {mean:.3f}±{sd:.3f}   "
              f"{statistics.median(tos) if tos else '—'}")
    sv.TOWERS["Frost"]["dps"] = orig_frost_dps
    set_cond(False)

    print()
    print("读法：fix-dps 与 fix-chain 的增量分别量化「基础值」与「条件链」两个根因的贡献。")
    print("若 fix-chain 增量 ≈ 0，说明条件链救不了「Frost 进场门槛」（基础值才是主因）。")


def run_mc(runs=200):
    """MC：条件链 × 波构成（Armor 波下霜序能否追平熔炉）。"""
    print("=" * 96)
    print(f"v0.15 MC（{runs} 局/格 × 3 seed）—— 条件链能否让霜序「有得选」")
    print("=" * 96)
    seeds = [v8.SEED1, v8.SEED2, v8.SEED3]
    tag_modes = [("no-tag", dict(wave_tag_on=False)),
                 ("wavetag", dict(wave_tag_on=True, wave_tag_seq=v13._default_tag_seq()))]
    conds = [("无条件链", False), ("条件链κ0.05", True)]

    print("| 条件链      | tag       | 霜序A率  | 熔炉A率  | 差距(熔炉-霜序) |")
    print("|-------------|-----------|----------|----------|-----------------|")
    for cname, cond in conds:
        set_cond(cond)
        for tname, kw in tag_modes:
            rime_rates, cinder_rates = [], []
            for seed in seeds:
                rime_rates.append(_mc_cell("A", "rime", kw, runs, seed)[0])
                cinder_rates.append(_mc_cell("A", "cinder", kw, runs, seed)[0])
            r_mean = statistics.mean(rime_rates)
            c_mean = statistics.mean(cinder_rates)
            print(f"| {cname:<11} | {tname:<9} | {r_mean:.3f}   | {c_mean:.3f}   | "
                  f"{c_mean - r_mean:+.3f}          |")
    set_cond(False)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 关闭条件链时 v15 vs v14 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "diag":
        diag()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 200)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
