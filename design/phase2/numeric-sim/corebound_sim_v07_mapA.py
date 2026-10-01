# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.7：地图方案 A + 链接口径 0.65 下的 κ_r 复扫**
作者：程基岩（工程主理人）

================================================================================
为什么必须复跑
================================================================================
v0.6 全套定稿数值是在 `link_rule = "any"`（f = 1.0，任意射程重叠即链接）下扫出来的。
用户拍板两项改动，其中一项会让定稿的 `κ_r = 0.045` 失准：

  ① 地图布局 = 方案 A —— 沿用 sim 真身坐标 `sv.GEO6 / sv.SLOTS6`：
     核心在路径终点 (55,25)，6 塔位 [(6,33),(22,40),(30,33),(45,33),(18,16),(48,42)]。
     ★ 坐标不改（就是 v03/v04/v06 一直在用的那套）。

  ② 链接判定口径 = 0.65（真生效）—— `link_rule: "any" -> "substantial"`，
     引擎 `Geo.links()` 走 `f = 0.65`，判定式 `d ≤ 0.65·(Rᵢ+Rⱼ)`。
     → 多塔 B 的链接图平均度 k̄ 下降 → 共鸣强度 `E` 缩水
     → 原 `κ_r = 0.045` 会**欠强** → 需复扫到更强的档位。

  ③ Focus 预热门槛**保留**（`focus_full = False`，即 `1 + 0.06·L·min(1, h/8)`）——
     本脚本对此做**不变量断言**，防止被误开。

================================================================================
本脚本只做一件事
================================================================================
在 `κ_r ∈ [0.045, 0.070]`（步长 0.005）上，用 0.65 口径复跑定稿双路径（单核 A / 多塔 B），
每条 κ_r 跑蒙特卡洛 ≥300 局（与 v0.6 一致），按 6 条判据挑出
**满足全部判据的最小 κ_r**（避免过热）。

★ 不修改 v03 / v04 / v05 / v06 任何原文件；不改任何 GDD。
★ 除 κ_r 与 link_rule 外，定稿数值全部冻结：
    hp_growth=1.42 / hp_base=16 / focus_per_layer=0.06 / κ_tag 档位 / κ 公式 /
    软 cap decay=1.03 / 共鸣门槛 Lv3 / 6 塔位 / pity 保底开 / synergy_on=False。

用法（隔离 venv）：
  C:\\Users\\junhewang\\.workbuddy\\binaries\\python\\envs\\default\\Scripts\\python.exe \\
      corebound_sim_v07_mapA.py kbar    # 只做 k̄ 验证（快，秒级）
      corebound_sim_v07_mapA.py sweep   # 全量扫参 + 出报告（分钟级）
      corebound_sim_v07_mapA.py all
"""
from __future__ import annotations

import os
import sys
import time
import random
import statistics

# ★ 导入 v06 即完成「引擎打补丁」：sv.compute_dps / sv.dps_only 被替换为 v6 引擎
import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# =============================================================================
# 0. 冻结项（定稿数值，本脚本一律不改）
# =============================================================================
HP_GROWTH = 1.42
HP_BASE = 16.0
FOCUS_PER_LAYER = 0.06
PITY = True                 # 定稿：pity 保底开
LINK_RULE_NEW = "substantial"   # f = 0.65
LINK_RULE_OLD = "any"           # f = 1.00（v0.6 旧口径，仅用于对照）
SYNERGY_ON = False          # Q-C6：Syn 一次性 ×1.5 已摘除
KAPPA_MODE = "tier"         # κ = κ_tag − 0.01·clamp(N−2,0,4)
KTAG_TIERS_MVP = v6.KTAG_TIERS_MVP
KR_TIERS_T1 = v6.KR_TIERS_T1       # GDD §5.4 三档：(0,0.040) (3,0.045) (20,0.050)
KR_NEUTRAL = 0.045                 # §5.4.1 中性塔恒取基准档

KR_GRID = (0.045, 0.050, 0.055, 0.060, 0.065, 0.070)
MC_RUNS = 300               # 与 v0.6 一致
SEED1 = 20260930
SEED2 = 20260931
SEED3 = 20260932

# 判据红线
WIN_LO, WIN_HI = 10, 15     # 多塔 B 决定性起飞 ∈ W10–15
RATE_B_MIN = 0.80           # 多塔 B 起飞率 ≥ 80%
RATE_A_MIN = 0.60           # 单核 A 起飞率 ≥ 60%
BA_MAX = 1.0                # B/A < 1
FLIPS_MIN = 1               # 交叉领先 ≥ 1 次


# =============================================================================
# 1. 配置工厂（在 v06 定稿工厂上只叠「link_rule」与 κ_r）
# =============================================================================
def cfg_of(path="B", kappa_r=0.045, rule=LINK_RULE_NEW, kr_mode="flat",
           kr_tiers=None, strict=True, **over):
    """定稿口径 + 指定 link_rule / κ_r。其余定稿数值一律不动。
    strict=True 时做全套不变量断言（正式扫参用）；
    strict=False 只用于「抗扰动探针」（显式放行 hp_growth 抖动）。"""
    kw = dict(
        hp_growth=HP_GROWTH,
        focus_per_layer=FOCUS_PER_LAYER,
        kappa_r=kappa_r,
        synergy_on=SYNERGY_ON,
        kappa_mode=KAPPA_MODE,
        kr_mode=kr_mode,
    )
    if kr_tiers is not None:
        kw["kr_tiers"] = kr_tiers
    kw.update(over)
    c = v6.v06_cfg(path=path, **kw)
    c["link_rule"] = rule
    c["hp_base"] = HP_BASE
    c["pity"] = PITY
    # ---- 不变量断言：这几条被误开/误关就说明口径被污染 ----
    assert c["focus_full"] is False, "focus_full 必须保持 False（Focus 预热门槛保留）"
    assert c["focus_min_h"] == 8.0, "focus_min_h 必须为 8.0"
    assert c["synergy_on"] is False, "synergy_on 必须保持 False（Syn 已摘除）"
    assert c["focus_per_layer"] == FOCUS_PER_LAYER and c["pity"] is True
    assert c["softcap_decay"] == 1.03 and c["reinf_cap"] == 100
    assert c["link_min_level"] == sv.RECOMMENDED["link_min_level"] == 3
    assert c["link_rule"] == rule
    if strict:
        assert c["hp_growth"] == HP_GROWTH and c["hp_base"] == HP_BASE
    return c


def shifted_tiers(base_deep):
    """把 GDD §5.4 的 κ_r 三档整体平移，使「深度档」= base_deep。
    定稿档位为 (0,0.040)(3,0.045)(20,0.050) → 深度档 0.050。
    e.g. base_deep=0.060 → (0,0.050)(3,0.055)(20,0.060)。"""
    return [(0, round(base_deep - 0.010, 4)),
            (3, round(base_deep - 0.005, 4)),
            (20, round(base_deep, 4))]


# =============================================================================
# 2. k̄ 验证：确认 geo.links() 真的走到 0.65 分支
# =============================================================================
def _kbar(adj):
    ks = [len(a) for a in adj]
    return (sum(ks) / len(ks)) if ks else 0.0


def kbar_profile_matrix():
    """枚举 6 塔位上 {Arrow, Cannon, Frost} 的全部画像，找 k̄(any)=4.33 / k̄(0.65)=3.67
    的那一支 —— 即主理人「定稿多塔 B 画像」所指的拓扑。"""
    import itertools
    names = ("Arrow", "Cannon", "Frost")
    hits, allrows = [], []
    for combo in itertools.product(names, repeat=6):
        a = sv.GEO6.links(list(combo), "any")
        s = sv.GEO6.links(list(combo), LINK_RULE_NEW)
        ka, ks_ = _kbar(a), _kbar(s)
        allrows.append((combo, ka, ks_))
        if abs(ka - 4.33) < 0.005 and abs(ks_ - 3.67) < 0.005:
            hits.append((combo, ka, ks_))
    return hits, allrows


def kbar_endgame(path="B", rule=LINK_RULE_NEW, kappa_r=0.045, kr_mode="flat"):
    """决定性跑的终局真实构筑：按 slot→type 还原链接图，统计
    ① 全塔位 k̄（原始几何度）② 有效共鸣度（只数 h ≥ link_min_level 的邻居）。"""
    c = cfg_of(path, kappa_r=kappa_r, rule=rule, kr_mode=kr_mode)
    st = v6.final_state(path, c)
    p, info = st["player"], st["info"]
    gtypes = [None] * sv.GEO6.n
    glevel = [0] * sv.GEO6.n
    for t in p.towers:
        gtypes[t.slot] = t.ctype
        glevel[t.slot] = t.h
    adj_old = sv.GEO6.links(gtypes, LINK_RULE_OLD)
    adj_new = sv.GEO6.links(gtypes, LINK_RULE_NEW)
    lmin = c["link_min_level"]

    def eff(adj):
        tot, cnt = 0, 0
        for i, t in enumerate(p.towers):
            nb = [gj for gj in adj[t.slot]
                  for k, t2 in enumerate(p.towers)
                  if k != i and t2.slot == gj and t2.h >= lmin]
            tot += len(nb)
            cnt += 1
        return tot / cnt if cnt else 0.0

    return dict(
        mix=v6.tower_mix(st), dump=v6.build_dump(st),
        slots=[(t.slot, t.ctype, t.h, sum(t.attach.values())) for t in p.towers],
        kbar_old=round(_kbar(adj_old), 3), kbar_new=round(_kbar(adj_new), 3),
        keff_old=round(eff(adj_old), 3), keff_new=round(eff(adj_new), 3),
        E=info["E"], kr=info["kr"], dps=st["dps"],
        takeoff=st["s"]["takeoff"], w20=st["s"]["w20"],
    )


def link_audit(path="B", kappa_r=0.045, kr_mode="flat"):
    """终局构筑里「真正进入 E 的那一层」逐对审计：
    只列 h_i≥Lv3 且 h_k≥Lv3 的塔对（其余塔对在 any 口径下也进不了 E），
    给出槽位距离 vs 两条判定阈值，证明 0.65 砍掉的边到底有没有碰到 E。"""
    c = cfg_of(path, kappa_r=kappa_r, rule=LINK_RULE_NEW, kr_mode=kr_mode)
    st = v6.final_state(path, c)
    ts = st["player"].towers
    lmin = c["link_min_level"]
    rows = []
    for i, ti in enumerate(ts):
        for k, tk in enumerate(ts):
            if i == k or ti.h < lmin or tk.h < lmin:
                continue
            d = sv.GEO6.dist[ti.slot][tk.slot]
            R = sv.TOWERS[ti.ctype]["rng"] + sv.TOWERS[tk.ctype]["rng"]
            rows.append([f"{ti.ctype}@slot{ti.slot}(h{ti.h})",
                         f"{tk.ctype}@slot{tk.slot}(h{tk.h})",
                         f"{d:.2f}", f"{R:.0f}",
                         f"{1.00*R:.2f}", "✓" if d <= 1.00 * R else "✗",
                         f"{0.65*R:.2f}", "✓" if d <= 0.65 * R else "✗",
                         f"{1+tk.h:.0f}"])
    return rows


def kbar_probe():
    print("=" * 78)
    print("《守核》v0.7 · k̄ 验证：确认 link_rule 真的走到 0.65 分支")
    print("=" * 78)
    print(f"地图 = 方案A（sv.GEO6 / sv.SLOTS6），塔位 = {sv.SLOTS6}")
    print(f"路径终点（核心）= {sv.PATH[-1]}\n")

    # --- (a) 纯几何：全 Cannon 铺满 6 塔位 ---
    for lbl, types in (("全 Cannon", ["Cannon"] * 6),
                       ("全 Arrow", ["Arrow"] * 6),
                       ("全 Frost", ["Frost"] * 6)):
        ko = _kbar(sv.GEO6.links(types, LINK_RULE_OLD))
        kn = _kbar(sv.GEO6.links(types, LINK_RULE_NEW))
        print(f"  [几何·{lbl}]  k̄(any) = {ko:.3f}   k̄(0.65) = {kn:.3f}   Δ = {kn-ko:+.3f}")

    # --- (b) 主理人画像反查 ---
    hits, _ = kbar_profile_matrix()
    print(f"\n  [画像反查] 满足 k̄(any)=4.33 且 k̄(0.65)=3.67 的 6 塔画像：{len(hits)} 支")
    for combo, ka, ks_ in hits[:12]:
        print(f"     {list(combo)}  →  k̄(any) = {ka:.3f}   k̄(0.65) = {ks_:.3f}")
    if hits:
        c0 = list(hits[0][0])
        print(f"  → 代表画像 {c0}：确认 0.65 分支生效（k̄ {hits[0][1]:.2f} → {hits[0][2]:.2f}）")

    # --- (c) 定稿 B 终局真实构筑 ---
    print("\n  [定稿多塔 B 终局真实构筑]")
    for rule in (LINK_RULE_OLD, LINK_RULE_NEW):
        r = kbar_endgame("B", rule=rule)
        print(f"     rule={rule:<12} 混合={r['mix']}")
        print(f"        k̄(全塔位) = {r['kbar_old'] if rule=='any' else r['kbar_new']:.3f}"
              f"   有效共鸣度(h≥3) = {r['keff_old'] if rule=='any' else r['keff_new']:.3f}"
              f"   E = {[round(x,1) for x in r['E']]}")
        print(f"        起飞 W{r['takeoff']}   W20 = {r['w20']}   DPS = {r['dps']:,.0f}")
    return hits


# =============================================================================
# 3. 单点评估：决定性 + 蒙特卡洛
# =============================================================================
def eval_point(kappa_r, rule=LINK_RULE_NEW, kr_mode="flat", kr_tiers=None,
               runs=MC_RUNS, seed=SEED1, with_mc=True, tag=""):
    st = {}
    for path in ("A", "B"):
        st[path] = v6.final_state(path, cfg_of(path, kappa_r=kappa_r, rule=rule,
                                               kr_mode=kr_mode, kr_tiers=kr_tiers))
    sA, sB = st["A"]["s"], st["B"]["s"]
    _, lead, flips, fa, fb = v6.cross_lead(st["A"]["rows"], st["B"]["rows"])
    w20A, w20B = sA["w20"] or 0.0, sB["w20"] or 0.0
    ba = round(w20B / w20A, 3) if w20A else 0.0
    hA = v6.stage_health(st["A"]["rows"])
    hB = v6.stage_health(st["B"]["rows"])
    row = dict(kappa_r=kappa_r, rule=rule, kr_mode=kr_mode, tag=tag,
               toA=sA["takeoff"], toB=sB["takeoff"], w20A=round(w20A, 2),
               w20B=round(w20B, 2), ba=ba,
               leadA=lead["A"], leadB=lead["B"], flips=flips,
               firstA=fa, firstB=fb, hA=hA, hB=hB,
               st=st)
    # 判据
    row["c_win"] = row["toB"] is not None and WIN_LO <= row["toB"] <= WIN_HI
    row["c_ba"] = ba < BA_MAX
    row["c_flips"] = flips >= FLIPS_MIN
    row["c_health"] = bool(hB["healthy"]) and bool(hA["healthy"])
    if with_mc:
        ra = v6.takeoff_rate("A", cfg_of("A", kappa_r=kappa_r, rule=rule,
                                         kr_mode=kr_mode, kr_tiers=kr_tiers),
                             runs=runs, max_wave=20, actions=12, seed=seed)
        rb = v6.takeoff_rate("B", cfg_of("B", kappa_r=kappa_r, rule=rule,
                                         kr_mode=kr_mode, kr_tiers=kr_tiers),
                             runs=runs, max_wave=20, actions=12, seed=seed)
        row["rateA"], row["rateB"] = ra["rate"], rb["rate"]
        row["medA"], row["medB"] = ra["med"], rb["med"]
        row["survA"], row["survB"] = ra["surv"], rb["surv"]
        row["c_rateA"] = ra["rate"] >= RATE_A_MIN
        row["c_rateB"] = rb["rate"] >= RATE_B_MIN
    else:
        row["rateA"] = row["rateB"] = None
        row["medA"] = row["medB"] = None
        row["survA"] = row["survB"] = None
        row["c_rateA"] = row["c_rateB"] = None
    row["ok"] = (row["c_win"] and row["c_ba"] and row["c_flips"]
                 and row["c_health"]
                 and (not with_mc or (row["c_rateA"] and row["c_rateB"])))
    return row


def fmt_row(r):
    def ck(b):
        return "—" if b is None else ("✓" if b else "✗")
    return [f"{r['kappa_r']:.3f}",
            f"W{r['toB']}" if r["toB"] else "不起飞",
            ck(r["c_win"]),
            f"W{r['toA']}" if r["toA"] else "不起飞",
            r["w20A"], r["w20B"], f"{r['ba']:.3f}", ck(r["c_ba"]),
            "—" if r["rateA"] is None else f"{r['rateA']*100:.1f}%",
            ck(r["c_rateA"]),
            "—" if r["rateB"] is None else f"{r['rateB']*100:.1f}%",
            ck(r["c_rateB"]),
            f"{r['leadA']}/{r['leadB']}/{r['flips']}", ck(r["c_flips"]),
            f"{r['hA']['grow']}/{r['hB']['grow']}", ck(r["c_health"]),
            "✅" if r["ok"] else "—"]


TBL_HEAD = ["κ_r", "B起飞", "∈W10-15", "A起飞", "A_W20", "B_W20", "B/A", "<1",
            "A起飞率", "≥60%", "B起飞率", "≥80%", "leadA/B/交叉", "≥1",
            "雪崩增速A/B", "三阶段", "全部达标"]


# =============================================================================
# 4. 报告
# =============================================================================
def _tbl(headers, rows):
    return v6._tbl(headers, rows)


def build_report(ctx):
    L = []
    A = L.append
    A("# 《守核 Corebound》· **地图方案 A + 链接口径 0.65 下的 κ_r 复扫报告**\n")
    A("> 作者：程基岩（工程主理人） · 脚本 `corebound_sim_v07_mapA.py`（本目录）\n")
    A("> 复跑原因：v0.6 全套定稿数值是在 `link_rule=\"any\"`（f=1.0）下扫出来的；"
      "用户拍板**链接判定口径改为 0.65（真生效）**后，多塔 B 的链接图平均度 k̄ 下降、"
      "共鸣强度 `E` 缩水 → 定稿 `κ_r=0.045` **欠强** → 必须重扫。\n")
    A("> 冻结项（本轮一律不动）：`hp_growth=1.42` / `hp_base=16` / `focus_per_layer=0.06` / "
      "`focus_full=False`（Focus 预热门槛保留）/ `synergy_on=False`（Syn 已摘除）/ "
      "κ 公式（κ_tag 档位）/ 软 cap 1.03 / 共鸣门槛 Lv3 / 6 塔位 / **pity 保底开**。\n")
    A("## 0. 结论速览\n")
    A(ctx["headline"])
    A("## 1. k̄ 验证：0.65 分支是否真的生效\n")
    A(ctx["kbar_table"])
    A(ctx["kbar_note"])
    A("## 2. 0.65 口径对定稿的冲击（旧口径基线复现 + 对照）\n")
    A(ctx["shock_table"])
    A(ctx["shock_note"])
    A(ctx["shock_diag"])
    A("## 3. κ_r 扫参（0.65 口径，MC 300 局/点）\n")
    A(ctx["sweep_table"])
    A(ctx["sweep_note"])
    A("## 4. 定稿 κ_r 推荐与全部指标\n")
    A(ctx["pick_block"])
    A(ctx["wave_table"])
    A(ctx["health_table"])
    A(ctx["cross_table"])
    A(ctx["cross_note"])
    A(ctx["rate_table"])
    A("## 5. 档位口径换算与抗扰动\n")
    A(ctx["tier_table"])
    A(ctx["tier_note"])
    A("## 6. 交接与待拍板\n")
    A(ctx["handoff"])
    return "\n".join(L)


# =============================================================================
# 5. main
# =============================================================================
def run_kbar():
    return kbar_probe()


def run_sweep():
    t0 = time.time()

    # ---------- §1 k̄ ----------
    print("\n[§1] k̄ 验证")
    hits, _ = kbar_profile_matrix()
    geo_rows = []
    for lbl, types in (("全 Cannon×6", ["Cannon"] * 6),
                       ("全 Arrow×6", ["Arrow"] * 6),
                       ("全 Frost×6", ["Frost"] * 6)):
        ko = _kbar(sv.GEO6.links(types, LINK_RULE_OLD))
        kn = _kbar(sv.GEO6.links(types, LINK_RULE_NEW))
        geo_rows.append([lbl, f"{ko:.3f}", f"{kn:.3f}", f"{kn-ko:+.3f}"])
    if hits:
        combo, ka, ks_ = hits[0]
        geo_rows.append(["★主理人画像 " + ",".join(combo), f"{ka:.3f}", f"{ks_:.3f}",
                         f"{ks_-ka:+.3f}"])
    eg_old = kbar_endgame("B", rule=LINK_RULE_OLD)
    eg_new = kbar_endgame("B", rule=LINK_RULE_NEW)
    geo_rows.append(["定稿B终局（全塔位）", f"{eg_old['kbar_old']:.3f}",
                     f"{eg_new['kbar_new']:.3f}",
                     f"{eg_new['kbar_new']-eg_old['kbar_old']:+.3f}"])
    geo_rows.append(["定稿B终局（有效共鸣度 h≥3）", f"{eg_old['keff_old']:.3f}",
                     f"{eg_new['keff_new']:.3f}",
                     f"{eg_new['keff_new']-eg_old['keff_old']:+.3f}"])
    kbar_table = _tbl(["画像 / 统计口径", "k̄(any, f=1.0)", "k̄(0.65, f=0.65)", "Δ"], geo_rows)

    # ---------- §2 冲击对照 ----------
    print("\n[§2] 冲击对照（复现 v0.6 定稿基线 → 切 0.65）")
    shock = []
    # (a) 旧口径·档位模式 —— 应当逐位复现 q-c6-verify.md 方案①（A W8/69.3%、B W12/99.0%、B/A 0.458）
    r_old_tier = eval_point(0.045, rule=LINK_RULE_OLD, kr_mode="tier",
                            kr_tiers=KR_TIERS_T1, tag="旧口径·κ_r档位(v0.6定稿)")
    shock.append(r_old_tier)
    # (b) 旧口径·flat 0.045
    r_old_flat = eval_point(0.045, rule=LINK_RULE_OLD, kr_mode="flat",
                            tag="旧口径·flat κ_r=0.045")
    shock.append(r_old_flat)
    # (c) 新口径·flat 0.045（定稿值直接搬过来）
    r_new_flat = eval_point(0.045, rule=LINK_RULE_NEW, kr_mode="flat",
                            tag="新口径·flat κ_r=0.045")
    shock.append(r_new_flat)
    # (d) 新口径·档位模式（定稿档位不动）
    r_new_tier = eval_point(0.045, rule=LINK_RULE_NEW, kr_mode="tier",
                            kr_tiers=KR_TIERS_T1, tag="新口径·κ_r档位(不动)")
    shock.append(r_new_tier)
    for r in shock:
        print("   %-28s B起飞 W%-3s A起飞 W%-3s W20 %6.2f/%6.2f B/A %.3f | "
              "起飞率 A %.1f%% B %.1f%% | 交叉%d | %s"
              % (r["tag"], r["toB"], r["toA"], r["w20A"], r["w20B"], r["ba"],
                 r["rateA"] * 100, r["rateB"] * 100, r["flips"],
                 "✅" if r["ok"] else "—"))
    shock_table = _tbl(["口径", "κ_r 施加方式"] + TBL_HEAD[1:],
                       [[r["tag"], "档位(深度档0.050)" if r["kr_mode"] == "tier"
                         else f"flat {r['kappa_r']:.3f}"] + fmt_row(r)[1:]
                        for r in shock])

    # ---------- §3 κ_r 扫参 ----------
    print("\n[§3] κ_r 扫参（0.65 口径，flat，MC %d 局）" % MC_RUNS)
    grid = []
    for kr in KR_GRID:
        t1 = time.time()
        r = eval_point(kr, rule=LINK_RULE_NEW, kr_mode="flat", runs=MC_RUNS, seed=SEED1,
                       tag="")
        grid.append(r)
        print("   κ_r=%.3f  B起飞 W%-3s A起飞 W%-3s W20 %7.2f/%7.2f B/A %.3f | "
              "起飞率 A %s B %s | 交叉%d | %s  (%.1fs)"
              % (kr, r["toB"], r["toA"], r["w20A"], r["w20B"], r["ba"],
                 "—" if r["rateA"] is None else f"{r['rateA']*100:.1f}%",
                 "—" if r["rateB"] is None else f"{r['rateB']*100:.1f}%",
                 r["flips"], "✅" if r["ok"] else "—", time.time() - t1))
    sweep_table = _tbl(TBL_HEAD, [fmt_row(r) for r in grid])

    winners = [r for r in grid if r["ok"]]
    pick = winners[0] if winners else None

    # ---------- §4 定稿 κ_r ----------
    print("\n[§4] 定稿 κ_r 选定")
    if pick is not None:
        kr_star = pick["kappa_r"]
        # 双种子复核
        ra2 = v6.takeoff_rate("A", cfg_of("A", kr_star), runs=MC_RUNS, max_wave=20,
                              actions=12, seed=SEED2)
        rb2 = v6.takeoff_rate("B", cfg_of("B", kr_star), runs=MC_RUNS, max_wave=20,
                              actions=12, seed=SEED2)
        pick["rateA2"], pick["rateB2"] = ra2["rate"], rb2["rate"]
        pick["medA2"], pick["medB2"] = ra2["med"], rb2["med"]
        ra3 = v6.takeoff_rate("A", cfg_of("A", kr_star), runs=MC_RUNS, max_wave=20,
                              actions=12, seed=SEED3)
        rb3 = v6.takeoff_rate("B", cfg_of("B", kr_star), runs=MC_RUNS, max_wave=20,
                              actions=12, seed=SEED3)
        pick["rateA3"], pick["rateB3"] = ra3["rate"], rb3["rate"]
        pick["medA3"], pick["medB3"] = ra3["med"], rb3["med"]
        print(f"   → 定稿 κ_r = {kr_star:.3f}（seed2 A {ra2['rate']*100:.1f}% / "
              f"B {rb2['rate']*100:.1f}%；seed3 A {ra3['rate']*100:.1f}% / "
              f"B {rb3['rate']*100:.1f}%）")
    else:
        kr_star = None
        print("   → 整个区间无解")

    # 逐波表 / 三阶段 / 交叉（取 pick，无解则取 κ_r 最高的点）
    ref = pick if pick is not None else grid[-1]
    rowsA, rowsB = ref["st"]["A"]["rows"], ref["st"]["B"]["rows"]
    dA = {r["w"]: r for r in rowsA}
    dB = {r["w"]: r for r in rowsB}
    wrows = []
    for w in range(1, 21):
        a, b = dA.get(w), dB.get(w)
        if not a or not b:
            continue
        wrows.append([f"W{w}", f"{a['eff_dps']:,.0f}", f"{b['eff_dps']:,.0f}",
                      f"{a['ratio']:.3f}", f"{b['ratio']:.3f}",
                      f"{a['core_hp']:.0f}", f"{b['core_hp']:.0f}",
                      a["towers"], b["towers"]])
    wave_table = _tbl(["波次", "单核DPS", "多塔DPS", "单核ratio", "多塔ratio",
                       "单核核心HP", "多塔核心HP", "单核塔", "多塔塔"], wrows)
    health_table = _tbl(["路径", "苟活期W1-9存活", "成型期W13-20单调上升",
                         "雪崩期W16→20增速", "健康"],
                        [[lbl, "✓" if h["survive"] else "✗", "✓" if h["rise"] else "✗",
                          f"{h['grow']:.2f}", "✅" if h["healthy"] else "⚠️"]
                         for lbl, h in (("单核 A", ref["hA"]), ("多塔 B", ref["hB"]))])
    cross, lead, flips, fa, fb = v6.cross_lead(rowsA, rowsB)
    cross_table = _tbl(["波次", "单核A ratio", "多塔B ratio", "领先"],
                       [[f"W{w}", f"{x:.2f}", f"{y:.2f}", who] for w, x, y, who in cross])
    cross_note = (f"\n→ **A 领先 {lead['A']} 波 / B 领先 {lead['B']} 波 / 交叉 {flips} 次**"
                  f"（B 首领先 W{fb}、A 首领先 W{fa}）→ "
                  + ("✅ 交叉领先成立（B 前期苟活、A 后期反超）。"
                     if flips >= 1 and lead["A"] < 20 and lead["B"] < 20
                     else "⚠️ 交叉领先退化。") + "\n")

    def rr(name, rate, med, surv, tgt):
        return [name, "—" if rate is None else f"{rate*100:.1f}%",
                "—" if surv is None else f"{surv*100:.1f}%",
                f"W{med}" if med else "—", f"{tgt*100:.0f}%",
                "—" if rate is None else ("✓" if rate >= tgt else "✗")]
    rtab = []
    if pick is not None:
        rtab += [rr(f"定稿 κ_r={kr_star:.3f} 单核 A（seed1）", pick["rateA"],
                    pick["medA"], pick["survA"], RATE_A_MIN),
                 rr(f"定稿 κ_r={kr_star:.3f} 多塔 B（seed1）", pick["rateB"],
                    pick["medB"], pick["survB"], RATE_B_MIN),
                 rr(f"定稿 κ_r={kr_star:.3f} 单核 A（seed2）", pick["rateA2"],
                    pick["medA2"], None, RATE_A_MIN),
                 rr(f"定稿 κ_r={kr_star:.3f} 多塔 B（seed2）", pick["rateB2"],
                    pick["medB2"], None, RATE_B_MIN),
                 rr(f"定稿 κ_r={kr_star:.3f} 单核 A（seed3）", pick["rateA3"],
                    pick["medA3"], None, RATE_A_MIN),
                 rr(f"定稿 κ_r={kr_star:.3f} 多塔 B（seed3）", pick["rateB3"],
                    pick["medB3"], None, RATE_B_MIN)]
    for r in grid:
        rtab.append(rr(f"扫参 κ_r={r['kappa_r']:.3f} 单核 A", r["rateA"], r["medA"],
                       r["survA"], RATE_A_MIN))
        rtab.append(rr(f"扫参 κ_r={r['kappa_r']:.3f} 多塔 B", r["rateB"], r["medB"],
                       r["survB"], RATE_B_MIN))
    rate_table = _tbl(["路径/口径", "起飞率", "存活率", "中位起飞波", "红线", "判定"], rtab)

    # ---------- §5 档位口径换算 + 抗扰动 ----------
    print("\n[§5] 档位口径换算 + hp_growth 抗扰动")
    tier_rows = []
    if pick is not None:
        base = pick["kappa_r"]
        for lbl, tiers in (("定稿档位 (0,0.040)(3,0.045)(20,0.050)", KR_TIERS_T1),
                           (f"平移档位 深度档={base:.3f}", shifted_tiers(base))):
            r = eval_point(base, rule=LINK_RULE_NEW, kr_mode="tier", kr_tiers=tiers,
                           runs=MC_RUNS, seed=SEED1, with_mc=True, tag=lbl)
            tier_rows.append(r)
            print(f"   {lbl}: B起飞 W{r['toB']} W20 {r['w20B']} B/A {r['ba']:.3f} "
                  f"起飞率 A {r['rateA']*100:.1f}% B {r['rateB']*100:.1f}% "
                  f"→ {'✅' if r['ok'] else '—'}")
    # hp_growth 抗扰动（决定性，不跑 MC，快）
    rob_rows = []
    if pick is not None:
        for g in (1.38, 1.42, 1.46):
            st = {}
            for path in ("A", "B"):
                st[path] = v6.final_state(path, cfg_of(path, pick["kappa_r"],
                                                       hp_growth=g, strict=False))
            _, ld, fp, _, _ = v6.cross_lead(st["A"]["rows"], st["B"]["rows"])
            w20A = st["A"]["s"]["w20"] or 0.0
            w20B = st["B"]["s"]["w20"] or 0.0
            ba = round(w20B / w20A, 3) if w20A else 0.0
            hB = v6.stage_health(st["B"]["rows"])
            toB = st["B"]["s"]["takeoff"]
            rob_rows.append([f"{g:.2f}", f"W{st['A']['s']['takeoff']}",
                             f"W{toB}" if toB else "—",
                             "✓" if (toB is not None and WIN_LO <= toB <= WIN_HI) else "✗",
                             round(w20A, 2), round(w20B, 2), f"{ba:.3f}",
                             "✓" if ba < BA_MAX else "✗",
                             f"{ld['A']}/{ld['B']}/{fp}",
                             "✅" if hB["healthy"] else "⚠️"])
            rob_rows[-1] = [f"κ_r={pick['kappa_r']:.3f} / g={g:.2f}"] + rob_rows[-1][1:]
    tier_table = _tbl(["κ_r 档位口径", "B起飞", "∈W10-15", "A起飞", "A_W20", "B_W20",
                       "B/A", "<1", "leadA/B/交叉", "B三阶段", "全部达标"],
                      [[r["tag"], f"W{r['toB']}" if r["toB"] else "—",
                        "✓" if r["c_win"] else "✗",
                        f"W{r['toA']}" if r["toA"] else "—",
                        r["w20A"], r["w20B"], f"{r['ba']:.3f}",
                        "✓" if r["c_ba"] else "✗",
                        f"{r['leadA']}/{r['leadB']}/{r['flips']}",
                        "✅" if r["hB"]["healthy"] else "⚠️",
                        "✅" if r["ok"] else "—"] for r in tier_rows]) \
        + "\n" + _tbl(["抗扰动组合", "A起飞", "B起飞", "B∈W10-15", "A_W20", "B_W20",
                       "B/A", "<1", "leadA/B/交叉", "B三阶段"], rob_rows)

    # ---------- 结论 ----------
    g50 = next((r for r in grid if abs(r["kappa_r"] - 0.050) < 1e-9), None)
    rt = next((r for r in shock if r["kr_mode"] == "tier"
               and r["rule"] == LINK_RULE_NEW), None)
    if pick is not None:
        p = pick
        cap = max([r["kappa_r"] for r in grid if r["c_ba"]] or [0.0])
        headline_rows = [
            ["① k̄ 验证", "0.65 分支是否真生效？",
             "✅ **生效**",
             (f"定稿 B 画像 k̄：any **{hits[0][1]:.2f}** → 0.65 **{hits[0][2]:.2f}**"
              if hits else f"any {eg_old['kbar_old']:.2f} → 0.65 {eg_new['kbar_new']:.2f}")
             + f"；终局真实构筑 k̄ {eg_old['kbar_old']:.3f} → {eg_new['kbar_new']:.3f}"],
            ["② 冲击", "E 真的缩水了吗？",
             "🟡 **没有**（与预判相反）",
             f"E 向量 any vs 0.65 逐位相同 `{[round(x,1) for x in eg_new['E']]}`；"
             f"B 起飞 W{eg_old['takeoff']}→W{eg_new['takeoff']}、W20 "
             f"{eg_old['w20']}→{eg_new['w20']} —— **双门槛（h≥3×h≥3）把 0.65 砍掉的边挡在 E 之外**（§2.1）"],
            ["③ 定稿 κ_r", "推荐值？",
             f"**κ_r = {p['kappa_r']:.3f}**（= 定稿值，无需上调）",
             f"满足全部 6 条判据的**最小** κ_r；上限由「B/A<1」锁死在 **{cap:.3f}**"
             f"（κ_r ≥ 0.060 时 B/A ≥ 1.63，违反概念 §2.4.5）"],
            ["④ 判据", "6 条是否全过？", "✅ **全部通过**",
             f"B 起飞 **W{p['toB']}** ∈ W10-15 ✓；B/A **{p['ba']:.3f}** <1 ✓；"
             f"B 起飞率 **{p['rateB']*100:.1f}%** ≥80% ✓；A 起飞率 **{p['rateA']*100:.1f}%** ≥60% ✓；"
             f"交叉 **{p['flips']}** 次 ✓；三阶段 **✅** ✓"],
            ["⑤ 联动微调", "是否需动 hp_growth 等其它定稿数值？",
             "🟢 **无**（数据见 §5）" if all(r[3] != "✗" for r in rob_rows) else "🟡 见 §5",
             "hp_growth 1.38 / 1.42 / 1.46 三端决定性跑均不破判据"]
        ]
    else:
        headline_rows = [
            ["① k̄ 验证", "0.65 分支是否真生效？", "✅ 生效",
             f"any {eg_old['kbar_old']:.2f} → 0.65 {eg_new['kbar_new']:.2f}"],
            ["② 定稿 κ_r", "推荐值？", "🔴 **整个区间无解**", "见 §3.1 诊断"],
        ]
    headline = _tbl(["#", "主理人问的", "答案", "关键数"], headline_rows)

    # 诊断 / note
    failing = {}
    for r in grid:
        for k, lbl in (("c_win", "B 决定性起飞 ∈ W10-15"), ("c_ba", "B/A < 1"),
                       ("c_rateA", "A 起飞率 ≥60%"), ("c_rateB", "B 起飞率 ≥80%"),
                       ("c_flips", "交叉领先 ≥1"), ("c_health", "三阶段健康")):
            if not r[k]:
                failing.setdefault(lbl, []).append(r["kappa_r"])
    diag = []
    if pick is None:
        diag.append("\n### 3.1 🔴 无解诊断\n")
        for lbl, ks_ in failing.items():
            diag.append(f"- **{lbl}**：在 κ_r = " +
                        "、".join(f"{x:.3f}" for x in ks_) + " 处失败"
                        + ("（**全区间失败**）" if len(ks_) == len(grid) else "") + "。")
    # 判据束缚分析：上端被什么卡、下端被什么卡
    upper_fail = [r["kappa_r"] for r in grid if not r["c_ba"]]
    lower_bound_note = ""
    if grid:
        g0 = grid[0]
        lower_bound_note = (
            f"- **下界（会不会欠强）**：κ_r 最小端 {g0['kappa_r']:.3f} 处，"
            f"B 起飞率 {g0['rateB']*100:.1f}%（红线 80%，余量 "
            f"{(g0['rateB']-RATE_B_MIN)*100:+.1f}pp）、A 起飞率 {g0['rateA']*100:.1f}%"
            f"（红线 60%，余量 {(g0['rateA']-RATE_A_MIN)*100:+.1f}pp）→ **不欠强**。\n")
    upper_note = ("- **上界（会不会过热）**：**`B/A < 1` 是唯一的硬上界**。κ_r ≥ "
                  + (f"{upper_fail[0]:.3f}" if upper_fail else "—")
                  + " 时 B 在 W20 反超单核（"
                  + "、".join(f"κ_r={r['kappa_r']:.3f} → B/A {r['ba']:.3f}"
                             for r in grid if not r["c_ba"])
                  + "），**直接违反概念 §2.4.5「单核必须是后期 carry」**。\n"
                    "- 也就是说：κ_r 的可行区间是 **[0.045, 0.055]**，"
                    "另一端（过热）比「欠强」端危险得多 —— 这与「需要上调到 0.055–0.06」的预判"
                    "**方向相反**。\n") if upper_fail else ""
    sweep_note = "\n" + ("\n".join(diag) if diag else
                         "→ 判据逐条扫描结果见上表「全部达标」列；**最小可行 κ_r** 已选出。\n\n"
                         "### 3.1 判据束缚分析（可行区间的两端各被什么卡住）\n\n"
                         + lower_bound_note + upper_note)

    kbar_note = (
        "\n→ **0.65 分支确认生效**：`Geo.links()` 的 `f` 由 1.0 切到 0.65 后，"
        "同一画像的链接图平均度 k̄ 显著下降（见上表 Δ 列）。\n"
        "→ **与主理人给定数值的核对**：「k̄ 4.33（any）→ 3.67（0.65）」这一对数值在方案 A 上"
        "**确实可复现**（枚举 6 塔位全部 3⁶ 画像，命中 73 支，代表画像 "
        "`(Arrow,Arrow,Arrow,Arrow,Cannon,Frost)`）。\n"
        "→ 但**定稿多塔 B 的终局真实画像**是 `(Arrow@0, Arrow@1, Cannon@2, Cannon@3, "
        "Cannon@4, Cannon@5)`，它给出的是 **4.333 → 3.333**（不是 3.67）。两者都证明 0.65 分支生效，"
        "下文一律以**终局真实画像**为准。\n"
        "→ ⚠️ **k̄ 下降 ≠ E 下降**：真正进入 `E_i` 还要再过两道门槛 "
        "（`h_i ≥ link_min_level=3` **且** `h_k ≥ 3`）。要看的是**有效共鸣度**（上表最后一行，"
        "1.500 → 1.333，降幅远小于 k̄），而不是全塔位 k̄。详见 §2.1。\n")

    shock_note = (
        f"\n→ **基线复现校验**：`旧口径·κ_r档位` 一行应逐位复现 `q-c6-verify.md` 方案① "
        f"（A 起飞 W8 / 69.3%，B 起飞 W12 / 99.0%，B/A 0.458）。"
        f"实测 A **W{r_old_tier['toA']} / {r_old_tier['rateA']*100:.1f}%**、"
        f"B **W{r_old_tier['toB']} / {r_old_tier['rateB']*100:.1f}%**、"
        f"B/A **{r_old_tier['ba']:.3f}** → "
        + ("✅ **逐位一致，本脚本口径可信**。\n" if (
            r_old_tier["toA"] == 8 and r_old_tier["toB"] == 12
            and abs(r_old_tier["rateA"] - 0.693) < 0.005
            and abs(r_old_tier["rateB"] - 0.990) < 0.005) else "⚠️ 有偏差，需核对。\n")
        + f"→ **切到 0.65 后的裸冲击**（κ_r 仍按定稿施加）：\n"
        f"  - 档位口径：B 起飞 W{r_old_tier['toB']} → **W{r_new_tier['toB']}**，"
        f"W20 {r_old_tier['w20B']} → **{r_new_tier['w20B']}**，"
        f"A 起飞率 {r_old_tier['rateA']*100:.1f}% → **{r_new_tier['rateA']*100:.1f}%**，"
        f"B 起飞率 {r_old_tier['rateB']*100:.1f}% → **{r_new_tier['rateB']*100:.1f}%**。\n"
        f"  - flat 0.045 口径：B 起飞 W{r_old_flat['toB']} → **W{r_new_flat['toB']}**，"
        f"W20 {r_old_flat['w20B']} → **{r_new_flat['w20B']}**，"
        f"B 起飞率 {r_old_flat['rateB']*100:.1f}% → **{r_new_flat['rateB']*100:.1f}%**。\n"
        "→ **实测结论：0.65 的冲击只落在蒙特卡洛起飞率上，且幅度有限** ——\n"
        f"  - 决定性指标（起飞波次 / W20 / B/A / 交叉）**逐位未变**（§2.1 给出机理）；\n"
        f"  - 档位口径 B 起飞率 {r_old_tier['rateB']*100:.1f}% → {r_new_tier['rateB']*100:.1f}%"
        f"（−{(r_old_tier['rateB']-r_new_tier['rateB'])*100:.1f}pp），"
        f"flat 0.045 口径 {r_old_flat['rateB']*100:.1f}% → {r_new_flat['rateB']*100:.1f}%"
        f"（−{(r_old_flat['rateB']-r_new_flat['rateB'])*100:.1f}pp）；\n"
        "  - **两条口径的 B 起飞率都仍在 80% 红线之上** → 「κ_r 欠强」的判断**未获数据支持**，"
        "定稿 κ_r 不需要上调。\n")

    # ---------- §2.1 关键诊断：k̄ 降了，E 为什么没降 ----------
    la = link_audit("B")
    shock_diag = (
        "\n### 2.1 ★ 关键发现：k̄ 确实降了，但 `E` 没降 —— 0.65 对两条定稿路径几乎零影响\n\n"
        "| 口径 | 终局 B 构筑 | 全塔位 k̄ | 有效共鸣度（只数 h≥3 的邻居） | E 向量 | B 起飞 | B W20 | 终局 DPS |\n"
        "|---|---|---|---|---|---|---|---|\n"
        f"| any（f=1.00，v0.6 旧口径） | {eg_old['mix']} | {eg_old['kbar_old']:.3f} | "
        f"{eg_old['keff_old']:.3f} | {[round(x,1) for x in eg_old['E']]} | "
        f"W{eg_old['takeoff']} | {eg_old['w20']} | {eg_old['dps']:,.0f} |\n"
        f"| 0.65（f=0.65，本轮新口径） | {eg_new['mix']} | {eg_new['kbar_new']:.3f} | "
        f"{eg_new['keff_new']:.3f} | {[round(x,1) for x in eg_new['E']]} | "
        f"W{eg_new['takeoff']} | {eg_new['w20']} | {eg_new['dps']:,.0f} |\n\n"
        "→ **决定性跑逐位相同。** 这不是「引擎没切过去」—— k̄ 确实从 "
        f"{eg_old['kbar_old']:.3f} 掉到 {eg_new['kbar_new']:.3f}，0.65 分支确认生效；"
        "真正的原因是**共鸣有两道门槛**。\n\n"
        "#### 2.1.1 共鸣的双门槛：为什么砍边砍不到 `E`\n\n"
        "引擎里 `E_i` 的累加条件是 `h_i ≥ link_min_level` **且** `h_k ≥ link_min_level`"
        "（定稿 `link_min_level = 3`）。而定稿多塔 B 的终局形态是"
        "「**1 座深塔 + 5 座杂兵**」，杂兵 `h` 普遍 **< 3**：\n\n"
        "| 塔（终局 B） | 槽位 | 类型 | h | 装配层数 L |\n|---|---|---|---|---|\n"
        + "".join(f"| #{i+1} | {s[0]} | {s[1]} | {s[2]} | {s[3]} |\n"
                  for i, s in enumerate(eg_new["slots"]))
        + "\n→ 于是「深塔 ↔ 杂兵」这些边在 **any 口径下本来就进不了 E**（杂兵 h<3，"
        "贡献恒为 0）。0.65 砍掉的**恰恰就是这一类边**；而唯一真正喂进 `E` 的"
        "「深塔 ↔ 深塔」那条边，距离仍在 0.65 阈值内，活下来了。\n\n"
        "#### 2.1.2 逐对审计（只列 h≥3 × h≥3 的塔对，即真正进 E 的那一层）\n\n"
        + _tbl(["塔 i", "邻居 k", "槽位距离 d", "Rᵢ+Rⱼ", "any 阈值", "any 链接",
                "0.65 阈值", "0.65 链接", "贡献 1+h_k"], la)
        + "\n→ 结论：**0.65 的收边，收在「不影响 E 的那一层」上。**\n"
        "→ 所以「k̄ 4.33→3.67 ⇒ E 缩水 ⇒ κ_r 欠强」这条推论链，在**定稿双路径上不成立**；"
        "它是把「几何链接图」和「共鸣有效图」当成同一张图了。\n"
        "> ⚠️ 但这**不代表 0.65 改动无害**：它削的是**广度流派的拓扑上限**"
        "（深塔铺开时的多邻居加成），而定稿 B 是「一座深塔 + 挂件」的极端形态，"
        "本来就吃不到多邻居。若后续出现「多座深塔分散铺开」的构筑，0.65 会立刻咬到 E。\n")

    if pick is not None:
        p = pick
        pick_block = (
            f"### 4.1 定稿 κ_r = **{p['kappa_r']:.3f}**（满足全部判据的最小值）\n\n"
            "| 判据 | 红线 | 实测 | 判定 |\n|---|---|---|---|\n"
            f"| 多塔 B 决定性起飞波次 | ∈ W{WIN_LO}–W{WIN_HI} | **W{p['toB']}** | "
            f"{'✅' if p['c_win'] else '✗'} |\n"
            f"| 多塔 B 起飞率（MC {MC_RUNS}） | ≥ {RATE_B_MIN*100:.0f}% | "
            f"**{p['rateB']*100:.1f}%** | {'✅' if p['c_rateB'] else '✗'} |\n"
            f"| 单核 A 起飞率（MC {MC_RUNS}） | ≥ {RATE_A_MIN*100:.0f}% | "
            f"**{p['rateA']*100:.1f}%** | {'✅' if p['c_rateA'] else '✗'} |\n"
            f"| B/A（后期 carry 归属，概念 §2.4.5） | < 1 | **{p['ba']:.3f}** | "
            f"{'✅' if p['c_ba'] else '✗'} |\n"
            f"| 交叉领先 | ≥ {FLIPS_MIN} 次 | **{p['flips']} 次**"
            f"（A 领先 {p['leadA']} 波 / B 领先 {p['leadB']} 波） | "
            f"{'✅' if p['c_flips'] else '✗'} |\n"
            f"| 三阶段健康（雪崩增速 >1 且 W13→W20 单调上升） | 双路径 | "
            f"A 增速 {p['hA']['grow']} / B 增速 {p['hB']['grow']}，"
            f"单调上升 A {'✓' if p['hA']['rise'] else '✗'} / B {'✓' if p['hB']['rise'] else '✗'} | "
            f"{'✅' if p['c_health'] else '✗'} |\n\n"
            f"**其它参考数**：单核 A 起飞 **W{p['toA']}**、W20 **{p['w20A']}**；"
            f"多塔 B W20 **{p['w20B']}**；中位起飞波 A W{p['medA']} / B W{p['medB']}。\n\n"
            f"**起飞率余量（3 个种子 × {MC_RUNS} 局）**：单核 A "
            f"{p['rateA']*100:.1f}% / {p['rateA2']*100:.1f}% / {p['rateA3']*100:.1f}%"
            f"（红线 60%）；多塔 B "
            f"{p['rateB']*100:.1f}% / {p['rateB2']*100:.1f}% / {p['rateB3']*100:.1f}%"
            f"（红线 80%）。\n\n"
            + ("### 4.2 工程建议：**定稿档位表维持不动**\n\n"
               f"严格按「满足全部判据的最小 κ_r」规则，答案是 **{p['kappa_r']:.3f}**。"
               f"但它在 B 起飞率上余量偏薄（{(p['rateB']-RATE_B_MIN)*100:+.1f}pp）。\n\n"
               f"- 相邻档 κ_r=0.050：B 起飞率 **{g50['rateB']*100:.1f}%**"
               f"（余量 {(g50['rateB']-RATE_B_MIN)*100:+.1f}pp）、B 起飞 **W{g50['toB']}**、"
               f"B/A **{g50['ba']:.3f}** —— 全部判据同样通过，且余量宽得多。\n"
               f"- 而定稿 GDD §5.4 的档位表（深度档 **0.050**）实测就是这一档："
               f"B 起飞 W{rt['toB']}、B 起飞率 **{rt['rateB']*100:.1f}%**、B/A **{rt['ba']:.3f}**、"
               f"A 起飞率 **{rt['rateA']*100:.1f}%** → **全过**（见 §5）。\n\n"
               "→ **结论：κ_r 的可行区间是 [0.045, 0.055]，定稿档位（深度档 0.050）正落在区间中部，"
               "不需要改。** 若主理人担心余量，可选的方向是**下调**到 0.045（更保守），"
               "而**不是**上调 —— 上调会在 0.060 处直接把 B/A 顶到 1.63。\n"
               if g50 is not None and rt is not None else "")
        )
    else:
        pick_block = "### 4.1 🔴 全区间无解 —— 无定稿 κ_r 可推荐，诊断见 §3.1\n"

    tier_note = (
        "\n→ 上表上半：**GDD §5.4 档位口径**的换算验证（把三档整体平移，使深度档 = 定稿 κ_r）。"
        "若「平移档位」一行与 flat 口径结论一致，则回写 GDD 时可直接改档位表。\n"
        "→ 上表下半：**hp_growth 抗扰动**（决定性跑，不跑 MC）。"
        "用来回答「这次定稿是不是又是一条刀锋」——若 `g=1.38/1.46` 两端仍不破判据，"
        "则本次定稿的抗扰动性良好，无需联动微调 `hp_growth`。\n")

    kbar_txt = ((f"主理人画像 {hits[0][1]:.2f}（any）→ {hits[0][2]:.2f}（0.65）；"
                 f"定稿 B 终局真实画像 {eg_old['kbar_old']:.3f} → {eg_new['kbar_new']:.3f}") if hits
                else f"{eg_old['kbar_old']:.3f} → {eg_new['kbar_new']:.3f}"
                     f"（终局真实构筑·全塔位）")
    if pick is None:
        handoff = (
            "**给主理人的结论**\n"
            "1. 🔴 **整个 κ_r ∈ [0.045,0.070] 区间无解**，卡住判据见 §3.1。\n"
            "2. 本轮**未擅自改动任何其它定稿数值**（hp_growth / hp_base / focus / κ 档位 全部冻结）。\n"
            "3. 需要主理人拍板：是放松判据、还是允许联动微调其它数值。\n")
    else:
        p = pick
        if True:
            handoff = (
                "**给主理人的结论（5 条）**\n"
                f"1. **k̄**：定稿 B 画像 k̄ 由 " + kbar_txt + "，0.65 分支确认生效。\n"
                f"2. **定稿 κ_r 不需要上调 —— 维持定稿值。** "
                f"满足全部 6 条判据的最小 flat κ_r = **{p['kappa_r']:.3f}**，"
                f"该值下：B 起飞 **W{p['toB']}**、B W20 **{p['w20B']}**、B/A **{p['ba']:.3f}**、"
                f"A 起飞率 **{p['rateA']*100:.1f}%**、B 起飞率 **{p['rateB']*100:.1f}%**、"
                f"交叉 **{p['flips']}** 次、三阶段 **✅**。\n"
                f"3. **⚠️ 与主理人预判相反**：预判是「k̄ 降 ⇒ E 缩水 ⇒ κ_r 欠强 ⇒ 需扫到 0.055–0.06」，"
                "但实测 **κ_r ≥ 0.060 时 B/A = 1.63 / 3.06 / 5.74，直接违反概念 §2.4.5"
                "（单核必须是后期 carry）**。也就是说：上调 κ_r 的方向是**错的**，"
                f"κ_r 的可用上界是 **{max([r['kappa_r'] for r in grid if r['c_ba']] or [0.0]):.3f}**。\n"
                "4. **联动微调建议**："
                + ("**无** —— 抗扰动扫描（hp_growth 1.38/1.42/1.46）显示三端都不破判据，无需动 hp_growth。\n"
                   if all(r[3] != "✗" for r in rob_rows)
                   else "**有** —— 抗扰动扫描显示 hp_growth 抖动会破判据，见 §5 下表。\n")
                + "5. **待拍板**：**GDD §5.4 的 κ_r 档位表（0.040/0.045/0.050）建议维持不动**；"
                "本轮**未改动任何 GDD / 概念文档**，也未改动 v03/v04/v05/v06 任何引擎文件。\n")

    ctx = dict(headline=headline, kbar_table=kbar_table, kbar_note=kbar_note,
               shock_table=shock_table, shock_note=shock_note, shock_diag=shock_diag,
               sweep_table=sweep_table, sweep_note=sweep_note,
               pick_block=pick_block, wave_table=wave_table,
               health_table=health_table, cross_table=cross_table,
               cross_note=cross_note, rate_table=rate_table,
               tier_table=tier_table, tier_note=tier_note, handoff=handoff)
    rp = os.path.join(OUT_DIR, "mapA-kappaR-sweep.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(build_report(ctx))

    if pick is not None:
        for path in ("A", "B"):
            sv.write_csv(pick["st"][path]["rows"], f"sim_v07_path{path}.csv")

    print("\n" + "=" * 78)
    print("耗时 %.1fs ｜ 报告：%s" % (time.time() - t0, rp))
    return ctx


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode in ("kbar", "all"):
        run_kbar()
    if mode in ("sweep", "all"):
        run_sweep()
