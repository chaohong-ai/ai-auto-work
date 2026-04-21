# Engine — Godot 4 游戏引擎

> 端口：6007 (TCP) | 目录：`Engine/` | 技术：Godot 4.3 Headless + GDScript

---

## 1. 选型理由

| 维度 | Godot 4.3 | Unity | Unreal | 浏览器原生 (Three.js) |
|------|-----------|-------|--------|----------------------|
| 开源协议 | **MIT** — 可自由修改、商用、嵌入容器 | 商业授权 + 运行时费用 | 商业授权 | MIT |
| Headless 支持 | **原生支持** `--headless` 模式 | 需购买 Server License | 不支持轻量 Headless | 不适用 |
| 容器化友好度 | **轻量** — 基础镜像 ~200MB | 重量级 ~2GB+ | 极重 | 不适用 |
| 多平台导出 | iOS / Android / Web / Desktop | 同 | 同（Web 弱） | 仅 Web |
| AI 可控性 | **GDScript 文本脚本**，AI 可直接读写 | C# 需编译步骤 | C++ 不适合 AI 生成 | JS 可生成但无引擎能力 |
| MCP 生态 | 已有开源 godot-mcp (149 工具) | 无成熟 MCP 实现 | 无 | 无 |
| 社区活跃度 | 高速增长，4.x 版本月活跃贡献 | 最大但商业化争议 | 专业级 | 分散 |

**结论：** Godot 4 是唯一同时满足「MIT 开源 + 原生 Headless + 轻量容器化 + AI 可控脚本 + 多平台导出」的引擎。

---

## 2. Headless 容器化设计

每个用户 Session 独占一个 Godot 容器实例，容器间完全隔离：

```
Engine/
├── docker/
│   ├── Dockerfile               # Ubuntu 22.04 + Godot 4.3 + Android SDK + xvfb
│   ├── entrypoint.sh            # 容器启动：xvfb + Godot Headless + TCP Server (6007)
│   └── healthcheck.sh           # 健康检查：HTTP :6007/healthz
├── godot/
│   ├── project/                 # 运行时游戏项目骨架
│   └── templates/               # 预置游戏模板
│       ├── platformer/          #   平台跳跃：角色控制/地面检测/相机/关卡
│       ├── shooter/             #   弹幕射击：飞船移动/子弹池/碰撞/分数
│       ├── puzzle/              #   解谜点击：可交互物体/状态机/事件总线
│       └── runner/              #   跑酷：程序化地形/障碍生成/加速曲线
└── container/                   # Go 容器管理接口（Server 调用）
```

---

## 3. 容器生命周期

```
创建 Session ──▶ Docker Create (CPU/Mem 限制)
                    │
                    ▼
              启动 xvfb + Godot Headless
                    │
                    ▼
              TCP Server :6007 就绪 ◀── MCP 连接
                    │
                    ├── 健康检查（每 10s，失败 3 次自动重启）
                    ├── 空闲检测（30 分钟无操作自动回收）
                    └── 快照保存（每组 MCP 操作后 → .tscn → COS/Local）
                    │
                    ▼
              Session 结束 ──▶ 容器销毁 + 资源清理
```

---

## 4. 关键设计

| 设计点 | 说明 |
|--------|------|
| **资源限制** | 每容器 CPU 1 core / 内存 1GB，防止单实例耗尽宿主 |
| **xvfb 虚拟帧缓冲** | Headless 模式下提供虚拟显示，支持截图验证 |
| **模板+增量** | AI 优先修改模板 `config.json` 参数，不碰场景树骨架（成功率 90%+） |
| **脚本策略** | P0: GDScript（AI 生成友好、零编译）→ P1: Luau（差异化壁垒） |
| **gVisor 沙箱** | 生产环境使用 gVisor 增强隔离，防止容器逃逸 |
| **KEDA 扩缩** | 基于 Redis Stream pending 消息数动态调整容器池大小 |

---

## 5. 游戏模板

| 模板类型 | 骨架内容 | AI 可修改的参数 |
|----------|----------|----------------|
| 平台跳跃 | 角色控制/地面检测/相机/死亡重置 | 移速/跳跃力/关卡长度/敌人类型/素材 |
| 弹幕射击 | 飞船移动/子弹池/碰撞/分数 | 射速/敌人波次/Boss配置/道具 |
| 解谜点击 | 可交互物体/状态机/事件总线 | 谜题类型/关卡数/提示系统 |
| 跑酷 | 程序化地形/障碍生成/加速曲线 | 速度曲线/障碍密度/皮肤 |

**关键原则：** AI 优先修改 `config.json`（参数化），不碰场景树骨架。节点命名用统一前缀 `TPL_`，System Prompt 明确标注可改/不可改。

---

## 6. 移动端约束（宪法第六条）

引擎层以中低端移动设备为性能基线：

| 资源类型 | 移动端上限 |
|---------|-----------|
| 纹理尺寸 | ≤1024x1024 |
| 粒子数量 | ≤200 per emitter |
| 同屏节点 | ≤500 |
| 音频码率 | OGG ≤128kbps |
| 目标帧率 | 60fps (2D) / 30fps (3D) |

---

## 7. 游戏客户端网络层

容器中的 Godot 游戏通过 TCP 长连接与 GameServer 的 gate_server 通信。

### 代码位置

```
Engine/godot/project/
├── net/
│   ├── gate_client.gd       # TCP 客户端：连接、鉴权、收发、自动重连
│   ├── packet_codec.gd      # 帧编解码（Big Endian，与 Go 端 common/net/gate/ 对应）
│   └── proto_dispatcher.gd  # cmd → Callable 路由
├── proto/gen/               # Protobuf GDScript 生成文件（纯 GDScript，无 GDExtension）
│   ├── account_pb.gd
│   ├── lobby_pb.gd
│   ├── match_pb.gd
│   ├── room_pb.gd
│   ├── team_pb.gd
│   └── common_pb.gd
└── test/
    ├── test_packet_codec.gd  # 编解码单测
    ├── test_login.gd         # 鉴权 E2E 测试
    └── test_lobby.gd         # 进大厅 E2E 测试
```

### 帧格式

```
[4B Length BE][8B SessionID BE][2B Flag BE][4B Cmd BE][Payload...]
```

- **HEADER_SIZE** = 18 字节（4+8+2+4）
- **Length** = 后续字节数 = 14 + Payload.size()
- **鉴权帧** = Flag=0x0002 + Cmd=0 + Token payload
- **最大包体** = 1MB（服务端限制）

### 连接流程

1. TCP 连接 gate_server
2. 服务端下发 8B SessionID
3. 客户端发送鉴权帧（Flag=0x0002, Cmd=0, Payload=token）
4. 服务端返回确认帧（Cmd=0）→ 进入 AUTHENTICATED 状态
5. 可收发业务 Protobuf 消息

> **详细协议规范和 API 参考** → `Docs/Engine/14-game-networking/networking-guide.md`
