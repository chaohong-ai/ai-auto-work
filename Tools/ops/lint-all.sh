#!/usr/bin/env bash
# 格式化和 lint 所有模块
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FAILED=0

echo "=== Lint All Modules ==="

echo "[1/4] Server (go vet + gofmt)..."
if (cd "$ROOT_DIR/Server" && go vet ./... && test -z "$(gofmt -l .)"); then
  echo "  ✓ Server lint OK"
else
  echo "  ✗ Server lint issues found"
  echo "    Run: cd Backend && gofmt -w ."
  FAILED=1
fi

echo "[2/4] Engine (go vet + gofmt)..."
if (cd "$ROOT_DIR/Engine" && go vet ./... && test -z "$(gofmt -l .)"); then
  echo "  ✓ Engine lint OK"
else
  echo "  ✗ Engine lint issues found"
  echo "    Run: cd Engine && gofmt -w ."
  FAILED=1
fi

echo "[3/4] MCP (eslint)..."
if (cd "$ROOT_DIR/MCP" && npx eslint src/ 2>&1); then
  echo "  ✓ MCP lint OK"
else
  echo "  ✗ MCP lint issues found"
  FAILED=1
fi

echo "[4/4] Client (next lint)..."
if (cd "$ROOT_DIR/Client" && npx next lint 2>&1); then
  echo "  ✓ Client lint OK"
else
  echo "  ✗ Client lint issues found"
  FAILED=1
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "=== All Lint Passed ==="
else
  echo "=== Some Lint Issues Found ==="
  exit 1
fi
