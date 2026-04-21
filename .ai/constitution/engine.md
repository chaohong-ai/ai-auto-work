# 宪法详细规则：Engine 与多平台

> **作用域：创作平台的 Engine/ 目录与导出链路。** 本文件是 `.ai/constitution.md` §6「多平台兼容」的详细展开，仅在涉及 Engine / 多平台导出时按需加载。
> **不适用于 `GameServer/`。**

## Linux 容器导出能力边界（不可协商）

Linux Godot 容器仅用于 Android / HTML5 / 资源导入与验证；完整 iOS 导出必须走 macOS + Xcode 流水线，不得在 Linux 容器方案里承诺"iOS 可导出"或把 iOS 验收挂到 Linux CI 步骤。涉及多平台验收的 feature，iOS 分支必须独立于 Linux 容器测试执行；缺 macOS runner 时明确标记为"未验收"而不是"通过"。详见 `.ai/context/project.md`"容器平台导出能力边界"。

---

> 以下规则从 endless-abyss 等 GDScript 游戏项目的多轮 develop-review 反复出现的代码质量问题中提取。

## GDScript 内部可变状态必须私有化（不可协商）

**内部可变状态**——Array、Dictionary、缓存句柄、运行时计数器等——必须使用 `_` 前缀标记为私有。外部访问通过 getter 方法，getter 返回 `.duplicate()` 副本而非可变引用。

**豁免**以下场景，不要求 `_` 前缀：
- `@export` 变量（有意暴露给 Inspector 的配置项）
- 对外公开的可调配置参数（如 `max_reconnect_attempts`、`move_speed`）
- 纯数据承载字段（Data Transfer Object / Config struct 的属性）
- `const` 常量

```gdscript
# ✅ 内部可变状态 → 私有化
var _zone_instances: Array = []
var _combo_count: int = 0
func get_zone_instances() -> Array:
    return _zone_instances.duplicate()

# ✅ 对外配置参数 → 公开合理
@export var max_reconnect_attempts: int = 5
var move_speed: float = 200.0

# ❌ 违宪：内部缓存/集合公开可变
var zone_instances: Array = []        # 内部集合暴露
var _hidden_types: Dictionary = {}    # 但 getter 返回原始引用
```

根因：endless-abyss 的 zone_speed / zone_stomp 中 `base_safe_weight` / `current_safe_weight` 内部权重被外部直接修改，review 多轮标记。

## GDScript 语义不自明的共享字面量必须抽常量（不可协商）

满足以下**任一条件**的数值字面量必须提取到 `config.json`、`config.gd` 或集中的 `CONST.gd`：
- **跨函数 / 跨文件重复出现**的同一数值
- **影响游戏平衡、协议行为、平台适配**的参数（分数倍率、帧率阈值、网络超时等）
- **语义不自明**——读到数字无法立刻理解"为什么是这个值"

**豁免**以下场景，允许保留字面量：
- 仅在当前函数内使用一次的布局偏移、动画时长、插值参数、碰撞阈值等本地值
- 数学常量（PI、TAU）、索引（0、1、-1）、位运算掩码
- Tween 的 duration/delay 等 Godot API 直接消费的一次性参数

```gdscript
# ❌ 语义不自明 + 影响平衡
var hp := 999                    # 999 表示"无敌"？抽常量
var layers := 20                 # 跨多处使用，抽到 Config

# ✅ 抽常量
const INVINCIBLE_HP := 999
var layers := Config.LAYERS_PER_ZONE

# ✅ 本地一次性值，保留合理
tween.tween_property(self, "modulate:a", 0.0, 0.3)  # 0.3s 淡出
position.x = clamp(position.x, 16.0, screen_width - 16.0)  # 边缘留白
```

根因：endless-abyss 中跨文件重复的平衡参数（层数、倍率、权重）散落在多个文件中，修改一处漏改另一处。

## GDScript 空值守卫（不可协商）

所有对外部对象 / 字典 / 节点的访问必须先做空值或存在性检查，带 `push_error` / `push_warning` 日志。禁止直接访问可能为 null 的属性——GDScript 不像静态语言有编译期保护，运行时 null access 直接崩溃。

```gdscript
# ✅ 正确
func show_stats(game_manager: GameManager) -> void:
    if game_manager == null:
        push_error("DeathScreen.show_stats: game_manager is null")
        return
    var player = game_manager.get_player()
    if player == null:
        push_warning("DeathScreen.show_stats: player is null, using defaults")
        _show_default_stats()
        return
    _show_player_stats(player)

# ❌ 违宪：直接访问可能为 null 的属性
func show_stats(game_manager) -> void:
    var score = game_manager.player.score  # 两层都可能 null
```

特别关注以下高危场景：
- 回调函数中访问 `_player`、`_game_manager` 等可能已被释放的引用
- `get_node()` 返回值直接使用（节点可能不存在或已释放）
- Dictionary 直接用 key 访问（key 可能不存在，应使用 `.get(key, default)` 或 `.has(key)` 判断）

根因：endless-abyss 的 death_screen.gd、zone_speed.gd、game_manager.gd 中 8+ 处 null/type safety 问题在 review 后才发现。

## GDScript 函数参数类型注解（推荐）

所有公开方法和信号回调的参数必须带类型注解。内部辅助方法建议带类型注解。类型注解帮助 Godot 编辑器提供自动补全和静态分析提示，减少运行时类型错误。

```gdscript
# ✅ 正确
func apply_damage(target: Node2D, amount: float, source: StringName) -> void:
    pass

# ❌ 不推荐
func apply_damage(target, amount, source):
    pass
```
