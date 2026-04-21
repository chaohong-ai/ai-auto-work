# Bug Fix Review Input

## Bug 描述

用户在 JWT 登录状态下，于 Export Dialog 点击 "Download" 按钮下载 Windows 平台构建，浏览器保存的文件名为 `download.json` 而非 `.exe`；同时提示"失败 - 需要获得授权"。

## 根因分析

`Backend/internal/router/router.go:100-108` 将 5 条 export 路由（create export / get status / download / play / static）放在同一个 JWT 保护组内：

```go
exports := v1.Group("")
if deps.AuthMode == "jwt" && len(deps.JWTSecret) > 0 {
    exports.Use(JWTAuthMiddleware(deps.JWTSecret, deps.Logger))
}
exports.POST("/games/:id/export", deps.ExportHandler.CreateExport)
exports.GET("/exports/:id", deps.ExportHandler.GetExport)
exports.GET("/exports/:id/download", deps.ExportHandler.DownloadExport)
exports.GET("/exports/:id/play", deps.ExportHandler.PlayExport)
exports.GET("/exports/:id/static/*filename", deps.ExportHandler.ServeExportStatic)
```

前端 `Frontend/src/components/export/ExportDialog.tsx:168-177` 用 `<a href download>` 发起下载、`Frontend/src/components/export/HTML5Player.tsx` 用 `<iframe src>` 嵌入 HTML5 游戏，浏览器对这两种资源加载 **无法附带 `Authorization: Bearer <token>` 头**。JWT middleware 因此拒绝请求并返回 401 JSON，浏览器按 URL 末段 `download` + JSON 扩展名保存为 `download.json`。

## 修复策略

最小化修改：把 `/exports/:id/download`、`/exports/:id/play`、`/exports/:id/static/*filename` 三条"资源交付"路由从 JWT 组拆出，放入公共组；保留 `POST /games/:id/export`、`GET /exports/:id` 仍需鉴权。Export ID 由服务端生成，充当 capability URL。

## 变更文件

- `Backend/internal/router/router.go`：拆分 exports 为 `protectedExports` + `publicExports` 两组
- `Backend/internal/router/router_test.go`：
  - 从 `TestRouter_JWTProtectedRoutes_NoToken_401` 的 protectedRoutes 列表移除 download/play/static 三条
  - 新增"publicExportArtifactRoutes"子测试，断言这三条路由在 JWT 模式下不返回 401（防回归）

## Diff

见 `/tmp/bug-fix.diff`。

## 编译与测试

- `go build ./...` 通过
- `go vet ./internal/router/... ./internal/handler/...` 通过
- `go test -short ./internal/router/...` 通过
- `go test -short ./internal/handler/...` 通过
