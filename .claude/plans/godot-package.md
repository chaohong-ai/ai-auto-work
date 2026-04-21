---
name: godot-package
version: v0.0.2-mvp
feature: godot-package
status: completed
created: 2026-03-12
completed: 2026-03-13
plan_source: Docs/Version/v0.0.2-mvp/godot-package/plan.md
---

# Godot 游戏导出（Package）实施计划

## 概述

在 Docker 容器内运行 Godot 4.3 Headless 完成游戏导出，Server 提供导出 API 和静态文件服务，Client 提供平台选择 UI、下载和 HTML5 内嵌播放。

## 实施阶段

### Phase 1: Docker 环境搭建 ✅

| 任务 | 文件 | 状态 |
|------|------|------|
| Docker Desktop 安装脚本 | `Scripts/setup-docker.ps1` | ✅ 已完成 |
| Godot 镜像拉取脚本 | `Scripts/setup-godot-image.ps1` | ✅ 已完成 |
| Docker 重启脚本 | `Scripts/restart-docker.ps1` | ✅ 已完成 |
| 镜像拉取脚本 | `Scripts/pull-image.ps1` | ✅ 已完成 |
| 一键部署脚本 | `Scripts/run-all.ps1` | ✅ 已完成 |
| 停止服务脚本 | `Scripts/stop-all.ps1` | ✅ 已完成 |
| 重启后部署脚本 | `Scripts/after-reboot.ps1` | ✅ 已完成 |

### Phase 2: Server 导出服务 + API ✅

| 任务 | 文件 | 状态 |
|------|------|------|
| Export 数据模型 | `Backend/internal/model/export.go` | ✅ 新建 |
| 空项目生成 | `Backend/internal/export/project.go` | ✅ 新建 |
| 导出预设生成 | `Backend/internal/export/preset.go` | ✅ 新建 |
| Docker 容器管理 | `Backend/internal/export/docker.go` | ✅ 新建 |
| 导出核心服务 | `Backend/internal/export/service.go` | ✅ 新建 |
| HTTP 端点处理 | `Backend/internal/handler/export_handler.go` | ✅ 新建 |
| 配置添加 ExportConfig | `Backend/internal/config/config.go` | ✅ 修改 |
| 路由注册 5 条导出路由 | `Backend/internal/router/router.go` | ✅ 修改 |
| 注入 ExportService | `Backend/cmd/api/main.go` | ✅ 修改 |
| 添加 export 配置段 | `Backend/configs/config.yaml` | ✅ 修改 |
| 添加 export 配置段 | `Backend/configs/config.mock.yaml` | ✅ 修改 |
| 移除旧导出存根 | `Backend/internal/handler/game.go` | ✅ 修改 |

### Phase 3: Client 导出 UI + HTML5 播放 ✅

| 任务 | 文件 | 状态 |
|------|------|------|
| Export 类型定义 | `Frontend/src/lib/types.ts` | ✅ 修改 |
| Export API 函数 | `Frontend/src/lib/api.ts` | ✅ 修改 |
| 导出状态管理 Hook | `Frontend/src/hooks/useExport.ts` | ✅ 新建 |
| 导出弹窗组件 | `Frontend/src/components/export/ExportDialog.tsx` | ✅ 新建 |
| 平台选择组件 | `Frontend/src/components/export/PlatformSelector.tsx` | ✅ 新建 |
| 导出进度组件 | `Frontend/src/components/export/ExportProgress.tsx` | ✅ 新建 |
| HTML5 播放器 | `Frontend/src/components/export/HTML5Player.tsx` | ✅ 新建 |
| Session 页面集成 | `Frontend/src/app/session/[id]/page.tsx` | ✅ 修改 |

### Phase 4: 测试 ✅

| 任务 | 文件 | 状态 |
|------|------|------|
| 预设生成测试 (7 cases) | `Backend/internal/export/preset_test.go` | ✅ 新建 |
| 项目生成测试 (6 cases) | `Backend/internal/export/project_test.go` | ✅ 新建 |
| 平台验证测试 (6 cases) | `Backend/internal/model/export_test.go` | ✅ 新建 |

## 验证结果

- Go: `go build ./...` 通过, `go test ./...` 全部 PASS (15 新测试)
- Client: `next build` 成功, 无类型错误
- API 错误处理: PLATFORM_NOT_SUPPORTED / DOCKER_UNAVAILABLE / EXPORT_NOT_FOUND / SYS_INVALID_INPUT 全部验证通过

## 待办（需手动操作）

- [ ] 重启电脑让 Docker Desktop WSL2 后端完成初始化
- [ ] 运行 `powershell -ExecutionPolicy Bypass -File Scripts/after-reboot.ps1`
- [ ] 在浏览器中完成端到端验收测试

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v1/games/:id/export` | 触发导出 |
| GET | `/api/v1/exports/:id` | 查询状态 |
| GET | `/api/v1/exports/:id/download` | 下载产物 |
| GET | `/api/v1/exports/:id/play` | HTML5 播放 |
| GET | `/api/v1/exports/:id/static/*filename` | 静态文件 |

## 技术决策

1. **Docker CLI 而非 Docker SDK**: 避免新增 go.mod 依赖, 通过 os/exec 调用 docker 命令
2. **内存存储而非 MongoDB**: MVP 阶段 Export 记录存内存 map, 后续接入持久化
3. **同步 goroutine 而非 Redis 队列**: MVP 不走队列, 直接在 goroutine 中执行导出
4. **轮询而非 SSE**: 客户端 2 秒轮询导出状态, 简化实现
