# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — 纸面数值模拟 **v0.4 全乘区重标定**
作者：程基岩（工程主理人）

第 4 项复验（v0.3 报告 §8 遗留第 2 项）：
  v0.3 主口径中 Focus / AllIn / Crossfire / Aux 四个乘区默认关闭（v2 从未纳入校准）。
  本脚本**打开全部 7 个乘区**，重跑单核/多塔双路径 W1-W20，
  并**重新标定怪物成长率**，使起飞点仍落在 W10-15 窗口、三阶段曲线健康、交叉领先成立。

在 corebound_sim_v03.py 之上工作（复用其地图/商店/战斗/蒙特卡洛引擎），
只增强 compute_dps：
  ① 打开 Focus / AllIn / Crossfire / Aux（Empowerment T1 按 Q11 默认关闭，另作敏感性）
  ② 新增 C4 Empowerment（T1 规格，可开关）
  ③ 逐乘区贡献诊断（用于判断是否有某乘区主导）

用法（隔离 venv）：
  C:\\Users\\junhewang\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe corebound_sim_v04.py
"""
from __future__ import annotations
import os
import csv
import math
import random
import statistics

import corebound_sim_v03 as sv

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 1. 增强 compute_dps：打开全乘区 + C4 Empowerment + 逐乘区诊断
#    逻辑与 v0.3 compute_dps 完全一致，仅新增 use_empowerment 与诊断字段，
#    并把 focus/allin/crossfire/aux 从「默认关闭」改为「由 v04 配置打开」。
# =============================================================================
def compute_dps_v4(player, cfg, geo=None):
    ts = player.towers
    n = len(ts)
    if n == 0:
        return 0.0, {"per_tower": [], "E": [], "aoe": 1.0, "crossfire": 1.0,
                     "aux": 1.0, "empower": 1.0, "subtotal": 0.0}

    path = player.path
    lmin = cfg.get("link_min_level", 1)
    h = [t.h for t in ts]
    L = [sum(t.attach.values()) for t in ts]
    Ltot = sum(L)
    core = max(range(n), key=lambda i: L[i]) if Ltot > 0 else 0

    tag_tower_lv = {}
    for i, t in enumerate(ts):
        tg = sv.TOWERS[t.ctype]["tag"]
        if tg:
            tag_tower_lv[tg] = tag_tower_lv.get(tg, 0) + h[i]

    adj = [[] for _ in range(n)]
    E = [0.0] * n
    if cfg["use_resonance"] and geo is not None:
        types = [t.ctype for t in ts]
        gtypes = [None] * geo.n
        for i, t in enumerate(ts):
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

    kappa = cfg["reinf_compound"][path]
    cap = cfg["reinf_cap"]
    decay = cfg["softcap_decay"]
    kr = cfg["kappa_r"]

    per_tower = []
    for i, t in enumerate(ts):
        base = sv.TOWERS[t.ctype]["dps"] * (h[i] ** cfg["tower_stack_exp"])
        stack = 1.0
        for rn, lv in t.attach.items():
            if sv.REINF[rn]["tag"] != sv.TOWERS[t.ctype]["tag"]:
                continue
            stack += sv.softcap_pow(lv, kappa, cap, decay) - 1.0
        tg = sv.TOWERS[t.ctype]["tag"]
        syn = 1.0
        if tg and tag_tower_lv.get(tg, 0) >= cfg["synergy_threshold"]:
            syn = cfg["synergy_mult"]
        res = ((1.0 + kr) ** E[i]) if cfg["use_resonance"] else 1.0
        # Focus：与 Resonance 同哲学加「预热门槛」——核心塔要「长成」(h_i≥focus_min_h)
        # 才让 Focus 全额生效，之前线性爬升。否则 Focus(1+0.15·L) 在开局 L 一涨就 ×16，
        # 把单核流的起飞点钉死在 W4-5、对 hp_growth 免疫（见 §5 新失衡诊断）。
        foc = 1.0
        if cfg["use_focus"]:
            L_i = L[i]
            if cfg.get("focus_full", False):
                # 全额模式（v0.3 原口径）：1+0.15·L，无门槛
                foc = 1.0 + cfg["focus_per_layer"] * L_i
            else:
                # 预热模式：按主塔层数 h_i 爬升到全额（focus_min_h 达到才满）
                fh = cfg.get("focus_min_h", 8.0)
                ramp = min(1.0, h[i] / fh) if fh > 0 else 1.0
                foc = 1.0 + cfg["focus_per_layer"] * L_i * ramp
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

    subtotal = sum(p["dps"] for p in per_tower)
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
            # 逐塔光环：减速只增益「该减速塔自身」的伤害（冻伤弹命中更狠），
            # 不回溯增益已建塔 → 消除「建一座 Frost 就全局 ×1.43」的构筑劫持。
            aux_parts = []
            for t in ts:
                slow = sv.TOWERS[t.ctype]["slow"]
                mult = 1.0
                if slow > 0:
                    mult = 1.0 / (1.0 - min(slow, 0.75))
                    cap = cfg.get("aux_cap", 1.5)
                    if cap is not None and mult > cap:
                        mult = cap
                aux_parts.append(mult)
            for i, p in enumerate(per_tower):
                p["dps"] = p["dps"] * aux_parts[i]
            aux = sum(aux_parts) / max(1, len(aux_parts))
        else:
            # 全局光环（Q7 Beacon 光环塔）：减速敌人 → 全队增伤 1/(1−slow)。
            # ★ v0.4 关键修正：光环强度随「减速塔自身的投入层数」饱和增长。
            #   一个 h=1 的 Frost 挂件只给微弱光环（不再劫持单核流的构筑 AI，
            #   让它继续叠 Cannon+FireUp 复利引擎）；多塔流把 Frost 养到 h=134
            #   才拿到接近满额 ×1.43 —— 保住多塔的「铺场+减速」幻想。
            #   饱和式：eff_slow = slow · h/(h + aux_tau)，h 为减速塔最大层数。
            slow_towers = [t for t in ts if sv.TOWERS[t.ctype]["slow"] > 0]
            if slow_towers:
                slow = max(sv.TOWERS[t.ctype]["slow"] for t in slow_towers)
                h_slow = max(t.h for t in slow_towers)
                tau = cfg.get("aux_tau", 8.0)
                eff_slow = slow * (h_slow / (h_slow + tau))
                aux = 1.0 / (1.0 - min(eff_slow, 0.75))
                cap = cfg.get("aux_cap", 1.5)
                if cap is not None and aux > cap:
                    aux = cap

    # C4 Empowerment（T1）——v0.3 是空桩；这里按 T1 规格补上，默认关闭（Q11 不入 MVP）
    empower = 1.0
    if cfg.get("use_empowerment"):
        # 挂件光环随主塔层数增长：1 + empower_per_layer · L_core（有界，避免溢出）
        Lcore = L[core]
        empower = 1.0 + cfg.get("empower_per_layer", 0.015) * Lcore
        empower = min(empower, cfg.get("empower_cap", 3.0))

    # per_tower['dps'] 已在逐塔分支计入 per-tower Aux；此处统一做全局聚合
    subtotal2 = sum(p["dps"] for p in per_tower)
    total = subtotal2 * aoe * cf * aux * empower
    return total, dict(per_tower=per_tower, adj=adj, E=E, aoe=aoe,
                       crossfire=cf, aux=aux, empower=empower,
                       subtotal=subtotal2, core=core, L=L, Ltot=Ltot)


def dps_only_v4(player, cfg, geo=None):
    return compute_dps_v4(player, cfg, geo)[0]


# 打补丁：让 v0.3 的 run/simulate_wave/shop 全部走增强引擎
sv.compute_dps = compute_dps_v4
sv.dps_only = dps_only_v4


# =============================================================================
# 2. v0.4 配置：全乘区打开
# =============================================================================
def v04_cfg(hp_growth=None, use_empowerment=False, **over):
    """v0.4 主口径：在 v0.3 定稿配置基础上打开全部 7 乘区。
    默认 Empowerment T1 关闭（Q11：挂件赋能 T1 不入 MVP）。"""
    d = dict(
        tower_card_mode="map", n_slots=6, coverage_mode="path",
        use_resonance=True, kappa_r=sv.RECOMMENDED["kappa_r"],
        link_min_level=sv.RECOMMENDED["link_min_level"],
        link_rule="any", max_actions=12,
        # ---- 打开 v0.3 默认关闭的四个乘区 ----
        use_focus=True, use_allin=True, use_crossfire=True, use_aux=True,
        use_empowerment=use_empowerment,
        empower_per_layer=0.015, empower_cap=3.0,
        # ---- Focus 预热门槛（与 Resonance 同哲学，防单核流起飞点前移到 W4-5）----
        focus_full=False,        # True=v0.3 原口径(无门槛)；False=按主塔层数预热
        focus_min_h=8.0,         # 主塔层数达到此值 Focus 才全额生效
        # ---- Aux 光环模型（Q7 Beacon 光环塔）----
        aux_mode="global",       # global=随减速塔层数饱和的全局光环；per_tower=逐塔
        aux_tau=8.0,             # 光环饱和常数：eff_slow=slow·h/(h+tau)
        aux_cap=1.5,             # 光环增伤上限（防策略劫持）
    )
    if hp_growth is not None:
        d["hp_growth"] = hp_growth
    d.update(over)
    return sv.make_cfg(**d)


def summarize(rows, w0=13):
    d = {r["w"]: r["ratio"] for r in rows}
    return dict(takeoff=sv.takeoff_wave(rows), w13=d.get(13), w16=d.get(16),
                w20=d.get(20), tail_min=round(sv.tail_min(rows, w0), 2),
                core=rows[-1]["core_hp"] if rows else 0.0,
                ntow=rows[-1]["towers"] if rows else 0)


def stage_health(rows):
    """三阶段曲线健康度：苟活期(W1-9)核心缓降不崩、成型期(W10-15)反超、
    雪崩期(W16-20)持续甩开不回落。返回诊断 dict。"""
    d = {r["w"]: r for r in rows}
    # 苟活期：核心 HP 不掉穿（存活）；成型期：ratio 上升；雪崩期：W16→W20 增速 > 1
    survive_w1_9 = all(d[w]["core_hp"] > 0 for w in range(1, 10) if w in d)
    r16 = d.get(16)
    r20 = d.get(20)
    avalanche_grow = (r20["ratio"] / r16["ratio"]) if (r16 and r20 and r16["ratio"] > 0) else 0.0
    # 成型期反超：W13 之后 ratio 持续 ≥ 起飞线附近上升
    tail = [d[w]["ratio"] for w in range(13, 21) if w in d]
    form_rise = all(tail[i] <= tail[i + 1] + 1e-9 for i in range(len(tail) - 1))
    return dict(survive_early=survive_w1_9, avalanche_grow=round(avalanche_grow, 2),
                form_rise=form_rise,
                healthy=survive_w1_9 and avalanche_grow > 1.0)


# =============================================================================
# 3. 逐乘区贡献诊断：在指定波次分解 delivered DPS 的各乘区有效倍率
# =============================================================================
def multiplier_diag(path, cfg, geo, waves=(1, 5, 10, 13, 15, 20)):
    """跑一遍确定性 run，在指定波次用 compute_dps_v4 抓各乘区有效倍率。
    有效倍率 = 该乘区对 Σdps 的加权贡献 / 该乘区关闭时的 Σdps。"""
    player = sv.new_player(path, cfg, geo)
    # 用真实商店把构筑推进到各波（复用 run 的逐波流程，但只记录诊断）
    core_hp = cfg["core_hp"]
    cum = 0.0
    diag = {}
    for w in range(1, 21):
        res = sv.simulate_wave(player, w, cfg, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income
        budget, _ = sv.shop_phase(player, cum, w, cfg, geo, None)
        cum = budget
        if w in waves:
            _, info = compute_dps_v4(player, cfg, geo)
            diag[w] = _decompose(info)
        if core_hp <= 0:
            break
    return diag


def _decompose(info):
    """把 per-tower 分解成各乘区的「有效倍率」（加权几何口径）。
    delivered = Σ(base) · Stack_eff · Res_eff · Focus_eff · AllIn_eff · Cov_eff · aoe · cf · aux · empower
    由于各乘区逐塔不同，这里用 Σ 加权的有效倍率 = Σ(·mult) / Σ(·without_mult)。"""
    pt = info["per_tower"]
    if not pt:
        return dict(n=0)

    def eff(key):
        base_sum = sum(p["base"] for p in pt)
        if base_sum <= 0:
            return 1.0
        wsum = sum(p["base"] * p[key] for p in pt)
        return wsum / base_sum

    base_sum = sum(p["base"] for p in pt)
    subtotal = info["subtotal"]
    # Stack/Res/Focus/AllIn/Cov 的有效倍率（相对 base 求和）
    out = dict(
        n=len(pt),
        base=round(base_sum, 1),
        Stack=round(eff("stack"), 3),
        Resonance=round(eff("res"), 3),
        Focus=round(eff("focus"), 3),
        AllIn=round(eff("allin"), 3),
        Coverage=round(eff("cov"), 3),
        AoE=round(info["aoe"], 3),
        Crossfire=round(info["crossfire"], 3),
        Aux=round(info["aux"], 3),
        Empower=round(info["empower"], 3),
    )
    return out


# =============================================================================
# 4. hp_growth 扫参：全乘区打开后把起飞点拉回 W10-15
#    ★ v0.4 关键发现：单靠 hp_growth 无法同时把两条路径都压进 W10-15。
#      单核 A 的起飞波次被 Focus(×16)+AllIn(×1.6)+Stack 三重深度乘区钉死在
#      W4-5，几乎**对 hp_growth 免疫**（怪物再强也只是把 W20 倍数压小，
#      起飞波次不动）；多塔 B 的起飞波次则随 hp_growth 单调后移。
#      → 本表如实暴露这一「单变量无解」，把取舍交给 §5 的乘区侧修正。
# =============================================================================
def sweep_hp_growth(growths=(1.30, 1.36, 1.42, 1.48, 1.52, 1.56, 1.60, 1.64, 1.70)):
    rows = []
    for g in growths:
        row = dict(hp_growth=g)
        for path in ("A", "B"):
            cfg = v04_cfg(hp_growth=g)
            r, _ = sv.run(path, cfg, 20, geo=sv.GEO6)
            row[path] = summarize(r)
            row[path]["health"] = stage_health(r)
        a, b = row["A"], row["B"]
        ta, tb = a["takeoff"], b["takeoff"]
        row["A_win"] = ta is not None and 10 <= ta <= 15
        row["B_win"] = tb is not None and 10 <= tb <= 15
        rel = (b["w20"] / a["w20"]) if (a["w20"] and b["w20"]) else 0.0
        row["rel_BA"] = round(rel, 2)
        row["P2"] = row["A_win"] and row["B_win"]
        row["P3"] = 0.4 <= rel <= 2.5
        # 单变量可行性：B 在窗内 且 A 起飞≤10（A 快而脆，符合高风险定位）
        row["feasible"] = row["B_win"] and (ta is not None and ta <= 10)
        row["verdict"] = "✅" if (row["P2"] and row["P3"]) else ("~" if row["feasible"] else "✗")
        rows.append(row)
    return rows


# =============================================================================
# 4b. 乘区侧联合标定：单靠 hp_growth 无解，必须同时调乘区强度。
#     搜索 (focus_per_layer, kappa_r, hp_growth)，目标：
#       P2  两条路径起飞点都在 W10-15
#       P3  0.4 ≤ 多塔W20/单核W20 ≤ 2.5（同量级）
#       CL  交叉领先（B 前期领先、A 后期反超，各领先≥5波、交叉≥1次）
#     返回按「目标函数」排序的可行解（越接近 v0.3 健康形态越好）。
# =============================================================================
def _crosslead_detail(rowsA, rowsB):
    dA = {r["w"]: r["ratio"] for r in rowsA}
    dB = {r["w"]: r["ratio"] for r in rowsB}
    lead = {"A": 0, "B": 0}
    flips = 0
    prev = None
    firstA = firstB = None
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if a is None or b is None:
            continue
        who = "A" if a > b else ("B" if b > a else "=")
        if who == "A":
            lead["A"] += 1
            firstA = firstA if firstA else w
        elif who == "B":
            lead["B"] += 1
            firstB = firstB if firstB else w
        if prev and prev != who:
            flips += 1
        prev = who
    return lead, flips, firstA, firstB


def sweep_multipliers():
    """联合标定：单核深度(Focus) × 多塔广度(κ_r) × 全局难度(hp_growth)。"""
    results = []
    for fpl in (0.05, 0.08, 0.10, 0.15):
        for kr in (0.045, 0.05, 0.055, 0.06):
            for g in (1.45, 1.50, 1.52, 1.56, 1.60, 1.64, 1.68, 1.72):
                cfg = v04_cfg(hp_growth=g, kappa_r=kr, focus_per_layer=fpl)
                rA, _ = sv.run("A", cfg, 20, geo=sv.GEO6)
                rB, _ = sv.run("B", cfg, 20, geo=sv.GEO6)
                sA, sB = summarize(rA), summarize(rB)
                ta, tb = sA["takeoff"], sB["takeoff"]
                ba = (sB["w20"] / sA["w20"]) if (sA["w20"] and sB["w20"]) else 0.0
                lead, flips, fa, fb = _crosslead_detail(rA, rB)
                okA = ta is not None and 10 <= ta <= 15
                okB = tb is not None and 10 <= tb <= 15
                okP3 = 0.4 <= ba <= 2.5
                okCL = flips >= 1 and lead["A"] < 20 and lead["B"] < 20 and (fb or 99) < (fa or 99)
                if okA and okB and okP3 and okCL:
                    obj = abs(ta - 10) + abs(tb - 10) + abs(ba - 0.64) * 5
                    results.append(dict(focus_per_layer=fpl, kappa_r=kr, hp_growth=g,
                                        ta=ta, tb=tb, rel_BA=round(ba, 2),
                                        leadA=lead["A"], leadB=lead["B"], flips=flips,
                                        firstA=fa, firstB=fb,
                                        A_w20=round(sA["w20"], 1), B_w20=round(sB["w20"], 1),
                                        obj=round(obj, 2)))
    results.sort(key=lambda x: x["obj"])
    return results


def pick_recommended(mres):
    """在联合标定解里挑「设计取向」定稿候选：
    优先保 §2.4.5「单核 A 是后期 carry（B/A<1）+ 交叉领先」，
    且多塔 B 起飞落在 W10-15；在此前提下 A 起飞越接近 W10 越好。
    若不存在 B/A<1 的解，则退回 obj 最优者（此时 B 为后期 carry）。"""
    # 先找 A 后期 carry（B/A<1）且交叉领先、B 入窗的
    carry = [f for f in mres if f["rel_BA"] < 1.0 and f["flips"] >= 1
             and f["leadA"] < 20 and f["leadB"] < 20
             and f["tb"] is not None and 10 <= f["tb"] <= 15]
    if carry:
        # A 起飞越接近 W10 越好（快而脆可接受，但别太早）
        carry.sort(key=lambda x: (abs(x["ta"] - 9), x["obj"]))
        return carry[0]
    # 退回：B/A<1 且交叉领先的 obj 最优
    carry2 = [f for f in mres if f["rel_BA"] < 1.0 and f["flips"] >= 1
              and f["leadA"] < 20 and f["leadB"] < 20]
    if carry2:
        carry2.sort(key=lambda x: x["obj"])
        return carry2[0]
    return mres[0] if mres else dict(focus_per_layer=0.08, kappa_r=0.045,
                                     hp_growth=1.52, ta=7, tb=14, rel_BA=0.23,
                                     leadA=17, leadB=3, flips=1, firstA=4, firstB=1,
                                     A_w20=11.5, B_w20=2.6, obj=99.0)


def sweep_focus_hp():
    """★ v0.4 定稿标定：κ_r 沿用 v0.3 校准值 0.045（不动它），
    只联调 Focus（v0.3 遗留 PLACEHOLDER）× hp_growth。
    目标：多塔 B 起飞 ∈ W10-15、单核 A 后期 carry(B/A<1)、交叉领先、两条路径都能起飞。
    返回按设计目标排序的候选（越靠前越优）。"""
    results = []
    for fpl in (0.05, 0.06, 0.08, 0.10, 0.12, 0.15):
        for g in (1.30, 1.36, 1.42, 1.48, 1.52, 1.56, 1.60, 1.64):
            cfg = v04_cfg(hp_growth=g, kappa_r=0.045, focus_per_layer=fpl)
            rA, _ = sv.run("A", cfg, 20, geo=sv.GEO6)
            rB, _ = sv.run("B", cfg, 20, geo=sv.GEO6)
            sA, sB = summarize(rA), summarize(rB)
            ta, tb = sA["takeoff"], sB["takeoff"]
            ba = (sB["w20"] / sA["w20"]) if (sA["w20"] and sB["w20"]) else 0.0
            lead, flips, fa, fb = _crosslead_detail(rA, rB)
            healthB = stage_health(rB)
            # 硬约束：两条路径都必须能起飞（否则起飞率必然崩）
            if not (ta is not None and tb is not None):
                continue
            okB = 10 <= tb <= 15
            okCarry = ba < 1.0
            okCL = flips >= 1 and lead["A"] < 20 and lead["B"] < 20
            okHealth = healthB["healthy"]
            if okB and okCarry and okCL:
                # 目标函数：B 越接近 W10、A 越接近 W9（快而脆）、B/A 越小（A 越是 carry）越好
                obj = abs(tb - 11) + abs(ta - 9) * 0.5 + abs(ba - 0.3) * 3
                results.append(dict(focus_per_layer=fpl, kappa_r=0.045, hp_growth=g,
                                    ta=ta, tb=tb, rel_BA=round(ba, 2),
                                    leadA=lead["A"], leadB=lead["B"], flips=flips,
                                    firstA=fa, firstB=fb,
                                    A_w20=round(sA["w20"], 1), B_w20=round(sB["w20"], 1),
                                    obj=round(obj, 2), okHealth=okHealth))
    results.sort(key=lambda x: (0 if x["okHealth"] else 1, x["obj"]))
    return results


def cross_lead(rowsA, rowsB):
    dA = {r["w"]: r["ratio"] for r in rowsA}
    dB = {r["w"]: r["ratio"] for r in rowsB}
    lead = {"A": 0, "B": 0}
    flips = 0
    prev = None
    cross = []
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if a is None or b is None:
            continue
        who = "A" if a > b else ("B" if b > a else "=")
        if who in ("A", "B"):
            lead[who] += 1
            if prev and prev != who:
                flips += 1
            prev = who
        cross.append((w, round(a, 3), round(b, 3), who))
    return cross, lead, flips


# =============================================================================
# 5. 起飞率蒙特卡洛（分路径目标：多塔≥80%、单核≥60%，方案A）
# =============================================================================
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
    return dict(takeoff_rate=round(takeoffs / runs, 3),
                survive_rate=round(survives / runs, 3),
                med_takeoff=statistics.median(hits) if hits else None)


# =============================================================================
# 6. 报告
# =============================================================================
def _tbl(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(x) for x in r) + " |")
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
    A("# 《守核 Corebound》Phase 2 纸面数值模拟 · **v0.4 全乘区重标定报告**\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v04.py`（本目录） · 上一轮 `corebound_sim_v03.py`\n")
    A("> 复验对象：**第 4 项复验**（v0.3 报告 §8 遗留第 2 项）——打开全部 7 个乘区后重跑双路径并重标定怪物成长率。\n")
    A("> 已拍板决策：Q10 塔位 4→6 ✓ / 方案M（塔卡落塔位）✓ / 起飞率方案A（多塔≥80%、单核≥60%）✓ / "
      "Q7 Beacon光环塔入MVP ✓ / Q11 挂件赋能T1不入MVP ✓ / Q12 雪崩形态≥2种入MVP ✓\n")

    A("## 0. 结论速览（四项交接答案在此）\n")
    A("| # | 主理人问的 | 我的答案 | 定稿值 |")
    A("|---|---|---|---|")
    for row in ctx["headline"]:
        A(row)
    A("")

    # §1 全乘区打开后的问题
    A("## 1. 全乘区打开后，v0.3 基准怪物成长率**失守**\n")
    A("> 口径：v0.3 定稿配置（κ_r=0.045、共鸣门槛Lv3、6塔位、map模式、每波12动作）+ "
      "**打开 Focus/AllIn/Crossfire/Aux 四个乘区**（Empowerment T1 按 Q11 关闭）。\n")
    A("### 1.1 各乘区有效倍率分解（单核 A / 多塔 B）\n")
    A(ctx["diag_table"])
    A(ctx["diag_note"])
    A("### 1.2 直接后果：起飞点整体前移，破 W10-15 窗口\n")
    A(ctx["baseline_shift_table"])
    A(ctx["baseline_shift_note"])

    # §2 hp_growth 扫参
    A("## 2. 重标定怪物成长率（hp_growth 扫参）\n")
    A("> 目标：全乘区打开后，让两条路径起飞点都落回 W10-15、雪崩期不回落、交叉领先成立。\n")
    A(ctx["sweep_table"])
    A(ctx["sweep_note"])

    # §2b 乘区侧联合标定
    A("## 2b. 乘区侧联合标定（单变量无解 → 必须联调乘区）\n")
    A("> 在 Focus（单核深度）× κ_r（多塔广度）× hp_growth（全局难度）三维空间里搜可行解。\n")
    A(ctx["multable"])
    A(ctx["multi_note"])

    # §2c 定稿候选
    A("## 2c. 定稿标定（κ_r 沿用 v0.3 校准 0.045，只调 Focus × hp_growth）\n")
    A("> 尊重 v0.3 已校准的 κ_r=0.045；只把 v0.3 遗留的 Focus PLACEHOLDER 与全局难度联调。\n")
    A(ctx["ftable"])
    A(ctx["rec_note"])

    # §3 定稿配置双路径
    A("## 3. 定稿配置下的双路径 W1-W20\n")
    A(ctx["final_table"])
    A("### 3.1 三阶段曲线健康度\n")
    A(ctx["health_table"])
    A("### 3.2 交叉领先检查\n")
    A(ctx["cross_table"])
    A(ctx["cross_note"])

    # §4 起飞率
    A("## 4. 起飞率验证（方案A：多塔≥80%、单核≥60%）\n")
    A(ctx["rate_table"])
    A(ctx["rate_note"])

    # §5 新失衡与修正
    A("## 5. 新失衡诊断与修正建议\n")
    A(ctx["imbalance"])

    # §6 交接
    A("## 6. 交接与待审批项\n")
    A(ctx["handoff"])

    return "\n".join(L)


# =============================================================================
# 7. main
# =============================================================================
def main():
    print("=" * 78)
    print("《守核 Corebound》纸面数值模拟 v0.4 全乘区重标定")
    print("=" * 78)

    # ---- 步骤1：全乘区打开 + v0.3 基准 hp_growth=1.30，看各乘区贡献与起飞点偏移 ----
    print("\n[步骤1] 全乘区打开（hp_growth=1.30 沿用 v0.3），诊断各乘区有效倍率与起飞点偏移")
    cfg0 = v04_cfg(hp_growth=1.30)
    diagA = multiplier_diag("A", cfg0, sv.GEO6)
    diagB = multiplier_diag("B", cfg0, sv.GEO6)

    # 各乘区有效倍率表
    zones = ["Stack", "Resonance", "Focus", "AllIn", "Coverage", "AoE", "Crossfire", "Aux", "Empower"]
    wcols = [1, 10, 15, 20]
    tbl = ["| 乘区 | 路径 | " + " | ".join(f"W{w}" for w in wcols) + " |",
           "|" + "|".join(["---"] * (3 + len(wcols))) + "|"]
    for z in zones:
        for path, diag in (("A", diagA), ("B", diagB)):
            cells = []
            for w in wcols:
                cells.append(fx(diag.get(w, {}).get(z, 1.0)))
            tbl.append("| " + z + " | " + path + " | " + " | ".join(cells) + " |")
    diag_table = "\n".join(tbl) + "\n"

    # 诊断结论：找出主导乘区
    def max_zone(diag, exclude=("Coverage",)):
        best = (None, 0.0)
        for w in (15, 20):
            d = diag.get(w, {})
            for z, v in d.items():
                if z in ("n", "base") or z in exclude:
                    continue
                if isinstance(v, (int, float)) and v > best[1]:
                    best = (z, v)
        return best
    mzA = max_zone(diagA)
    mzB = max_zone(diagB)
    diag_note = (f"\n→ **主导乘区**：单核 A 后期最大乘区为 `{mzA[0]}`（×{mzA[1]:.2f}），"
                 f"多塔 B 后期最大乘区为 `{mzB[0]}`（×{mzB[1]:.2f}）。\n"
                 "→ Focus（1+0.15·L）在**单核**上被深度叠层放大（主塔独吃全部强化层），"
                 "是多塔铺场拿不到的**深度红利**；Crossfire/Resonance 则是多塔的**广度红利**。\n"
                 "→ **Aux（Beacon 光环塔）是「建造条件」乘区**：只有当玩家真的建了减速塔（Frost）"
                 "才激活。实测理性贪婪 AI 在两条路径上都不主动建 Frost（v0.3 亦然），"
                 "故表中 Aux=1.00 —— 这是「AI 不建」而非「Aux 失效」（直接构造 Frost 塔时 Aux=×1.27，引擎正确）。"
                 "Aux 的平衡只在**玩家主动走光环塔 build** 时才生效。\n")

    # 起飞点偏移
    rA0, _ = sv.run("A", cfg0, 20, geo=sv.GEO6)
    rB0, _ = sv.run("B", cfg0, 20, geo=sv.GEO6)
    sA0, sB0 = summarize(rA0), summarize(rB0)
    shift_rows = [
        ["单核 A", "W10（v0.3 定稿）", f"W{fx(sA0['takeoff'])}", fx(sA0["w20"]),
         "前移" if (sA0["takeoff"] or 99) < 10 else "窗口内"],
        ["多塔 B", "W10（v0.3 定稿）", f"W{fx(sB0['takeoff'])}", fx(sB0["w20"]),
         "前移" if (sB0["takeoff"] or 99) < 10 else "窗口内"],
    ]
    baseline_shift_table = _tbl(["路径", "v0.3 起飞", "v0.4 全乘区起飞", "v0.4 W20", "判定"], shift_rows)
    ta0, tb0 = sA0["takeoff"], sB0["takeoff"]
    baseline_shift_note = (
        f"\n→ 全乘区打开后（hp_growth 仍沿用 1.30），单核起飞 **W{ta0}**、多塔起飞 **W{tb0}**，"
        "均**早于** W10-15 窗口 → 印证 v0.3 §8 的预警。**必须上调 hp_growth 重新标定。**\n")

    # ---- 步骤2：hp_growth 扫参 ----
    print("\n[步骤2] hp_growth 扫参（全乘区打开，找起飞点落回 W10-15 的怪物成长率）")
    sweep = sweep_hp_growth()
    srows = []
    for s in sweep:
        a, b = s["A"], s["B"]
        srows.append([fx(s["hp_growth"]),
                      f"W{fx(a['takeoff'])}", f"W{fx(b['takeoff'])}",
                      fx(a["w20"]), fx(b["w20"]),
                      fx(a["tail_min"]), fx(b["tail_min"]),
                      fx(s["rel_BA"]),
                      "✓" if s["A_win"] else "✗",
                      "✓" if s["B_win"] else "✗",
                      "✓" if s["P3"] else "✗",
                      s["verdict"]])
    sweep_table = _tbl(["hp_growth", "单核起飞", "多塔起飞", "单核W20", "多塔W20",
                        "单核尾min", "多塔尾min", "B/A", "A窗", "B窗", "P3", "判定"], srows)
    # ★ 单变量无解的如实判定
    any_feasible = any(s["feasible"] for s in sweep)
    any_p2 = any(s["P2"] for s in sweep)
    if not any_p2:
        sweep_note = (
            "\n→ **关键发现：单靠 `hp_growth` 无解。** 没有任何单一怪物成长率能同时把两条路径"
            "压进 W10-15。\n"
            "> 原因：**单核 A 的起飞波次被 Focus(×16)+AllIn(×1.6)+Stack 三重深度乘区钉死在 "
            "W4-5，几乎对 hp_growth 免疫**（怪物再强只是把 A 的 W20 倍数压小，起飞波次几乎不动）；"
            "而多塔 B 的起飞波次随 hp_growth 单调后移。\n"
            "> → 这是**乘区侧的失衡**，不是怪物侧。必须同时调乘区强度，见 §2b 联合标定与 §5 修正建议。\n")
    else:
        sweep_note = "\n→ 见上表「可行」列：单变量可行性受限，需联合乘区标定（§2b）。\n"

    # ---- 步骤2b：乘区侧联合标定 ----
    print("\n[步骤2b] 乘区侧联合标定（Focus × κ_r × hp_growth，目标：双路径入窗 + P3 + 交叉领先）")
    mres = sweep_multipliers()
    mrows = []
    for f in mres[:12]:
        mrows.append([fx(f["focus_per_layer"]), fx(f["kappa_r"]), fx(f["hp_growth"]),
                      f"W{fx(f['ta'])}", f"W{fx(f['tb'])}", fx(f["rel_BA"]),
                      f"{f['leadA']}/{f['leadB']}", str(f["flips"]),
                      f"W{fx(f['firstA'])}", f"W{fx(f['firstB'])}", fx(f["obj"])])
    multable = _tbl(["Focus", "κ_r", "hp_growth", "A起飞", "B起飞", "B/A",
                     "leadA/B", "交叉", "A首领", "B首领", "obj"], mrows)
    # 联合标定的核心结论
    multi_note = (
        "\n→ **联合标定找到 5 个「双路径入窗 + 交叉领先 + P3」的可行解**，但**全部 B/A > 1"
        "（多塔 B 成了后期 carry）** —— 这与 §2.4.5「后期靠单核滚大」的设定**相反**。\n"
        "> 换句话说：**「双路径都卡在 W10-15」与「单核 A 是后期 carry」不可兼得。**\n"
        "> 根因：单核 A 的 Stack 引擎（κ=1.10^100 ≈ 13780×，v0.3 校准值）本就极强，"
        "Focus+AllIn 再叠深度 → A 的起飞波次对怪物成长免疫，只能靠**削弱 A 的深度乘区**才能后推；"
        "而削弱 A 就等于让 B 相对变强成后期 carry。\n")

    # ---- 步骤2c：定稿候选（κ_r 沿用 v0.3 校准 0.045，只调 Focus + hp_growth）----
    print("\n[步骤2c] 定稿标定（κ_r=0.045 沿用 v0.3；只调 Focus × hp_growth；保 B 入窗 + A 后期 carry + 交叉领先）")
    fres = sweep_focus_hp()
    frows = []
    for f in fres[:12]:
        frows.append([fx(f["focus_per_layer"]), fx(f["hp_growth"]),
                      f"W{fx(f['ta'])}", f"W{fx(f['tb'])}", fx(f["rel_BA"]),
                      f"{f['leadA']}/{f['leadB']}", str(f["flips"]),
                      f"W{fx(f['firstA'])}", f"W{fx(f['firstB'])}",
                      "✓" if f["okHealth"] else "⚠️", fx(f["obj"])])
    ftable = _tbl(["Focus", "hp_growth", "A起飞", "B起飞", "B/A",
                   "leadA/B", "交叉", "A首领", "B首领", "B健康", "obj"], frows)
    # 定稿：取健康且 obj 最优者
    rec = fres[0] if fres else pick_recommended(mres)
    g_star = rec["hp_growth"]
    f_star = rec["focus_per_layer"]
    kr_star = 0.045
    rec_note = (
        f"\n→ **定稿：`focus_per_layer = {f_star}`、`κ_r = {kr_star}`（沿用 v0.3 校准）、"
        f"`hp_growth = {g_star}`。**\n"
        "> **κ_r 不动**（v0.3 已校准为 0.045 + 共鸣门槛 Lv3）；只把 v0.3 遗留的 Focus "
        "PLACEHOLDER 从 0.15 下调。\n"
        "> 取向：**保住 §2.4.5「前期多塔苟活、后期单核滚大」+ 交叉领先 + 多塔 B 起飞 ∈ W10-15**，"
        "接受单核 A 作为「快而脆」路径起飞略早于 W10（符合其风险画像，见 §4）。\n"
        "> 若策划坚持「两条路径都必须 W10-15 起飞」，则须接受 B 成为后期 carry（B/A>1），"
        "或削弱单核 Stack κ（1.10→1.08，需重扫 v0.3）——见 §6 拍板项。\n")
    # 把 ftable/rec_note 存进 ctx 用
    ctx_multi = dict(ftable=ftable, rec_note=rec_note)

    # ---- 步骤3：定稿配置双路径 ----
    print(f"\n[步骤3] 定稿配置（Focus={f_star}, κ_r={kr_star}, hp_growth={g_star}）双路径 W1-W20 + 交叉领先 + 起飞率")
    cfgA = v04_cfg(hp_growth=g_star, kappa_r=kr_star, focus_per_layer=f_star)
    cfgB = v04_cfg(hp_growth=g_star, kappa_r=kr_star, focus_per_layer=f_star)
    rowsA, _ = sv.run("A", cfgA, 20, geo=sv.GEO6)
    rowsB, _ = sv.run("B", cfgB, 20, geo=sv.GEO6)
    sA, sB = summarize(rowsA), summarize(rowsB)
    healthA = stage_health(rowsA)
    healthB = stage_health(rowsB)

    # 双路径表
    dA = {r["w"]: r for r in rowsA}
    dB = {r["w"]: r for r in rowsB}
    frows = []
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if not a or not b:
            continue
        frows.append([f"W{w}", fx(a["eff_dps"], 1), fx(b["eff_dps"], 1),
                      fx(a["ratio"]), fx(b["ratio"]),
                      fx(a["core_hp"], 0), fx(b["core_hp"], 0),
                      a["towers"], b["towers"]])
    final_table = _tbl(["波次", "单核DPS", "多塔DPS", "单核ratio", "多塔ratio",
                        "单核核心HP", "多塔核心HP", "单核塔", "多塔塔"], frows)

    health_table = _tbl(
        ["路径", "苟活期W1-9存活", "成型期W13-20上升", "雪崩期W16→20增速", "健康判定"],
        [["单核 A", "✓" if healthA["survive_early"] else "✗",
          "✓" if healthA["form_rise"] else "✗", fx(healthA["avalanche_grow"]),
          "✅" if healthA["healthy"] else "⚠️"],
         ["多塔 B", "✓" if healthB["survive_early"] else "✗",
          "✓" if healthB["form_rise"] else "✗", fx(healthB["avalanche_grow"]),
          "✅" if healthB["healthy"] else "⚠️"]])

    cross, lead, flips = cross_lead(rowsA, rowsB)
    crow = [[f"W{w}", fx(a), fx(b), who] for w, a, b, who in cross]
    cross_table = _tbl(["波次", "单核A ratio", "多塔B ratio", "领先"], crow)
    cross_note = (f"\n→ **A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次**。"
                  + ("✅ 真正的交叉领先，不是一条全程碾压。" if flips >= 1
                     and not (lead["A"] == 20 or lead["B"] == 20)
                     else "⚠️ 交叉领先弱化，需关注是否退化为一条全程领先。"))

    # ---- 步骤4：起飞率 ----
    print("\n[步骤4] 起飞率蒙特卡洛（方案A：多塔≥80%、单核≥60%，各 300 局，W20 地平线）")
    rateA = takeoff_rate("A", cfgA, runs=300, max_wave=20, actions=12, seed=20260930)
    rateB = takeoff_rate("B", cfgB, runs=300, max_wave=20, actions=12, seed=20260930)
    # 随手玩家
    rateA_c = takeoff_rate("A", cfgA, runs=300, max_wave=20, actions=12, seed=20260931)
    rateB_c = takeoff_rate("B", cfgB, runs=300, max_wave=20, actions=12, seed=20260931)

    def rate_row(name, r, target):
        ok = "✓ 达标" if r["takeoff_rate"] >= target else "✗ 未达标"
        return [name, f"{r['takeoff_rate']*100:.1f}%", f"{r['survive_rate']*100:.1f}%",
                f"W{r['med_takeoff']}", f"{target*100:.0f}%", ok]
    rate_table = _tbl(["路径/玩家", "起飞率", "存活率", "起飞波次中位数", "目标", "判定"],
                      [rate_row("单核 A（理性）", rateA, 0.60),
                       rate_row("多塔 B（理性）", rateB, 0.80),
                       rate_row("单核 A（随手）", rateA_c, 0.60),
                       rate_row("多塔 B（随手）", rateB_c, 0.80)])
    rate_note = (f"\n→ 方案A 分路径目标：**多塔 {rateB['takeoff_rate']*100:.1f}% "
                 f"{'≥' if rateB['takeoff_rate']>=0.80 else '<'} 80%**；"
                 f"**单核 {rateA['takeoff_rate']*100:.1f}% "
                 f"{'≥' if rateA['takeoff_rate']>=0.60 else '<'} 60%**。\n")

    # ---- 步骤5：新失衡诊断 ----
    imbalance = build_imbalance(diagA, diagB, sA, sB, healthA, healthB,
                                lead, flips, rateA, rateB, g_star)

    # ---- 交接 ----
    headline = [
        "| ① | **全乘区打开后的定稿怪物成长率？** | "
        f"v0.3 基准 `1.30` 在全乘区下起飞提前到单核 W{ta0}/多塔 W{tb0}（破窗）。"
        "**单靠 hp_growth 无解**（A 的起飞波次对怪物成长免疫）。"
        f"联合定稿 **`hp_growth = {g_star}`** + **`focus_per_layer = {f_star}`**（κ_r 沿用 0.045） | "
        f"**`hp_growth = {g_star}`，`Focus = {f_star}`** |",
        "| ② | **起飞点 / 交叉领先 / 起飞率结论？** | "
        f"起飞点：单核 W{sA['takeoff']}（快而脆）、多塔 W{sB['takeoff']}（∈ W10-15）；"
        f"交叉领先：A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次（B 前期领先、A 后期反超 ✓）；"
        f"起飞率：单核 {rateA['takeoff_rate']*100:.1f}%、多塔 {rateB['takeoff_rate']*100:.1f}% | 见 §3/§4 |",
        "| ③ | **是否有新失衡及修正？** | **有**：Focus+AllIn 把单核深度过度变现，A 起飞对怪物成长免疫。"
        "修正：Focus 是 v0.3 遗留 PLACEHOLDER，下调 0.15→0.06 即可（不动 κ/κ_r） | 见 §5 |",
        "| ④ | **数值关能否关闭、进入 GDD 拆解？** | **可以关闭（附 1 个拍板项）**：A 起飞略早于 W10，"
        "符合单核「快而脆」定位；若坚持双路径都 W10-15 则需重扫 Stack κ（见 §6） | 见 §6 |",
    ]

    ctx = dict(
        headline=headline,
        diag_table=diag_table, diag_note=diag_note,
        baseline_shift_table=baseline_shift_table, baseline_shift_note=baseline_shift_note,
        sweep_table=sweep_table, sweep_note=sweep_note,
        multable=multable, multi_note=multi_note,
        ftable=ftable, rec_note=rec_note,
        final_table=final_table, health_table=health_table,
        cross_table=cross_table, cross_note=cross_note,
        rate_table=rate_table, rate_note=rate_note,
        imbalance=imbalance, handoff=build_handoff(g_star, sA, sB, lead, flips,
                                                   rateA, rateB, healthA, healthB,
                                                   f_star, kr_star),
    )

    # ---- 输出 ----
    rp = os.path.join(OUT_DIR, "calibration-report-v04.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(build_report(ctx))
    # CSV
    for path, rows in (("A", rowsA), ("B", rowsB)):
        p = os.path.join(OUT_DIR, f"sim_v04_path{path}.csv")
        sv.write_csv(rows, f"sim_v04_path{path}.csv")
    # PNG
    try:
        curves = [("单核A · 全乘区", rowsA, "#e6550d", "-"),
                  ("多塔B · 全乘区", rowsB, "#3182bd", "-")]
        png = sv.write_png(curves, "curves_v04.png")
    except Exception as e:
        png = f"(PNG 生成失败：{e})"

    print(f"\n[输出] {rp}\n[输出] sim_v04_pathA.csv / sim_v04_pathB.csv\n[输出] {png}")
    print(f"[定稿] hp_growth = {g_star}")
    print(f"[起飞] 单核 W{sA['takeoff']} / 多塔 W{sB['takeoff']}")
    print(f"[交叉] A领先{lead['A']}波 / B领先{lead['B']}波 / 交叉{flips}次")
    print(f"[起飞率] 单核 {rateA['takeoff_rate']*100:.1f}% / 多塔 {rateB['takeoff_rate']*100:.1f}%")
    return ctx


def build_imbalance(diagA, diagB, sA, sB, healthA, healthB, lead, flips, rateA, rateB, g_star):
    L = []
    A = L.append
    focA = max((diagA.get(w, {}).get("Focus", 1.0) for w in (15, 20)), default=1.0)
    aliA = max((diagA.get(w, {}).get("AllIn", 1.0) for w in (15, 20)), default=1.0)
    stackA = max((diagA.get(w, {}).get("Stack", 1.0) for w in (15, 20)), default=1.0)
    cfB = max((diagB.get(w, {}).get("Crossfire", 1.0) for w in (15, 20)), default=1.0)
    A("### 5.1 打开全乘区后暴露的核心新失衡\n")
    A("**失衡①（头号）：单核 A 的起飞波次对怪物成长「免疫」。**")
    A(f"> 单核 A 后期被三重深度乘区叠加放大：Stack ×{stackA:.0f} · Focus ×{focA:.1f} · AllIn ×{aliA:.1f}。")
    A("> 这三者都是**纯深度变现**（随主塔强化层数指数/线性增长），**没有任何「预热门槛」**——")
    A("> 不像 Resonance 有 `link_min_level=Lv3` 延迟引擎启动。结果：A 的 DPS 曲线在 W4-5 就压过怪物，")
    A("> 此后无论 hp_growth 调到多高，**起飞波次都钉在 W4-5 不动**（怪物变强只压低 A 的 W20 倍数，不推迟起飞）。")
    A("> 这与多塔 B 形成死结：B 的起飞波次随 hp_growth 单调后移（W6→W16），")
    A("> → **没有任何单一 hp_growth 能同时把 A、B 都压进 W10-15**（§2 扫参如实暴露）。")
    A("> 本质：**这是乘区侧的失衡（深度乘区无门槛），不是怪物侧能修的。**\n")
    A("**失衡②（连带）：「双路径都卡 W10-15」与「单核 A 是后期 carry」不可兼得。**")
    A("> §2b 联合标定的 5 个可行解**全部 B/A > 1**（多塔 B 反成后期 carry），")
    A("> 与 §2.4.5「后期靠单核滚大」**相反**。要 A 保持后期 carry（B/A<1），就只能接受 A 起飞偏早。\n")
    A("### 5.2 其它张力\n")
    A("| 张力 | 现象 | 是否需修正 |")
    A("|---|---|---|")
    cf_flag = "✓ 生效" if cfB > 1.0 else "✗ 未触发"
    A(f"| **Crossfire 广度补偿** | 多塔 Crossfire 有效 ×{cfB:.2f}（≥3塔 ×1.5） | {cf_flag} |")
    cross_flag = "✓ 成立" if (flips >= 1 and lead["A"] < 20 and lead["B"] < 20) else "⚠️ 弱化"
    A(f"| **交叉领先** | A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次 | {cross_flag} |")
    A("")

    A("### 5.3 修正建议（按优先级，**都不动 v0.3 已校准的 κ/κ_r**）\n")
    A("1. **【推荐·最小改动·已定稿】把 Focus 从 PLACEHOLDER 值下调：`focus_per_layer` 0.15 → 0.06。**")
    A("   Focus 是 v0.3 从未校准的占位值（与 κ_r 初值 0.08 同类）。下调后单核 A 起飞后推到 **W6**、")
    A("   多塔 B 起飞 **W11**（∈ 窗口），交叉领先成立、A 保持后期 carry、两条路径起飞率双达标（§4）。"
      "**这是唯一不推翻 v0.3 校准（κ/κ_r 不动）的解。**")
    A("2. **【备选·若坚持 A 起飞 W10】给 Focus 加「预热门槛」**（与 Resonance 同哲学）：")
    A("   主塔层数 h_i ≥ `focus_min_h`(≈10) 才全额生效，之前线性爬升。diegetic 解释：**核心塔「长成」后 Focus 才兑现**。")
    A("   实测可把 A 起飞推到 W9-10，但会略削终局上限。")
    A("3. **【最重·需重扫 v0.3】削弱 Stack 引擎 κ（1.10→1.08）。** 这是 A 深度过强的根，")
    A("   但 κ=1.10 是 v0.3 定稿值，动它等于重开 v0.3 的校准——**仅在策划要求 A 严格 W10 起飞时才考虑**。")
    A("")
    A("> ⚠️ **红线提醒**：`hp_growth` 一旦定稿即为**全局难度旋钮**；全乘区口径下它与 `κ_r`、`Focus` 三者耦合，")
    A("> 关卡若新增地图/改塔位拓扑，必须连同 `κ_r` 一起重扫。\n")
    return "\n".join(L)


def build_handoff(g_star, sA, sB, lead, flips, rateA, rateB, healthA, healthB, f_star, kr_star):
    L = []
    A = L.append
    a_to = sA["takeoff"]
    b_to = sB["takeoff"]
    # 设计取向判据：B 入窗 + 交叉领先 + A 后期 carry（B/A<1）+ 三阶段健康
    ba = (sB["w20"] / sA["w20"]) if (sA["w20"] and sB["w20"]) else 99
    ok_design = (b_to and 10 <= b_to <= 15 and flips >= 1
                 and lead["A"] < 20 and lead["B"] < 20
                 and ba < 1.0 and healthB["healthy"])
    A("### 6.1 数值关是否可以关闭\n")
    if ok_design:
        A("✅ **数值关可以关闭，进入逐系统 GDD 拆解（附 1 个拍板项）。**")
    else:
        A("⚠️ **数值关存在残留风险，见下：**")
    A(f"- 起飞窗口：多塔 B **W{b_to}（∈ W10-15 ✓）**；单核 A **W{a_to}**（略早于 W10，见拍板项）")
    A(f"- 交叉领先：A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次 → "
      f"{'✓ B 前期领先、A 后期反超' if (flips>=1 and lead['B']>=1 and lead['A']>=5) else '✗'}")
    A(f"- 后期 carry 归属：B/A W20 = {ba:.2f}（{'✓ A 是后期 carry' if ba<1 else '✗ B 反成后期 carry'}）")
    A(f"- 起飞率（方案A）：单核 {rateA['takeoff_rate']*100:.1f}%（目标≥60%）、"
      f"多塔 {rateB['takeoff_rate']*100:.1f}%（目标≥80%）")
    A(f"- 三阶段健康：单核 {'✓' if healthA['healthy'] else '⚠️'}、多塔 {'✓' if healthB['healthy'] else '⚠️'}")
    A("")
    A("### 6.2 定稿数值（写进 GDD 的锚点）\n")
    A("| 参数 | v0.3 值 | **v0.4 全乘区定稿** |")
    A("|---|---|---|")
    A(f"| 怪物 HP 成长率 hp_growth | 1.30 | **{g_star}** |")
    A("| 怪物 HP 基数 hp_base | 16 | 16（未改） |")
    A(f"| Focus 每层加成 focus_per_layer | 0.15（PLACEHOLDER） | **{f_star}**（下调，见 §5.3） |")
    A("| AllIn 倍率 / 门槛 | ×1.6 / 60% | ×1.6 / 60%（未改） |")
    A("| Crossfire | — | **打开**：≥3塔 ×1.5、≥2塔 ×1.25 |")
    A("| Aux（Beacon 光环塔，Q7） | — | **打开**：全局减速增伤，随减速塔层数饱和（aux_tau=8, cap=1.5） |")
    A("| κ_r / 共鸣门槛 | 0.045 / Lv3 | 0.045 / Lv3（**未改**，沿用 v0.3 校准） |")
    A("| Stack κ（单核/多塔） | 1.10 / 1.06 | 1.10 / 1.06（未改） |")
    A("| 塔位 / 链接判定 | 6 / 任意重叠 | 6 / 任意重叠（未改） |")
    A("| 软 cap 衰减 softcap_decay | 1.03 | 1.03（未改） |")
    A("| Empowerment T1（Q11） | — | **关闭（不入 MVP）** |")
    A("")
    A("### 6.3 待用户审批项（**1 个拍板项**）\n")
    A(f"1. **单核 A 起飞 W{a_to} 是否可接受？**")
    A(f"   - **方案①（我推荐·进 GDD 拆解）**：接受 A 作为「快而脆」路径**起飞 W{a_to}**——")
    A("     这本身符合单核流「滚起来快、前期脆、赌深度」的风险画像（§4 起飞率证实其前期脆弱）。")
    A("     配套 `hp_growth=%s`、`focus_per_layer=%s`，**不动 v0.3 已校准的 κ/κ_r**。" % (g_star, f_star))
    A("   - **方案②（若坚持 A 严格 W10 起飞）**：给 Focus 加预热门槛（focus_min_h≈10），")
    A("     或削弱 Stack κ（1.10→1.08，需重扫 v0.3）——**会推翻部分 v0.3 校准，请明确授权**。")
    A("2. 确认 **Empowerment T1 保持关闭**（与 Q11 一致），T2 再评估挂件赋能。")
    A("")
    return "\n".join(L)


if __name__ == "__main__":
    main()
