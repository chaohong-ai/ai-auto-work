# Editor Module Architecture

## Overview

The GameMaker Editor is a desktop AI game creation application built with Tauri v2 + Next.js 14. It provides a chat-based interface for creating games through AI, with real-time preview and multi-LLM support.

## Technology Stack

- **Desktop Shell**: Tauri v2 (Rust backend, system WebView2)
- **Frontend**: Next.js 14 (static export) + React 18 + TypeScript
- **Styling**: Tailwind CSS with brand color palette
- **Testing**: Jest + ts-jest
- **State**: React hooks + Context API (no external state library)

## Architecture

```
Editor (Tauri WebView)
    |
    ├── React App (Static HTML/JS)
    |   ├── Pages: /, /login, /editor, /settings
    |   ├── Hooks: useAuth, useSession, useSettings, useFetchSSE
    |   └── Components: Chat, Preview, Layout, Auth, Settings, UI
    |
    ├── lib/api.ts ─── HTTP/REST ───> Backend (:18081)
    └── lib/fetch-sse.ts ── SSE ───> Backend (:18081)
```

## Communication

The Editor communicates directly with the Backend API using standard protocols:

- **REST**: All CRUD operations (sessions, games, auth, exports)
- **SSE**: Real-time events during builds (screenshots, progress, completion)
- **Auth**: JWT Bearer token in Authorization header

Key difference from Frontend: The Editor uses `fetch`-based SSE (not `EventSource`) to support Authorization headers on SSE connections.

## Directory Structure

```
Editor/
├── src-tauri/           # Tauri Rust shell
├── src/
│   ├── app/             # Next.js pages (static export)
│   ├── components/      # React components
│   │   ├── auth/        # Login, AuthProvider
│   │   ├── chat/        # ChatPanel, MessageBubble, PromptInput
│   │   ├── layout/      # EditorLayout (split pane), TitleBar
│   │   ├── preview/     # PreviewPanel, ScreenshotView, BuildProgress
│   │   ├── session/     # SessionList
│   │   ├── settings/    # SettingsForm, ProviderConfig
│   │   └── ui/          # Button, Input, Loading
│   ├── hooks/           # React hooks
│   └── lib/             # API client, types, config, SSE parser
├── __tests__/           # Jest tests
├── package.json
├── next.config.js       # output: 'export'
└── tailwind.config.ts
```

## Key Design Decisions

### 1. Tauri v2 over Electron
- 10x smaller binary (<10MB vs 100MB+)
- 8x lower memory (~30MB vs ~250MB idle)
- Native WebView2 (Windows) instead of bundled Chromium
- Tauri v2 supports Windows/macOS/Linux/iOS/Android

### 2. Static Export (not SSR)
- `output: 'export'` produces pure static HTML/JS/CSS
- No server-side rendering required (Tauri loads from filesystem)
- All data fetching happens client-side via API calls
- `next/image` replaced with native `<img>` (unoptimized: true)
- Dynamic routes replaced with query parameters (`/editor?id=xxx`)

### 3. fetch-based SSE (not EventSource)
- `EventSource` API cannot set custom HTTP headers
- Backend SSE endpoints require JWT authentication
- Solution: `fetch()` with `ReadableStream` parsing SSE text format
- Supports `Authorization: Bearer {token}` header
- Includes reconnection logic (3 retries, 3s interval)

### 4. Independent from Frontend
- Editor and Frontend are separate Next.js projects
- Types defined independently from Backend API contract
- API client uses configurable absolute URLs (not proxy rewrites)
- No runtime code sharing to avoid coupling

## Relationship to Other Modules

| Module | Relationship | Protocol |
|--------|-------------|----------|
| Backend | Direct API consumer | REST + SSE over HTTP |
| MCP | Indirect (via Backend) | N/A |
| Engine | Indirect (via Backend → MCP) | N/A |
| Frontend | Peer (same Backend API) | N/A |

## Configuration

Local settings stored in browser localStorage (Tauri store planned):

```typescript
interface EditorSettings {
  backendUrl: string;        // Default: http://localhost:18081
  providers: ProviderConfig[]; // Claude, OpenAI, Gemini, GLM
  splitRatio: number;        // Default: 0.4
  recentSessions: string[];  // Last 10 session IDs
}
```

## Testing

- **Unit tests**: Jest + ts-jest for lib/ and hooks
- **Component tests**: @testing-library/react for UI components
- **Type checking**: `tsc --noEmit` as build gate
- **Build gate**: `next build` static export as compile gate
