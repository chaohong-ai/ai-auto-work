# Aippy UI/UX 规格（实测）

**调研日期**: 2026-04-17  
**调研方式**: 浏览器实测截图 + Accessibility Snapshot 分析

---

## 1. 整体布局结构

### 1.1 导航栏（Nav）
```
[Logo] [Aippy Logo]    [Play on mobile 🔗] [Globe 🌐] [Sign In] [Sign Up]
```
- 固定在顶部
- 左：品牌 Logo
- 右：移动端下载入口 + 语言切换 + 认证按钮

### 1.2 首页（未登录）
```
[Nav]
[Hero Section]
  - 大图标 + "Build What You Feel."
  - Prompt 输入框 + 按钮组（发送/图片/文件）
  - 快捷 Prompt 标签：iPhone Meme Unlock / Heartbreak Simulator / Gravity Simulator / Bumble Crinble

[Feed Section]
  [分类 Tab]：Hot | Latest | Mindless | Brain Hack | Unhinged | Dopamine | Send This
  
  [瀑布流 Card Grid]（每行 4-6 列，响应式）
  每个 Card:
    ├── 封面图（游戏截图）
    ├── 游戏标题
    ├── 创作者头像 + 用户名 + 发布时间
    └── 统计：👁 Views | 💬 Comments | ❤️ Likes

[Footer]
  - 社交媒体图标
  - "NADA AI" 品牌
  - Privacy Policy | Terms of Service
```

### 1.3 游戏详情页（`/@{username}/{game-slug}`）
```
[左侧/主区域]
  ├── iframe（游戏运行，占主视口）
  └── 游戏内容全屏运行

[右侧/覆盖层]
  ├── 游戏截图（缩略图）
  ├── 游戏标题
  ├── 创作者信息（头像 + 用户名 + 时间）
  ├── 统计信息（Views + Score/自己的分数）
  └── 操作栏：
      ├── 🔗 分享按钮
      ├── 💬 评论数 (887)
      ├── ❤️ 点赞 (44K)
      └── 🔀 Remix

[底部导航]
  ├── ← 上一个
  └── → 下一个
```

### 1.4 登录/注册页（`/login`）
```
[左半区]
  - Aippy Logo
  - "Sign In" 标题
  - "Don't have an account? Sign Up" 链接
  - [Continue with Google] 按钮
  - [Continue with Apple] 按钮
  - ─── OR ───
  - Email 输入框
  - Password 输入框（含显示/隐藏）
  - "Forgot password?" 链接
  - [Sign In] 按钮
  - 服务条款说明

[右半区]
  - 装饰图片（游戏截图/品牌视觉）
  - "Build What You Feel." 标语
```

---

## 2. 交互细节

### 2.1 Prompt 创建区
- 三个按钮：发送（活跃）、图片上传（登录后可用）、文件上传（登录后可用）
- 快捷 Prompt 以圆角 Tag 形式展示，点击直接填入输入框
- 未登录点击发送 → 弹出登录 Modal（非跳转）

### 2.2 Feed 瀑布流
- 分类 Tab 横向滚动，当前选中高亮
- 每次切换分类加载新数据（非 SPA 路由切换，动态请求）
- Card hover 效果（推断：cursor=pointer 确认）
- 无限滚动加载（实测页面 page=18247，说明是随机翻页而非顺序翻页）

### 2.3 游戏详情页
- 游戏在 iframe 中全屏运行，不可见滚动条
- 右侧信息面板叠加在 iframe 上（绝对定位或 flex 布局）
- 上/下游戏导航箭头在页面底部
- Remix 按钮：一键 Fork 游戏（无需自己创建项目）

### 2.4 Feed 中的特殊卡片
- **推荐创作者卡片**（实测发现）：`Catch the vibe` 版块，展示创作者头像+关注按钮+作品预览
- **Loading 卡片**：内容加载中时显示 loading 占位

---

## 3. 内容标签系统

### 游戏标签（Tags）
标签按类型分层：

**玩法标签**:
- Click, Tap, Drag, Swipe, TapRepeat
- RNG, Physics Sandbox, Turn-based, VS
- Action Reflex, Puzzle Logic, Time Attack

**视觉标签**:
- 3D Interactive Games
- Particle FX, Light Glow, Color Play
- Abstract Geometry, Liquid Motion, Generative Art
- HDR, Bounce Hit

**情绪标签**:
- Satisfying Play, Relax Mood, Exciting
- Dopamine, Mindless, Funny Sound
- Relaxing, Satisfying

**互动类型**:
- Sound Toys, RNG Toys, Generator
- Tracker, Counter

---

## 4. 用户等级系统

| Level | 颜色 | 
|-------|------|
| 1-3 | 基础色（推断） |
| 4 | `#8F4E24`（棕色）|
| 5 | `#BA912A`（金色）|
| 6 | `#BA912A`（金色）|
| 7 | `#A15049`（铜红）|
| 8 | `#A15049`（铜红）|
| 9 | `#629A1B`（绿色）|
| 10 | `#629A1B`（绿色）|
| 11 | `#05A155`（亮绿）|

等级图标：CDN 托管 WebP 图片（`cdn.aippy.ai/uploads/{uuid}.webp`）

---

## 5. 移动端适配

- 导航栏有"Play on mobile"入口（App Store + Google Play 下载）
- iframe 允许 `vibrate`（haptic-feedback）
- 游戏声明 `deviceCapability: ["haptic-feedback", "local-storage"]`
- `allow="vibrate"` iframe 属性（实测 console 有 `Unrecognized feature: 'vibrate'` 警告，浏览器不支持但 iOS App 支持）
- ThinkingData Analytics 支持 ReactNative + Flutter Bridge（说明有原生 App）

---

## 6. SEO & 分享

- 游戏详情页 title: `{游戏名} - Aippy`
- 游戏详情页 URL: `aippy.ai/@{username}/{game-alias}-{shortId}`
- 短 ID 格式：3-4 字母大小写混合（如 `uTG`）
- 支持 `shareUrl`（推测为短链接）

---

## 7. 技术实现关键点（UI 相关）

### iframe 沙箱
```html
<!-- 游戏 iframe 允许的特性（推测） -->
<iframe 
  src="https://{uuid}.aippy.live/?v={ts}"
  allow="vibrate; camera; microphone; gyroscope; accelerometer"
  sandbox="allow-scripts allow-same-origin allow-popups"
/>
```

### 图片处理（Alibaba Cloud OSS）
```
原图: cdn.aippy.ai/asset/{uuid}.png
缩略图: ?x-oss-process=style/thumbnail_middle
头像压缩: ?x-oss-process=style/p
列表大图: ?x-oss-process=image/resize,w_720/sharpen,100
头像小图: ?x-oss-process=image/resize,w_100/sharpen,100
```

### 游戏截图生成
- 服务端自动截图（构建完成后）
- 存储路径：`cdn.aippy.ai/image/screenshot_{uuid}.png`
- 推测使用 Playwright/Puppeteer 无头浏览器截图
