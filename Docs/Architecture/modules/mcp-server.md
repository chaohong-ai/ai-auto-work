# MCP Server — AI↔引擎桥接层

> 端口：3100 | 目录：`MCP/` | 语言：TypeScript

---

## 1. 选型理由

| 维度 | 选择 | 理由 |
|------|------|------|
| 协议 | **MCP (Model Context Protocol)** | Anthropic 提出的标准化 AI↔工具交互协议，Claude 原生支持 Tool Use |
| 语言 | **TypeScript** | MCP SDK 官方支持最完善、JSON-RPC 处理方便、async/await 适合 I/O 密集场景 |
| 基础 | **tugcantopaloglu/godot-mcp** | 二次开发（149 底层工具 → 30 语义化工具），不从零造轮子 |
| Web 框架 | **Express** | 成熟稳定，Backend 通过 HTTP 调用 MCP 端点 |
| 校验 | **Zod** | 运行时类型校验，确保 AI 生成的工具参数合法 |
| 日志 | **Winston** | 与 Express 生态集成好，结构化 JSON 输出 |

**为什么不用 Go 实现 MCP Server？** MCP SDK 的 TypeScript 实现最完善、社区工具最多；Godot MCP 开源项目均基于 TypeScript/Python；TCP JSON-RPC 通信是 I/O 密集型，TypeScript async/await 在此场景无劣势。

---

## 2. 架构设计

```
MCP/src/
├── server/                      # Express HTTP 服务（Backend 调用入口）
│   ├── http-server.ts           #   中间件：错误处理、请求校验、超时控制
│   └── routes.ts                #   RESTful 端点：/tools/execute, /sessions/*
├── session/                     # 会话管理
│   ├── session-manager.ts       #   创建/销毁 Godot TCP 连接，连接池管理
│   └── session.ts               #   单会话状态：快照栈、工具执行历史
├── tools/                       # 语义化工具系统（核心）
│   ├── tool-registry.ts         #   工具注册、发现、执行分发
│   ├── level0/                  #   底层：文件读写、节点 CRUD（内部使用）
│   ├── level1/                  #   引擎操作层：create_node, set_property, add_script
│   ├── level2/                  #   游戏语义层：add_player, add_enemy, set_win_condition (~30)
│   └── level3/                  #   模板操作层：apply_template, configure_game
├── godot/                       # Godot 通信层
│   ├── godot-connection.ts      #   TCP 连接管理（重连、超时、心跳）
│   ├── godot-rpc.ts             #   JSON-RPC 2.0 协议编解码
│   └── godot-events.ts          #   事件定义（scene_changed, error, screenshot_ready）
└── resources/                   # Godot 资源访问（场景树查询、文件列表）
```

---

## 3. 工具分层设计

```
Layer 3  模板操作（最高语义）     AI 首选
  apply_template(type="platformer", config={...})
  ──────────────────────────────────────────────
Layer 2  游戏语义（~30 工具）     AI 常用
  add_player() / add_enemy() / set_physics() / add_asset()
  ──────────────────────────────────────────────
Layer 1  引擎操作                 AI 修复时使用
  create_node() / set_property() / add_script()
  ──────────────────────────────────────────────
Layer 0  底层 Godot API          MCP 内部，不暴露给 AI
```

**渐进式发现：** 初始只加载 Level 3 + Level 2 工具（~35 个）。AI 遇到复杂需求或修复场景时，动态加载 Level 1。避免一次性加载所有工具消耗上下文窗口。

**工具响应设计：** 每个工具返回执行结果 + 下一步建议（suggestions），引导 AI 高效决策：

```json
{
  "status": "success",
  "node_path": "/root/Main/Enemies/FlyingEnemy_1",
  "suggestions": ["可以用 set_physics() 调整飞行速度", "用 apply_asset() 绑定敌人模型"]
}
```
