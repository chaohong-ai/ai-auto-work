# 宪法详细规则：跨模块通信

> **作用域：创作平台链路（Frontend ↔ Backend ↔ MCP ↔ Godot）。** 本文件是 `.ai/constitution.md` §7「跨模块通信」的详细展开，仅在涉及跨模块 API 通信时按需加载。
> **不适用于 `GameServer/`**——GameServer 使用 Protobuf + TCP 的服务间通信模型。

## 浏览器原生请求鉴权约束（不可协商）

`<a href download>`、`<iframe src>`、`<img src>`、`EventSource` 这类浏览器原生发起的请求无法附带 `Authorization` 头。若接口需要被这些标签直连，不得放在依赖 `Authorization: Bearer` 的 JWT middleware 保护组内；应使用以下替代之一：（1）Cookie session 鉴权；（2）强随机、短时效、可撤销的签名 URL；（3）服务端生成的不可枚举 capability ID（>=128bit 熵）。典型场景：文件下载、HTML5 iframe 预览、SSE 事件流。禁止用可预测业务 ID（如 `<prefix>_<UnixNano>`）充当 capability URL。

## 跨语言 ToolResponse 契约回归保护（不可协商）

凡涉及跨语言契约变更（例如 MCP TypeScript -> Backend Go 的 `ToolResponse` 字段结构调整），必须同时满足：(a) producer 侧（MCP）补充或更新对应字段的单元测试；(b) **至少一个真实 consumer 回归测试**——即 Go 侧（Backend）断言能正确读取该字段并写入业务状态（如 `sess.LatestScreenshotURL`）。仅在 MCP 侧补单测不足以防止回归，因为 producer 的输出格式与 consumer 的读取路径属于不同语言的独立实现，任何一侧的局部测试都无法捕获跨语言的字段漂移。`get_screenshot` 字段从嵌套 `result.screenshot.url` 漂移至扁平 `result.url` 已造成反复回归，属于系统性盲区。**Plan Review 和 Develop Review 必须核查**：凡本轮修改了 MCP 工具的 `ToolResponse` 结构，testing.md 中是否同时含 producer + consumer 双侧测试用例；缺少任一侧即判 Critical。

## 内部服务间通信鉴权约束（不可协商）

<!-- Context Repair: aippy-research Round6 I-R6-3 — build-worker 回调端点在 Plan 中被隐式假设但未定义，且无鉴权声明 -->
凡 Plan 涉及非用户侧服务（worker、job、sidecar 等）调用 Backend HTTP 端点，Plan **必须同时声明**：

1. **端点路径**（建议 `/internal/v1/...` 路由组，与用户侧端点物理隔离）；
2. **鉴权机制**（三选一）：环境变量注入的静态 API Key（`BACKEND_INTERNAL_API_KEY`）/ 网络隔离声明（仅内网可达，需在文档中明确）/ mTLS。

**典型场景**：
- build-worker 构建完成 → `PATCH /internal/v1/games/:id/build-result`（body: `{buildStatus, accessUrl, snapshot}`）
- AI worker 输出无效 → `POST /internal/v1/users/:id/credits/refund`（body: `{amount, type, refId}`）

**Plan Review 必须核查**：
- 凡 Plan 新增 worker / job 服务，是否同时定义了对应的内部端点路径与鉴权方式；缺失鉴权声明 → 判 **Important**（安全类）
- 内部端点对外暴露且无鉴权，攻击者可伪造业务结果（如写入恶意 AccessUrl、触发无授权退款）→ 判 **Critical**，不得降级
- testing 节必须包含内部端点的路由注册测试（`router_test.go` 覆盖）；缺失 → 判 **Important**

## API 幂等键租户隔离（不可协商）

任何客户端生成的幂等键（`idempotency_key`、`request_id` 等）必须绑定 `user_id` 或等价租户边界，禁止以全局 key 替代租户隔离查询：(a) 幂等查询必须按 `(user_id, idempotency_key)` 组合键命中，不得仅按全局 key 全表查询；(b) 持久化层必须为 `(user_id, idempotency_key)` 建立唯一约束（推荐稀疏唯一索引）兜底，防止并发重试产生重复记录；(c) 命中但 `user_id` 不一致时必须返回冲突错误（`409`），不得复用他人记录或返回他人的 capability token；(d) `EnsureIndexes()` 必须在服务启动路径（`startRealMode`）中显式调用，建索引失败视为启动失败。违反本条可导致任意用户通过复用他人 UUID 直接获取他人 session 与 SSE capability token，属 Critical 安全漏洞。Plan Review 和 Develop Review 必须检查：凡引入新的幂等键字段，是否已同时修改查询条件（加 user_id 过滤）、建索引、补幂等冲突测试。
