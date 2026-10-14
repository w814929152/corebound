# T-P6-07 音频框架 · 独立复核报告（audio-verify）

> 复核人：**严守真（quality-lead）** · 日期：2026-10-13
> 对象：`8c04aff`（框架）/ `8dd4a79`（断言）/ `44b19cf`（资产）——基于 `5304edd` · **未 push**
> 方法：独立复跑（未复用 audio-impl 自验）· 静态核查先做、Godot 跑动后做（遵守单实例锁）· 新增探针 `tests/_qa_audio_probe.gd`。
> 只读：**未改 `scripts/audio/**` / `project.godot` / 三源**；不 push。

---

## §0 结论

# 🟡 CONDITIONAL PASS

**三个提交本身达标**（全 8 项红线通过 · 全量回归逐位一致 · 零玩法扰动）。
**条件（1 条硬、2 条软）**：
1. 🔴 **硬**：`id→路径` 是**运行时映射**，打错 key = 运行时**静默 null**（`_get_stream` 负缓存不留痕）。**关闭该盲区的唯一有效手段 = headless 免导入静态 lint**（遍历 `SFX_FILES`/`STEM_FILES` 做 `FileAccess.file_exists`，映射取自 `audio_director.gd` 常量本身）。**注**：唯一含「21+4 资产可加载」断言的 `run_audio_scene_check.gd` 需**真显示驱动** → 与 CI 条件**互斥**，故把 `run_audio_asserts.gd` 入 CI **不覆盖**该盲区、**不得**作为关闭条件（详见 §6）。**（复核后状态：该 lint 已落地 CI → 本条件已满足。）**
2. 🟡 软：spec 四处已登记偏差回写（§4.1 路径 / §4.6 preload / §3.1 pan / §3.2 稀有度档）。
3. 🟡 软：`_auto_discover` 陈旧引用为**潜伏风险**（当前不可达，见 §3）。

> 逐项「PASS / 未证实」见下；证据 = 命令 + 原始读数 + file:line。

---

## §1 逐项复核（team-lead 8 项）

### ✅ [1] 确定性零扰动（最关键）—— PASS
- 命令：`G --headless --path D:/roguedemo --script res://tests/run_tests.gd`
- 原始读数：**EXIT=0 · PASS=1157 / FAIL=0 · `SCRIPT ERROR`/`Parse Error` 计数 = 0**
- 九段与冻结基线**逐项相同**：

| 段 | slice1 | slice2 | slice3 | slice4 | slice5 | slice6 | slice7 | slice8 | t1aggro |
|---|---|---|---|---|---|---|---|---|---|
| 本次 | 222 | 2228 | 142 | 123 | 302 | 41 | 31 | 92 | 234 |
| 基线 | 222 | 2228 | 142 | 123 | 302 | 41 | 31 | 92 | 234 |

- slice1：`[逐波] 原始列最大相对偏差 = 1.712e-16 @ tierB W17`（验收线 1e-6）·「全部对齐…逐位一致」。
- slice2 MC：**A 起飞率 69.3%（=208/300）· 中位 W8.0**；**B 起飞率 91.3%（=274/300）· 中位 W13.0**；`[7b]` MC_TRACE 前 20 局 `got == want`（**分歧局数 0**）。
- **意义**：该基线系**无 autoload 时录制** → 逐一相同 = **证明音频 autoload 对 golden / slice2 / MC 确定性零扰动**。**无 FAIL、无需定位根因。**
- ⚠️ 环境注明：复核工作树含**未提交 #36 VFX 改动**（`wave_director.gd`/`battle_shop.gd`/`monster_layer.gd`）——与音频文件**不相交**，不影响本项归因。

### ✅ [2] 接线真实性（代码调用 vs 运行期连上，分开报）—— PASS
- **代码调用数**：`grep -nE "_connect\(" scripts/audio/audio_director.gd` → **18 命中 = 17 调用 + 1 定义**（定义在 `:263`）。17 调用分布在 `:232-239`(WD×8) · `:246-252`(TD×7) · `:259-260`(SC×2)。
- **运行期连上数**（探针 `_qa_audio_probe.gd` + `run_audio_scene_check.gd` 各测一次）：**17/17**
  `[QA-WIRING] 运行期连接 = 17/17 （TD=true WD=true SC=true）`。
- ✅ 代码有调用 **且** 运行期真连上，两项独立一致。

### ✅ [3] `_auto_discover` 启发式稳健性 —— PASS（附 1 潜伏风险）
代码 `scripts/audio/audio_director.gd:210-226`：`_walk` 递归全树，按信号组合猜容器：
`wave=monster_killed+snapshot` · `time=wave_started+drawer_mode_changed` · `shop=shop_changed+run_changed`。
- **误绑风险 = 低**：三组组合在本仓各只匹配唯一节点（WaveDirector / TimeDirector / ShopController）；未见其它节点同时具备该组合。
- **漏绑（容器晚于 `_ready` 实例化）= 已兜住**：`_ready` 即时扫 + `call_deferred` 扫 + `_process` 每帧 `if not _all_bound(): _auto_discover()` 重试 → 容器一旦出现即绑定（本工程 `battle_shop.gd:50` 在场景 `_ready` 内 `add_child`，实测 17/17 已连）。
- 🟡 **潜伏风险（当前不可达）**：`_bind_*` 只判 `n == null / is_instance_valid(n)`，但**未清空陈旧引用**——若容器被**释放后重建**，`_wave_director` 仍持旧引用（`!= null`）→ `_walk` 的 `if _wave_director == null` 为假 → **永不重绑**，只见「子节点 ALWAYS」而音频静默。
  - **复现条件**：`get_tree().reload_current_scene()` / 重建容器节点。
  - **现状**：`grep` 全 `scripts/` **无** `reload_current_scene` / `change_scene_to`；`WaveDirector` 仅在 `battle_shop.gd:50` 创建一次，重开（`_on_restart_requested`）只 `bind_runtime` 不重建 → **当前不可达**。
  - **建议**：`_walk` 绑定前加 `if not is_instance_valid(_wave_director): _wave_director = null`（3 行防御）。非阻断。

### ✅ [4] 暂停 & 时间轴红线 —— PASS
- `PROCESS_MODE_ALWAYS` **5 处**：`:163`(self) · `:627`(SFX 池) · `:640`(2D 池) · `:651`(stem) · `:673`(swarm) —— 与 team-lead 所列一致，**无遗漏**。
- **无遗漏的判决性证据**（运行期枚举，非读码）：`run_audio_scene_check.gd` → `[PASS] ④ 全部音频子节点 ALWAYS  children=33`（24+4+4+1）。stem 为**显式** ALWAYS（非继承）。
- **`Engine.time_scale` 零写入**：`grep time_scale` 仅 `:21`(注释) + `:400/:416/:709`(`Tween.set_ignore_time_scale(true)`，**非**写 `Engine.time_scale`)。→ **零写**。
- 行为验证：`paused=true` 下 `music_playing_count=4`；开商店 Music LPF `cutoff 20500→700`（非 pitch）。

### ✅ [5] 零信号 / 零玩法写入 —— PASS
- `grep -nE "signal |emit_signal|\.emit\(" scripts/audio/audio_director.gd` → **唯一命中 `:12` 为类注释**；**零** `signal` 声明、**零** `emit`。
- 三提交 `git show --name-only`：**均未触碰** `scripts/engine/**` · `scripts/data/**` · `scripts/geo/**` · `scripts/gameplay/**` · `wave_director.gd` · `monster_layer.gd` · `battle_shop.gd`。
- 三源信号计数：`wave_director=8` · `time_director=15` · `shop_controller=2`（grep 独立复核 = 基线）。

### ✅ [6] 降级路径 + 兜底责任 —— PASS（附「错 key 盲区」订正）
`_get_stream()` `:687-702`：`_stream_cache` 首查 → `ResourceLoader.exists()` 守卫 → `load()` → 写缓存（失败也写 `null` = **负缓存**）。
- **负缓存成立**：失败路径 `_stream_cache[rel_or_id] = st`（`st` 可为 null）→ 后续同 id 直接吃缓存，**不重复尝试、不刷屏、静默降级**（headless 无导入时不报错）。✅
- **反面无网（重点 · ⚠️ 我首版报告此处有一处内部不一致，已订正）**：
  - 「A 21 个 SFX 资产可加载 / 4 stem」这条断言**并不在** `run_audio_asserts.gd` 里。该脚本断言全集 = `:88` kill≤8 · `:98` 子节点 ALWAYS · `:101-108` **总线名**齐备（`:104` 的 `missing` 是总线名，非资产）· `:110-126` 低通/聚焦不改 pitch · `:128` stem=4 · `:131-135` paused · `:138-146` 信号数基线 → **资产存在性检查 0 处**。
  - 该断言的**唯一所在** = `tests/run_audio_scene_check.gd:95-100`，而该脚本头部 `:5` 明确「🔴 必须非 headless」（依赖真显示驱动的 `playing`）→ **CI（ubuntu headless）跑不了**。
  - ⇒ **唯一兜底断言所在脚本与 CI 运行条件互斥** → 故**必须另立非 CI-内** 的检查（或改走下面的免导入 lint）。
- **关闭错 key 盲区的唯一有效手段 = 免导入静态 lint**：遍历 `SFX_FILES`/`STEM_FILES` → `FileAccess.file_exists(AUDIO_DIR + rel)`，**映射须取自 `audio_director.gd` 常量本身**（不得另抄地图 / 无第二 SSOT），不依赖 `--import`。
- **`run_audio_asserts.gd` 入 CI = 额外回归网**（池 24+4 / 总线名 / 信号数 / 聚焦低通 / token 扫描），**🔴 不覆盖错 key 盲区**，**不得**列为关闭条件。
- **状态更新（独立复核后）**：CI 现已加两步 —— `lint_audio_assets.gd`（免导入 lint = 上述唯一手段）+ `run_audio_asserts.gd`（额外回归网）；`run_audio_scene_check.gd` 明确**排除**在 CI 外（需真显示）。→ **错 key 盲区已由 lint 关闭，本条件已满足**。

### ✅ [7] 击杀聚合器（探针实测，非读码）—— PASS
探针 `tests/_qa_audio_probe.gd`（**窗口真驱动**，因 headless dummy 驱动 `playing` 恒 false）原始读数：
```
[QA-CAP]   clear + 9× notify_kill（rate=9<10）→ kill_voice_count = 8（上限 8；≤8 = true）
[QA-CAP]   active_voice_count = 9（≤24 = true）
[QA-SWARM] clear + 12× notify_kill（rate=12≥10）→ _swarm_active = true ; swarm.playing = true ; rate(窗口)=12
[QA-HOLD]  停投 ~1.6s 后（窗口已排空）→ _swarm_active = false ; rate=0
```
- 并发上限 **8** 实测达成（第 9 次被 `if _kill_voices() < KILL_VOICE_CAP` 拒播）。
- 阈值切换：rate≥10 → 转 `snd_combat_kill_swarm` 循环层且**真在播**。
- 迟滞退出：停投后窗口排空 → `_swarm_active=false`（符合 `SWARM_QUIET_HOLD=0.4s`）。
✅ 三条均实测，非"确认存在"式复述。

### ✅ [8] R-d 红线 —— PASS
- `scripts/audio/audio_director.gd:531-532` `_on_tower_revived` **仅 1 行** `play_sfx(&"snd_combat_tower_up", {…position…})`。
- 断言②：`play_sfx` 调用数 **= 1**；token 扫描（`tick/countdown/charge/3..2..1`）**hits=[]**。

---

## §2 pan API 裁定（team-lead 指定独立判）

**实测（ClassDB，探针原始读数）**：
```
[QA-PAN] AudioStreamPlayer   pan 类属性 = []                       # 空 —— 无 pan/panning 属性
[QA-PAN] AudioStreamPlayer2D pan 类属性 = ["panning_strength"]
[QA-PAN] AudioStreamPlayer3D pan 类属性 = ["panning_strength"]
[QA-PAN] AudioStreamPlayer 全部属性名 = ["stream","volume_db","volume_linear","pitch_scale",
         "playing","autoplay","stream_paused","mix_target","max_polyphony","bus","playback_type", …]
```
**判定**：
- ✅ audio-impl 的「`AudioStreamPlayer` 无 pan 属性」**属实**（属性表确无任何 pan 类字段；仅有 `mix_target`(STEREO/MONO/SURROUND)，不提供左右声像）。
- ❌ **无"免费"替代**：要实现「屏幕 x 声像」，唯一可行路径是走 **`AudioStreamPlayer2D`（position.x）**——但 `kill_voice_count()` 只数**非定位池**的 `_pool_is_kill`，把击杀改 2D 会**破坏「击杀并发 ≤8 可数」**（team-lead 设的"不破 gate"前提不成立），除非**同步扩 gate**（让 `kill_voice_count()` 兼数 kill 标记的 2D 实例）。
- 🟡 **结论**：**MVP 降级（击杀走非定位池）可接受**——不是"有替代却不选"，而是"替代需连带改门禁、非最小改动"。建议 **backlog**（最小改动路径 = 击杀走 2D 池 + `kill_voice_count()` 兼数两池的 kill 实例；约 10~15 行）。**不阻断本轮。**

---

## §3 四处规格偏差 · 判读（建议回写 spec）

| # | 偏差 | 判读 |
|---|---|---|
| 1 | 路径 `scripts/audio/` vs spec §4.1 `autoload/` | 🟡 可接受（内部自洽）；**建议回写 spec** |
| 2 | §4.6 `preload` → 首次 `load()`+负缓存 | 🟡 可接受（headless 不导入、`preload`=解析期硬错误）；**兜底 = 免导入 lint（§6）**（非 `run_audio_asserts.gd`） |
| 3 | 击杀略去「屏幕 x 声像」（§3.1） | 🟡 可接受（见 §2 裁定：无免费替代）；backlog |
| 4 | 购买=顺序轮播 5 变体（§3.2「按稀有度 5 档」） | 🟡 可接受（资产齐备、选择逻辑未接稀有度）；backlog |

---

## §4 提交洁净度 —— PASS
| 提交 | 文件 | 判定 |
|---|---|---|
| `8c04aff` | `project.godot`（**仅 `[autoload]`+`[audio]` 两段** · diff 已核）· `default_bus_layout.tres` · `scripts/audio/audio_director.gd` | ✅ |
| `8dd4a79` | `tests/run_audio_asserts.gd` · `tests/run_audio_scene_check.gd`（未动 `run_tests.gd`） | ✅ |
| `44b19cf` | `assets/audio/**`（21 wav + 4 ogg + `_src/` 3 件 = 28 文件；无 `.import`） | ✅ |

无 `design/`·`.workbuddy/`·残留混入。

---

## §5 附加验证（窗口端到端，独立跑）
`--import`(EXIT=0) → `G --path D:/roguedemo --script res://tests/run_audio_scene_check.gd` → **EXIT=0 · 23/0**：
21 SFX `missing=[]` · 4 stem `null=0` 在播 · 17/17 · 漏怪/塔毁/塔复活→2D(1/2/3) · 购买→UI(0→1) · cutoff 20500→700 · paused 下 music=4。
headless 断言 `run_audio_asserts.gd` → **EXIT=0 · 23/0**。

---

## §6 证据 / 复现
日志：`ci-logs/qa-s-verify/{run_tests-audio-head,audio-asserts,audio-import,audio-scene,audio-probe}.log`
```bash
G="/c/Users/junhewang/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path D:/roguedemo --script res://tests/run_tests.gd            # [1] 1157/0 · EXIT=0
"$G" --headless --path D:/roguedemo --script res://tests/run_audio_asserts.gd     # 23/0 · EXIT=0
"$G" --headless --path D:/roguedemo --import
"$G" --path D:/roguedemo --script res://tests/run_audio_scene_check.gd            # 23/0 · EXIT=0
"$G" --path D:/roguedemo --script res://tests/_qa_audio_probe.gd                  # [2][7]+pan 取证
```

## §7 未证实项
- **无**「证实存在」式结论；[1]/[2]/[4]/[7] 均为运行期实测，[5]/[6]/[8] 为 grep/文件级实测。
- 唯一**未做**：`_auto_discover` 陈旧引用的**故障复现**（因当前无场景重载路径，**不可达**）——按「潜伏风险」报告，非「未证实」。

*报告结束 · 严守真（quality-lead）· T-P6-07 音频框架独立复核 · **🟡 CONDITIONAL PASS***
