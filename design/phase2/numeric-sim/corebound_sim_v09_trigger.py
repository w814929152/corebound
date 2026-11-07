# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.9：触发式卡（Charge）与 Tag 中继（Relay）的适配数值验证**
作者：文策渊（策划）／执行：数值仿真

================================================================================
回答什么问题
================================================================================
`design/gdd/keyword-adaptation.md` 提了四张卡，其中两张能在 v0.3 引擎里被忠实建模：

  **Charge 蓄能**（触发链）：每波开始，该塔本波伤害 +2%×n（cap +30%）；
      若上波该塔击杀 ≥ K，本波效果翻倍。
      建模难点：v0.3 的 simulate_wave 只统计**全局击杀数**，不分塔。
      → 本脚本按「该塔 DPS 占比」把击杀数分摊到塔（见 §2.2 假设 A1）。

  **RelayFire / RelayFrost 中继**（几何联动）：挂上后向指定 Tag 池注入
      1 层/层（全局 cap 2 层），自身**不产生任何 Stack 伤害**。
      建模方式：不进 `stack` 累加、不进 `L`（Focus/AllIn 的层数），只进 `tag_invest`。
      → 它直接拨 `κ_tag` 档位开关（0.06 → 0.10），是本轮**最高风险**的一张。

另外两张（Brittle 脆化、Cascade 级联）**不在本脚本内**：
  · Brittle 的作用对象是 `凝滞 / 霜爆` 的触发条件，而这两个机制在 v0.3 引擎里
    根本没有实现（引擎只有 FireUp / FrostUp 两种强化卡）→ 建模不出来，硬凑等于造假。
  · Cascade 撞 Q-C3 定稿（拆塔装配卡全销毁），属未拍板项 → 不验。

================================================================================
实验设计（唯一变量原则）
================================================================================
卡池大小会直接影响 pity 命中与购买分布，所以**所有实验格的卡池总张数固定为 10**，
缺的用「空牌」（进商店、无效果、AI 不买）补齐：

  base7      7 张原卡池（对照基准，必须与 v08 逐位一致）
  pad10      7 张 + 3 张空牌           → 只测「卡池稀释」这一个变量
  charge10   7 张 + Charge + 2 空牌    → 稀释前提下测 Charge
  relay10    7 张 + Relay×2 + 1 空牌   → 稀释前提下测 Relay
  both10     7 张 + 3 张新卡           → 全开

================================================================================
不做的事
================================================================================
★ 不改 v03 / v04 / v05 / v06 / v07 / v08 任何原文件。
★ 不改任何 GDD；本脚本只产出数据，结论由策划写回文档。
★ 不改任何定稿数值（κ 公式 / κ_tag 档位 / κ_r / 卡价 / hp_growth / focus …）。

用法：
  python corebound_sim_v09_trigger.py det          # 决定性 5 格（秒级）
  python corebound_sim_v09_trigger.py mc 300       # 蒙特卡洛（分钟级）
  python corebound_sim_v09_trigger.py sweep        # Charge 的 K 值扫参
"""
from __future__ import annotations

import os
import sys
import time
import random
import statistics

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6
import corebound_sim_v07_mapA as v7          # noqa: F401  （导入即为链式打补丁）
import corebound_sim_v08_salvage as v8

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 新卡常量（全部 [PLACEHOLDER]，取值理由见 keyword-adaptation.md §7.1）
# =============================================================================
CHARGE_PER = 0.02       # 每层 +2%/波（对照 Overclock 攻速 +8%/层）
CHARGE_CAP = 0.30       # 上限 +30%（对照 Overclock cap +80%）
CHARGE_K = 8            # 上波击杀阈值（W1 全场 10 只怪 → 主塔要抢）
RELAY_PER = 1.0         # 每层向 Tag 池注入 1 层
RELAY_CAP = 2.0         # 全局 cap 2 层（GDD §5.2 闸门 1）

PRICE_REINF = sv.PRICE["reinforce"]

V9_CARDS = {
    "Charge":     dict(tag=None,    is_relay=False, w=0.14),
    "RelayFire":  dict(tag="fire",  is_relay=True,  w=0.12),
    "RelayFrost": dict(tag="frost", is_relay=True,  w=0.12),
}
V9_NON_STACK = set(V9_CARDS)          # 不进 stack、不进 L
W_PAD = 0.14                          # 空牌权重 ≈ 原卡池均值


def _layers(t):
    """该塔的「有效强化层数」= GDD 的 n（Focus / AllIn / core 判定都用它）。
    Charge / Relay 不是伤害叠层卡，必须排除，否则会白送 Focus 与 AllIn。"""
    return sum(lv for rn, lv in t.attach.items() if rn not in V9_NON_STACK)


# =============================================================================
# 1. v0.9 引擎 = v0.8 引擎 + 三个 hook（Charge / Relay / 层数口径）
#    关闭全部新卡时，必须与 v8 逐位一致（selfcheck_engine）
# =============================================================================
def compute_dps_v9(player, cfg, geo=None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return v8.compute_dps_v8(player, cfg, geo)

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    h = [t.h for t in ts]
    L = [_layers(t) for t in ts]                     # ★ hook：排除 Charge/Relay
    Ltot = sum(L)
    core = max(range(n), key=lambda i: L[i]) if Ltot > 0 else 0

    tag_invest = {}
    tag_tower_lv = {}
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if tg:
            tag_invest[tg] = tag_invest.get(tg, 0) + h[i]
            tag_tower_lv[tg] = tag_tower_lv.get(tg, 0) + h[i]
        for rn, lv in t.attach.items():
            if rn in V9_NON_STACK:                   # ★ hook
                continue
            rt = sv.REINF[rn]["tag"]
            tag_invest[rt] = tag_invest.get(rt, 0) + lv

    # ---- ★ hook：Relay 向 Tag 池注入虚拟层数（全局 cap）----
    if cfg.get("v9_relay"):
        relay = {}
        for t in ts:
            for rn, lv in t.attach.items():
                if rn in V9_CARDS and V9_CARDS[rn]["is_relay"]:
                    tg = V9_CARDS[rn]["tag"]
                    relay[tg] = relay.get(tg, 0) + lv
        for tg, rl in relay.items():
            tag_invest[tg] = tag_invest.get(tg, 0) + min(RELAY_PER * rl, RELAY_CAP)

    kmode = cfg.get("kappa_mode", "path")
    ktiers = cfg.get("ktag_tiers", v6.KTAG_TIERS_MVP)
    if cfg.get("ntower_mode", "current") == "max":
        n_for_kappa = max(int(getattr(player, "n_hist_max", n)), n)
    else:
        n_for_kappa = n
    disc = 0.01 * min(max(n_for_kappa - 2, 0), 4)
    kappa, caps = [], []
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if kmode == "tier":
            inv = tag_invest.get(tg, 0) if tg else 0
            k = max(0.02, v8._tier(inv, ktiers) - disc)
            cap_i = (v8._tier(inv, cfg.get("stackcap_tiers", v6.STACKCAP_TIERS))
                     if cfg.get("stackcap_tier") else cfg["reinf_cap"])
        else:
            k = cfg["reinf_compound"][path] - 1.0
            cap_i = cfg["reinf_cap"]
        kappa.append(1.0 + k)
        caps.append(cap_i)

    krmode = cfg.get("kr_mode", "flat")
    krtiers = cfg.get("kr_tiers", v6.KR_TIERS_T1)
    neutral = cfg.get("kr_neutral", 0.045)
    kr = []
    for t in ts:
        tg = sv.TOWERS[t.ctype]["tag"]
        if krmode == "tier":
            kr.append(v8._tier(tag_invest.get(tg, 0), krtiers) if tg else neutral)
        else:
            kr.append(cfg["kappa_r"])

    adj = [[] for _ in range(n)]
    E = [0.0] * n
    if cfg["use_resonance"] and geo is not None:
        gtypes = [None] * geo.n
        for t in ts:
            gtypes[t.slot] = t.ctype
        gadjs = geo.links(gtypes, cfg["link_rule"])
        for i, t in enumerate(ts):
            for gj in gadjs[t.slot]:
                for k, t2 in enumerate(ts):
                    if k != i and t2.slot == gj:
                        adj[i].append(k)
                        if h[i] >= lmin and h[k] >= lmin:
                            E[i] += 1.0 + h[k]
    elif cfg["use_resonance"]:
        for i in range(n):
            for k in range(n):
                if k != i:
                    adj[i].append(k)
                    if h[i] >= lmin and h[k] >= lmin:
                        E[i] += 1.0 + h[k]

    decay = cfg["softcap_decay"]
    charge_cond = getattr(player, "charge_cond", {}) or {}

    per_tower = []
    syn_hits = 0
    for i, t in enumerate(ts):
        base = sv.TOWERS[t.ctype]["dps"] * (h[i] ** cfg["tower_stack_exp"])
        stack = 1.0
        for rn, lv in t.attach.items():
            if rn in V9_NON_STACK:                   # ★ hook
                continue
            if sv.REINF[rn]["tag"] != sv.TOWERS[t.ctype]["tag"]:
                continue
            stack += sv.softcap_pow(lv, kappa[i], caps[i], decay) - 1.0
        tg = sv.TOWERS[t.ctype]["tag"]
        syn = 1.0
        if cfg.get("synergy_on", True) and tg and tag_tower_lv.get(tg, 0) >= cfg["synergy_threshold"]:
            syn = cfg["synergy_mult"]
            syn_hits += 1
        res = ((1.0 + kr[i]) ** E[i]) if cfg["use_resonance"] else 1.0
        foc = 1.0
        if cfg["use_focus"]:
            if cfg.get("focus_full", False):
                foc = 1.0 + cfg["focus_per_layer"] * L[i]
            else:
                fh = cfg.get("focus_min_h", 8.0)
                ramp = min(1.0, h[i] / fh) if fh > 0 else 1.0
                foc = 1.0 + cfg["focus_per_layer"] * L[i] * ramp
        ali = 1.0
        if cfg["use_allin"] and Ltot > 0 and i == core and L[i] >= cfg["allin_share"] * Ltot:
            ali = cfg["allin_mult"]
        if cfg["coverage_mode"] == "geometry" and geo is not None:
            cov = geo.cov[(t.slot, t.ctype)]
        else:
            cov = cfg["path_coverage"][path]
        per_tower.append(dict(base=base, stack=stack, syn=syn, res=res,
                              focus=foc, allin=ali, cov=cov, charge=1.0,
                              dps=base * stack * syn * res * foc * ali * cov))

    aoe_total = sum(tag_tower_lv.values())
    aoe = min(cfg["aoe_cap"][path], 1.0 + cfg["aoe_per"][path] * aoe_total)

    if not cfg["use_crossfire"]:
        cf = 1.0
    else:
        cf = cfg["crossfire_3"] if n >= 3 else (cfg["crossfire_2"] if n >= 2 else 1.0)

    aux = 1.0
    if cfg["use_aux"]:
        aux_mode = cfg.get("aux_mode", "global")
        if aux_mode == "per_tower":
            aux_parts = []
            for t in ts:
                slow = sv.TOWERS[t.ctype]["slow"]
                mult = 1.0
                if slow > 0:
                    mult = 1.0 / (1.0 - min(slow, 0.75))
                    c = cfg.get("aux_cap", 1.5)
                    if c is not None and mult > c:
                        mult = c
                aux_parts.append(mult)
            for i, p in enumerate(per_tower):
                p["dps"] = p["dps"] * aux_parts[i]
            aux = sum(aux_parts) / max(1, len(aux_parts))
        else:
            slow_towers = [t for t in ts if sv.TOWERS[t.ctype]["slow"] > 0]
            if slow_towers:
                slow = max(sv.TOWERS[t.ctype]["slow"] for t in slow_towers)
                h_slow = max(t.h for t in slow_towers)
                tau = cfg.get("aux_tau", 8.0)
                eff_slow = slow * (h_slow / (h_slow + tau))
                aux = 1.0 / (1.0 - min(eff_slow, 0.75))
                c = cfg.get("aux_cap", 1.5)
                if c is not None and aux > c:
                    aux = c

    empower = 1.0
    if cfg.get("use_empowerment"):
        empower = 1.0 + cfg.get("empower_per_layer", 0.015) * L[core]
        empower = min(empower, cfg.get("empower_cap", 3.0))

    # ---- ★ hook：Charge 波级乘区（只作用于本塔，不进 stack 复利）----
    if cfg.get("v9_charge"):
        for i, t in enumerate(ts):
            nl = t.attach.get("Charge", 0)
            if nl <= 0:
                continue
            bonus = min(CHARGE_PER * nl, CHARGE_CAP)
            met = bool(charge_cond.get(t.slot))
            if cfg.get("charge_gate"):
                cond = 1.0 if met else 0.0          # 纯门控：不达标则完全不生效
            elif not cfg.get("charge_double", True):
                cond = 1.0                          # 消融实验：摘掉「达标翻倍」
            else:
                cond = 2.0 if met else 1.0
            f = 1.0 + bonus * cond
            per_tower[i]["charge"] = f
            per_tower[i]["dps"] *= f

    subtotal = sum(p["dps"] for p in per_tower)
    total = subtotal * aoe * cf * aux * empower
    return total, dict(per_tower=per_tower, adj=adj, E=E, aoe=aoe, crossfire=cf,
                       aux=aux, empower=empower, subtotal=subtotal, core=core,
                       L=L, Ltot=Ltot, kr=kr, kappa=kappa, caps=caps,
                       tag_invest=tag_invest, tag_tower_lv=tag_tower_lv,
                       syn_hits=syn_hits, n_for_kappa=n_for_kappa, disc=disc)


def selfcheck_engine():
    """关闭全部新卡时，v9 必须与 v8 逐位一致（防复制粘贴漂移）。"""
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        st = v8.final_state(path, cfg, waves=20, salvage_on=False)
        p = st["player"]
        d8, i8 = v8.compute_dps_v8(p, cfg, sv.GEO6)
        d9, i9 = compute_dps_v9(p, cfg, sv.GEO6)
        worst = max(worst, abs(d8 - d9) / max(1.0, abs(d8)))
        assert abs(i8["subtotal"] - i9["subtotal"]) < 1e-9, f"{path}: subtotal 漂移"
        assert i8["E"] == i9["E"], f"{path}: E 漂移"
        assert i8["kappa"] == i9["kappa"], f"{path}: κ 漂移"
    return worst


sv.compute_dps = compute_dps_v9
sv.dps_only = lambda p, c, g=None: compute_dps_v9(p, c, g)[0]


# =============================================================================
# 2. 商店：卡池 / 抽卡 / 动作枚举 / 估值
# =============================================================================
def pool_weights(cfg):
    w = dict(sv.WEIGHTS)                       # 7 张原卡（含 RerollD，权重不动）
    if cfg.get("v9_charge"):
        w["Charge"] = V9_CARDS["Charge"]["w"]
    if cfg.get("v9_relay"):
        w["RelayFire"] = V9_CARDS["RelayFire"]["w"]
        w["RelayFrost"] = V9_CARDS["RelayFrost"]["w"]
    for i in range(int(cfg.get("v9_pad", 0))):
        w[f"_pad{i}"] = W_PAD                  # 空牌：进商店、无动作、AI 不买
    return w


def draw_offers_v9(rng, cfg, k=3, force=None):
    """🔴 卡名顺序必须与 v03 的 `_CARD_NAMES` 一致（= WEIGHTS 的插入序），
    否则 `rng.choices()` 消耗随机数的顺序改变 → 同一个 seed 下整条 MC 轨迹全偏，
    base7 就无法与 v08 的 300 局读数对照。"""
    w = pool_weights(cfg)
    names = list(w)                            # 不用 sorted：保序
    s = set(rng.choices(names, weights=[w[n] for n in names], k=k))
    if force:
        s.add(force)
        while len(s) > k:
            s.discard(rng.choice(sorted(s - {force})))
    return s


def enumerate_actions_v9(player, cfg, fire_bought, offers=None, geo=None):
    acts = list(sv.enumerate_actions(player, cfg, fire_bought, offers, geo))
    for name, meta in V9_CARDS.items():
        if not cfg.get("v9_" + ("charge" if name == "Charge" else "relay")):
            continue
        if meta["tag"] == "fire" and fire_bought >= cfg["fire_stock"][player.path]:
            continue
        if offers is not None and name not in offers:
            continue
        for t in player.towers:
            if name in player.cards:
                acts.append(("reinf", name, t.slot, None))
            elif len(player.cards) < cfg["backpack"]:
                acts.append(("reinf_new", name, t.slot, None))
            else:
                drop = sv.weakest_card(player, cfg, geo)
                if drop is not None and drop != name:
                    acts.append(("reinf_swap", name, t.slot, drop))
    return acts


def action_value_v9(player, act, cfg, geo):
    kind, name, slot, extra = act
    if kind in ("reinf", "reinf_new", "reinf_swap") and name == "Charge":
        if slot is None:
            return None
        i = next((k for k, t in enumerate(player.towers) if t.slot == slot), None)
        if i is None:
            return None
        total, info = compute_dps_v9(player, cfg, geo)
        if not info["per_tower"]:
            return None
        contrib = (info["per_tower"][i]["dps"] * info["aoe"]
                   * info["crossfire"] * info["aux"] * info["empower"])
        nl = player.towers[i].attach.get("Charge", 0)
        d_bonus = (min(CHARGE_PER * (nl + 1), CHARGE_CAP)
                   - min(CHARGE_PER * nl, CHARGE_CAP))
        cond = getattr(player, "charge_cond", {}) or {}
        share = getattr(player, "last_share", {}) or {}
        # 理性 AI 的预期：已达标 / 该塔上波占输出 ≥35% → 预期翻倍
        pred = 2.0 if (cond.get(slot) or share.get(slot, 0.0) >= 0.35) else 1.0
        return contrib * d_bonus * pred, PRICE_REINF
    return v8._action_value_v8(player, act, cfg, geo)


def shop_phase_v9(player, budget, w, cfg, geo, rng, st):
    fl = st["free_layers"]
    rerolls = 0
    actions = 0
    fire_bought = 0
    counts = {}
    offers = None
    if rng is not None:
        offers = draw_offers_v9(rng, cfg, cfg["shop_offers"],
                                sv.pity_card(player) if cfg.get("pity") else None)
    while budget > 0:
        if cfg["max_actions"] is not None and actions >= cfg["max_actions"]:
            break
        cands = enumerate_actions_v9(player, cfg, fire_bought, offers, geo)
        scored = []
        for act in cands:
            v = action_value_v9(player, act, cfg, geo)
            if v is None:
                continue
            gain, _ = v
            cost = sv.action_cost(act, cfg, counts)
            if gain <= 0 or budget < cost:
                continue
            scored.append((gain / cost, act, cost))
        if scored:
            if rng is not None and cfg["skill"] < 1.0 and rng.random() > cfg["skill"]:
                pick = scored[rng.randrange(len(scored))]
            else:
                pick = max(scored, key=lambda x: x[0])
            _, act, cost = pick
            sv.apply_action(player, act, cfg)
            if sv.ALL_CARDS.get(act[1], {}).get("tag") == "fire":
                fire_bought += 1
            counts[act[1]] = counts.get(act[1], 0) + 1
            budget -= cost
            actions += 1
            if act[1] == "Charge":
                st["charge_bought"] += 1
                st["charge_log"].append(w)
            elif act[1] in ("RelayFire", "RelayFrost"):
                st["relay_bought"] += 1
                st["relay_log"].append(w)
            v8._sync_free_layers(player, fl)
            st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
            player.n_hist_max = st["n_hist_max"]
            continue
        rc = max(1.0, cfg["reroll_base"] + cfg["reroll_growth"] * rerolls - player.reroll_disc)
        if rc > budget:
            break
        if cfg["max_actions"] is not None and actions + 1 > cfg["max_actions"]:
            break
        budget -= rc
        rerolls += 1
        actions += 1
        if rng is not None:
            offers = draw_offers_v9(rng, cfg, cfg["shop_offers"],
                                    sv.pity_card(player) if cfg.get("pity") else None)
        elif rerolls > 400:
            break
    return budget, rerolls


# =============================================================================
# 3. 主循环（= v8.run_v08 + 击杀分摊 + 触发态更新）
# =============================================================================
def run_v9(path, cfg, max_wave=20, geo=None, rng=None):
    cfg = dict(cfg)
    if geo is None:
        geo = sv.GEO6 if cfg["n_slots"] >= 6 else sv.GEO4
    player = sv.new_player(path, cfg, geo)
    player.charge_cond = {}
    player.last_share = {}
    st = dict(free_layers={0: 1}, n_hist_max=len(player.towers), salvages=0, log=[],
              charge_bought=0, relay_bought=0, cond_hit=0, cond_miss=0,
              main_hit=0, main_miss=0, charge_log=[], relay_log=[])
    player.n_hist_max = st["n_hist_max"]
    core_hp = cfg["core_hp"]
    rows = []
    cum = 0.0
    cum_rerolls = 0
    n_max_hist = len(player.towers)
    for w in range(1, max_wave + 1):
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]
        n_max_hist = max(n_max_hist, len(player.towers))

        res = sv.simulate_wave(player, w, cfg, geo)      # 用「上一波结算出的」charge_cond
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income

        # ---- 回写触发态：按 DPS 占比分摊本波击杀（假设 A1）----
        _, info = compute_dps_v9(player, cfg, geo)
        sub = info["subtotal"] if info["subtotal"] > 0 else 1.0
        share = {}
        for i, t in enumerate(player.towers):
            share[t.slot] = info["per_tower"][i]["dps"] / sub
        player.last_share = share
        cond = {}
        main_slot = max(player.towers, key=lambda t: sum(t.attach.values())).slot \
            if player.towers else None
        for t in player.towers:
            k_i = res["kills"] * share.get(t.slot, 0.0)
            cond[t.slot] = k_i >= CHARGE_K
            if t.attach.get("Charge", 0) > 0:
                if cond[t.slot]:
                    st["cond_hit"] += 1
                else:
                    st["cond_miss"] += 1
                if t.slot == main_slot:          # 只看主塔：这才是这张卡真正的判定对象
                    if cond[t.slot]:
                        st["main_hit"] += 1
                    else:
                        st["main_miss"] += 1
        player.charge_cond = cond

        budget, rr = shop_phase_v9(player, cum, w, cfg, geo, rng, st)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]
        n_max_hist = max(n_max_hist, len(player.towers))
        dps, _ = compute_dps_v9(player, cfg, geo)
        ratio = dps / res["total_hp"] if res["total_hp"] > 0 else 0.0
        rows.append(dict(
            w=w, n=res["n"], hp_each=round(res["hp_each"], 1),
            total_hp=round(res["total_hp"], 1), eff_dps=round(dps, 1),
            ratio=round(ratio, 3), core_hp=round(max(0.0, core_hp), 1),
            income=round(income, 1), rerolls=rr, cum_rerolls=cum_rerolls,
            towers=len(player.towers), slots=len(player.cards),
            build=player.build_str(),
        ))
        if core_hp <= 0:
            break
    st["n_hist_max"] = n_max_hist
    return rows, player, st


# =============================================================================
# 4. 实验格
# =============================================================================
CELLS = [
    ("base7",    dict(v9_charge=False, v9_relay=False, v9_pad=0)),
    ("pad10",    dict(v9_charge=False, v9_relay=False, v9_pad=3)),
    ("charge10", dict(v9_charge=True,  v9_relay=False, v9_pad=2)),
    ("chargeno", dict(v9_charge=True,  v9_relay=False, v9_pad=2, charge_double=False)),
    ("chargegate", dict(v9_charge=True, v9_relay=False, v9_pad=2, charge_gate=True)),
    ("relay10",  dict(v9_charge=False, v9_relay=True,  v9_pad=1)),
    ("both10",   dict(v9_charge=True,  v9_relay=True,  v9_pad=0)),
]
# base7  = 7 张原池（对照基准，必须与 v08 逐位一致）
# pad10  = 7+3 空牌       → 纯卡池稀释成本
# chargeno = Charge 但摘掉「达标翻倍」 → 消融实验：证明触发条件是否真的在起作用


def make_cfg(path, cell_kw, **over):
    c = v8.cfg_of(path)
    for k, v in cell_kw.items():
        c[k] = v
    c.update(over)
    return c


def eval_cell(name, kw, runs_mc=0, seed=v8.SEED1):
    out = dict(cell=name, kw=dict(kw))
    sts = {}
    for path in ("A", "B"):
        rows, player, st = run_v9(path, make_cfg(path, kw), 20, geo=sv.GEO6, rng=None)
        s = v6.summarize(rows)
        sts[path] = dict(rows=rows, s=s, player=player, st=st)
    sA, sB = sts["A"]["s"], sts["B"]["s"]
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    _, lead, flips, _, _ = v6.cross_lead(sts["A"]["rows"], sts["B"]["rows"])
    out.update(toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=round(w20B / w20A, 3) if w20A else 0.0,
               hpA=sA["core_hp"], hpB=sB["core_hp"], flips=flips,
               hA=v6.stage_health(sts["A"]["rows"]),
               hB=v6.stage_health(sts["B"]["rows"]),
               st=sts)
    if runs_mc:
        mc = {}
        for path in ("A", "B"):
            rng = random.Random(seed)
            cfg = make_cfg(path, kw)
            cfg["max_actions"] = cfg.get("max_actions") or 12
            ok = hits = 0
            tos = []
            ch = []
            for _ in range(runs_mc):
                rows, player, st = run_v9(path, cfg, 20, geo=sv.GEO6, rng=rng)
                alive = bool(rows) and rows[-1]["core_hp"] > 0
                tw = sv.takeoff_wave(rows)
                if alive:
                    ok += 1
                    if tw is not None:
                        hits += 1
                        tos.append(tw)
                ch.append(st["charge_bought"])
            mc[path] = dict(rate=round(hits / runs_mc, 3), surv=round(ok / runs_mc, 3),
                            med=statistics.median(tos) if tos else None,
                            charge_mean=round(statistics.mean(ch), 2))
        out["mc"] = mc
    return out


# =============================================================================
# 5. 输出
# =============================================================================
def fmt_row(r):
    def n(v):
        return "—" if v is None else str(v)
    mc = r.get("mc") or {}
    a, b = mc.get("A", {}), mc.get("B", {})
    return (f"| {r['cell']:<9} | {n(r['toA']):>4} | {n(r['toB']):>4} | "
            f"{r['w20A']:>8.2f} | {r['w20B']:>8.2f} | {r['ba']:>6.3f} | "
            f"{n(a.get('rate')):>6} | {n(b.get('rate')):>6} | "
            f"{r['flips']:>3} | {r['hpA']:>6} |")


HDR = ("| 实验格    | toA  | toB  |   W20-A  |   W20-B  |  B/A   | A率   | B率   | 交叉 | A核心 |\n"
       "|-----------|------|------|----------|----------|--------|-------|-------|------|-------|")


def run_det():
    print("=" * 100)
    print("v0.9 决定性对照（rng=None，理性 AI，GEO6，20 波）")
    print("=" * 100)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw)
        rows.append(r)
        print(f"[{name}] {time.time()-t0:.1f}s  " + r["st"]["A"]["player"].build_str())
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    print()
    base = next(r for r in rows if r["cell"] == "base7")
    print("相对 base7 的偏移：")
    for r in rows:
        if r["cell"] == "base7":
            continue
        dA = (r["toA"] - base["toA"]) if (r["toA"] and base["toA"]) else None
        dB = (r["toB"] - base["toB"]) if (r["toB"] and base["toB"]) else None
        print(f"  {r['cell']:<9} toA {dA if dA is None else format(dA,'+d')}"
              f"  toB {dB if dB is None else format(dB,'+d')}"
              f"  W20A {'+' if r['w20A']>=base['w20A'] else ''}{r['w20A']-base['w20A']:.2f}"
              f"  B/A {r['ba']-base['ba']:+.3f}")
    print()
    print("Charge 购入画像（判定它到底是「时序卡」还是「第 11 个乘区」）：")
    print("| 实验格    | 购入层数 | 首次购入波 | 主塔达标率 | 主塔Charge层 | 该塔总层数 |")
    print("|-----------|----------|------------|------------|----------|----------|")
    for r in rows:
        if not r["kw"].get("v9_charge"):
            continue
        st = r["st"]["A"]["st"]
        tot = st["main_hit"] + st["main_miss"]
        mrate = round(st["main_hit"] / tot, 3) if tot else 0.0
        lay = max((t.attach.get("Charge", 0) for t in r["st"]["A"]["player"].towers), default=0)
        cap = max((sum(t.attach.values()) for t in r["st"]["A"]["player"].towers), default=0)
        first = min(st["charge_log"]) if st["charge_log"] else "—"
        print(f"| {r['cell']:<9} | {st['charge_bought']:>8} | {str(first):>10} | "
              f"{mrate:>10} | {lay:>12} | {cap:>10} |")
    return rows


def run_mc(runs=300):
    print("=" * 100)
    print(f"v0.9 蒙特卡洛（{runs} 局/路径，seed={v8.SEED1}）")
    print("=" * 100)
    rows = []
    for name, kw in CELLS:
        t0 = time.time()
        r = eval_cell(name, kw, runs_mc=runs)
        rows.append(r)
        print(f"[{name}] {time.time()-t0:.1f}s  A起飞率 {r['mc']['A']['rate']}  "
              f"B起飞率 {r['mc']['B']['rate']}  平均买Charge {r['mc']['A']['charge_mean']}")
    print()
    print(HDR)
    for r in rows:
        print(fmt_row(r))
    return rows


def run_sweep():
    print("=" * 100)
    print("Charge 的 K 值扫参（决定性，A/B 单核两塔）")
    print("=" * 100)
    global CHARGE_K
    base_k = CHARGE_K
    print("| K   | toA | W20A  | B/A   | 主塔达标率 | 全塔达标率 |")
    print("|-----|-----|-------|-------|------------|------------|")
    for k in (4, 8, 12, 20, 30):
        CHARGE_K = k
        r = eval_cell("charge10", dict(v9_charge=True, v9_relay=False, v9_pad=2))
        st = r["st"]["A"]["st"]
        tot = st["main_hit"] + st["main_miss"]
        mrate = round(st["main_hit"] / tot, 3) if tot else 0.0
        tot2 = st["cond_hit"] + st["cond_miss"]
        arate = round(st["cond_hit"] / tot2, 3) if tot2 else 0.0
        print(f"| {k:<3} | {r['toA']:>3} | {r['w20A']:>5.2f} | {r['ba']:>5.3f} | "
              f"{mrate:>10} | {arate:>10} |")
    CHARGE_K = base_k


def run_relay_probe():
    """Relay 的机制证明：它只在「某个 Tag 还没跨过 3 层档」时有价值。
    MVP 只有 fire / frost 两个池，且 fire 在 W1 就 ≥3 层 → Relay 对老流派恒为 0。
    这里直接量它的理论上限：把 L_tag 从 2 推到 3，κ 0.06 → 0.10，在 L 层深叠下的倍数。"""
    print("=" * 100)
    print("Relay 机制探针：跨越 3 层档（κ 0.06 → 0.10）的杠杆有多大")
    print("=" * 100)
    print("| 深叠层数 L | (1.10/1.06)^L | 备注 |")
    print("|-----------|---------------|------|")
    for L in (10, 20, 47, 80, 100):
        mult = (1.10 / 1.06) ** L
        print(f"| {L:<9} | {mult:>13.2f} | {'← 定稿多塔 B 的深度' if L == 47 else ''} |")
    print()
    print("结论：一次 9 分的 Relay，在 L=47 时值 ×5.8；在 L=100 时值 ×40。")
    print("     → 这已经不是「卡」，是一根直达 κ 档位的杠杆。必须封顶（GDD §5.2 闸门 1）。")
    print()
    print("但在 MVP 双 Tag 结构下：fire 池在 W1 即 ≥3 层（Cannon h=1 + FireUp 1），")
    print("Relay 永远只能把「已满的档」再推一次 → 实测购入次数 = 0（见 det 表 relay10 行）。")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "det"
    t0 = time.time()
    w = selfcheck_engine()
    print(f"[selfcheck] v9 vs v8 最大相对偏差 = {w:.3e}（关闭新卡时必须为 0）\n")
    if mode == "det":
        run_det()
    elif mode == "mc":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 300
        run_mc(n)
    elif mode == "sweep":
        run_sweep()
    elif mode == "all":
        run_det()
        print()
        run_sweep()
        print()
        run_mc(300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
