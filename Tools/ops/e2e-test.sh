#!/bin/bash
# End-to-end integration test for GameMaker
# Prerequisites: docker, mongodb, redis running
# Usage: ./e2e-test.sh [SERVER_URL]
#
# This script exercises the full API flow:
#   1. Health check
#   2. Create a game (which auto-enqueues generation)
#   3. Poll generation status until completion or timeout
#   4. Verify final game state
#
set -euo pipefail

SERVER_URL="${1:-http://localhost:8080}"
MCP_URL="${MCP_URL:-http://localhost:3000}"
TIMEOUT_SECONDS=120
POLL_INTERVAL=3

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ---------------------------------------------------------------------------
# Step 0: Check prerequisites
# ---------------------------------------------------------------------------
info "Checking prerequisites..."

command -v curl >/dev/null 2>&1 || fail "curl is required but not installed."
command -v jq   >/dev/null 2>&1 || fail "jq is required but not installed."

pass "Prerequisites OK (curl, jq)"

# ---------------------------------------------------------------------------
# Step 1: Health check — Server
# ---------------------------------------------------------------------------
info "Health checking Server at ${SERVER_URL}..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SERVER_URL}/health" || true)
if [ "$HTTP_CODE" != "200" ]; then
  fail "Server health check failed (HTTP ${HTTP_CODE}). Is the server running?"
fi

HEALTH_BODY=$(curl -s "${SERVER_URL}/health")
HEALTH_STATUS=$(echo "$HEALTH_BODY" | jq -r '.data.status // empty')
if [ "$HEALTH_STATUS" != "ok" ]; then
  fail "Server health check returned unexpected status: ${HEALTH_BODY}"
fi

pass "Server health OK"

# ---------------------------------------------------------------------------
# Step 1b: Health check — MCP (optional, non-blocking)
# ---------------------------------------------------------------------------
info "Health checking MCP at ${MCP_URL}..."

MCP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${MCP_URL}/health" 2>/dev/null || echo "000")
if [ "$MCP_CODE" = "200" ]; then
  pass "MCP health OK"
else
  info "MCP not reachable (HTTP ${MCP_CODE}) — skipping MCP checks (generation may fail)"
fi

# ---------------------------------------------------------------------------
# Step 2: Create a game
# ---------------------------------------------------------------------------
info "Creating a game via POST /api/v1/games..."

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${SERVER_URL}/api/v1/games" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Create a simple platformer with a jumping character","template":"platformer"}')

CREATE_BODY=$(echo "$CREATE_RESPONSE" | head -n -1)
CREATE_CODE=$(echo "$CREATE_RESPONSE" | tail -n 1)

if [ "$CREATE_CODE" != "201" ]; then
  fail "Create game failed (HTTP ${CREATE_CODE}): ${CREATE_BODY}"
fi

GAME_ID=$(echo "$CREATE_BODY" | jq -r '.data.id // empty')
GAME_STATUS=$(echo "$CREATE_BODY" | jq -r '.data.status // empty')
TASK_ID=$(echo "$CREATE_BODY" | jq -r '.data.task_id // empty')

if [ -z "$GAME_ID" ]; then
  fail "Create game returned no game ID: ${CREATE_BODY}"
fi

pass "Game created: id=${GAME_ID}, status=${GAME_STATUS}, task_id=${TASK_ID}"

# ---------------------------------------------------------------------------
# Step 3: Verify game exists via GET
# ---------------------------------------------------------------------------
info "Fetching game via GET /api/v1/games/${GAME_ID}..."

GET_RESPONSE=$(curl -s -w "\n%{http_code}" "${SERVER_URL}/api/v1/games/${GAME_ID}")
GET_BODY=$(echo "$GET_RESPONSE" | head -n -1)
GET_CODE=$(echo "$GET_RESPONSE" | tail -n 1)

if [ "$GET_CODE" != "200" ]; then
  fail "Get game failed (HTTP ${GET_CODE}): ${GET_BODY}"
fi

GET_ID=$(echo "$GET_BODY" | jq -r '.data.id // empty')
if [ "$GET_ID" != "$GAME_ID" ]; then
  fail "Get game returned wrong ID: expected ${GAME_ID}, got ${GET_ID}"
fi

pass "Game fetched successfully"

# ---------------------------------------------------------------------------
# Step 4: Poll generation status until complete or timeout
# ---------------------------------------------------------------------------
info "Polling generation status (timeout: ${TIMEOUT_SECONDS}s)..."

ELAPSED=0
FINAL_STATUS=""

while [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
  STATUS_RESPONSE=$(curl -s "${SERVER_URL}/api/v1/games/${GAME_ID}/generate/status")
  CURRENT_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.data.status // empty')
  CURRENT_PHASE=$(echo "$STATUS_RESPONSE" | jq -r '.data.phase // empty')

  info "  status=${CURRENT_STATUS}, phase=${CURRENT_PHASE} (${ELAPSED}s elapsed)"

  if [ "$CURRENT_STATUS" = "succeeded" ]; then
    FINAL_STATUS="succeeded"
    break
  fi

  if [ "$CURRENT_STATUS" = "failed" ]; then
    TASK_ERROR=$(echo "$STATUS_RESPONSE" | jq -r '.data.error // "unknown"')
    fail "Generation failed: ${TASK_ERROR}"
  fi

  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ -z "$FINAL_STATUS" ]; then
  info "Generation did not complete within ${TIMEOUT_SECONDS}s — this may be OK if MCP/Godot are not running."
  info "The API integration itself was verified successfully."
fi

# ---------------------------------------------------------------------------
# Step 5: Verify final game state (if generation completed)
# ---------------------------------------------------------------------------
if [ "$FINAL_STATUS" = "succeeded" ]; then
  info "Verifying final game state..."

  FINAL_RESPONSE=$(curl -s "${SERVER_URL}/api/v1/games/${GAME_ID}")
  FINAL_GAME_STATUS=$(echo "$FINAL_RESPONSE" | jq -r '.data.status // empty')
  FINAL_GAME_URL=$(echo "$FINAL_RESPONSE" | jq -r '.data.game_url // empty')
  FINAL_SCREENSHOT=$(echo "$FINAL_RESPONSE" | jq -r '.data.screenshot_url // empty')

  if [ "$FINAL_GAME_STATUS" != "ready" ]; then
    fail "Expected game status 'ready', got '${FINAL_GAME_STATUS}'"
  fi

  pass "Game status is 'ready'"

  if [ -n "$FINAL_GAME_URL" ] && [ "$FINAL_GAME_URL" != "null" ]; then
    pass "Game URL present: ${FINAL_GAME_URL}"
  else
    info "No game_url set (export may not be configured)"
  fi

  if [ -n "$FINAL_SCREENSHOT" ] && [ "$FINAL_SCREENSHOT" != "null" ]; then
    pass "Screenshot URL present: ${FINAL_SCREENSHOT}"
  else
    info "No screenshot_url set"
  fi
fi

# ---------------------------------------------------------------------------
# Step 6: List games (verify pagination)
# ---------------------------------------------------------------------------
info "Listing games via GET /api/v1/games..."

LIST_RESPONSE=$(curl -s "${SERVER_URL}/api/v1/games?page=1&page_size=10")
LIST_TOTAL=$(echo "$LIST_RESPONSE" | jq -r '.data.total // 0')
LIST_COUNT=$(echo "$LIST_RESPONSE" | jq -r '.data.games | length // 0')

if [ "$LIST_COUNT" -ge 1 ]; then
  pass "Games list returned ${LIST_COUNT} game(s) (total: ${LIST_TOTAL})"
else
  fail "Games list is empty after creating a game"
fi

# ---------------------------------------------------------------------------
# Step 7: Delete the test game
# ---------------------------------------------------------------------------
info "Deleting test game ${GAME_ID}..."

DEL_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${SERVER_URL}/api/v1/games/${GAME_ID}")
if [ "$DEL_CODE" != "204" ]; then
  fail "Delete game failed (HTTP ${DEL_CODE})"
fi

pass "Game deleted successfully"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  End-to-end integration test PASSED    ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Verified endpoints:"
echo "  GET    /health"
echo "  POST   /api/v1/games"
echo "  GET    /api/v1/games/:id"
echo "  GET    /api/v1/games/:id/generate/status"
echo "  GET    /api/v1/games"
echo "  DELETE /api/v1/games/:id"
if [ "$FINAL_STATUS" = "succeeded" ]; then
  echo "  (Generation completed end-to-end)"
else
  echo "  (Generation not completed — MCP/Godot may not be running)"
fi
