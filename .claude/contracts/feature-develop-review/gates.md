合宪性审查（逐语言）：
- Go: error 必须 fmt.Errorf 包装+zap 日志；defer 释放锁；Context 传播
  - 禁止裸断言 `err.(T)`，必须用 `errors.As`
  - 公开 HTTP 服务必须同时配置 ReadHeaderTimeout / ReadTimeout / WriteTimeout / IdleTimeout + MaxBytesReader
  - 请求链路禁用 context.Background() / context.TODO()，必须从 handler 透传
  - 向异步队列发送失败必须向调用方返回错误，不得只记日志静默丢包
- TS: 无空 catch {}；Winston 日志；Zod 校验外部输入；通信超时
- GDScript: 信号连接；节点引用安全
- Python: 无裸 except/pass；Pydantic/FastAPI 校验

Plan 完整性：遗漏/偏差/接口一致性/数据流方向

测试覆盖（严重级：缺失 handler 测试 = CRITICAL）：
- 新增 HTTP 端点 → 必须有 router_test.go 路由注册测试 + Backend/tests/smoke/*.hurl
- JWT 保护的 handler → 至少一组经由真实 router + middleware 的测试用例
- 产物存在性：plan 声明"新建"的文件必须在工作区中存在

边界情况：null/并发/时序/异常路径/资源泄漏

对抗审查重点（Claude 常见盲区）：
1. 并发竞态：goroutine 共享状态锁保护？channel 阻塞？
2. 资源泄漏：文件句柄、DB 连接、HTTP Body 正确关闭？
3. 异常路径：错误分支真正处理了？happy-path-only？
4. 边界输入：空切片、nil map、零值 struct、并发写 map
5. 安全：注入风险、硬编码凭证、未校验外部输入
6. 测试质量：只覆盖 happy path？有表格驱动测试？
7. 上下文缺口：失误源于缺失上下文 → 指出应补到哪个 .ai/ 或 .claude/ 文件
