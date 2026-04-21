# Robot — Backend API 全量测试机器人

> 目录：`Robot/` | 语言：Go | 模块路径：`robot` (本地模块) | 版本：v0.0.4

---

## 1. 概述

Robot 是一个纯 Go 编写的命令行测试工具，用于对 GameMaker Backend 进行全量 API 验收测试。它不是 Godot 引擎模块，与 Engine/、MCP/ 无依赖关系，属于独立的测试基础设施。

**使用场景：**

- 部署后的冒烟验收：验证 Backend 服务在目标环境（Ubuntu 测试机）上的所有公开 API 是否符合预期
- 回归测试：每次 Backend 迭代后，在 10.10.8.32:18081 上跑全套用例，确认无回归
- CI 集成：可编译为 Linux 二进制并在流水线中直接运行，退出码 0/1 表示通过/失败

**特性：**

- 全流程串行执行（49 个测试步骤），覆盖注册 → 登录 → 游戏 → Session → SSE → 导出 → 资产搜索全链路
- 使用 Unix 时间戳生成唯一测试账号，避免重复注册冲突，测试结束自动清理资源
- 对外部服务不可用（Docker 容器、Export 服务、Claude API）的步骤支持 WARN 降级，不中断整体运行
- 唯一第三方依赖：`gopkg.in/yaml.v3`（配置解析）；HTTP 客户端使用 Go 标准库

---

## 2. 架构设计

### 2.1 目录结构

```
Robot/
├── go.mod                      # module robot, go 1.21
├── go.sum
├── robot.yaml.example          # 配置模板（提交到仓库）
├── main.go                     # 入口：flag 解析 + 配置加载 + Suite 运行
├── config/
│   └── config.go               # Config 结构体 + LoadConfig() + DefaultConfig()
├── client/
│   └── client.go               # HTTP 客户端封装（Do/DoRaw/DoSSE/GetJSON）
└── suite/
    ├── suite.go                 # Suite 结构体 + step() + Run() + 汇总输出
    ├── health.go                # REQ-010, REQ-011
    ├── auth.go                  # REQ-020 ~ REQ-026
    ├── games.go                 # REQ-030 ~ REQ-039
    ├── sessions.go              # REQ-040 ~ REQ-049（基础 Session 流程）
    ├── sessions_advanced.go     # REQ-050 ~ REQ-062（SSE 能力 Token + 生命周期）
    ├── exports.go               # REQ-070 ~ REQ-073
    ├── assets.go                # REQ-080 ~ REQ-081
    └── cleanup.go               # Cleanup/DeleteSession2 + Cleanup/DeleteGame
```

### 2.2 模块职责

| 包 | 职责 |
|----|------|
| `config` | 配置加载；从 YAML 文件读取，缺文件时使用内置默认值；CLI flag 覆盖在 main.go 中完成 |
| `client` | HTTP 请求封装；统一处理 JSON 序列化、Authorization 头注入、SSE 短连接；提供 `GetJSON` 的简易 dot-notation 路径提取 |
| `suite` | 测试套件；持有跨步骤共享的运行时状态（token、gameID、sessionID 等）；通过 `step()` 统一记录 PASS / FAIL / WARN |

---

## 3. 核心流程

### 3.1 运行方式

```bash
# 使用默认配置（目标 http://10.10.8.32:18081）
cd Robot/
go run ./main.go

# 指定目标地址（flag 优先级高于配置文件）
go run ./main.go --base-url http://10.10.8.32:18081

# 指定配置文件
go run ./main.go --config ./robot.yaml

# 编译后运行
go build -o robot .
./robot --base-url http://10.10.8.32:18081

# 交叉编译 Linux 二进制（Windows 开发机）
GOOS=linux GOARCH=amd64 go build -o robot-linux .
scp robot-linux admin@10.10.8.32:/tmp/
ssh admin@10.10.8.32 /tmp/robot-linux
```

### 3.2 配置

配置文件路径默认为 `robot.yaml`（若不存在则使用内置默认值）。

```yaml
# robot.yaml.example
base_url: "http://10.10.8.32:18081"   # Backend API base URL
timeout_seconds: 60                     # 每请求超时（Chat 调用 Claude API，需 ~60s）
email_prefix: "robot"                   # 测试账号前缀，完整格式: <prefix>-<ts>@<domain>
email_domain: "test.local"
```

`robot.yaml` 已加入 `.gitignore`，不提交真实配置；仓库中只提交 `robot.yaml.example`。

### 3.3 执行顺序

`Suite.Run()` 按以下顺序串行调用各分组：

```
1. RunHealth()          — Health/Liveness, Health/Readiness
2. RunAuth()            — 注册两个用户 + 登录验证（填充 token/token2/email）
3. RunGames()           — 游戏 CRUD + 生成 + 权限检查（填充 gameID）
4. RunSessions()        — 基础流程 + SSE Token + 生命周期（填充 sessionID/capToken）
5. RunExports()         — 导出任务创建与状态查询（使用 gameID）
6. RunAssets()          — 资产搜索（无状态依赖）
7. RunCleanup()         — 删除 session2、删除 game（WARN 降级，不影响退出码）
```

注意：`Games/Delete`（REQ-034）在 `RunGames()` 末尾作为正式测试步骤执行，Cleanup 阶段的 `DeleteGame` 是幂等清理（若 RunGames 已通过则 204 幂等成功）。

### 3.4 输出格式

```
=== GameMaker Robot Test Suite ===
Target: http://10.10.8.32:18081

[PASS] Health/Liveness (3ms)
[PASS] Auth/Register (45ms)
[FAIL] Games/Create: got 503, want 201 (12ms)
[WARN] Games/Get: gameID empty (Games/Create degraded), skipping (0ms)
...

Results: 45 passed, 1 failed, 3 warned, 49 total
```

有任意 FAIL 时以退出码 1 退出；WARN 不计入失败数。

---

## 4. 关键文件索引

| 文件 | 职责说明 |
|------|---------|
| `main.go` | 解析 `--config` / `--base-url` CLI flag；加载配置；创建 `client.Client` 和 `suite.Suite`；调用 `Run()`；按失败数决定 `os.Exit` 退出码 |
| `config/config.go` | `Config` 结构体（BaseURL/TimeoutSeconds/EmailPrefix/EmailDomain）；`DefaultConfig()` 返回默认值（目标 10.10.8.32:18081）；`LoadConfig(path)` 读取 YAML 并合并默认值，文件不存在时静默返回默认值 |
| `client/client.go` | `Client` 结构体；`Do()` 自动附加 JWT Bearer Token；`DoRaw()` 不附加 Token（用于负向鉴权测试）；`DoSSE()` 建立 2 秒短连接 SSE 请求（非 200 直接读 body 返回，200 读第一行后断开）；`GetJSON()` 基于 `encoding/json` 的 dot-notation 路径提取，无第三方依赖 |
| `suite/suite.go` | `Suite` 结构体（含 token/token2/gameID/sessionID/sessionID2/capToken/capToken2/exportID/email/ts 等共享状态）；`step()` 辅助方法（统一 PASS/FAIL/WARN 记录与打印）；`skip()` 用于前置依赖缺失时快速跳过；`Run()` 调度全部分组并输出汇总 |
| `suite/health.go` | `RunHealth()`：GET /health（REQ-010）、GET /readyz（REQ-011） |
| `suite/auth.go` | `RunAuth()`：注册主用户和第二用户（REQ-020）、重复注册（REQ-021）、邮箱登录（REQ-022）、错误密码（REQ-023）、GetMe（REQ-024/025）、AssetManager 字段验证（REQ-026） |
| `suite/games.go` | `RunGames()`：创建（REQ-030）、无 Token 创建（REQ-031）、列表（REQ-032）、获取（REQ-033）、触发生成（REQ-035）、生成状态（REQ-036）、封面重生成 422（REQ-037）、非 Owner 403（REQ-038）、game_id 格式验证（REQ-039）、删除（REQ-034） |
| `suite/sessions.go` | `runSessionsBasic()`（由 `RunSessions()` 调用）：创建 Session（REQ-040）、列表（REQ-041）、获取（REQ-042）、发送消息（REQ-043）、历史记录（REQ-044）、触发构建（REQ-045）、构建状态（REQ-046）、取消构建（REQ-047）、game-spec 404（REQ-048）、game-plan 404（REQ-049） |
| `suite/sessions_advanced.go` | `runSessionsAdvanced()`（由 `RunSessions()` 调用）：SSE 有效 Token（REQ-050）、无 Token 401（REQ-051）、无效 Token 401（REQ-052）、Token 刷新（REQ-053）、旧 Token 吊销（REQ-054）、跨 Session Token 失配 403（REQ-055）、Resume 409（REQ-056）、非 Owner Rehydrate 403（REQ-057）、不存在 Session Rehydrate 404（REQ-058）、删除（REQ-059）、幂等删除（REQ-060）、删除后 Rehydrate 409（REQ-061）、删除后 Token Refresh 409（REQ-062） |
| `suite/exports.go` | `RunExports()`：创建导出任务 html5（REQ-070）、查询导出状态（REQ-071）、下载端点 404（REQ-072）、游玩端点 404（REQ-073） |
| `suite/assets.go` | `RunAssets()`：资产搜索（REQ-080）、资产详情（REQ-081）——仅验证不返回 5xx |
| `suite/cleanup.go` | `RunCleanup()`：删除 session2（使用 token2）、删除 game；失败仅 WARN，不计入失败数 |
| `robot.yaml.example` | 配置模板；包含 base_url/timeout_seconds/email_prefix/email_domain 四个字段 |

---

## 5. 测试套件覆盖范围

### 5.1 覆盖端点汇总

| 分类 | 端点 | 测试名称 | 优先级 |
|------|------|---------|--------|
| **健康检查** | GET /health | Health/Liveness | P0 |
| | GET /readyz | Health/Readiness | P0 |
| **认证** | POST /api/v1/auth/register | Auth/Register, Auth/RegisterDuplicate | P0 |
| | POST /api/v1/auth/login/email | Auth/LoginEmail, Auth/LoginEmailWrongPassword | P0 |
| | GET /api/v1/auth/me | Auth/GetMe, Auth/GetMeNoToken, Auth/AssetManagerUIDType | P0/P1 |
| **游戏** | POST /api/v1/games | Games/Create, Games/CreateNoToken | P0 |
| | GET /api/v1/games | Games/List | P0 |
| | GET /api/v1/games/:id | Games/Get | P0 |
| | DELETE /api/v1/games/:id | Games/Delete | P0 |
| | POST /api/v1/games/:id/generate | Games/Generate | P1 |
| | GET /api/v1/games/:id/generate/status | Games/GenerateStatus | P1 |
| | POST /api/v1/games/:id/cover-regenerate | Games/CoverRegenerate422, Games/CoverRegenerate403 | P1 |
| **Session** | POST /api/v1/sessions | Sessions/Create | P0 |
| | GET /api/v1/sessions | Sessions/List | P0 |
| | GET /api/v1/sessions/:id | Sessions/Get | P0 |
| | POST /api/v1/sessions/:id/chat | Sessions/Chat | P0 |
| | GET /api/v1/sessions/:id/history | Sessions/History | P0 |
| | POST /api/v1/sessions/:id/build | Sessions/Build | P1 |
| | GET /api/v1/sessions/:id/build-status | Sessions/BuildStatus | P1 |
| | POST /api/v1/sessions/:id/build/cancel | Sessions/CancelBuild | P1 |
| | GET /api/v1/sessions/:id/game-spec | Sessions/GameSpec404 | P1 |
| | GET /api/v1/sessions/:id/game-plan | Sessions/GamePlan404 | P1 |
| | GET /api/v1/sessions/:id/events | Sessions/EventsValidToken/MissingToken/InvalidToken/RevokedToken/SessionMismatch | P0/P1 |
| | POST /api/v1/sessions/:id/events/token/refresh | Sessions/EventsTokenRefresh, Sessions/TokenRefreshAfterDelete409 | P1 |
| | POST /api/v1/sessions/:id/resume | Sessions/Resume409 | P1 |
| | POST /api/v1/sessions/:id/rehydrate | Sessions/RehydrateNonOwner/NotFound/AfterDelete409 | P1 |
| | DELETE /api/v1/sessions/:id | Sessions/Delete, Sessions/DeleteIdempotent | P0/P1 |
| **导出** | POST /api/v1/games/:id/export | Exports/Create | P1 |
| | GET /api/v1/exports/:id | Exports/GetStatus | P1 |
| | GET /api/v1/exports/:id/download | Exports/DownloadNotFound | P2 |
| | GET /api/v1/exports/:id/play | Exports/PlayNotFound | P2 |
| **资产** | GET /api/v1/assets/search | Assets/Search | P2 |
| | GET /api/v1/assets/:id | Assets/GetByID | P2 |

总计：49 个测试步骤（含 2 个 Cleanup 步骤）。

### 5.2 状态依赖链

```
Auth/Register（填充 token / token2 / email）
  └── Games/Create（填充 gameID）
        ├── Sessions/Create（填充 sessionID / capToken）
        │     ├── Sessions/Chat（依赖 sessionID）
        │     │     └── Sessions/Build（依赖 sessionID，需 Chat 先完成）
        │     └── Sessions/EventsTokenRefresh → Sessions/EventsRevokedToken
        │           └── Sessions/EventsSessionMismatch（创建 sessionID2 / capToken2）
        └── Exports/Create（依赖 gameID）
```

---

## 6. 关键设计说明

### 6.1 JSON 路径提取

`client.GetJSON()` 使用 `encoding/json` 反序列化为 `map[string]any` 后按 `.` 分段遍历，支持形如 `$.data.token`、`$.error.code` 的路径。不依赖第三方 jsonpath 库。

大多数成功响应格式为 `{"data": {...}}`；SSE 鉴权失败响应格式为 `{"error": {"code": "...", "message": "..."}}`，路径为 `$.error.code`（非 `$.code`）。

### 6.2 SSE 短连接验证

`DoSSE()` 使用独立的 2 秒超时 `http.Client`，不携带 Authorization 头（SSE 端点使用 `?token=` query string 鉴权）。非 200 时直接读取 body 返回 JSON；200 时读取第一个非空 SSE 行后立即断开连接。

`DoSSE()` 适用场景：REQ-050（有效 Token）、REQ-052（无效 Token）、REQ-054（被吊销 Token）、REQ-055（跨 Session 失配）。  
REQ-051（缺少 `?token=` 参数）使用普通 `Do()`，因为该请求不携带 token 参数、不走 SSE 路径。

### 6.3 CoverRegenerate 422 响应格式

`cover_regenerate_handler.go` 使用裸 `c.JSON(422, gin.H{"error": "no project_dir on game"})` 而非统一的 `RespondError()`，响应中 `$.error` 是顶层字符串，不是 `{"code":"..."}` 嵌套对象。Robot 对此只做存在性检查（`ok && value != nil`），不检查 `$.error.code`。

### 6.4 WARN 降级机制

以下场景会产生 WARN 而不是 FAIL：

- 步骤前置状态缺失（如 gameID 为空，说明 Games/Create 已降级）
- 外部服务不可用：Sessions/Create 或 Sessions/Build 返回 500/503（Docker 不可用）；Exports/Create 返回 500/503（Export 服务不可用）；Sessions/Chat 返回 500/503/504（Claude API 不可用）
- `Games/AssetManagerGameID` 中 `$.data.game_id` 字段不存在（counterRepo 未配置）

WARN 步骤不计入失败数，不影响退出码。

---

## 7. 注意事项

### 7.1 环境依赖

Robot 依赖 Backend 服务完整运行，具体要求：

- Backend 可访问于 `base_url`（默认 `http://10.10.8.32:18081`）
- 认证模式：JWT email/password（`auth.mode=jwt`）
- MongoDB 和 Redis 正常运行（注册/登录/Session 全链路需要）
- Docker 容器服务可用时，Sessions/Build 系列测试才能通过（不可用时降级为 WARN）
- Claude API 可访问时，Sessions/Chat 测试才能通过（不可用时降级为 WARN）

### 7.2 测试隔离

每次运行使用 Unix 时间戳生成唯一邮箱：

```go
email  = fmt.Sprintf("%s-%d@%s",   cfg.EmailPrefix, ts, cfg.EmailDomain)  // 主用户
email2 = fmt.Sprintf("%s-b%d@%s",  cfg.EmailPrefix, ts, cfg.EmailDomain)  // 第二用户
```

两次运行间隔 >= 1 秒即可避免冲突（REQ-004）。清理顺序：先删 session（含 session2），再删 game，避免孤儿数据。

### 7.3 go.mod 模块路径

`go.mod` 声明为本地模块名 `robot`（非完整 URL 路径）：

```
module robot
go 1.21
require gopkg.in/yaml.v3 v3.0.1
```

这是与 feature.md 规范文档中 `github.com/gamemaker/robot` 的实际差异，以代码中的 `go.mod` 为准。

### 7.4 已知限制

| 限制 | 说明 |
|------|------|
| 串行执行 | 所有步骤顺序串行（有状态依赖），不支持并行 |
| 无覆盖 Cover 409 场景 | REQ-037 变体（cover-regenerate 冲突 409）需要 project_dir 已设置，全量跑测中标记为 P2 可选 |
| SSE 长连接不验证 | 仅做短连接状态码验证，不验证 SSE 事件内容和格式 |
| 无 RBAC 端点覆盖 | 当前 Backend 无 admin 端点，Robot 不包含 admin 测试用例 |
| Export 产物不验证 | REQ-072/073 只验证假 ID 返回 404，不验证真实导出产物的可下载性 |

---

## 8. 版本历史

| 版本 | 内容 |
|------|------|
| v0.0.4 | 初始实现；覆盖 REQ-001 ~ REQ-081；支持 WARN 降级；task-01 ~ task-12 全部完成 |
