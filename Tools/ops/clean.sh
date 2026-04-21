#!/usr/bin/env bash
# 清理构建产物和依赖缓存
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "=== Clean Build Artifacts ==="

# Node modules
if [ -d "$ROOT_DIR/MCP/node_modules" ]; then
  echo "  Removing MCP/node_modules..."
  rm -rf "$ROOT_DIR/MCP/node_modules"
fi

if [ -d "$ROOT_DIR/Frontend/node_modules" ]; then
  echo "  Removing Frontend/node_modules..."
  rm -rf "$ROOT_DIR/Frontend/node_modules"
fi

# TypeScript build output
if [ -d "$ROOT_DIR/MCP/dist" ]; then
  echo "  Removing MCP/dist..."
  rm -rf "$ROOT_DIR/MCP/dist"
fi

# Next.js build output
if [ -d "$ROOT_DIR/Frontend/.next" ]; then
  echo "  Removing Frontend/.next..."
  rm -rf "$ROOT_DIR/Frontend/.next"
fi

# Go build cache (optional)
if [ "${1:-}" = "--deep" ]; then
  echo "  Clearing Go build cache..."
  go clean -cache
fi

# Snapshot data
if [ -d "$ROOT_DIR/Backend/data" ]; then
  echo "  Removing Backend/data/..."
  rm -rf "$ROOT_DIR/Backend/data"
fi

echo ""
echo "=== Clean Complete ==="
echo "Run 'Tools/ops/setup.sh' to reinstall dependencies."
