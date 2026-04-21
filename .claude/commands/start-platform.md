---
description: 启动/停止 GameServer 排行榜服务（:22333）
argument-hint: "[stop]"
---

## 参数解析

用户传入的参数：action=`$ARGUMENTS`

- `stop`（不区分大小写）：仅停止服务
- 空或其他值：编译并启动服务

---

## 执行流程

### 第一步：停止已有 GameServer 进程

```bash
powershell.exe -Command "Get-Process -Name 'gameserver' -ErrorAction SilentlyContinue | Stop-Process -Force; Write-Host 'GameServer stopped'"
```

timeout **10000**ms。

**如果 action 为 `stop`，到此结束，向用户输出"GameServer 已停止"。**

---

### 第二步：编译 GameServer

Bash timeout 设置 **300000**ms（5 分钟）：

```bash
cd E:/GameMaker/GameServer && go build -o bin/gameserver.exe ./cmd/
```

- 编译失败 → **立即停止**，输出错误给用户
- 编译成功 → 继续下一步

---

### 第三步：启动 GameServer（后台）

```bash
powershell.exe -Command "Start-Process -FilePath 'E:/GameMaker/GameServer/bin/gameserver.exe' -WorkingDirectory 'E:/GameMaker/GameServer' -PassThru -WindowStyle Hidden | Select-Object -ExpandProperty Id"
```

timeout **15000**ms。记录返回的 PID。

---

### 第四步：验证服务

```bash
sleep 3 && curl -sf --noproxy localhost http://localhost:22333/leaderboard && echo " - GameServer OK" || echo "GameServer health check failed"
```

---

### 第五步：输出结果

简洁报告：
1. 编译结果（成功/失败）
2. 启动结果和 PID
3. 健康检查状态（http://localhost:22333）
