# Go 异步任务取消语义约束

适用场景：所有涉及 goroutine 状态机、`CancelBuild`、`Shutdown`、后台任务取消的 Go 代码。

## 规则

1. **`context.Canceled` / `context.DeadlineExceeded` 必须单独分类**：不得无条件落入通用失败路径（如 `handleBuildFailure`）。取消和超时是预期的控制流，不是错误。

2. **取消态不可被覆盖**：一旦状态被设为 `interrupted` / `cancelled`，后续的失败回写路径必须做短路保护，禁止将其覆盖为 `failed`。

3. **终态断言测试**：涉及 `CancelBuild` / `Shutdown` / `StopTask` 的代码，必须有测试断言"最终持久化状态"与预期一致，不能只检查首个 HTTP 响应。

4. **错误分类模式**：
   ```go
   if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
       // 取消/超时：保留当前状态，不回写 failed
       return
   }
   // 真正的失败：走失败处理路径
   ```

## 为什么

Claude 在 goroutine 状态机上反复遗漏取消语义，导致"主动取消"和"构建失败"共用同一条失败回写路径，前端和恢复逻辑误判。这是系统性上下文缺口，不是一次性编码失误。
