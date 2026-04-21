# 03-语义 MCP 工具层 技术规格

## 1. 概述

在 godot-mcp 的 149 个底层工具之上，封装约 30 个游戏语义粒度的 Level 2 工具。每个工具对应一个完整的「游戏概念操作」，内部编排多步底层 Godot 调用，大幅减少 AI 调用步骤和 Token 消耗。

**范围**：
- 30 个 Level 2 语义工具的定义和实现
- 工具响应格式规范（含 suggestions 和 next_steps）
- System Prompt v1 + 核心约束规则
- 负向示例规则库（初始 20 条）

**不做**：
- Level 3 模板工具（在 04-game-templates 中）
- Level 0/1 底层工具（沿用 godot-mcp 原有）

## 2. 工具分层总览

```
Level 3: 模板操作层 (04-game-templates 负责)
  apply_template() / configure_template()

Level 2: 游戏语义层 (本模块, ~30 工具) ← AI 主要使用
  场景对象 (10) / 游戏规则 (8) / 素材 (5) / 验证调试 (5)

Level 1: 引擎操作层 (godot-mcp 原有, AI 自修复用)
  create_node() / set_property() / add_script() / ...

Level 0: 底层 Godot API (内部使用, 不暴露给 AI)
```

## 3. Level 2 工具清单

### 3.1 场景对象类 (10 个)

| 工具名 | 说明 | 核心参数 |
|--------|------|----------|
| `add_player` | 添加玩家角色 | position, speed, jump_force, sprite_asset |
| `add_enemy` | 添加敌人 | type(walking/flying/stationary), position, health, patrol_path, sprite_asset |
| `add_platform` | 添加平台 | position, size, type(static/moving/breakable), move_path |
| `add_collectible` | 添加收集物 | position, type(coin/gem/star), value, sprite_asset |
| `add_obstacle` | 添加障碍物 | position, type(spike/lava/saw), damage, size |
| `add_npc` | 添加 NPC | position, dialogue_lines[], sprite_asset |
| `add_ui_element` | 添加 UI 元素 | type(score/health_bar/timer/text), position, style |
| `add_camera` | 配置相机 | follow_target, zoom, limits, smooth_speed |
| `add_background` | 设置背景 | type(color/image/parallax), layers[], scroll_speed |
| `add_trigger_zone` | 添加触发区域 | position, size, on_enter_action, on_exit_action |

### 3.2 游戏规则类 (8 个)

| 工具名 | 说明 | 核心参数 |
|--------|------|----------|
| `set_win_condition` | 设置胜利条件 | type(reach_goal/collect_all/kill_all/survive_time), params |
| `set_lose_condition` | 设置失败条件 | type(health_zero/fall_off/time_up), params |
| `set_player_controls` | 设置操作方式 | move_type(platformer/top_down/point_click), keys_config |
| `set_physics` | 设置物理参数 | gravity, friction, bounce, air_resistance |
| `set_spawn_point` | 设置重生点 | position, respawn_delay |
| `add_level_transition` | 添加关卡切换 | trigger_position, target_scene, transition_type |
| `set_difficulty` | 设置难度参数 | enemy_speed_mult, enemy_health_mult, player_damage_mult |
| `set_game_loop` | 设置游戏循环 | start_scene, game_over_scene, restart_behavior |

### 3.3 素材类 (5 个)

| 工具名 | 说明 | 核心参数 |
|--------|------|----------|
| `search_asset` | 搜索素材库 | query(自然语言), type(3d/2d/audio), style, limit |
| `apply_asset` | 应用素材到节点 | node_path, asset_id, scale, offset |
| `generate_asset` | 实时生成素材 | description, type, style_seed, size |
| `set_bgm` | 设置背景音乐 | asset_id or query, loop, volume |
| `add_sfx` | 添加音效 | trigger_event, asset_id or query, volume |

### 3.4 验证调试类 (5 个)

| 工具名 | 说明 | 核心参数 |
|--------|------|----------|
| `get_screenshot` | 截取当前场景截图 | scene_path(可选), resolution |
| `run_game_test` | 运行游戏并获取日志 | duration_seconds, auto_actions[] |
| `validate_scene` | 静态检查场景完整性 | scene_path |
| `save_snapshot` | 保存当前项目快照 | label |
| `rollback_snapshot` | 回滚到指定快照 | snapshot_id |

## 4. 工具实现规范

### 4.1 工具响应格式

```typescript
interface ToolResponse {
  status: 'success' | 'error' | 'warning';
  result: {
    message: string;                    // 人可读的操作结果
    node_path?: string;                 // 创建/修改的节点路径
    data?: Record<string, any>;         // 额外数据
  };
  suggestions?: string[];               // 下一步操作建议
  scene_changed?: boolean;              // 是否修改了场景（用于快照决策）
  error?: {
    code: string;                       // 错误码
    message: string;
    recovery_hint?: string;             // 修复建议
  };
}
```

### 4.2 单个工具实现示例 (add_player)

```typescript
// MCP/src/tools/level2/add-player.ts

import { ToolDefinition, ToolResponse } from '../tool-registry';

export const addPlayerTool: ToolDefinition = {
  name: 'add_player',
  level: 2,
  description: 'Add a player character to the scene with movement controls. Creates a CharacterBody2D with collision shape, sprite placeholder, and movement script.',
  parameters: {
    type: 'object',
    properties: {
      position: {
        type: 'object',
        properties: { x: { type: 'number' }, y: { type: 'number' } },
        default: { x: 100, y: 300 }
      },
      speed: { type: 'number', default: 300, description: 'Movement speed in pixels/sec' },
      jump_force: { type: 'number', default: -400, description: 'Jump velocity (negative = up)' },
      sprite_asset: { type: 'string', description: 'Asset ID for player sprite (optional)' }
    }
  },
  examples: [
    {
      description: 'Add a basic player at default position',
      arguments: {},
      expected_result: { status: 'success', result: { node_path: '/root/Main/Player' } }
    }
  ],
  tags: ['scene', 'character', 'player']
};

export async function executeAddPlayer(args: any, session: Session): Promise<ToolResponse> {
  const { position = { x: 100, y: 300 }, speed = 300, jump_force = -400, sprite_asset } = args;

  // 内部编排多步底层操作
  // 1. 创建 CharacterBody2D
  await session.callLevel0('create_node', {
    parent: '/root/Main',
    type: 'CharacterBody2D',
    name: 'Player'
  });

  // 2. 设置位置
  await session.callLevel0('set_property', {
    node_path: '/root/Main/Player',
    property: 'position',
    value: { x: position.x, y: position.y }
  });

  // 3. 添加 CollisionShape2D
  await session.callLevel0('create_node', {
    parent: '/root/Main/Player',
    type: 'CollisionShape2D',
    name: 'CollisionShape'
  });
  await session.callLevel0('set_property', {
    node_path: '/root/Main/Player/CollisionShape',
    property: 'shape',
    value: { type: 'RectangleShape2D', size: { x: 32, y: 64 } }
  });

  // 4. 添加 Sprite2D (占位或实际素材)
  await session.callLevel0('create_node', {
    parent: '/root/Main/Player',
    type: 'Sprite2D',
    name: 'Sprite'
  });

  if (sprite_asset) {
    // 通过素材系统应用素材
    await session.callLevel2('apply_asset', {
      node_path: '/root/Main/Player/Sprite',
      asset_id: sprite_asset
    });
  }

  // 5. 附加移动脚本
  const script = generatePlayerScript(speed, jump_force);
  await session.callLevel0('add_script', {
    node_path: '/root/Main/Player',
    script_content: script
  });

  return {
    status: 'success',
    result: {
      message: `Player added at (${position.x}, ${position.y}) with speed=${speed}, jump_force=${jump_force}`,
      node_path: '/root/Main/Player'
    },
    suggestions: [
      'Use add_camera({ follow_target: "/root/Main/Player" }) to follow the player',
      'Use set_player_controls() to customize key bindings',
      'Use apply_asset() to set a player sprite'
    ],
    scene_changed: true
  };
}

function generatePlayerScript(speed: number, jumpForce: number): string {
  return `extends CharacterBody2D

const SPEED = ${speed}.0
const JUMP_VELOCITY = ${jumpForce}.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta):
    if not is_on_floor():
        velocity.y += gravity * delta

    if Input.is_action_just_pressed("ui_accept") and is_on_floor():
        velocity.y = JUMP_VELOCITY

    var direction = Input.get_axis("ui_left", "ui_right")
    if direction:
        velocity.x = direction * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)

    move_and_slide()
`;
}
```

## 5. System Prompt v1

```markdown
# 角色
你是一个 Godot 游戏生成 AI，通过 MCP 工具控制 Godot 4 引擎来创建 2D 游戏。

# 工具使用规范

## 优先级
1. 优先使用 Level 3 模板工具（apply_template）作为起点
2. 使用 Level 2 语义工具修改和扩展游戏
3. 仅在语义工具无法满足需求时，才使用 Level 1 引擎工具

## 工作流程
1. 分析用户需求，确定游戏类型
2. 选择合适的模板（apply_template）
3. 使用语义工具添加/修改游戏元素
4. 每 3-5 步操作后调用 get_screenshot() 验证
5. 发现问题立即调用 validate_scene() 排查
6. 严重错误时 rollback_snapshot() 回滚

## 场景树规范
- 根节点必须是 Node2D，命名为 "Main"
- Player 必须是 CharacterBody2D（不是 RigidBody2D）
- CollisionShape 必须是 CollisionBody/Area 的直接子节点
- 不得创建引用不存在的 res:// 路径的节点
- 场景树命名统一用 PascalCase

## 素材使用规范
- 同一游戏内的所有素材必须使用相同的 style_seed
- 优先使用 search_asset() 搜索底库，不要直接生成
- 生成素材时必须带 style_seed 参数

## 禁止操作
- 禁止在 CharacterBody2D 外层套 RigidBody2D
- 禁止创建空的 CollisionShape（没有 shape 属性）
- 禁止在 _ready() 中执行耗时操作
- 禁止使用 get_tree().change_scene() 的字符串参数引用不存在的场景
- 禁止修改 TPL_ 前缀的模板骨架节点
```

## 6. 负向示例规则库 (初始 20 条)

```json
[
  { "id": "N001", "rule": "CollisionShape2D must be child of CollisionBody2D/Area2D, never a direct child of Node2D", "severity": "critical" },
  { "id": "N002", "rule": "CharacterBody2D should not be nested inside RigidBody2D", "severity": "critical" },
  { "id": "N003", "rule": "RectangleShape2D.size must have positive width and height", "severity": "error" },
  { "id": "N004", "rule": "Sprite2D.texture must reference an existing resource path", "severity": "error" },
  { "id": "N005", "rule": "Node names must be unique among siblings", "severity": "error" },
  { "id": "N006", "rule": "GDScript must use @onready for node references, not _ready() assignment to exported vars", "severity": "warning" },
  { "id": "N007", "rule": "Camera2D.limit values: left < right, top < bottom", "severity": "error" },
  { "id": "N008", "rule": "TileMap cell_size must match tileset tile_size", "severity": "error" },
  { "id": "N009", "rule": "AnimatedSprite2D requires at least one frame in SpriteFrames", "severity": "error" },
  { "id": "N010", "rule": "Area2D monitoring/monitorable should be true for signal-based triggers", "severity": "warning" },
  { "id": "N011", "rule": "Do not call queue_free() in _physics_process() without guard condition", "severity": "error" },
  { "id": "N012", "rule": "Parallax layers must be ordered by z_index for correct depth", "severity": "warning" },
  { "id": "N013", "rule": "Timer.wait_time must be > 0", "severity": "error" },
  { "id": "N014", "rule": "AudioStreamPlayer must have stream property set before calling play()", "severity": "error" },
  { "id": "N015", "rule": "Do not use change_scene_to_file() with non-existent .tscn path", "severity": "critical" },
  { "id": "N016", "rule": "Gravity value should match project settings unless intentionally overriding", "severity": "warning" },
  { "id": "N017", "rule": "Signal connections must target existing methods", "severity": "critical" },
  { "id": "N018", "rule": "export var must have type annotation for editor visibility", "severity": "warning" },
  { "id": "N019", "rule": "Path2D/PathFollow2D: path must have at least 2 points", "severity": "error" },
  { "id": "N020", "rule": "Node groups used in get_nodes_in_group() must be actually assigned to nodes", "severity": "error" }
]
```

## 7. 文件清单 (工具实现)

```
MCP/src/tools/level2/
├── scene/
│   ├── add-player.ts
│   ├── add-enemy.ts
│   ├── add-platform.ts
│   ├── add-collectible.ts
│   ├── add-obstacle.ts
│   ├── add-npc.ts
│   ├── add-ui-element.ts
│   ├── add-camera.ts
│   ├── add-background.ts
│   └── add-trigger-zone.ts
├── rules/
│   ├── set-win-condition.ts
│   ├── set-lose-condition.ts
│   ├── set-player-controls.ts
│   ├── set-physics.ts
│   ├── set-spawn-point.ts
│   ├── add-level-transition.ts
│   ├── set-difficulty.ts
│   └── set-game-loop.ts
├── assets/
│   ├── search-asset.ts
│   ├── apply-asset.ts
│   ├── generate-asset.ts
│   ├── set-bgm.ts
│   └── add-sfx.ts
├── verify/
│   ├── get-screenshot.ts
│   ├── run-game-test.ts
│   ├── validate-scene.ts
│   ├── save-snapshot.ts
│   └── rollback-snapshot.ts
└── shared/
    ├── script-templates.ts      # GDScript 模板库
    ├── negative-rules.json      # 负向示例规则库
    └── validation.ts            # 参数校验工具
```

## 8. 验收标准

1. **工具数量**：30 个 Level 2 工具全部注册并可通过 HTTP 调用
2. **add_player 端到端**：调用 add_player → Godot 中创建 CharacterBody2D + CollisionShape + Script → 游戏可运行，角色可移动
3. **add_enemy 端到端**：调用 add_enemy(type="walking") → 敌人节点带巡逻逻辑
4. **工具响应格式**：所有工具返回统一的 ToolResponse 格式，含 suggestions
5. **validate_scene**：能检测出 N001~N020 中的至少 10 条规则违反
6. **get_screenshot**：截图返回 base64 PNG，可被 AI 视觉模型读取
7. **AI 集成测试**：用 Claude 通过这 30 个工具生成一个简单平台跳跃游戏，步骤 < 15 步
8. **System Prompt**：配合 System Prompt v1，AI 能正确遵循工具使用优先级
