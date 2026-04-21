#!/bin/bash
# ensure-proxy.sh — 无头 claude -p / codex 子进程的代理预设
#
# 问题：Claude Code 主会话在启动时如果没有 HTTPS_PROXY 环境变量（例如 Windows
# 下 Clash 只配了 WinINET 注册表代理），Node.js 子进程 `claude -p` 会绕过代理
# 裸连 Anthropic，从受限网络会被返回 HTTP 403 "Request not allowed"，导致
# auto-work 探测失败降级到 MODE_B。
#
# 本脚本幂等地注入 HTTP_PROXY / HTTPS_PROXY：
#   - 用户已显式设置则原样保留
#   - 未设置时尝试探测 127.0.0.1:7890（Clash 默认）；端口开则自动启用，否则不动
#
# 使用：在需要无头调用 claude -p 的编排脚本顶部加一行
#   source "$(dirname "$0")/ensure-proxy.sh"

_ensure_proxy_default_host="127.0.0.1"
_ensure_proxy_default_port="7890"
_ensure_proxy_url="http://${_ensure_proxy_default_host}:${_ensure_proxy_default_port}"

# 仅在两个变量都没设时才自动探测
if [ -z "${HTTPS_PROXY:-}" ] && [ -z "${HTTP_PROXY:-}" ]; then
    if (exec 3<>"/dev/tcp/${_ensure_proxy_default_host}/${_ensure_proxy_default_port}") 2>/dev/null; then
        exec 3<&- 3>&-
        export HTTPS_PROXY="$_ensure_proxy_url"
        export HTTP_PROXY="$_ensure_proxy_url"
        export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,10.*,192.168.*}"
        echo "[ensure-proxy] auto-enabled HTTPS_PROXY=$_ensure_proxy_url (Clash detected)" >&2
    fi
fi

unset _ensure_proxy_default_host _ensure_proxy_default_port _ensure_proxy_url
