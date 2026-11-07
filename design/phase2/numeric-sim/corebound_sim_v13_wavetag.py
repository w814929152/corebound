# -*- coding: utf-8 -*-
"""
《守核 Corebound》Phase 2 — **v0.13：wave_tag（敌人构成）能不能当阵营的定价器**

================================================================================
它要回答的一个问题
================================================================================
`faction-decks.md` 的结论是：阵营要「有得选」，缺的不是卡，是**定价器**——敌人构成。
当前 sim 只有一条 HP 曲线，所有波次构成相同，于是：
    霜序等不到「值得慢下来的目标」，枢网的广覆盖永远打不过一座塔打穿。

本脚本做两件事：
  P0 · 三参数扫描：确认 wave_tag 的 n/hp 修正**不改变总难度曲线**（总血量守恒）。
  P2 · 三路对照：给引擎补「构成敏感」的物理层，验证三个阵营能否因敌人构成而分化。

================================================================================
★ 方法学前提（必须先讲清，否则这是假实验）
================================================================================
v03/v08 的 DPS 模型是「**总 DPS 均匀削血**」：`dps_only(player, cfg, geo)` 的签名里
根本没有「本波怪物构成」这个参数。`n` 只决定出怪间隔，胜负只由 `total_hp / dps` 决定。
⇒ 在**总血量守恒**的前提下，直接改 `n`/`hp` 的拆分，会被引擎完全吸收成「没变化」——
   这正是 keyword-adaptation.md 里记过的「恒定系数被吸收」同款陷阱。

所以 wave_tag 要产生阵营差异，必须给引擎补一个**缺失的物理层**：
    ① 单体溢出（overkill）   —— 单体塔打多怪，单发 > 单只血量会浪费；溅射塔不浪费
    ② 减速驻留（slow dwell） —— 减速塔的价值 = 减速比例 × 驻留时长，怪越肉驻留越久

本脚本用「**构成调制因子**」把这两层物理做进来：它是「塔属性 × 波构成」的交叉项，
落在「有效 DPS」上，**不碰 `dps_only_v8` 金标本**（在 v13 层包装）。

⚠️ 这是**粗粒度近似**，不是从引擎内部涌现的精确物理。三个调制因子的数值是
**假设**（标 `[HYP]`），不是定稿。方向性结论可信，具体数值待真实战斗引擎校准。
关闭 wave_tag 时必须与 v08 逐位一致 —— 这是守住金标本的唯一方式。

================================================================================
用法
================================================================================
  python corebound_sim_v13_wavetag.py selfcheck   # 关闭时与 v08 逐位一致
  python corebound_sim_v13_wavetag.py p0          # 三参数扫描：总难度曲线不变
  python corebound_sim_v13_wavetag.py p2          # 三路对照：阵营是否分化
  python corebound_sim_v13_wavetag.py mc 300      # 300 局 MC（含 wave_tag 的通过率）
"""

import random
import statistics
import sys
import time

import corebound_sim_v03 as sv
import corebound_sim_v06_synergy as v6
import corebound_sim_v08_salvage as v8
import corebound_sim_v11_chain as v11

# =============================================================================
# 0. wave_tag 定义
# =============================================================================
# 每个 wave_tag 的「构成修正」：总血量守恒（n_mult × hp_mult ≈ 1.0 附近，允许微小
# 误差，因为 n 是整数取整）。数值为假设 [HYP]，方向有物理依据，具体值待校准。

WAVE_TAGS = {
    #  name      n_mult   hp_mult   物理依据 / 受益塔
    "Swarm":   dict(n=1.5,  hp=1.0 / 1.5,  dur=1.0,  desc="多怪低血：单体溢出、溅射命中多 → 熔炉(Cannon AoE)"),
    "Armor":   dict(n=0.6,  hp=1.0 / 0.6,  dur=1.0,  desc="少怪高血：减速驻留久、溅射无收益 → 霜序(Frost slow)"),
    "Trickle": dict(n=1.0,  hp=1.0,        dur=2.0,  desc="慢出怪长窗口：长射程覆盖久 → 枢网(Arrow rng)"),
}

# 每个阵营（faction）对应的一组 wave_tag 偏好权重 —— 用于 P2 三路对照。
# [HYP] 权重本身也是假设，只用于「验证方向」，不用于最终配平。
FACTIONS = {
    "cinder": dict(desc="熔炉（火/溅射）", tag_boost={"Swarm": 1.0}),
    "rime":   dict(desc="霜序（冰/减速）", tag_boost={"Armor": 1.0}),
    "lattice":dict(desc="枢网（长射程）", tag_boost={"Trickle": 1.0}),
}

# =============================================================================
# 1. 构成调制：把「塔属性 × 波构成」的交叉项作用到有效 DPS 上
# =============================================================================
# 塔属性来自 sv.TOWERS：aoe(bool), slow(float), rng(float)
# 波构成来自 wave_tag：Swarm(多怪)/Armor(肉怪)/Trickle(慢出)

# 构成调制因子 [HYP]：
#   Swarm 波：AoE 塔的「密度效率」放大（溅射命中更多），单体塔有溢出损耗
#   Armor 波：减速塔的「驻留收益」放大（肉怪驻留久），AoE 塔无溅射收益
#   Trickle 波：长射程塔的「覆盖时长」放大
COMPOSITION_MOD = {
    # 对每类塔属性，在对应 wave_tag 下的有效乘数
    "Swarm":   dict(aoe=1.30,  slow=0.85,  rng=1.00),  # 溅射 +30%，减速 -15%（脆怪还没减速就死）
    "Armor":   dict(aoe=0.85,  slow=1.30,  rng=1.00),  # 溅射 -15%（单个肉怪无溅射），减速 +30%
    "Trickle": dict(aoe=1.00,  slow=1.00,  rng=1.15),  # 长射程 +15%（覆盖窗口翻倍）
}


def wave_tag_of(w, cfg):
    """返回第 w 波的 wave_tag。默认 None（无构成差异，退回金标本）。"""
    if not cfg.get("wave_tag_on", False):
        return None
    seq = cfg.get("wave_tag_seq", {})
    # seq 是 {起始波: tag}，取不超过 w 的最大键
    keys = sorted([k for k in seq if k <= w])
    return seq[keys[-1]] if keys else None


def composition_factor(player, cfg, tag):
    """给定 wave_tag，计算全场「构成调制因子」（塔构成 × 波构成的交叉项）。

    每个塔按其属性（aoe/slow/rng）拿到一个调制系数，按该塔的 DPS 占比加权合成
    全场因子。这样「多 AoE 塔的队伍在 Swarm 波更强」就自然涌现，而不是写死。
    """
    if tag is None:
        return 1.0
    ts = player.towers
    if not ts:
        return 1.0
    # 每座塔的基础 dps（不含构成调制），用于加权
    total, info = v11.compute_dps_v11(player, cfg, None)
    per = info.get("per_tower", [])
    if not per:
        return 1.0
    mod = COMPOSITION_MOD[tag]
    num = 0.0
    den = 0.0
    for i, t in enumerate(ts):
        d = per[i].get("dps", 0.0) if i < len(per) else 0.0
        if d <= 0:
            continue
        attr = sv.TOWERS[t.ctype]
        # 塔的构成调制：按属性加权（aoe 塔吃 aoe 调制，slow 塔吃 slow 调制，rng 塔吃 rng 调制）
        f = 1.0
        if attr["aoe"]:
            f *= mod["aoe"]
        if attr["slow"] > 0:
            f *= mod["slow"]
        if attr["rng"] >= 22.0:
            f *= mod["rng"]
        num += d * f
        den += d
    return num / den if den > 0 else 1.0


# =============================================================================
# 2. 波次仿真（包装 v08，只在「有效 DPS」上乘构成因子）
# =============================================================================
def _eff_dps(player, cfg, geo, tag):
    """有效 DPS = 基础 DPS × 构成调制因子。关闭 wave_tag 时 factor=1 → 逐位一致。"""
    total, info = v11.compute_dps_v11(player, cfg, geo)
    return total * composition_factor(player, cfg, tag), info


def run_v13(path, cfg, max_wave=20, geo=None, rng=None):
    """复刻 v08 的主循环，但把「有效 DPS」换成带构成调制的版本。

    关键：wave_tag 只改「有效 DPS 的构成因子」，不改怪物数值（n/hp 守恒，见 P0）。
    因此关闭 wave_tag 时，本函数必须与 v08 逐位一致（selfcheck 验证）。
    """
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

        # 本波构成
        tag = wave_tag_of(w, cfg)
        cfg2 = _apply_tag_to_monsters(cfg, w, tag)

        res = sv.simulate_wave(player, w, cfg2, geo)
        core_hp -= res["core_damage"]
        income = res["scrap_earned"] * (1.0 + player.income_mult)
        cum += income

        # 商店（复用 v08 的 shop_phase；wave_tag 不改经济）
        budget, rr = v8.shop_phase_v08(player, cum, w, cfg, geo, rng, st)
        cum = budget
        cum_rerolls += rr
        st["n_hist_max"] = max(st["n_hist_max"], len(player.towers))
        player.n_hist_max = st["n_hist_max"]

        # ★ 用带构成调制的有效 DPS 算 ratio（在 shop 之后，与 v08 顺序一致）
        eff, info = _eff_dps(player, cfg, geo, tag)

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


def _apply_tag_to_monsters(cfg, w, tag):
    """按 wave_tag 修正怪物构成，但**总血量守恒**（n × hp 不变）。

    若 tag is None，原样返回 cfg（不复制、不改动 → 逐位一致）。
    """
    if tag is None or tag not in WAVE_TAGS:
        return cfg
    wt = WAVE_TAGS[tag]
    # 这里不直接改 cfg（那是共享的），而是返回一个浅拷贝并覆盖 num_base/num_growth
    # 因为 n = num_base + num_growth*w，要精确控制 n_mult 需要覆盖成固定 n。
    # 简化：直接覆盖 cfg 的 num/hp 生成 —— 但为避免污染，复制一份。
    c = dict(cfg)
    base_n = cfg["num_base"] + cfg["num_growth"] * w
    base_hp = cfg["hp_base"] * (cfg["hp_growth"] ** (w - 1))
    # 用固定值覆盖：num_base 与 num_growth 组合成目标 n，hp_base/hp_growth 组合成目标 hp
    c["num_base"] = base_n * wt["n"]
    c["num_growth"] = 0.0
    c["hp_base"] = base_hp * wt["hp"]
    c["hp_growth"] = 1.0
    # Trickle：出怪窗口翻倍 → 覆盖 wave_dur
    if wt["dur"] != 1.0:
        c["wave_dur"] = lambda w, _d=cfg["wave_dur"]: _d(w) * wt["dur"]
    return c


# =============================================================================
# 3. 校验与实验
# =============================================================================
def selfcheck():
    """关闭 wave_tag 时，v13 必须与 v08 逐位一致。"""
    worst = 0.0
    for path in ("A", "B"):
        cfg = v8.cfg_of(path)
        cfg["wave_tag_on"] = False
        r13, _, _ = run_v13(path, cfg, 20, geo=sv.GEO6, rng=None)
        r8, _, _ = v8.run_v08(path, v8.cfg_of(path), 20, geo=sv.GEO6, rng=None)
        if len(r13) != len(r8):
            return float("inf")
        for x, y in zip(r13, r8):
            worst = max(worst, abs(x["eff_dps"] - y["eff_dps"]))
    return worst


def p0_scan():
    """P0：三参数扫描，确认 wave_tag 的总血量守恒（不改变总难度曲线）。"""
    print("=" * 96)
    print("P0 · wave_tag 总血量守恒扫描（n × hp 应 ≈ 原曲线）")
    print("=" * 96)
    cfg = v8.cfg_of("A")
    print(f"{'tag':<10} {'w':>3} {'原n':>6} {'原hp':>9} {'原total_hp':>11} "
          f"{'tag_n':>7} {'tag_hp':>9} {'tag_total':>11} {'守恒比':>7}")
    print("-" * 96)
    for tag in WAVE_TAGS:
        for w in (1, 5, 10, 15, 20):
            base_n = cfg["num_base"] + cfg["num_growth"] * w
            base_hp = cfg["hp_base"] * (cfg["hp_growth"] ** (w - 1))
            base_total = base_n * base_hp
            wt = WAVE_TAGS[tag]
            tn = base_n * wt["n"]
            thp = base_hp * wt["hp"]
            ttotal = tn * thp
            print(f"{tag:<10} {w:>3} {base_n:>6.1f} {base_hp:>9.1f} {base_total:>11.1f} "
                  f"{tn:>7.1f} {thp:>9.1f} {ttotal:>11.1f} {ttotal/base_total:>7.4f}")
        print()
    print("注：Trickle 的 n/hp 不变，守恒比恒为 1.0，其差异在出怪时长（×2.0），不影响总血量。")


def _default_tag_seq():
    """默认波次节奏：W1-3 Swarm、W4 首次 Armor、W10 首次 Trickle（faction-decks §4）。"""
    seq = {}
    for w in range(1, 21):
        if w <= 3:
            seq[w] = "Swarm"
        elif w <= 9:
            seq[w] = "Armor" if w % 2 == 0 else "Swarm"
        elif w <= 14:
            seq[w] = "Trickle" if w % 3 == 0 else "Armor"
        else:
            seq[w] = "Trickle" if w % 2 == 0 else "Armor"
    return seq


def p2_contrast():
    """P2：三路对照 —— 同一玩家/AI 下，wave_tag 让不同塔构成产生不同有效 DPS。"""
    print("=" * 96)
    print("P2 · 构成调制：同一队伍在不同 wave_tag 下的有效 DPS 因子")
    print("=" * 96)
    cfg = v8.cfg_of("A")
    cfg["wave_tag_on"] = True
    cfg["wave_tag_seq"] = _default_tag_seq()
    geo = sv.GEO6

    # 构造三个「代表队伍」：熔炉(全 Cannon)、霜序(全 Frost)、枢网(全 Arrow+长射程)
    def make_faction_towers(path, ctype, n):
        p = sv.new_player(path, cfg, geo)
        p.towers = []
        for i in range(n):
            from types import SimpleNamespace
            t = SimpleNamespace(slot=i, ctype=ctype, h=5, attach={})
            p.towers.append(t)
        return p

    print(f"\n{'tag':<10} {'熔炉(Cannon×3)':>18} {'霜序(Frost×3)':>18} {'枢网(Arrow×3)':>18}")
    print("-" * 96)
    for tag in ("Swarm", "Armor", "Trickle"):
        row = []
        for ctype, label in (("Cannon", "熔炉"), ("Frost", "霜序"), ("Arrow", "枢网")):
            p = make_faction_towers("A", ctype, 3)
            f = composition_factor(p, cfg, tag)
            row.append(f)
        print(f"{tag:<10} {row[0]:>18.3f} {row[1]:>18.3f} {row[2]:>18.3f}")
    print()
    print("读法：每行 = 一个 wave_tag，每列 = 一个阵营。对角线应 > 非对角线，")
    print("即 Swarm 行熔炉列最高、Armor 行霜序列最高、Trickle 行枢网列最高。")


def run_mc(runs=300, seed=None):
    """MC：wave_tag 开/关下，A/B 起飞率是否改变（验证「构成差异」是否影响胜负）。"""
    print("=" * 96)
    print(f"v0.13 MC（{runs} 局/路径）—— wave_tag 对起飞率的影响")
    print("=" * 96)
    if seed is None:
        seed = v8.SEED1
    cells = [
        ("base",      dict(wave_tag_on=False)),
        ("wavetag",   dict(wave_tag_on=True, wave_tag_seq=_default_tag_seq())),
    ]
    print("| 实验格   | A率   | B率   | A中位起飞 | B中位起飞 |")
    print("|----------|-------|-------|-----------|-----------|")
    for name, kw in cells:
        a_to, b_to = [], []
        a_hit = b_hit = 0
        for path in ("A", "B"):
            rng = random.Random(seed)
            cfg = v8.cfg_of(path)
            cfg.update(kw)
            cfg["max_actions"] = cfg.get("max_actions") or 12
            hits = tos = 0
            to_list = []
            for _ in range(runs):
                rows, _, _ = run_v13(path, cfg, 20, geo=sv.GEO6, rng=rng)
                alive = bool(rows) and rows[-1]["core_hp"] > 0
                tw = sv.takeoff_wave(rows)
                if alive and tw is not None:
                    hits += 1
                    to_list.append(tw)
            if path == "A":
                a_hit, a_to = hits, to_list
            else:
                b_hit, b_to = hits, to_list
        print(f"| {name:<8} | {a_hit/runs:.3f} | {b_hit/runs:.3f} | "
              f"{statistics.median(a_to) if a_to else '—':>9} | "
              f"{statistics.median(b_to) if b_to else '—':>9} |")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "selfcheck"
    t0 = time.time()
    if mode == "selfcheck":
        d = selfcheck()
        print(f"[selfcheck] 关闭 wave_tag 时 v13 vs v08 逐波 DPS 最大绝对差：{d:.3e}（必须 = 0.000e+00）")
    elif mode == "p0":
        p0_scan()
    elif mode == "p2":
        p2_contrast()
    elif mode == "mc":
        run_mc(int(sys.argv[2]) if len(sys.argv) > 2 else 300)
    print(f"\n总耗时 {time.time()-t0:.1f}s")
