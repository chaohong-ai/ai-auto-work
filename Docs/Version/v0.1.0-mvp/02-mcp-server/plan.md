# 02-MCP Server 技术规格

## 1. 概述

基于 tugcantopaloglu/godot-mcp 二次开发 MCP Server，提供 Godot 引擎操作的 HTTP API 接口，供 Go 后端调用。MCP Server 本身是 TypeScript 独立进程，通过 TCP 与 Godot Headless 通信，通过 HTTP REST 与 Go 后端通信。

**范围**：
- Fork godot-mcp，精简并重构为三层工具架构
- 暴露 HTTP REST API（Go 后端调用入口）
- 维护 MCP Session（每个用户生成任务对应一个 session）
- 实现 MCP Resources（AI 可读取的引擎状态）

**不做**：
- AI 调用逻辑（在 07-backend-api 中 Go 侧完成）
- 语义工具封装（在 03-semantic-tools 中完成）

## 2. 架构

```
Go Backend ──HTTP REST──→ MCP Server (TS) ──TCP──→ Godot Headless
                              │
                              ├── Session Manager
                              ├── Tool Registry (Level 0/1/2/3)
                              └── Resource Provider
```

### 通信协议

| 路径 | 协议 | 说明 |
|------|------|------|
| Go → MCP Server | HTTP REST (JSON) | Go 调用 MCP 工具 / 读取资源 |
| MCP Server → Godot | TCP (JSON-RPC) | 沿用 godot-mcp 原有协议 |
| MCP Server ← Godot | TCP (JSON-RPC) | Godot 事件回调（日志/错误） |

## 3. 文件清单

```
MCP/
├── package.json
├── tsconfig.json
├── .env.example                  # 配置模板
├── src/
│   ├── index.ts                  # 入口，启动 HTTP 服务
│   ├── config.ts                 # 环境变量配置
│   ├── server/
│   │   ├── http-server.ts        # Express HTTP 服务（Go 调用入口）
│   │   └── routes.ts             # HTTP 路由定义
│   ├── session/
│   │   ├── session-manager.ts    # Session 生命周期管理
│   │   └── session.ts            # 单个 Session 实体
│   ├── godot/
│   │   ├── godot-connection.ts   # TCP 连接管理（复用 godot-mcp）
│   │   ├── godot-rpc.ts          # JSON-RPC 协议封装
│   │   └── godot-events.ts       # Godot 事件监听
│   ├── tools/
│   │   ├── tool-registry.ts      # 工具注册中心
│   │   ├── level0/               # 底层 Godot API（内部使用）
│   │   │   └── (从 godot-mcp 迁移)
│   │   ├── level1/               # 引擎操作层（AI 自修复用）
│   │   │   ├── create-node.ts
│   │   │   ├── set-property.ts
│   │   │   ├── add-script.ts
│   │   │   └── ...
│   │   ├── level2/               # 游戏语义层（核心，见 03-semantic-tools）
│   │   │   └── (由 03 模块填充)
│   │   └── level3/               # 模板操作层（最高语义）
│   │       └── (由 04-game-templates 填充)
│   ├── resources/
│   │   ├── resource-provider.ts  # MCP Resources 实现
│   │   ├── scene-tree.ts         # 场景树资源
│   │   ├── project-structure.ts  # 项目结构资源
│   │   └── game-log.ts           # 运行日志资源
│   └── utils/
│       ├── logger.ts
│       └── errors.ts
└── tests/
    ├── http-server.test.ts
    ├── session-manager.test.ts
    └── tool-registry.test.ts
```

## 4. HTTP REST API 定义

### 4.1 Session 管理

```
POST   /api/sessions
  Body: { "container_id": "xxx", "godot_host": "172.17.0.2", "godot_port": 6005 }
  Response: { "session_id": "uuid", "status": "connected" }

DELETE /api/sessions/:session_id
  Response: { "status": "closed" }

GET    /api/sessions/:session_id
  Response: { "session_id": "uuid", "status": "connected", "created_at": "...", "tool_call_count": 12 }
```

### 4.2 工具调用

```
POST   /api/sessions/:session_id/tools/call
  Body: {
    "tool_name": "add_player",
    "arguments": {
      "position": { "x": 100, "y": 200 },
      "speed": 300
    }
  }
  Response: {
    "status": "success",
    "result": {
      "node_path": "/root/Main/Player",
      "message": "Player added at (100, 200)"
    },
    "suggestions": ["Use set_camera_follow() to attach camera"]
  }

GET    /api/sessions/:session_id/tools
  Query: ?level=2,3 (可选，筛选层级)
  Response: {
    "tools": [
      {
        "name": "add_player",
        "level": 2,
        "description": "Add a player character to the scene",
        "parameters": { ... JSON Schema ... }
      }
    ]
  }
```

### 4.3 资源读取

```
GET    /api/sessions/:session_id/resources/:resource_uri
  Examples:
    /api/sessions/xxx/resources/godot://scene/main/tree
    /api/sessions/xxx/resources/godot://scene/main/preview
    /api/sessions/xxx/resources/godot://project/structure
    /api/sessions/xxx/resources/godot://game/errors
  Response: {
    "uri": "godot://scene/main/tree",
    "content": { ... }   // JSON 或 base64 (截图)
    "mime_type": "application/json"
  }
```

### 4.4 快照管理

```
POST   /api/sessions/:session_id/snapshots
  Body: { "label": "after_adding_enemies" }
  Response: { "snapshot_id": "snap_001", "files": ["main.tscn", "player.gd"] }

POST   /api/sessions/:session_id/snapshots/:snapshot_id/restore
  Response: { "status": "restored" }

GET    /api/sessions/:session_id/snapshots
  Response: { "snapshots": [...] }
```

## 5. Session 管理

### 5.1 Session 生命周期

```
创建 → 连接 Godot TCP → Ready → 执行工具调用 → 空闲超时/主动关闭 → 断开 TCP → 销毁
```

### 5.2 Session 数据结构

```typescript
interface Session {
  id: string;
  containerId: string;         // 关联的 Docker 容器 ID
  godotConnection: GodotConnection;  // TCP 连接
  status: 'connecting' | 'connected' | 'disconnected' | 'error';
  createdAt: Date;
  lastActivityAt: Date;
  toolCallCount: number;
  snapshots: Snapshot[];       // 项目快照列表
}

interface Snapshot {
  id: string;
  label: string;
  createdAt: Date;
  files: Map<string, Buffer>;  // 文件名 → 内容
}
```

### 5.3 超时策略

| 超时类型 | 时长 | 行为 |
|----------|------|------|
| Session 空闲超时 | 5 分钟 | 断开 TCP，标记为 disconnected |
| 单次工具调用超时 | 30 秒 | 返回超时错误 |
| TCP 连接超时 | 10 秒 | 返回连接失败 |

## 6. 工具注册机制

### 6.1 工具定义规范

```typescript
interface ToolDefinition {
  name: string;
  level: 0 | 1 | 2 | 3;
  description: string;         // AI 可读的描述
  parameters: JSONSchema;      // 参数 JSON Schema
  returns: JSONSchema;         // 返回值 JSON Schema
  examples: ToolExample[];     // 使用示例
  tags: string[];              // 分类标签
}

interface ToolExample {
  description: string;
  arguments: Record<string, any>;
  expected_result: Record<string, any>;
}
```

### 6.2 渐进式发现

```typescript
// 初始加载 Level 2 + Level 3
// AI 请求 Level 1 工具时动态加载
class ToolRegistry {
  getTools(levels: number[]): ToolDefinition[];
  callTool(name: string, args: Record<string, any>): Promise<ToolResult>;
  loadLevel(level: number): void;
}
```

## 7. MCP Resources 实现

| Resource URI | 返回内容 | 用途 |
|-------------|---------|------|
| `godot://project/structure` | 项目文件列表 JSON | AI 了解项目结构 |
| `godot://scene/{name}/tree` | 场景节点树 JSON | AI 了解当前场景 |
| `godot://scene/{name}/preview` | 截图 base64 | AI 视觉验证 |
| `godot://node/{path}/properties` | 节点属性列表 | AI 精确修改 |
| `godot://script/{path}/source` | GDScript 源码 | AI 阅读/修改脚本 |
| `godot://game/log` | 最近 100 行运行日志 | AI 排查错误 |
| `godot://game/errors` | 错误列表 | AI 自修复依据 |
| `godot://assets/list` | 当前项目资源清单 | AI 引用已有素材 |

## 8. 配置

```env
# MCP Server 配置
MCP_HTTP_PORT=3100              # HTTP 服务端口
MCP_LOG_LEVEL=info

# Godot 连接默认配置
GODOT_DEFAULT_HOST=127.0.0.1
GODOT_DEFAULT_PORT=6005
GODOT_CONNECT_TIMEOUT=10000     # ms

# Session 配置
SESSION_IDLE_TIMEOUT=300000     # 5 分钟 (ms)
SESSION_MAX_COUNT=20            # 最大并发 session 数
TOOL_CALL_TIMEOUT=30000         # 单次工具调用超时 (ms)
```

## 9. 依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| express | ^4.18 | HTTP 服务 |
| uuid | ^9.0 | Session ID 生成 |
| winston | ^3.11 | 日志 |
| zod | ^3.22 | 参数校验 |
| typescript | ^5.3 | 开发语言 |

## 10. 验收标准

1. **HTTP 服务启动**：`npm start` 后在 3100 端口正常响应
2. **Session 创建**：POST /api/sessions 成功建立 TCP 到 Godot
3. **工具调用**：通过 HTTP 调用 Level 1 工具（create_node），Godot 中实际创建节点
4. **资源读取**：通过 HTTP 读取 scene/tree，返回正确的场景树 JSON
5. **快照保存/恢复**：保存快照后修改场景，恢复后场景回到快照状态
6. **Session 超时**：5 分钟无操作后自动断开
7. **错误处理**：Godot 断连时返回明确错误，不崩溃
8. **工具列表**：GET /tools 返回所有已注册工具及其 JSON Schema
