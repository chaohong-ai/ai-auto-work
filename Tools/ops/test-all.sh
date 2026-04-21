#!/usr/bin/env bash
# 运行所有模块的测试
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

echo "=== Run All Tests ==="

echo "[1/3] Server (Go test)..."
if (cd "$ROOT_DIR/Server" && go test ./... 2>&1); then
  echo "  ✓ Server tests passed"
else
  echo "  ✗ Server tests failed"
  FAILED=1
fi

echo "[2/3] MCP (Jest)..."
if (cd "$ROOT_DIR/MCP" && npx jest --passWithNoTests 2>&1); then
  echo "  ✓ MCP tests passed"
else
  echo "  ✗ MCP tests failed"
  FAILED=1
fi

echo "[3/3] Client (type check)..."
if (cd "$ROOT_DIR/Client" && npx tsc --noEmit 2>&1); then
  echo "  ✓ Client type check passed"
else
  echo "  ✗ Client type check failed"
  FAILED=1
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "=== All Tests Passed ==="
else
  echo "=== Some Tests Failed ==="
  exit 1
fi
