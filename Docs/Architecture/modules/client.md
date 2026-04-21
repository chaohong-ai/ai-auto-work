# Client — Next.js 前端

> 端口：3000 | 目录：`Frontend/` | 语言：TypeScript

---

## 1. 选型理由

| 维度 | 选择 | 理由 | 不选 |
|------|------|------|------|
| 框架 | **Next.js 14** | App Router、SSR/SSG、API Routes、Image Optimization，React 生态最成熟的全栈框架 | Nuxt（Vue 生态）、SvelteKit（生态小） |
| UI 库 | **React 18** | 团队熟悉、生态丰富、Concurrent 特性（Suspense + Streaming）适合 SSE 实时场景 | Vue（生态略小）、Svelte（招人难） |
| 样式 | **Tailwind CSS** | 原子化 CSS、开发速度快、打包体积小 | styled-components（运行时开销）、CSS Modules（开发效率低） |
| 状态管理 | **React Hooks** | useState/useReducer + Context，应用状态简单够用 | Redux/Zustand（过重） |

**为什么选 Next.js？** 平台需要 SEO（游戏展示页、分享页）和实时交互（聊天/SSE）并存。Next.js SSR 处理前者，React Streaming 处理后者。AI 代码生成对 React 覆盖率最高。

---

## 2. 架构设计

```
Frontend/src/
├── app/                         # Next.js App Router（页面路由）
│   ├── games/                   #   游戏列表、详情页、分享页
│   ├── create/                  #   创建游戏：prompt 输入 + 模板选择
│   └── session/                 #   会话界面：聊天 + 实时预览 + 构建控制
├── components/                  # React 组件库
│   ├── chat/                    #   对话气泡、工具执行状态、AI 思考动画
│   ├── game/                    #   游戏卡片、截图轮播、状态标签
│   ├── editor/                  #   游戏预览面板、参数调整 UI
│   └── common/                  #   通用 UI（Button, Modal, Loading...）
├── hooks/                       # 自定义 Hooks（业务逻辑封装）
│   ├── useGames.ts              #   游戏 CRUD + 列表分页
│   ├── useSession.ts            #   会话创建/销毁/状态轮询
│   ├── useGameGeneration.ts     #   生成状态轮询 + 进度计算
│   ├── useSSE.ts                #   SSE 实时事件订阅（EventSource 封装）
│   └── useExport.ts             #   导出操作 + 下载
└── lib/
    ├── api.ts                   #   API 客户端：fetch 封装 + trace-id + 错误处理
    └── types.ts                 #   全局 TypeScript 类型（Game, Session, Task...）
```

---

## 3. 关键交互模式

| 模式 | 技术 | 说明 |
|------|------|------|
| **实时消息推送** | SSE (EventSource) | 生成进度、AI 思考过程、截图实时推送到浏览器 |
| **对话式交互** | REST + SSE | POST 发送消息 → SSE 接收 AI 回复流 |
| **游戏预览** | iframe / WebGL | 嵌入 Godot HTML5 导出的游戏运行时 |
| **乐观更新** | React State | 用户操作立即反映 UI，后台异步同步服务端 |
