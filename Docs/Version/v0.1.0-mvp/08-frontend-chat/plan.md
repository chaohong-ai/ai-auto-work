# 08-前端对话界面 技术规格

## 1. 概述

React + Next.js 前端，提供 AI 对话式游戏创建界面。用户通过自然语言描述游戏需求，实时查看生成进度和截图预览，最终在浏览器中游玩生成的 H5 游戏。

**范围**：
- 对话式生成界面（输入 Prompt → 流式进度 → 截图预览 → 游玩）
- 游戏大厅（浏览所有游戏）
- 游戏详情页（游玩 H5 iframe + 信息）
- SSE 流式进度展示

**不做**：
- 用户注册/登录（Phase 0 跳过）
- 个人主页/社交功能（Phase 1）
- 素材编辑器（Phase 2）
- 移动端适配（Phase 1）

## 2. 文件清单

```
Frontend/
├── package.json
├── next.config.js
├── tsconfig.json
├── tailwind.config.js
├── .env.local.example
├── public/
│   ├── favicon.ico
│   └── images/
│       └── logo.svg
├── src/
│   ├── app/
│   │   ├── layout.tsx              # 全局布局
│   │   ├── page.tsx                # 首页（→ 游戏大厅）
│   │   ├── create/
│   │   │   └── page.tsx            # 创建游戏页面
│   │   ├── games/
│   │   │   ├── page.tsx            # 游戏大厅
│   │   │   └── [id]/
│   │   │       └── page.tsx        # 游戏详情/游玩页
│   │   └── api/                    # Next.js API routes (proxy)
│   │       └── ...
│   ├── components/
│   │   ├── layout/
│   │   │   ├── Header.tsx
│   │   │   └── Footer.tsx
│   │   ├── create/
│   │   │   ├── ChatInterface.tsx       # 对话界面主组件
│   │   │   ├── MessageBubble.tsx       # 消息气泡
│   │   │   ├── PromptInput.tsx         # 输入框
│   │   │   ├── GenerationProgress.tsx  # 生成进度展示
│   │   │   ├── StepIndicator.tsx       # 步骤指示器
│   │   │   ├── ScreenshotPreview.tsx   # 截图预览
│   │   │   └── TemplateSelector.tsx    # 模板选择（可选）
│   │   ├── games/
│   │   │   ├── GameCard.tsx            # 游戏卡片
│   │   │   ├── GameGrid.tsx            # 游戏网格
│   │   │   └── GamePlayer.tsx          # H5 游戏播放器 (iframe)
│   │   └── ui/
│   │       ├── Button.tsx
│   │       ├── Input.tsx
│   │       ├── Loading.tsx
│   │       └── Badge.tsx
│   ├── hooks/
│   │   ├── useSSE.ts                   # SSE 连接 Hook
│   │   ├── useGameGeneration.ts        # 生成流程状态管理
│   │   └── useGames.ts                 # 游戏列表 Hook
│   ├── lib/
│   │   ├── api.ts                      # API 客户端
│   │   └── types.ts                    # TypeScript 类型定义
│   └── styles/
│       └── globals.css
```

## 3. 页面设计

### 3.1 创建游戏页面 (/create)

```
┌─────────────────────────────────────────────────────┐
│  [Logo] GameMaker AI                    [大厅] [创建] │
├─────────────────────────────────────────────────────┤
│                                                       │
│  ┌─────────────────────┐  ┌─────────────────────┐   │
│  │    对话区域           │  │    预览区域           │   │
│  │                      │  │                      │   │
│  │  🤖 你好！描述你想做  │  │  ┌──────────────┐   │   │
│  │     的游戏吧         │  │  │              │   │   │
│  │                      │  │  │  截图预览     │   │   │
│  │  👤 做一个平台跳跃    │  │  │  (实时更新)   │   │   │
│  │     游戏...          │  │  │              │   │   │
│  │                      │  │  └──────────────┘   │   │
│  │  🤖 好的，我来创建！  │  │                      │   │
│  │                      │  │  ── 生成进度 ──      │   │
│  │  ⚙️ 步骤 1/8:        │  │  [■■■■■□□□] 62%      │   │
│  │    正在应用模板...    │  │                      │   │
│  │                      │  │  ✅ 模板已应用        │   │
│  │  ⚙️ 步骤 2/8:        │  │  ✅ 玩家已添加        │   │
│  │    正在添加玩家...    │  │  ⏳ 添加敌人...       │   │
│  │                      │  │  ○ 验证场景          │   │
│  │                      │  │  ○ 导出 H5           │   │
│  ├──────────────────────┤  │                      │   │
│  │ [输入你的游戏想法...] │  │  [▶️ 开始游玩]       │   │
│  │                 [发送]│  │                      │   │
│  └──────────────────────┘  └─────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### 3.2 游戏大厅 (/games)

```
┌─────────────────────────────────────────────────────┐
│  [Logo] GameMaker AI                    [大厅] [创建] │
├─────────────────────────────────────────────────────┤
│  最新游戏                                  [搜索...]  │
│                                                       │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐               │
│  │ 截图 │ │ 截图 │ │ 截图 │ │ 截图 │               │
│  │      │ │      │ │      │ │      │               │
│  │ 名称 │ │ 名称 │ │ 名称 │ │ 名称 │               │
│  │ 描述 │ │ 描述 │ │ 描述 │ │ 描述 │               │
│  │▶️ 12 │ │▶️ 8  │ │▶️ 45 │ │▶️ 3  │               │
│  └──────┘ └──────┘ └──────┘ └──────┘               │
└─────────────────────────────────────────────────────┘
```

### 3.3 游戏详情页 (/games/[id])

```
┌─────────────────────────────────────────────────────┐
│  [← 返回大厅]                                        │
├─────────────────────────────────────────────────────┤
│                                                       │
│  ┌─────────────────────────────────────────────┐    │
│  │                                               │    │
│  │           H5 游戏 iframe                       │    │
│  │           (全屏可玩)                            │    │
│  │                                               │    │
│  └─────────────────────────────────────────────┘    │
│                                                       │
│  游戏名称                                    [全屏]   │
│  游戏描述...                                          │
│  ▶️ 123 次游玩   ❤️ 45 赞                             │
│                                                       │
│  创建 Prompt: "做一个平台跳跃游戏..."                  │
└─────────────────────────────────────────────────────┘
```

## 4. 核心组件

### 4.1 SSE Hook

```typescript
// src/hooks/useSSE.ts

interface SSEEvent {
  type: 'status' | 'step' | 'verify' | 'screenshot' | 'heal' | 'complete' | 'error';
  data: any;
}

export function useSSE(taskId: string | null) {
  const [events, setEvents] = useState<SSEEvent[]>([]);
  const [status, setStatus] = useState<'connecting' | 'connected' | 'closed'>('connecting');
  const [latestScreenshot, setLatestScreenshot] = useState<string | null>(null);
  const [isComplete, setIsComplete] = useState(false);
  const [result, setResult] = useState<any>(null);

  useEffect(() => {
    if (!taskId) return;

    const eventSource = new EventSource(`/api/games/${taskId}/generate/stream`);

    eventSource.onopen = () => setStatus('connected');

    eventSource.addEventListener('step', (e) => {
      const data = JSON.parse(e.data);
      setEvents(prev => [...prev, { type: 'step', data }]);
    });

    eventSource.addEventListener('screenshot', (e) => {
      const data = JSON.parse(e.data);
      setLatestScreenshot(data.base64);
    });

    eventSource.addEventListener('complete', (e) => {
      const data = JSON.parse(e.data);
      setResult(data);
      setIsComplete(true);
      eventSource.close();
    });

    eventSource.addEventListener('error', (e) => {
      // 处理错误
    });

    return () => eventSource.close();
  }, [taskId]);

  return { events, status, latestScreenshot, isComplete, result };
}
```

### 4.2 游戏生成流程 Hook

```typescript
// src/hooks/useGameGeneration.ts

interface GenerationState {
  phase: 'idle' | 'submitting' | 'queued' | 'generating' | 'complete' | 'failed';
  gameId: string | null;
  taskId: string | null;
  steps: StepEvent[];
  currentStep: number;
  totalSteps: number;
  screenshot: string | null;
  gameUrl: string | null;
  error: string | null;
}

export function useGameGeneration() {
  const [state, setState] = useState<GenerationState>({ phase: 'idle', ... });

  const startGeneration = async (prompt: string, template?: string) => {
    setState(s => ({ ...s, phase: 'submitting' }));

    // POST /api/games
    const { gameId, taskId } = await api.createGame({ prompt, template });
    setState(s => ({ ...s, phase: 'queued', gameId, taskId }));
  };

  // SSE 连接
  const { events, latestScreenshot, isComplete, result } = useSSE(state.taskId);

  // 根据 SSE 事件更新状态
  useEffect(() => {
    if (events.length > 0) {
      const latest = events[events.length - 1];
      // 更新 steps, currentStep, phase 等
    }
  }, [events]);

  useEffect(() => {
    if (latestScreenshot) {
      setState(s => ({ ...s, screenshot: latestScreenshot }));
    }
  }, [latestScreenshot]);

  useEffect(() => {
    if (isComplete && result) {
      setState(s => ({
        ...s,
        phase: result.status === 'success' ? 'complete' : 'failed',
        gameUrl: result.game_url,
      }));
    }
  }, [isComplete, result]);

  return { state, startGeneration };
}
```

### 4.3 对话界面

```typescript
// src/components/create/ChatInterface.tsx

interface Message {
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: Date;
  screenshot?: string;
  steps?: StepEvent[];
}

export function ChatInterface() {
  const [messages, setMessages] = useState<Message[]>([
    { role: 'assistant', content: '你好！描述你想做的游戏，我来帮你创建。', timestamp: new Date() }
  ]);
  const { state, startGeneration } = useGameGeneration();

  const handleSend = async (prompt: string) => {
    // 添加用户消息
    setMessages(prev => [...prev, { role: 'user', content: prompt, timestamp: new Date() }]);

    // 添加 AI 响应（流式更新）
    setMessages(prev => [...prev, {
      role: 'assistant',
      content: '好的，我来创建这个游戏！',
      timestamp: new Date()
    }]);

    await startGeneration(prompt);
  };

  // 根据生成状态更新最后一条 AI 消息
  useEffect(() => {
    if (state.phase === 'generating') {
      // 更新消息中的步骤和截图
    }
    if (state.phase === 'complete') {
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: '游戏创建完成！点击下方按钮开始游玩。',
        timestamp: new Date(),
        screenshot: state.screenshot,
      }]);
    }
  }, [state]);

  return (
    <div className="flex h-full">
      {/* 左侧：对话区 */}
      <div className="flex-1 flex flex-col">
        <div className="flex-1 overflow-y-auto p-4">
          {messages.map((msg, i) => <MessageBubble key={i} message={msg} />)}
        </div>
        <PromptInput onSend={handleSend} disabled={state.phase === 'generating'} />
      </div>

      {/* 右侧：预览区 */}
      <div className="w-96 border-l p-4">
        {state.screenshot && <ScreenshotPreview src={state.screenshot} />}
        <GenerationProgress steps={state.steps} currentStep={state.currentStep} />
        {state.gameUrl && (
          <a href={`/games/${state.gameId}`} className="btn-primary mt-4 block text-center">
            开始游玩
          </a>
        )}
      </div>
    </div>
  );
}
```

### 4.4 游戏播放器

```typescript
// src/components/games/GamePlayer.tsx

export function GamePlayer({ gameUrl }: { gameUrl: string }) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [isFullscreen, setIsFullscreen] = useState(false);

  const toggleFullscreen = () => {
    if (iframeRef.current) {
      if (!isFullscreen) {
        iframeRef.current.requestFullscreen();
      } else {
        document.exitFullscreen();
      }
      setIsFullscreen(!isFullscreen);
    }
  };

  return (
    <div className="relative">
      <iframe
        ref={iframeRef}
        src={gameUrl}
        className="w-full aspect-video border rounded-lg"
        sandbox="allow-scripts allow-same-origin"
        allow="fullscreen"
      />
      <button onClick={toggleFullscreen} className="absolute top-2 right-2">
        全屏
      </button>
    </div>
  );
}
```

## 5. API 客户端

```typescript
// src/lib/api.ts

const BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080';

export const api = {
  createGame: async (data: { prompt: string; template?: string }) => {
    const res = await fetch(`${BASE_URL}/api/games`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    return res.json();
  },

  getGames: async () => {
    const res = await fetch(`${BASE_URL}/api/games`);
    return res.json();
  },

  getGame: async (id: string) => {
    const res = await fetch(`${BASE_URL}/api/games/${id}`);
    return res.json();
  },

  searchAssets: async (query: string, type?: string) => {
    const params = new URLSearchParams({ query });
    if (type) params.set('type', type);
    const res = await fetch(`${BASE_URL}/api/assets/search?${params}`);
    return res.json();
  },
};
```

## 6. TypeScript 类型

```typescript
// src/lib/types.ts

export interface Game {
  id: string;
  prompt: string;
  title: string;
  description: string;
  template: string;
  status: 'draft' | 'queued' | 'generating' | 'ready' | 'failed';
  screenshot_url: string | null;
  game_url: string | null;
  play_count: number;
  like_count: number;
  created_at: string;
}

export interface StepEvent {
  step: number;
  tool: string;
  status: 'executing' | 'done' | 'failed';
  message?: string;
}

export interface VerifyEvent {
  layer: 'static' | 'run' | 'screenshot' | 'logic';
  passed: boolean;
  errors?: string[];
}

export interface GenerationComplete {
  status: 'success' | 'partial' | 'failed';
  game_url?: string;
  screenshot?: string;
  steps_count: number;
  heal_attempts: number;
}
```

## 7. 依赖

```json
{
  "dependencies": {
    "next": "^14",
    "react": "^18",
    "react-dom": "^18",
    "tailwindcss": "^3"
  },
  "devDependencies": {
    "typescript": "^5",
    "@types/react": "^18",
    "@types/node": "^20"
  }
}
```

## 8. 验收标准

1. **首页**：打开 localhost:3000 显示游戏大厅
2. **创建页面**：/create 页面有对话输入框和预览区域
3. **发送 Prompt**：输入 Prompt 后 POST 到后端，获得 game_id
4. **SSE 进度**：生成过程中左侧对话区实时显示步骤进度
5. **截图预览**：右侧预览区实时显示最新截图
6. **进度条**：显示当前进度百分比和步骤列表
7. **生成完成**：完成后显示"开始游玩"按钮
8. **游戏大厅**：/games 显示所有已生成游戏的卡片网格
9. **游戏详情**：/games/[id] 页面嵌入 H5 iframe 可游玩
10. **全屏游玩**：iframe 支持全屏模式
11. **端到端**：输入 Prompt → 看到进度 → 截图更新 → 点击游玩 → H5 游戏正常运行
