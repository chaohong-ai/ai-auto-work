# 外部平台调用 — LLM + 资源生成

---

## 1. 大语言模型平台调用（游戏逻辑组织）

AI 是 GameMaker 的核心创作引擎，负责理解用户意图、规划游戏结构、生成代码逻辑。

### 1.1 调用场景

| 场景 | 输入 | AI 输出 | 调用方 |
|------|------|---------|--------|
| **需求理解** | 用户自然语言 prompt | GameSpec（游戏规格 JSON/Markdown） | Orchestrator |
| **方案规划** | GameSpec | GamePlan（分步实现计划） | Orchestrator |
| **代码生成** | GamePlan + MCP 工具列表 | Tool Call 序列（场景创建、脚本编写等） | Agentic Loop |
| **验证修复** | 运行结果 + 错误日志 | 修复方案 + Tool Call | Verifier/Healer |
| **对话式开发** | 用户多轮对话 + Session 上下文 | 增量修改指令 | Session Chat |

### 1.2 调用架构

```
                          ┌─────────────────────────────┐
                          │      AI Client 抽象层        │
                          │  Backend/internal/ai/         │
                          │                             │
                          │  ┌─────────┐  ┌──────────┐ │
                          │  │ CLI Mode│  │ API Mode │ │
                          │  │(claude  │  │(HTTP SDK)│ │
                          │  │ binary) │  │          │ │
                          │  └────┬────┘  └────┬─────┘ │
                          └───────┼────────────┼───────┘
                                  │            │
                          ┌───────▼────────────▼───────┐
                          │    Claude API (Anthropic)    │
                          │  claude-sonnet-4-6           │
                          │  (Tool Use / Streaming)      │
                          └──────────────────────────────┘
```

### 1.3 当前实现：Claude (Anthropic)

- **模型：** `claude-sonnet-4-6`（生产），支持 Tool Use
- **双模式：**
  - **CLI Mode（开发）：** 通过 `claude` 二进制进程调用，适合本地调试，支持 `--allowedTools` 限制工具范围
  - **API Mode（生产）：** 通过 Anthropic HTTP API 直接调用，支持 streaming、token 计费统计
- **Tool Use 协议：** AI 返回 `tool_use` 类型 content block，包含工具名和参数 JSON，由 Orchestrator 解析并分发到 MCP Server 执行
- **Context 管理：** 每次调用携带 System Prompt（游戏模板 + MCP 工具说明）+ 历史 messages，控制在模型上下文窗口内

### 1.4 调用流程（Agentic Loop 内）

```
1. Orchestrator 构建 prompt
   ├── System: 游戏模板规则 + 可用工具列表
   ├── Messages: 历史对话 + GameSpec + GamePlan
   └── 当前步骤上下文

2. AI Client 发送请求
   ├── CLI: claude --model sonnet --allowedTools ... --print
   └── API: POST /v1/messages (streaming)

3. 解析 AI 响应
   ├── text block → 记录推理过程
   └── tool_use block → 提取 tool_name + input → 执行 MCP 工具

4. 工具执行结果回填
   └── tool_result 追加到 messages → 进入下一轮迭代

5. 终止条件
   ├── AI 返回 end_turn（无更多 tool_call）
   ├── 达到 max_tool_calls (50)
   └── verify 失败超过 max_heal_attempts (2)
```

### 1.5 扩展性设计

AI Client 抽象层（`Backend/internal/ai/`）定义统一接口，支持未来切换或混合使用其他 LLM：

```go
// AIClient 统一接口
type AIClient interface {
    // SendMessage 发送消息并获取 AI 响应（含 tool_use）
    SendMessage(ctx context.Context, req *SendMessageRequest) (*AIResponse, error)
    // Stream 流式响应（用于 SSE 实时推送）
    Stream(ctx context.Context, req *SendMessageRequest) (<-chan StreamEvent, error)
}
```

| 潜在 LLM 平台 | 适用场景 | 备注 |
|---------------|---------|------|
| **Claude (当前)** | 主力：需求理解、代码生成、工具调用 | Tool Use 能力强，上下文窗口大 |
| **GPT-4o** | 备选：多模态理解（截图分析） | 可作为 fallback |
| **开源模型 (Llama/Qwen)** | 轻量任务：参数校验、格式转换 | 降低 API 成本 |

---

## 2. 第三方资产生成平台调用（游戏资源生成）

游戏资源（图片、音频、3D 模型等）通过外部 AI 生成平台创建，再经 Asset Pipeline 处理后入库。

### 2.1 资源类型与生成平台

| 资源类型 | 目标平台/API | 输入 | 输出 | 规格约束（移动端基线） |
|---------|-------------|------|------|---------------------|
| **2D 精灵/角色** | Stable Diffusion API / DALL·E 3 / Midjourney API | 文本描述 + 风格参考 | PNG (透明背景) | ≤512x512, sprite sheet |
| **UI 图标/元素** | Stable Diffusion (ControlNet) | 文本描述 + 模板约束 | PNG (透明背景) | ≤256x256 |
| **背景/地图贴图** | Stable Diffusion / DALL·E 3 | 场景描述 + 风格词 | PNG/JPG (tileable) | ≤1024x1024, seamless |
| **音效 (SFX)** | ElevenLabs SFX / AudioCraft | 文本描述 | WAV/OGG | ≤5s, mono, 44.1kHz |
| **背景音乐 (BGM)** | Suno API / MusicGen | 风格描述 + 时长 | MP3/OGG | 30-120s, loop-friendly |
| **3D 模型（未来）** | Meshy / Tripo3D API | 文本/图片 | GLTF/GLB | ≤10k triangles |

### 2.2 调用架构

```
                   ┌──────────────────────────────────────────┐
                   │           Asset Generator 抽象层          │
                   │     Backend/internal/asset/generator/      │
                   │                                          │
                   │  ┌──────────┐ ┌────────┐ ┌────────────┐ │
                   │  │ Image    │ │ Audio  │ │ 3D Model   │ │
                   │  │Generator │ │Generator│ │Generator   │ │
                   │  └────┬─────┘ └───┬────┘ └─────┬──────┘ │
                   └───────┼───────────┼────────────┼────────┘
                           │           │            │
               ┌───────────▼──┐  ┌─────▼─────┐  ┌──▼──────┐
               │ SD API /     │  │ ElevenLabs│  │ Meshy / │
               │ DALL·E 3 /   │  │ Suno /    │  │ Tripo3D │
               │ Midjourney   │  │ AudioCraft│  │         │
               └───────┬──────┘  └─────┬─────┘  └────┬────┘
                       │               │              │
                       ▼               ▼              ▼
                  ┌──────────────────────────────────────┐
                  │         Asset Pipeline               │
                  │   Tools/asset-pipeline/               │
                  │                                      │
                  │  1. 下载原始资源                       │
                  │  2. 后处理（缩放、裁剪、格式转换）       │
                  │  3. CLIP 嵌入生成（语义索引）           │
                  │  4. 上传到文件存储（COS/Local）         │
                  │  5. 写入元数据（MongoDB + Milvus）      │
                  └──────────────────────────────────────┘
```

### 2.3 调用流程

```
1. AI 决策资源需求
   └── Agentic Loop 中 Claude 识别需要创建资源
       ├── 分析 GameSpec 中的视觉/音频描述
       └── 生成资源描述 prompt（风格、尺寸、用途）

2. 资源生成请求
   └── Orchestrator → Asset Generator
       ├── 选择对应类型的 Generator
       ├── 构建平台特定的 API 请求
       └── 发送请求 + 轮询/回调等待结果

3. 资源后处理（Asset Pipeline）
   ├── 格式校验（分辨率、文件大小、格式）
   ├── 移动端适配（缩放到目标尺寸、压缩）
   ├── CLIP 嵌入计算 → 存入 Milvus
   └── 元数据写入 MongoDB

4. 资源注入游戏项目
   └── MCP 工具将处理后的资源导入 Godot 项目
       ├── 复制到项目 assets/ 目录
       ├── 创建 Godot .import 资源引用
       └── 更新场景节点引用
```

### 2.4 统一接口设计

```go
// AssetGenerator 资源生成统一接口
type AssetGenerator interface {
    Generate(ctx context.Context, req *AssetGenRequest) (*AssetGenResult, error)
    SupportedTypes() []AssetType
}

type AssetGenRequest struct {
    Type        AssetType  // sprite, icon, background, sfx, bgm, model3d
    Prompt      string     // 文本描述
    Style       string     // 风格关键词 (pixel-art, cartoon, realistic...)
    Constraints AssetConstraints // 尺寸、时长、格式等约束
    ReferenceID string     // 可选：参考已有资源的 ID
}

type AssetGenResult struct {
    FilePath    string            // 本地临时文件路径
    Format      string            // png, jpg, ogg, wav, glb...
    Metadata    map[string]string // 平台返回的元数据
    CostTokens  int               // API 消耗（用于计费追踪）
}
```

### 2.5 免费/开源资源优先策略

在调用付费生成 API 之前，系统优先搜索已有免费资源：

```
资源需求 → CLIP 语义搜索 (Milvus)
              │
              ├── 匹配度 > 阈值 → 直接使用已有资源（零成本）
              │
              └── 匹配度 < 阈值 → 调用第三方生成 API
                                    │
                                    └── 生成后入库 → 后续可复用
```

### 2.6 平台配置

```yaml
# configs/config.yaml
asset_generation:
  image:
    provider: "stable-diffusion"   # stable-diffusion | dalle3 | midjourney
    api_url: "https://api.stability.ai/v1"
    api_key: "${SD_API_KEY}"
    default_style: "pixel-art"
    max_resolution: 512
  audio:
    sfx_provider: "elevenlabs"     # elevenlabs | audiocraft-local
    bgm_provider: "suno"           # suno | musicgen-local
    api_url: "https://api.elevenlabs.io/v1"
    api_key: "${ELEVENLABS_API_KEY}"
  model3d:
    provider: "meshy"              # meshy | tripo3d (未来)
    api_url: "https://api.meshy.ai/v1"
    api_key: "${MESHY_API_KEY}"
  search_threshold: 0.85           # CLIP 搜索匹配阈值
  cost_tracking: true              # 启用 API 调用计费追踪
```

---

## 3. 外部调用治理

| 治理项 | 策略 |
|--------|------|
| **超时控制** | 所有外部 API 调用必须设置 context timeout（图片生成 ≤60s，音频 ≤120s，LLM ≤30s/轮） |
| **重试机制** | 网络错误/限流自动重试（指数退避，最多 3 次），业务错误不重试 |
| **降级策略** | 生成平台不可用时，fallback 到内置占位资源，不阻塞游戏创建流程 |
| **费用控制** | 每个 Session 设置 API 调用预算上限（token/次数），超限后降级到免费资源搜索 |
| **日志审计** | 每次外部调用记录：平台、耗时、费用、成功/失败，支持成本分析和平台对比 |
| **密钥管理** | API Key 通过环境变量注入，不得硬编码，生产环境使用 K8S Secret |
