# 06-生成验证与自修复闭环 技术规格

## 1. 概述

实现 AI 游戏生成的「生成→验证→自修复」闭环。每次 AI 完成一组 MCP 工具调用后，自动触发多层验证，发现问题后引导 AI 自修复或回滚到安全快照。

**范围**：
- 四层验证管线（静态检查 → 运行检查 → 截图验证 → 逻辑验证）
- 快照保存与回滚机制
- 自修复编排逻辑（最多 2 次重试）
- Go 侧验证编排器（调用 AI + MCP）
- 验证结果结构化输出（供 AI 阅读）

**不做**：
- 基准测试系统（Phase 0 末期手动运行）
- 自动化 CI 验证（Phase 1）

## 2. 文件清单

```
Backend/
├── internal/
│   ├── verify/
│   │   ├── pipeline.go           # 验证管线编排
│   │   ├── static_check.go       # 静态检查
│   │   ├── run_check.go          # 运行检查
│   │   ├── screenshot_check.go   # 截图验证
│   │   ├── logic_check.go        # 逻辑验证
│   │   └── result.go             # 验证结果数据结构
│   ├── snapshot/
│   │   ├── manager.go            # 快照管理
│   │   └── storage.go            # 快照存储（本地 + COS）
│   └── generation/
│       ├── orchestrator.go       # 生成编排器（Plan→Build→Verify→Heal）
│       ├── ai_client.go          # Claude API 客户端
│       └── heal.go               # 自修复逻辑
```

## 3. 验证管线

### 3.1 四层验证

```
Layer 1: 静态检查 (Static Check)
  ├── godot --headless --import 预检
  ├── 场景树结构校验（必需节点存在、类型正确）
  ├── 负向示例规则检查（N001~N020）
  └── 脚本语法检查
  耗时: ~2s | 检出: 结构错误、语法错误

Layer 2: 运行检查 (Run Check)
  ├── 启动游戏 3 秒
  ├── 捕获 stdout/stderr
  ├── 检测崩溃/异常退出
  └── 收集运行时错误日志
  耗时: ~5s | 检出: 运行时错误、空引用、资源缺失

Layer 3: 截图验证 (Screenshot Check)
  ├── xvfb 截图 (640x480)
  ├── 基础图像检查（非全黑/全白、有内容）
  ├── 可选: AI 视觉验证（Claude Vision）
  └── 截图存入快照
  耗时: ~3s (基础) / ~5s (含 AI) | 检出: 视觉异常

Layer 4: 逻辑验证 (Logic Check)
  ├── 模拟输入（按左右键、跳跃）
  ├── 检测玩家是否能移动
  ├── 检测碰撞是否工作
  └── 检测基础游戏循环
  耗时: ~5s | 检出: 逻辑缺陷
```

### 3.2 验证策略

| 场景 | 使用层级 | 说明 |
|------|----------|------|
| 每次工具调用后 | Layer 1 | 快速静态检查 |
| 每 3~5 步操作后 | Layer 1 + 2 | 运行检查 |
| 生成完成时 | Layer 1 + 2 + 3 | 完整验证 |
| 最终交付前 | Layer 1 + 2 + 3 + 4 | 全量验证 |

## 4. 数据结构

```go
// Backend/internal/verify/result.go

type VerifyResult struct {
    Passed     bool            `json:"passed"`
    Layers     []LayerResult   `json:"layers"`
    Summary    string          `json:"summary"`         // AI 可读的摘要
    Errors     []VerifyError   `json:"errors"`
    Warnings   []VerifyError   `json:"warnings"`
    Screenshot *Screenshot     `json:"screenshot,omitempty"`
}

type LayerResult struct {
    Layer    string     `json:"layer"`     // "static", "run", "screenshot", "logic"
    Passed   bool       `json:"passed"`
    Duration int        `json:"duration_ms"`
    Details  string     `json:"details"`
    Errors   []VerifyError `json:"errors"`
}

type VerifyError struct {
    Code        string `json:"code"`          // "N001", "RUNTIME_CRASH", "SCREENSHOT_BLANK"
    Severity    string `json:"severity"`      // "critical", "error", "warning"
    Message     string `json:"message"`
    NodePath    string `json:"node_path,omitempty"`
    RecoveryHint string `json:"recovery_hint"` // AI 可执行的修复建议
}

type Screenshot struct {
    Base64   string `json:"base64"`
    Width    int    `json:"width"`
    Height   int    `json:"height"`
    IsBlank  bool   `json:"is_blank"`   // 全黑/全白检测
}
```

## 5. 验证实现

### 5.1 静态检查

```go
// Backend/internal/verify/static_check.go

func (v *StaticChecker) Check(ctx context.Context, sessionID string) (*LayerResult, error) {
    result := &LayerResult{Layer: "static"}

    // 1. Godot import 预检
    stdout, stderr, exitCode, err := v.mcp.Exec(ctx, sessionID, "import")
    if exitCode != 0 {
        result.Errors = append(result.Errors, VerifyError{
            Code:     "IMPORT_FAILED",
            Severity: "critical",
            Message:  stderr,
        })
    }

    // 2. 场景树结构检查
    tree, err := v.mcp.GetResource(ctx, sessionID, "godot://scene/main/tree")
    structErrors := v.checkSceneTree(tree)
    result.Errors = append(result.Errors, structErrors...)

    // 3. 负向示例规则检查
    ruleErrors := v.checkNegativeRules(tree)
    result.Errors = append(result.Errors, ruleErrors...)

    result.Passed = !hasErrors(result.Errors, "critical", "error")
    return result, nil
}
```

### 5.2 运行检查

```go
// Backend/internal/verify/run_check.go

func (v *RunChecker) Check(ctx context.Context, sessionID string) (*LayerResult, error) {
    result := &LayerResult{Layer: "run"}

    // 在容器中运行游戏 3 秒
    stdout, stderr, exitCode, err := v.container.ExecWithTimeout(ctx, sessionID,
        []string{"godot", "--rendering-driver", "opengl3", "--path", "/project"},
        3*time.Second,
    )

    // 检测崩溃
    if exitCode != 0 && exitCode != 124 { // 124 = timeout (正常)
        result.Errors = append(result.Errors, VerifyError{
            Code:     "RUNTIME_CRASH",
            Severity: "critical",
            Message:  fmt.Sprintf("Game crashed with exit code %d: %s", exitCode, stderr),
        })
    }

    // 解析运行日志中的错误
    logErrors := v.parseGameLog(stderr)
    result.Errors = append(result.Errors, logErrors...)

    result.Passed = !hasErrors(result.Errors, "critical", "error")
    return result, nil
}
```

### 5.3 截图验证

```go
// Backend/internal/verify/screenshot_check.go

func (v *ScreenshotChecker) Check(ctx context.Context, sessionID string) (*LayerResult, error) {
    result := &LayerResult{Layer: "screenshot"}

    // 1. 调用截图 MCP 工具
    screenshotResult, err := v.mcp.CallTool(ctx, sessionID, "get_screenshot", map[string]any{
        "resolution": "640x480",
    })

    // 2. 基础图像检查
    imgData := screenshotResult.Data["base64"].(string)
    isBlank := v.checkBlank(imgData)  // 检测全黑/全白
    if isBlank {
        result.Errors = append(result.Errors, VerifyError{
            Code:         "SCREENSHOT_BLANK",
            Severity:     "error",
            Message:      "Screenshot is blank (all black or all white)",
            RecoveryHint: "Check if scene has visible nodes with proper textures/colors",
        })
    }

    result.Screenshot = &Screenshot{
        Base64:  imgData,
        Width:   640,
        Height:  480,
        IsBlank: isBlank,
    }

    result.Passed = !isBlank
    return result, nil
}
```

## 6. 快照机制

### 6.1 快照管理

```go
// Backend/internal/snapshot/manager.go

type SnapshotManager struct {
    localStorage string  // 本地临时存储
    cosStorage   *COSStorage  // 持久存储
}

type Snapshot struct {
    ID         string            `json:"id"`
    Label      string            `json:"label"`
    SessionID  string            `json:"session_id"`
    Files      map[string][]byte `json:"-"`           // 文件名 → 内容
    FileList   []string          `json:"file_list"`
    CreatedAt  time.Time         `json:"created_at"`
    VerifyResult *VerifyResult   `json:"verify_result,omitempty"`  // 快照时的验证状态
}

func (m *SnapshotManager) Save(ctx context.Context, sessionID, label string) (*Snapshot, error) {
    // 1. 从容器复制项目文件（.tscn, .gd, config.json, .tres）
    // 2. 保存到本地临时目录
    // 3. 异步上传到 COS (持久化)
}

func (m *SnapshotManager) Restore(ctx context.Context, sessionID, snapshotID string) error {
    // 1. 从本地或 COS 获取快照文件
    // 2. 清除容器中当前项目文件
    // 3. 复制快照文件到容器
    // 4. 重新 import
}
```

### 6.2 自动快照时机

| 时机 | 说明 |
|------|------|
| apply_template 后 | 保存初始模板状态 |
| 每 3~5 步工具调用后 | 定期快照 |
| 验证通过后 | 保存已验证的安全状态 |
| 用户确认满意后 | 保存为最终版本 |

## 7. 生成编排器（核心）

### 7.1 生成流程

```
用户 Prompt
    │
    ▼
[1. Plan 阶段]
    AI 分析需求，输出执行计划（工具调用序列）
    │
    ▼
[2. Build 阶段]
    循环执行工具调用:
    ├── 调用 MCP 工具
    ├── 每步后 Layer 1 静态检查
    ├── 每 3 步后 Layer 1+2 运行检查
    ├── 检查通过 → 继续
    └── 检查失败 → 进入 Heal
    │
    ▼
[3. Verify 阶段]
    Layer 1 + 2 + 3 完整验证
    ├── 通过 → Deliver
    └── 失败 → Heal
    │
    ▼
[4. Heal 阶段] (最多 2 次)
    ├── 将 VerifyResult 发给 AI
    ├── AI 分析错误，输出修复工具调用
    ├── 执行修复
    ├── 重新 Verify
    ├── 通过 → Deliver
    └── 第 2 次仍失败 → Rollback + 降级提示
    │
    ▼
[5. Deliver 阶段]
    保存最终快照 → 导出 H5 → 返回结果
```

### 7.2 编排器实现

```go
// Backend/internal/generation/orchestrator.go

type Orchestrator struct {
    aiClient    *AIClient
    mcpClient   *MCPClient
    verifier    *verify.Pipeline
    snapshots   *snapshot.SnapshotManager
}

type GenerationRequest struct {
    UserPrompt  string `json:"prompt"`
    SessionID   string `json:"session_id"`
    ContainerID string `json:"container_id"`
}

type GenerationResult struct {
    Status      string             `json:"status"`    // "success", "partial", "failed"
    GameURL     string             `json:"game_url,omitempty"`
    Screenshot  string             `json:"screenshot_base64,omitempty"`
    Steps       []StepRecord       `json:"steps"`
    HealAttempts int               `json:"heal_attempts"`
    FinalVerify *verify.VerifyResult `json:"final_verify"`
}

type StepRecord struct {
    Step       int    `json:"step"`
    ToolName   string `json:"tool_name"`
    Arguments  any    `json:"arguments"`
    Result     any    `json:"result"`
    VerifyOK   bool   `json:"verify_ok"`
}

func (o *Orchestrator) Generate(ctx context.Context, req GenerationRequest) (*GenerationResult, error) {
    result := &GenerationResult{Steps: []StepRecord{}}

    // 1. Plan: AI 分析需求
    plan, err := o.aiClient.Plan(ctx, req.UserPrompt, o.getAvailableTools())

    // 2. Build: 执行工具调用
    for i, toolCall := range plan.ToolCalls {
        // 执行
        toolResult, err := o.mcpClient.CallTool(ctx, req.SessionID, toolCall.Name, toolCall.Args)
        result.Steps = append(result.Steps, StepRecord{...})

        // 静态检查（每步）
        staticResult, _ := o.verifier.RunLayer(ctx, req.SessionID, "static")
        if !staticResult.Passed {
            // 立即修复或回滚
            healed := o.tryHeal(ctx, req, staticResult, &result.HealAttempts)
            if !healed { break }
        }

        // 运行检查（每 3 步）
        if (i+1) % 3 == 0 {
            runResult, _ := o.verifier.RunLayers(ctx, req.SessionID, []string{"static", "run"})
            if !runResult.Passed {
                healed := o.tryHeal(ctx, req, runResult, &result.HealAttempts)
                if !healed { break }
            }
            // 验证通过，保存快照
            o.snapshots.Save(ctx, req.SessionID, fmt.Sprintf("step_%d_verified", i+1))
        }
    }

    // 3. Verify: 完整验证
    finalVerify, _ := o.verifier.RunLayers(ctx, req.SessionID, []string{"static", "run", "screenshot"})
    result.FinalVerify = finalVerify

    if !finalVerify.Passed {
        healed := o.tryHeal(ctx, req, finalVerify, &result.HealAttempts)
        if !healed {
            result.Status = "partial"
            return result, nil
        }
    }

    // 4. Deliver
    result.Status = "success"
    result.Screenshot = finalVerify.Screenshot.Base64
    return result, nil
}

func (o *Orchestrator) tryHeal(ctx context.Context, req GenerationRequest, verifyResult *verify.VerifyResult, attempts *int) bool {
    if *attempts >= 2 {
        // 回滚到最近的安全快照
        o.snapshots.RestoreLatestVerified(ctx, req.SessionID)
        return false
    }
    *attempts++

    // 将错误信息发给 AI，请求修复
    fixPlan, err := o.aiClient.Heal(ctx, verifyResult)
    if err != nil { return false }

    // 执行修复
    for _, toolCall := range fixPlan.ToolCalls {
        o.mcpClient.CallTool(ctx, req.SessionID, toolCall.Name, toolCall.Args)
    }

    // 重新验证
    reVerify, _ := o.verifier.RunLayers(ctx, req.SessionID, []string{"static", "run", "screenshot"})
    return reVerify.Passed
}
```

## 8. AI 自修复 Prompt

```markdown
# 错误修复请求

以下是游戏验证失败的结果，请分析错误并给出修复方案。

## 验证结果
{verify_result_json}

## 当前场景树
{scene_tree_json}

## 要求
1. 只使用 MCP 工具修复问题
2. 优先使用 Level 2 语义工具
3. 如果问题无法通过工具修复，使用 rollback_snapshot() 回到安全状态
4. 每个错误给出具体的修复步骤
```

## 9. 验收标准

1. **静态检查**：能检出场景树结构错误（缺少 CollisionShape、类型错误等）
2. **运行检查**：能检出运行时崩溃和脚本错误
3. **截图检查**：能检出空白截图，返回 base64 PNG
4. **快照保存**：save_snapshot 保存完整项目文件，耗时 < 2s
5. **快照恢复**：restore_snapshot 恢复后游戏状态与快照一致
6. **自修复成功**：故意引入一个错误（如缺少 CollisionShape），AI 能在 2 次内修复
7. **自修复失败回滚**：2 次修复失败后自动回滚到安全快照
8. **编排器端到端**：输入 Prompt → 输出可玩游戏 + 截图 + 验证报告
9. **验证耗时**：完整 4 层验证 < 15 秒
10. **日志可追溯**：每步操作和验证结果都有结构化日志记录
