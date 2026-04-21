#!/usr/bin/env bash
# 编译所有模块
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

echo "=== Build All Modules ==="

echo "[1/4] Server (Go)..."
if (cd "$ROOT_DIR/Server" && go build ./...); then
  echo "  ✓ Server build OK"
else
  echo "  ✗ Server build FAILED"
  FAILED=1
fi

echo "[2/4] Engine (Go)..."
if (cd "$ROOT_DIR/Engine" && go build ./...); then
  echo "  ✓ Engine build OK"
else
  echo "  ✗ Engine build FAILED"
  FAILED=1
fi

echo "[3/4] MCP (TypeScript)..."
if (cd "$ROOT_DIR/MCP" && npx tsc --noEmit); then
  echo "  ✓ MCP type check OK"
else
  echo "  ✗ MCP type check FAILED"
  FAILED=1
fi

echo "[4/4] Client (Next.js)..."
if (cd "$ROOT_DIR/Client" && npx tsc --noEmit); then
  echo "  ✓ Client type check OK"
else
  echo "  ✗ Client type check FAILED"
  FAILED=1
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "=== All Builds Passed ==="
else
  echo "=== Some Builds Failed ==="
  exit 1
fi
