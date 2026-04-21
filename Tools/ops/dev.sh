#!/usr/bin/env bash
# 启动所有开发服务器（并行运行）
# 用法: ./dev.sh [all|server|mcp|client|clip]
# 默认启动全部
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${1:-all}"

cleanup() {
  echo ""
  echo "Shutting down all dev servers..."
  kill $(jobs -p) 2>/dev/null || true
  wait
  echo "Done."
}
trap cleanup EXIT INT TERM

start_server() {
  echo "[Server] Starting Go backend on :8080..."
  (cd "$ROOT_DIR/Server" && go run cmd/api/main.go) &
}

start_mcp() {
  echo "[MCP] Starting TypeScript MCP server..."
  (cd "$ROOT_DIR/MCP" && npm run dev) &
}

start_client() {
  echo "[Client] Starting Next.js dev server on :3000..."
  (cd "$ROOT_DIR/Client" && npm run dev) &
}

start_clip() {
  echo "[CLIP] Starting CLIP service on :8100..."
  (cd "$ROOT_DIR/Tools/clip-service" && python -m uvicorn main:app --host 0.0.0.0 --port 8100) &
}

echo "=== GameMaker Dev Servers ==="

case "$TARGET" in
  all)
    start_server
    start_mcp
    start_client
    start_clip
    ;;
  server)  start_server ;;
  mcp)     start_mcp ;;
  client)  start_client ;;
  clip)    start_clip ;;
  *)
    echo "Usage: $0 [all|server|mcp|client|clip]"
    exit 1
    ;;
esac

echo ""
echo "All requested services started. Press Ctrl+C to stop."
wait
