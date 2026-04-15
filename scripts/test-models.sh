#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/models.conf"

OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT:-11434}"

# First load with Metal can take 10-30s for large models (weight transfer to GPU)
INFERENCE_TIMEOUT=120

# ── Pre-flight ───────────────────────────────────────────────
echo "==> Testing models at $OLLAMA_URL"
echo ""

if ! curl -sf "$OLLAMA_URL/" >/dev/null 2>&1; then
    echo "ERROR: Ollama API is not reachable at $OLLAMA_URL"
    echo "       Run ./scripts/up.sh first."
    exit 1
fi

# ── Test each model ──────────────────────────────────────────
PASSED=0
FAILED=0
SKIPPED=0

for model in "${MODELS[@]}"; do
    echo "-------------------------------------------"
    echo "  Testing: $model"
    echo "-------------------------------------------"

    # Check model is installed
    if ! curl -sf "$OLLAMA_URL/api/show" -d "{\"name\": \"$model\"}" >/dev/null 2>&1; then
        echo "  SKIP — model not installed. Run ./scripts/pull-models.sh"
        SKIPPED=$((SKIPPED + 1))
        echo ""
        continue
    fi

    # Run inference (non-streaming).
    # Reasoning models (deepseek-r1, qwen3.5) emit a "thinking" field before
    # the visible "response", so we need enough tokens for both.
    echo "  Sending test prompt (timeout ${INFERENCE_TIMEOUT}s)..."
    RESPONSE=$(curl -sf "$OLLAMA_URL/api/generate" \
        --max-time "$INFERENCE_TIMEOUT" \
        -d "{
            \"model\": \"$model\",
            \"prompt\": \"Say hello in one sentence.\",
            \"stream\": false,
            \"options\": { \"num_predict\": 200 }
        }" 2>&1) || true

    if [ -z "$RESPONSE" ]; then
        echo "  FAIL — no response (timeout or connection error)"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # Parse response — check both "response" and "thinking" fields
    # (reasoning models put chain-of-thought in "thinking")
    ANSWER=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    THINKING=$(echo "$RESPONSE" | jq -r '.thinking // empty' 2>/dev/null)
    EVAL_COUNT=$(echo "$RESPONSE" | jq -r '.eval_count // 0' 2>/dev/null)
    TOTAL_NS=$(echo "$RESPONSE" | jq -r '.total_duration // 0' 2>/dev/null)
    EVAL_NS=$(echo "$RESPONSE" | jq -r '.eval_duration // 0' 2>/dev/null)

    # Model produced output if either field is non-empty
    if [ -n "$ANSWER" ] || [ -n "$THINKING" ]; then
        TOTAL_SEC=$(echo "$TOTAL_NS" | awk '{printf "%.1f", $1/1000000000}')
        TPS=$(echo "$EVAL_COUNT $EVAL_NS" | awk '{if ($2>0) printf "%.1f", $1/($2/1000000000); else print "?"}')

        if [ -n "$ANSWER" ]; then
            TRIMMED=$(echo "$ANSWER" | tr '\n' ' ' | head -c 120)
            echo "  PASS — ${EVAL_COUNT} tokens in ${TOTAL_SEC}s (${TPS} tok/s)"
            echo "  Response: ${TRIMMED}"
        else
            TRIMMED=$(echo "$THINKING" | tr '\n' ' ' | head -c 120)
            echo "  PASS — ${EVAL_COUNT} tokens in ${TOTAL_SEC}s (${TPS} tok/s) [reasoning model]"
            echo "  Thinking: ${TRIMMED}..."
        fi
        PASSED=$((PASSED + 1))
    else
        ERROR=$(echo "$RESPONSE" | jq -r '.error // empty' 2>/dev/null)
        echo "  FAIL — ${ERROR:-unknown error}"
        FAILED=$((FAILED + 1))
    fi
    echo ""
done

# ── Summary ──────────────────────────────────────────────────
echo "==========================================="
echo "  Test Summary"
echo "==========================================="
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "  Total:   ${#MODELS[@]}"
echo "==========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi
