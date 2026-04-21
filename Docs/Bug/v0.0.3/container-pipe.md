# Bug 清单：v0.0.3 / container-pipe

| # | 标题 | 严重度 | 归因 | 状态 | 分析报告 |
|---|------|--------|------|------|----------|
| 1 | Redis 3.x 不支持 XREADGROUP 导致队列消费失败 | Critical | 环境前提遗漏 | Open | [redis-xreadgroup-unsupported.md](container-pipe/redis-xreadgroup-unsupported.md) |
