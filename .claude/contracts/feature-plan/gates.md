合宪性 6 条原则逐条自检：
1. 简单性：只实现需求要求的，无预支设计？
2. 测试先行：每个 Handler/Service 有测试？HTTP 端点有 router_test + hurl？
3. 明确性：错误显式处理+日志？无全局可变状态？
4. 低耦合：依赖方向单向？Service 层不 import 基础设施包？
5. 并发安全：Redis Streams 幂等？Goroutine 有退出机制？容器有资源限制？
6. 多平台：引擎决策兼容 iOS/Android？

附加 gate：
- 文件清单列出所有新增/修改文件
- 测试计划覆盖核心路径
