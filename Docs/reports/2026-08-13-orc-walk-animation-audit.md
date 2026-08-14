# Slow Orc Walk 动画审计

日期：2026-08-13
范围：只读审计；未改动玩家、动画库或资源；未启动 Godot、导入、测试、截图或渲染。

## 结论

当前项目里没有 `Slow_Orc_Walk`，也没有任何以兽人行走命名或登记的角色动画。
用户给出的两个来源不是同一份内容：

- 项目 `Refs/game ref/Meshy_AI_Winter_Wanderer_biped (9)/...` 中只有
  `Meshy_AI_Winter_Wanderer_biped_Animation_Shot_and_Fall_Backward_withSkin.fbx`，
  没有 Orc Walk。
- `C:/Users/aresr/Downloads/Meshy_AI_Winter_Wanderer_biped (9)/...` 中有
  `Meshy_AI_Winter_Wanderer_biped_Animation_Slow_Orc_Walk_withSkin.fbx`。

Downloads 中的动画在**骨架层面可以接入**：它与当前角色源骨架是同一套 24 骨骼，
无需跨骨架重定向。但它在**运动学层面不能直接替换当前深雪行走**：动画原生步速约
`0.34–0.38 m/s`，当前角色在平坦满深雪中的实际速度约为 `0.88 m/s`（起步）到
`1.09 m/s`（形成节奏后）。直接替换会要求约 `2.3–3.0x` 播放，超过当前
`anim_max_pace = 1.5`，会把沉重迈步播放成匆忙踩踏并产生明显脚底滑移。

因此本轮没有替换。安全结论不是“格式不支持”，而是“骨架兼容、步速不兼容”。

## 当前项目状态

`src/entities/player/wanderer_animations.gd` 登记了 21 个模型内 take，另有一个
`idle_hunched` 数据资源；没有 `orc` / `slow_orc_walk`。

`src/entities/player/player_controller.gd` 也没有独立的深雪动画槽。当前深雪行为是：

1. `SnowField.wade_factor()` 降低移动速度；
2. 同一套普通 walk/run locomotion 按地速调节播放速度；
3. 深雪额外生成腿部沟槽；
4. `walk_guarded` 由冻伤脚部的 `_footing` 驱动，它不是深雪专用动画。

所以“用 Orc Walk 替换深雪艰难行走”并非替换一个现成槽位；它还需要新增一个由雪深
驱动、带平滑进出的动画分支，并处理它与普通 gait、冻伤 footing 的组合关系。

## 两个来源的文件证据

### 项目 Refs

递归清单只有一次后仰倒地 FBX 及其纹理/导入伴随文件。FBX：

- 大小：`16,326,476` bytes
- SHA-256：`1945C60F61B6BB2A362AF...`（本审计不依赖截断摘要判定内容）
- take：`Shot_and_Fall_Backward`
- 不包含 `Slow_Orc_Walk`

### Downloads

- 文件：`Meshy_AI_Winter_Wanderer_biped_Animation_Slow_Orc_Walk_withSkin.fbx`
- 大小：`16,363,692` bytes
- SHA-256：`15A4D92744B1D6F11EAA0E1DBBC044703250F8F78A20D40160D62DFC575A398B`
- take：`Slow_Orc_Walk`
- 帧：`1..166 @ 30 fps`
- 时长：`5.50 s`

## 骨架兼容性

通过 Blender 5.2 后台只读导入元数据，对比 Downloads 动画 FBX 与
`assets/source/characters/winter_wanderer_meshy.fbx`：

- 都是 24 骨骼；
- 骨骼名称和顺序完全一致；
- 两者高度都是约 `1.601953 m`；
- Armature 对象缩放都是 `0.01`；
- 最坏 rest matrix 元素差 `2.10e-5`；
- 最坏 rest bone-head 位置差约 `2.11e-7 m`；
- 24/24 骨骼都有动画曲线。

结论：这是同角色同骨架的另一条 Meshy 动画，不需要 `retarget_hunch.gd` 那种跨骨架
重定向。现有 `tools/decimate_character.py` 的 merge 路径原则上可以把它折入角色 GLB。

## 动画性质

只读骨骼曲线测量得到：

- Hips 首尾净位移约 `1.32 mm`：它是 in-place 动画；
- 首尾主要骨骼旋转差不超过 `0.058°`：循环边界干净；
- 脚高曲线自相关峰在 83 帧：全 take 含 2 个 gait cycle；
- 单周期约 `2.767 s`，总步频约 `43.4 steps/min`；
- 左脚抬高约 `0.250 m`，右脚约 `0.169 m`；
- Hips 垂直起伏约 `0.196 m`，Head 约 `0.258 m`。

这些数字说明动画确实具有高抬腿、沉重、明显上下起伏的艰难跋涉读感，而不是普通慢走。
它也有可见的左右差异，可能适合极深雪、疲劳或失衡状态，但不适合覆盖所有深雪。

主支撑段的脚相对身体向后速度约 `0.34–0.38 m/s`；边界处一段约 `0.47 m/s`，
不作为稳定步速。按主段估计，允许的 `1.5x` 播放上限只能支持约
`0.51–0.57 m/s` 的角色地速。

## 为什么本轮没有替换

当前平坦满深雪：

- 起步地速：`1.35 × lerp(1.0, 0.30, 0.50) ≈ 0.88 m/s`；
- 形成节奏后：约 `1.09 m/s`。

若保持现有游戏移动速度，Orc Walk 需要 `2.3–3.0x` 才能脚底配速；这会：

- 超过 `anim_max_pace = 1.5`；
- 破坏原动画“沉重”的时间感；
- 在雪面产生脚底滑移；
- 让足迹落点、步频音效和骨骼脚步相位更难一致。

若把角色速度降到约 `0.55 m/s` 来适配动画，则是在改变深雪玩法平衡，不是一次视觉替换；
这一决定不能由动画接入任务擅自作出。

## 推荐方案

不建议把 Orc Walk 直接覆盖整个深雪区间。建议二选一：

1. **保留现有速度（推荐）**：普通 walk 继续负责常规深雪；Orc Walk 只在更极端的
   “深度 + 坡度/体力”组合中少量混入，作为姿态层而不是 100% locomotion 替换。
   这仍需做脚底相位验证，不能只检查 take 是否成功播放。
2. **接受极深雪降速**：把真正极端区域的地速约束到 `0.51–0.57 m/s`，让 Orc Walk
   在不超过 `1.5x` 的范围内全权负责。它会显著改变玩家绕路、逃生与风险节奏，需所有者
   明确批准后再实施。

在没有这个选择前，继续使用当前 walk 比把一个骨架兼容但配速错误的动画硬塞进去更安全。

## 资源与版本控制风险

项目当前同时忽略 `/Refs/` 和 `/assets/`。即使把 Downloads FBX 复制到
`assets/source/characters/animations/slow_orc_walk.fbx` 并重建 GLB，这两份二进制仍不会随
GitHub 提交传播。代码若登记新 take，而另一台机器没有本地重建后的 GLB，会得到缺失动画。

实现前必须先决定二进制资产交付策略：继续本地维护并有明确同步步骤，或采用 Git LFS / 发布包。
本审计没有改变现有 ignore 策略。

## 本轮动作与安全边界

- 没有复制 FBX；
- 没有修改 `player_controller.gd` 或 `wanderer_animations.gd`；
- 没有重建 `winter_wanderer.glb`；
- 没有启动 Godot GUI、headless、import、测试、捕获或性能采样；
- Blender 仅后台解析 FBX 元数据和骨骼曲线，没有渲染。
