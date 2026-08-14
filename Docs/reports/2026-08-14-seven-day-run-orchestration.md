# 七日运行编排切片报告

日期：2026-08-14

状态：完成

## 结果

`GameState` 已取代临时 `RunBoot`，成为一次七日尝试的唯一所有者。它负责：

- 使用同一个转换原子启动 `SurvivalSystem` 与已加载七份日程的 `WorldClock`；
- 持有可重放的 `run_seed`，并通过 `ServiceRegistry` 发布 `game_state` 与 `run_seed`；
- 监听 `survival.died` 与 `beacons.final_state`，只发布一次值类型的 `game.run_ended`；
- 区分 `rescued`、`abandoned`、`dead`，不把“活着但没被看见”折叠为死亡；
- 死亡时停止世界时钟，避免结算期间继续推进天气和日期；
- 在统一复位契约完成前拒绝从终态局部重开，避免只治疗身体却保留旧库存、拾取物和信标油量。

真实的七份 `DaySchedule` 与五份 `BeaconDefinition` 已在测试中用固定种子 `1729` 走到第八天黎明，并得到 `rescued` 结果。

## TDD 证据

RED：新增 `tests/unit/test_game_state.gd` 后运行：

```bash
bash tools/run_tests.sh
```

主线新增断言按预期失败：六个测试报告“the seven-day run still has no GameState owner”，项目接线测试同时指出 `GameState` 缺失且 `RunBoot` 仍在。该次工作区另有一条不属于本切片的天气测试失败，因此总结果为 `2376 passed, 8 failed`。

GREEN：实现运行编排、迁移旧测试和更新工具引用后，再运行同一命令：

```text
2382 passed, 0 failed
```

包装器退出码为 0，没有 `SCRIPT ERROR`、`ERROR:`、`WARNING:`、解析错误、泄漏或仍在使用的资源。15 个 `test_game_state.gd` 测试与 18 个 `test_world_clock.gd` 测试全部通过。

## 文件与迁移

- 新增：`src/systems/game_state.gd`、`tests/unit/test_game_state.gd` 及 UID；
- 修改：`project.godot`、`world_clock.gd`、运行种子消费者、测试门槛和进度文档；
- 删除：`src/systems/run_boot.gd`、`tests/unit/test_run_boot.gd` 及 UID；
- 恢复：6 个仍有脚本主体、此前被误判为孤立文件的 UID；
- 未触碰：本轮开始前已经存在并在同时变化的天气/雪雾工作文件。

## 下一切片

为 `FuelEconomy`、`SurvivalRouteLayer`/路线节点和 `BeaconNetwork` 增加统一的 `reset_for_run(seed)` 或等价事件契约，然后让 `GameState` 安全支持死亡后从第 1 天重开。
