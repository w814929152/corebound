# 可游玩版本（Demo Build）— 打包与游玩说明

> **归属**：交付流程（非玩法）· **零数值 / 零口径 / 零基线影响**
> **首次产出**：2026-11-06 · Corebound `0.1.0`（Phase 3 MVP · 切片 1–8）
> **对应提交**：`export_presets.cfg` + `icon.svg` + 窗口尺寸 override + B-1 引导文案分态

---

## 1. 玩家侧：怎么玩

产物是**单文件 exe**，双击即玩：

```
build/windows/Corebound.exe     112 MB（pck 已内嵌，无伴随文件）
```

- **零依赖**：不需要安装 Godot、不需要 .NET、不需要联网。
- **窗口**：1600×900（逻辑视口仍是 1920×1080，等比缩放）。
- **配置要求**：渲染后端为 `gl_compatibility`（OpenGL 3.3），核显可跑。

### 操作

| 输入 | 作用 |
|---|---|
| `Tab` | 开 / 关商店抽屉 |
| `1` `2` `3` | 买第 1/2/3 个商品位的卡（选中即买） |
| `R` | 刷新商店（安全窗内） |
| `Space` | 安全窗内开始下一波 / 锁定焦点塔位 |
| `Esc` | 关抽屉 / 取消放置；两者都不适用时 = 跳过引导 |
| 鼠标左键 | 点「放置」→ 点一个塔位落子；点塔位做修复 / 拆除 / 献祭 |
| `F3` | 调试面板 |
| `Alt + F4` | 退出（游戏中途唯一退出方式） |

### 一局怎么走

1. **开局即 W1**（自动开波）——玩家自带 1 座塔 + 1 张卡，废料 0。
2. 撑过本波 → **安全窗**，商店自动打开，按击杀数结算废料。
3. 用废料买卡 → 点「放置」→ 点塔位落子 → `Space` 开下一波。
4. 塔会在战斗中受损进入 `Disabled`（断输出不断链），安全窗内三选一处置：修复 / 拆除 / 放着不管。
5. **活过 W20 且核心未归零 = 通关**；核心 HP（1000）归零 = 失败。终局有「再来一局 / 退出」。

### 首局引导（B-1 零教学）

底部浮层按四步单向推进，做完即自动跳到下一步，随时可点「跳过」或按 `Esc` 退出：

```
买卡 → 放置 → 开下一波 → 修塔
```

浮层文案**跟着钱包走**：废料不够时提示「守住这一波 —— 击杀敌人换废料」，攒够且商店已开时才提示「1/2/3 买一张建筑卡」。

## 2. 工程侧：怎么重新打包

### 前置：导出模板

必须与编辑器版本**严格同号**：`4.7.2.stable`。

- 常规安装：`%APPDATA%\Godot\export_templates\4.7.2.stable\`
- **Steam 版**：`<Steam>\steamapps\common\Godot Engine\editor_data\export_templates\4.7.2.stable\`（本机即此路径，2.0 GB，含 windows_release_x86_64.exe）

> 模板缺失时导出会直接失败并提示下载 `Godot_v4.7.2-stable_export_templates.tpz`。Steam 版随 depot 自带，无需单独下载。

### 一条命令

```bash
GODOT="<你的 Godot 可执行文件>"
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/Corebound.exe
```

预设定义在 `export_presets.cfg`：

| 项 | 值 | 理由 |
|---|---|---|
| `binary_format/embed_pck` | **true** | 单文件分发：一个 exe，无 `data.pck` 伴随文件 |
| `binary_format/architecture` | `x86_64` | 目标平台 |
| `script_export_mode` | `2` | 压缩二进制 token（减小体积、不暴露明文源码） |
| `application/modify_resources` | true | 写入 PE 图标 + 版本信息（产品名「守核 Corebound」） |
| `application/icon` | `res://icon.svg` | 128×128 径向核心图标 |

产物被 `.gitignore` 覆盖（`build/`、`*.exe`、`*.pck`、`*.zip`）——**二进制不进版本库**，只留可复现的导出配置。

### 冒烟验证（不需要人盯着）

```bash
# 用导出的 exe 自己录 120 帧，然后看最后一张图
./build/windows/Corebound.exe --write-movie /tmp/f.png --quit-after 120 --fixed-fps 30
```

日志里应出现 `[boot] proto/elite/aggro/revive 全 ON`，退出码 0。

> 结尾的 `ObjectDB instances were leaked` / `resources still in use` 是 headless / movie 模式下的引擎退出噪声，**不影响退出码**，与 CI 判定无关。

## 3. 本次为「可游玩」做的三处修正

### 3.1 引导文案分态（`tutorial_overlay.gd`）

实测开局 `scrap = 0`、裸塔价 12 ⇒ **首波结束前整个商店都是灰的**。原文案无论贫富一律提示「买一张建筑卡」，玩家照做会撞见买不起的货架，首局卡在第一步。

改为三态（判定逻辑一字未改，只换字）：

| 条件 | 文案 |
|---|---|
| 货架无买得起的卡 | `守住这一波 —— 击杀敌人换废料，波间才能建塔` |
| 买得起 + 抽屉关闭 | `Tab 打开商店 · 1/2/3 买一张建筑卡` |
| 买得起 + 抽屉已开 | `1/2/3 买一张建筑卡` |

数据源全部来自既有快照：`scrap` / `affordable`（`shop_runtime.snapshot()`）+ `drawer`（`time_director.snapshot()`）。**零新 snapshot 键。**

同时修正 `RUN` 步文案：「开始**本**波」→「开始**下一**波」——该步判据本就是「波次 +1」，开局 W1 由 `start_run(1)` 自动开波，玩家真正要学的是安全窗开下一波。

### 3.2 窗口尺寸（`project.godot`）

```
window/size/viewport_width=1920      # 逻辑视口不变
window/size/viewport_height=1080
window/size/window_width_override=1600   # 实际窗口
window/size/window_height_override=900
```

默认 1920×1080 窗口在 1080p 屏上连同标题栏会溢出，**底部核心血条被切掉**。`override` 只改窗口外框、不改逻辑视口 ⇒ `shop_layout.gd` 的 1920 基准算尺、快照读数、金标本全部零扰动。

### 3.3 图标（`icon.svg`）

新增 128×128 矢量图标：深色底 + 同心环 + 橙色发光核心 + 八向入侵点，对应「径向核心围攻」。导出时写入 exe 的 PE 资源。

## 4. 已知限制

| # | 限制 | 说明 |
|---|---|---|
| 1 | **中途无法退出** | `Esc` 已分配给「关抽屉 / 跳过引导」。结算界面有「退出」按钮；中途只能 `Alt + F4` |
| 2 | **无存档** | 每局从 W1 开始，进度不落盘（肉鸽单局制，刻意如此） |
| 3 | **引导每次启动重来** | `TutorialOverlay` 不持久化 `DONE` 状态，每次启动都会再走一遍；点「跳过」即可 |
| 4 | **单文件体积 112 MB** | 含完整 Godot 运行时（x86_64 release 模板 109 MB）。pck 本身仅约 6 MB |
| 5 | **仅 Windows x86_64** | 模板齐全，可随时加 Linux / macOS / Web 预设，本次未做 |

## 5. 验收记录

| 项 | 结果 |
|---|---|
| 导出退出码 | 0（`--export-release`，0 错误） |
| 产物 | `build/windows/Corebound.exe` 117,478,184 B，单文件 |
| PE 元信息 | ProductName `守核 Corebound` · FileVersion `0.1.0` · CompanyName `Corebound` |
| 实机启动 | 1920×1080 movie 录制 901 帧，`gl_compatibility` / AMD RX 9070 XT，退出码 0 |
| 开局文案 | 第 30 帧：`守住这一波 —— 击杀敌人换废料，波间才能建塔`（废料 0）✅ |
| 安全窗文案 | 第 899 帧：`1/2/3 买一张建筑卡`（废料 25，商店自动开）✅ |
| 引导状态机 | 25 项断言全过（`-- tutorial`） |
| 默认全量回归 | 10 段全绿，3,440 项 0 失败 |
