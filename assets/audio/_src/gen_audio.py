#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Corebound · 音频 MVP 资产生成器（build tooling —— 非运行时资产）
================================================================================
任务：T-P6-07 · 音频 MVP 资产制作批次
依据：docs/phase6/audio-assets-plan.md §3（自助路径）+ §4（交付规格）
      docs/phase6/audio-spec-a.md §1.3（音色词典）/ §3.1（资产 id）/ §3.2（实现明细）

基调 A = 暗黑机械电子。全部程序化合成（numpy）——无外部采样、无 DAW。
落盘：assets/audio/{music,sfx,ui}/，命名与 audio-spec-a §3.1 的资产 id 逐字一致。
格式：音乐 .ogg(Vorbis 流式) / 短音 .wav(PCM_24)；stereo(音乐/UI) · mono(SFX 定位音)。
响度：长音(≥1s)→ −16 LUFS integrated（真峰 ≤ −1 dBTP）；短瞬态→ 真峰归一（见报告）。

🔴 本文件是「构建脚本」，不是引擎资产；引擎实现（AudioDirector）由工程另做。
   重跑： python assets/audio/_src/gen_audio.py
"""
import os, sys, json, math
import numpy as np
import soundfile as sf

SR = 48000
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))  # assets/audio
rng = np.random.default_rng(20261013)  # 确定性

# 音乐网格：BPM 96 / D 小调；4 小节循环 = 10.0 s
BPM = 96.0
BEAT = 60.0 / BPM           # 0.625 s
LOOP = 4 * 4 * BEAT         # 10.0 s（16 拍）
XF = 0.02                   # 循环折叠交叉淡化窗口(s)
GLEN = LOOP + XF            # 合成长度（多出的 XF 用于折叠）
NOTE = {  # 音名→频率（Hz）
    "D1": 36.71, "D2": 73.42, "A2": 110.00, "D3": 146.83, "F3": 174.61,
    "A3": 220.00, "D4": 293.66, "F4": 349.23, "A4": 440.00, "D5": 587.33,
}

# ---------------------------------------------------------------------------
#  基础工具
# ---------------------------------------------------------------------------
def tt(dur):
    return np.arange(int(round(dur * SR)), dtype=np.float64) / SR

def sine(f, t, ph=0.0):
    return np.sin(2 * np.pi * f * t + ph)

def sine_phase(freq_arr):
    """频率随时间变化的相位（∫f dt）。"""
    return np.cumsum(2 * np.pi * freq_arr / SR)

def noise(n):
    return rng.standard_normal(n)

def env_exp(n, tau):
    """指数衰减 1→0，时间常数 tau(s)。"""
    return np.exp(-np.arange(n) / max(tau * SR, 1.0))

def env_ar(n, a, r, curve=3.0):
    """攻击-衰减包络。"""
    a_n = max(1, int(a * SR))
    e = np.zeros(n)
    e[:a_n] = np.linspace(0.0, 1.0, a_n)
    e[a_n:] = np.exp(-curve * np.linspace(0.0, 1.0, max(n - a_n, 1)))
    return e

def _mag_filter(x, Hfun, pad):
    n0 = len(x)
    if pad:
        xp = np.concatenate([x, np.zeros(n0)])
        n = len(xp)
    else:
        xp, n = x, n0
    X = np.fft.rfft(xp)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(X * Hfun(f), n)
    return y[:n0]

def lp(x, fc, order=2, pad=True):
    return _mag_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)), pad)

def hp(x, fc, order=2, pad=True):
    return _mag_filter(x, lambda f: (f / fc) ** order / np.sqrt(1.0 + (f / fc) ** (2 * order)), pad)

def bp(x, fc, q=1.0, pad=True):
    # |H| = 1/sqrt(1 + Q^2 (f/fc - fc/f)^2)
    return _mag_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (q ** 2) * (f / fc - fc / np.maximum(f, 1e-6)) ** 2), pad)

def res_lp(x, fc, q=3.0, order=2, pad=True):
    def H(f):
        r = f / fc
        peak = 1.0 + (q - 1.0) * np.exp(-(np.log(np.maximum(r, 1e-6)) ** 2) / (2 * 0.25 ** 2))
        return (1.0 / np.sqrt(1.0 + r ** (2 * order))) * peak
    return _mag_filter(x, H, pad)

def sat(x, drive=1.5):
    return np.tanh(x * drive)

def bitcrush(x, bits=8):
    q = 2 ** (bits - 1)
    return np.round(np.clip(x, -1, 1) * q) / q

def compress(x, thr_db=-14.0, ratio=3.0, win_ms=10.0, makeup_db=0.0):
    """简易前馈压缩（包络=移动平均），降 crest factor。x: 1D 或 (n,2)。"""
    m = _mono(x)
    w = max(1, int(win_ms / 1000.0 * SR))
    env = np.convolve(np.abs(m), np.ones(w) / w, mode="same") + 1e-9
    env_db = 20.0 * np.log10(env)
    over = np.maximum(env_db - thr_db, 0.0)
    gain_db = -over * (1.0 - 1.0 / ratio) + makeup_db
    g = 10 ** (gain_db / 20.0)
    return x * g[:, None] if np.asarray(x).ndim == 2 else x * g

def pan(x, p=0.0):
    """等功率声像；返回 stereo (n,2)。"""
    th = (np.clip(p, -1, 1) + 1.0) / 2.0 * (np.pi / 2.0)
    return np.stack([x * np.cos(th), x * np.sin(th)], axis=1)

def haas(x, ms=12.0):
    """Haas 展宽：右声道微延时 → stereo。"""
    d = int(ms / 1000.0 * SR)
    l = x
    r = np.concatenate([np.zeros(d), x])[:len(x)]
    return np.stack([l, r], axis=1)

def make_seamless(x, loop_s=None, xfade_ms=None):
    """
    正确的「交叉淡化循环」：把多出的尾段折入头部，返回长度 = loop_s 的无缝循环。
    输入 x 长度须 = loop_s*(1) + xfade（即按 GLEN 合成）。
    """
    loop_s = LOOP if loop_s is None else loop_s
    xf_ms = (XF * 1000.0) if xfade_ms is None else xfade_ms
    x = np.asarray(x)
    L = int(round(loop_s * SR))
    d = x.shape[0] - L
    if d <= 0:
        return x
    body = x[:L].copy()
    tail = x[L:L + d]
    fade = np.linspace(0.0, 1.0, d)
    if x.ndim == 2:
        body[:d] = body[:d] * fade[:, None] + tail * (1.0 - fade)[:, None]
    else:
        body[:d] = body[:d] * fade + tail * (1.0 - fade)
    return body

# ---------------------------------------------------------------------------
#  响度（BS.1770 近似）与真峰
# ---------------------------------------------------------------------------
def _kweight(x):
    def shelf(f):
        fc = 1681.0; g = 10 ** (4.0 / 20)
        return 1.0 + (g - 1.0) * (f / fc) ** 2 / (1.0 + (f / fc) ** 2)
    y = _mag_filter(x, shelf, pad=False)
    y = _mag_filter(y, lambda f: (f / 38.0) ** 2 / (1.0 + (f / 38.0) ** 2), pad=False)
    return y

def _mono(x):
    x = np.asarray(x)
    return x.mean(axis=1) if x.ndim == 2 else x

def integrated_lufs(x):
    y = _kweight(_mono(x))
    bs = int(0.4 * SR); hop = max(bs // 4, 1)
    if len(y) < bs:
        blocks = [y]
    else:
        blocks = [y[i:i + bs] for i in range(0, len(y) - bs + 1, hop)]
    ms = np.array([np.mean(b ** 2) for b in blocks]) + 1e-12
    loud = -0.691 + 10 * np.log10(ms)
    keep = loud > -70.0
    if not keep.any():
        return float(-0.691 + 10 * np.log10(np.mean(ms)))
    thr = -0.691 + 10 * np.log10(np.mean(ms[keep])) - 10.0
    keep2 = keep & (loud > thr)
    sel = ms[keep2] if keep2.any() else ms[keep]
    return float(-0.691 + 10 * np.log10(np.mean(sel)))

def true_peak(x, L=4):
    x = np.asarray(x)
    if x.ndim == 2:
        return max(true_peak(x[:, 0], L), true_peak(x[:, 1], L))
    n = len(x)
    X = np.fft.rfft(x)
    Y = np.zeros(n * L // 2 + 1, dtype=complex)
    Y[:X.shape[0]] = X
    y = np.fft.irfft(Y, n * L) * L
    return float(np.max(np.abs(y)))

def db(v):
    return 20.0 * math.log10(max(v, 1e-12))

def normalize(x, mode="rms", target=-18.0, ceiling=-1.5):
    """
    mode='lufs': 目标 integrated LUFS = target
    mode='rms' : 目标 RMS(dBFS)      = target
    mode='peak': 目标真峰(dBTP)      = target
    最后统一受 ceiling（dBTP）约束。stereo 下以 mono 混合计测，增益同施两声道。
    """
    m = _mono(x)
    if mode == "lufs":
        cur = integrated_lufs(m)
    elif mode == "rms":
        cur = 20.0 * math.log10(np.sqrt(np.mean(m ** 2)) + 1e-12)
    else:
        cur = db(true_peak(m))
    g = 10 ** ((target - cur) / 20.0)
    y = x * g
    tp = db(true_peak(y))
    if tp > ceiling:
        y = y * 10 ** ((ceiling - tp) / 20.0)
    return y

# ===========================================================================
#  资产合成
# ===========================================================================
def gen_ui_reroll(idx):
    """翻牌：滤波噪声滑音 + 机械 click。stereo。"""
    dur = 0.16 + 0.02 * idx
    n = int(dur * SR); t = tt(dur)
    nz = noise(n)
    lo = bp(nz, 1100.0 + idx * 250, q=0.8)
    hi = bp(noise(n), 4200.0 + idx * 400, q=0.8)
    ramp = np.linspace(0, 1, n)
    sweep = lo * (1 - ramp) ** 1.5 + hi * ramp ** 2.0
    click = sine(2100.0 + idx * 120, t) * env_exp(n, 0.004)
    tick = np.zeros(n); tick[:int(0.0025 * SR)] = 0.7
    y = (sweep * 0.8 + click * 0.45 + tick) * env_exp(n, 0.045)
    return normalize(pan(y, 0.0), "rms", -18.0)

def gen_ui_buy(idx):
    """购买：FM 铃，稀有度越高越"贵"（音高↑/亮度↑/尾↑）。stereo。"""
    fc = [NOTE["D4"] * 1.5, NOTE["F4"], NOTE["A4"], NOTE["D5"], NOTE["D5"] * 1.5][idx]
    dur = 0.16 + 0.035 * idx
    n = int(dur * SR); t = tt(dur)
    I = (1.4 + 0.8 * idx) * np.exp(-t / 0.05)
    mod = I * np.sin(2 * np.pi * fc * 2.0 * t)
    bell = np.sin(2 * np.pi * fc * t + mod) * env_exp(n, 0.06 + 0.03 * idx)
    sparkle = sine(fc * 4.0, t) * env_exp(n, 0.015) * (0.08 + 0.05 * idx)
    y = bell * 0.85 + sparkle
    return normalize(pan(y, 0.0), "rms", -18.0)

def gen_kill(idx):
    """击杀：噪声瞬态 + FM click（橙，金属碎屑）。mono。4 变体。"""
    dur = [0.06, 0.075, 0.095, 0.115][idx]
    n = int(dur * SR); t = tt(dur)
    base = [320.0, 360.0, 300.0, 275.0][idx]
    trans = bp(noise(n), 2400.0 + idx * 350, q=0.7) * env_exp(n, 0.018)
    click = sine(base * 2.0, t) * env_exp(n, 0.010)
    body = sine(base, t) * env_exp(n, 0.030)
    y = sat(trans * 0.9 + click * 0.5 + body * 0.45, 1.4) * env_exp(n, 0.02)
    return normalize(y, "rms", -18.0)

def gen_swarm():
    """洪流颗粒层：密集噪声收割（循环）。mono。"""
    dur = 0.5 + XF
    n = int(dur * SR); t = tt(dur)
    base = bp(noise(n), 3200.0, q=0.5, pad=False) + bp(noise(n), 6500.0, q=0.5, pad=False) * 0.5
    am = 0.45 + 0.55 * np.clip(0.5 + 0.5 * np.sin(2 * np.pi * 40.0 * t) + 0.5 * np.sin(2 * np.pi * 53.0 * t), 0, 1)
    y = base * am
    y = normalize(y, "rms", -22.0, ceiling=-3.0)
    return make_seamless(y, loop_s=0.5)

def gen_leak():
    """漏怪/核心受创：低频撞击 + 失真警报。mono。"""
    dur = 0.36
    n = int(dur * SR); t = tt(dur)
    phase = sine_phase(np.linspace(96.0, 50.0, n))
    thump = np.sin(phase) * env_exp(n, 0.09)
    alarm = sat((0.5 * (2 * ((180 * t) % 1) - 1) + 0.5 * sine(181, t)) * 2.6, 1.0) * env_exp(n, 0.13) * 0.5
    y = sat(thump + alarm, 1.3)
    return normalize(y, "rms", -15.0)

def gen_tower_down():
    """塔被摧毁：comb 金属断裂 + 失能 drone（程序化近似，待 CC0 替换）。mono。"""
    dur = 0.65
    n = int(dur * SR); t = tt(dur)
    impact = bp(noise(n), 2200.0, q=0.6) * env_exp(n, 0.028)
    metal = np.zeros(n)
    for i, f in enumerate([137.0, 241.0, 389.0, 517.0, 733.0, 967.0]):
        metal += sine(f, t, ph=rng.uniform(0, 6.28)) * env_exp(n, 0.14 + 0.05 * i) / (i + 1.0)
    drone = np.sin(sine_phase(np.linspace(70.0, 42.0, n))) * env_exp(n, 0.22) * 0.6
    y = sat(impact * 0.85 + metal * 0.55 + drone, 1.25)
    return normalize(y, "rms", -15.0)

def gen_tower_up():
    """塔复活：上升 whoosh + 干净机械 click（青，正面）。mono。"""
    dur = 0.45
    n = int(dur * SR); t = tt(dur)
    a = bp(noise(n), 420.0, q=0.7)
    b = bp(noise(n), 3000.0, q=0.7)
    ramp = np.linspace(0, 1, n)
    whoosh = a * (1 - ramp) ** 1.5 + b * ramp ** 1.5
    env = np.sin(np.pi * ramp) ** 1.0
    click = sine(1850.0, t) * env_exp(n, 0.006) * 0.5
    rise = sine_phase(np.linspace(300.0, 950.0, n))
    y = whoosh * 0.8 * env + click + np.sin(rise) * 0.28 * env
    return normalize(y, "rms", -18.0)

def gen_wave_start(band):
    """波次开始：HP 扫频 riser + 低频 impact。stereo。band∈{0,1,2}=早/中/晚。"""
    dur = [1.5, 2.0, 2.5][band]
    n = int(dur * SR); t = tt(dur)
    fc0, fc1 = [(320, 3200), (260, 4200), (200, 5200)][band]
    lo = bp(noise(n), fc0, q=0.6)
    hi = bp(noise(n), fc1, q=0.6)
    ramp = np.linspace(0, 1, n)
    sweep = (lo * (1 - ramp) + hi * ramp) * (ramp ** 1.5)
    # 末尾 impact（低频 thump）
    imp_start = dur - 0.45
    imp = sine_phase(np.linspace(90.0 - band * 12, 42.0 - band * 8, n))
    imp_amp = np.exp(-np.maximum(t - imp_start, 0.0) * 9.0) * (t >= imp_start)
    impact = np.sin(imp) * imp_amp * 0.9
    y = sweep * 0.55 + impact
    y = sat(y, 1.1) * (0.35 + 0.65 * np.minimum(t / dur, 1.0))
    st = haas(y, 10.0 + band * 4)
    return normalize(st, "lufs", -16.0)

def gen_sting(win):
    """胜负乐句。stereo。win=True 胜利 / False 失败。"""
    dur = 4.0
    n = int(dur * SR); t = tt(dur)
    if win:
        y = np.zeros(n)
        for i, nm in enumerate(["D4", "F4", "A4", "D5", "A4"]):
            f = NOTE[nm]; s = int(i * 0.17 * SR); seg = n - s
            if seg <= 0: break
            ts = np.arange(seg) / SR
            tone = (np.sin(2 * np.pi * f * ts) + 0.3 * np.sin(2 * np.pi * f * 2.01 * ts) + 0.15 * np.sin(2 * np.pi * f * 3.0 * ts))
            y[s:] += tone * np.exp(-ts * 1.8) * 0.45
        y += np.sin(sine_phase(np.full(n, NOTE["D2"]))) * np.exp(-np.maximum(t - 0.8, 0.0) * 0.9) * 0.35
        y = sat(y, 1.05)
    else:
        f = np.linspace(112.0, 36.0, n)
        ph = sine_phase(f)
        y = np.sin(ph) * np.exp(-t * 0.45)
        y += 0.4 * np.sin(ph * 0.5) * np.exp(-t * 0.3)
        y += np.sin(sine_phase(np.full(n, 30.0))) * np.exp(-t * 0.35) * 0.5
        y = sat(y, 1.7)
    st = haas(y, 14.0)
    return normalize(st, "lufs", -16.0)

# ---- 音乐 stem（4 条，均 10.0 s / 可无缝循环 · 统一 RMS 归一以保相对平衡）----
def gen_music_sub_drone():
    n = int(GLEN * SR); t = tt(GLEN)
    y = sine(NOTE["D1"], t) * 0.7 + sine(NOTE["D1"] * 2.0, t) * 0.12 + sine(NOTE["D1"] * 1.003, t) * 0.15
    lfo = 0.72 + 0.28 * np.sin(2 * np.pi * (2.0 / LOOP) * t)  # 2 cyc/loop → seamless
    y = lp(y * lfo, 180.0, order=2, pad=False)
    st = haas(y, 6.0)
    return make_seamless(normalize(st, "rms", -28.5, ceiling=-1.5))

def gen_music_pulse():
    n = int(GLEN * SR); t = tt(GLEN)
    # 持续低频脉动底（保证 RMS 稳定 → 归一不失衡）
    y = sine(NOTE["D2"], t) * 0.22 + sine(NOTE["D1"], t) * 0.10
    k = 0.0
    while k < LOOP - 1e-9:  # 半速脉冲
        s = int(k * SR); seg = min(int(0.16 * SR), n - s)
        if seg > 0:
            ts = np.arange(seg) / SR
            y[s:s + seg] += np.sign(np.sin(2 * np.pi * NOTE["D2"] * ts)) * np.exp(-ts * 26.0) * 0.8
        k += 2 * BEAT
    y = res_lp(y, 520.0, q=3.5, pad=False) * 0.8
    y = compress(y, -14.0, 3.0, 10.0)
    st = haas(y, 4.0)
    return make_seamless(normalize(st, "rms", -28.5, ceiling=-1.5))

def gen_music_harmony_pad():
    n = int(GLEN * SR); t = tt(GLEN)
    y = np.zeros(n)
    for nm in ["D2", "D3", "F3", "A3"]:
        f = NOTE[nm]
        y += (sine(f, t) + 0.5 * sine(f * 1.005, t) + 0.35 * sine(f * 0.996, t)) / 4.0
    lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (1.0 / LOOP) * t)
    y = lp(y * lfo, 900.0, order=2, pad=False)
    st = haas(y, 16.0)
    return make_seamless(normalize(st, "rms", -28.5, ceiling=-1.5))

def gen_music_rhythm():
    n = int(GLEN * SR); t = tt(GLEN)
    # 持续工业 bed（中低频噪声 + 弱 sub）→ stem 有稳定能量，RMS 归一不失衡
    bed = lp(noise(n), 260.0, pad=False) * 0.30
    bed += bp(noise(n), 1300.0, q=0.6, pad=False) * 0.12
    bed += sine(NOTE["D1"] * 2.0, t) * 0.06
    y = bed
    # 8 分 noise hat
    k = 0.0
    while k < LOOP - 1e-9:
        s = int(k * SR); seg = min(int(0.06 * SR), n - s)
        if seg > 0:
            ts = np.arange(seg) / SR
            y[s:s + seg] += bp(rng.standard_normal(seg), 8000.0, q=0.6, pad=False) * np.exp(-ts * 70.0) * 0.45
        k += BEAT / 2.0
    # 拍点 kick（低 thump 体）
    for b in range(0, 16, 2):
        s = int(b * BEAT * SR); seg = min(int(0.16 * SR), n - s)
        if seg > 0:
            ts = np.arange(seg) / SR
            y[s:s + seg] += np.sin(sine_phase(np.linspace(88.0, 44.0, seg))) * np.exp(-ts * 18.0) * 0.85
    # 小节首金属 hit
    for b in range(0, 16, 4):
        s = int(b * BEAT * SR); seg = min(int(0.18 * SR), n - s)
        if seg > 0:
            ts = np.arange(seg) / SR
            hit = sum(sine(f, ts) for f in (196.0, 311.0, 466.0)) / 3.0
            y[s:s + seg] += hit * np.exp(-ts * 20.0) * 0.7
    y = compress(y, -16.0, 4.0, 12.0)
    st = haas(y, 3.0)
    return make_seamless(normalize(st, "rms", -28.5, ceiling=-1.5))

# ===========================================================================
#  生成与落盘
# ===========================================================================
def main():
    manifest = []
    def emit(subdir, name, data, fmt, subtype=None, loop=False, note=""):
        path = os.path.join(ROOT, subdir, name)
        kwargs = {}
        if fmt == "OGG":
            kwargs = dict(format="OGG", subtype=subtype or "VORBIS")
        else:
            kwargs = dict(subtype=subtype or "PCM_24")
        sf.write(path, data.astype(np.float32) if data.ndim == 2 else data.astype(np.float64), SR, **kwargs)
        ch = 2 if data.ndim == 2 else 1
        rec = {
            "file": os.path.relpath(path, ROOT).replace("\\", "/"),
            "format": fmt, "subtype": kwargs.get("subtype"),
            "sr": SR, "channels": ch, "dur_s": round(len(data) / SR, 3),
            "lufs": round(integrated_lufs(data if data.ndim == 1 else data.mean(axis=1)), 2),
            "true_peak_dbtp": round(db(true_peak(data)), 2),
            "loop": bool(loop), "note": note,
        }
        manifest.append(rec)
        print(f"  ✓ {rec['file']:38s} {rec['dur_s']:>6.3f}s {ch}ch LUFS={rec['lufs']:>6.2f} TP={rec['true_peak_dbtp']:>5.2f}")

    print("[ui]")
    for i in range(3):
        emit("ui", f"snd_ui_reroll_{i+1:02d}.wav", gen_ui_reroll(i), "WAV", note="翻牌触感")
    for i in range(5):
        emit("ui", f"snd_ui_buy_{i+1:02d}.wav", gen_ui_buy(i), "WAV", note=f"购买 rarity={i}")

    print("[sfx]")
    for i in range(4):
        emit("sfx", f"snd_combat_kill_{i+1:02d}.wav", gen_kill(i), "WAV", note="击杀变体")
    emit("sfx", "snd_combat_kill_swarm.wav", gen_swarm(), "WAV", loop=True, note="洪流颗粒层(循环)")
    emit("sfx", "snd_combat_leak.wav", gen_leak(), "WAV", note="漏怪/核心受创")
    emit("sfx", "snd_combat_tower_down.wav", gen_tower_down(), "WAV",
         note="程序化近似·待CC0替换")
    emit("sfx", "snd_combat_tower_up.wav", gen_tower_up(), "WAV", note="塔复活(T-E1③:无倒计时)")
    for i, nm in enumerate(["early", "mid", "late"]):
        emit("sfx", f"snd_wave_start_{nm}.wav", gen_wave_start(i), "WAV", note=f"波次riser·{nm}")
    emit("sfx", "snd_sting_victory.wav", gen_sting(True), "WAV", note="胜利乐句")
    emit("sfx", "snd_sting_defeat.wav", gen_sting(False), "WAV", note="失败乐句")

    print("[music]")
    emit("music", "music_sub_drone.ogg", gen_music_sub_drone(), "OGG", loop=True, note="低频地基")
    emit("music", "music_pulse.ogg", gen_music_pulse(), "OGG", loop=True, note="节拍/心跳")
    emit("music", "music_harmony_pad.ogg", gen_music_harmony_pad(), "OGG", loop=True, note="和声/主题点亮")
    emit("music", "music_rhythm.ogg", gen_music_rhythm(), "OGG", loop=True, note="工业节奏件")

    out = os.path.join(ROOT, "_src", "manifest.json")
    with open(out, "w", encoding="utf-8") as fp:
        json.dump({"sr": SR, "bpm": BPM, "loop_s": LOOP, "assets": manifest}, fp, ensure_ascii=False, indent=2)
    print(f"\nmanifest → {out}  ({len(manifest)} assets)")

if __name__ == "__main__":
    main()
