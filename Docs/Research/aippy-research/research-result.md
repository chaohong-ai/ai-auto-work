# Aippy.ai 技术调研报告

**调研日期**: 2026-04-17  
**调研方法**: 浏览器直连（aippy.ai）+ API 抓包 + JS Bundle 逆向分析  
**调研深度**: 深入对比，面向 1:1 复制  
**子报告目录**: `research-result/`

---

## 一、问题定义

### 调研目标
对 aippy.ai 进行完整技术拆解，为 1:1 复制做准备。重点覆盖：
- 核心功能边界与产品逻辑
- 前后端架构与 API 契约
- AI 游戏生成 Pipeline
- 游戏运行时沙箱机制
- 社区/内容 Feed 系统
- 用户系统与商业化

### Aippy 是什么
Aippy（aippy.ai）是赤子城科技（NADA AI）旗下的 AI 原生游戏创作与社区平台。用户输入自然语言 Prompt，系统通过 AI Agent 自动生成可运行的 React/TypeScript 小游戏，发布到独立子域运行，并以类 TikTok 瀑布流方式进行社区分发。

**核心定位**: 零门槛创作 × 病毒式传播 × 订阅制商业变现

**规模（实测数据 2026-04-17）**:
- 平台总游戏数：**218,953 个**（来源：`/api/template/recommend` total 字段）
- 单游戏最高播放量：835K+ views
- 单游戏最高点赞：73K+ likes

---

## 二、业界方案概览（≥3 个）

### 方案 A — Aippy（本体）
AI 生成 → React/TypeScript SPA → 沙箱 iframe 子域部署 → 类 TikTok Feed

核心特色：
- 游戏以独立 UUID 子域（`{uuid}.aippy.live`）运行，完全隔离
- AI Agent 通过 SSE 实时流式反馈生成过程
- 内置 `@aippy/runtime` SDK（Tweaks + Leaderboard），游戏通过 postMessage 与宿主通信
- 音视频资源全部上传到自有 CDN（Alibaba Cloud OSS）

### 方案 B — Bolt.new（StackBlitz）
AI 生成 → 全栈代码（React/Next.js 等）→ WebContainer 本地运行 → Vercel/Netlify 部署

与 Aippy 的差异：
- 面向开发者而非普通用户，门槛较高
- 支持完整项目结构（多文件、package.json、npm install）
- 使用 WebContainer 在浏览器内原生运行 Node.js，代价是每次需要安装依赖（首次慢）
- 无社区 Feed，无游戏化运营

### 方案 C — Lovable.dev
AI 生成 → React SPA → 实时预览（无独立子域）→ GitHub 集成 + Supabase 后端

与 Aippy 的差异：
- 强调与 GitHub 集成，适合有工程能力的创作者
- 通过 Supabase 提供数据库，支持有状态应用
- 无沙箱子域机制，预览内嵌在平台内
- 无游戏化社区 Feed

### 方案 D — Replit（AI 模式）
AI 生成 → 服务端容器（多语言）→ Replit 自有子域部署 → 协作编辑

与 Aippy 的差异：
- 服务端容器（非纯前端），支持任意语言
- 子域部署模式与 Aippy 最相似（`{repl}.replit.app`）
- 面向开发者，无社区 Feed

---

## 三、方案对比表

| 维度 | Aippy | Bolt.new | Lovable | Replit |
|------|-------|---------|---------|--------|
| **生成目标** | 轻量 React 小游戏/互动 | 全栈 Web App | React SPA | 多语言应用 |
| **运行时架构** | 独立 UUID 子域 iframe | 浏览器 WebContainer | 内嵌预览 | 服务端容器 |
| **AI 通信** | SSE 流式（WebWorker） | SSE 流式 | SSE 流式 | 混合 |
| **代码框架** | React + TypeScript | 任意（默认 React）| React | 任意 |
| **构建方式** | 服务端打包→单文件 inline JS | 浏览器内 Vite | 服务端打包 | 服务端编译 |
| **游戏 bundle 大小** | ~230KB inline JS（实测） | 按项目大小 | 按项目大小 | N/A |
| **资源隔离** | ✅ 独立子域+CSP | ❌ 同域 | ❌ 同域 | ✅ 独立域 |
| **社区 Feed** | ✅ TikTok 风格瀑布流 | ❌ | ❌ | ❌ |
| **版本化 URL** | `?v={timestamp}` 缓存击穿 | hash 版本 | N/A | N/A |
| **Remix/Fork** | ✅ 一键 Remix | ✅ Fork | ✅ | ✅ |
| **移动端 SDK** | ✅ iOS WebKit + postMessage | ❌ | ❌ | ❌ |
| **Haptic 反馈** | ✅（deviceCapability 声明） | ❌ | ❌ | ❌ |
| **订阅模型** | Credit 制（$0–$199/月） | Credit 制 | Credit 制 | Pro 订阅 |
| **CDN** | Alibaba Cloud OSS | Cloudflare | AWS | Replit 自有 |
| **Analytics** | GA4 + ThinkingData（lolipopmobi）| Posthog | N/A | N/A |

---

## 四、业界实战经验（Aippy 深度拆解）

> 以下均为实测一手数据

### 4.1 整体架构

```
用户浏览器（aippy.ai）
    ↓ prompt
api.aippy.ai（REST + SSE）
    ↓ 生成代码
AI Agent（SSE 流式）
    ├── 工具链: list_files → read_file → write_file → build_project → deploy_project
    └── 产物: 单文件 HTML（inline React bundle）
        ↓ 部署
{uuid}.aippy.live（Nginx + OSS）
    ↓ iframe 嵌入
aippy.ai 游戏详情页（postMessage 通信）
```

### 4.2 前端技术栈（实测）

| 组件 | 技术 | 来源 |
|------|------|------|
| 框架 | React 18（实测 JS bundle 含 `Symbol.for("react.transitional.element")`）| JS bundle 分析 |
| 路由 | SPA（单文件 `index-BqoiCaJw.js`）| 网络请求 |
| PWA | ServiceWorker（`registerSW.js`）| HTML head |
| 状态管理 | 内置 React hooks（推断）| JS bundle |
| SSE 客户端 | 自研 `fetchEventSource`（基于 @microsoft/fetch-event-source 风格）| JS bundle |
| 图表/动画 | Lottie（实测 bundle 含 Lottie 引用）| JS bundle |
| UI 组件 | Ant Design（实测 bundle 含 defaultToken 色彩变量）| JS bundle |
| 打包工具 | Vite（bundle 文件名含 hash `BqoiCaJw`）| 推断 |

### 4.3 完整 API 端点清单（实测）

**认证 & 用户**
```
POST /api/user/login
POST /api/user/register
GET  /api/user/profile
GET  /api/user/account/info
PUT  /api/user/account/info
POST /api/user/password/find
POST /api/user/password/reset
POST /api/user/activate
POST /api/user/reactivate
GET  /api/user/uid
GET  /api/user/recommend            # 推荐创作者
POST /api/user/attendance           # 签到/积分
GET  /api/user/affiliate/info       # 推广/邀请
GET  /api/user/account/transaction/records  # 积分流水
POST /api/user/media/upload         # 用户头像上传
```

**项目（游戏创建）**
```
POST /api/project                   # 创建项目（返回 projectId + siteId）
GET  /api/project/{id}              # 获取项目详情
PUT  /api/project                   # 更新项目
DELETE /api/project/{id}            # 删除项目
GET  /api/project?targetUid=...     # 获取用户项目列表
POST /api/project/agent             # AI 生成（SSE 流式）
GET  /api/project/agent/chat/history?projectId=&offset=&sortOrder=  # 对话历史
PUT  /api/project/chat/{id}         # 更新对话
POST /api/project/publish           # 发布游戏
POST /api/project/share             # 分享
GET  /api/project/models            # 可用 AI 模型
```

**内容 Feed & 社区**
```
GET  /api/template/recommend?page=&size=&category=&sortBy=  # Feed（实测 total=218,953）
GET  /api/template/category_v2      # 分类列表
GET  /api/template/info?templateId= # 游戏详情
GET  /api/template/list             # 模板列表
POST /api/template/view             # 记录浏览
POST /api/template/like             # 点赞
POST /api/template/unlike           # 取消点赞
POST /api/template/remix            # Remix（Fork）
POST /api/template/report           # 举报
GET  /api/template/favorites/list   # 收藏列表
```

**社交**
```
POST /api/friend/follow
POST /api/friend/unfollow
GET  /api/friend/follower
GET  /api/friend/following
GET  /api/message/list
GET  /api/message/unread/count
POST /api/message/read
POST /api/comment/publish
GET  /api/comment/list
GET  /api/comment/replies
POST /api/comment/reply
POST /api/comment/remove
```

**媒体 & AI 工具**
```
POST /api/media/asset/upload        # 上传素材
POST /api/media/asset/batchDelete
GET  /api/media/asset/list
GET  /api/media/asset/stats
POST /api/llmodel/prompt/enhance    # Prompt 增强（AI 优化用户输入）
```

**支付 & 订阅**
```
POST /api/payment/order/create      # 创建 Stripe 订单
GET  /api/payment/subscription/plan
GET  /api/subscription/product/?productType=1  # 套餐列表
```

### 4.4 SSE 游戏生成流程（完整协议）

**请求**: `POST api/project/agent`（SSE，WebWorker 执行）

**SSE 事件类型（AgentMessageCardType）**:

```typescript
enum AgentMessageCardType {
  START = "start",
  THINKING = "thinking",          // AI 思考文本
  ASSISTANT = "assistant",        // AI 对话文本
  TOOL = "tool",                  // 工具调用
  SUGGESTION = "suggestion",      // 建议操作
  DEPLOY = "deploy_project",      // 部署状态
  ERROR = "error",
  ERROR_RETRY = "error_retry",
  END = "end"
}
```

**AI 工具链（AgentToolType）**:
```typescript
enum AgentToolType {
  LIST_FILES = "list_files",
  READ_FILE = "read_file",
  WRITE_FILE = "write_file",
  REPLACE_FILE_CONTENT = "replace_file_content",
  DELETE_FILE = "delete_file",
  BUILD_PROJECT = "build_project",
  DEPLOY_PROJECT = "deploy_project"
}
```

**对话消息类型（ChatMessageType）**:
```typescript
enum ChatMessageType {
  COMMON = 1,         // 普通对话
  AI_EDIT = 2,        // AI 编辑
  INSTANT_EDIT = 3,   // 即时编辑
  RESTORE = 4,        // 版本恢复
  OTHER_CHANGE = 5,
  RECONNECT = 8,      // 重连
  ERROR_RETRY = 9,
  FIX_ERROR = 10      // 自动修复 bug
}
```

**部署状态（AgentMessageCardStatus）**:
```typescript
enum AgentMessageCardStatus {
  PENDING = 0,
  SUCCESS = 1,
  FAIL = 2
}
```

### 4.5 游戏运行时架构（沙箱机制）

**部署产物格式**:
- 每个游戏：单文件 HTML，内联 ~230KB React bundle
- 域名：`{siteId-uuid}.aippy.live`（独立子域，天然 CORS 隔离）
- 版本化：`?v={unix-timestamp}` 用于缓存击穿
- 预览：`preview--{siteId}.aippy.live?v={build-ts}`

**HTML 结构**:
```html
<html lang="en">
  <head>
    <!-- 资源预加载（aippy:preload 自定义 meta）-->
    <meta name="aippy:preload" content="https://cdn.aippy.ai/uploads/{uuid}.mp3">
    <meta name="aippy:preload" content="https://www.myinstants.com/media/sounds/xxx.mp3">
    <!-- React bundle 内联 -->
  </head>
  <body>
    <script>/* 230KB 单文件 React 应用 */</script>
  </body>
</html>
```

**`@aippy/runtime` SDK（反向工程）**:

游戏代码内嵌 Aippy 运行时，提供两大能力：

1. **Aippy Tweaks**（运行时参数注入）
```typescript
// 游戏代码调用
const tweaks = aippyTweaksRuntime.tweaks({
  speed: { type: "number", default: 1.0 },
  theme: { type: "string", default: "dark" }
});

// 通信机制：
// Web: window.parent.postMessage({type: "tweaks-initialize", config: JSON.stringify(config)}, "*")
// iOS: window.webkit.messageHandlers.aippyListener.postMessage({command: "tweaks.initialize", parameters: config})
// 接收更新: window.addEventListener("message", e => e.data.type === "tweaks-update")
```

2. **Aippy Leaderboard**（排行榜）
```typescript
// 游戏代码调用
import { updateScore } from "@aippy/runtime/leaderboard";
updateScore(100);

// 底层：postMessage({type: "score", score: 100, url: location.href}) to parent
// iOS：webkit.messageHandlers.aippyListener.postMessage({command: "leaderboard.updateScore", ...})
```

### 4.6 游戏数据模型（完整字段）

```typescript
interface Template {
  id: number;              // 社区 ID（templateId）
  projectId: number;       // 内部项目 ID
  prompt: string;          // AI 对话摘要（summary 格式）
  name: string;
  siteId: string;          // UUID，对应 {siteId}.aippy.live
  previewUrl: string;      // preview--{siteId}.aippy.live?v={build-ts}?v={latest-ts}
  accessUrl: string;       // {siteId}.aippy.live?v={latest-ts}
  permission: 2 | 3;       // 2=公开, 3=?
  publishStatus: 0 | 1;    // 1=已发布
  buildStatus: 0 | 1;      // 1=构建成功
  status: 2 | 3;           // 2=正常, 3=精选/Featured?
  snapshot: string;        // 游戏截图 URL（OSS）
  createTime: string;      // ISO 8601
  uid: number;
  nickName: string;
  username: string;
  avatar: string;
  userType: 1 | 3;         // 1=普通, 3=认证创作者
  level: number;           // 1-11+
  levelIcon: string;
  levelBgColor: string;
  isFollow: boolean;
  coverImage: string;
  tags: string;            // 逗号分隔，如 "3D Interactive Games, Click, RNG"
  likes: number;
  forks: number;
  views: number;
  comments: number;
  shares: number;
  collects: number;
  category: string;        // hot/mindless/brain_hack/unhinged/dopamine/send_this
  favorite: boolean;
  collected: boolean;
  fromProjectId: number;   // Remix 来源
  projectAlias: string;    // URL slug
  shareUrl: string;
  trackingDataMap: { data_source: 0 };
  remixInfo: { projectId: number; name: string };
  rankAttr: { isShow: boolean; sort: "DESC" };
  deviceCapability: string[];  // ["haptic-feedback", "local-storage"]
  aiProjectType: 1;
  subCategory: string;     // game_simulation/game_idle/game_chance/game_puzzle/fun_prank/...
}
```

### 4.7 分类体系（实测）

**主分类（category）**:
- Hot（热门）
- Latest（最新）
- Mindless（无脑放松）
- Brain Hack（益智）
- Unhinged（猎奇）
- Dopamine（多巴胺）
- Send This（转发分享）

**子分类（subCategory）**:
- `game_simulation` - 模拟经营
- `game_idle` - 放置/Idle
- `game_chance` - 随机/抽奖
- `game_puzzle` - 解谜
- `fun_prank` - 整蛊/有趣
- `relaxing_satisfying` - 解压满足
- `tool_canvas` - 工具/画板
- `visual_generative` - 视觉生成

**常见 Tags 标签**:
- 玩法: Click, RNG, Particle FX, Physics Sandbox, Action Reflex, Turn-based, VS
- 视觉: 3D Interactive Games, Light Glow, Color Play, Abstract Geometry, Liquid Motion
- 情绪: Satisfying Play, Relax Mood, Exciting, Dopamine

### 4.8 订阅与积分模型（实测）

| 套餐 | 价格/月 | Credits/月 | Stripe price_id |
|------|--------|-----------|----------------|
| Starter | $0 | 500 | — |
| Explorer | $19 | 2,000 | price_1RF9B5AsfbpdwUgqUGxh3VQe |
| Builder | $49 | 5,000 | price_1RF9CqAsfbpdwUgq5FR7MlDV |
| Master | $99 | 10,000 | price_1RF9E0AsfbpdwUgquEHZCI1c |
| Team | $199 | 20,000 | price_1RF9GYAsfbpdwUgqI9wrNqOe |

（来源：`/api/subscription/product/?productType=1` 实测）

### 4.9 CDN 与资源管理

| 类型 | URL 模式 | 说明 |
|------|---------|------|
| 游戏截图 | `cdn.aippy.ai/image/screenshot_{uuid}.png` | 自动截图 |
| 用户素材 | `cdn.aippy.ai/asset/{uuid}.{ext}` | 游戏内图片/音频 |
| 平台上传 | `cdn.aippy.ai/uploads/{uuid}.{ext}` | 用户头像/级别图标 |
| 图片压缩 | `?x-oss-process=style/p` | Alibaba Cloud OSS 图片处理 |
| 缩略图 | `?x-oss-process=style/thumbnail_middle` | 列表缩略图 |
| 音频格式 | `.m4a`（CDN 存储），`.mp3`（外链） | 支持外链音频 |

### 4.10 Analytics 双路追踪（实测）

1. **Google Analytics 4**: `G-LD0Z19ZH4P`
2. **ThinkingData（lolipopmobi）**: `appid=aab4794da88b49828062ac11a61359f3`
   - 自定义事件：`ta_page_show`、`home_page_view`、`home_page_stay`（含 `#duration` 停留时长）
   - 跨端：Web + iOS + Android (ReactNative Bridge) + Flutter

### 4.11 URL 结构

```
https://aippy.ai/                              # 首页 Feed
https://aippy.ai/@{username}                   # 用户主页
https://aippy.ai/@{username}/{game-slug}-{shortId}  # 游戏详情
https://aippy.ai/login                         # 登录
https://aippy.ai/privacy.html                  # 静态页
https://aippy.ai/terms.html

https://api.aippy.ai/api/...                   # 后端 API
https://cdn.aippy.ai/...                       # CDN 资源
https://{uuid}.aippy.live/?v={timestamp}       # 游戏运行
https://preview--{uuid}.aippy.live?v={ts}      # 游戏预览
```

---

## 五、项目适配分析（对比 GameMaker）

### 5.1 现有能力对齐

| Aippy 功能 | GameMaker 现状 | 差距 |
|-----------|-------------|------|
| AI 游戏生成 | ✅ 已有（Godot + MCP + Claude）| 技术路线不同，非 Web |
| 游戏运行沙箱 | ✅ Docker 容器隔离 | Aippy 用子域 iframe，更轻量 |
| 社区 Feed | ❌ 无 | 需完整建设 |
| 用户系统 | ✅ JWT 鉴权 | 缺少等级/积分/社交 |
| 媒体上传 | ✅ COS 存储 | 需对齐 CDN 图片处理策略 |
| 订阅/Credit | ❌ 无 | 需建设 Stripe 集成 |

### 5.2 核心技术路线差异

**Aippy 的选择（简单有效）**:
- 生成目标：React/TypeScript SPA → 单文件 HTML（230KB）
- 无构建依赖：无 npm install，秒级部署
- 运行时：纯前端，无服务端，成本低
- 限制：不支持后端逻辑、数据库、复杂状态

**GameMaker 的选择（功能丰富）**:
- 生成目标：Godot 4 项目（有状态、多平台导出）
- 需要容器编译，时间较长（分钟级）
- 支持原生移动端导出
- 适合更重度的游戏

### 5.3 若要 1:1 复制 Aippy，需要建设的核心模块

1. **AI Agent + SSE 流式架构**（核心）
   - 后端：Go SSE 流式输出（或 Node.js）
   - Agent 工具链：list_files / read_file / write_file / build / deploy
   - 前端：WebWorker + EventSource 消费

2. **React 游戏构建管线**（核心）
   - AI 生成 React + TypeScript 代码
   - 服务端 Vite 打包 → 单文件 inline HTML
   - 部署到 `{uuid}.{your-domain}` 子域

3. **游戏运行时 SDK**（重要）
   - `@your-brand/runtime` 包：Tweaks + Leaderboard
   - postMessage 协议（parent ↔ iframe）
   - iOS WebKit 桥接

4. **社区 Feed 系统**（重要）
   - 瀑布流 Feed + 分类过滤
   - 推荐算法（热门/最新/类目）
   - 互动：Like / Collect / Comment / Share / Remix

5. **子域部署基础设施**（中等）
   - Wildcard DNS `*.{domain}`
   - Nginx 泛域名路由
   - CDN + 版本化 URL

6. **订阅/积分系统**（中等）
   - Stripe 集成（5 套餐）
   - Credit 消耗与充值

---

## 六、推荐与参考资料

### 推荐方案

**核心判断**: Aippy 的技术架构本质上是「AI Agent + Vite SSR + 子域 iframe 沙箱 + 社区Feed」，技术门槛中等，复制完整度取决于 AI 生成质量与运营积累。

**推荐实施路径（分阶段）**:

**Phase 1（核心创作环）**:
- 将 AI 生成目标从 Godot 游戏切换（或新增）为 React/TypeScript 小游戏
- 建立 SSE 流式 Agent（工具链：write_file / build / deploy）
- Vite 服务端构建管线 → 单文件 HTML
- 子域部署（wildcard DNS + Nginx）

**Phase 2（社区环）**:
- 游戏 Feed（参照 `/api/template/recommend` 数据模型）
- 用户体系（等级/积分/关注）
- Like / Comment / Remix 互动

**Phase 3（商业化）**:
- Credit 系统 + Stripe 订阅
- Prompt 增强（`/api/llmodel/prompt/enhance`）
- 媒体素材上传（图片/音频管理）

**关键技术选型建议**:
| 组件 | 建议 | 说明 |
|------|------|------|
| AI 模型 | Claude Sonnet（现有）| 生成 React 效果好 |
| 游戏框架 | React 18 + TypeScript + Vite | 与 Aippy 同款 |
| 构建服务 | Node.js + Vite（服务端） | 秒级打包 |
| 子域方案 | Wildcard DNS + Nginx | 成本低 |
| CDN | 腾讯云 COS（现有）| 对标 Alibaba OSS |
| 支付 | Stripe | 与 Aippy 相同 |
| SSE 框架 | Go SSE（现有 Backend）| 复用现有能力 |

### 参考资料

- **Aippy 官网**: https://aippy.ai （实测）
- **Aippy API**: https://api.aippy.ai （实测）
- **Aippy 游戏运行时**: `https://{uuid}.aippy.live` （实测）
- **Aippy JS Bundle 分析**: `https://aippy.ai/assets/js/index-BqoiCaJw.js` （逆向）
- **Bolt.new 架构参考**: StackBlitz WebContainer 文档
- **Aippy 公司介绍**: [LinkedIn - NADA AI](https://www.linkedin.com/company/nada-ai)
- **产品分析文章**: [Aippy Kicks Off the Flywheel Before the Explosion of AI Games](https://eu.36kr.com) (2026-04-16)
- **Google Play**: https://play.google.com/store/apps/details?id=com.nadiai.aippy
- **App Store**: iOS 版 Aippy

---

*详细子报告见 `research-result/` 目录*
