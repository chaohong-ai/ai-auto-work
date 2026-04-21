编译 gate：
- Go: go build ./...
- TS: tsc --noEmit

HTTP 端点铁律：
- 新增 HTTP 端点 → router_test.go + Backend/tests/smoke/*.hurl

测试验证：
- 每个新增/修改的源文件必须有对应测试
- Go: go test -short -count=1 ./affected_package/...
- TS: npx jest --findRelatedTests affected_files
- Python: pytest affected_test_files

禁止事项：
- 不编造 plan 中未定义的 API 或接口
- 不超范围实现 plan 未要求的功能
- 不忽略错误：Go 不得用 _ 丢弃 error；TS 不得空 catch {}
- 不跳过上下文：先读已有代码再改，不凭假设动手
- 不破坏已有代码：改动前确认不引入回归

产物落地校验：
- 从 feature.md + plan/*.md 提取所有"新建"/"create"/"新增"的文件路径
- 逐个验证工作区中真实存在，缺失视为功能未完成
