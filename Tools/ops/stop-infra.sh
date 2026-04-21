#!/usr/bin/env bash
# 停止基础设施
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Stopping Infrastructure ==="
docker compose -f "$SCRIPT_DIR/docker-compose.yml" down
echo "=== Infrastructure Stopped ==="
