# 04-游戏模板系统 技术规格

## 1. 概述

实现「平台跳跃」游戏模板作为 Phase 0 的核心模板，包含完整的骨架场景、config.json 参数化配置、以及 Level 3 MCP 工具。AI 优先通过修改 config.json 参数来定制游戏，而非从零构建场景树。

**范围**：
- 平台跳跃模板骨架（.tscn + GDScript + config.json）
- Level 3 模板工具：apply_template / configure_template / get_template_info
- 模板参数 Schema 定义
- 模板节点命名规范（TPL_ 前缀）

**不做**：
- 弹幕射击、解谜、跑酷模板（Phase 1）
- Luau 脚本（Phase 2）

## 2. 文件清单

```
Engine/godot/templates/
├── platformer/                      # 平台跳跃模板
│   ├── project.godot                # Godot 项目配置
│   ├── config.json                  # 模板参数配置文件
│   ├── config.schema.json           # 参数 JSON Schema
│   ├── scenes/
│   │   ├── main.tscn                # 主场景（骨架）
│   │   ├── player.tscn              # 玩家子场景
│   │   ├── ui.tscn                  # UI 层
│   │   └── game_over.tscn           # 游戏结束场景
│   ├── scripts/
│   │   ├── main.gd                  # 主场景逻辑
│   │   ├── player.gd                # 玩家控制（参数从 config 读取）
│   │   ├── enemy_base.gd            # 敌人基类
│   │   ├── enemy_walking.gd         # 行走敌人
│   │   ├── enemy_flying.gd          # 飞行敌人
│   │   ├── collectible.gd           # 收集物逻辑
│   │   ├── platform_moving.gd       # 移动平台
│   │   ├── platform_breakable.gd    # 可碎平台
│   │   ├── camera_follow.gd         # 相机跟随
│   │   ├── game_manager.gd          # 游戏状态管理（读取 config.json）
│   │   ├── ui_manager.gd            # UI 更新
│   │   └── config_loader.gd         # config.json 加载器
│   ├── assets/
│   │   ├── placeholder/             # 占位素材
│   │   │   ├── player_placeholder.png
│   │   │   ├── enemy_placeholder.png
│   │   │   ├── platform_tile.png
│   │   │   └── coin_placeholder.png
│   │   └── .gitkeep
│   └── README.md                    # 模板使用说明
│
└── _shared/                         # 模板间共享资源
    ├── scripts/
    │   ├── config_loader_base.gd    # 配置加载基类
    │   └── scene_transition.gd      # 场景切换工具
    └── shaders/
        └── .gitkeep
```

## 3. config.json 定义

### 3.1 平台跳跃模板 config.json

```json
{
  "template": "platformer",
  "version": "1.0.0",

  "game": {
    "title": "My Platformer",
    "description": "",
    "difficulty": "normal"
  },

  "player": {
    "speed": 300,
    "jump_force": -400,
    "max_health": 3,
    "start_position": { "x": 100, "y": 300 },
    "can_double_jump": false,
    "can_wall_jump": false,
    "sprite_asset": null
  },

  "camera": {
    "zoom": 1.0,
    "smooth_speed": 5.0,
    "limit_left": 0,
    "limit_right": 3000,
    "limit_top": -500,
    "limit_bottom": 800
  },

  "physics": {
    "gravity": 980,
    "friction": 0.1,
    "bounce": 0.0
  },

  "level": {
    "width": 3000,
    "height": 800,
    "background_color": "#87CEEB",
    "background_asset": null,
    "ground_y": 700,
    "platforms": [
      { "x": 300, "y": 500, "width": 200, "type": "static" },
      { "x": 600, "y": 400, "width": 150, "type": "static" },
      { "x": 900, "y": 300, "width": 100, "type": "moving", "move_range": 200, "move_speed": 50 }
    ]
  },

  "enemies": [
    { "type": "walking", "x": 500, "y": 680, "speed": 80, "patrol_range": 200, "health": 1, "sprite_asset": null },
    { "type": "flying", "x": 800, "y": 350, "speed": 60, "fly_range": 150, "health": 1, "sprite_asset": null }
  ],

  "collectibles": [
    { "type": "coin", "x": 350, "y": 450, "value": 1, "sprite_asset": null },
    { "type": "coin", "x": 650, "y": 350, "value": 1, "sprite_asset": null }
  ],

  "win_condition": {
    "type": "reach_goal",
    "goal_position": { "x": 2800, "y": 600 }
  },

  "lose_condition": {
    "type": "health_zero"
  },

  "audio": {
    "bgm_asset": null,
    "sfx_jump": null,
    "sfx_coin": null,
    "sfx_hurt": null,
    "sfx_win": null
  },

  "style": {
    "style_seed": null,
    "color_palette": "default"
  }
}
```

### 3.2 config.schema.json (关键部分)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["template", "version", "player", "level"],
  "properties": {
    "template": { "type": "string", "enum": ["platformer"] },
    "player": {
      "type": "object",
      "properties": {
        "speed": { "type": "number", "minimum": 50, "maximum": 1000 },
        "jump_force": { "type": "number", "minimum": -800, "maximum": -100 },
        "max_health": { "type": "integer", "minimum": 1, "maximum": 20 },
        "start_position": {
          "type": "object",
          "properties": {
            "x": { "type": "number" },
            "y": { "type": "number" }
          }
        }
      }
    },
    "level": {
      "type": "object",
      "properties": {
        "width": { "type": "number", "minimum": 800, "maximum": 20000 },
        "platforms": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["x", "y", "width", "type"],
            "properties": {
              "type": { "type": "string", "enum": ["static", "moving", "breakable"] }
            }
          }
        }
      }
    },
    "enemies": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["type", "x", "y"],
        "properties": {
          "type": { "type": "string", "enum": ["walking", "flying", "stationary"] }
        }
      }
    }
  }
}
```

## 4. 模板骨架场景树

```
Main (Node2D) [main.gd]
├── TPL_GameManager (Node) [game_manager.gd]    # 不可删除
├── TPL_Background (ParallaxBackground)
│   └── ParallaxLayer
│       └── ColorRect / TextureRect
├── TPL_World (Node2D)
│   ├── TPL_Ground (StaticBody2D)               # 不可删除
│   │   ├── CollisionShape2D
│   │   └── Sprite2D
│   ├── Platforms (Node2D)                       # AI 可添加子节点
│   ├── Enemies (Node2D)                         # AI 可添加子节点
│   ├── Collectibles (Node2D)                    # AI 可添加子节点
│   └── Obstacles (Node2D)                       # AI 可添加子节点
├── Player (CharacterBody2D) [player.gd]         # AI 可修改参数
│   ├── CollisionShape2D
│   ├── Sprite2D
│   └── AnimationPlayer
├── TPL_Camera (Camera2D) [camera_follow.gd]     # 不可删除
├── TPL_UI (CanvasLayer) [ui_manager.gd]         # 不可删除
│   ├── ScoreLabel
│   ├── HealthBar
│   └── GameOverPanel (hidden)
└── GoalArea (Area2D)
    └── CollisionShape2D
```

**命名规范**：
- `TPL_` 前缀：模板骨架节点，AI 不得删除/重命名
- 无前缀：AI 可自由修改/删除
- 容器节点（Platforms/Enemies/Collectibles/Obstacles）：AI 在其下添加子节点

## 5. Level 3 MCP 工具

### 5.1 apply_template

```typescript
{
  name: 'apply_template',
  level: 3,
  description: 'Initialize a new game project from a template. Copies template files to the project directory and applies config.json.',
  parameters: {
    type: 'object',
    required: ['template_type'],
    properties: {
      template_type: { type: 'string', enum: ['platformer'] },
      config_overrides: {
        type: 'object',
        description: 'Partial config.json to merge with defaults'
      }
    }
  }
}

// 执行流程：
// 1. 复制模板文件到容器 /project/
// 2. 合并 config_overrides 到 config.json
// 3. 运行 godot --headless --import 导入资源
// 4. 返回项目结构和可修改参数列表
```

### 5.2 configure_template

```typescript
{
  name: 'configure_template',
  level: 3,
  description: 'Modify template config.json parameters. Validates against schema and regenerates the scene.',
  parameters: {
    type: 'object',
    required: ['changes'],
    properties: {
      changes: {
        type: 'object',
        description: 'Partial config.json with values to change (deep merge)'
      }
    }
  }
}

// 执行流程：
// 1. 读取当前 config.json
// 2. Deep merge changes
// 3. 校验 schema
// 4. 写入 config.json
// 5. 调用 game_manager.gd 的 reload_config() 重新生成场景
// 6. 返回变更摘要
```

### 5.3 get_template_info

```typescript
{
  name: 'get_template_info',
  level: 3,
  description: 'Get information about available templates and their configurable parameters.',
  parameters: {
    type: 'object',
    properties: {
      template_type: { type: 'string', description: 'Specific template to query, or omit for all' }
    }
  }
}

// 返回模板列表、每个模板的可配参数 Schema、示例 config
```

## 6. game_manager.gd 核心逻辑

```gdscript
# scripts/game_manager.gd
extends Node

var config: Dictionary = {}

func _ready():
    load_config()
    build_level()

func load_config():
    var file = FileAccess.open("res://config.json", FileAccess.READ)
    if file:
        var json = JSON.new()
        json.parse(file.get_as_text())
        config = json.data
        file.close()

func build_level():
    # 根据 config 生成关卡内容
    _setup_player()
    _setup_platforms()
    _setup_enemies()
    _setup_collectibles()
    _setup_goal()

func _setup_player():
    var player = get_node("/root/Main/Player")
    var pc = config.get("player", {})
    player.position = Vector2(pc.get("start_position", {}).get("x", 100),
                              pc.get("start_position", {}).get("y", 300))
    player.speed = pc.get("speed", 300)
    player.jump_force = pc.get("jump_force", -400)

func _setup_platforms():
    var container = get_node("/root/Main/TPL_World/Platforms")
    # 清除已有动态平台
    for child in container.get_children():
        child.queue_free()
    # 根据 config 创建平台
    for p_data in config.get("level", {}).get("platforms", []):
        var platform = _create_platform(p_data)
        container.add_child(platform)

func _create_platform(data: Dictionary) -> StaticBody2D:
    var platform = StaticBody2D.new()
    platform.position = Vector2(data.get("x", 0), data.get("y", 0))
    var collision = CollisionShape2D.new()
    var shape = RectangleShape2D.new()
    shape.size = Vector2(data.get("width", 100), 20)
    collision.shape = shape
    platform.add_child(collision)
    # 视觉表现
    var sprite = ColorRect.new()
    sprite.size = Vector2(data.get("width", 100), 20)
    sprite.position = Vector2(-data.get("width", 100) / 2, -10)
    sprite.color = Color("#8B4513")
    platform.add_child(sprite)
    # 移动平台逻辑
    if data.get("type") == "moving":
        var tween = platform.create_tween().set_loops()
        var range_val = data.get("move_range", 100)
        var speed_val = data.get("move_speed", 50)
        var duration = range_val / speed_val
        tween.tween_property(platform, "position:y", platform.position.y - range_val, duration)
        tween.tween_property(platform, "position:y", platform.position.y, duration)
    return platform

func _setup_enemies():
    var container = get_node("/root/Main/TPL_World/Enemies")
    for child in container.get_children():
        child.queue_free()
    for e_data in config.get("enemies", []):
        var enemy = _create_enemy(e_data)
        container.add_child(enemy)

func _create_enemy(data: Dictionary) -> CharacterBody2D:
    # 根据 type 实例化不同敌人
    var enemy = CharacterBody2D.new()
    enemy.position = Vector2(data.get("x", 0), data.get("y", 0))
    # ... CollisionShape, Sprite, Script
    return enemy

func _setup_collectibles():
    var container = get_node("/root/Main/TPL_World/Collectibles")
    for child in container.get_children():
        child.queue_free()
    for c_data in config.get("collectibles", []):
        var item = _create_collectible(c_data)
        container.add_child(item)

func _create_collectible(data: Dictionary) -> Area2D:
    var item = Area2D.new()
    item.position = Vector2(data.get("x", 0), data.get("y", 0))
    # ... CollisionShape, Sprite, value
    return item

func _setup_goal():
    var goal = get_node("/root/Main/GoalArea")
    var wc = config.get("win_condition", {})
    if wc.get("type") == "reach_goal":
        var pos = wc.get("goal_position", {})
        goal.position = Vector2(pos.get("x", 2800), pos.get("y", 600))

func reload_config():
    load_config()
    build_level()
```

## 7. AI 与模板的交互流程

```
用户: "做一个简单的平台跳跃游戏，角色跑得快一点，加几个飞行敌人"

AI 执行步骤:
1. apply_template(template_type="platformer")
2. configure_template(changes={
     "player": { "speed": 500 },
     "enemies": [
       { "type": "flying", "x": 500, "y": 300, "speed": 80, "fly_range": 200 },
       { "type": "flying", "x": 900, "y": 250, "speed": 100, "fly_range": 150 }
     ]
   })
3. get_screenshot()  // 验证
4. search_asset(query="cartoon character sprite", type="2d")
5. apply_asset(node_path="/root/Main/Player/Sprite", asset_id="...")
6. get_screenshot()  // 最终验证

总步骤: 6 步 (vs 底层工具 20+ 步)
```

## 8. 验收标准

1. **模板初始化**：apply_template("platformer") 后游戏可运行，角色可移动和跳跃
2. **config 修改**：configure_template 修改 player.speed → 游戏中角色速度变化
3. **平台生成**：config 中添加 platform → 场景中出现对应平台
4. **敌人生成**：config 中添加 enemy → 场景中出现带巡逻逻辑的敌人
5. **收集物**：config 中添加 collectible → 可拾取，分数增加
6. **胜利条件**：角色到达 goal_position → 触发胜利
7. **Schema 校验**：无效参数（如 speed=-1）被拒绝并返回错误信息
8. **TPL_ 保护**：尝试删除 TPL_ 节点时返回错误
9. **截图验证**：apply_template 后 get_screenshot 返回有意义的游戏画面
10. **AI 端到端**：Claude 能通过 6~10 步完成一个定制化平台跳跃游戏
