# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **Q-C6 数值口径核实** v0.6
作者：程基岩（工程主理人）

核实对象（策划文策渊在 `design/gdd/card-system.md` §10 提的 Q-C6）：
    引擎是否仍在应用 `synergy_mult = 1.5` 的一次性 Tag 协同乘区？
    概念 §2.4.7 早已把它**作废**（改为「Tag 档位 → 复利率 κ / κ_r」）。

本脚本回答三件事：
  Q1  Q-C6 是否成立？在 v0.4 定稿口径下 ×1.5 是否真的触发并乘进了每塔 DPS？两条定稿路径是否都吃了它？
  Q2  移除 ×1.5（synergy_mult = 1.0）+ 接入概念 §5.4 / GDD §5.2 的 `κ_tag` 档位后，
      起飞点是否还落在 W10-15 窗口？不在的话联调哪个系数才能回窗？
  Q3  移除后之前 v0.4 定稿数值是否仍有效？给出最终定稿数值表。

新增引擎能力（本脚本独占，不改 v03/v04/v05）：
  ① synergy_on : True = v0.4 基线（一次性 ×1.5）；False = 按概念 §2.4.7 作废
  ② kappa_mode : "path" = v0.4 定稿（κ 由路径常量 1.10/1.06 给）
                 "tier" = GDD §5.2/§5.4（κ = κ_tag − 0.01·clamp(N−2,0,4)，下限 0.02）
  ③ kr_mode    : "flat" = v0.4 定稿 κ_r=0.045 恒定
                 "tier" = GDD §5.4 档位（0.040 / 0.045 / 0.050）+ §5.4.1 中性塔恒取基准档
  ④ stackcap_tier : GDD §5.4 的 StackCap 档位（50 / 100 / 150）

用法（隔离 venv）：
  C:\\Users\\junhewang\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe corebound_sim_v06_synergy.py
"""
from __future__ import annotations
import os
import sys
import math
import random
import statistics

import corebound_sim_v03 as sv
import corebound_sim_v04 as v4
import corebound_sim_v05_card as v5      # 复用 v0.5 配置工厂（导入即打补丁，下面被 v6 覆盖）

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 定稿口径常量（来自 GDD §5.2 / §5.4 与概念 §2.4.7）
# =============================================================================
# κ_tag 档位（单塔效果卡复利**基准**利率）
KTAG_TIERS_MVP = [(0, 0.06), (3, 0.10)]                 # MVP：未协同 / 协同成立
KTAG_TIERS_T1 = [(0, 0.06), (3, 0.10), (20, 0.12)]      # T1：加「深度协同」档
# κ_r 档位（共鸣复利率）—— card-verify.md Q-C5 定稿
KR_TIERS_MVP = [(0, 0.040), (3, 0.045)]                 # MVP 两档
KR_TIERS_T1 = [(0, 0.040), (3, 0.045), (20, 0.050)]     # GDD §5.4 三档（≥20 层标 T1）
# StackCap 档位
STACKCAP_TIERS = [(0, 50), (3, 100), (20, 150)]


def _tier(inv, tiers):
    """按 (阈值, 值) 升序表取档。"""
    val = tiers[0][1]
    for th, v in tiers:
        if inv >= th:
            val = v
    return val


# =============================================================================
# 1. v0.6 伤害引擎：synergy 开关 + κ_tag 档位 + κ_r 档位 + StackCap 档位
# =============================================================================
def compute_dps_v6(player, cfg, geo=None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return 0.0, dict(per_tower=[], E=[], aoe=1.0, crossfire=1.0, aux=1.0,
                         empower=1.0, subtotal=0.0, core=0, L=[], Ltot=0.0,
                         kr=[], kappa=[], tag_invest={}, syn_hits=0)

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    h = [t.h for t in ts]
    L = [sum(t.attach.values()) for t in ts]
    Ltot = sum(L)
    core = max(range(n), key=lambda i: L[i]) if Ltot > 0 else 0

    # ---- Tag 投入层数（建筑卡层数 + 单塔效果卡层数；全局卡无 Tag 不计入）----
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

    # ---- κ 判定（GDD §5.2：κ = κ_tag − 广度折价，下限 0.02）----
    kmode = cfg.get("kappa_mode", "path")
    ktiers = cfg.get("ktag_tiers", KTAG_TIERS_MVP)
    disc = 0.01 * min(max(n - 2, 0), 4)          # 广度折价 = 0.01·clamp(N−2,0,4)
    kappa, caps = [], []
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if kmode == "tier":
            inv = tag_invest.get(tg, 0) if tg else 0
            k = max(0.02, _tier(inv, ktiers) - disc)
            cap_i = (_tier(inv, cfg.get("stackcap_tiers", STACKCAP_TIERS))
                     if cfg.get("stackcap_tier") else cfg["reinf_cap"])
        else:
            k = cfg["reinf_compound"][path] - 1.0
            cap_i = cfg["reinf_cap"]
        kappa.append(1.0 + k)
        caps.append(cap_i)

    # ---- κ_r 判定（GDD §5.4 + §5.4.1 中性塔恒取基准档）----
    krmode = cfg.get("kr_mode", "flat")
    krtiers = cfg.get("kr_tiers", KR_TIERS_T1)
    neutral = cfg.get("kr_neutral", 0.045)
    kr = []
    for t in ts:
        tg = sv.TOWERS[t.ctype]["tag"]
        if krmode == "tier":
            kr.append(_tier(tag_invest.get(tg, 0), krtiers) if tg else neutral)
        else:
            kr.append(cfg["kappa_r"])

    # ---- 链接 / E_i ----
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
        # ★ B3 Synergy：概念 §2.4.7 已作废的一次性 ×1.5（Q-C6 的主角）
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
                              # ⚠️ 2026-11-08 口径：有效 DPS = 伤害 × 攻速（与引擎同序）
                              dps=base * stack * syn * res * foc * ali * cov
                                  * sv.TOWERS[t.ctype].get("aspeed", 1.0)))

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
                       syn_hits=syn_hits)


def dps_only_v6(player, cfg, geo=None):
    return compute_dps_v6(player, cfg, geo)[0]


# ---- 打补丁：让 v03 的 run/shop/action_value 全部走 v6 引擎 ----
sv.compute_dps = compute_dps_v6
sv.dps_only = dps_only_v6


# =============================================================================
# 2. 配置工厂（v0.4 定稿主口径 + 本轮开关）
# =============================================================================
def v06_cfg(path="B", hp_growth=1.42, focus_per_layer=0.06, kappa_r=0.045,
            synergy_on=True, kappa_mode="path", kr_mode="flat", **over):
    d = dict(
        tower_card_mode="map", n_slots=6, coverage_mode="path",
        use_resonance=True, kappa_r=kappa_r,
        link_min_level=sv.RECOMMENDED["link_min_level"],
        link_rule="any", max_actions=12,
        use_focus=True, use_allin=True, use_crossfire=True, use_aux=True,
        use_empowerment=False,
        focus_full=False, focus_min_h=8.0,
        aux_mode="global", aux_tau=8.0, aux_cap=1.5,
        hp_growth=hp_growth, focus_per_layer=focus_per_layer,
        # ---- v0.6 新增 ----
        synergy_on=synergy_on,          # True = 一次性 ×1.5 生效（v0.4 基线）；False = 按概念作废
        kappa_mode=kappa_mode,          # "path" | "tier"
        ktag_tiers=KTAG_TIERS_MVP,
        kr_mode=kr_mode,                # "flat" | "tier"
        kr_tiers=KR_TIERS_T1,
        kr_neutral=0.045,               # §5.4.1 中性塔恒取基准档
        stackcap_tier=False,
        stackcap_tiers=STACKCAP_TIERS,
        kappa_main=0.10, kappa_aux=0.06,
        mix_bias=0.0, mix_cap=None,
    )
    d.update(over)
    return sv.make_cfg(**d)


# =============================================================================
# 3. 观测指标
# =============================================================================
def summarize(rows, w0=13):
    d = {r["w"]: r["ratio"] for r in rows}
    return dict(takeoff=sv.takeoff_wave(rows), w10=d.get(10), w13=d.get(13),
                w16=d.get(16), w20=d.get(20),
                tail_min=round(sv.tail_min(rows, w0), 2),
                core_hp=rows[-1]["core_hp"] if rows else 0.0,
                towers=rows[-1]["towers"] if rows else 0)


def final_state(path, cfg, waves=20):
    rows, player = sv.run(path, cfg, waves, geo=sv.GEO6)
    dps, info = compute_dps_v6(player, cfg, sv.GEO6)
    return dict(rows=rows, player=player, dps=dps, info=info, s=summarize(rows))


def build_dump(st):
    p, info = st["player"], st["info"]
    parts = []
    for i, t in enumerate(p.towers):
        att = ",".join(f"{k}{v}" for k, v in sorted(t.attach.items())) or "-"
        parts.append(f"{t.ctype}(h{t.h}|{att}|E{info['E'][i]:.0f}"
                     f"|k{info['kappa'][i]:.3f}|kr{info['kr'][i]:.3f}|syn{info['per_tower'][i]['syn']:.2f})")
    return " ".join(parts)


def tower_mix(st):
    p = st["player"]
    agg = {}
    for t in p.towers:
        agg[t.ctype] = agg.get(t.ctype, 0) + t.h
    return ",".join(f"{k}x{v}" for k, v in sorted(agg.items()))


def cross_lead(rowsA, rowsB):
    dA = {r["w"]: r["ratio"] for r in rowsA}
    dB = {r["w"]: r["ratio"] for r in rowsB}
    lead = {"A": 0, "B": 0}
    flips = 0
    prev = None
    cross = []
    firstA = firstB = None
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if a is None or b is None:
            continue
        who = "A" if a > b else ("B" if b > a else "=")
        if who in ("A", "B"):
            lead[who] += 1
            if who == "A" and firstA is None:
                firstA = w
            if who == "B" and firstB is None:
                firstB = w
            if prev and prev != who:
                flips += 1
            prev = who
        cross.append((w, round(a, 3), round(b, 3), who))
    return cross, lead, flips, firstA, firstB


def stage_health(rows):
    d = {r["w"]: r for r in rows}
    survive = all(d[w]["core_hp"] > 0 for w in range(1, 10) if w in d)
    r16, r20 = d.get(16), d.get(20)
    grow = (r20["ratio"] / r16["ratio"]) if (r16 and r20 and r16["ratio"] > 0) else 0.0
    tail = [d[w]["ratio"] for w in range(13, 21) if w in d]
    rise = all(tail[i] <= tail[i + 1] + 1e-9 for i in range(len(tail) - 1))
    return dict(survive=survive, grow=round(grow, 2), rise=rise,
                healthy=survive and grow > 1.0)


def takeoff_rate(path, cfg, runs=300, max_wave=20, actions=12, seed=20260930):
    rng = random.Random(seed)
    takeoffs, survives, hits = 0, 0, []
    for _ in range(runs):
        cfgx = dict(cfg)
        cfgx["max_actions"] = actions
        rows, _ = sv.run(path, cfgx, max_wave, geo=sv.GEO6, rng=rng)
        alive = bool(rows) and rows[-1]["core_hp"] > 0
        if alive:
            survives += 1
        tw = sv.takeoff_wave(rows)
        if alive and tw is not None:
            takeoffs += 1
            hits.append(tw)
    return dict(rate=round(takeoffs / runs, 3), surv=round(survives / runs, 3),
                med=statistics.median(hits) if hits else None)


# =============================================================================
# 4. Q1：×1.5 是否真的生效（逐波追踪）
# =============================================================================
def syn_trace(path, cfg, waves=20):
    """逐波记录：syn 有效倍率（加权）、吃到 ×1.5 的塔数、该 Tag 塔层数之和。"""
    player = sv.new_player(path, cfg, sv.GEO6)
    core_hp = cfg["core_hp"]
    cum = 0.0
    out = []
    for w in range(1, waves + 1):
        res = sv.simulate_wave(player, w, cfg, sv.GEO6)
        core_hp -= res["core_damage"]
        cum += res["scrap_earned"] * (1.0 + player.income_mult)
        budget, _ = sv.shop_phase(player, cum, w, cfg, sv.GEO6, None)
        cum = budget
        _, info = compute_dps_v6(player, cfg, sv.GEO6)
        pt = info["per_tower"]
        base_sum = sum(p["base"] for p in pt) or 1.0
        syn_eff = sum(p["base"] * p["syn"] for p in pt) / base_sum
        out.append(dict(w=w, syn_eff=round(syn_eff, 3), hits=info["syn_hits"],
                        fire_lv=info["tag_tower_lv"], ratio=round(res["total_hp"] and 0 or 0, 3)))
        if core_hp <= 0:
            break
    return out


def q1_evidence():
    """Q-C6 成立性证据：基线(v0.4 定稿) vs 移除 ×1.5，双路径逐塔 syn。"""
    ev = {}
    for path in ("A", "B"):
        cfg_on = v06_cfg(path=path, synergy_on=True)
        cfg_off = v06_cfg(path=path, synergy_on=False)
        st_on = final_state(path, cfg_on)
        st_off = final_state(path, cfg_off)
        ev[path] = dict(
            mix=tower_mix(st_on),
            dump_on=build_dump(st_on),
            dump_off=build_dump(st_off),
            # ★ 真·有效倍率 = Σ dps / Σ(dps / syn)  —— 用「去掉 syn 后的 DPS」加权，
            #   而不是用 base 加权（base 加权会把无 Tag 的高谐波 Arrow 算进来，严重低估）
            # 注意：分子必须用 subtotal（Σ 逐塔 dps），不能用 total（已含 AoE/Crossfire/Aux 全局乘区）
            syn_eff_on=round(st_on["info"]["subtotal"] / max(1e-9, sum(
                p["dps"] / p["syn"] for p in st_on["info"]["per_tower"])), 4),
            dps_ratio=round(st_on["dps"] / max(1e-9, st_off["dps"]), 5),
            syn_hits_on=st_on["info"]["syn_hits"],
            dps_on=st_on["dps"], dps_off=st_off["dps"],
            to_on=st_on["s"]["takeoff"], to_off=st_off["s"]["takeoff"],
            w20_on=round(st_on["s"]["w20"] or 0, 2), w20_off=round(st_off["s"]["w20"] or 0, 2),
            tag_tower_lv=st_on["info"]["tag_tower_lv"],
            tag_invest=st_on["info"]["tag_invest"],
        )
    return ev


# =============================================================================
# 4b. 数学等价性检验：移除 ×1.5 是否 ≡ 全场 DPS ÷ 1.5？
#     若是，则「把 hp_base 除以 1.5」是它的精确反操作 —— 这是判断
#     「该作废乘区是否被其它系数吸收」的关键。
# =============================================================================
def equivalence_test():
    """S1（移除 ×1.5）+ hp_base ÷ 1.5  vs  S0（v0.4 定稿基线）。
    两条路径逐位比对：起飞波次 / W20 倍数 / 终局核心 HP。"""
    hb = 16.0 / 1.5
    rows = []
    for path in ("A", "B"):
        s0 = final_state(path, v06_cfg(path=path, synergy_on=True,
                                       kappa_mode="path", kr_mode="flat"))["s"]
        c = v06_cfg(path=path, synergy_on=False, kappa_mode="path", kr_mode="flat")
        c["hp_base"] = hb
        s1 = final_state(path, c)["s"]
        rows.append(dict(path=path, hp_base=round(hb, 3),
                         to0=s0["takeoff"], w200=round(s0["w20"] or 0, 4), hp0=s0["core_hp"],
                         to1=s1["takeoff"], w201=round(s1["w20"] or 0, 4), hp1=s1["core_hp"],
                         d_w20=round((s1["w20"] / s0["w20"] - 1) * 100, 2) if s0["w20"] else 0.0))
    return rows


# =============================================================================
# 4c. 单核 A 的失败模式诊断（起飞率为何掉？）
# =============================================================================
def failure_mode(path, cfg, runs=300, seed=20260930):
    """把 300 局分成三类：① 中途核心被打爆（记录死亡波）
    ② 存活但 W20 仍未起飞 ③ 起飞。并统计「死于没能叠起层数」的占比。"""
    import collections
    rng = random.Random(seed)
    dead = collections.Counter()
    dead_no_layer = 0
    alive_no_takeoff = 0
    took_off = 0
    for _ in range(runs):
        c = dict(cfg)
        c["max_actions"] = 12
        rows, p = sv.run(path, c, 20, geo=sv.GEO6, rng=rng)
        Ltot = sum(sum(t.attach.values()) for t in p.towers)
        if rows[-1]["core_hp"] <= 0:
            dw = next(r["w"] for r in rows if r["core_hp"] <= 0)
            dead[dw] += 1
            if Ltot < 10:
                dead_no_layer += 1
        elif sv.takeoff_wave(rows) is None:
            alive_no_takeoff += 1
        else:
            took_off += 1
    return dict(dead=dict(sorted(dead.items())), dead_total=sum(dead.values()),
                dead_no_layer=dead_no_layer, alive_no_takeoff=alive_no_takeoff,
                took_off=took_off, runs=runs)


# =============================================================================
# 5. 场景矩阵：S0 基线 → S1 移除 → S2/S3 接入 κ_tag 档位
# =============================================================================
def scenario_matrix(hp_growth=1.42):
    scen = [
        dict(key="S0", name="S0 基线：v0.4 定稿（×1.5 生效）",
             kw=dict(synergy_on=True, kappa_mode="path", kr_mode="flat")),
        dict(key="S1", name="S1 仅移除 ×1.5（其余不动）",
             kw=dict(synergy_on=False, kappa_mode="path", kr_mode="flat")),
        dict(key="S2", name="S2 移除 ×1.5 + κ_tag 档位（§5.2）",
             kw=dict(synergy_on=False, kappa_mode="tier", kr_mode="flat")),
        dict(key="S3", name="S3 移除 ×1.5 + κ_tag 档位 + κ_r 档位（§5.4，MVP 两档）",
             kw=dict(synergy_on=False, kappa_mode="tier", kr_mode="tier",
                     kr_tiers=KR_TIERS_MVP)),
        dict(key="S4", name="S4 = S3 + κ_r 深度档 0.050（GDD §5.4 三档）",
             kw=dict(synergy_on=False, kappa_mode="tier", kr_mode="tier",
                     kr_tiers=KR_TIERS_T1)),
        dict(key="S5", name="S5 = S4 + StackCap 档位（50/100/150）",
             kw=dict(synergy_on=False, kappa_mode="tier", kr_mode="tier",
                     kr_tiers=KR_TIERS_T1, stackcap_tier=True)),
        dict(key="S6", name="S6 = S4 + κ_tag 深度档 0.12（T1 前瞻·预期过热）",
             kw=dict(synergy_on=False, kappa_mode="tier", kr_mode="tier",
                     kr_tiers=KR_TIERS_T1, ktag_tiers=KTAG_TIERS_T1)),
    ]
    out = []
    for s in scen:
        row = dict(key=s["key"], name=s["name"])
        st = {}
        for path in ("A", "B"):
            cfg = v06_cfg(path=path, hp_growth=hp_growth, **s["kw"])
            st[path] = final_state(path, cfg)
            row[f"to{path}"] = st[path]["s"]["takeoff"]
            row[f"w20{path}"] = round(st[path]["s"]["w20"] or 0, 2)
        rowsA, rowsB = st["A"]["rows"], st["B"]["rows"]
        _, lead, flips, fa, fb = cross_lead(rowsA, rowsB)
        row["leadA"], row["leadB"], row["flips"] = lead["A"], lead["B"], flips
        row["firstA"], row["firstB"] = fa, fb
        row["ba"] = round((row["w20B"] / row["w20A"]) if row["w20A"] else 0.0, 3)
        row["in_window"] = (row["toA"] is not None and 10 <= row["toA"] <= 15,
                            row["toB"] is not None and 10 <= row["toB"] <= 15)
        row["healthA"] = stage_health(rowsA)
        row["healthB"] = stage_health(rowsB)
        row["dumps"] = {p: build_dump(st[p]) for p in ("A", "B")}
        row["mix"] = {p: tower_mix(st[p]) for p in ("A", "B")}
        out.append(row)
    return out


# =============================================================================
# 6. hp_growth 扫参：把起飞点拉回 W10-15
# =============================================================================
def sweep_hp_growth(kw, growths=(1.28, 1.32, 1.34, 1.35, 1.36, 1.40, 1.42, 1.46, 1.50)):
    out = []
    for g in growths:
        row = dict(g=g)
        st = {}
        for path in ("A", "B"):
            cfg = v06_cfg(path=path, hp_growth=g, **kw)
            st[path] = final_state(path, cfg)
            row[f"to{path}"] = st[path]["s"]["takeoff"]
            row[f"w20{path}"] = round(st[path]["s"]["w20"] or 0, 2)
            row[f"hp{path}"] = round(st[path]["s"]["core_hp"], 0)
        _, lead, flips, fa, fb = cross_lead(st["A"]["rows"], st["B"]["rows"])
        row["leadA"], row["leadB"], row["flips"] = lead["A"], lead["B"], flips
        row["ba"] = round((row["w20B"] / row["w20A"]) if row["w20A"] else 0.0, 3)
        row["winA"] = row["toA"] is not None and 10 <= row["toA"] <= 15
        row["winB"] = row["toB"] is not None and 10 <= row["toB"] <= 15
        row["hA"] = stage_health(st["A"]["rows"])
        row["hB"] = stage_health(st["B"]["rows"])
        # 设计取向判据：B 入窗 + 交叉领先 + A 后期 carry（B/A<1）+ B 三阶段健康
        row["ok"] = row["winB"] and row["ba"] < 1.0 and flips >= 1 \
            and lead["A"] < 20 and lead["B"] < 20 and row["hB"]["healthy"]
        # 目标函数：B 越接近 W11、A 越接近 W10、B/A 越接近 0.3 越好
        row["obj"] = round(abs((row["toB"] or 99) - 11) + abs((row["toA"] or 99) - 10) * 1.0
                           + abs(row["ba"] - 0.30) * 3, 2)
        out.append(row)
    return out


# =============================================================================
# 6b. 联合扫参：hp_base（水平旋钮） × hp_growth（斜率旋钮） × pity（发牌保底）
# =============================================================================
def sweep_joint(kw, combos, runs=200):
    """(hp_base, hp_growth, pity) 网格：决定性跑给出起飞点/W20/B/A，
    蒙特卡洛给出起飞率。判据：A 起飞率 ≥60%、B ≥80%、B 决定性起飞 ∈ W10-15、B/A < 1。"""
    out = []
    for hb, g, pity in combos:
        row = dict(hb=hb, g=g, pity=pity)
        st = {}
        for path in ("A", "B"):
            cfg = v06_cfg(path=path, hp_growth=g, **kw)
            cfg["hp_base"] = hb
            cfg["pity"] = pity
            st[path] = final_state(path, cfg)
            row[f"to{path}"] = st[path]["s"]["takeoff"]
            row[f"w20{path}"] = round(st[path]["s"]["w20"] or 0, 2)
        _, lead, flips, fa, fb = cross_lead(st["A"]["rows"], st["B"]["rows"])
        row["leadA"], row["leadB"], row["flips"] = lead["A"], lead["B"], flips
        row["ba"] = round((row["w20B"] / row["w20A"]) if row["w20A"] else 0.0, 3)
        cfgA = v06_cfg(path="A", hp_growth=g, **kw)
        cfgA["hp_base"], cfgA["pity"] = hb, pity
        cfgB = v06_cfg(path="B", hp_growth=g, **kw)
        cfgB["hp_base"], cfgB["pity"] = hb, pity
        ra = takeoff_rate("A", cfgA, runs=runs, seed=20260930)
        rb = takeoff_rate("B", cfgB, runs=runs, seed=20260930)
        row["rateA"], row["rateB"] = ra["rate"], rb["rate"]
        row["medA"], row["medB"] = ra["med"], rb["med"]
        row["hB"] = stage_health(st["B"]["rows"])
        row["winB"] = row["toB"] is not None and 10 <= row["toB"] <= 15
        row["okA"] = ra["rate"] >= 0.60
        row["okB"] = rb["rate"] >= 0.80
        row["ok"] = row["okA"] and row["okB"] and row["winB"] and row["ba"] < 1.0 \
            and flips >= 1 and row["hB"]["healthy"]
        out.append(row)
    return out


# =============================================================================
# 7. 报告
# =============================================================================
def _tbl(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        out.append("| " + " | ".join("—" if x is None else str(x) for x in r) + " |")
    return "\n".join(out) + "\n"


def fx(v, nd=2):
    if v is None:
        return "—"
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def build_report(ctx):
    L = []
    A = L.append
    A("# 《守核 Corebound》· **Q-C6 数值口径核实报告**（引擎残留 Tag 一次性 ×1.5）\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v06_synergy.py`（本目录）\n")
    A("> 核实对象：`design/gdd/card-system.md` §10 **Q-C6**（策划文策渊提出） —— "
      "引擎是否仍在应用已被概念 §2.4.7 作废的 `synergy_mult = 1.5` 一次性 Tag 协同乘区。\n")
    A("> 基线口径：v0.4 定稿 —— `hp_growth=1.42` / `focus_per_layer=0.06` / `κ_r=0.045` / "
      "共鸣门槛 Lv3 / 6 塔位 / map 模式 / 每波 12 动作 / 全乘区打开（Empowerment 关闭）。\n")
    A("## 0. 结论速览（三问答复在此）\n")
    A(ctx["headline"])
    A("## 1. Q-C6 是否成立（成立性证据）\n")
    A(ctx["q1_table"])
    A(ctx["q1_note"])
    A("### 1.1 逐波 ×1.5 生效追踪\n")
    A(ctx["trace_table"])
    A(ctx["trace_note"])
    A("### 1.2 数学等价性检验：移除 ×1.5 ≡ 全场 DPS ÷ 1.5？\n")
    A(ctx["equiv_table"])
    A(ctx["equiv_note"])
    A("## 2. 移除 ×1.5 + 接入 κ_tag / κ_r 档位后的场景矩阵\n")
    A(ctx["scen_table"])
    A(ctx["scen_note"])
    A("## 3. 起飞率掉到哪里去了（单核 A 的失败模式诊断）\n")
    A(ctx["fail_table"])
    A(ctx["fail_note"])
    A("## 4. 联调扫参（找回起飞率红线）\n")
    A("### 4.1 hp_growth 单变量\n")
    A(ctx["sweep_table"])
    A(ctx["sweep_note"])
    A("### 4.2 hp_base × hp_growth × pity 联合扫参\n")
    A(ctx["joint_table"])
    A(ctx["joint_note"])
    A("## 5. 两个候选定稿方案\n")
    A(ctx["pick_table"])
    A("### 5.1 方案①（推荐）定稿口径下的双路径 W1-W20\n")
    A(ctx["final_table"])
    A(ctx["health_table"])
    A(ctx["cross_table"])
    A(ctx["cross_note"])
    A("### 5.2 起飞率验证（方案A：多塔≥80%、单核≥60%，300 局 × 2 种子）\n")
    A(ctx["rate_table"])
    A(ctx["rate_note"])
    A("## 6. 最终定稿数值表与交接\n")
    A(ctx["final_numbers"])
    A(ctx["handoff"])
    return "\n".join(L)


# =============================================================================
# 8. main
# =============================================================================
KW_FINAL = dict(synergy_on=False, kappa_mode="tier", kr_mode="tier", kr_tiers=KR_TIERS_T1)
PICK1 = dict(hb=16.0, g=1.42, pity=True)     # 方案①：定稿数值不动 + 开 v0.3 已有的 pity 保底
PICK2 = dict(hb=16.0, g=1.34, pity=False)    # 方案②：纯数值，只动 hp_growth


def _cfg(path, hb, g, pity, **over):
    kw = dict(KW_FINAL)
    kw.update(over)
    c = v06_cfg(path=path, hp_growth=g, **kw)
    c["hp_base"] = hb
    c["pity"] = pity
    return c


def main():
    print("=" * 78)
    print("《守核 Corebound》Q-C6 数值口径核实 v0.6 · synergy ×1.5 残留")
    print("=" * 78)

    # ---------- Q1 成立性 ----------
    print("\n[Q1] 检查 ×1.5 是否在 v0.4 定稿口径下真实生效")
    ev = q1_evidence()
    q1_rows = []
    for path in ("A", "B"):
        e = ev[path]
        q1_rows.append([path, e["mix"], str(e["tag_tower_lv"]), str(e["tag_invest"]),
                        e["syn_hits_on"], f"×{e['syn_eff_on']:.4f}",
                        f"{e['dps_on']:,.0f}", f"{e['dps_off']:,.0f}",
                        f"÷{e['dps_ratio']:.4f}",
                        f"W{e['to_on']}", f"W{e['to_off']}",
                        e["w20_on"], e["w20_off"]])
    q1_table = _tbl(["路径", "终局构筑", "Tag塔层数", "Tag投入层数", "吃×1.5塔数",
                     "Syn 有效倍率", "终局DPS(有)", "终局DPS(无)", "DPS比",
                     "起飞(有)", "起飞(无)", "W20(有)", "W20(无)"], q1_rows)

    trA = syn_trace("A", v06_cfg(path="A", synergy_on=True))
    trB = syn_trace("B", v06_cfg(path="B", synergy_on=True))
    tr_rows = []
    for ta, tb in zip(trA, trB):
        tr_rows.append([f"W{ta['w']}", ta["hits"], f"×{ta['syn_eff']}",
                        tb["hits"], f"×{tb['syn_eff']}",
                        ta["fire_lv"].get("fire", 0), tb["fire_lv"].get("fire", 0)])
    trace_table = _tbl(["波次", "A·吃×1.5塔数", "A·Syn有效(base加权)", "B·吃×1.5塔数",
                        "B·Syn有效(base加权)", "A·fire塔层数", "B·fire塔层数"], tr_rows[:12])

    ea, eb = ev["A"], ev["B"]
    q1_note = (
        "\n→ **Q-C6 成立。** 在 v0.4 定稿口径下，`synergy_mult=1.5` **确实被触发、且真实乘进了每塔 DPS**，"
        "两条定稿路径**都吃了它**：\n\n"
        f"- **单核 A**：终局 `{ea['mix']}`，`fire` Tag 的**塔建筑卡层数之和 = {ea['tag_tower_lv'].get('fire', 0)} "
        f"≥ 阈值 3` → 主 Cannon 的 `syn = ×1.5`（命中 {ea['syn_hits_on']} 座）。\n"
        f"- **多塔 B**：终局 `{eb['mix']}`，`fire` 塔层数之和 = {eb['tag_tower_lv'].get('fire', 0)} → "
        f"**命中 {eb['syn_hits_on']} 座 Cannon**（含承载 `E=134` 共鸣的主 Cannon）。\n"
        f"- **有效倍率（按去掉 syn 后的 DPS 加权）**：A `×{ea['syn_eff_on']:.4f}`、B `×{eb['syn_eff_on']:.4f}` "
        f"—— 即**两条路径实质上 100% 的输出都吃到了这个 ×1.5**。\n"
        f"- 终局 DPS：A `{ea['dps_on']:,.0f} → {ea['dps_off']:,.0f}`（÷{ea['dps_ratio']:.5f}）、"
        f"B `{eb['dps_on']:,.0f} → {eb['dps_off']:,.0f}`（÷{eb['dps_ratio']:.5f}）。\n\n"
        "> ⚠️ **口径定性**：这是一条**已被设计层作废、但从未被引擎摘除**的乘区（概念 §2.4.7 明确 "
        "「Tag 协同**不再提供一次性乘区**，改为复利率档位」）。**v0.4 全套定稿数值是在叠着这个 ×1.5 的前提下扫出来的。**\n")

    trace_note = (
        "\n→ 逐波追踪：`fire` 塔建筑卡层数在 **W1 即 ≥3**（塔卡 `h` 一建就有层数），"
        "所以 ×1.5 **几乎从第一波就在生效**，不是后期才触发的局部增益。\n"
        "→ 这也解释了为什么它在 v0.4 扫参时**完全隐形**：它是一个**全程恒定的 ×1.5**，"
        "等价于把怪物 HP 基数整体下调 1/1.5 —— 只扫 `hp_growth` 是看不出它的存在的。\n"
        "> ⚠️ 读表注意：此表用 `base` 加权（与各乘区分解表口径一致），会**低估** ×1.5 的真实影响 "
        "（多塔 B 的 `Arrow(h=133)` 无 Tag、不吃 syn，但 `base` 很大）。真实影响见表 §1 的 DPS 比。\n")

    # ---------- 等价性 ----------
    print("\n[Q1b] 数学等价性检验：S1 + hp_base÷1.5 是否逐位复原 S0")
    eq = equivalence_test()
    equiv_table = _tbl(["路径", "hp_base(÷1.5)", "S0起飞", "S0 W20", "S0核心HP",
                        "S1′起飞", "S1′ W20", "S1′核心HP", "ΔW20"],
                       [[e["path"], e["hp_base"], f"W{e['to0']}", e["w200"], f"{e['hp0']:.0f}",
                         f"W{e['to1']}", e["w201"], f"{e['hp1']:.0f}", f"{e['d_w20']:+.2f}%"]
                        for e in eq])
    eqA, eqB = eq[0], eq[1]
    equiv_note = (
        f"\n→ **多塔 B：逐位复原。** 起飞波次 W{eqB['to0']}→W{eqB['to1']}、`W20 = {eqB['w200']} → {eqB['w201']}`"
        f"（差 {eqB['d_w20']:+.2f}%，仅浮点截断）→ **「移除 ×1.5」与「hp_base ÷ 1.5」在数学上互为反操作**。\n"
        f"→ **单核 A：近似复原但不等价。** 起飞波次 W{eqA['to0']}→W{eqA['to1']} 一致，但 "
        f"`W20 = {eqA['w200']} → {eqA['w201']}`（**{eqA['d_w20']:+.2f}%**），核心 HP "
        f"{eqA['hp0']:.0f}→{eqA['hp1']:.0f}。\n"
        "  → 差异来源不是乘区，而是**经济反馈环**：HP 基数降 1/1.5 → 早期清怪数变多 → 废铁收入变多 → "
        "构筑更强 → 终局倍数反而**高于**原定稿。单核 A 在 W1-3 会漏怪（核心掉 100 HP），这个反馈对它显著；"
        "多塔 B 全程不漏怪，故逐位相等。\n"
        "→ **结论：×1.5 是一个「全局恒定的 ÷1.5」，对伤害侧确实被其它系数完全吸收；"
        "但对整局轨迹不是严格等价（单核侧有 +5.9% 的经济反馈差）。**\n")

    # ---------- 场景矩阵 ----------
    print("\n[Q2] 场景矩阵：S0 基线 → S1 移除 → S2…S6 接入 κ_tag / κ_r 档位")
    scen = scenario_matrix(hp_growth=1.42)
    srows = []
    for s in scen:
        srows.append([s["name"], f"W{s['toA']}" if s["toA"] else "不起飞",
                      f"W{s['toB']}" if s["toB"] else "不起飞",
                      s["w20A"], s["w20B"], f"{s['ba']:.3f}",
                      f"{s['leadA']}/{s['leadB']}/{s['flips']}",
                      "✓" if s["in_window"][0] else "✗",
                      "✓" if s["in_window"][1] else "✗",
                      "✓" if s["ba"] < 1 else "✗",
                      "✓" if s["healthB"]["healthy"] else "⚠️"])
    scen_table = _tbl(["场景", "A起飞", "B起飞", "A_W20", "B_W20", "B/A",
                       "leadA/B/交叉", "A∈窗", "B∈窗", "B/A<1", "B健康"], srows)

    d = {s["key"]: s for s in scen}
    s0, s1, s2, s4, s6 = d["S0"], d["S1"], d["S2"], d["S4"], d["S6"]
    scen_note = (
        f"\n→ **S1（仅移除 ×1.5）**：A 起飞 W{s0['toA']}→**W{s1['toA']}**、B W{s0['toB']}→**W{s1['toB']}**（各推迟 2 波）；"
        f"W20 倍数 A {s0['w20A']}→{s1['w20A']}、B {s0['w20B']}→{s1['w20B']}；B/A 恒为 {s1['ba']}（不受影响）。\n"
        f"→ **S2（κ_tag 档位）与 S1 逐位相同** → 印证 GDD §5.2 的「零重标定」承诺："
        "A（2 塔）`κ = 0.10 − 0 = 0.10`、B（6 塔）`κ = 0.10 − 0.04 = 0.06`，与 v0.4 路径常量**逐位一致**。\n"
        f"→ **S3（κ_r MVP 两档 0.040/0.045）也与 S1 逐位相同** → 「未协同档」在本作是**死参数**"
        "（`fire` 塔层数 W1 即 ≥3，且 W1 时 `E_i = 0`，取任何值都无差别），与 `card-verify.md` §2.2 结论一致。\n"
        f"→ **S4（κ_r 三档 + 深度档 0.050）**：B 起飞 W{s1['toB']}→**W{s4['toB']}**、W20 {s1['w20B']}→**{s4['w20B']}**"
        f"（+{(s4['w20B']/s1['w20B']-1)*100:.0f}%），B/A {s1['ba']}→**{s4['ba']}**（仍 <1 ✓）。"
        "这是 Q-C5 已定稿的设计增益，与 ×1.5 无关。\n"
        f"→ **S6（κ_tag 深度档 ≥20 层 → 0.12，T1）实测过热**：A W20 {s4['w20A']}→**{s6['w20A']}**（6.1×）、"
        f"起飞 W{s4['toA']}→W{s6['toA']} → 🔴 **MVP 绝不能开深度档**（GDD §5.4 已标 T1，此处实测确认）。\n")

    # ---------- 失败模式 ----------
    print("\n[Q3] 单核 A 失败模式诊断（300 局）")
    fm0 = failure_mode("A", v06_cfg(path="A", synergy_on=True, kappa_mode="path", kr_mode="flat"))
    fm1 = failure_mode("A", _cfg("A", 16.0, 1.42, False))
    fm_rows = [
        ["S0 基线（×1.5 生效）", fm0["took_off"], fm0["dead_total"], fm0["dead_no_layer"],
         fm0["alive_no_takeoff"], str(fm0["dead"])],
        ["S4 移除 ×1.5 + 档位", fm1["took_off"], fm1["dead_total"], fm1["dead_no_layer"],
         fm1["alive_no_takeoff"], str(fm1["dead"])],
    ]
    fail_table = _tbl(["口径（单核 A，300 局）", "起飞", "中途被打爆", "其中「没叠起层数」",
                       "存活但 W20 未起飞", "死亡波分布"], fm_rows)
    fail_note = (
        f"\n→ **A 的起飞率不是被「平衡」压下去的，是被「发牌 RNG」压下去的。**\n"
        f"  - 基线：{fm0['dead_total']} 局被打爆，其中 **{fm0['dead_no_layer']} 局（{fm0['dead_no_layer']/max(1,fm0['dead_total']):.0%}）"
        f"终局强化层数 < 10** —— 即**整局没抽到几张 FireUp**，深度引擎根本没启动。\n"
        f"  - 移除 ×1.5 后：打爆 {fm1['dead_total']} 局（其中 {fm1['dead_no_layer']} 局没叠起层数），"
        f"另加 **存活但 W20 未起飞 {fm0['alive_no_takeoff']}→{fm1['alive_no_takeoff']} 局**。\n"
        f"  - 死亡波集中在 **W10-13**（起飞悬崖处）：基线 "
        + "、".join(f"W{k}:{v}" for k, v in fm0["dead"].items() if v >= 5) +
        "；移除后 " + "、".join(f"W{k}:{v}" for k, v in fm1["dead"].items() if v >= 5) + "。\n\n"
        "> 🔴 **这就是为什么 ×1.5 会被误当成「无害」**：它给单核 A 的**边际局**（没抽到 FireUp 的那些局）"
        "垫了一层 ×1.5 的地板，把起飞率从 47% 抬到 64%（刚好越过 60% 红线）。\n"
        "> → 摘掉它之后，**真正暴露的是「发牌 RNG 决定单核起飞」这个设计问题**，"
        "不是数值强度问题。这正是概念 §2.4.7 想避免的「归因滑向运气」。\n")

    # ---------- 4.1 hp_growth 单变量 ----------
    print("\n[Q4.1] hp_growth 单变量扫参（200 局）")
    sweep = sweep_hp_growth(KW_FINAL)
    swrows = []
    for s in sweep:
        swrows.append([fx(s["g"]), f"W{s['toA']}" if s["toA"] else "不起飞",
                       f"W{s['toB']}" if s["toB"] else "不起飞",
                       s["w20A"], s["w20B"], f"{s['ba']:.3f}",
                       f"{s['leadA']}/{s['leadB']}/{s['flips']}",
                       "✓" if s["winA"] else "✗", "✓" if s["winB"] else "✗",
                       "✓" if s["hB"]["healthy"] else "⚠️",
                       "✅" if s["ok"] else "—", s["obj"]])
    sweep_table = _tbl(["hp_growth", "A起飞", "B起飞", "A_W20", "B_W20", "B/A",
                        "leadA/B/交叉", "A∈窗", "B∈窗", "B健康", "可行", "obj"], swrows)

    # 起飞率随 hp_growth 的变化（单变量可行性判据）
    print("\n[Q4.1b] 起飞率随 hp_growth 变化（200 局）")
    gr = []
    for g in (1.28, 1.32, 1.34, 1.35, 1.36, 1.40, 1.42, 1.46):
        ra = takeoff_rate("A", _cfg("A", 16.0, g, False), runs=200, seed=20260930)
        rb = takeoff_rate("B", _cfg("B", 16.0, g, False), runs=200, seed=20260930)
        gr.append([fx(g), f"{ra['rate']*100:.1f}%", "✓" if ra["rate"] >= 0.60 else "✗",
                   f"{rb['rate']*100:.1f}%", "✓" if rb["rate"] >= 0.80 else "✗",
                   f"W{ra['med']}", f"W{rb['med']}"])
    rate_sweep_table = _tbl(["hp_growth", "A起飞率", "A≥60%", "B起飞率", "B≥80%",
                             "A中位起飞", "B中位起飞"], gr)
    g1 = {r[0]: r for r in gr}
    sweep_note = (
        "\n→ **起飞点本身没问题**：`hp_growth` 在 **1.34 ~ 1.50** 区间内多塔 B 的决定性起飞点都落在 W10-15"
        "（下表 §4.1），B/A 恒为 0.458 < 1，交叉领先 1 次，三阶段健康 → **移除 ×1.5 没有破坏起飞窗口。**\n"
        "→ **问题只在单核 A 的起飞率**：见下表，" + "、".join(
            f"`g={r[0]}` → A {r[1]}" for r in gr) + "。\n"
        "→ 🟡 **单变量可行，但区间是刀锋**（与 v0.4 §2 的「单变量无解」同族 —— 这次勉强相交）：\n"
        "  - A 起飞率 ≥60% 要求 `g ≤ ~1.35`（`g=1.36` 时 A 已掉到 58.5%）；\n"
        "  - B 决定性起飞 ∈ W10-15 要求 `g ≥ ~1.33`（`g=1.32` 时 B 已被推到 W9，出窗）；\n"
        "  - → **交集只有 `g ≈ 1.34 ~ 1.35`，宽约 0.02**，一个 `±0.01` 的抖动就破线。\n"
        "  → 根因：A 的失败是「发牌 RNG 没给 FireUp」（§3），降 `hp_growth` 是用**全局变简单**去硬抬，"
        "代价是把 W20 倍数放大约 2-4×（雪崩幅度失真，见 §5 方案②）。\n\n"
        + rate_sweep_table)

    # ---------- 4.2 联合扫参 ----------
    print("\n[Q4.2] hp_base × hp_growth × pity 联合扫参（200 局）")
    combos = [(16.0, 1.42, False), (16.0, 1.36, False), (16.0, 1.34, False),
              (12.0, 1.42, False), (10.7, 1.42, False),
              (16.0, 1.42, True), (16.0, 1.40, True), (16.0, 1.36, True),
              (14.0, 1.42, True)]
    joint = sweep_joint(KW_FINAL, combos, runs=200)
    jrows = []
    for s in joint:
        jrows.append([f"{s['hb']:g}", fx(s["g"]), "开" if s["pity"] else "关",
                      f"W{s['toA']}" if s["toA"] else "—", f"W{s['toB']}" if s["toB"] else "—",
                      s["w20A"], s["w20B"], f"{s['ba']:.3f}",
                      f"{s['rateA']*100:.1f}%", "✓" if s["okA"] else "✗",
                      f"{s['rateB']*100:.1f}%", "✓" if s["okB"] else "✗",
                      "✅" if s["ok"] else "—"])
    joint_table = _tbl(["hp_base", "hp_growth", "pity", "A起飞", "B起飞", "A_W20", "B_W20",
                        "B/A", "A起飞率", "≥60%", "B起飞率", "≥80%", "全部达标"], jrows)
    jd = {(s["hb"], s["g"], s["pity"]): s for s in joint}
    j_pity = jd[(16.0, 1.42, True)]
    j_134 = jd[(16.0, 1.34, False)]
    joint_note = (
        f"\n→ **`hp_base`（水平旋钮）单独降无效**：16→12→10.7 只能把 A 起飞率从 47% 抬到 "
        f"{jd[(12.0,1.42,False)]['rateA']*100:.1f}% / {jd[(10.7,1.42,False)]['rateA']*100:.1f}%，"
        "仍 <60% —— 因为 A 的失败是「引擎没启动」，HP 降多少都救不回一个没叠层的构筑。\n"
        f"→ **`pity`（v0.3 已实现的起飞保底：商店必出 1 张与主塔同 Tag 的强化卡）一开就够**："
        f"`hp_base=16 / hp_growth=1.42 / pity=开` → A 起飞率 **{j_pity['rateA']*100:.1f}%** ✓、"
        f"B **{j_pity['rateB']*100:.1f}%** ✓、B 决定性起飞 **W{j_pity['toB']}** ∈ 窗 ✓、B/A **{j_pity['ba']}** ✓。\n"
        f"→ **纯数值退路也存在**：`hp_base=16 / hp_growth=1.34 / pity=关` → "
        f"A **{j_134['rateA']*100:.1f}%** ✓、B **{j_134['rateB']*100:.1f}%** ✓、B W{j_134['toB']} ✓、"
        f"B/A {j_134['ba']} ✓，但 W20 倍数被抬到 {j_134['w20A']}/{j_134['w20B']}"
        f"（定稿 {s0['w20A']}/{s0['w20B']}，雪崩幅度放大约 "
        f"{j_134['w20B']/s0['w20B']:.1f}×）。\n")

    # ---------- 5. 两个候选 ----------
    picks = []
    for lbl, pk in (("① 推荐：定稿数值不动 + 开 pity 保底", PICK1),
                    ("② 备选：纯数值，hp_growth 1.42→1.34", PICK2)):
        stA = final_state("A", _cfg("A", **pk))
        stB = final_state("B", _cfg("B", **pk))
        _, lead, flips, fa, fb = cross_lead(stA["rows"], stB["rows"])
        ra = takeoff_rate("A", _cfg("A", **pk), runs=300, seed=20260930)
        rb = takeoff_rate("B", _cfg("B", **pk), runs=300, seed=20260930)
        ra2 = takeoff_rate("A", _cfg("A", **pk), runs=300, seed=20260931)
        rb2 = takeoff_rate("B", _cfg("B", **pk), runs=300, seed=20260931)
        sA, sB = stA["s"], stB["s"]
        ba = (sB["w20"] / sA["w20"]) if sA["w20"] else 0.0
        picks.append(dict(lbl=lbl, pk=pk, stA=stA, stB=stB, sA=sA, sB=sB,
                          lead=lead, flips=flips, fa=fa, fb=fb, ba=round(ba, 3),
                          ra=ra, rb=rb, ra2=ra2, rb2=rb2,
                          hA=stage_health(stA["rows"]), hB=stage_health(stB["rows"])))
    p1, p2 = picks
    pick_table = _tbl(["候选", "hp_base", "hp_growth", "pity", "A起飞", "B起飞",
                       "A_W20", "B_W20", "B/A", "A起飞率", "B起飞率", "交叉领先", "判定"],
                      [[p["lbl"], f"{p['pk']['hb']:g}", fx(p["pk"]["g"]),
                        "开" if p["pk"]["pity"] else "关",
                        f"W{p['sA']['takeoff']}", f"W{p['sB']['takeoff']}",
                        p["sA"]["w20"], p["sB"]["w20"], f"{p['ba']:.3f}",
                        f"{p['ra']['rate']*100:.1f}%", f"{p['rb']['rate']*100:.1f}%",
                        f"{p['lead']['A']}/{p['lead']['B']}/{p['flips']}",
                        "✅ 全达标" if (p["ra"]["rate"] >= 0.60 and p["rb"]["rate"] >= 0.80
                                    and 10 <= (p["sB"]["takeoff"] or 0) <= 15 and p["ba"] < 1.0)
                        else "⚠️"]
                       for p in picks])

    # 方案① 明细
    rowsA, rowsB = p1["stA"]["rows"], p1["stB"]["rows"]
    dA = {r["w"]: r for r in rowsA}
    dB = {r["w"]: r for r in rowsB}
    frows = []
    for w in range(1, 21):
        ra_, rb_ = dA.get(w), dB.get(w)
        if not ra_ or not rb_:
            continue
        frows.append([f"W{w}", f"{ra_['eff_dps']:,.0f}", f"{rb_['eff_dps']:,.0f}",
                      fx(ra_["ratio"], 3), fx(rb_["ratio"], 3),
                      fx(ra_["core_hp"], 0), fx(rb_["core_hp"], 0),
                      ra_["towers"], rb_["towers"]])
    final_table = _tbl(["波次", "单核DPS", "多塔DPS", "单核ratio", "多塔ratio",
                        "单核核心HP", "多塔核心HP", "单核塔", "多塔塔"], frows)
    health_table = _tbl(["路径", "苟活期W1-9存活", "成型期W13-20上升", "雪崩期W16→20增速", "健康"],
                        [["单核 A", "✓" if p1["hA"]["survive"] else "✗",
                          "✓" if p1["hA"]["rise"] else "✗", fx(p1["hA"]["grow"]),
                          "✅" if p1["hA"]["healthy"] else "⚠️"],
                         ["多塔 B", "✓" if p1["hB"]["survive"] else "✗",
                          "✓" if p1["hB"]["rise"] else "✗", fx(p1["hB"]["grow"]),
                          "✅" if p1["hB"]["healthy"] else "⚠️"]])
    cross, lead1, flips1, fa1, fb1 = cross_lead(rowsA, rowsB)
    cross_table = _tbl(["波次", "单核A ratio", "多塔B ratio", "领先"],
                       [[f"W{w}", fx(x), fx(y), who] for w, x, y, who in cross])
    cross_note = (f"\n→ **A 领先 {lead1['A']} 波 / B 领先 {lead1['B']} 波 / 交叉 {flips1} 次**"
                  f"（B 首领先 W{fb1}、A 首领先 W{fa1}）→ "
                  + ("✅ 真正的交叉领先（B 前期苟活、A 后期反超）。"
                     if flips1 >= 1 and lead1["A"] < 20 and lead1["B"] < 20
                     else "⚠️ 交叉领先退化。") + "\n")

    def rr(name, r, tgt):
        return [name, f"{r['rate']*100:.1f}%", f"{r['surv']*100:.1f}%",
                f"W{r['med']}" if r["med"] else "—", f"{tgt*100:.0f}%",
                "✓" if r["rate"] >= tgt else "✗"]
    rate_table = _tbl(["路径/玩家", "起飞率", "存活率", "中位起飞波", "目标", "判定"],
                      [rr("方案① 单核 A（seed1）", p1["ra"], 0.60),
                       rr("方案① 多塔 B（seed1）", p1["rb"], 0.80),
                       rr("方案① 单核 A（seed2）", p1["ra2"], 0.60),
                       rr("方案① 多塔 B（seed2）", p1["rb2"], 0.80),
                       rr("方案② 单核 A（seed1）", p2["ra"], 0.60),
                       rr("方案② 多塔 B（seed1）", p2["rb"], 0.80)])
    rate_note = (
        f"\n→ **方案①**：单核 **{p1['ra']['rate']*100:.1f}%** ≥60% ✓、多塔 **{p1['rb']['rate']*100:.1f}%** ≥80% ✓，"
        f"换种子后 {p1['ra2']['rate']*100:.1f}% / {p1['rb2']['rate']*100:.1f}% 仍双达标。\n"
        f"→ **方案②**：单核 {p2['ra']['rate']*100:.1f}% ✓、多塔 {p2['rb']['rate']*100:.1f}% ✓（同样双达标）。\n"
        f"→ 两方案都过线；差别在**代价**（见 §6.2）：方案① 不动任何定稿数值、W20 雪崩幅度几乎不变；"
        f"方案② 只动一个数，但把 W20 倍数放大到 {p2['sB']['w20']/s0['w20B']:.1f}×（多塔）/ "
        f"{p2['sA']['w20']/s0['w20A']:.1f}×（单核）。\n")

    # ---------- 6. 结论 ----------
    final_numbers = (
        "### 6.1 Q-C6 三问答复\n\n"
        "| # | 问题 | 答复 |\n|---|---|---|\n"
        f"| **①** | **Q-C6 是否成立？** | ✅ **成立。** v0.4 定稿口径下 `synergy_mult=1.5` 真实触发并乘进每塔 DPS；"
        f"两条定稿路径**都吃了它**（A 命中 {ea['syn_hits_on']} 座、B 命中 {eb['syn_hits_on']} 座）。"
        f"有效倍率 A ×{ea['syn_eff_on']:.4f} / B ×{eb['syn_eff_on']:.4f}（≈ 全场 ÷1.5，"
        f"实测 DPS 比 A ÷{ea['dps_ratio']:.4f} / B ÷{eb['dps_ratio']:.4f}） |\n"
        f"| **②** | **移除 + 接档位后是否还在 W10-15 窗口？** | "
        f"✅ **起飞点没问题，起飞率有问题。** 起飞点：A **W{s0['toA']}→W{s4['toA']}**、B **W{s0['toB']}→W{s4['toB']}**"
        f"（B 仍在窗内、A 仍偏早，与 v0.4 定稿同形态）；B/A {s0['ba']}→**{s4['ba']} <1** ✓、交叉 {s4['flips']} 次 ✓。"
        f"**但单核 A 起飞率 64.0%→47.0%，跌破 60% 红线** → 需联调；单靠 `hp_growth` 只有 "
        f"`g ≈ 1.34~1.35` 一条刀锋区间可行（±0.01 即破线） |\n"
        f"| **③** | **之前 v0.4 定稿是否仍有效？** | "
        f"✅ **数值仍有效，不需要重标定**（`hp_growth` / `hp_base` / `focus_per_layer` / κ / κ_r 全都不动），"
        f"**但必须做两件事**：① 摘掉 ×1.5（口径修正）；② 补一条**发牌保底**或**接受 hp_growth 1.34**。"
        f"只摘不补 → A 起飞率 47% 破线 |\n\n"
        "### 6.2 最终定稿数值锚点\n\n"
        "| 参数 | v0.4 定稿 | **Q-C6 核实后定稿** | 说明 |\n|---|---|---|---|\n"
        "| `synergy_threshold` / `synergy_mult`（一次性 Tag 乘区） | 3 / 1.5（**生效**） | "
        "**摘除** | 🔴 概念 §2.4.7 已作废；引擎从未摘 |\n"
        "| `κ` 来源 | 路径常量 1.10 / 1.06 | **GDD §5.2：κ = κ_tag − 0.01·clamp(N−2,0,4)，下限 0.02** | 端点逐位一致，**零重标定** |\n"
        "| `κ_tag` 档位（MVP） | 从未被引擎实现 | **0–2 层 0.06 / ≥3 层 0.10** | 🆕 接回概念 §2.4.7 |\n"
        "| `κ_tag` 深度档（≥20 层 0.12） | — | **MVP 不开**（实测 A W20 ×6.1，过热） | T1 |\n"
        "| `κ_r` 档位 | flat 0.045 | **0.040 / 0.045 / 0.050（阈值 3 / 20 层）+ 中性塔恒取 0.045** | card-verify Q-C5 定稿 |\n"
        "| `StackCap` 档位 50/100/150 | 100 恒定 | **可选**（实测惰性，只通过改变 AI 决策间接影响 ±7%） | 非本轮差异源 |\n"
        f"| 怪物 HP 成长率 `hp_growth` | 1.42 | **1.42（方案① 不动）** / `1.34`（方案② 备选） | 见 §6.3 |\n"
        "| 怪物 HP 基数 `hp_base` | 16 | **16（不动）** | 单独降无效（§4.2） |\n"
        "| `focus_per_layer` | 0.06 | **0.06（不动）** | — |\n"
        "| 共鸣门槛 / 塔位 / 软 cap 衰减 | Lv3 / 6 / 1.03 | **同左（不动）** | — |\n"
        "| Empowerment T1（Q11） | 关闭 | **关闭（不动）** | — |\n\n"
        "### 6.3 双路径定稿指标（方案①）\n\n"
        "| 指标 | 单核 A | 多塔 B | 判据 | v0.4 定稿（含 ×1.5） |\n|---|---|---|---|---|\n"
        f"| 起飞波次（决定性） | **W{p1['sA']['takeoff']}** | **W{p1['sB']['takeoff']}** | B ∈ W10-15 | "
        f"W{s0['toA']} / W{s0['toB']} |\n"
        f"| W20 DPS/HP 倍数 | {p1['sA']['w20']} | {p1['sB']['w20']} | — | {s0['w20A']} / {s0['w20B']} |\n"
        f"| 起飞率（300 局） | **{p1['ra']['rate']*100:.1f}%** | **{p1['rb']['rate']*100:.1f}%** | A≥60% / B≥80% | "
        f"64.0% / 95.3% |\n"
        f"| 三阶段健康 | {'✅' if p1['hA']['healthy'] else '⚠️'} | {'✅' if p1['hB']['healthy'] else '⚠️'} | 雪崩增速 >1 | — |\n"
        f"| B/A（后期 carry 归属） | — | **{p1['ba']}** | <1 | {s0['ba']} |\n"
        f"| 交叉领先 | — | **{p1['lead']['A']}/{p1['lead']['B']}/{p1['flips']}** | ≥1 次 | "
        f"{s0['leadA']}/{s0['leadB']}/{s0['flips']} |\n")

    handoff = (
        "### 6.4 交接与待审批项\n\n"
        "**必须回写文档（3 处）**\n"
        "1. 🔴 `card-system` GDD §10 **Q-C6 定稿为「确有其事、已摘除」**。\n"
        "2. 🔴 `damage-pipeline` GDD 乘区清单：**删除 B3 `Syn`（一次性 ×1.5）**，"
        "Tag 的作用改由 **A6 TagTier → κ / κ_r / StackCap** 表达（概念 §2.4.7 早已这么写，是引擎没跟上）。\n"
        "3. 🟡 `card-verify.md` 的 Q-C5 结论（B 起飞 W10、W20 14.95、B/A 0.46）**是在 ×1.5 之上测的**，"
        "需在摘除后重述（本轮摘除后：B 起飞 W12、W20 9.97、B/A 0.458 —— 结论方向不变，数值需替换）。\n\n"
        "**待用户/主理人拍板（1 项，二选一）**\n"
        f"- **方案①（我推荐）**：`hp_growth / hp_base / focus / κ / κ_r` **一个都不改**，只打开 v0.3 已实现的 "
        f"`pity` 起飞保底 → A 起飞率 {p1['ra']['rate']*100:.1f}%、B {p1['rb']['rate']*100:.1f}%、"
        f"B 起飞 W{p1['sB']['takeoff']} ∈ 窗、W20 雪崩幅度与定稿同量级。\n"
        f"  代价：`pity` 是**机制改动**（商店必出 1 张与主塔同 Tag 的强化卡），需要策划确认它不违反 "
        "「失败归因于决策而非运气」（我判断**反而有利于**该原则 —— 见 §3）。\n"
        f"- **方案②（纯数值退路）**：`hp_growth 1.42 → 1.34`，不动任何机制 → "
        f"A {p2['ra']['rate']*100:.1f}%、B {p2['rb']['rate']*100:.1f}% 同样双达标；"
        f"但 W20 倍数放大到 {p2['sA']['w20']}/{p2['sB']['w20']}（定稿 {s0['w20A']}/{s0['w20B']}），"
        "雪崩幅度失真约 2-4×；且可行区间是刀锋（`g≈1.34~1.35`，±0.01 破线）—— "
        "后续只要改地图 / 塔位拓扑，就得重扫。方案① 的可行区间则宽得多（`g=1.36~1.42` 全达标），**抗扰动**。\n\n"
        "**知识缺口 / 风险标注**\n"
        "- 本次只核到**纸面模拟**层。真实引擎若已按 GDD 实现 A6 TagTier，结算顺序需与本报告一致"
        "（κ 档位在 B2 之前算；`N_tower` 变化时全场重算）。\n"
        "- `StackCap` 档位在两条定稿路径上**实测惰性**（层数 <50 时「未协同档」永不触发；≥50 层必然已协同，"
        "cap=100 与 v0.4 一致），MVP 可先不实现。\n"
        "- 单核 A 的起飞率**对发牌 RNG 高度敏感**（约 1/3 的失败是「整局没抽到 FireUp」）。"
        "这本身就是一条设计风险：若不开保底，A 的成败有相当部分归因于运气，与概念 §4.1 相悖 —— "
        "**这一点建议提给策划单独立项**（不阻塞本次定稿）。\n")

    headline = _tbl(
        ["#", "主理人问的", "我的答案", "关键数"],
        [["Q-C6①", "×1.5 是否真的生效？", "✅ **成立**",
          f"基线终局：A 命中 {ea['syn_hits_on']} 座（有效 ×{ea['syn_eff_on']:.4f}）、"
          f"B 命中 {eb['syn_hits_on']} 座（有效 ×{eb['syn_eff_on']:.4f}）。"
          f"移除后终局 DPS A ÷{ea['dps_ratio']:.4f}、B ÷{eb['dps_ratio']:.4f}（≈ 精确的 ÷1.5）"],
         ["Q-C6②", "移除后是否还在 W10-15 窗口？", "✅ 起飞点在窗，⚠️ 起飞率破线",
          f"起飞点：A W{s0['toA']}→**W{s4['toA']}**、B W{s0['toB']}→**W{s4['toB']}**（B 仍 ∈ W10-15 ✓、"
          f"B/A {s4['ba']}<1 ✓）；但 **A 起飞率 64.0%→47.0%（<60% ✗）**，"
          f"单靠 hp_growth 只有 `g≈1.34~1.35` 一条刀锋区间可行（±0.01 即破线）"],
         ["Q-C6③", "之前 v0.4 定稿是否仍有效？",
          "✅ **数值有效，无需重标定**（摘乘区 + 补保底即可）",
          f"方案①：`hp_growth=1.42` 不动 + 开 `pity` → A {p1['ra']['rate']*100:.1f}% / "
          f"B {p1['rb']['rate']*100:.1f}%、B 起飞 W{p1['sB']['takeoff']}、B/A {p1['ba']}；"
          f"方案②（纯数值）：`hp_growth=1.34` → A {p2['ra']['rate']*100:.1f}% / B {p2['rb']['rate']*100:.1f}%"]])

    ctx = dict(headline=headline, q1_table=q1_table, q1_note=q1_note,
               trace_table=trace_table, trace_note=trace_note,
               equiv_table=equiv_table, equiv_note=equiv_note,
               scen_table=scen_table, scen_note=scen_note,
               fail_table=fail_table, fail_note=fail_note,
               sweep_table=sweep_table, sweep_note=sweep_note,
               joint_table=joint_table, joint_note=joint_note,
               pick_table=pick_table, final_table=final_table,
               health_table=health_table, cross_table=cross_table, cross_note=cross_note,
               rate_table=rate_table, rate_note=rate_note,
               final_numbers=final_numbers, handoff=handoff)
    rp = os.path.join(OUT_DIR, "q-c6-verify.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(build_report(ctx))

    for path, rows in (("A", rowsA), ("B", rowsB)):
        sv.write_csv(rows, f"sim_v06_path{path}.csv")

    print("\n" + "=" * 78)
    print("【Q1】×1.5 生效：A hits=%d 有效×%.4f / B hits=%d 有效×%.4f"
          % (ea["syn_hits_on"], ea["syn_eff_on"], eb["syn_hits_on"], eb["syn_eff_on"]))
    print("【Q1】移除后 DPS：A %.0f→%.0f (÷%.5f) / B %.0f→%.0f (÷%.5f)"
          % (ea["dps_on"], ea["dps_off"], ea["dps_ratio"],
             eb["dps_on"], eb["dps_off"], eb["dps_ratio"]))
    for s in scen:
        print("【场景】%-46s A W%-3s B W%-3s W20 %7.2f/%6.2f B/A %.3f 交叉%d"
              % (s["name"], s["toA"], s["toB"], s["w20A"], s["w20B"], s["ba"], s["flips"]))
    for p in picks:
        print("【%s】A W%s B W%s W20 %.2f/%.2f B/A %.3f | 起飞率 A %.1f%% B %.1f%% | 交叉%d"
              % (p["lbl"], p["sA"]["takeoff"], p["sB"]["takeoff"], p["sA"]["w20"],
                 p["sB"]["w20"], p["ba"], p["ra"]["rate"] * 100, p["rb"]["rate"] * 100,
                 p["flips"]))
    print("[输出] %s" % rp)
    return ctx


if __name__ == "__main__":
    main()
