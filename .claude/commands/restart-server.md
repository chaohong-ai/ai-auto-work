---
description: 重启/停止开发服务（Backend:18081 + MCP:3100 + FrontEnd:3000）
argument-hint: "[stop|backend|mcp|frontend]"
---

## 参数解析

用户传入的参数：action=`$ARGUMENTS`

- `stop`：停止 Backend + MCP + FrontEnd
- `backend`：仅重启 Backend
- `mcp`：仅重启 MCP
- `frontend`：仅重启 FrontEnd
- 空或其他值：重启 Backend + MCP + FrontEnd（默认）

---

## 执行

直接运行脚本，将 action 作为参数传入：

```bash
bash E:/GameMaker/scripts/restart-dev.sh <action>
```

- action 为空时不传参数
- timeout **300000**ms（5 分钟，编译可能较慢）
- 脚本会自动处理：停止旧进程 → 编译 → 启动 → 健康检查

---

## 输出结果

将脚本输出直接展示给用户，包含：
1. 各服务的启停状态
2. PID
3. 健康检查结果
