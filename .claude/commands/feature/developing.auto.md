---
description: "自动模式实现功能代码（由 feature-develop-loop.sh 调用），无用户交互"
argument-hint: [feature_dir]
---

## 参数

从提示词中读取 `功能目录（FEATURE_DIR）` 字段作为 FEATURE_DIR。

验证 `{FEATURE_DIR}/plan.md` 存在。

## 工作流程

### 第一步：建立完整上下文

先根据任务范围和 plan 文件清单判定命中模块，再建立上下文。

先自己读 plan.md，同时启动并行 Agent：
- **Agent 1（plan 子文件）**：如果 `plan/` 子目录存在，只阅读与当前任务涉及模块对应的子文件，返回关键实现细节
- **Agent 2（约束）**：阅读 `feature.md` 和 `.ai/constitution.md`；只有遇到代码级细则不明确时再补读 `.claude/constitution.md` 或专题 guide
- **Agent 3（现有代码）**：只在命中模块目录中搜索最相似的已有实现，返回参考模板的命名风格、文件组织、API 调用方式

按需补充：
- fake/mock 集成测试链路 → 读取 `.claude/guides/fake-env-closure.md`
- Go 取消/超时/Shutdown/后台任务状态机 → 读取 `.claude/guides/go-cancellation-semantics.md`
- 未命中的模块目录、Godot/MCP 细节、系统级架构文档禁止预读

### 第二步：制定实现计划

基于 plan.md 文件清单，按依赖排序：
1. 数据模型 → 2. 基础设施 → 3. 服务层 → 4. 接口层 → 5. 表现层 → 6. 集成层

使用 TaskCreate 创建任务列表。默认所有涉及模块一次性全部完成。

### 第三步：逐个实现

互不依赖的模块可用并行 Agent 同时实现。有依赖关系的必须串行。

**编码规则：**
- 先阅读再编写：修改已有文件必须先 Read 完整文件
- 模式一致：新代码与同目录已有代码风格一致
- 只做 plan 要求的事
- 编码规范遵循 `.claude/constitution.md` 第三、四、五条

每完成一个任务用 TaskUpdate 标记 completed。

### 第四步：编写测试

- Go: 表格驱动测试，`*_test.go`，优先 fake 不 mock
- TS: Jest，`*.test.ts`
- Python: pytest，`test_*.py`
- **HTTP 端点铁律**：新增端点必须有 router_test.go 路由注册测试 + smoke/*.hurl 冒烟测试

### 第五步：编译验证

```bash
cd Backend && go build ./... 2>&1 | tail -20
cd Backend && go test ./... 2>&1 | tail -30
cd MCP && npx tsc --noEmit 2>&1 | tail -20        # 如涉及
cd Frontend && npx tsc --noEmit 2>&1 | tail -20    # 如涉及
```

编译/测试失败 → 立即修复，重新验证直到通过。测试通过数只能升不能降。

### 第六步：产物落地校验

从 plan 提取所有"新建"文件路径，用 Glob 逐个确认存在。缺失文件禁止标记完成。

### 第七步：输出实现总结 + 写 develop-log.md

写入 `{FEATURE_DIR}/develop-log.md`。

---

## 禁止事项

1. 禁止编造 API：不确定时先搜索代码库
2. 禁止超范围实现：plan 没提到的不做
3. 禁止忽略错误
4. 禁止跳过上下文
5. 禁止在代码或日志中写"待人工处理"等推脱标记
