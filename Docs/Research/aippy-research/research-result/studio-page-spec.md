# Aippy 游戏创作页（Studio）实测规格

**调研日期**: 2026-04-17  
**数据来源**: 用户实测截图（已登录账号）  
**被测页面**: `/project/{project-id}` — 游戏创作/编辑工作区

---

## 1. 页面整体结构

### 1.1 布局模式

Studio 页是三栏式布局，顶部有全局工具栏：

```
[Top Bar]
┌──────────────────┬──────────────┬────────────────────────────┐
│  Left Panel      │ Middle Panel │ Right / Main Panel         │
│  AI Chat         │ Asset Browser│ 动态内容区（Settings/资产） │
│  (对话 + 步骤)   │ (分类导航)   │                            │
└──────────────────┴──────────────┴────────────────────────────┘
[Bottom Input Bar]
```

### 1.2 Top Bar（顶部工具栏）

```
[← →] [项目标题（可内联编辑）]    [Studio | Preview]  [🔔] [Post▶] [头像]
```

| 元素 | 功能 |
|------|------|
| ← → | 操作历史（Undo/Redo 或页面导航） |
| 项目标题 | 点击可直接编辑（inline edit） |
| Studio \| Preview | 切换创作模式和游戏预览模式 |
| 🔔 | 消息通知 |
| Post | 发布到社区 Feed（绿色主 CTA） |
| 头像 | 用户账号菜单 |

---

## 2. Studio 模式（创作视图）

### 2.1 Left Panel — AI 对话区

**顶部：**
- Agent 名称标识：`Aippy`（头像圆圈）

**中部：步骤进度流**

每次 AI 生成游戏时，以列表形式实时显示步骤，完成打 ✅：

```
✅ Reviewed relevant information
✅ Reviewed relevant information
✅ Optimizing project organization
✅ Generated code
✅ Generated code
✅ Generated code
✅ Built project
```

步骤类型（已观测到的）：
- `Reviewed relevant information` — AI 检索上下文
- `Optimizing project organization` — 项目结构优化
- `Generated code` — 代码生成（可能执行多次）
- `Built project` — 项目构建完成

**下部：AI 总结 + 功能清单**

游戏构建完成后，AI 输出结构化总结：
```
我为您开发了一款结合复古像素美学与现代触感反馈的扫雷游戏。

■ 包含初级、中级、高级三种经典难度选择
■ 实现了"首次点击安全"机制与自动连锁展开功能
■ 适配移动端的长按揭旗操作与震动反馈
■ 实时计时的全球排行榜系统与复古像素音效
```

**Suggestions（主动建议区）**

AI 完成构建后自动生成 3 条改进建议，每条带 `→` 点击执行按钮：
```
允许玩家自行输入行数、列数和地雷数量，创建专属挑战关卡。  [→]
实现经典扫雷的"双击"功能，当周围数量匹配已归零时...       [→]
提供多种颜色配色方案（如经典灰、薰衣草紫、极致黑色）...    [→]
```

> **关键机制**：点击 `→` 按钮直接把该建议发送为新的 Prompt，触发下一轮 AI 迭代。

**底部：输入区**
```
[Type your idea and start building...]  [+] [↑] [→]
```
- 文本输入框：自然语言描述新需求
- `+`：添加附件/文件
- `↑`/`→`：发送

### 2.2 Middle Panel — Asset Browser（资产浏览器）

**标签页导航：**
```
Settings  |  Assets ▼
```

**Assets 折叠展开后的子分类：**
```
Assets
├── Image
├── Video
├── Audio
├── 3D
├── Fonts
└── Document
```

> **功能**：支持用户上传自定义资源（图片、视频、音频、3D 模型、字体、文档），上传后可被 AI 在生成游戏时引用。

### 2.3 Right Panel — Settings（设置面板）

Settings 面板内容：

| 字段 | 说明 |
|------|------|
| Project Name | 可编辑文本框 |
| Created at | 显示创建时间（只读），例：`Apr 17, 2026, 11:43 AM` |
| Visibility | 三选一单选组 |
| Thumbnail | 封面图上传（.jpg/.png/.gif，max 2MB） |
| Delete this project | 红色危险操作按钮 |

**Visibility 选项：**
```
⦿ Public & Remixable    — Anyone can view and remix.
○ Public & View Only    — Anyone can view, no remix.
○ Private               — Only friends with link you share can view.
```

**缩略图区域：**
- 右侧实时预览游戏截图作为缩略图
- 提示文字：`Thumbnails talk before your work does. Upload .jpg, .png, or .gif, max 2MB.`

---

## 3. Preview 模式（预览视图）

### 3.1 Layout 变化

切换到 Preview 后，布局简化为两栏：

```
┌──────────────────┬──────────────────────────────────────────┐
│  Left Panel      │  Game Canvas（游戏实际运行区域）           │
│  （项目列表）    │                                          │
└──────────────────┴──────────────────────────────────────────┘
```

### 3.2 Left Panel（Preview 模式）

```
[+ New Project]
─────────────────
Recent Projects
  ├── Retro Minesweeper  ◀ 当前项目（高亮）
  └── ...

（底部）
[Customize]  [+]  [↑]  [→]
```

- `New Project`：创建新游戏入口（醒目按钮）
- Recent Projects：最近项目列表，快速切换
- `Customize` 按钮：进入定制模式（替代 Studio 模式的完整对话）

### 3.3 Game Canvas（游戏运行区域）

- 游戏在主区域全屏渲染
- 已观测到的游戏渲染特性：
  - 自定义背景图（赛博朋克城市夜景）
  - 游戏 UI 覆盖层（顶部状态栏：❤️ 010 | 😊 | ⏱️ 000）
  - 难度切换 Tab：Easy | Medium | Hard
  - 游戏格子网格（8×7 cells）
  - 像素风格格子按钮
- 可直接在 Preview 模式内进行游戏交互

### 3.4 Top Bar 附加功能（Preview 模式）

Preview 模式的 Top Bar 右侧额外出现：
- 截图/分享按钮（相机图标）
- 嵌入/导出按钮（代码图标）

### 3.5 Preview 刷新机制

- Preview 界面支持手动刷新（刷新按钮 🔄）
- **刷新后拉取最新版本游戏**：每次 AI 迭代后，Preview 不会自动热更新，用户需要手动刷新才能看到最新构建结果
- 这意味着游戏构建是异步的：AI 在 Studio 侧生成新版本 → 用户切换/刷新 Preview → 加载新版本

> **实现启示**：Studio 和 Preview 使用不同的"版本快照"，Preview 刷新 = 拉取最新 build artifact，不是实时 hot-reload。

---

## 4. 核心 UX 流程

### 4.1 首次创建游戏流程

```
1. 在输入框输入自然语言描述
2. AI 开始执行，Left Panel 实时显示步骤进度
3. 步骤完成（Reviewed → Generated → Built）
4. AI 输出游戏总结 + 功能清单
5. AI 自动生成 3 条 Suggestions
6. 用户切换到 Preview 模式 → 游戏可运行
```

### 4.2 迭代优化流程

```
方式A：点击 Suggestion → 按钮直接发送为 Prompt → 触发新一轮生成
方式B：手动在输入框描述修改需求 → 触发新一轮生成
方式C：点击 Customize（Preview 模式）→ 进入定制界面
```

### 4.3 资源上传流程

```
Assets → 选择分类（Image/Video/Audio/3D/Fonts/Document）
→ 上传文件
→ AI 在后续生成中可引用这些资源
```

### 4.4 发布流程

```
设置 Visibility → 配置封面图（Thumbnail）→ 点击 Post → 发布到社区 Feed
```

---

## 5. 关键产品机制总结

| 机制 | 说明 |
|------|------|
| 步骤可视化 | AI 生成过程完全透明，用户实时看到每一步 |
| Suggestions 飞轮 | 完成后主动推荐改进方向，驱动持续创作 |
| Studio/Preview 双模式 | 创作和体验分离，Preview 可真实游玩 |
| Remix 机制 | 通过 Visibility 设置控制是否允许他人 Remix |
| 多类型资源上传 | 支持 Image/Video/Audio/3D/Fonts/Document |
| 项目管理 | Recent Projects 列表 + New Project 快速创建 |
| 发布门槛极低 | 一键 Post 即可发布到社区 |

---

## 6. 与 GameMaker 的对比差距（实现参考）

| 功能 | Aippy | 我们现有能力 | 优先级 |
|------|-------|------------|--------|
| 步骤进度可视化 | ✅ 实时显示 | ❌ 无 | P0 |
| Studio/Preview 双模式 | ✅ | ❌ 只有创作 | P0 |
| AI Suggestions 建议 | ✅ 3条/次 | ❌ 无 | P1 |
| 多类型资源上传 | ✅ 6种 | ❌ 无 | P1 |
| Remix 可见性控制 | ✅ 3级 | ❌ 无 | P1 |
| 项目列表快速切换 | ✅ | ❌ | P2 |
| 封面图上传 | ✅ | ❌ | P2 |
