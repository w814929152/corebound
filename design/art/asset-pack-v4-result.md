# 资产包 v4 · 结算页 + 三态鼠标光标 —— 提案

**状态**：🟢 已落地（2026-11-08）
**范围**：`result_overlay.gd`（最后一个零美术整屏之一，玩家每局必看两态）+
 全局鼠标光标（当前用系统默认箭头，无游戏语言）。
 商店/卡包选择/战役 v2 屏由并行会话负责，本包不碰。

---

## 1. 现状基准（shots_uifinal/03-result-win.png）

- 结算页：全屏 0.72 死黑 ColorRect + 居中青边面板。**胜负零情绪差异**（除标题色），
  战场被压成一片黑，没有任何「通关爆发 / 核心被击穿」的视觉叙事。
- 光标：全游戏 0 处 `set_custom_mouse_cursor` —— 拖塔放置时仍是系统箭头，
  「能不能放这里」没有任何光标级反馈（只有松手后 `exit_placement(false)` 静默取消）。

## 2. 资产清单（7 件，`art/2d/ui/`）

| 资产 | 尺寸 | 用途 / 落点 |
|---|---|---|
| `ui_result_won_bg_v1` | 1920×1080 | 胜利情绪背景：夜幕紫底 + 中心辉金放射辉光（核心爆发）+ 细噪点；盖在 0.72 黑幕**之上**（normal 混合，自带暗部） |
| `ui_result_lost_bg_v1` | 1920×1080 | 失败情绪背景：中心警报红辉光 + 六向放射裂纹 + 焦暗边角 |
| `ui_result_won_banner_v1` | 960×96 | 胜利横幅带：辉金渐亮带 + 两端斜切收头 + 顶/底 1px 亮线；嵌面板标题上方 |
| `ui_result_lost_banner_v1` | 960×96 | 失败横幅带：警报红同构 |
| `ui_cursor_default_v1` | 48×48 | 默认光标：蓝图风箭头（白杆+耀青描边+深色填充）；hotspot **(4,2)** |
| `ui_cursor_place_v1` | 48×48 | 放置态：准星（十字四刻 + 中心圆点，耀青）；hotspot **(24,24)** |
| `ui_cursor_deny_v1` | 48×48 | 禁止态：警报红圆环 + 45° 斜杠 + 内暗底；hotspot **(24,24)** |

色号逐字取 art-bible §2.2（`#FFC94A` 辉金 / `#FF2E4E` 警报红 / `#3ED0E8` 耀青 /
`#141726` 夜幕紫 / `#0A0C14` 深底）。🔴 光标必须**白底可辨也暗底可辨**：全部带深色
描边 + 亮色主体，禁止纯白细线。

## 3. 接入设计

### 3.1 result_overlay.gd
- `_backdrop`（黑幕）与 `_panel` 之间插 `_mood: TextureRect`（FULL_RECT，
  `KEEP_ASPECT_COVERED`，mouse_filter=IGNORE）。`show_result` 按胜负切贴图。
- 面板内、标题上方插横幅 TextureRect（`EXPAND_FILL` 宽、高 96×面板宽比缩放）。
- **判空降级**：贴图缺失 → 不加层，回纯黑幕 + 纯色标题（现状）。

### 3.2 光标（`ui_style.gd` + `tower_backpack.gd` + `main_menu_overlay.gd`）
- `ui_style.set_cursor(mode: String)`：mode ∈ default/place/deny；`_cursor_tex()`
  判空降级（资产缺失 → 不动光标，保持系统箭头）。
- main_menu `_ready` → default（全局一次）。
- tower_backpack 拖放流（已有的逐帧 `_draw` 驱动）：
  - 拖起卡（`_drag_index >= 0`）→ **place**
  - 拖动中 `placement_mode_at(world).mode == "invalid"` → **deny**（逐帧反馈，
    之前只有松手才静默失败）
  - 松手 / 拖回背包条 → **default**
- 🔴 `Input.set_custom_mouse_cursor` 全局生效且 headless 下无害（有 `exists` 门）。

## 4. 验证口径

- 全量回归 FAIL 集与基线逐字一致（结算页/背包均被既有测试覆盖）。
- 实机截图：胜利/失败两态结算页；光标三态在截图里以「背包拖卡中」帧验证。

## 5. 教训区（落地后回填）

- 🔴 **生成器坐标铁律再现**：光标箭头 pts 忘走 `P()`（1× 坐标画在 4× 画布）→
  缩后只剩 8×12px。量化验证：`np.where(alpha>30)` 的 bbox 是唯一可靠目检替代——
  本次 62 个不透明像素 vs 预期 ~700，一眼定案。
- 🔴 **4× 画布上的模糊量要 ×4**：横幅高亮核 GaussianBlur(10) 在 4× 画布上只有
  1× 2.5px，硬边仍可辨；改 36（≈1× 9px）才柔。
- 🔴 **大渐变/噪点必须 numpy 向量化**：1920×1080 双层径向 + 双张噪点纯 Python
  逐像素要数十秒；`np.mgrid` + `Image.effect_noise` 后全程 <3s。
- **PIL putalpha 尺寸静默不查**：`np.tile` 转置错（(w,h) vs (h,w)）报
  "images do not match"——tile 前先想清楚形状。
- **冒烟截图链式驱动**沿用 v3：拍前校验中心像素非 0.3 灰、拍到一张才切下一态。
- 光标三态接入点收敛在 `tower_backpack` 的 `_draw`（motion 逐帧驱动）+
  `_drop_at` 统一恢复 default；`ui_style.set_cursor(mode)` 判空降级。
