# 《守核 Corebound》Phase 6 · 基调 A 可执行音频规格（audio-spec-a）

> 项目：Roguelite 塔防 + 卡牌构筑 · Godot 4.7.2-stable · PC (Steam) · 1920×1080 基准
> 阶段：**Phase 6.1** · 责任人：**阮和鸣（游戏音频与声效设计师）** · 任务：**T-P6-05**
> **用户已拍板**：音乐基调 = **A · 暗黑机械电子**；**启动音频批次**。
> 性质：**落地规格文档**。不写代码、不引入资产、不改玩法、不 push（工程实现待本规格 + 用户资产选型后由程基岩执行）。
> 上游：`docs/phase6/audio-audit.md`（方向/事件表/架构 §2–§6）、`design/art/art-bible.md`（§2.2 配色 / §8 反馈 / §8.4 超载）、`design/concept/game-concept.md`（P2/P4 · §2.2 心流三阶段）

---

## 0. 范围与边界

| 项 | 内容 |
|---|---|
| **本文解决** | 基调 A 的**可执行规格**：音色词典 → 三层音乐 stem 编制 → MVP 7 音效**实现级参数** → `AudioDirector` **接口清单**（工程照做）→ 两坑/R-d 处理 |
| **本文不解决** | 资产**制作与获取**（→ `audio-assets-plan.md`）、代码实现（→ 程基岩）、资产文件本身（另立批次） |
| **ID 口径** | 事件 ID（L/C/S/W/F）以 `audio-audit.md` §3 表为准。⚠️ audit §2.3 正文曾用「F-05」指协同成立，**以 §3 表为准 = `F-02`**，本规格统一用 **F-02**。 |
| **参数性质** | 本文所有数值为**可执行的推荐基线**（工程可直接照做），非不可变常量；标注 `🟡 可调` 的参数允许工程/试玩阶段微调。 |

---

## 1. 基调 A 定义 —— 暗黑机械电子（Dark Mechanical Electronic）

### 1.1 一句话

> **「冰冷的工业机器在低鸣，玩家的构筑越强，它越失控、越低频轰鸣、越失真。」**

与 `audio-audit §2.1` 听觉身份「冷静的青色精密机械 → 失控成橙色的咆哮」的关系：**基调 A 是把该身份落成"可制作"的音乐语言**——青色机 = 干净合成器脉冲/钟体；橙色咆哮 = 工业失真/低频 drone。

### 1.2 参考板（借什么 / 不借什么）

| 参考 | 借 | 不借 |
|---|---|---|
| **Blade Runner 2049（Zimmer/Wallfisch）** | 极低频 drone、空旷、压抑的空间感 | 过长的影视化铺陈 |
| **FTL: Faster Than Light（B. Prunty）** | 极简合成器脉冲、克制的循环、冷色调 | 其过于"宅"的音色库 |
| **Into the Breach（Ben Prunty）** | 冷静的机械节拍、信息化的干净音 | 循环过短易腻 |
| **SIGNALIS** | 工业暗氛围、失真、机械恐怖感（**敌人侧**） | 全曲性偏暗（本作需留"青色"对比） |
| **Lorn / 工业电子** | 低频扭曲 bass、失谐、噪声纹理（**雪崩期**） | 绝对的嘈杂（会盖 SFX） |
| **Doom (2016)** | 战斗"打击"的失真冲击感 | 金属吉他驱动（不属于基调 A） |

> 一句话：**玩家侧 = FTL/Into the Breach 的干净合成器；敌人/雪崩侧 = SIGNALIS/Lorn 的工业失真。** 二者在基调 A 里共存、彼此消长。

### 1.3 音色词典（合成器 / 失真 / 滤波 / 调制 / 空间）

| 类别 | 选用 | 用途（对应事件/阶段） |
|---|---|---|
| **减法合成（analog-modeled，锯齿/方波）** | 主合成器 | 本体：pulse / drone / 敌人感 bass |
| **FM 合成（DX 式）** | 钟体/金属体 | **玩家侧**音色：购买铃声、塔复活重启音、主题 lead |
| **Wavetable 合成** | 纹理层 | pad / 和声情绪 |
| **颗粒合成（granular）** | 颗粒/星屑 | 虚空主题层（§2.2）、击杀聚合"洪流"层 |
| **Sub-bass（sine/triangle）** | 纯低频 | sub_drone / 心跳 / 失败下行 |
| **失真：磁带饱和（tape saturation）** | 暖/脏 | 全局 glue、雪崩期"变响" |
| **失真：管驱（tube drive）** | 谐波加厚 | 敌人、冲击、失败 |
| **失真：位压碎（bitcrush）** | 数字故障感 | 失谐层、超载、Sapper 锁定 |
| **滤波：谐振低通（resonant LPF）** | 酸味/聚焦 | 商店开门"聚焦"滤波（§5）、pulse 塑形 |
| **滤波：高通扫频（HP sweep）** | riser/上扬 | 波次开始（L-02）、充能（F-06） |
| **滤波：梳状（comb）** | 金属共鸣 | 塔摧毁断裂（C-04）、机械音 |
| **调制：LFO / 包络** | 呼吸/脉动 | drone 与 pad 的缓慢起伏 |
| **调制：侧链压缩（sidechain）** | 泵动 | 音乐与 pulse 的呼吸感、Overload duck（§2.3） |
| **空间：卷积混响（工业大厅/短房间）** | 定位感 | SFX 空间；音乐走短混响防糊 |
| **空间：延迟（ping-pong）** | 机械纵深 | arp / lead 的机械序列感 |

**调性 / 音高基调**：**D 小调（Aeolian）**为核心；根音 **D1 ≈ 36.7 Hz**（sub 基频），威胁时刻引入 **♭2（E♭）**制造 Phrygian 式不安（敌人侧）。

---

## 2. 音乐规格（三层情绪弧 · 垂直分层 + 水平过渡）

### 2.1 Stem 矩阵（6 stem 设计 · MVP 落地前 4 条）

> 同一段和声/节奏素材拆成 stem，按游戏状态**实时增删层**（垂直分层）。MVP 先做 4 条（覆盖 A/B/C 弧线），后 2 条（lead/chaos）留 6.2/6.3。

| # | Stem 名（建议） | 合成 | 角色 | A 苟活 | B 成型 | C 雪崩 | MVP |
|---|---|---|---|---|---|---|---|
| 1 | `music_sub_drone` | Sub sine + tape sat | 地基低频 drone（36–80 Hz） | ✅ 缓慢心跳（0.5 Hz 脉动） | ✅ 略强 | ✅ 连续轰鸣 | **✅** |
| 2 | `music_pulse` | 减法（方波+resonant LPF） | 节拍/心跳脉冲（中枢节奏） | ✅ 半速（half-time） | ✅ 直拍 | ✅ 直拍 + 加密 | **✅** |
| 3 | `music_harmony_pad` | Wavetable + 短混响 | 和声层（承担"主题点亮"） | ✅ 单音悬念和弦 | ✅ 转三和弦 + 主题动机（**F-02 相变**） | ✅ 加厚 + 叠层 | **✅** |
| 4 | `music_rhythm` | 工业打击（噪声 hat + 金属 hit） | 节奏驱动件 | ⬜ 关 | ✅ 轻件进入 | ✅ 全开驱动 | **✅** |
| 5 | `music_lead` | FM 钟体/lead | 主题旋律 | ⬜ 关 | ✅ 首次进入（相变） | ✅ 失谐/叠八度 | 🟡 6.3 |
| 6 | `music_chaos` | bitcrush 噪声 + 失谐 unison | 失控/失谐层 | ⬜ 关 | ⬜ 关 | ✅ 抬升 | 🟡 6.3 |

### 2.2 三阶段编配表

| 参数 | **A 苟活期（W1–5）** | **B 成型期（W6–12）** | **C 雪崩期（W13+）** |
|---|---|---|---|
| 主导情感 | 紧张·脆弱·期待 | 顿悟·掌控·焦灼 | 狂喜·主宰·观赏 |
| 活跃 stem | 1,2,3 | 1,2,3,4（+ lead 于相变后） | 全 6 |
| BPM | **96**（pulse 半速感 ≈ 48 拍点） | **96** | **96**（rhythm 可双倍 hat） |
| 调性 | D Aeolian | D Aeolian | D Aeolian + ♭2 点缀 |
| 动态（integrated） | **−18 LUFS** 🟡 | **−15 LUFS** 🟡 | **−12 LUFS** 🟡 |
| 峰值（true peak） | ≤ −6 dBTP | ≤ −3 dBTP | ≤ −1 dBTP |
| `AudioScale`（驱动参数） | ≈ 0.2 | ≈ 0.5 | ≈ 1.0 |
| 节奏密度 | 低（留白） | 中 | 高（洪流） |
| 混响 | 短房间（防糊） | 短-中 | 短（大量层叠下必须克制） |

> ✅ **单一循环可行性**：三阶段同为 **BPM 96 / D 小调**，靠 stem 增删 + `AudioScale` 调制完成弧线 → **1 条循环即可覆盖 A/B/C**（`audio-audit §5` 的"4-stem 循环"）。

### 2.3 过渡与动态规则

| 规则 | 触发 | 实现 |
|---|---|---|
| **垂直增删** | 阶段推进（A→B→C）／`AudioScale` 变化 | 各 stem 单独 `volume_db` 包络，**1–2 小节 crossfade**（🟡 建议 1.5 s）；禁硬切 |
| **主题点亮（相变）** | **F-02 首次 Tag 协同成立**（派生） | `harmony_pad` 由单音→三和弦 + **`lead` 首次进入**；建议配一次**短暂挂留解决**（ritardando 感） |
| **水平换装** | 波次区间（art-bible §2.4：晨雾/黄昏/血夜/虚空） | 共享 96 BPM 网格上切换**音色/附加层**（暖音色→低频轰鸣→高频星屑颗粒），**3 s 缓动**（对齐 art-bible §2.4） |
| **精英 / Boss 插段** | `snapshot()["is_elite_wave"]` / 波次预告 | 常规音乐 **duck −4 dB** 0.3 s + 插入**一次性精英动机**（水平过渡），结束回弹 |
| **Overload / 起飞（F-06）** | 单秒击杀/连击/单帧伤害达阈值（art-bible §8.4） | **低频上升扫频充能（0.4 s）** + Music/SFX **侧链 duck −6~−9 dB**（0.15 s 上升 / 0.5 s 回落）；🔴 **冷却 ≥ 6 s、上限 8 s**（与 art-bible §8.4 严格一致） |
| **胜负落点** | `run_won` / `run_lost` | **独占 stinger**：duck 全部总线 → 播乐句；胜利=上行解决 + 低频 release；失败=下行 drone collapse + 失真 |

### 2.4 混音定位

- **总线**（`audio-audit §4.2`）：`Master → Music / SFX / UI / Voice`。
- **Music 总线**在 **250–500 Hz 做 −2~−3 dB 挖坑**，让战斗 SFX / 未来 VO 透出（`audio-audit §2.4③` 防糊）。
- **响度基准**：Music 参考 −16~−14 LUFS（比 SFX 低，避免抢戏）；播放中按 A/B/C 上表微调。🟡 可调。

---

## 3. 事件 → 音效实现级参数（MVP 7 条）

> 对应 `audio-audit §5` 的 7 个核心 + 1 扩展。**优先级 P0 必播 / P1 重要 / P2 增强**（可被抢占）。**总线**决定频段与 duck 归属。

### 3.1 参数总表

| # | MV | 事件 ID | 建议资产 id | 音色/合成 | 时长 | 变体 | 优先级 | 总线 | 衰减/声像 | 节流 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ✅ | **C-02** 击杀 | `snd_combat_kill_01..04` + `snd_combat_kill_swarm` | 噪声瞬态 + FM click（橙，金属碎屑） | 60–120 ms（个体）/ 循环 0.5–1 s（洪流层） | **4** + 1 洪流层 | **P0**（个体）/ P2（洪流层） | SFX | 全局（🎯 **MVP 无定位声像**，见 §6 G-1） | 🔴 击杀聚合器（§3.2） |
| 2 | ✅ | **S-02/S-03** 翻牌·购买 | `snd_ui_reroll_01..03` + `snd_ui_buy_01..05` | 翻牌=滤波噪声滑音+click；购买=FM 铃（MVP 按轮转） | 100–250 ms | reroll **3** / buy **5**（🏷️ **按 id 轮转**，非稀有度；见 §6 G-2） | **P0** | **UI** | 全局（不定位） | 无（玩家主动，频率天然受限） |
| 3 | ✅ | **C-03** 漏怪·核心受创 | `snd_combat_leak` | 低频撞击 + 失真警报（红系） | 250–400 ms | **1**（🟡 可 2） | **P0** | SFX | 全局（🟡 可定位至核心） | 每次漏怪（漏怪频率低，无需节流） |
| 4 | ✅ | **L-02** 波次开始 | `snd_wave_start_early/mid/late` | HP 扫频 riser + 低频 impact + 主题动机 hint | 1.5–2.5 s | **3**（按 w 分段） | **P0** | SFX | 全局 | 每波一次 |
| 5 | ✅ | **C-04** 塔被摧毁 | `snd_combat_tower_down` | 金属断裂（comb+噪声）+ 低沉失能 drone | 400–700 ms | **1** | **P0** | SFX | 全局（🟡 可定位至 slot） | 每塔一次（低密度） |
| 6 | ✅ | **C-05** 塔复活 | `snd_combat_tower_up` | 上升"重启"whoosh + 干净机械 click（青，正面） | 300–500 ms | **1** | **P0** | SFX | 全局 | 🔴 **T-E1③**：单次重启，**禁倒计时/滴答/进度音** |
| 7 | ✅ | **L-05/L-06** 胜负 | `snd_sting_victory` / `snd_sting_defeat` | 胜=上行 FM 乐句；败=下行 drone collapse + 失真 | 3–5 s | **1 / 1** | **P0**（独占） | Music/SFX | 全局 | 局末一次 |
| 8 | 🟡 6.3 | **F-06** Overload 充能 | `snd_sting_overload_charge` | HP 上升扫频 + 和声堆叠 + 低频 impact | 0.4 s 涌入 + ≤8 s 持续 | 1（+ 连击重音） | **P0** | SFX | 全局 | 🔴 冷却 ≥6 s / 上限 8 s |

### 3.2 逐条实现明细（工程关键参数）

**① 击杀（C-02）—— 全项目最关键的高密度音**
- 合成：`噪声瞬态（HP/LP 整形）` + `FM click（金属）`，短衰减（60–120 ms）。
- **变体**：4 个样本，播放时 `pitch_randomize = ±2 半音`，防机械重复。
- **3 档强度**（`AudioScale`）：轻（早期）= 高频短脆；中 = +低频体；重（后期）= +失真 +混响尾。
- 🎯 **MVP 无定位声像**（as-built G-1）：击杀走非定位 1D 池，**不做屏幕 x 声像**；对分层/过渡可感知性的影响裁定见 **§7.2**。
- 🔴 **击杀聚合器**（`AudioDirector._on_kill`）：
  - 滑动窗口计 `kill/s`；`< 10 kill/s` → 逐只播（**并发 ≤ 8**，超出丢弃最低优先级）。
  - `≥ 10 kill/s` → 停个体音，转 **`snd_combat_kill_swarm` 循环颗粒层**（`volume_db` 随 `kill/s` 抬升）+ 每 N 杀一次**爆点变体**。
  - 语义：听觉从"噼啪"→"洪流"，**天然映射 P2 雪崩**。
- 内存 ≈ 5 样本 × ~30 KB ≈ 150 KB。

**② 翻牌 / 购买（S-02/S-03）—— P4 手感核心**
- 🔴 **"成交"判定**：必须订阅 `ShopController.shop_changed` 并 **diff 快照**（`scrap` 下降 = 购买；卡片列表变 = 刷新），**不可**用 `reroll/buy_requested`（那是先于校验的"意图"信号）。
- 翻牌：**滤波噪声滑音 + click**（"卡片飞过"的纸张/金属感，对齐 art-bible「卡牌飞向牌组带金色拖尾」）；3 循环变体防腻。
- 购买：**FM 铃**，5 档升调/加谐波（越稀有越"贵"，对齐 art-bible §2.3 稀有度色阶 + §8.1 L3）。🔴 **MVP as-built**：稀有度**未接**（`shop` 快照未暴露 `rarity`），暂按 **`_buy_seq % 5` 轮转**（G-2）；影响裁定见 **§7.3**。
- 总线 = **UI**（恒清晰，永不被战斗淹没）。

**③ 漏怪 / 核心受创（C-03）**
- 低频撞击 + 失真警报；与 art-bible「基地血条该段闪红碎裂」同步。
- 核心低血时叠加 **W-02 心跳层**（后续批次）。

**④ 波次开始（L-02）**
- HP 扫频 riser（1.2 s）→ 低频 impact；按 w 分 **早/中/晚** 三变体（音色随阶段变暗/变重）。
- 与 art-bible「WAVE N 大字由大缩小落下 + 边缘光扫过」**同步对齐 1.2 s**。

**⑤ 塔被摧毁（C-04）**
- comb 滤波金属断裂 + 失能 drone；反制窗口的**关键负反馈**（新机制，玩家必须"听见"塔倒下）。

**⑥ 塔复活（C-05）**
- 上升 whoosh + 干净 click（青系，正面情感）。
- 🔴 **T-E1③ 红线**：`tower_revived` 是**单向通知**，渲染层不得据此画倒计时（`wave_director.gd:84-91`）。**音频同纪律**：只播"重启"一声，**无滴答/进度/节拍**。

**⑦ 胜负（L-05/L-06）**
- **独占** stinger：先 duck 全部总线，再播乐句（3–5 s）；结束后交由 `result_overlay`。

### 3.3 VFX 契约对齐（据 `docs/phase6/vfx-contract-feasibility.md` · art-director T-P6-05 #28）

> 与本批 VFX 契约核对后的**确定性结论**——直接决定 C-02 击杀音的取数方式：

| 结论 | 对音频的影响 |
|---|---|
| **P1-1 投射物：不需要 `projectiles` 字段**（玩法是 hitscan 瞬时聚合 `wave_sim.gd:92-103`，无"哪一炮→命中谁"因果链，加字段也无源可派生） | 与本报告**无关**——§3 从未依赖该字段。**零改动**。 |
| **C-02 击杀音取数：`monster_killed(m)` 信号直携 `Monster` 对象**（`wave_director.gd:82/383`），此刻可直读 `m.pos(v0_)` / `m.hp_max` / `m.index` | 🎯 **取数方案已就绪且最简**：命中音直接订阅既有信号即可，**连 snapshot `index` 键都不需要**。 |
| **P1-2 伤害数字：唯一增量 = snapshot 加 1 行只读键 `"index": int(m.index)`**（供逐怪 `Δhp` 帧间差分） | 🟡 **可选依赖**——仅当音频要做"逐怪伤害量 → 命中音强度分级"时才需要。 |
| **P1-3b 精英 hitstop：触碰「`Engine.time_scale` 唯一写入者」架构红线 → 本轮不做，需单独 ADR** | 🔴 **hitstop 音效挂起**——本报告**不为它设计**任何音效（等 ADR 定论）。 |

> 🎯 **推荐取数策略（解耦）**：**C-02 命中音按"存在即有音"实现**（订阅 `monster_killed(m)`，强度档由 `AudioScale` / 波次驱动），**不依赖逐怪 `Δhp`**——与伤害数字**解耦**，避免被 `index` 键的排期卡住。若后续确需"伤害量分级命中音"，再引入 `index` 键做差分（该键与伤害数字同源）。
> ✅ **对本规格的影响**：§3.1 参数表（C-02）与 §4.3 订阅点（`monster_killed` → `_on_kill`）**均无需改动**——现有口径本就正确。

---

## 4. `AudioDirector` 接口清单（工程可直接照做）

> 本节是**给程基岩的实现契约**。🔴 `AudioDirector` = **表现层只读订阅者**：不 `emit` 任何 gameplay 信号、不写玩法状态（对齐 `control-manifest §5`）。

### 4.1 autoload 与总线常量

```
# project.godot
[autoload]
AudioDirector="*res://scripts/audio/audio_director.gd"

[audio]
buses/default_bus_layout="res://default_bus_layout.tres"
```
> 🔴 **as-built（T-P6-07 采纳）**：实现落 `res://scripts/audio/audio_director.gd`（本仓**无 `autoload/` 目录**；`scripts/**` 是全仓唯一脚本布局）。

```gdscript
# res://scripts/audio/audio_director.gd —— 骨架签名
extends Node
# 🔴 process_mode = ALWAYS（解 §5 的 paused 静音坑）
const BUS_MASTER := "Master"
const BUS_MUSIC  := "Music"
const BUS_SFX    := "SFX"
const BUS_UI     := "UI"
const BUS_VOICE  := "Voice"

const POOL_SIZE     := 24   # 非定位 AudioStreamPlayer
const POOL_SIZE_2D  := 4    # 定位 AudioStreamPlayer2D
const POLL_HZ       := 10   # 派生轮询频率
const KILL_VOICE_CAP := 8   # 击杀个体音并发上限
const SWARM_THRESHOLD := 10.0  # kill/s：超过转洪流层
```

### 4.2 公开方法签名

```gdscript
# ---- 接线（开局一次性）----
func bind(wave_director: Node, time_director: Node, shop_controller: Node) -> void

# ---- 播放（核心 API）----
func play_sfx(id: StringName, opts := {}) -> void
#   opts 可含：priority:int(0..2)· volume_db:float· pitch:float· pitch_jitter:float
#              pan:float(-1..1)· position:Vector2(定位)· bus:String

# ---- 音乐 ----
func set_music_stage(stage: int) -> void       # 0=A 1=B 2=C
func set_music_theme(theme: int) -> void       # 0=晨雾 1=黄昏 2=血夜 3=虚空
func play_stinger(id: StringName) -> void       # elite/victory/defeat/takeoff/overload

# ---- 混音 ----
func duck(bus: String, db: float, attack: float, release: float) -> void
func set_focus_filter(amount: float) -> void     # 商店开门低通 0..1（代替 pitch-bend）
func set_bus_volume_db(bus: String, db: float) -> void
func set_master_mute(muted: bool) -> void

# ---- 参数驱动 ----
func set_audio_scale(s: float) -> void           # JuiceScale → AudioScale（0..1）

# ---- 高密度聚合 ----
func notify_kill(strength: float) -> void        # 由 _on_kill 调用
```

### 4.3 订阅点清单（signal → handler）

**只连既有节点，零新信号：**

| 来源节点 | 既有信号 | handler | 触发事件 |
|---|---|---|---|
| `TimeDirector` | `wave_started(w)` | `_on_wave_started` | L-01/L-02（w==1 判开局） |
| `TimeDirector` | `wave_ended(w)` | `_on_wave_ended` | L-04 + 进安全窗 |
| `TimeDirector` | `drawer_mode_changed(mode)` | `_on_drawer` | S-01（开/关） |
| `TimeDirector` | `budget_drained()` | `_on_budget_drained` | S-12 |
| `TimeDirector` | `placement_confirmed(slot)` | `_on_placement_confirmed` | S-06 |
| `TimeDirector` | `placement_cancelled()` | `_on_placement_cancelled` | S-07 |
| `TimeDirector` | `tower_select_requested(slot)` | `_on_tower_select` | S-11 |
| `WaveDirector` | `wave_result(w, res)` | `_on_wave_result` | L-03（结算音） |
| `WaveDirector` | `monster_spawned(m)` | `_on_spawn` | C-01（聚合 0.15 s） |
| `WaveDirector` | `monster_killed(m)` | `_on_kill` | C-02（→ `notify_kill`） |
| `WaveDirector` | `monster_leaked(m)` | `_on_leak` | C-03 |
| `WaveDirector` | `tower_destroyed(slot)` | `_on_tower_destroyed` | C-04 |
| `WaveDirector` | `tower_revived(slot)` | `_on_tower_revived` | C-05（守 T-E1③） |
| `WaveDirector` | `run_won(w)` | `_on_win` | L-05 |
| `WaveDirector` | `run_lost(w)` | `_on_lose` | L-06 |
| `ShopController` | `shop_changed()` | `_on_shop_changed` | S-02/S-03/S-05（**diff 快照**判成交类型） |
| `ShopController` | `run_changed()` | `_on_run_changed` | S-08/S-09/S-10（diff：塔数/积分变化） |

> 🔴 **弹窗信号不可直连**：`salvage_confirm_dialog` / `disabled_tower_dialog` 由 `shop_controller.gd` 在运行时 `.new()` 生成、**未暴露引用** → `AudioDirector` 无法稳定订阅其 `confirmed` / `tower_repair_requested`。故 S-08/S-09/S-10 **一律走 `shop_changed` / `run_changed` 的 diff 派生**（只读，🈚新信号）。
> 🔴 **`reroll/buy/lock_requested` 不用**：它们是先于校验的意图信号（`time_director.gd:193-204`）→ 会误报"买不起也响成功音"。

### 4.4 派生轮询器（~10 Hz，只读）

```gdscript
func _poll() -> void:   # 每 0.1s（用 max(0.1, delta) 夹住，防失焦跳变刷爆）
    var wd := _wave_director.snapshot()      # 只读
    var w  := int(wd.get("w", 0))
    #  阶段：A(W1-5)/B(W6-12)/C(W13+) → set_music_stage
    #  F-02 协同成立（diff 构筑态）→ play_stinger("takeoff") + harmony_pad 相变点亮（lead 属 6.3）
    #  F-03 起飞（wd["dps"] 跨里程碑）→ stinger
    #  W-01 next_is_elite_wave → 预告音
    #  W-02 core_hp/core_hp_max 比例 → 心跳层频率
    #  F-06 单秒击杀/连击/单帧伤害 → overload（含冷却≥6s/上限8s 守卫）
    #  W-03 min(monsters[*].t_remain) → 环境紧张层
```

### 4.5 池 / 优先级抢占规则

```
请求 play_sfx(id, opts):
  p = opts.priority (默认按 id 表)
  inst = 池中空闲实例
  if 无空闲:
      victim = 池内 (priority 最低) 且 (已播时长最长) 的实例
      if victim.priority <= p: 抢占并播放
      else: 丢弃本次请求
  设置 stream / bus / volume / pitch → play()
  （🔴 MVP：非定位 1D 池**无 pan**；定位音走 2D 池 4 路，见 §6 G-1 / §7.2）
```

### 4.6 资产 id → 路径映射约定

- 约定：**id = StringName，与文件名同构**（`&"snd_combat_kill_01"` → `res://assets/audio/sfx/snd_combat_kill_01.ogg`）。
- 🔴 **实现（as-built，T-P6-07 采纳）：首次使用 `load()` + 字典缓存**（**非** `preload`）。
  - **理由（关键工程判断）**：`.godot/` 被 gitignore、`.import` 不入库 ⇒ 新克隆**无导入态**；`preload` 未导入音频 = **解析期硬错误（EXIT=1，整局/CI 挂）**；`load()` 失败返回 `null` ⇒ **优雅静音**。语义上仍满足"零重复加载"（缓存命中即不再 `load`）。
  - 🔴 **代价 + 兜底责任（显式登记）**：失去 `preload` 的"路径写错即编译期报错" → 改由 **`run_audio_asserts.gd` 的"21+4 资产可加载"断言兜底**；🔴 该断言**已核：未纳入 CI** →（**兜底当前未生效 · 唯一关闭手段见 §6 G-6**）。
- 命名规范见 `audio-audit §4.3`；**本文档 §3.1 「建议资产 id」列即权威资产清单**。

---

## 5. 两坑 + R-d 的可执行处理（re~ `audio-audit §4.6` / §6.1）

| 问题 | 处理（可执行） |
|---|---|
| 🔴 **`paused` 静音坑**（安全窗 `get_tree().paused = true` → 播放器随暂停静音） | `AudioDirector` **及所有音频子节点** `process_mode = Node.PROCESS_MODE_ALWAYS`；安全窗音乐**继续**（情绪不断）。若需静默，用 `AudioStreamPlayer.stream_paused` 显式控制，**不靠** `paused`。 |
| **战术减速 `Engine.time_scale = 0.35`**（引擎默认**不**改音频速度） | 商店开门 → `set_focus_filter(1.0)`（Music+SFX **谐振低通**，1.5 s 缓动）表达"聚焦"；**禁**对音乐 pitch-bend（会像卡带故障）。关门 → `set_focus_filter(0.0)`。 |
| 🔴 **R-d / T-E1③**（塔复活音禁择时提示） | `_on_tower_revived` **只播 `snd_combat_tower_up` 单次**；**源码级回归断言**：该 handler 与音频资产名中**不含** `tick/countdown/charge/3..2..1` 等 token（供 quality-lead 守，见 §9）。 |

---

## 6. 已知缺口（MVP · as-built 登记）

> 登记 T-P6-07 实现（`scripts/audio/audio_director.gd` + `default_bus_layout.tres`）相比本规格的 **MVP 缩减**。每条含：现状 / 影响 / 补齐路径。可感知性裁定见 §7。

| # | 缺口 | 现状（as-built） | 影响 | 补齐路径 |
|---|---|---|---|---|
| **G-1** | **击杀无声像** | 击杀音走非定位 `AudioStreamPlayer`（1D 池），**无屏幕 x 声像** | §3.1 原列"全局 + 屏幕 x 声像"的**声像项未落**；节拍/密度信息不受影响（判据 §7.2） | 6.2：扩 `AudioStreamPlayer2D` 池（4→≥10）**或**改总线声像方案；代价=池/并发预算重估（原 2D 池 4 路 vs 击杀并发 ≤8 相冲突） |
| **G-1b** | **击杀伪空间增强（延后 · 本轮不做）** | 击杀音统一居中、无空间声像；已核实 `audio_director.gd:148,455-457` 的 `_kill_seq % 4` 为**确定性顺序轮转**（非随机，4 变体必循环覆盖）；rotate 与 `pitch_jitter` 独立（后者走确定性哈希、不用 RNG） | 仅后期击杀流缺**空间纹理**；密度与音色手感**完整**（判据 §7.2） | 🔴 **纯资产重制、零代码**：把 4 变体中 2 个烘焙立体声像（建议 1 号偏 L、4 号偏 R，做梯度而非硬左右），靠 `%4` 轮转产生伪空间（`AudioStreamPlayer` 按流自带声像播放）。⚠️ `%4` 为**确定性顺序**轮转 → 偏置会呈**固定重复**，必要时改为 **4 变体梯度偏置（L / L-轻 / R-轻 / R）**。🔴 **覆盖域受限（audio-impl 确认）**：变体仅在**个体相位（`< 10 kill/s`）**播；`≥ 10 kill/s` 停个体音、整层切 `snd_combat_kill_swarm` 循环洪流 → 4 变体**完全不播**，即**空间感恰在雪崩期消失**（该相位最需空间感）；若要覆盖洪流期须动 mono 的 `snd_combat_kill_swarm`。另：改 stereo 后**须保持文件名/时长/真峰口径**（按 id→文件名同构加载，改名即断）。**触发条件 = 资产复核通过后 + 用户需空间纹理时**（本轮冻结资产集：quality-lead 正对 `44b19cf` 在途复核，改动将使该轮复核作废） |
| **G-2** | **购买 5 档稀有度未接** | 购买音按 **`_buy_seq % 5` 轮转**（非按稀有度） | 稀有度**语义**丢失；音乐/节奏不受影响（判据 §7.3） | 待 `snapshot` 暴露 **`rarity`** 键后**一改即接**（读取→选档） |
| **G-3** | **`bind()` 无调用方** | 公开方法已实现，**MVP 未接线** | 无功能影响；为**公开扩展点**保留 | 引擎接入时由 `boot.gd` / `battle_shop.gd` 调用 |
| **G-4** | **`set_music_theme` no-op** | 单主题；环境换装（晨雾/黄昏/血夜/虚空）**未实现** | 水平换装的**环境色彩层**未落；**阶段 A/B/C 主弧线不受影响**（判据 §7.4） | 6.2：接波次区间 / `next_is_elite_wave` → theme 切换 |
| **G-5** | **金属断裂 CC0 来源待选型** | `snd_combat_tower_down.wav` 为程序化**占位**（可接入） | 质感为占位级 | 用户拍板 CC0 来源后替换（关键词/来源见 `audio-assets-build.md §4`） |
| **G-6** | **`run_audio_asserts.gd` 未纳入 CI（已核）** | 🔴 quality-lead 独立核：`.github/workflows/ci.yml`（171 行）**无 audio 步**；`tests/run_tests.gd` 不引用 audio。且 `run_audio_asserts.gd`（headless）断言全集 = kill≤8 · 子节点 ALWAYS · **总线名**齐备 · 低通/聚焦不改 pitch · stem=4 · paused 行为 · 信号数基线 → **资产存在性检查 0 处**（`:162` 的 `file_exists` 在 `_read()` 内，用途是数源码 signal）；**唯一**一条 `_ok("A 21 个 SFX 资产可加载")` 在 `tests/run_audio_scene_check.gd:95-100`，而该脚本 `:5` 明写「🔴 必须非 headless」→ CI（`ubuntu-latest` headless）**跑不了**。 | 🔴 §4.6 的 `load()` 兜底**既失去编译期路径检查、断言又不在 CI** → 「打错 `SFX_FILES`/`STEM_FILES` key」当前**无网**（静默 `null`，`_get_stream` 负缓存 `audio_director.gd:687-702`）。**判据**：唯一兜底断言**所在脚本与 CI 运行条件互斥**（需真显示驱动）→ 故**必须在 CI 外另立检查**。 | 🔴 **关闭错 key 盲区的唯一有效手段 = 免导入静态 lint**（**非**"更省"的备选）：遍历 `SFX_FILES`/`STEM_FILES`，判定 `FileAccess.file_exists(AUDIO_DIR + rel)`，**不依赖导入态**；⚠️ key→path 映射**必须取自 `audio_director.gd` 常量本身**，**不得另抄一份地图**（否则 lint 自身漂移）。🟡 **另可（可选，非关闭手段）**：把 `run_audio_asserts.gd` 加为 CI 一步 —— 仅补 **池/总线/信号/低通/token** 的额外回归网，🔴 **不覆盖错 key 盲区**，**不得**作为关闭手段列出。 |

---

## 7. 设计侧裁定：MVP 缩减 × 分层/过渡可感知性

> 回答主理人问题：**G-1（击杀无声像）/ G-2（购买档位轮转）是否让战斗/商店的"节奏可听性"退化到难以分辨？** → **判定：不退化**（判据如下）。另附相邻项 G-4 同判。

### 7.1 总判据
基调 A 的"**分层/过渡可感知性**"由 **`Music` 总线**决定：
- **垂直分层** = **4 stem 的增删**（`sub_drone` / `pulse` / `harmony_pad` / `rhythm`）；
- **水平过渡** = **`set_music_stage` 的 A↔B↔C 切换**（+ 6.3 的 theme）。
→ **G-1/G-2 均落在 `SFX` / `UI` 总线，且只触及"空间声像"与"稀有度语义"两个 *非节奏、非结构* 维度**，**不在分层/过渡的可感知性判据域内**。

### 7.2 G-1 击杀无声像 —— 判定 **不退化** ✅
- **声像是空间维度，与分层/过渡正交**：分层靠 stem 的频段/音色增删，过渡靠 stage 切换；击杀声像**既不参与分层、也不参与过渡**。
- **P2 关键信息（密度/音色）完整保留**：`< 10 kill/s` 个体音 → `≥ 10 kill/s` **洪流颗粒层**（§3.2①）——"噼啪→洪流"的**密度手感**是 P2 雪崩的听觉载体，**与声像无关**，如实保留。玩家听到的"战斗在变猛"完全成立。
- **遮挡风险已被设计内消解**：击杀洪流（P2，可被抢占）不会挤掉 P0（漏怪/塔毁）——**优先级抢占**（§4.5）保护关键音 → mono 集中不会"糊掉"关键信息。
- **唯一真实损失**：后期击杀流的**空间纹理**（声音随击杀位置扫动的"战场活跃感"）——属**打磨层**（6.2），非可读性层。
- **若 6.2 想补（不扩池 / 不改架构 / 不改 `audio_director.gd`）**：把 4 个击杀变体中的 **2 个烘焙轻微 L/R 偏置成 stereo**，靠"变体轮转"产生**伪空间感**（**纯资产重制**，我方可做）。✅ 前提已核实：`_kill_seq % 4`（`audio_director.gd:148,455-457`）为**确定性顺序轮转** → 方案技术成立；🔴 **本轮不做**（资产集冻结），已登记为 **§6 G-1b**（含梯度偏置建议与触发条件）。

### 7.3 G-2 购买档位轮转 —— 判定 **不退化** ✅
- **节奏/手感信息完整保留**：每次购买**可靠触发一声清脆 FM 铃**（存在感 + 干脆度 = P4"操作像动作游戏"的核心）；`_buy_seq % 5` **只改变音高/亮度，不改变触发时机** → **节奏可听性 100% 保留**。
- **丢失的是稀有度"语义"而非"节奏"**：稀有度分档是**信息/情感**维度（art-bible §2.3 色阶的听觉对应物），**不参与分层/过渡**；其缺失**降低丰富度，不降低可分辨性**。
- **唯一潜在负效应（已登记）**：轮转可能产生"普通卡响传说铃"的**错误联想**（false affordance）——但本作**无系统强绑定**该语义，故为**低风险**。
- **6.2 路径**：**无需替代**——`snapshot` 暴露 `rarity` 键后**一改即接**即达目标；在此之前维持轮转（多样性听感反优于"全用同一档"）。**不建议**把 5 档资产改成近同音色（会牺牲 6.2 的现成升级素材）。

### 7.4 相邻项 G-4（`set_music_theme` no-op）—— 判定 **不退化（但登记）** ✅
- 阶段 **A/B/C 弧线**（分层主结构）由 `set_music_stage` + 4 stem 承载、**已实现** → 玩家能听到"苟活→成型→雪崩"的**主相变**。
- 环境换装（theme）是**叠加在阶段之上的二级色彩层**（对齐 art-bible §2.4 雾色迁移）——其缺失**不削弱主弧线可分辨性**，仅少四档"背景色"。
- → **主弧线可感知性：保留；环境色彩丰富度：待 6.2。**

### 7.5 结论一句话
> **G-1 / G-2 / G-4 均未破坏分层/过渡的可感知性**——三者分别落在"**声像 / 稀有度语义 / 环境色彩**"三个 *非节奏、非结构* 维度；基调 A 的"**4 stem 分层 + A/B/C 过渡**"主结构在 MVP 中**完整可辨**。两处**最小可行增强**（击杀伪空间 / 购买保真）均为 **6.2 低成本增量**；其中 **G-1 的替代方案不需扩池、不需改架构、不需改 `audio_director.gd`**（纯资产重制，前提已标注）。

---

## 8. 预算（对齐 `audio-audit §4.7`）

| 项 | 数值 |
|---|---|
| 音频内存 | Music `.ogg` 流式 ≤ ~25 MB；SFX ≤ ~15 MB；**合计 ≤ ~40 MB** |
| 同发实例 | SFX ≤ 24（击杀个体 ≤ 8）+ Music stem ≤ 6 + Voice ≤ 1 |
| 音频线程 CPU | < 5% 单核（池规模硬约束） |
| 衰减 | `AudioStreamPlayer2D`: `max_distance ≈ 2~3 屏宽`，对数衰减；UI/Music 永不定位 |

---

## 9. 验收 / 回归断言（给 quality-lead 的钩子）

1. **只读性**：`audio_director.gd` **不出现**任何 `emit_signal(...)`（音频层永不发 gameplay 信号）。
2. **T-E1③**：`_on_tower_revived` 触发的音效无倒计时/滴答语义（token 扫描 + 人耳验收）。
3. **并发**：运行中 `AudioDirector.active_voice_count() ≤ 24`，击杀个体 ≤ 8。
4. **两坑**：安全窗（`paused=true`）下音乐**仍在播**；商店开门时 `Music` 总线滤波器 cutoff 下降（非 pitch）。
5. **零新信号**：`wave_director.gd` / `time_director.gd` / `shop_controller.gd` 的 `signal` 数量与基线**一致**。

---

## 10. 交接 / 下一步

- **对 `engineering-lead`（程基岩）**：本 §4 为**实现契约**——autoload/总线/池/订阅点/抢占规则/资产 map。落地前需用户确认资产选型（`audio-assets-plan.md`）。🔴 `project.godot` 仅增 `[autoload]` + `[audio]` 两段。🟢 **as-built 与本规格的缩减差异集中于 §6「已知缺口」**（G-1~G-6），其**可感知性经设计侧裁定为"不退化"（见 §7）** → **架构无需为 G-1/G-2/G-4 改动**；唯一需质量侧确认的是 §6 **G-6**（`run_audio_asserts.gd` 是否入 CI，关系 §4.6 的 `load()` 兜底）。
- **对 `quality-lead`**：§9 五条断言可直接转 CI/回归。
- **对 `team-lead`**：本规格 + `audio-assets-plan.md` 齐备后，可请用户拍板资产来源 → 开资产制作批次 → 程基岩接实现。

> **边界复述**：本批次只写规格文档；未改代码、未引入资产、未跑 Godot、未 push。
