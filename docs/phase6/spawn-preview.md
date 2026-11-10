# 准备阶段出怪预告

准备阶段显示下一波实际出生点：视野内用橙色菱形和向内箭头，视野外用屏幕边缘向外箭头。相邻屏幕标记合并，镜头平移、缩放时重新投影。部署期间保留，开战和结算时隐藏。

`wave_director.preview_spawn_positions()` 只读波表数量，复用实际生成的 `spawn_angle()` 与 `SpaceModel.radial_pos_of_t()`，因此包含当前关卡、波次、异形地图边界和战术入口规则；不启动波次、不消费随机数、不创建怪物。渲染缓存按导演、波次、关卡、地图和配置更新。

验证：`run_spawn_preview_asserts.gd` 十关、第一和第二波共 151 项通过，核对真实怪物出生位置、数量、重复读取、战斗和结算隐藏；已加入 world 门禁。`run_preparation_asserts.gd` 通过。窗口截图已目检：`art/_review/spawn-preview-close.png`、`spawn-preview-overview.png`。本轮未运行完整回归，退出仍有既有资源清理警告。
