#!/bin/bash
# Unit tests for __parse_claude_rate_limit_wait in cli-trace-helpers.sh
#
# Run: bash .claude/scripts/_test_rate_limit_parser.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stub trace helpers needed by source — avoid network/proxy side effects
ensure_proxy_path="${SCRIPT_DIR}/ensure-proxy.sh"
[ -f "$ensure_proxy_path" ] || { echo "missing $ensure_proxy_path" >&2; exit 1; }

# shellcheck source=cli-trace-helpers.sh
source "${SCRIPT_DIR}/cli-trace-helpers.sh"

PASS=0
FAIL=0
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# assert_wait_in_range <text> <name> <min_seconds> <max_seconds>
#   Asserts the parser returns a number within [min, max].
assert_wait_in_range() {
    local text="$1" name="$2" min="$3" max="$4"
    printf '%s' "$text" > "$TMP"
    local got
    got=$(__parse_claude_rate_limit_wait "$TMP")
    if [ -z "$got" ]; then
        echo "  FAIL  $name — expected wait, got empty"
        FAIL=$((FAIL + 1))
        return
    fi
    if [ "$got" -lt "$min" ] || [ "$got" -gt "$max" ]; then
        echo "  FAIL  $name — wait=${got}s, expected ∈ [${min}, ${max}]"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "  PASS  $name (wait=${got}s)"
    PASS=$((PASS + 1))
}

# assert_no_wait <text> <name>
assert_no_wait() {
    local text="$1" name="$2"
    printf '%s' "$text" > "$TMP"
    local got
    got=$(__parse_claude_rate_limit_wait "$TMP")
    if [ -z "$got" ]; then
        echo "  PASS  $name (no wait)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name — expected empty, got ${got}s"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== rate_limit_parser tests ==="
echo

# 1. Canonical message — within 24h
assert_wait_in_range \
    "You've hit your limit · resets 1am (Asia/Shanghai)" \
    "canonical-1am-shanghai" \
    1 \
    "$((24 * 3600 + 120))"

# 2. PM time
assert_wait_in_range \
    "You've hit your limit · resets 11pm (UTC)" \
    "11pm-UTC" \
    1 \
    "$((24 * 3600 + 120))"

# 3. HH:MM 24h
assert_wait_in_range \
    "Anthropic API: You've hit your usage limit · resets 13:30 (America/Los_Angeles)" \
    "13:30-LA" \
    1 \
    "$((24 * 3600 + 120))"

# 4. HH:MMam
assert_wait_in_range \
    "Quota exhausted. Resets 12:30am (UTC)" \
    "12:30am-UTC" \
    1 \
    "$((24 * 3600 + 120))"

# 5. Generic rate-limit string without time → fallback wait
assert_wait_in_range \
    "Rate limit reached. Try again later." \
    "rate-limit-no-time-fallback" \
    1 \
    1200

# 6. Non-rate-limit error → no wait
assert_no_wait \
    "Error: file not found at /tmp/foo.txt" \
    "non-rate-limit-error"

# 7. Empty input → no wait
assert_no_wait \
    "" \
    "empty-input"

# 8. Network 503 should NOT trigger a wait
assert_no_wait \
    "503 Service Unavailable" \
    "503-not-rate-limit"

# 9. Mixed-case + unicode middle dot
assert_wait_in_range \
    "you've HIT your LIMIT · resets 2pm (Asia/Tokyo)" \
    "mixed-case-tokyo" \
    1 \
    "$((24 * 3600 + 120))"

# 10. "usage limit reached" w/o reset clause → fallback
assert_wait_in_range \
    "claude: usage limit reached. Please try again." \
    "usage-limit-reached-fallback" \
    1 \
    1200

# 11. Real Anthropic absolute-date format: "try again at Apr 14th, 2026 1:50 AM (UTC)"
#     This format historically appeared in CLI output; must NOT degrade to fallback.
#     Use a year far in the future so the date is always > now regardless of test run time.
assert_wait_in_range \
    "You've hit your usage limit. Try again at Apr 14th, 2099 1:50 AM (UTC)" \
    "absolute-date-format-Apr-2099" \
    1 \
    "$((100 * 365 * 86400))"

# 11b. Same format without ordinal suffix
assert_wait_in_range \
    "Hit your usage limit. try again at December 31, 2099 11:59 PM (Asia/Shanghai)" \
    "absolute-date-no-ordinal-Dec-2099" \
    1 \
    "$((100 * 365 * 86400))"

# 11c. Absolute format without timezone (uses local TZ)
assert_wait_in_range \
    "Usage limit reached. Try again at Jul 4th, 2099 12:00 PM" \
    "absolute-date-no-tz-Jul-2099" \
    1 \
    "$((100 * 365 * 86400))"

# 12. CRITICAL High-finding regression: reset clause present but date -d parse fails
#     (e.g. impossible time "25:99" or unrecognized TZ "Mars/Phobos") → MUST return fallback,
#     not empty string. Empty string causes the outer caller to treat it as a non-rate-limit
#     error and abort the auto-work loop.
assert_wait_in_range \
    "You've hit your limit · resets 25:99 (Mars/Phobos)" \
    "unparseable-time-and-tz-falls-back" \
    1 \
    1200

assert_wait_in_range \
    "rate limit hit · resets 99am (NotARealTimezone)" \
    "unparseable-hour-falls-back" \
    1 \
    1200

# 13. Absolute date with garbage internals → fallback
assert_wait_in_range \
    "usage limit hit. Try again at Foobar 99th, 9999 99:99 ZZ (Mars/Phobos)" \
    "unparseable-absolute-date-falls-back" \
    1 \
    1200

echo
echo "=== Format helper tests ==="

assert_format() {
    local secs="$1" expect="$2" name="$3"
    local got
    got=$(__format_wait_secs "$secs")
    if [ "$got" = "$expect" ]; then
        echo "  PASS  $name (${secs}s → ${got})"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name — got '$got', expected '$expect'"
        FAIL=$((FAIL + 1))
    fi
}
assert_format 30    "30s"    "format-seconds"
assert_format 90    "1m30s"  "format-minutes"
assert_format 3600  "1h00m"  "format-hour"
assert_format 7290  "2h01m"  "format-hours-mins"

echo
echo "=== __cli_trace_run retry loop integration ==="

# Stub claude binary in a private dir; AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT=2
# keeps each "wait" short so the test finishes in seconds.
STUB_DIR=$(mktemp -d)
COUNTER_FILE="${STUB_DIR}/counter"
trap 'rm -rf "$STUB_DIR" "$TMP"' EXIT

# Stub: first ${FAIL_COUNT} invocations emit rate-limit (no parseable time → fallback wait),
# subsequent invocations emit OK + exit 0.
# IMPORTANT: the message intentionally does NOT include "resets <time> (<TZ>)"
# so __parse_claude_rate_limit_wait falls back to AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT
# (set to 2s in tests below for speed).
cat > "${STUB_DIR}/claude" <<'STUB'
#!/bin/bash
counter_file="${STUB_COUNTER_FILE:-/dev/null}"
fail_count="${STUB_FAIL_COUNT:-2}"
n=0
if [ -f "$counter_file" ]; then
    n=$(cat "$counter_file" 2>/dev/null || echo 0)
fi
n=$((n + 1))
echo "$n" > "$counter_file" 2>/dev/null || true
if [ "$n" -le "$fail_count" ]; then
    # No "resets X (TZ)" clause — parser will return the FALLBACK_WAIT value.
    echo "You've hit your usage limit. Try again later."
    exit 1
fi
echo "OK from stub claude (call #$n)"
exit 0
STUB
chmod +x "${STUB_DIR}/claude"

# 1. Default = unbounded retry: succeeds after N rate-limit hits (keep N small + tiny waits for speed)
echo
echo "  test: default unbounded retry succeeds after 2 rate-limit hits"
> "$COUNTER_FILE"
output=$(PATH="${STUB_DIR}:${PATH}" \
    STUB_COUNTER_FILE="$COUNTER_FILE" \
    STUB_FAIL_COUNT=2 \
    AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT=2 \
    AUTO_WORK_RATE_LIMIT_BUFFER=0 \
    bash -c "source '${SCRIPT_DIR}/cli-trace-helpers.sh'; cli_call 'test prompt'" 2>&1)
ec=$?
calls=$(cat "$COUNTER_FILE")
if [ $ec -eq 0 ] && [ "$calls" = "3" ] && echo "$output" | grep -q "OK from stub claude"; then
    echo "  PASS  unbounded-retry-success (exit=$ec, total_calls=$calls)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  unbounded-retry-success (exit=$ec, calls=$calls, expected exit=0 calls=3)"
    echo "$output" | head -10 | sed 's/^/         /'
    FAIL=$((FAIL + 1))
fi

# 2. MAX_RETRIES=1 caps after one retry → returns non-zero
echo
echo "  test: AUTO_WORK_RATE_LIMIT_MAX_RETRIES=1 gives up after 1 retry"
> "$COUNTER_FILE"
output=$(PATH="${STUB_DIR}:${PATH}" \
    STUB_COUNTER_FILE="$COUNTER_FILE" \
    STUB_FAIL_COUNT=99 \
    AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT=2 \
    AUTO_WORK_RATE_LIMIT_BUFFER=0 \
    AUTO_WORK_RATE_LIMIT_MAX_RETRIES=1 \
    bash -c "source '${SCRIPT_DIR}/cli-trace-helpers.sh'; cli_call 'test prompt'" 2>&1)
ec=$?
calls=$(cat "$COUNTER_FILE")
if [ $ec -ne 0 ] && [ "$calls" = "2" ]; then
    echo "  PASS  max-retries-cap (exit=$ec, total_calls=$calls)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  max-retries-cap (exit=$ec, total_calls=$calls, expected exit≠0 and calls=2)"
    echo "$output" | tail -10 | sed 's/^/         /'
    FAIL=$((FAIL + 1))
fi

# 3. AUTO_WORK_RATE_LIMIT_DISABLE=1 → no retry at all
echo
echo "  test: AUTO_WORK_RATE_LIMIT_DISABLE=1 returns immediately"
> "$COUNTER_FILE"
output=$(PATH="${STUB_DIR}:${PATH}" \
    STUB_COUNTER_FILE="$COUNTER_FILE" \
    STUB_FAIL_COUNT=99 \
    AUTO_WORK_RATE_LIMIT_DISABLE=1 \
    bash -c "source '${SCRIPT_DIR}/cli-trace-helpers.sh'; cli_call 'test prompt'" 2>&1)
ec=$?
calls=$(cat "$COUNTER_FILE")
if [ $ec -ne 0 ] && [ "$calls" = "1" ]; then
    echo "  PASS  rate-limit-disabled (exit=$ec, total_calls=$calls)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  rate-limit-disabled (exit=$ec, total_calls=$calls, expected exit≠0 and calls=1)"
    FAIL=$((FAIL + 1))
fi

# 3b. AUTO_WORK_RATE_LIMIT_MAX_WAIT caps individual sleep without giving up
echo
echo "  test: MAX_WAIT=1 truncates a long fallback wait but still retries"
> "$COUNTER_FILE"
output=$(PATH="${STUB_DIR}:${PATH}" \
    STUB_COUNTER_FILE="$COUNTER_FILE" \
    STUB_FAIL_COUNT=2 \
    AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT=600 \
    AUTO_WORK_RATE_LIMIT_BUFFER=0 \
    AUTO_WORK_RATE_LIMIT_MAX_WAIT=1 \
    bash -c "source '${SCRIPT_DIR}/cli-trace-helpers.sh'; cli_call 'test prompt'" 2>&1)
ec=$?
calls=$(cat "$COUNTER_FILE")
if [ $ec -eq 0 ] && [ "$calls" = "3" ]; then
    echo "  PASS  max-wait-truncates (exit=$ec, total_calls=$calls)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  max-wait-truncates (exit=$ec, total_calls=$calls, expected exit=0 calls=3)"
    echo "$output" | tail -10 | sed 's/^/         /'
    FAIL=$((FAIL + 1))
fi

# 4. Non-rate-limit failure: stub returns 1 with unrelated message → no retry
cat > "${STUB_DIR}/claude" <<'STUB'
#!/bin/bash
counter_file="${STUB_COUNTER_FILE:-/dev/null}"
n=0
[ -f "$counter_file" ] && n=$(cat "$counter_file" 2>/dev/null || echo 0)
echo "$((n + 1))" > "$counter_file" 2>/dev/null || true
echo "Some unrelated error: file not found"
exit 1
STUB
chmod +x "${STUB_DIR}/claude"

echo
echo "  test: non-rate-limit failure returns immediately without retry"
output=$(PATH="${STUB_DIR}:${PATH}" \
    STUB_COUNTER_FILE="$COUNTER_FILE" \
    AUTO_WORK_RATE_LIMIT_FALLBACK_WAIT=2 \
    bash -c "> '$COUNTER_FILE'; source '${SCRIPT_DIR}/cli-trace-helpers.sh'; cli_call 'test prompt'" 2>&1)
ec=$?
calls=$(cat "$COUNTER_FILE")
if [ $ec -ne 0 ] && [ "$calls" = "1" ]; then
    echo "  PASS  non-rate-limit-no-retry (exit=$ec, total_calls=$calls)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  non-rate-limit-no-retry (exit=$ec, total_calls=$calls, expected exit≠0 and calls=1)"
    FAIL=$((FAIL + 1))
fi

echo
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
