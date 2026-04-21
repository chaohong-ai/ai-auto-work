# Fake 环境闭环规则

适用场景：E2E 测试、集成测试中使用 fake/mock 替代外部依赖的所有场景。

## 规则

1. **Fake 必须接入**：当 feature 要求"无外部依赖即可跑通完整链路"时，测试 setup 必须为链路中**每个**外部能力（exporter、AI client、storage 等）提供可运行的 fake 实现，并在 server/handler 初始化时**实际注入**。仅定义 fake 而未注入等同于未实现。

2. **Happy Path 验证**：fake 接入后，必须在验收前跑通对应 happy path。如果 happy path 因 fake 缺失返回 500 或 panic，说明 fake 接入不完整。

3. **注入点检查**：`SetupFullFlowServer()` 或同等 test helper 必须接收并使用 `SetupFullFlowDeps()` 返回的所有 fake 依赖。禁止在 helper 中用空 map、nil 或默认值覆盖已准备好的 fake。

4. **调用断言**：当 feature 要求"验证某外部能力被正确调用"时，fake 必须提供 `GetCalls()` 或等效的调用记录机制，测试中必须断言调用参数和次数。

## 为什么

v0.0.3 full-test 验收中，E2E 测试定义了 `FakeExporter` 但 `SetupFullFlowServer()` 未接入，导致 export 步骤必然 500。这属于"fake 定义了但没闭环"的系统性模式，不是单次疏忽。

## 如何应用

- 写 E2E/集成测试时，检查 test setup 是否把所有 fake 注入到了被测对象
- Code review 时，对比 `SetupDeps` 返回的 fake 列表与 `SetupServer` 实际使用的依赖列表，两者必须一致
- 验收时，若链路中任一步因"no exporter configured"或类似错误失败，判定为 fake 闭环缺失
