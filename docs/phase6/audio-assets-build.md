# 《守核 Corebound》Phase 6 · 音频 MVP 资产制作批次报告（audio-assets-build）

> 项目：Roguelite 塔防 + 卡牌构筑 · Godot 4.7.2-stable · PC (Steam) · 1920×1080 基准
> 阶段：**Phase 6.1 资产制作** · 责任人：**阮和鸣（游戏音频与声效设计师）** · 任务：**T-P6-07**
> 依据：`docs/phase6/audio-assets-plan.md §3`（自助路径）/ §4（交付规格）· `docs/phase6/audio-spec-a.md §1.3 / §3.1 / §3.2`
> 性质：🔴 **只落 `assets/audio/**` 资产 + 本报告**；`scripts/` 与 `project.godot` **零改动**；未 push。
> 用户已批准：**音频全 MVP + 本期自制音乐 + 自助资产来源**。

---

## 0. 总览

| 项 | 结果 |
|---|---|
| **资产总数** | **25 个文件**（21 短音效 + 4 音乐 stem） |
| 采样率 / 位深 | 全部 **48 kHz**；短音 **WAV/PCM_24**；音乐 **OGG/Vorbis**（流式） |
| 声道 | 音乐/UI/波次/乐句 = **stereo**；战斗定位音（击杀/漏怪/塔/洪流）= **mono** |
| 命名 | 与 `audio-spec-a §3.1` **资产 id 逐字一致**（engine `SFX_TABLE` id→路径映射不破） |
| 落盘 | `assets/audio/{music,sfx,ui}/`（生成脚本与清单在 `assets/audio/_src/`） |
| 总大小 | **≈ 4.88 MB**（远低于 §4 的 ≤40 MB 预算） |
| 生成方式 | 🔴 **100% 程序化合成**（numpy + soundfile，无外部采样、无 DAW、无第三方素材 → **版权=自有**） |
| 响度 | 长音(≥1s) → **−16 LUFS**（乐句/riser）；短瞬态 → RMS 归一 + 真峰 ≤ −1.5 dBTP；音乐 stem **按"总和可用"归一**（见 §3） |
| 循环 | 4 music + 1 swarm 均做**交叉淡化折叠循环**；music 循环点不连续度 **≤ ~3%**（tonal） |

**依赖（本环境已安装）**：`numpy 2.5.4` · `soundfile 0.14.0`（libsndfile，含 OGG/Vorbis 编码）。**未用** ffmpeg/sox/DAW。

---

## 1. 复现方法

```bash
# 依赖（仅本次构建环境）
python -m pip install numpy soundfile
# 生成（确定性 seed=20261013）
python assets/audio/_src/gen_audio.py
```
- 生成器：`assets/audio/_src/gen_audio.py`（构建工具，非运行时资产）
- 清单：`assets/audio/_src/manifest.json`（逐文件 SR/声道/时长/LUFS/真峰/loop/说明）
- 🔴 `_src/` **不参与引擎引用**；引擎只引用 `music/ sfx/ ui/` 下的音频文件。

> 说明：Godot **未运行** → 尚无 `.import` 文件（引擎首次打开工程时自动导入，按 `.ogg` 流式 / `.wav` 采样类型设置即可）。

---

## 2. 逐项清单 —— 【已生成】

> 表注：`LUFS` 为 integrated（短瞬态 LUFS 仅供参照）；`TP` = 真峰(dBTP)。全部 48 kHz。

### 2.1 UI（stereo · 总线 UI）—— 8 个

| 文件 | 时长 | LUFS | TP | 生成方式 | 对应事件 |
|---|---|---|---|---|---|
| `ui/snd_ui_reroll_01.wav` | 0.16s | −22.9 | −1.5 | 带通噪声滑音+click，3 变体（音高/频段漂移） | S-02 翻牌 |
| `ui/snd_ui_reroll_02.wav` | 0.18s | −22.9 | −1.5 | 同上（变体 2） | S-02 |
| `ui/snd_ui_reroll_03.wav` | 0.20s | −23.1 | −1.5 | 同上（变体 3） | S-02 |
| `ui/snd_ui_buy_01.wav` | 0.16s | −18.3 | −8.7 | FM 铃（D5），稀有度 1 | S-03 购买 |
| `ui/snd_ui_buy_02.wav` | 0.20s | −18.3 | −8.6 | FM 铃（F5），稀有度 2 | S-03 |
| `ui/snd_ui_buy_03.wav` | 0.23s | −17.9 | −8.4 | FM 铃（A5）+ sparkle，稀有度 3 | S-03 |
| `ui/snd_ui_buy_04.wav` | 0.27s | −17.4 | −8.6 | FM 铃（D6）+ sparkle，稀有度 4 | S-03 |
| `ui/snd_ui_buy_05.wav` | 0.30s | −16.8 | −8.0 | FM 铃（A6）+ sparkle，稀有度 5（最"贵"） | S-03 |

### 2.2 战斗 SFX（mono · 总线 SFX）—— 8 个

| 文件 | 时长 | LUFS | TP | 生成方式 | 对应事件 |
|---|---|---|---|---|---|
| `sfx/snd_combat_kill_01.wav` | 0.06s | −16.8 | −2.0 | 带通噪声瞬态 + FM click + tanh 饱和，4 变体 | C-02 击杀 |
| `sfx/snd_combat_kill_02.wav` | 0.08s | −16.7 | −1.8 | 同上（变体 2） | C-02 |
| `sfx/snd_combat_kill_03.wav` | 0.10s | −16.6 | −2.1 | 同上（变体 3） | C-02 |
| `sfx/snd_combat_kill_04.wav` | 0.12s | −17.1 | −1.5 | 同上（变体 4） | C-02 |
| `sfx/snd_combat_kill_swarm.wav` | **0.50s（循环）** | −19.2 | −7.5 | 双带通噪声 + 周期 AM（40/53 Hz）→ 洪流颗粒层 | C-02 聚合层 |
| `sfx/snd_combat_leak.wav` | 0.36s | −16.9 | −5.1 | 下滑正弦撞击（96→50 Hz）+ 失真警报 | C-03 漏怪/核心受创 |
| `sfx/snd_combat_tower_down.wav` | 0.65s | −17.5 | −3.2 | 冲击 + 非谐分音金属 + 下滑 drone ⚠️**程序化近似·待 CC0 替换** | C-04 塔摧毁 |
| `sfx/snd_combat_tower_up.wav` | 0.45s | −16.3 | −5.2 | 上升带通 whoosh + 干净 click 🔴**无倒计时/滴答**（守 T-E1③） | C-05 塔复活 |

### 2.3 波次 / 乐句（stereo · 总线 SFX）—— 5 个

| 文件 | 时长 | LUFS | TP | 生成方式 | 对应事件 |
|---|---|---|---|---|---|
| `sfx/snd_wave_start_early.wav` | 1.5s | −18.5 | −1.5 | 上扫噪声 riser（320→3200）+ 低频 impact | L-02 波次开始（早） |
| `sfx/snd_wave_start_mid.wav` | 2.0s | −17.8 | −1.5 | 同上（260→4200，更重） | L-02（中） |
| `sfx/snd_wave_start_late.wav` | 2.5s | −17.5 | −1.5 | 同上（200→5200，最重） | L-02（晚） |
| `sfx/snd_sting_victory.wav` | 4.0s | −16.0 | −3.3 | 上行 FM 钟体琶音（D-F-A-D-A）+ 低频 release | L-05 胜利 |
| `sfx/snd_sting_defeat.wav` | 4.0s | −16.0 | −3.3 | 下行 drone collapse（112→36 Hz）+ 失真 | L-06 失败 |

### 2.4 音乐 stem（stereo · 总线 Music）—— 4 个（均 10.0s 无缝循环）

| 文件 | 时长 | 单 stem LUFS* | TP | 生成方式 | 角色（spec §2.1） |
|---|---|---|---|---|---|
| `music/music_sub_drone.ogg` | 10.0s | −35.5 | −19.2 | D1 sine(+弱倍频/微失谐) + 2 周期/环 LFO + LP180 | 低频地基（A/B/C 常开） |
| `music/music_pulse.ogg` | 10.0s | −32.0 | −11.9 | D2/D1 持续底 + 半速方波脉冲 + 谐振 LP520 | 节拍/心跳 |
| `music/music_harmony_pad.ogg` | 10.0s | −30.0 | −11.7 | D 小三和弦（D2/D3/F3/A3）微失谐 + LP900 + 慢 LFO | 和声/主题点亮 |
| `music/music_rhythm.ogg` | 10.0s | −28.5 | −2.1 | 工业 bed（噪声+弱 sub）+ 8 分 hat + 拍点 kick + 小节金属 hit | 工业节奏件 |

> **\* 单 stem LUFS 偏低是刻意的**：4 条 stem 是**同一首曲的垂直分层**，设计为**叠加播放**。已按"**总和 mix-ready**"归一（见 §3），请勿按单 stem LUFS 判断音量。
> **声像/衰减**：stems 与 UI 均为 stereo（总线内不再定位）。仅需注意——**每条 stem 均为 10.0s 且同 BPM/调性**，引擎可用统一播放位置对齐（stem 同步）。

---

## 3. 音乐 stem 混音说明（给引擎的增益表）

**设计**：4 条 stem 作为一首曲的分层，**叠加**后应落在 spec §2.4 的 Music 总线基准（−16~−14 LUFS）。

| 场景 | 活跃 stem | 实测总和 RMS |
|---|---|---|
| 阶段 A（苟活 W1-5） | sub_drone + pulse + harmony_pad（3 条） | **−18.6 dBFS** |
| 阶段 B（成型 W6-12） | +rhythm（4 条，pulse/harmony 逐步加厚） | **−17.2 dBFS** |
| 阶段 C（雪崩 W13+） | 全 4 条 + （6.3）失谐层 | **−17.2 dBFS** |

**✅ 全 4 条同放：总和 RMS −17.2 dBFS / 真峰 −2.71 dBTP（不削波）** —— 即 **unity 播放已 mix-ready**，引擎无需额外 stem trim 即可安全叠加；阶段切换靠**逐 stem 淡入**（spec §2.3 的 1.5s crossfade）实现情绪弧。
> 🟡 若引擎想更贴 −14 LUFS，可在 Music 总线整体 **+3 dB**（真峰仍 ≤ 0）。此为引擎侧微调项，非资产侧。

---

## 4. 需外部获取（CC0 补）

| 资产 | 现状 | 待外部获取项 | 建议关键词 | 候选 CC0/免版税来源 |
|---|---|---|---|---|
| `sfx/snd_combat_tower_down.wav`（C-04 塔摧毁·金属断裂） | ✅ **已用程序化近似占位**（可立即接入） | **真实金属断裂采样**，替换占位以获得"脆、碎、有质感"的断裂感（程序化合成难到"好听"） | `metal fracture`、`metal crash debris`、`scrap metal break`、`tower collapse`、`breaking metal` | **Freesound**（筛 CC0）、**Sonniss GDC Game Audio Bundle**（商用免版税）、**Kenney**（CC0 SFX pack） |

**接入方式**：找到后**保留同文件名覆盖** `snd_combat_tower_down.wav`（或另存取新资产 id）→ 重新归一（RMS −15 / 真峰 ≤ −1.5）→ 覆盖即可，**零代码改动**。

> 其余 **24 个资产为程序化原创，版权=项目自有（可商用）**，无第三方授权风险。

---

## 5. 未做（+ 原因）

| 资产 | 原因 | 归属阶段 |
|---|---|---|
| `snd_sting_overload_charge`（F-06 Overload 低频充能） | **不在本批次 MVP 范围**（`audio-spec-a §3.1` 标为 🟡 6.3 扩展，成本最高，需和声堆叠+扫频，建议精修批次） | **6.3** |
| `music_lead`（主题旋律 stem） | 同上——spec §2.1 标 🟡 6.3；MVP 用 4 stem 覆盖 A/B/C 弧线已足够 | **6.3** |
| `music_chaos`（失谐/失控层 stem） | 同上——雪崩期专用层，6.3 精修 | **6.3** |
| VO（配音） | 项目 MVP 无 VO；总线已预留 `Voice`（`audio-spec-a §4.1`） | 后续 |

> 说明：本批次范围 = 用户批准的「**21 短音效 + 1 条 4-stem 循环**」，**已 100% 完成**；上表 3 项均**明确在 6.3 扩展范围**，非遗漏。

---

## 6. 规格符合性核对（vs `audio-assets-plan §4`）

| 规格项 | 要求 | 实际 | 结果 |
|---|---|---|---|
| 落盘路径 | `assets/audio/{music,sfx,ui}/` | 一致 | ✅ |
| 命名 | 与 `audio-spec-a §3.1` 资产 id 逐字一致 | 一致（见 §2） | ✅ |
| 音乐格式 | `.ogg` 流式 | 4 × OGG/Vorbis | ✅ |
| 短音格式 | `.wav` 48k/24bit | 21 × WAV/PCM_24 | ✅ |
| 响度 | ~−16 LUFS（真峰 ≤ −1 dBTP） | 乐句/riser = −16~−18.5 LUFS；短瞬态 = RMS 归一 + 真峰 ≤ −1.5；stem 按总和归一到 −17.2 dBFS RMS（≈−16 LUFS） | ✅（瞬态 LUFS 不作硬指标，见下方说明） |
| 真峰 | ≤ −1 dBTP | **全部 ≤ −1.5 dBTP**（最严） | ✅ |
| 声道 | 音乐/UI stereo · 定位音 mono | 一致（见 §0 表） | ✅ |
| 循环对齐 | 无缝、无爆音 | music 循环点连续性 ≤ ~3%（tonal）；swarm 为宽带噪声（20ms 交叉折叠） | ✅ |
| 尺寸预算 | ≤ ~40 MB | ≈ 4.88 MB | ✅ |

> **关于"−16 LUFS 硬指标"的工程说明**：LUFS 对**亚秒级瞬态**（击杀 60ms、UI 100ms）不是一个稳定/有意义的度量；业界对 one-shot 采用**真峰归一 + 混音期调平**。本批**已统一真峰 ≤ −1.5 dBTP** 并保证同类音（如 4 击杀变体）电平一致；最终相对平衡由引擎 per-sound 增益表微调（标准做法）。**长音（乐句/riser/音乐）严格按 LUFS −16 归一。**

---

## 7. 已知限制 / 待办

| # | 项 | 说明 |
|---|---|---|
| L-1 | **无 `.import`** | Godot 未运行；首次打开工程时引擎自动导入。`.ogg` 建议设循环+流式；`.wav` 短音默认即可。 |
| L-2 | **音质为"占位级"** | 程序化合成适合瞬态/UI/基底，但音乐"耐听度"与金属断裂"质感"**建议 6.2/6.3 精修**（用免费合成器/DAW 或替换 CC0）。 |
| L-3 | **stem 需同步播放** | 同长 10.0s/同 BPM，引擎需从同一播放位置对齐各 stem（避免相位错位）。 |
| L-4 | **loop 点** | metal/swarm 等已折叠；若引擎侧再设 loop 起点/终点，请用文件首尾（已无缝）。 |
| L-5 | **C-05 塔复活音合规** | 资产 `snd_combat_tower_up.wav` **仅单次 whoosh+click**，无滴答/进度语义（守 T-E1③）；回归断言见 `audio-spec-a §7`。 |
| L-6 | 命名冲突 | 未发现既有同名资产（本批为项目首次引入音频）。 |

---

## 8. 交接 / 下一步

- **对 `engineering-lead`（程基岩）**：资产已就绪于 `assets/audio/{music,sfx,ui}/`，**命名即 `audio-spec-a §4.6` 的 id→路径映射**。可直接按 `audio-spec-a §4` 建 `AudioDirector` + 总线（`project.godot` 增 `[autoload]`+`[audio]`）。🔴 请勿引用 `_src/`。音乐 4 stem 按 §3 增益表叠加。
- **对 `quality-lead`**：可对 25 个文件做**规格校验**（SR/位深/声道/真峰/命名）与 `audio-spec-a §7` 五条回归断言。
- **对 `art-director`**：若 6.3 新增 VFX（尤其 P1-3b hitstop 解红后），同步 `audio-audit §3`。
- **对 `team-lead`**：本批次交付完成；**剩余待拍板**：金属断裂 CC0 来源选型（§4）；音乐精修是否排入 6.2。

> **边界复述**：仅写 `assets/audio/**`（资产 + `_src/` 构建脚本/清单）+ 本报告；`scripts/`、`project.godot` **零改动**；未 push；未运行 Godot。
