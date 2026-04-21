审查维度（7 维度全覆盖）：
1. 需求覆盖：每个 REQ 有对应设计？遗漏？隐含需求？
2. 边界条件（逐项检查）：
   - 数据边界：空数据、容器资源限制、并发修改、nil/零值
   - 时间边界：AI 超时、Godot 崩溃、重复请求、SSE 断开
   - 状态边界：容器生命周期、Redis 重试、Session 隔离、锁竞争
   - **首次 durable write crash 窗口**：涉及锁/容器/reservation/并发计数时，必须枚举"首次权威持久化写入之前 kill -9"场景，断言不残留悬空锁/孤儿容器
3. API/工具设计：REST 字段完整？错误码全量覆盖？分页？幂等性？
4. 服务端设计：Handler/Service 职责？Redis Streams 幂等+ACK？Docker 资源限制？
   - 公开 HTTP 服务有四项超时（ReadHeader/Read/Write/Idle）+ MaxBytesReader？
5. MCP/引擎设计：工具语义化？Godot 通信超时？GDScript 信号连接？
6. 安全/容器：Docker 隔离？用户输入过滤？数据流方向？浏览器原生请求鉴权？
7. 测试/可观测：关键操作有日志？测试覆盖核心路径？HTTP 端点有 router_test+hurl？
   - **基础设施任务完成门槛**：凡改 go.mod/go.work/Makefile，验收必须包含真实消费端包的编译；仅子模块自身通过不算完成

宪法补充硬检查（Plan Review 必执行）：
- 子文档合同一致性：api.md × client.md × server.md × testing.md 状态码、DTO、前端完成条件四处对齐
- 列表接口验收：通过本轮新建实体 ID 定位，禁用"首项/长度>0"作为验收信号
- 鉴权能力存在性：使用 RBAC/admin 前必须核查 Claims.Role/User.role/RequireAdmin 是否存在
- Game 模型落点单一：internal/model vs internal/game 只能指向一套
- 产物清单一致性：plan 声明"新建"的文件必须在工作区真实存在

对抗审查重点：
- 可行性漏洞：假设了不存在的 API？依赖版本兼容？
- 并发与状态：多用户/多容器状态一致性？
- 故障模式：外部依赖挂掉时的系统行为？
- 性能瓶颈：N+1 查询、内存增长、阻塞？
- 上下文缺口：问题源于 Claude 缺失上下文 → 指出应补到哪个 .ai/ 或 .claude/ 文件
