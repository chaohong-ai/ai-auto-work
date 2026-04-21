# Aippy 1:1 复制实施指南

**基于**: 完整技术调研（2026-04-17）  
**目标**: 功能对等的 AI 游戏创作社区平台

---

## 一、核心架构设计

```
用户浏览器（your-domain.com）
    ↓ prompt（POST + SSE）
your-api.com（Go + Gin）
    ↓ AI Agent
Claude Sonnet（现有）
    ├── 工具链：write_file / replace / build / deploy
    └── 产出：单文件 React HTML（~230KB）
        ↓
Object Storage（腾讯云 COS，现有）
    ↓ 部署到子域
{uuid}.your-game-domain.com
    ↓ iframe 嵌入
your-domain.com 游戏页
```

---

## 二、分阶段实施清单

### Phase 1：核心创作环（MVP）

#### 1.1 React 游戏生成 Agent

**目标**: AI 能生成可运行的 React 小游戏

技术选型：
- AI 模型：Claude Sonnet（现有）
- 游戏框架：React 18 + TypeScript + Vite
- 构建：服务端 Node.js + Vite（`vite build`）
- 产出：`dist/index.html`（内联所有 JS/CSS）

Agent 工具链实现（Go + MCP 或直接实现）：
```go
tools := []Tool{
  {Name: "list_files",            Handler: listProjectFiles},
  {Name: "read_file",             Handler: readProjectFile},
  {Name: "write_file",            Handler: writeProjectFile},
  {Name: "replace_file_content",  Handler: replaceInFile},
  {Name: "delete_file",           Handler: deleteProjectFile},
  {Name: "build_project",         Handler: buildWithVite},
  {Name: "deploy_project",        Handler: deployToSubdomain},
}
```

**项目模板**（AI 在此基础上修改）：
```
template/
  package.json          # React 18 + TypeScript + Vite
  vite.config.ts        # build.rollupOptions.output.inlineDynamicImports: true
  tsconfig.json
  src/
    main.tsx            # ReactDOM.render
    App.tsx             # 入口组件
    runtime/
      index.ts          # @your-brand/runtime SDK stub
      leaderboard.ts
      tweaks.ts
```

**Vite 配置关键点**（生成单文件 HTML）：
```typescript
// vite.config.ts
export default {
  build: {
    rollupOptions: {
      output: {
        inlineDynamicImports: true,  // 关键：合并所有 chunk
        manualChunks: undefined,
      }
    }
  },
  plugins: [
    react(),
    viteSingleFile(),  // vite-plugin-singlefile 插件
  ]
}
```

#### 1.2 SSE 流式 API（Go）

```go
// POST /api/project/agent
// 参考 Aippy 的 AgentMessageCardType 协议

type SSEEvent struct {
  CardType string      `json:"card_type"`
  Message  interface{} `json:"message"`
}

// SSE 事件序列
events := []SSEEvent{
  {CardType: "start",   Message: startMsg},
  {CardType: "thinking", Message: []ThinkingMsg{{Content: "分析需求...", Status: 0}}},
  {CardType: "tool",    Message: []ToolMsg{{Tool: [{Type: "write_file", Input: {...}}]}}},
  {CardType: "tool",    Message: []ToolMsg{{Tool: [{Type: "build_project"}], Status: 1}}},
  {CardType: "deploy_project", Message: []DeployMsg{{Content: deployURL, Status: 1}}},
  {CardType: "end"},
}
```

#### 1.3 子域部署基础设施

**DNS**: Wildcard A 记录
```
*.games.your-domain.com → {server-ip}
```

**Nginx 配置**:
```nginx
server {
  listen 443 ssl;
  server_name ~^(?<siteId>[a-f0-9-]+)\.games\.your-domain\.com$;
  
  location / {
    root /var/games/${siteId};
    try_files /index.html =404;
    
    # 版本化缓存
    add_header Cache-Control "public, max-age=31536000, immutable";
  }
}
```

**部署流程**:
```go
func deployToSubdomain(siteId, buildPath string) (accessUrl string, err error) {
  // 1. 读取 dist/index.html
  html := readFile(buildPath + "/index.html")
  
  // 2. 上传到 COS: games/{siteId}/index.html
  cosKey := fmt.Sprintf("games/%s/index.html", siteId)
  uploadToCOS(cosKey, html)
  
  // 3. 或直接写到 Nginx serve 目录
  os.WriteFile(fmt.Sprintf("/var/games/%s/index.html", siteId), html, 0644)
  
  // 4. 生成版本化 URL
  version := time.Now().Unix()
  return fmt.Sprintf("https://%s.games.your-domain.com?v=%d", siteId, version), nil
}
```

#### 1.4 游戏运行时 SDK（注入模板）

在模板 `src/runtime/` 目录预置以下代码：

```typescript
// src/runtime/index.ts
export function tweaks<T extends Record<string, TweakOption>>(config: T) {
  // 通知父页面
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tweaks-initialize", config: JSON.stringify(config) }, "*");
    window.parent.postMessage({ type: "aippy-tweaks-ready" }, "*");
  }
  
  // iOS WebKit bridge（移动端）
  const bridge = (window as any).webkit?.messageHandlers?.yourBrandListener;
  bridge?.postMessage({ command: "tweaks.initialize", parameters: JSON.stringify(config) });
  
  // 监听更新
  const state = { ...Object.fromEntries(Object.entries(config).map(([k, v]) => [k, v.default])) };
  window.addEventListener("message", (e) => {
    if (e.data?.type === "tweaks-update") {
      Object.entries(e.data).forEach(([k, v]: any) => {
        if (k !== "type" && state[k] !== undefined) state[k] = v.value;
      });
    }
  });
  
  return Object.fromEntries(Object.keys(config).map(k => [k, {
    useState: () => [state[k], (v: any) => { state[k] = v; }]
  }]));
}

// src/runtime/leaderboard.ts
export function updateScore(score: number) {
  const url = window.location.href;
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ __yourGame: true, payload: { type: "score", score, url } }, "*");
  }
  const bridge = (window as any).webkit?.messageHandlers?.yourBrandListener;
  bridge?.postMessage({ command: "leaderboard.updateScore", parameters: JSON.stringify({ score, url }) });
  console.log(`[Game] Score updated: ${score}`);
}
```

---

### Phase 2：社区 Feed 系统

#### 数据模型（参照 Aippy）

```sql
-- 游戏内容表
CREATE TABLE templates (
  id            BIGINT PRIMARY KEY AUTO_INCREMENT,
  project_id    BIGINT NOT NULL,
  site_id       VARCHAR(64) NOT NULL UNIQUE,  -- UUID
  name          VARCHAR(255),
  prompt        TEXT,               -- AI 对话摘要
  access_url    VARCHAR(512),
  preview_url   VARCHAR(512),
  snapshot      VARCHAR(512),       -- 截图 URL
  cover_image   VARCHAR(512),
  tags          VARCHAR(1000),
  category      VARCHAR(64),        -- hot/dopamine/...
  sub_category  VARCHAR(64),
  device_cap    VARCHAR(255),       -- JSON array
  status        INT DEFAULT 0,
  publish_status INT DEFAULT 0,
  build_status  INT DEFAULT 0,
  permission    INT DEFAULT 2,
  uid           BIGINT,
  likes         INT DEFAULT 0,
  views         INT DEFAULT 0,
  forks         INT DEFAULT 0,
  comments      INT DEFAULT 0,
  shares        INT DEFAULT 0,
  collects      INT DEFAULT 0,
  created_at    TIMESTAMP DEFAULT NOW(),
  INDEX (category, likes DESC),
  INDEX (uid),
  INDEX (created_at DESC)
);
```

#### Feed API 设计

```go
// GET /api/template/recommend
// 注意：Aippy 的 page 参数返回随机大数，可能是随机偏移量而非页码
// 建议实现为：随机偏移 + 分类过滤 + 排序

func GetRecommend(ctx *gin.Context) {
  category := ctx.Query("category")  // hot/latest/dopamine/...
  size, _ := strconv.Atoi(ctx.DefaultQuery("size", "12"))
  
  var templates []Template
  
  switch category {
  case "hot":
    // 按综合热度排序（likes * 0.4 + views * 0.3 + recency * 0.3）
    db.Where("publish_status = 1").
       Order("(likes * 0.4 + views * 0.001 + UNIX_TIMESTAMP(created_at) * 0.3) DESC").
       Limit(size).Find(&templates)
  case "latest":
    db.Where("publish_status = 1").
       Order("created_at DESC").
       Limit(size).Find(&templates)
  default:
    db.Where("publish_status = 1 AND category = ?", category).
       Order("likes DESC").
       Limit(size).Find(&templates)
  }
  
  ctx.JSON(200, gin.H{"code": 0, "data": gin.H{
    "list": templates,
    "total": count,
  }})
}
```

#### Remix 功能
```go
// POST /api/template/remix
// 复制项目文件，创建新 siteId，保留 fromProjectId 引用
func RemixTemplate(ctx *gin.Context) {
  originalId := ctx.GetInt("templateId")
  
  // 1. 复制原始项目代码到新 siteId
  // 2. 创建新 project 记录（fromProjectId = originalId）
  // 3. 触发新 AI 对话（携带原始代码作为上下文）
}
```

---

### Phase 3：商业化

#### Stripe 集成（参照 Aippy price_id 格式）

```go
// POST /api/payment/order/create
func CreateOrder(ctx *gin.Context) {
  productId := ctx.GetInt("productId")
  product := getProduct(productId)
  
  // Stripe Checkout Session
  params := &stripe.CheckoutSessionParams{
    Mode: stripe.String("subscription"),
    LineItems: []*stripe.CheckoutSessionLineItemParams{
      {Price: &product.StripePriceId, Quantity: stripe.Int64(1)},
    },
    SuccessURL: stripe.String("https://your-domain.com/payment/success"),
    CancelURL:  stripe.String("https://your-domain.com/pricing"),
  }
  session, _ := session.New(params)
  ctx.JSON(200, gin.H{"clientSecret": session.ClientSecret})
}
```

#### Credit 消耗逻辑

| 操作 | Credit 消耗 | 说明 |
|------|------------|------|
| 创建游戏（首次） | 10 credits | 推测 |
| AI 对话修改 | 5 credits | 推测 |
| Remix | 5 credits | 推测 |
| Prompt 增强 | 1 credit | 推测 |

---

## 三、与 GameMaker 现有架构的集成点

| Aippy 组件 | GameMaker 对应 | 复用/新建 |
|-----------|-------------|---------|
| 用户认证 JWT | `Backend/internal/router/middleware.go` | 复用，加 OAuth |
| 文件存储 COS | 已有 COS 集成 | 复用 |
| SSE 流式 | `Backend/` 已有 Redis Stream | 新增 SSE endpoint |
| AI Agent | `MCP/src/` | 新增 React 生成工具集 |
| 子域部署 | 新建 | Nginx Wildcard |
| 游戏 Feed DB | MongoDB（现有）| 新增 collection |
| 支付 Stripe | 无 | 新增 |

---

## 四、关键风险点

1. **AI 生成质量**: Aippy 游戏质量参差不齐（实测可见），需要好的 System Prompt 和错误自愈（`FIX_ERROR` 消息类型）
2. **构建速度**: Vite build 需 5-30 秒，需异步处理 + 进度 SSE 推送
3. **子域 HTTPS**: Wildcard SSL 证书（Let's Encrypt wildcard 需 DNS challenge）
4. **内容安全**: Aippy 有 `report` 接口，需内容审核
5. **版权风险**: Aippy 游戏引用外部音频（myinstants.com），版权灰色地带，复制时应用自有音频库

---

## 五、最小可行版（1-2周）

实现 "Prompt → 游戏 → 可分享链接" 的完整链路：

1. `POST /api/project/agent`（SSE）调用 Claude 生成 React 代码
2. 服务端 Vite build → 单文件 HTML
3. 部署到 `{uuid}.games.your-domain.com`
4. 返回可分享的 URL
5. 最简游戏列表页展示（无复杂 Feed 算法）
