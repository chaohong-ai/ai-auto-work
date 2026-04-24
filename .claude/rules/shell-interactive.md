# Shell 交互安全规则（headless / no-TTY 场景）

适用场景：auto-work-loop.sh 及其辅助函数中新增任何 `read` 调用时

## 核心约束（不可协商）

<!-- Context Repair: task-01 M2 RECURRING — check_feature_pending_items 连续两轮写入 read 均无 TTY 检测 -->
auto-work-loop.sh 及其辅助函数中的所有 `read` 调用，**必须在前一行加 TTY 检测防护**：

\`\`\`bash
# ✅ 正确：TTY 检测前置
[ -t 0 ] || { echo "[WARN] 非交互模式，跳过 <操作名>，以默认方案继续" >&2; return 0; }
read -r VARIABLE

# ❌ 违规：裸 read，无头模式静默得到空值
read -r VARIABLE
\`\`\`

**禁止**向 auto-work-loop.sh 或辅助函数中添加不带 TTY 检测的裸 `read` 调用。

## 背景

auto-work-loop.sh 同时被两种模式使用：
- **交互式**：用户直接在终端运行，stdin 为真实 TTY
- **无头模式（headless）**：由 `claude -p` 作为子进程调用，stdin 为 `/dev/null` 或管道

无头模式下，裸 `read` 立即得到 EOF，变量为空，脚本以默认值**静默推进**。
feature.md 中的待确认项（鉴权策略、数据模型等）在用户零感知的情况下以默认方案落地，
下游 plan/develop 基于未确认假设运行，决策静默丢失且无任何 WARN 日志。

## 写 `read` 前的自检清单

1. 前一行是否有 `[ -t 0 ] || { ...; return 0; }`？
2. WARN 信息是否说明了"跳过了什么"（不是静默跳过）？
3. 跳过后脚本是否以合理默认行为继续？

三条全部满足才可提交。

## codex preflight 实测调用须加超时

auto-work-loop.sh 中调用 `codex exec` 做 API 可达性实测时，必须加 `timeout`：

\`\`\`bash
# ✅ 正确
timeout 30 codex exec --full-auto "reply OK" > "$codex_tmp" 2>&1
rc=$?; [ "$rc" -eq 124 ] && { echo "[WARN] codex preflight 超时，降级 CODEX_AVAILABLE=0" >&2; CODEX_AVAILABLE=0; }

# ❌ 违规：裸调用，挂起时整个 auto-work 无限等待
codex exec --full-auto "reply OK" > "$codex_tmp" 2>&1
\`\`\`

根因（M4 task-01）：preflight 无超时在网络延迟高或服务端挂起时阻塞 auto-work 启动。
