
# GameMaker - AI Native 游戏创作平台

用户通过自然语言对话，自动完成游戏的设计、开发、构建和多平台导出。

## 项目简介

GameMaker 是一个 AI 驱动的游戏创作平台。用户在浏览器中描述游戏想法，系统借助大语言模型进行游戏逻辑编排，通过 MCP 工具链操作 Godot 4 引擎构建游戏，并调用第三方 AI 平台生成图片、音效等游戏资源。最终产出可在 iOS、Android、Web、Windows 等多平台运行的完整游戏。

核心流程：`用户描述 → AI 理解需求 → 生成游戏规格 → 调用工具构建场景/脚本 → AI 生成资源 → 验证修复 → 多平台导出`

## AI 工作目录约定

本仓库已经整理为多 agent 共用目录：

- `.ai/` 是共享上下文层，适用于 Claude Code、Codex 等所有 agent
- `.claude/` 是 Claude Code 专用运行时层，保留 commands、skills、plans、logs 等能力

Claude 在工作时，应优先读取共享层，再按需读取 Claude 专用层。

@.ai/context/project.md
@.ai/constitution.md

### 按需加载（不默认装载）

- **模块判定优先**：先根据需求文本、计划文件、任务清单、目标文件路径判断命中模块；未命中的模块文档不要预读
  - 只改 `Backend/` → 读取 `.ai/constitution/backend.md` + `.ai/context/backend-lifecycle.md`；不读取 MCP / Engine / Godot / GameServer 文档
  - 只改 `Frontend/` → 不读取 Backend / MCP / Engine / GameServer 文档
  - 只改 `MCP/` → 涉及跨语言契约时读取 `.ai/constitution/cross-module.md`；不读取 GameServer 文档
  - 只改 `Tools/` → 不读取 Frontend / MCP / Engine / GameServer 文档
  - 只改 `Engine/` → 读取 `.ai/constitution/engine.md`；不读取 GameServer 文档
  - 只改 `GameServer/` → 读取 `GameServer/CLAUDE.md`（通用入口），再根据命中的子服务读取对应 `servers/<name>/CLAUDE.md`；**不读取** Backend / MCP / Engine / Frontend 的宪法和生命周期文档（GameServer 是独立领域，技术栈和架构模式与创作平台完全不同）
  - 只有同时出现跨目录耦合、跨模块接口变更、端到端链路变更时，才读取系统级架构文档
- **宪法详细规则**：命中特定场景时读取对应子文件
  - Backend Go 代码（并发/锁/ctx/生命周期/错误比较/JSON tag/HTTP超时/Config校验） → `.ai/constitution/backend.md`
  - 测试验收、Plan Review、Develop Review、路由测试、回归命令执行 → `.ai/constitution/testing-review.md`（文件内已用 [通用]/[创作平台] 标签分域，GameServer review 只需关注 [通用] 标签的规则）
  - 跨模块 API 通信（鉴权/契约/幂等） → `.ai/constitution/cross-module.md`
  - Engine / 多平台导出 / GDScript 编码规范（封装/空值守卫/魔法数字） → `.ai/constitution/engine.md`
- **项目详细约束**：
  - Backend Session/Container/Shutdown 生命周期 → `.ai/context/backend-lifecycle.md`
- **架构文档**：涉及特定模块时读取对应文件
  - Backend → `Docs/Architecture/modules/backend.md`
  - MCP → `Docs/Architecture/modules/mcp-server.md`
  - Frontend/Client → `Docs/Architecture/modules/client.md`
  - Engine → `Docs/Architecture/modules/engine.md`
  - Tools → `Docs/Architecture/modules/tools.md`
  - GameServer → `Docs/Architecture/modules/gameserver.md`
  - 跨模块大改 → `Docs/Architecture/system-architecture.md`（注意：GameServer 与创作平台之间不存在跨模块调用，不需要联合加载）
- **Review 执行标准**：执行 develop-review / plan-review 前 → `.ai/context/reviewer-brief.md`
- **Claude 详细宪法**：需要代码级规则和示例时读取 `.claude/constitution.md`
- **游戏网络协议**：涉及 Godot 客户端与 GameServer 网络通信时读取
  - Godot 客户端网络（GateClient/PacketCodec/Proto 使用） → `Docs/Engine/14-game-networking/networking-guide.md`
- **专题规则**：仅在命中特定场景时读取
  - Fake / mock 闭环、E2E 注入链路 → `.claude/guides/fake-env-closure.md`
  - Go `context.Canceled` / `DeadlineExceeded`、`Shutdown`、后台任务取消 → `.claude/guides/go-cancellation-semantics.md`
  - auto-work CLI trace、stage 标注、trace_view → `.claude/guides/cli-trace.md`
