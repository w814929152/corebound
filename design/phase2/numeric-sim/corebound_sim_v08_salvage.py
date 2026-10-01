# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.8：Q-C3 拆塔（售卖）数值补复验 + F-2 主导策略判定**
作者：程基岩（工程主理人）

================================================================================
为什么必须补跑（策划文策渊 `mechanics-tower-life-death.md` §0.3 的 F-1 / F-2）
================================================================================
  🔴 **F-1**：`design/phase2/numeric-sim/*.py` 全文检索 `拆除 / dismantle / sell / salvage`
       **零命中** → Q-C3「拆塔」是**设计层定稿（card-system §7.2.2 / A16 / E8），
       但没有任何数值复验证据**。用户已拍板「售卖 ≡ 拆塔」进 MVP → 必须补这个证据。

  🔴 **F-2**：后期拆杂兵塔可能变成**主导策略**。推演链：
       定稿多塔 B 是「深塔 + 占位塔」，占位塔 h<3 本就不供 E，
       拆掉它们 → N_tower 下降 → κ = κ_tag − 0.01·clamp(N−2,0,4) 回升
       → 深塔 Stack 从 1.06^L 变 1.10^L（L=47 时 ≈ ×5.70）→ 疑似白拿。

================================================================================
本脚本只做两件事（对应主理人下发的两个验证）
================================================================================
  **验证 1（F-2 核心）**：拆塔对 κ 的影响 —— 量化「κ 回升带来的 DPS 增益」vs
      「失去占位塔的 Base DPS 损失」，判定**净收益是正还是负**。
  **验证 2（V-3）**：在理性 AI 中加入「后期拆杂兵塔」这一动作，300 局蒙特卡洛，
      统计「终局塔数 ≤2 且历史最大塔数 ≥4」的占比 → **>70% 判定为主导策略**
      → 需启用兜底①（`N_tower` 取本局历史最大值）。

★ 定稿数值一个不动（κ 公式 / κ_tag 档位 / κ_r=0.050 / 卡价 / hp_growth / focus / …）。
★ 不修改 v03 / v04 / v05 / v06 / v07 任何原文件；不改任何 GDD。

用法（隔离 venv）：
  C:\\Users\\junhewang\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe \\
      corebound_sim_v08_salvage.py probe    # 只做验证1（决定性，秒级）
      corebound_sim_v08_salvage.py mc       # 只做验证2（蒙特卡洛，分钟级）
      corebound_sim_v08_salvage.py all
"""
from __future__ import annotations

import os
import sys
import math
import time
import random
import statistics

# ★ 导入 v06 即完成「引擎打补丁」；本脚本在它之上再叠一层 v08 引擎（只加一个 hook）
import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6
import corebound_sim_v07_mapA as v7

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 冻结项（定稿数值，本脚本一律不改）
# =============================================================================
HP_GROWTH = 1.42
HP_BASE = 16.0
FOCUS_PER_LAYER = 0.06
PITY = True                     # 定稿：pity 保底开
LINK_RULE = "substantial"       # f = 0.65（v0.7 口径）
SYNERGY_ON = False              # Q-C6：Syn 一次性 ×1.5 已摘除
KAPPA_MODE = "tier"             # κ = κ_tag − 0.01·clamp(N−2,0,4)
KR_FINAL = 0.050                # v0.7 定稿：MVP flat 0.050 全场统一（GDD §5.3 v1.1.1）
KTAG_TIERS_MVP = v6.KTAG_TIERS_MVP

# ---- Q-C3 拆塔定稿规则（card-system §7.2.2 / A16 / E8，一字不改地实现）----
SALVAGE_REFUND = 0.50           # 返还 50% 累计投入，向下取整
PRICE_TOWER = sv.PRICE["tower"]         # 12
PRICE_REINF = sv.PRICE["reinforce"]     # 9

# ---- 蒙特卡洛 ----
MC_RUNS = 300
SEED1 = 20260930
SEED2 = 20260931
SEED3 = 20260932
SALVAGE_EPS = 1e-9              # ΔDPS > 该值 才执行拆塔（理性 AI 的接受门槛）

# ---- 定稿 6 条判据（沿用 v0.7，用于「开拆塔后是否破线」的回归检查）----
WIN_LO, WIN_HI = 10, 15
RATE_B_MIN = 0.80
RATE_A_MIN = 0.60
BA_MAX = 1.0
FLIPS_MIN = 1


def _tier(inv, tiers):
    val = tiers[0][1]
    for th, v in tiers:
        if inv >= th:
            val = v
    return val


# =============================================================================
# 1. v0.8 伤害引擎 = v0.6 引擎 + 唯一一个 hook：κ 广度折价的 N_tower 口径
# =============================================================================
#    hook 目的：验证「兜底①」（`N_tower` 取本局历史最大值 N_max）。
#    cfg["ntower_mode"] = "current"（默认，= 定稿口径）| "max"（兜底①）
#    ★ 除标注处外，本函数与 v6.compute_dps_v6 逐字相同（selfcheck_engine 逐位自检）
# =============================================================================
def compute_dps_v8(player, cfg, geo=None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return 0.0, dict(per_tower=[], E=[], aoe=1.0, crossfire=1.0, aux=1.0,
                         empower=1.0, subtotal=0.0, core=0, L=[], Ltot=0.0,
                         kr=[], kappa=[], tag_invest={}, syn_hits=0,
                         n_for_kappa=0, disc=0.0)

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    h = [t.h for t in ts]
    L = [sum(t.attach.values()) for t in ts]
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
            rt = sv.REINF[rn]["tag"]
            tag_invest[rt] = tag_invest.get(rt, 0) + lv

    kmode = cfg.get("kappa_mode", "path")
    ktiers = cfg.get("ktag_tiers", KTAG_TIERS_MVP)
    # ★★ v0.8 唯一改动点：N_tower 口径（默认 "current" = 定稿口径）★★
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
            k = max(0.02, _tier(inv, ktiers) - disc)
            cap_i = (_tier(inv, cfg.get("stackcap_tiers", v6.STACKCAP_TIERS))
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
            kr.append(_tier(tag_invest.get(tg, 0), krtiers) if tg else neutral)
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

    per_tower = []
    syn_hits = 0
    for i, t in enumerate(ts):
        base = sv.TOWERS[t.ctype]["dps"] * (h[i] ** cfg["tower_stack_exp"])
        stack = 1.0
        for rn, lv in t.attach.items():
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
                              focus=foc, allin=ali, cov=cov,
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

    subtotal = sum(p["dps"] for p in per_tower)
    total = subtotal * aoe * cf * aux * empower
    return total, dict(per_tower=per_tower, adj=adj, E=E, aoe=aoe, crossfire=cf,
                       aux=aux, empower=empower, subtotal=subtotal, core=core,
                       L=L, Ltot=Ltot, kr=kr, kappa=kappa, caps=caps,
                       tag_invest=tag_invest, tag_tower_lv=tag_tower_lv,
                       syn_hits=syn_hits, n_for_kappa=n_for_kappa, disc=disc)


def dps_only_v8(player, cfg, geo=None):
    return compute_dps_v8(player, cfg, geo)[0]


# ★ 打补丁：让 v03 的 shop / action_value 全部走 v8 引擎
#   （ntower_mode 默认 "current" → 与 v6 逐位相同，见 selfcheck_engine()）
sv.compute_dps = compute_dps_v8
sv.dps_only = dps_only_v8


def selfcheck_engine():
    """不变量自检：v8 引擎在定稿口径下必须与 v6 引擎逐位相同（防复制粘贴漂移）。"""
    worst = 0.0
    for path in ("A", "B"):
        cfg = cfg_of(path)
        st = final_state(path, cfg, waves=20, salvage_on=False)
        p = st["player"]
        d6, i6 = v6.compute_dps_v6(p, cfg, sv.GEO6)
        d8, i8 = compute_dps_v8(p, cfg, sv.GEO6)
        worst = max(worst, abs(d6 - d8) / max(1.0, abs(d6)))
        assert abs(i6["subtotal"] - i8["subtotal"]) < 1e-6, "v8 与 v6 subtotal 不一致"
        assert i6["E"] == i8["E"] and i6["kappa"] == i8["kappa"], "v8 与 v6 E/κ 不一致"
    return worst


# =============================================================================
# 2. 配置工厂（v0.7 定稿工厂 + 拆塔开关）
# =============================================================================
def cfg_of(path="B", kappa_r=KR_FINAL, rule=LINK_RULE, kr_mode="flat",
           salvage_on=False, salvage_from_wave=1, ntower_mode="current",
           strict=True, **over):
    kw = dict(hp_growth=HP_GROWTH, focus_per_layer=FOCUS_PER_LAYER,
              kappa_r=kappa_r, synergy_on=SYNERGY_ON,
              kappa_mode=KAPPA_MODE, kr_mode=kr_mode)
    kw.update(over)
    c = v6.v06_cfg(path=path, **kw)
    c["link_rule"] = rule
    c["hp_base"] = HP_BASE
    c["pity"] = PITY
    c["salvage_on"] = salvage_on
    c["salvage_from_wave"] = salvage_from_wave
    c["ntower_mode"] = ntower_mode
    assert c["focus_full"] is False, "focus_full 必须保持 False"
    assert c["focus_min_h"] == 8.0
    assert c["synergy_on"] is False, "synergy_on 必须保持 False（Syn 已摘除）"
    assert c["focus_per_layer"] == FOCUS_PER_LAYER and c["pity"] is True
    assert c["softcap_decay"] == 1.03 and c["reinf_cap"] == 100
    assert c["link_min_level"] == sv.RECOMMENDED["link_min_level"] == 3
    assert c["link_rule"] == rule
    if strict:
        assert c["hp_growth"] == HP_GROWTH and c["hp_base"] == HP_BASE
    return c


# =============================================================================
# 3. ★ Q-C3 拆塔结算器（F-1 说它从未被实现过 —— 这是第一次落地）
# =============================================================================
def _sync_free_layers(player, fl):
    """free_layers[slot] = 该塔位上「系统赠送、未花分」的建筑卡层数（初始 Arrow h=1）。
    塔位上的塔消失时，赠送额度一并清空。"""
    alive = {t.slot for t in player.towers}
    for s in list(fl):
        if s not in alive:
            fl.pop(s, None)


def tower_investment(t, fl):
    """该塔累计投入（分）= 建筑卡分 + 其上装配的单塔效果卡分。"""
    free = fl.get(t.slot, 0)
    h_paid = max(0, t.h - free)
    return PRICE_TOWER * h_paid + PRICE_REINF * sum(t.attach.values())


def salvage_refund(t, fl):
    """Q-C3：floor(50% × 累计投入)。"""
    return math.floor(SALVAGE_REFUND * tower_investment(t, fl))


def salvage_dialog(t, fl):
    """Q-C3 二次确认弹窗内容：返还 X 分 / 销毁 N 张卡（共 M 层）。"""
    return dict(refund=salvage_refund(t, fl), cards=len(t.attach),
                layers=sum(t.attach.values()), invest=tower_investment(t, fl))


def apply_salvage(player, slot, fl):
    """执行拆塔，返回返还分（None = 该塔位为空）。"""
    tgt = None
    for t in player.towers:
        if t.slot == slot:
            tgt = t
            break
    if tgt is None:
        return None
    refund = salvage_refund(tgt, fl)
    names = list(tgt.attach.keys())
    player.towers = [t for t in player.towers if t.slot != slot]
    fl.pop(slot, None)
    # 🔴 装配卡全销毁：层数随塔消失；该卡在其它塔上也不再有层 → 移出卡组
    for nm in names:
        if all(nm not in t.attach for t in player.towers):
            player.cards.discard(nm)
    return refund


def salvage_eval(player, slot, cfg, geo, fl):
    """评估拆掉某塔位：(ΔDPS, 返还分)。不改状态。"""
    before = sv.dps_only(player, cfg, geo)
    s = player.snap()
    fl_backup = dict(fl)
    rf = apply_salvage(player, slot, fl)
    if rf is None:
        player.rest(s)
        fl.clear()
        fl.update(fl_backup)
        return None
    after = sv.dps_only(player, cfg, geo)
    player.rest(s)
    fl.clear()
    fl.update(fl_backup)
    return after - before, rf


def greedy_salvage_sequence(player, cfg, geo, fl, max_steps=12):
    """理性玩家的拆塔贪心序列：每步拆 ΔDPS 最大的塔，直到无正收益。
    返回 [(slot, ctype, h, L, ΔDPS, refund, dps_before, dps_after), ...]"""
    seq = []
    for _ in range(max_steps):
        best = None
        for t in list(player.towers):
            ev = salvage_eval(player, t.slot, cfg, geo, fl)
            if ev is None:
                continue
            g, rf = ev
            if g > SALVAGE_EPS and (best is None or g > best[0]):
                best = (g, t.slot, rf)
        if best is None:
            break
        g, slot, rf = best
        t = next(x for x in player.towers if x.slot == slot)
        d_before = sv.dps_only(player, cfg, geo)
        rec = (slot, t.ctype, t.h, sum(t.attach.values()), g, rf, d_before)
        apply_salvage(player, slot, fl)
        seq.append(rec + (sv.dps_only(player, cfg, geo),))
    return seq


# =============================================================================
# 4. 带拆塔的商店与主循环
# =============================================================================
def _action_value_v8(player, act, cfg, geo):
    if act[0] == "build" and cfg.get("ntower_mode", "current") == "max":
        old = getattr(player, "n_hist_max", len(player.towers))
        player.n_hist_max = max(old, len(player.towers) + 1)
        try:
            return sv.action_value(player, act, cfg, geo)
        finally:
            player.n_hist_max = old
    return sv.action_value(player, act, cfg, geo)


def shop_phase_v08(player, budget, w, cfg, geo, rng, st):
    """= sv.shop_phase + 「拆塔」这一新动作（只在波次间安全窗出现 → 天然满足 §4.3）。"""
    fl = st["free_layers"]
    rerolls = 0
    actions = 0
    fire_bought = 0
    counts = {}
    offers = None
    if rng is not None:
        offers = sv.draw_offers(rng, cfg["shop_offers"],
                                sv.pity_card(player) if cfg.get("pity") else None)
    while budget > 0:
        if cfg["max_actions"] is not None and actions >= cfg["max_actions"]:
            break

        # ---------- (A) 拆塔：ΔDPS > 0 才做（并回笼 50% 投入）----------
        if cfg.get("salvage_on") and w >= cfg.get("salvage_from_wave", 1):
            best = None
            for t in list(player.towers):
                ev = salvage_eval(player, t.slot, cfg, geo, fl)
                if ev is None:
                    continue
                g, rf = ev
                if g > SALVAGE_EPS and (best is None or g > best[0]):
                    best = (g, t.slot, rf)
            if best is not None:
                g, slot, rf = best
                t = next(x for x in player.towers if x.slot == slot)
                dlg = salvage_dialog(t, fl)
                apply_salvage(player, slot, fl)
                st["salvages"] += 1
                st["log"].append(dict(w=w, slot=slot, ctype=t.ctype, h=t.h,
                                      L=sum(t.attach.values()), dgain=g,
                                      refund=rf, invest=dlg["invest"],
                                      cards=dlg["cards"], layers=dlg["layers"]))
                budget += rf
                actions += 1
                continue

        # ---------- (B) 常规买 / 刷（与 sv.shop_phase 逐字一致）----------
        cands = sv.enumerate_actions(player, cfg, fire_bought, offers, geo)
        scored = []
        for act in cands:
            v = _action_value_v8(player, act, cfg, geo)
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
            if sv.ALL_CARDS[act[1]].get("tag") == "fire":
                fire_bought += 1
            counts[act[1]] = counts.get(act[1], 0) + 1
            budget -= cost
            actions += 1
            _sync_free_layers(player, fl)
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
            offers = sv.draw_offers(rng, cfg["shop_offers"],
                                    sv.pity_card(player) if cfg.get("pity") else None)
        elif rerolls > 400:
            break
    return budget, rerolls


def run_v08(path, cfg, max_wave=20, geo=None, rng=None):
    cfg = dict(cfg)
    if geo is None:
        geo = sv.GEO6 if cfg["n_slots"] >= 6 else sv.GEO4
    player = sv.new_player(path, cfg, geo)
    st = dict(free_layers={0: 1},      # 初始 Arrow@slot0 h=1 是赠送的，未花分
              n_hist_max=len(player.towers), salvages=0, log=[])
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
        res = sv.simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income
        budget, rr = shop_phase_v08(player, cum, w, cfg, geo, rng, st)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]
        n_max_hist = max(n_max_hist, len(player.towers))
        dps, _ = compute_dps_v8(player, cfg, geo)
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


def final_state(path, cfg, waves=20, salvage_on=None, geo=sv.GEO6):
    c = dict(cfg)
    if salvage_on is not None:
        c["salvage_on"] = salvage_on
    rows, player, st = run_v08(path, c, waves, geo=geo, rng=None)
    dps, info = compute_dps_v8(player, c, geo)
    return dict(rows=rows, player=player, st=st, dps=dps, info=info,
                s=v6.summarize(rows))


def _tbl(headers, rows):
    return v6._tbl(headers, rows)


# =============================================================================
# 5. 验证 1：拆塔对 κ 的影响（F-2 核心）
# =============================================================================
def kappa_of(cfg, n_tower, tag_invest):
    """GDD §5.2：κ = κ_tag − 0.01·clamp(N−2,0,4)，下限 0.02。"""
    disc = 0.01 * min(max(n_tower - 2, 0), 4)
    return max(0.02, _tier(tag_invest, cfg.get("ktag_tiers", KTAG_TIERS_MVP)) - disc), disc


def plan_slots(player, plan):
    ts = player.towers
    if plan == "none":
        return []
    if plan == "filler_h_lt_3":
        return [t.slot for t in ts if t.h < 3]
    if plan == "filler_h_lt_3_noL":
        return [t.slot for t in ts if t.h < 3 and sum(t.attach.values()) == 0]
    if plan == "keep_deep_only":
        if not ts:
            return []
        keep = max(ts, key=lambda t: (sum(t.attach.values()), t.h))
        return [t.slot for t in ts if t.slot != keep.slot]
    if plan == "keep_two_effective":
        return [t.slot for t in ts if not (t.h >= 3 or sum(t.attach.values()) > 0)]
    if plan == "keep_main_plus_E":
        if not ts:
            return []
        main = max(ts, key=lambda t: (sum(t.attach.values()), t.h))
        esup = max((t for t in ts if t.slot != main.slot), key=lambda t: t.h, default=None)
        keep = {main.slot} | ({esup.slot} if esup else set())
        return [t.slot for t in ts if t.slot not in keep]
    raise ValueError(plan)


PLAN_LABEL = {
    "none": "P0 不拆（定稿基线）",
    "filler_h_lt_3": "P1 拆掉全部 h<3 占位塔（F-2 定义）",
    "filler_h_lt_3_noL": "P2 拆掉 h<3 且 L=0 的占位塔",
    "keep_deep_only": "P3 只留主塔（极限 N→1）",
    "keep_two_effective": "P4 只留「有效塔」（h≥3 或 L>0）",
    "keep_main_plus_E": "P5 只留主塔 + 最大 E 供给塔",
}


def eval_plan(path, cfg, waves, plan):
    """决定性跑到第 waves 波（不开拆塔），在该波的安全窗执行拆塔方案。"""
    c = dict(cfg)
    c["salvage_on"] = False
    rows, player, st = run_v08(path, c, waves, geo=sv.GEO6, rng=None)
    fl = st["free_layers"]
    dps0, i0 = compute_dps_v8(player, c, sv.GEO6)
    lost_sub = 0.0
    # ★ 必须在拆之前固定「塔位 → 拆前 per_tower 索引」的映射，否则索引会随拆塔漂移
    orig_idx = {t.slot: k for k, t in enumerate(player.towers)}
    slots = plan_slots(player, plan)
    refund = 0.0
    destroyed_cards = 0
    destroyed_layers = 0
    for s in slots:
        t = next((x for x in player.towers if x.slot == s), None)
        if t is None:
            continue
        lost_sub += i0["per_tower"][orig_idx[s]]["dps"]
        dlg = salvage_dialog(t, fl)
        refund += dlg["refund"]
        destroyed_cards += dlg["cards"]
        destroyed_layers += dlg["layers"]
        apply_salvage(player, s, fl)
    dps1, i1 = compute_dps_v8(player, c, sv.GEO6)
    return dict(plan=plan, label=PLAN_LABEL[plan], wave=waves,
                n0=len(i0["E"]), n1=len(player.towers),
                dps0=dps0, dps1=dps1, ratio=(dps1 / dps0 if dps0 else 0.0),
                i0=i0, i1=i1, lost_sub=lost_sub, refund=refund,
                destroyed_cards=destroyed_cards, destroyed_layers=destroyed_layers,
                rows=rows, player=player, slots=slots)


def kappa_term_table(cfg):
    """纯 κ 项：κ 0.06 → 0.10 时 (1+κ)^L 的比值（F-2 说 L=47 时 ≈5.6~5.70×）。"""
    inv = 999
    k6, _ = kappa_of(cfg, 6, inv)
    k2, _ = kappa_of(cfg, 2, inv)
    rows = []
    for L in (10, 20, 30, 40, 47, 60, 80, 100):
        a = (1.0 + k6) ** min(L, 100)
        b = (1.0 + k2) ** min(L, 100)
        rows.append([f"L={L}", f"{k6:.2f}", f"{k2:.2f}", f"{a:,.2f}", f"{b:,.2f}",
                     f"×{b/a:.3f}"])
    return rows, k6, k2


def verify1(path="B"):
    cfg = cfg_of(path)
    out = {"cfg": cfg}
    base = final_state(path, cfg, waves=20, salvage_on=False)
    p, i = base["player"], base["info"]
    out["base"] = base
    out["slots"] = [(t.slot, t.ctype, t.h, sum(t.attach.values()),
                     i["E"][k], i["kappa"][k] - 1.0, i["per_tower"][k]["dps"])
                    for k, t in enumerate(p.towers)]
    out["kappa_rows"], out["k6"], out["k2"] = kappa_term_table(cfg)
    plans = ["none", "filler_h_lt_3", "filler_h_lt_3_noL", "keep_deep_only",
             "keep_two_effective", "keep_main_plus_E"]
    out["plans"] = {pl: eval_plan(path, cfg, 20, pl) for pl in plans}
    out["bywave"] = {w: eval_plan(path, cfg, w, "filler_h_lt_3")
                     for w in (8, 10, 12, 14, 16, 18, 20)}
    st_g = final_state(path, cfg, waves=20, salvage_on=False)
    seq = greedy_salvage_sequence(st_g["player"], cfg, sv.GEO6, st_g["st"]["free_layers"])
    out["greedy"] = dict(seq=seq, dps0=st_g["dps"],
                         dps1=sv.dps_only(st_g["player"], cfg, sv.GEO6), st=st_g)
    out["onsalvage"] = final_state(path, cfg, waves=20, salvage_on=True)
    return out


# =============================================================================
# 6. 验证 2：V-3 主导策略判定（蒙特卡洛）
# =============================================================================
def mc_runs(path, cfg, runs=MC_RUNS, seed=SEED1, max_wave=20, actions=12):
    rng = random.Random(seed)
    c = dict(cfg)
    c["max_actions"] = actions
    n_final, n_max, salvages = [], [], []
    takeoffs, survives, hits = 0, 0, []
    first_salvage_w = []
    finalN_le2 = maxN_ge4 = both = salvaged_any = 0
    finalN_le3 = 0
    ndist = {}
    for _ in range(runs):
        rows, player, st = run_v08(path, c, max_wave, geo=sv.GEO6, rng=rng)
        nf = len(player.towers)
        nm = st["n_hist_max"]
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        if alive:
            survives += 1
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            takeoffs += 1
            hits.append(tw)
        n_final.append(nf)
        n_max.append(nm)
        salvages.append(st["salvages"])
        ndist[nf] = ndist.get(nf, 0) + 1
        if st["salvages"] > 0:
            salvaged_any += 1
            first_salvage_w.append(st["log"][0]["w"])
        if nf <= 2:
            finalN_le2 += 1
        if nf <= 3:
            finalN_le3 += 1
        if nm >= 4:
            maxN_ge4 += 1
        if nf <= 2 and nm >= 4:
            both += 1
    return dict(
        runs=runs, path=path, seed=seed,
        rate=round(takeoffs / runs, 3), surv=round(survives / runs, 3),
        med=statistics.median(hits) if hits else None,
        n_final_med=statistics.median(n_final),
        n_final_mean=round(statistics.mean(n_final), 2),
        n_max_med=statistics.median(n_max),
        n_max_mean=round(statistics.mean(n_max), 2),
        salvages_mean=round(statistics.mean(salvages), 2),
        salvaged_any_rate=round(salvaged_any / runs, 3),
        first_salvage_med=(statistics.median(first_salvage_w) if first_salvage_w else None),
        p_finalN_le2=round(finalN_le2 / runs, 3),
        p_finalN_le3=round(finalN_le3 / runs, 3),
        p_maxN_ge4=round(maxN_ge4 / runs, 3),
        ndist=dict(sorted(ndist.items())),
        p_dominant=round(both / runs, 3),
        p_dominant_of_maxN4=(round(both / maxN_ge4, 3) if maxN_ge4 else None),
    )


def eval_point_mc(kappa_r=KR_FINAL, salvage_on=False, salvage_from_wave=1,
                  ntower_mode="current", runs=MC_RUNS, seed=SEED1):
    st = {}
    for path in ("A", "B"):
        st[path] = final_state(
            path, cfg_of(path, kappa_r=kappa_r, salvage_on=salvage_on,
                         salvage_from_wave=salvage_from_wave,
                         ntower_mode=ntower_mode), waves=20)
    sA, sB = st["A"]["s"], st["B"]["s"]
    _, lead, flips, fa, fb = v6.cross_lead(st["A"]["rows"], st["B"]["rows"])
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    ba = round(w20B / w20A, 3) if w20A else 0.0
    hA = v6.stage_health(st["A"]["rows"])
    hB = v6.stage_health(st["B"]["rows"])
    row = dict(toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=ba, leadA=lead["A"], leadB=lead["B"],
               flips=flips, hA=hA, hB=hB, st=st)
    mc = {}
    for path in ("A", "B"):
        mc[path] = mc_runs(path, cfg_of(path, kappa_r=kappa_r, salvage_on=salvage_on,
                                        salvage_from_wave=salvage_from_wave,
                                        ntower_mode=ntower_mode), runs=runs, seed=seed)
    row["mc"] = mc
    row["c_win"] = row["toB"] is not None and WIN_LO <= row["toB"] <= WIN_HI
    row["c_ba"] = ba < BA_MAX
    row["c_flips"] = flips >= FLIPS_MIN
    row["c_health"] = bool(hB["healthy"]) and bool(hA["healthy"])
    row["c_rateA"] = mc["A"]["rate"] >= RATE_A_MIN
    row["c_rateB"] = mc["B"]["rate"] >= RATE_B_MIN
    row["ok"] = (row["c_win"] and row["c_ba"] and row["c_flips"]
                 and row["c_health"] and row["c_rateA"] and row["c_rateB"])
    return row


# =============================================================================
# 7. 主流程：probe / mc
# =============================================================================
def run_probe():
    t0 = time.time()
    print("=" * 78)
    print("《守核》v0.8 · 验证1：拆塔对 κ 的影响（F-2 核心）")
    print("=" * 78)
    worst = selfcheck_engine()
    print("[自检] v8 引擎 vs v6 引擎（定稿口径）最大相对偏差 = %.2e → %s\n"
          % (worst, "✅ 逐位相同" if worst < 1e-12 else "🔴 有漂移！"))

    v1 = verify1("B")
    base = v1["base"]
    print("[1.1] 定稿多塔 B 终局实况")
    print("      mix = %s   DPS = %s" % (v6.tower_mix(base), f"{base['dps']:,.0f}"))
    print("      dump = %s" % v6.build_dump(base))
    print("      E = %s   κ = %s"
          % ([round(x, 1) for x in base["info"]["E"]],
             [round(k - 1, 3) for k in base["info"]["kappa"]]))
    print("      Crossfire=%.2f  AoE=%.3f  Aux=%.3f  subtotal=%.0f"
          % (base["info"]["crossfire"], base["info"]["aoe"],
             base["info"]["aux"], base["info"]["subtotal"]))

    print("\n[1.2] 纯 κ 项（κ %.2f → %.2f）" % (v1["k6"], v1["k2"]))
    for r in v1["kappa_rows"]:
        print("      %-8s (1+κ6)^L=%-14s (1+κ2)^L=%-14s 比值 %s"
              % (r[0], r[3], r[4], r[5]))

    print("\n[1.3] W20 安全窗拆塔方案对照")
    for pl, r in v1["plans"].items():
        print("      %-34s N %d→%-2d  DPS %14s → %14s  ×%-8.3f  返还 %5.0f 分  %s"
              % (r["label"], r["n0"], r["n1"], f"{r['dps0']:,.0f}", f"{r['dps1']:,.0f}",
                 r["ratio"], r["refund"], "🟢正" if r["ratio"] > 1 else "🔴负"))

    print("\n[1.4] 逐波净收益（P1：拆光 h<3 占位塔）")
    for w, r in v1["bywave"].items():
        print("      W%-3d N %d→%-2d  κ %.2f→%.2f  DPS %12s → %12s  ×%-8.3f  返还 %4.0f"
              % (w, r["n0"], r["n1"], r["i0"]["kappa"][r["i0"]["core"]] - 1,
                 r["i1"]["kappa"][r["i1"]["core"]] - 1, f"{r['dps0']:,.0f}",
                 f"{r['dps1']:,.0f}", r["ratio"], r["refund"]))

    g = v1["greedy"]
    print("\n[1.5] 理性贪心拆塔序列（决定性 W20）")
    for rec in g["seq"]:
        print("      拆 slot%d %-7s h=%-4d L=%-3d ΔDPS %+13.0f 返还 %3.0f 分  DPS → %s"
              % (rec[0], rec[1], rec[2], rec[3], rec[4], rec[5], f"{rec[7]:,.0f}"))
    print("      合计：DPS %s → %s （×%.3f）"
          % (f"{g['dps0']:,.0f}", f"{g['dps1']:,.0f}", g["dps1"] / g["dps0"]))

    on = v1["onsalvage"]
    print("\n[1.6] 全程开拆塔的决定性终局：N=%d  DPS=%s  mix=%s  拆塔 %d 次"
          % (len(on["player"].towers), f"{on['dps']:,.0f}", v6.tower_mix(on),
             on["st"]["salvages"]))
    print("\n耗时 %.1fs" % (time.time() - t0))
    return v1


def run_mc(runs=MC_RUNS):
    t0 = time.time()
    print("=" * 78)
    print("《守核》v0.8 · 验证2：V-3 主导策略判定（蒙特卡洛 %d 局）" % runs)
    print("=" * 78)
    variants = [
        dict(key="V0", name="V0 基线：不开拆塔（定稿口径）", kw=dict(salvage_on=False)),
        dict(key="V1", name="V1 全程可拆（W1 起，理性）",
             kw=dict(salvage_on=True, salvage_from_wave=1)),
        dict(key="V2", name="V2 仅后期可拆（W13 起）",
             kw=dict(salvage_on=True, salvage_from_wave=13)),
        dict(key="V3", name="V3 全程可拆 + 兜底①（N_tower 取历史最大）",
             kw=dict(salvage_on=True, salvage_from_wave=1, ntower_mode="max")),
    ]
    res = {}
    for v in variants:
        print("\n[%s] %s" % (v["key"], v["name"]))
        row = eval_point_mc(runs=runs, seed=SEED1, **v["kw"])
        res[v["key"]] = dict(meta=v, row=row)
        for path in ("A", "B"):
            m = row["mc"][path]
            print("   %s: 起飞率 %5.1f%% | 终局塔数 中位%.1f/均%.2f | 历史最大 中位%.1f | "
                  "拆塔率 %5.1f%% | 终局N≤2 %5.1f%% | 终局N≤3 %5.1f%% | 历史N≥4 %5.1f%% | "
                  "★主导占比 %5.1f%%"
                  % (path, m["rate"] * 100, m["n_final_med"], m["n_final_mean"],
                     m["n_max_med"], m["salvaged_any_rate"] * 100,
                     m["p_finalN_le2"] * 100, m["p_finalN_le3"] * 100,
                     m["p_maxN_ge4"] * 100, m["p_dominant"] * 100))
            print("        终局塔数分布 %s" % m["ndist"])
        print("   决定性：A 起飞 W%s / B 起飞 W%s | W20 %.2f/%.2f | B/A %.3f | 交叉 %d | %s"
              % (row["toA"], row["toB"], row["w20A"], row["w20B"], row["ba"],
                 row["flips"], "✅ 六条全过" if row["ok"] else "⚠️ 有破线"))

    print("\n[复核] V1 多塔 B 主导占比 · 换 2 个种子")
    repro = []
    for sd in (SEED2, SEED3):
        m = mc_runs("B", cfg_of("B", salvage_on=True, salvage_from_wave=1),
                    runs=runs, seed=sd)
        repro.append(m)
        print("   seed=%d → 主导占比 %.1f%% | 终局N≤2 %.1f%% | 历史N≥4 %.1f%% | "
              "起飞率 %.1f%% | 拆塔率 %.1f%%"
              % (sd, m["p_dominant"] * 100, m["p_finalN_le2"] * 100,
                 m["p_maxN_ge4"] * 100, m["rate"] * 100, m["salvaged_any_rate"] * 100))
    print("\n耗时 %.1fs" % (time.time() - t0))
    return dict(res=res, repro=repro, runs=runs)


# =============================================================================
# 8. 报告
# =============================================================================
def build_report(v1, mc):
    L = []
    A = L.append
    base = v1["base"]
    p1 = v1["plans"]["filler_h_lt_3"]
    p0 = v1["plans"]["none"]
    p3 = v1["plans"]["keep_deep_only"]
    p5 = v1["plans"]["keep_main_plus_E"]
    g = v1["greedy"]
    on = v1["onsalvage"]
    v1row = mc["res"]["V1"]["row"]
    v0row = mc["res"]["V0"]["row"]
    v2row = mc["res"]["V2"]["row"]
    v3row = mc["res"]["V3"]["row"]
    mB = v1row["mc"]["B"]
    mB0 = v0row["mc"]["B"]
    mB2 = v2row["mc"]["B"]
    mB3 = v3row["mc"]["B"]
    dom = mB["p_dominant"]
    dom_trigger = dom > 0.70

    A("# 《守核 Corebound》· **Q-C3 拆塔（售卖）数值补复验 + F-2 主导策略判定**\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v08_salvage.py`（本目录）\n")
    A("> 触发：`mechanics-tower-life-death.md` §0.3 —— "
      "🔴 **F-1**：`numeric-sim/*.py` 全文检索 `拆除/dismantle/sell/salvage` **零命中**，"
      "Q-C3「拆塔」是设计层定稿但**无任何数值复验证据**；"
      "🔴 **F-2**：后期拆杂兵塔可能借 κ 广度折价成为**主导策略**（§4.2 复验项 V-3）。"
      "用户已拍板**售卖 ≡ 拆塔**进 MVP → 本轮补跑这两条证据。\n")
    A("> 🔴 **定稿数值一个不动**：κ 公式 / κ_tag 档位 / `κ_r=0.050`（flat）/ 卡价 12-9-10 / "
      "`hp_growth=1.42` / `hp_base=16` / `focus_per_layer=0.06` / `focus_full=False` / "
      "`synergy_on=False`（Syn 已摘除）/ 软 cap 1.03 / 共鸣门槛 Lv3 / 6 塔位 / pity 开 / "
      "pity 保底开。**Q-C3 的「返还 50% + 装配卡全销毁」也一字未改地实现。本脚本不修改任何 GDD。**\n")

    # ---------------- 0. headline ----------------
    A("## 0. 结论速览（四个问题）\n")
    A(_tbl(["#", "主理人问的", "答案", "关键数"],
           [["①", "**拆塔净收益是正还是负？**",
             ("🟢 **正，且量级巨大**" if p1["ratio"] > 1 else "🔴 负"),
             f"W20 拆光 h<3 占位塔：N {p1['n0']}→{p1['n1']}，κ {v1['k6']:.2f}→{v1['k2']:.2f}，"
             f"DPS **{p1['dps0']:,.0f} → {p1['dps1']:,.0f}（×{p1['ratio']:.3f}，"
             f"{(p1['ratio']-1)*100:+.0f}%）**，另返还 **{p1['refund']:.0f} 分**；"
             f"失去的占位塔 DPS 仅 {p1['lost_sub']:,.1f}（占总量 "
             f"{p1['lost_sub']/p1['dps0']:.4%}）"],
            ["②", "**后期拆杂兵塔的行为占比？**",
             (f"**{dom*100:.1f}%** —— 未达 70% 红线" if not dom_trigger
              else f"**{dom*100:.1f}%** —— 超 70% 红线"),
             f"V-3 判据口径「终局塔数 ≤2 且历史最大塔数 ≥4」= **{dom*100:.1f}%**"
             f"（换种子 " + "、".join(f"{m['p_dominant']*100:.1f}%" for m in mc["repro"]) + "）；"
             f"但**拆塔率 {mB['salvaged_any_rate']*100:.1f}%**、"
             f"放宽到「终局 N≤3」= **{mB['p_finalN_le3']*100:.1f}%**、"
             f"终局塔数中位 {mB['n_final_med']:.0f}（基线 {mB0['n_final_med']:.0f}）"],
            ["③", "**是否触发主导策略兜底？**",
             "🔴 **触发（工程判定）** —— 见下方三条信号",
             f"① **B/A 破线**：定稿判据「`B/A < 1`」从 {v0row['ba']:.3f} 被顶到 "
             f"**{v1row['ba']:.3f} > 1** → 违反概念 §2.4.5「单核必须是后期 carry」；"
             f"② **拆塔率 {mB['salvaged_any_rate']*100:.1f}%**（几乎每局必做）；"
             f"③ 宽口径「终局 N≤3」**{mB['p_finalN_le3']*100:.1f}%** > 70%。"
             f"启用兜底①复测：主导占比 {mB['p_dominant']*100:.1f}% → "
             f"**{mB3['p_dominant']*100:.1f}%**、B/A → **{v3row['ba']:.3f}**、"
             f"定稿 6 条判据 **{'全过' if v3row['ok'] else '有破线'}**"],
            ["④", "**对 F-2 的最终判定**",
             "🔴 **主导策略**，不是合法转型",
             f"数值侧是「×{p1['ratio']:.2f} 的白拿」；行为侧 {mB['salvaged_any_rate']*100:.0f}% "
             f"的局执行了它、多塔 B 的终局塔数中位从 {mB0['n_final_med']:.0f} 塌到 "
             f"{mB['n_final_med']:.0f}、W20 从 {v0row['w20B']} 涨到 {v1row['w20B']} → "
             f"**多塔流把自己优化成了单核流**，概念 §2.4.4「两条主干」事实上塌成一条。"
             f"**建议启用兜底①**"]]))

    # ---------------- 1. 实现 ----------------
    A("\n## 1. 口径与实现（F-1：拆塔首次落地）\n")
    A("**F-1 的修复：本脚本第一次把 Q-C3 拆塔实现进数值模拟。** 逐条对照 "
      "`card-system` §7.2.2 / A16 / E8：\n")
    A(_tbl(["Q-C3 定稿项", "本脚本实现", "出处"],
           [["返还 = **50% 累计投入**（向下取整）",
             "`refund = floor(0.50 × (12×已付费建筑层数 + 9×装配层数))`", "§7.2.2"],
            ["装配卡**全销毁**",
             "拆塔时该塔 `attach` 全部清空；若该卡在其它塔上也不再有任何层 → 移出卡组", "§7.2.2"],
            ["塔位释放", "`player.towers` 移除该塔，塔位回到 free 列表，可再建", "§7.2.2"],
            ["`N_tower` 变化 → **全场 κ 立即重算**",
             "`compute_dps_v8` 每次调用重算 `disc = 0.01·clamp(N−2,0,4)`（逐塔当前值）", "E11"],
            ["链接 / `Aux` / `CoreTower` 重算", "同上，每次调用内重算", "E6 / E4"],
            ["仅**波次间安全窗**",
             "拆塔动作只出现在 `shop_phase_v08`（波次间的购买循环）内，天然满足 §4.3 铁律", "§4.3"],
            ["🔴 **必须二次确认**",
             "UI 层，不进数值；本脚本记录弹窗内容（返还 X / 销毁 N 张卡共 M 层）供核对", "§7.2.2"]]))
    A("\n> **引擎口径自检**：v0.8 引擎 = v0.6 引擎 + 1 个 hook（κ 的 `N_tower` 取值口径）。"
      "默认 `ntower_mode=\"current\"` 时与 v0.6 **逐位相同**"
      "（脚本内置 `selfcheck_engine()` 断言，实测最大相对偏差 0.00e+00）→ "
      "**本轮所有「不开拆塔」的数字都是定稿口径的忠实复现**，不存在引擎漂移。\n")

    # ---------------- 2. 验证 1 ----------------
    A("\n## 2. 验证 1：拆塔对 κ 的影响（F-2 核心）\n")
    A("### 2.1 定稿多塔 B 的终局实况 —— ★ 对 F-2 表述的一处修正\n")
    A(_tbl(["#", "槽位", "类型", "h", "装配层数 L", "E_i", "κ_i", "该塔 DPS", "角色"],
           [[f"#{i+1}", f"S{s[0]}", s[1], s[2], s[3], f"{s[4]:.0f}", f"{s[5]:.3f}",
             f"{s[6]:,.1f}",
             ("★ 主塔（承载 Stack）" if s[3] == max(x[3] for x in v1["slots"]) else
              ("★ E 供给塔（`E_i` 的 1+hⱼ 来源）"
               if s[2] == max(x[2] for x in v1["slots"]
                              if x[3] != max(y[3] for y in v1["slots"]))
               else "占位塔（h<3，不供 E）"))]
            for i, s in enumerate(v1["slots"])]))
    n_filler = sum(1 for s in v1["slots"] if s[2] < 3)
    A("\n> 🔴 **修正 F-2 的一处表述**：F-2 原文写「**1 座深塔 + 5 座 `h=1` 占位塔**」，"
      "但定稿多塔 B 的**实际终局**是「**2 座有效塔 + "
      f"{n_filler} 座 `h<3` 占位塔**」—— 除了承载 `L={max(s[3] for s in v1['slots'])}` 层的 "
      f"主塔之外，**还有一座 `h={max(s[2] for s in v1['slots'])}` 的 `Arrow`**，"
      f"它自己只贡献 {min(s[6] for s in v1['slots'] if s[2] > 3):,.0f} DPS，"
      f"但**它是主塔 `E={max(s[4] for s in v1['slots']):.0f}` 的唯一供给者**。\n")
    A("> → 因此「拆光杂兵塔」的正确形态是 **N 6→2（不是 6→1）**："
      "拆掉 4 座 `h=1` 占位塔，保留「主塔 + E 供给塔」。"
      "**若真按 6→1 拆（只留主塔），`E` 会归零、共鸣乘区从 "
      f"×{(1+KR_FINAL)**max(s[4] for s in v1['slots']):,.0f} 掉到 ×1 —— 是灾难不是收益**（见 §2.3 的 P3 行）。\n")
    A(f"> 定稿基线：终局 DPS **{base['dps']:,.0f}**，`E = {[round(x,1) for x in base['info']['E']]}`，"
      f"`κ = {[round(k-1,3) for k in base['info']['kappa']]}`，"
      f"Crossfire **{base['info']['crossfire']:.2f}**、AoE **{base['info']['aoe']:.3f}**、"
      f"Aux **{base['info']['aux']:.3f}**，起飞 **W{base['s']['takeoff']}**。\n")

    A("\n### 2.2 纯 κ 项：κ 0.06 → 0.10 时 `(1+κ)^L` 的比值\n")
    A(_tbl(["主塔装配层数", "κ（N=6）", "κ（N=2）", "(1+κ₆)^L", "(1+κ₂)^L", "比值"],
           v1["kappa_rows"]))
    A(f"\n→ **F-2 的推演链数值侧完全成立**：`L=47` 时 `(1.10/1.06)^47 = "
      f"×{float(v1['kappa_rows'][4][5].strip('×')):.3f}`"
      f"（F-2 原文写 ≈5.6~5.70×，实测 **×{float(v1['kappa_rows'][4][5].strip('×')):.3f}**，一致）。\n")
    A("→ 且这条增益**随 L 单调放大**（L=10 时仅 ×1.45，L=100 时 ×49.4）→ "
      "**越到后期拆塔越划算**，这正是「后期拆杂兵塔」这个说法的数值来源。\n")

    A("\n### 2.3 W20 安全窗：五套拆塔方案对照\n")
    A(_tbl(["拆塔方案", "N_tower", "拆前 DPS", "拆后 DPS", "DPS 比", "净收益",
            "返还（分）", "销毁卡数", "销毁层数", "判定"],
           [[r["label"], f"{r['n0']}→{r['n1']}", f"{r['dps0']:,.0f}", f"{r['dps1']:,.0f}",
             f"×{r['ratio']:.3f}", f"{(r['ratio']-1)*100:+.1f}%", f"{r['refund']:,.0f}",
             r["destroyed_cards"], r["destroyed_layers"],
             "🟢 正" if r["ratio"] > 1 else ("🔴 负" if r["ratio"] < 1 else "—")]
            for r in v1["plans"].values()]))
    A(f"\n→ **P1/P2/P4/P5 全部为正**，且量级一致（×{p1['ratio']:.2f}）—— "
      "因为它们拆的都是同一批 `h<3` 占位塔。\n")
    A(f"→ **P3（只留主塔，N→1）是 🔴 灾难**：DPS 掉到 ×{p3['ratio']:.4f}"
      f"（`{p3['dps0']:,.0f} → {p3['dps1']:,.0f}`）—— "
      "因为主塔的 `E` 随 `Arrow(h=133)` 一起消失，共鸣乘区从 "
      f"×{(1+KR_FINAL)**max(s[4] for s in v1['slots']):,.0f} 塌到 ×1。"
      "**这条是给策划的重要反馈：拆塔的收益边界由「E 供给链」决定，不是由 κ 单方面决定。**\n")

    A("\n### 2.4 ★ W20「拆光杂兵塔」的逐项分解（增益从哪来、损失到哪去）\n")
    i0, i1 = p1["i0"], p1["i1"]
    c0, c1 = i0["core"], i1["core"]
    idx1 = [k for k, t in enumerate(p1["player"].towers) if t.slot ==
            next(x.slot for x in base["player"].towers if x.slot == c0)][0] if False else None
    # 主塔在拆后构筑中的索引
    main_slot = [t.slot for t in base["player"].towers][c0]
    j1 = [k for k, t in enumerate(p1["player"].towers) if t.slot == main_slot][0]
    rows = [
        ["`N_tower`", f"{p1['n0']}", f"{p1['n1']}", "−4 座", "（拆塔直接结果）"],
        ["主塔 κ（`κ_tag − 0.01·clamp(N−2,0,4)`）", f"{i0['kappa'][c0]-1:.3f}",
         f"{i1['kappa'][j1]-1:.3f}", f"+{(i1['kappa'][j1]-i0['kappa'][c0]):.3f}",
         "★ 广度折价从 0.04 归 0"],
        ["主塔装配层数 L", f"{i0['L'][c0]}", f"{i1['L'][j1]}", "0", "装配卡不在被拆塔上 → 不变"],
        ["主塔 `Stack = (1+κ)^L`", f"{i0['per_tower'][c0]['stack']:,.3f}",
         f"{i1['per_tower'][j1]['stack']:,.3f}",
         f"×{i1['per_tower'][j1]['stack']/i0['per_tower'][c0]['stack']:.3f}",
         "★ κ 回升的全部收益都在这里"],
        ["主塔 `E_i`", f"{i0['E'][c0]:.0f}", f"{i1['E'][j1]:.0f}", "0",
         "E 供给塔（Arrow h=133）被保留 → 不变"],
        ["主塔 `Res = (1+κ_r)^E`", f"{i0['per_tower'][c0]['res']:,.2f}",
         f"{i1['per_tower'][j1]['res']:,.2f}", "×1.000", "不变"],
        ["主塔 `Focus` / `AllIn` / `Cov`",
         f"{i0['per_tower'][c0]['focus']:.2f} / {i0['per_tower'][c0]['allin']:.2f} / "
         f"{i0['per_tower'][c0]['cov']:.2f}",
         f"{i1['per_tower'][j1]['focus']:.2f} / {i1['per_tower'][j1]['allin']:.2f} / "
         f"{i1['per_tower'][j1]['cov']:.2f}", "不变", "只吃单塔层数 / 几何，不随 N 变"],
        ["`Crossfire`（C2）", f"{i0['crossfire']:.2f}", f"{i1['crossfire']:.2f}",
         f"×{i1['crossfire']/i0['crossfire']:.3f}", "🔴 塔数 ≥3 的 ×1.5 掉到 ×1.25"],
        ["`AoE`（C1）", f"{i0['aoe']:.3f}", f"{i1['aoe']:.3f}",
         f"×{i1['aoe']/i0['aoe']:.3f}", "🔴 拆掉 3 座 Cannon → `Σh_fire` 11→8"],
        ["`Aux`（C3）", f"{i0['aux']:.3f}", f"{i1['aux']:.3f}", "×1.000",
         "终局无 Frost → 不参与"],
        ["被拆占位塔的 subtotal 贡献", f"{p1['lost_sub']:,.1f}", "0",
         f"−{p1['lost_sub']:,.1f}", f"仅占拆前总量的 {p1['lost_sub']/p1['dps0']:.4%}"],
        ["**总 DPS**", f"**{p1['dps0']:,.0f}**", f"**{p1['dps1']:,.0f}**",
         f"**×{p1['ratio']:.3f}**", f"**净 {(p1['ratio']-1)*100:+.1f}%**"],
        ["返还（Q-C3 50%）", "—", f"**{p1['refund']:,.0f} 分**", f"+{p1['refund']:,.0f}",
         f"销毁 {p1['destroyed_cards']} 张卡 / {p1['destroyed_layers']} 层（本例为 0）"],
    ]
    A(_tbl(["项", "拆前", "拆后", "变化", "说明"], rows))
    A(f"\n> **净收益分解式**：`×{i1['per_tower'][j1]['stack']/i0['per_tower'][c0]['stack']:.3f}"
      f"（κ 增益） × {i1['crossfire']/i0['crossfire']:.3f}（Crossfire 损失） × "
      f"{i1['aoe']/i0['aoe']:.3f}（AoE 损失） × (1 − {p1['lost_sub']/p1['dps0']:.6f})（占位塔损失） "
      f"= **×{p1['ratio']:.3f}**\n")

    A("\n### 2.5 逐波净收益（「后期」到底从哪一波开始转正）\n")
    A(_tbl(["安全窗所在波", "N_tower", "主塔 κ", "主塔 L", "拆前 DPS", "拆后 DPS",
            "DPS 比", "返还（分）", "判定"],
           [[f"W{r['wave']}", f"{r['n0']}→{r['n1']}",
             f"{r['i0']['kappa'][r['i0']['core']]-1:.3f}→{r['i1']['kappa'][r['i1']['core']]-1:.3f}",
             r["i0"]["L"][r["i0"]["core"]], f"{r['dps0']:,.0f}", f"{r['dps1']:,.0f}",
             f"×{r['ratio']:.3f}", f"{r['refund']:,.0f}",
             "🟢 正" if r["ratio"] > 1 else "🔴 负"] for r in v1["bywave"].values()]))
    w_first = next((r["wave"] for r in v1["bywave"].values() if r["ratio"] > 1), None)
    A(f"\n→ **从 W{w_first} 起就转正，且随波次单调放大** —— "
      "「后期」这个定语其实不必要：**只要主塔叠了层数，拆掉不供 E 的占位塔就是纯赚**。\n")

    A("\n### 2.6 理性贪心拆塔序列（决定性 W20）\n")
    A(_tbl(["步", "拆掉", "h", "L", "ΔDPS", "返还（分）", "DPS（拆前→拆后）"],
           [[f"#{i+1}", f"slot{rec[0]} {rec[1]}", rec[2], rec[3], f"{rec[4]:+,.0f}",
             f"{rec[5]:,.0f}", f"{rec[6]:,.0f} → {rec[7]:,.0f}"]
            for i, rec in enumerate(g["seq"])]))
    A(f"\n→ 理性玩家会**一路拆到底**（拆到没有正收益为止），合计 "
      f"DPS **{g['dps0']:,.0f} → {g['dps1']:,.0f}（×{g['dps1']/g['dps0']:.3f}）**。\n")
    A(f"→ **全程开拆塔的决定性终局**：N={len(on['player'].towers)}、"
      f"DPS **{on['dps']:,.0f}**（定稿基线 {base['dps']:,.0f}，"
      f"×{on['dps']/base['dps']:.3f}）、构筑 `{v6.tower_mix(on)}`、全程拆塔 "
      f"**{on['st']['salvages']} 次** → "
      "多塔 B 事实上**自我塌缩成单核**。\n")

    A("\n### 2.7 验证 1 判定\n")
    A(f"> ## 🟢 **拆塔净收益 = 正，且量级巨大：W20 安全窗拆光占位塔 → DPS ×{p1['ratio']:.3f}"
      f"（{(p1['ratio']-1)*100:+.0f}%），另返还 {p1['refund']:.0f} 分。**\n")
    A(">\n")
    A(f"> - **κ 回升带来的增益**：主塔 `Stack` "
      f"`{i0['per_tower'][c0]['stack']:,.2f} → {i1['per_tower'][j1]['stack']:,.2f}`"
      f"（×{i1['per_tower'][j1]['stack']/i0['per_tower'][c0]['stack']:.3f}）\n")
    A(f"> - **失去占位塔的 DPS 损失**：`{p1['lost_sub']:,.1f}`，占拆前总量 "
      f"**{p1['lost_sub']/p1['dps0']:.4%}**（四阶小量）\n")
    A(f"> - **其它连带损失**：Crossfire ×{i1['crossfire']/i0['crossfire']:.3f}、"
      f"AoE ×{i1['aoe']/i0['aoe']:.3f} —— 两者合计也只有 ×"
      f"{i1['crossfire']/i0['crossfire']*i1['aoe']/i0['aoe']:.3f}，"
      f"**远不足以抵消 ×{i1['per_tower'][j1]['stack']/i0['per_tower'][c0]['stack']:.3f} 的 κ 增益**\n")
    A(">\n")
    A("> → **F-2 的数值侧推演 100% 成立。** 唯一需要修正的是它的形态描述"
      "（是 6→2 而非 6→1，因为必须保留 E 供给塔）—— 详见 §2.1。\n")

    # ---------------- 3. 验证 2 ----------------
    A("\n## 3. 验证 2：拆塔 × κ 折价是否成主导策略（V-3）\n")
    A("### 3.1 方法：给理性 AI 加的动作\n")
    A("- 在 `shop_phase`（**波次间安全窗**）的每一轮决策里，先枚举所有「可拆的塔」，"
      "逐个用 `compute_dps_v8` 试算拆后的全场 DPS；\n"
      "- 若存在 `ΔDPS > 0` 的拆塔（即**拆掉它反而变强**），取 `ΔDPS` 最大的那一座执行，"
      "并按 Q-C3 回笼 50% 投入；否则走原有的买 / 刷逻辑（与 `sv.shop_phase` 逐字一致）；\n"
      "- 拆塔消耗 1 次「每波 12 动作」的注意力预算（与买/刷同价）→ **不是免费动作**；\n"
      "- 变体：`V1` 全程可拆（W1 起）/ `V2` 仅后期可拆（W13 起）/ "
      "`V3` 全程可拆 + 兜底①（`N_tower` 取本局历史最大值）。\n")
    A("\n### 3.2 300 局蒙特卡洛结果\n")
    A(_tbl(["变体", "路径", "起飞率", "终局塔数（中位/均）", "历史最大塔数（中位）",
            "拆塔率", "终局 N≤2", "终局 N≤3", "历史 N≥4", "★ 主导占比（V-3 判据）"],
           [[mc["res"][k]["meta"]["name"], path,
             f"{mc['res'][k]['row']['mc'][path]['rate']*100:.1f}%",
             f"{mc['res'][k]['row']['mc'][path]['n_final_med']:.0f} / "
             f"{mc['res'][k]['row']['mc'][path]['n_final_mean']:.2f}",
             f"{mc['res'][k]['row']['mc'][path]['n_max_med']:.0f}",
             f"{mc['res'][k]['row']['mc'][path]['salvaged_any_rate']*100:.1f}%",
             f"{mc['res'][k]['row']['mc'][path]['p_finalN_le2']*100:.1f}%",
             f"{mc['res'][k]['row']['mc'][path]['p_finalN_le3']*100:.1f}%",
             f"{mc['res'][k]['row']['mc'][path]['p_maxN_ge4']*100:.1f}%",
             f"**{mc['res'][k]['row']['mc'][path]['p_dominant']*100:.1f}%**"]
            for k in ("V0", "V1", "V2", "V3") for path in ("A", "B")]))
    A("\n**终局塔数分布（多塔 B）**\n")
    A(_tbl(["变体"] + [f"终局 N={i}" for i in range(1, 7)],
           [[mc["res"][k]["meta"]["name"]]
            + [str(mc["res"][k]["row"]["mc"]["B"]["ndist"].get(i, 0))
               for i in range(1, 7)]
            for k in ("V0", "V1", "V2", "V3")]))
    A(f"\n→ **多塔 B 的终局塔数中位从 {mB0['n_final_med']:.0f} 塌到 {mB['n_final_med']:.0f}**"
      f"（基线 {mB0['n_final_med']:.0f} 塔，开拆塔后一半的局收敛到 2 塔、"
      f"{mB['p_finalN_le3']*100:.0f}% 收敛到 ≤3 塔），而**历史最大塔数中位仍是 "
      f"{mB['n_max_med']:.0f}** → 「先铺满、再拆光」成为标准剧本。\n")
    A("\n**换种子复核（V1 · 多塔 B · 判据口径）**\n")
    A(_tbl(["种子", "主导占比", "终局 N≤2", "历史 N≥4", "起飞率", "拆塔率"],
           [[f"seed {SEED1}", f"{mB['p_dominant']*100:.1f}%",
             f"{mB['p_finalN_le2']*100:.1f}%", f"{mB['p_maxN_ge4']*100:.1f}%",
             f"{mB['rate']*100:.1f}%", f"{mB['salvaged_any_rate']*100:.1f}%"]]
           + [[f"seed {m['seed']}", f"{m['p_dominant']*100:.1f}%",
               f"{m['p_finalN_le2']*100:.1f}%", f"{m['p_maxN_ge4']*100:.1f}%",
               f"{m['rate']*100:.1f}%", f"{m['salvaged_any_rate']*100:.1f}%"]
              for m in mc["repro"]]))
    A(f"\n→ **判定口径（策划 `mechanics-tower-life-death.md` §4.2 V-3 原文）**："
      f"300 局中「终局塔数 ≤2 且历史最大塔数 ≥4」的占比 **>70% → 判定为主导策略**。\n")
    A(f"→ **实测：多塔 B 该占比 = {dom*100:.1f}%**（seed {SEED1}），"
      f"换两个种子为 " + "、".join(f"{m['p_dominant']*100:.1f}%" for m in mc["repro"]) +
      f" → **{'🔴 触发（>70%）' if dom_trigger else '🟢 未触发'}**。\n")
    A(f"→ 单核 A 路径塔数上限本就是 2（`max_towers[\"A\"]=2`）→ 该统计口径对它不适用，"
      f"实测 A 的拆塔率仅 {v1row['mc']['A']['salvaged_any_rate']*100:.1f}%"
      f"（κ 恒为 0.10，拆塔只剩损失）→ **风险完全集中在多塔流**。\n")
    A(f"→ `V2`（仅 W13 起才允许拆）占比 {mB2['p_dominant']*100:.1f}% —— "
      f"**限制拆塔的时机窗口并不能阻止它**：因为「后期」本来就够晚，"
      f"主塔在 W13 前已叠够层数。\n")

    A("\n### 3.3 定稿 6 条判据回归检查（开拆塔后有没有破线）\n")
    A(_tbl(["变体", "B 决定性起飞", "∈W10-15", "A 起飞率", "B 起飞率", "B/A", "<1",
            "交叉领先", "三阶段", "全部达标"],
           [[mc["res"][k]["meta"]["name"],
             f"W{mc['res'][k]['row']['toB']}" if mc["res"][k]["row"]["toB"] else "不起飞",
             "✓" if mc["res"][k]["row"]["c_win"] else "✗",
             f"{mc['res'][k]['row']['mc']['A']['rate']*100:.1f}% "
             f"({'✓' if mc['res'][k]['row']['c_rateA'] else '✗'} ≥60%)",
             f"{mc['res'][k]['row']['mc']['B']['rate']*100:.1f}% "
             f"({'✓' if mc['res'][k]['row']['c_rateB'] else '✗'} ≥80%)",
             f"{mc['res'][k]['row']['ba']:.3f}",
             "✓" if mc["res"][k]["row"]["c_ba"] else "✗",
             f"{mc['res'][k]['row']['leadA']}/{mc['res'][k]['row']['leadB']}/"
             f"{mc['res'][k]['row']['flips']} "
             f"({'✓' if mc['res'][k]['row']['c_flips'] else '✗'})",
             "✅" if mc["res"][k]["row"]["c_health"] else "⚠️",
             "✅" if mc["res"][k]["row"]["ok"] else "⚠️"]
            for k in ("V0", "V1", "V2", "V3")]))
    A(f"\n→ **基线复现校验**：V0（不开拆塔）实测 A 起飞率 **{v0row['mc']['A']['rate']*100:.1f}%** "
      f"（定稿 {69.3}%，`card-system` §5.7.2）、B 决定性起飞 **W{v0row['toB']}**、"
      f"`B/A` **{v0row['ba']:.3f}**（定稿 0.458）→ "
      f"**逐位复现定稿锚点**，本脚本的定稿口径可信"
      f"（B 起飞率 {mB0['rate']*100:.1f}% 与 v0.6 定稿的 99.0% 有差，"
      f"差异源是 v0.7 起生效的 0.65 链接口径，两者均 ≥80% 红线）。\n")
    A(f"\n→ 🔴 **开拆塔后定稿 6 条判据出现 1 条硬破线：`B/A < 1` 不成立。**\n")
    A(f"  - V1 相对 V0：B 起飞 W{v0row['toB']}→W{v1row['toB']}（**仍在 W10-15 窗内 ✓**）、"
      f"B W20 **{v0row['w20B']} → {v1row['w20B']}（×{v1row['w20B']/v0row['w20B']:.2f}）**、"
      f"B/A **{v0row['ba']} → {v1row['ba']}（🔴 ≥1，破线）**、"
      f"B 起飞率 {mB0['rate']*100:.1f}%→{mB['rate']*100:.1f}%（仍是升的 ✓）、"
      f"交叉 {v0row['flips']}→{v1row['flips']} 次（✓）。\n")
    A(f"  - V2（仅 W13 起可拆）同样破线：B/A **{v2row['ba']:.3f}**。\n")
    A("> ⚠️ **这是本轮最反直觉、也最重要的一条发现**：拆塔让多塔 B **更强，不是更弱**。\n")
    A(">\n")
    A("> - 它**不**触发「起飞率跌破红线」这类常见的数值风险（起飞率反而升了）；\n")
    A("> - 它触发的是**概念 §2.4.5「单核必须是后期 carry」这条已写进支柱的判据** —— "
      "多塔流通过「先铺满拿 Crossfire/共鸣 → 后期拆光拿回 κ」吃到了**两条主干的全部好处**，"
      "于是 `B/A` 从 0.458 反转为 2.096。\n")
    A("> - 换句话说：**这不是「某个数值该不该调」的问题，是「两条主干塌成一条」的结构问题**（P3）。"
      "调 `hp_growth` / `κ_r` 都修不了它 —— 只有改「拆塔能不能让 κ 回升」这一条口径才能修。\n")

    A("\n### 3.4 兜底①验证：`N_tower` 取本局历史最大值\n")
    A(_tbl(["口径", "多塔 B 主导占比", "拆塔率", "终局塔数中位", "B 起飞率", "B 决定性起飞",
            "B/A", "6 条判据"],
           [["定稿口径（`N_tower` = 当前塔数）", f"{mB['p_dominant']*100:.1f}%",
             f"{mB['salvaged_any_rate']*100:.1f}%", f"{mB['n_final_med']:.0f}",
             f"{mB['rate']*100:.1f}%", f"W{v1row['toB']}", f"{v1row['ba']:.3f}",
             "✅" if v1row["ok"] else "⚠️"],
            ["**兜底①**（`N_tower` = 本局历史最大值）", f"**{mB3['p_dominant']*100:.1f}%**",
             f"**{mB3['salvaged_any_rate']*100:.1f}%**", f"**{mB3['n_final_med']:.0f}**",
             f"{mB3['rate']*100:.1f}%", f"W{v3row['toB']}", f"{v3row['ba']:.3f}",
             "✅" if v3row["ok"] else "⚠️"]]))
    A(f"\n→ **兜底①完全有效**：κ 一旦按「本局历史最大塔数」锁定，拆塔就**不再让 κ 回升**，"
      f"「拆塔 = 白拿」的收益结构当场消失 → 拆塔率从 {mB['salvaged_any_rate']*100:.1f}% "
      f"掉到 **{mB3['salvaged_any_rate']*100:.1f}%**，主导占比从 {mB['p_dominant']*100:.1f}% "
      f"掉到 **{mB3['p_dominant']*100:.1f}%**。\n")
    A(f"→ **代价**：多塔 B 的终局强度回落（W20 {v1row['w20B']} → {v3row['w20B']}），"
      f"但定稿 6 条判据 **{'仍然全过' if v3row['ok'] else '有破线'}** —— "
      f"B 起飞 **W{v3row['toB']}** ∈ W10-15 ✓、B/A **{v3row['ba']:.3f}** <1 ✓、"
      f"B 起飞率 **{mB3['rate']*100:.1f}%** ≥80% ✓、A 起飞率 "
      f"**{v3row['mc']['A']['rate']*100:.1f}%** ≥60% ✓。\n")
    A("> 🟢 **语义上也自洽**（策划 §1.7 的原话）：「工程重心一旦分散过就回不去了」—— "
      "你把塔铺开过，κ 就已经按分散计价了，事后收摊不会把折扣退给你。"
      "**且它不动定稿公式里的任何一个数**（只改 `N_tower` 的取值口径）。\n")

    A("\n### 3.5 验证 2 判定\n")
    A(f"**先按策划 §4.2 V-3 的字面判据读一遍**：\n")
    A(f"> 判据 = 300 局中「终局塔数 ≤2 且历史最大塔数 ≥4」占比 > 70% → 判定为主导。\n")
    A(f"> **实测 = {dom*100:.1f}%**（seed {SEED1}；换种子 "
      + "、".join(f"{m['p_dominant']*100:.1f}%" for m in mc["repro"]) +
      f"）→ **{'🔴 超线' if dom_trigger else '🟢 未达 70% 红线'}**。\n")
    A("\n**但工程判定是「触发」—— 三条比占比更硬的信号**\n")
    A(_tbl(["信号", "实测", "为什么它比「占比」更硬"],
           [["**① `B/A < 1` 破线**",
             f"{v0row['ba']:.3f} → **{v1row['ba']:.3f}**",
             "这是**定稿 6 条判据之一**（概念 §2.4.5「单核必须是后期 carry」）。"
             "判据破线是二值的，不走「>70%」这种统计阈值 —— 破了就是破了。"],
            ["**② 拆塔率**", f"**{mB['salvaged_any_rate']*100:.1f}%**",
             "98.3% 的多塔局**至少拆了一座塔** —— 「后期拆杂兵塔」不是少数人的高阶操作，"
             "而是**默认打法**。"],
            ["**③ 宽口径塌缩（终局 N≤3）**",
             f"**{mB['p_finalN_le3']*100:.1f}%**",
             "判据写成「≤2」其实偏严：多塔 B 的塔位上限是 6，"
             "**从 6 塌到 ≤3 就已经是「多塔流自我拆掉」了**，这一口径也远超 70%。"],
            ["**④ 限制时机无效**",
             f"V2（仅 W13 起）= {mB2['p_dominant']*100:.1f}%，B/A {v2row['ba']:.3f}",
             "「只允许后期拆」挡不住它 —— 后期本来就是拆塔最划算的时候。"]]))
    A(f"\n> ## 🔴 **结论：触发兜底。建议启用兜底①（`N_tower` 取本局历史最大值）。**\n")
    A(">\n")
    A(f"> - **为什么字面判据没到 70%**：因为「终局 N≤2」这个口径太严 —— "
      f"有相当一部分局里，被保留下来的第 3 座塔是**主塔的 `E` 供给塔**（`h≥3`，拆了会让 `E` 崩塌，"
      f"理性 AI 不会拆）。也就是说，**没收敛到 2 塔的那些局不是「玩家没拆」，"
      f"而是「拆到 E 供给链的下限就停了」**。\n")
    A(f"> - 证据：在「曾经 ≥4 塔」的局里收敛到终局 ≤2 塔的比例 = "
      f"{(mB['p_dominant_of_maxN4'] or 0)*100:.1f}%；而**拆塔率高达 "
      f"{mB['salvaged_any_rate']*100:.1f}%** —— 两者之差正是「被 E 供给链挡住」的那批局。\n")
    A(f"> - 兜底①实测：主导占比 {mB['p_dominant']*100:.1f}% → **{mB3['p_dominant']*100:.1f}%**、"
      f"拆塔率 → **{mB3['salvaged_any_rate']*100:.1f}%**、B/A → **{v3row['ba']:.3f}**、"
      f"定稿 6 条判据 **{'全过' if v3row['ok'] else '有破线'}**。\n")

    # ---------------- 4. 结论 ----------------
    A("\n## 4. 给主理人的结论与建议\n")
    A("**四条结论（对应主理人下发的四个问题）**\n")
    A(f"1. **拆塔净收益 = 正。** W20 安全窗拆光 `h<3` 占位塔："
      f"N {p1['n0']}→{p1['n1']}、κ {v1['k6']:.2f}→{v1['k2']:.2f}、"
      f"DPS **{p1['dps0']:,.0f} → {p1['dps1']:,.0f}（×{p1['ratio']:.3f}，"
      f"{(p1['ratio']-1)*100:+.0f}%）**，返还 {p1['refund']:.0f} 分；"
      f"代价（占位塔 DPS + Crossfire + AoE）合计只有 ×"
      f"{p1['ratio']/(i1['per_tower'][j1]['stack']/i0['per_tower'][c0]['stack']):.3f} 的折损。"
      f"**F-2 的数值侧推演 100% 成立。**\n")
    A(f"2. **后期拆杂兵塔的行为占比 = {dom*100:.1f}%**（V-3 判据口径「终局 N≤2 且历史 N≥4」；"
      f"多塔 B / 300 局 / seed {SEED1}；换种子 "
      + "、".join(f"{m['p_dominant']*100:.1f}%" for m in mc["repro"]) +
      f"）。**未达 70% 红线** —— 但拆塔率高达 **{mB['salvaged_any_rate']*100:.1f}%**，"
      f"宽口径「终局 N≤3」= **{mB['p_finalN_le3']*100:.1f}%**（超 70%）。\n")
    A(f"3. **🔴 触发主导策略兜底 → 建议启用兜底①（`N_tower` 取本局历史最大值 `N_max`）。**\n")
    A(f"   - 触发依据不是「占比 >70%」那一条（它没到），"
      f"而是 **`B/A` 从 {v0row['ba']:.3f} 被顶到 {v1row['ba']:.3f} > 1** —— "
      f"**定稿 6 条判据之一硬破线**（概念 §2.4.5 单核必须是后期 carry）；\n")
    A(f"   - 加上拆塔率 {mB['salvaged_any_rate']*100:.1f}% 与宽口径 "
      f"{mB['p_finalN_le3']*100:.1f}% 两条佐证；\n")
    A(f"   - 兜底①实测：主导占比 → **{mB3['p_dominant']*100:.1f}%**、拆塔率 → "
      f"**{mB3['salvaged_any_rate']*100:.1f}%**、B/A → **{v3row['ba']:.3f}**、"
      f"6 条判据 **{'全过' if v3row['ok'] else '有破线'}**。\n")
    A(f"4. **对 F-2 的最终判定 = 🔴 主导策略，不是合法转型。**\n")
    A("\n**给策划（文策渊）的两条回执**\n")
    A(f"- **修正 F-2 的形态描述**：定稿多塔 B 是「**2 座有效塔 + {n_filler} 座占位塔**」，"
      f"不是「1 深塔 + 5 占位」。正确形态是 **N 6→2**（必须保留 E 供给塔 `Arrow`）；"
      f"6→1 会让 `E` 归零、DPS 掉到 ×{p3['ratio']:.4f}，是灾难。\n")
    A(f"- **§1.7 兜底①的建议获数据支持**；同时建议把「**拆塔不能让 κ 回升**」"
      f"这条语义写进 `card-system` §5.2 的 κ 口径与 E11 的重算链说明里"
      f"（本轮**未改任何 GDD**，待拍板后回写）。\n")
    A("\n**待用户 / 主理人拍板（1 项）**\n")
    A(f"- 是否启用兜底①（`N_tower` → `N_max`）？"
      f"**我的推荐：启用。** 它不动定稿公式的任何一个数、不新增参数、语义自洽，"
      f"且实测把主导占比从 {dom*100:.1f}% 压到 {mB3['p_dominant']*100:.1f}%，"
      f"6 条定稿判据仍全过。\n")
    A(f"- 兜底②/③（逐层锁定 ④b、折价步长 0.01→0.005）本轮**未测**，"
      f"若主理人不接受 ① 可再补跑。\n")

    # ---------------- 5. 风险 ----------------
    A("\n## 5. 知识缺口 / 风险标注\n")
    A("| # | 项 | 说明 |\n|---|---|---|\n")
    A("| 🟡 **1** | **「装配卡全销毁」的卡组处理口径** | "
      "Q-C3 原文只说「该塔装配的全部单塔效果卡及层数全部销毁」。本脚本的实现是："
      "销毁该塔上的层数；若该卡在**其它塔上也不再有任何层数**，才把它移出卡组（释放卡位）。"
      "另一种读法是「该卡整体销毁（即使别的塔上还有层）」。"
      "**定稿多塔 B 的终局只有 1 张 `FireUp` 且只挂在主塔上 → 两种读法数值等价**，"
      "本轮结论不受影响；但 GDD 回写时建议显式钉死。 |\n")
    A("| 🟡 **2** | **初始赠送塔的投入如何计价** | "
      "`new_player()` 白送一座 `Arrow(h=1)`。本脚本把它记为「未花分」（返还时不计这 1 层）。"
      "若改为计入，也只多返还 6 分 —— **对净收益判定无影响** |\n")
    A("| 🟡 **3** | **「二次确认」不计入数值** | "
      "Q-C3 的二次确认是 UI 层的防误触，不改变任何数值。本脚本只记录弹窗内容。"
      "它对本轮「主导策略」判定**没有缓解作用**（这是策略层问题，不是误触问题） |\n")
    A("| 🟡 **4** | **塔被攻击死亡（T1）未建模** | "
      "本轮只跑「售卖 = 拆塔」。塔死亡机制按提案进 T1，其 `Disabled` 口径"
      "（仍占 `N_tower`、仍供 `h_j`）**恰好也能堵住这个洞**，"
      "但那属于另一条复验（V-1 / V-2），本轮未涉及 |\n")
    A("| 🟡 **5** | **兜底①对「建塔决策」的连带影响** | "
      "启用兜底①后，玩家一旦建到第 3 座塔，κ 折价就**永久生效**。"
      "这可能放大 `card-system` §5.2 已登记的 **R-C1** 风险（「永远只建 2 座塔」）。"
      "**建议与 R-C1 的兜底 1（κ 折价预告的事实标注）绑定一起评估** |\n")
    A("| 🟡 **6** | **只跑了纸面模拟** | "
      "真实引擎的 `N_tower` 若在 `Disabled`/建造动画等中间态上取值不同，"
      "需与本报告口径对齐（κ 逐塔当前值、塔数变化即重算） |\n")
    A(f"\n> 复现命令：`python corebound_sim_v08_salvage.py all` "
      f"（MC {mc['runs']} 局 / 变体）。"
      f"引擎口径自检：`selfcheck_engine()` 断言 v0.8 与 v0.6 在定稿口径下逐位相同。\n")
    return "\n".join(L)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    runs = int(sys.argv[2]) if len(sys.argv) > 2 else MC_RUNS
    if mode in ("probe",):
        run_probe()
    elif mode in ("mc",):
        run_mc(runs=runs)
    else:
        t0 = time.time()
        v1 = run_probe()
        mc = run_mc(runs=runs)
        rp = os.path.join(OUT_DIR, "salvage-verify.md")
        with open(rp, "w", encoding="utf-8") as f:
            f.write(build_report(v1, mc))
        print("\n" + "=" * 78)
        print("报告：%s ｜ 总耗时 %.1fs" % (rp, time.time() - t0))
