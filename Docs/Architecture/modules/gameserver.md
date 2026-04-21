# GameServer — 实时游戏服务器框架

> 目录：`GameServer/` | 语言：Go | 协议：TCP / KCP + Protobuf | 独立部署，与创作平台 Backend 无运行时耦合

---

## 1. 选型理由

| 维度 | 选择 | 理由 |
|------|------|------|
| 语言 | **Go** | 高并发、低延迟，适合实时游戏后端 |
| 通信 | **TCP / KCP + Protobuf** | 二进制协议，满足实时帧同步需求 |
| 独立部署 | 与创作平台 Backend 分离 | 完全不同的架构模式和流量模型，避免互相影响 |

---

## 2. 服务架构

多进程分布式架构，客户端通过 gate_server 接入，网关将请求路由到对应后端服务：

```
Client (TCP/KCP)
    └─► gate_server (接入网关)
            ├─► account_server  (鉴权与 UID 管理)
            ├─► lobby_server    (大厅：玩家信息、好友、在线状态)
            ├─► team_server     (组队管理)
            ├─► match_server    (匹配与房间分配)
            └─► room_server     (对局：游戏实例运行时)
                      └─► db_server (统一数据读写代理)
```

## 3. 目录结构

```
GameServer/
├── base/           # 基础库（网络、日志、Redis、压缩）
├── common/         # 公共能力（Actor、缓存、配置、FSM、网络、在线状态）
├── servers/        # 各服务器进程
│   ├── account_server/  # 账号鉴权
│   ├── db_server/       # 数据读写代理
│   ├── gate_server/     # TCP/KCP 接入网关
│   ├── lobby_server/    # 大厅
│   ├── match_server/    # 匹配
│   ├── room_server/     # 对局（Actor + Entity-Component + Player FSM）
│   └── team_server/     # 组队
├── proto/          # Protobuf 协议定义
├── gen/            # 生成代码
├── tools/          # 运维与开发工具
└── robots/         # 压测与功能机器人
```

## 4. 核心技术特征

| 特征 | 说明 |
|------|------|
| 并发模型 | Actor 模式，每个 Map 实例为独立 Actor |
| 游戏运行时 | Entity-Component 架构 + Player FSM 状态机 |
| 帧同步 | 全量快照 + 增量差异，可配置更新率 |
| 服务间通信 | 内网 TCP，Protobuf 编码 |
| 数据持久化 | 经 db_server 代理或直连 MongoDB |

## 5. 与创作平台的关系

GameServer 与创作平台（Backend/MCP/Engine/Frontend）**完全独立**：
- 独立的 `go.mod`，不共享 model / repository / service
- 不同的架构模式：创作平台用 Gin + REST，GameServer 用 Actor + Protobuf + TCP
- 不同的并发模型：创作平台用 context + goroutine，GameServer 用 Actor 消息传递
- 开发规范独立：见 `GameServer/CLAUDE.md`（通用入口），各子服务有独立的 `servers/<name>/CLAUDE.md`

## 6. 客户端协议对接

Godot 游戏客户端通过 TCP 长连接与 gate_server 通信，协议实现分布在两端：

| 端 | 位置 | 说明 |
|----|------|------|
| **Go 服务端** | `common/net/gate/` | `TCPCodec` 帧编解码、`Packet` 结构、Flag 常量 |
| **GDScript 客户端** | `Engine/godot/project/net/` | `PacketCodec` 帧编解码、`GateClient` 连接管理 |
| **Protobuf 定义** | `GameServer/proto/*.proto` | 共享消息格式 |
| **GDScript Proto** | `Engine/godot/project/proto/gen/` | 纯 GDScript 的 Protobuf 实现 |

> **完整的客户端网络协议指南** → `Docs/Engine/14-game-networking/networking-guide.md`
