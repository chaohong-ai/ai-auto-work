#!/usr/bin/env bash
# 启动基础设施：MongoDB, Redis, Milvus
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Starting Infrastructure ==="
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

echo ""
echo "Waiting for services to be healthy..."

# Wait for MongoDB
echo -n "  MongoDB: "
for i in $(seq 1 30); do
  if docker exec gamemaker-mongo mongosh --eval "db.adminCommand('ping')" &>/dev/null; then
    echo "✓ ready"
    break
  fi
  if [ "$i" -eq 30 ]; then echo "✗ timeout"; fi
  sleep 2
done

# Wait for Redis
echo -n "  Redis: "
for i in $(seq 1 15); do
  if docker exec gamemaker-redis redis-cli ping &>/dev/null; then
    echo "✓ ready"
    break
  fi
  if [ "$i" -eq 15 ]; then echo "✗ timeout"; fi
  sleep 2
done

# Wait for Milvus
echo -n "  Milvus: "
for i in $(seq 1 30); do
  if curl -sf http://localhost:9091/healthz &>/dev/null; then
    echo "✓ ready"
    break
  fi
  if [ "$i" -eq 30 ]; then echo "✗ timeout"; fi
  sleep 2
done

# Wait for Godot Headless
echo -n "  Godot: "
for i in $(seq 1 30); do
  if docker exec gamemaker-godot bash /home/godot/healthcheck.sh &>/dev/null; then
    echo "✓ ready"
    break
  fi
  if [ "$i" -eq 30 ]; then echo "✗ timeout"; fi
  sleep 2
done

echo ""
echo "=== Infrastructure Ready ==="
echo "  MongoDB:  localhost:27017"
echo "  Redis:    localhost:6379"
echo "  Milvus:   localhost:19530"
echo "  Godot:    localhost:6007 (TCP/JSON-RPC)"
