# Aippy 游戏运行时 SDK 逆向分析

**数据来源**: 游戏 HTML 源码逆向 (`*.aippy.live`)  
**调研日期**: 2026-04-17

---

## 1. 游戏部署格式

### 文件结构
每个游戏是一个**单文件 HTML**，无外部 JS/CSS 依赖。

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <!-- 1. 资源预加载（自定义 meta 标签） -->
  <meta name="aippy:preload" content="https://cdn.aippy.ai/uploads/{uuid}.mp3">
  <meta name="aippy:preload" content="https://www.myinstants.com/media/sounds/xxx.mp3">
  <!-- ... 更多 preload ... -->
  
  <!-- 2. 无外部 CSS/JS 引用 -->
</head>
<body>
  <!-- 3. 单个内联 <script> 包含完整 React 应用 -->
  <script>/* ~230KB minified React bundle */</script>
</body>
</html>
```

### 关键特征
- **大小**: 典型 ~230KB 内联 JS（实测 "The Meme Soundboard"）
- **框架**: React 18（含 `Symbol.for("react.transitional.element")`）
- **构建**: Vite 打包，无代码分割（单文件适合 CDN 缓存）
- **页面标题**: "Aippy Viby Zappy"（运行时容器名）

---

## 2. @aippy/runtime SDK 功能

SDK 功能以单个 JS bundle 形式注入游戏，而非 npm 包导入。包含两大模块：

### 2.1 Aippy Tweaks（运行时参数面板）

允许游戏暴露可调节参数，父页面（aippy.ai）可以实时更新这些参数。

**游戏代码使用方式（推测，基于逆向）**:
```typescript
import { tweaks } from "@aippy/runtime";

// 声明可调参数
const gameSettings = tweaks({
  speed: { type: "number", default: 1.0, min: 0.1, max: 10 },
  theme: { type: "string", default: "dark", options: ["dark", "light"] },
  gravity: { type: "number", default: 9.8 }
});

// 使用参数（响应式更新）
const [speed] = gameSettings.speed.useState();
```

**内部通信协议（逆向确认）**:

游戏 → 父页面（初始化）:
```javascript
window.parent.postMessage({
  type: "tweaks-initialize",
  config: JSON.stringify({
    speed: { type: "number", default: 1.0 },
    theme: { type: "string", default: "dark" }
  })
}, "*");

// 同时发送 ready 消息
window.parent.postMessage({
  type: "aippy-tweaks-ready",
  aippyTweaksRuntime: {
    tweaks: window.aippyTweaksRuntime?.tweaks,
    tweaksInstance: window.aippyTweaksRuntime?.tweaksInstance
  }
}, "*");
```

父页面 → 游戏（更新参数）:
```javascript
iframe.contentWindow.postMessage({
  type: "tweaks-update",
  speed: { value: 2.0 },
  theme: { value: "light" }
}, "*");
```

iOS 原生通信:
```javascript
window.webkit.messageHandlers.aippyListener.postMessage({
  command: "tweaks.initialize",
  parameters: JSON.stringify(config)
});
```

**错误处理**:
- `tweaks()` 只能调用一次，多次调用返回同一实例并打印警告
- 父页面不存在时（直接访问游戏 URL）：`Failed to send to parent window`（只有 warning，不影响游戏运行）

### 2.2 Aippy Leaderboard（排行榜）

**游戏代码使用方式**:
```typescript
import { updateScore } from "@aippy/runtime/leaderboard";

// 更新分数
updateScore(100);
// 内部：postMessage({type: "score", score: 100, url: location.href})
```

**内部通信协议**:
```javascript
// 发送分数事件
function updateScore(score) {
  const payload = { type: "score", score, url: window.location.href };
  
  // Web 父页面
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ __aippyGame: true, payload }, "*");
  }
  
  // iOS 原生
  const bridge = window.webkit?.messageHandlers?.aippyListener;
  if (bridge) {
    bridge.postMessage({
      command: "leaderboard.updateScore",
      parameters: JSON.stringify(payload)
    });
  }
  
  console.log(`[Aippy Leaderboard] Score updated: ${score}, URL: ${url}`);
}
```

**游戏内存储**: 使用 `localStorage` 保存游戏进度
```javascript
// 自动保存（游戏内日志）
console.log("[Aippy] Auto-saved game data");
console.log("[Aippy] Saved on page unload");
console.log("[Aippy] Saved on visibility change");
```

---

## 3. 游戏初始化生命周期

基于 console 日志逆向分析的初始化流程：

```
1. [Aippy] No save data found, creating new game  OR  [Aippy] Save data loaded
2. [Aippy] App initialized
3. [Aippy] {GameName} initialized            ← 各游戏自定义初始化
4. [Aippy Tweaks] ⚠️ tweaks() expected once  ← 如果在非 Aippy 宿主中运行
5. [Aippy Leaderboard] Score updated: 0      ← 初始分数上报
6. [Aippy] Auto-saved game data              ← 定时自动保存
7. [Aippy] Achievement unlocked: xxx         ← 成就系统
```

---

## 4. 游戏 → 父页面通信完整协议

| 事件方向 | type | payload | 触发时机 |
|---------|------|---------|---------|
| 游戏→父 | `tweaks-initialize` | `{ config: JSON }` | 游戏 mount 时 |
| 游戏→父 | `aippy-tweaks-ready` | `{ aippyTweaksRuntime }` | 游戏 mount 时 |
| 游戏→父 | `__aippyGame + payload` | `{ type: "score", score, url }` | 分数变化 |
| 父→游戏 | `tweaks-update` | `{ [key]: { value } }` | 用户调整参数 |

---

## 5. 资源预加载机制

游戏 HTML head 中使用自定义 meta 标签预加载资源：
```html
<meta name="aippy:preload" content="{url}">
```

支持的资源类型：
- **CDN 音频**: `cdn.aippy.ai/uploads/{uuid}.mp3` / `.m4a`
- **外链音频**: `www.myinstants.com/media/sounds/xxx.mp3`
- **第三方 CDN**: `assets.mixkit.co/active_storage/sfx/{id}-preview.mp3`

音频格式偏好：
- CDN 存储用 `.m4a`（AAC，移动端友好）
- 外链用 `.mp3`（兼容性好）

---

## 6. 设备能力声明

游戏在发布时声明 `deviceCapability`，父页面据此展示能力标签：

```json
["haptic-feedback", "local-storage"]
```

已知值：
- `haptic-feedback` — 触觉反馈（移动端）
- `local-storage` — 本地存储（进度保存）

---

## 7. 游戏 URL 约定

| 环境 | URL 格式 | 说明 |
|-----|---------|------|
| 正式版 | `https://{siteId}.aippy.live/?v={timestamp}` | 发布后访问 |
| 预览版 | `https://preview--{siteId}.aippy.live?v={build-ts}?v={latest-ts}` | 构建完但未发布 |
| 版本历史 | `?v={older-timestamp}` | 可通过修改 v 参数访问旧版本 |

**注意**: `previewUrl` 的格式是 `?v=X?v=Y`（两个 v 参数，可能是 bug 或历史原因）

---

## 8. 复刻 SDK 需要实现的内容

```typescript
// packages/runtime/src/index.ts

export interface TweakConfig {
  [key: string]: {
    type: "number" | "string" | "boolean";
    default: any;
    min?: number;
    max?: number;
    options?: any[];
  }
}

export function tweaks<T extends TweakConfig>(config: T): {
  [K in keyof T]: { useState: () => [T[K]["default"], (v: any) => void] }
} {
  // 1. 初始化 state
  // 2. postMessage tweaks-initialize 到父页面
  // 3. 监听 tweaks-update 消息更新 state
  // 4. iOS webkit bridge 同步
}

// packages/runtime/src/leaderboard.ts
export function updateScore(score: number): void {
  // postMessage to parent + iOS bridge
}

// packages/runtime/src/storage.ts
export function saveGame(data: object): void { /* localStorage */ }
export function loadGame(): object | null { /* localStorage */ }
```
