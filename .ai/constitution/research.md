# 宪法详细规则：调研（Research）信息质量

> 本文件是 `.ai/constitution.md` 关于调研方法与信息质量的详细展开，仅在执行 `research:do` / `research:review` / `research:loop` 或任何写入 `Docs/Research/*/research-result*.md`、`research-review-report.md` 的工作流时按需加载。
>
> **作用域：** 通用规则，适用于所有 agent（Claude / Codex / 其他）在本仓库开展的任何技术、商业、竞品调研。
>
> **背景来源：** `Docs/Research/kubee-research/` 2026-04-22 review 发现三类系统性缺口——teaser 判定过早、第三方目录页被当成一手来源、竞品规模数字无时点。以下规则把这三个缺口固化为项目级硬约束，避免后续调研重蹈覆辙。

## R1. 产品存在性 / teaser 判定不得依赖静态抓取

**规则**：不得仅凭 `curl` / `WebFetch` / 普通 HTTP 抓取失败、首页文案简陋、无公开截图等弱信号，直接把调研对象定性为「teaser」「未形成真正产品」「未上线」「demo only」。必须先通过以下至少两项硬证据才能下定性结论：

1. 真实浏览器访问（含 JS 渲染）并截取 Network 面板 / 页面截图，注明访问日期；
2. 注册账号后完成一次端到端可生成样例（图片 / 视频 / 文本 / 游戏 / avatar 等产品宣称的主路径），保存产物 URL 或文件；
3. 应用商店 / APK 镜像的元数据（版本号、更新日期、评分、下载量）并与官网主张对比；
4. 社交渠道（Telegram / X / Discord / YouTube）最近 90 天是否存在真实用户生成内容、官方广告投放或生成演示视频。

**下调定性的话术义务**：若以上硬证据暂不可得，结论必须标记为「未验证 / 待实测」并以六级状态（未验证 / 可访问 / 可生成 / 可分享 / 可编辑 / 可导出）分级，禁止用「teaser」「无产品」等二分定性。

**硬检查（`research:review` 阶段）**：review 报告维度 3（信息质量）检查清单须显式追加一条——「是否仅凭静态抓取失败就下定性结论」；命中即判 Critical 并要求补实测。

## R2. 第三方聚合 / AI 工具目录页只能作为线索

**规则**：Aibase、Creati、AITECHFY、Powerusers、OpenTools、Similarweb、ProductHunt、Toolify、FutureTools 等第三方 SEO / 聚合目录页，只能作为「线索来源」（source_type=`third_party`），不得单独支撑以下关键结论：

- 融资状态、估值、轮次（必须官方公告 / 可信媒体）；
- 月访问量 / MAU / DAU / 下载量 / 注册用户（必须 Similarweb 原站 / 商店官方 / 官方披露）；
- 定价 / 套餐 / 功能清单（必须官网 / 商店 / 官方帮助文档）；
- 技术栈 / 架构 / 使用的基础模型（必须 APK 反编译 / bundle 指纹 / 官方技术博客 / 白皮书）。

若关键结论只能拿到第三方目录页证据，则该结论必须标注 `confidence=low` 并在正文显式写出「仅第三方目录页来源，未经官方核验」，或在正文中**取消该结论**、移到「待验证假设」章节。

**多源冲突处理**：同一指标存在多个第三方数值冲突时（例如 Aptoide / APKPure / AppBrain 三家给出不同 APK 大小），必须在报告中列出冲突数据表，不得私自选一个数值上呈。

**硬检查（`research:review` 阶段）**：review 维度 3 检查清单追加——「关键事实（融资 / 规模 / 定价 / 技术栈）是否有第三方目录页以外的来源」；命中「仅第三方」即判 Important，要求补一手证据或降级结论。

## R3. 规模 / 状态数据必须带时点与来源类型

**规则**：所有出现数量级描述的字段（MAU / DAU / 月访问 / 下载量 / 注册用户 / 估值 / 融资额 / 员工数 / 付费率 / 订阅价）必须在同一表格或段落中同时附带：

- `as_of`：数据对应的时点，精度至少到年月（YYYY-MM）；
- `source_type`：来源类型，枚举 `official` / `store` / `press` / `third_party` / `inference`；
- `source_url`：原始证据 URL，若为推断或二手转述必须写出推断链；
- `verified_at`：本调研实际核验日期（YYYY-MM-DD）。

**术语口径（不得混用）**：

| 术语 | 含义 | 允许来源 |
|------|------|----------|
| `traffic` | Similarweb / Powerusers 类站点访问量 | 第三方流量工具 |
| `installs` / `downloads` | 商店或 APK 镜像累计安装 / 下载 | 商店 / APK 镜像 |
| `MAU` / `DAU` | 月 / 日活跃用户 | 官方披露 / 可信媒体 |
| `registered_users` | 注册用户数，不等于活跃 | 官方披露 |

禁止把 `traffic` 说成 `MAU`，禁止把 `installs` 说成 `registered_users`。

**战略变化列义务**：竞品对比表必须包含「当前状态」列，标注最近 12 个月内发生的收购、停服、转型、融资枯竭、监管事件等，避免使用过时估值和旧定位得出结论。

**URL 必须实际支撑所引用事实，同赛道公司数据禁止互套**（kubee-research 2026-04-22 review I2）：仅填写 `source_url` 不够，必须核验 URL 指向的报道 / 公告 / 页面**主体公司名**与所引用指标**逐字对应**。遇到同赛道多家公司数字易混淆的场景（Synthesia / HeyGen / Runway / D-ID 等 AI 视频；Character.AI / Replika / Talkie / PolyAI 等 AI 伴聊；Zepeto / Ready Player Me / Genies 等 Avatar；Rosebud / Chaotix / Aippy / Ludo / Kubee 等 AI Game Creation），`verified_at` 条目必须同时注明**被引 URL 的主体公司名**，确认与本行公司一致；若 URL 讲的是同赛道另一家公司，视为误引 / 幻觉引用，必须立刻撤回并在 `evidence-log.md` 新增「误引修正」行（保留撤回痕迹而非静默删除）。

**硬检查（`research:review` 阶段）**：review 维度 3 / 维度 4 检查清单追加——「规模数字是否带 as_of 与 source_type」「竞品状态是否有近 12 个月更新」「被引 URL 主体公司名是否与所述条目一致（防止 Synthesia / HeyGen 类同赛道互套）」；任一字段缺失或 URL 主体错位即判 Important；若误引已支撑为关键结论（估值 / ARR / 融资轮次）且未撤回，升级为 Critical。

## R4. 报告模板附录要求

凡同时涉及 R1 / R2 / R3 的调研（竞品研究、市场调研、克隆工作量估算），主报告 `research-result.md` 或 `research-result/` 子目录必须包含以下附录文件之一：

- `evidence-log.md`：记录访问日期、URL、截图文件、抓取摘要、是否需要登录、是否 JS 渲染、是否可复现；
- `sources.md`：按 `source_type` 分组列出全部引用 URL，每条注明 `verified_at` 与 `confidence`。

缺附录则 `research:review` 维度 3 直接判 Important。

## 引用关系

- 上游：`.ai/constitution.md` §2「明确性与可观测性」（事实与观点区分）、§4「测试先行」（验证先于结论的思路外延到调研）。
- 下游：`.claude/commands/research/do.md`「搜索质量要求」「禁止事项」段；`.claude/commands/research/review.md` 维度 3 与维度 4 检查清单。

改动本文件时，必须同步检查 `.claude/commands/research/*.md` 是否需要同步收紧。
