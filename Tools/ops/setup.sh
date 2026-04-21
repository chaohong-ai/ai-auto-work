#!/usr/bin/env bash
# 一键初始化开发环境：安装所有模块依赖
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
echo "=== GameMaker Dev Setup ==="
echo "Root: $ROOT_DIR"

# Go modules
echo ""
echo "[1/5] Server: go mod tidy..."
(cd "$ROOT_DIR/Backend" && go mod tidy)
echo "  ✓ Server dependencies installed"

echo "[2/5] Engine: go mod tidy..."
(cd "$ROOT_DIR/Engine" && go mod tidy)
echo "  ✓ Engine dependencies installed"

# Node modules
echo "[3/5] MCP: npm install..."
(cd "$ROOT_DIR/MCP" && npm install)
echo "  ✓ MCP dependencies installed"

echo "[4/5] Client: npm install..."
(cd "$ROOT_DIR/Client" && npm install)
echo "  ✓ Client dependencies installed"

# Python
echo "[5/5] CLIP Service: pip install..."
(cd "$ROOT_DIR/Tools/clip-service" && pip install -r requirements.txt)
echo "  ✓ CLIP service dependencies installed"

# Generate config files from examples if they don't exist
if [ -f "$ROOT_DIR/Backend/configs/config.example.yaml" ] && [ ! -f "$ROOT_DIR/Backend/configs/config.yaml" ]; then
  cp "$ROOT_DIR/Backend/configs/config.example.yaml" "$ROOT_DIR/Backend/configs/config.yaml"
  echo "  ✓ Server config.yaml created from example"
fi

if [ -f "$ROOT_DIR/MCP/.env.example" ] && [ ! -f "$ROOT_DIR/MCP/.env" ]; then
  cp "$ROOT_DIR/MCP/.env.example" "$ROOT_DIR/MCP/.env"
  echo "  ✓ MCP .env created from example"
fi

if [ -f "$ROOT_DIR/Frontend/.env.local.example" ] && [ ! -f "$ROOT_DIR/Frontend/.env.local" ]; then
  cp "$ROOT_DIR/Frontend/.env.local.example" "$ROOT_DIR/Frontend/.env.local"
  echo "  ✓ Client .env.local created from example"
fi

echo ""
echo "=== Setup Complete ==="
