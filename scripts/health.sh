#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$PROJECT_DIR/.ollama.pid"

source "$SCRIPT_DIR/models.conf"

OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT:-11434}"
ISSUES=0

echo "==========================================="
echo "  Health Check"
echo "==========================================="
echo ""

# ── 1. Process status ────────────────────────────────────────
echo "1. Ollama process"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "   Process: running (PID $PID, managed by scripts)"
    else
        echo "   Process: NOT running (stale PID $PID)"
        ISSUES=$((ISSUES + 1))
    fi
elif pgrep -f "ollama serve" >/dev/null 2>&1; then
    PIDS=$(pgrep -f "ollama serve" | tr '\n' ',')
    echo "   Process: running (PID ${PIDS%,}, external — not managed by scripts)"
else
    echo "   Process: NOT running"
    ISSUES=$((ISSUES + 1))
fi
echo ""

# ── 2. API reachability ─────────────────────────────────────
echo "2. API reachability"
if curl -sf "$OLLAMA_URL/" >/dev/null 2>&1; then
    echo "   API: reachable at $OLLAMA_URL"
else
    echo "   API: NOT reachable at $OLLAMA_URL"
    ISSUES=$((ISSUES + 1))
fi
echo ""

# ── 3. GPU / Metal status ───────────────────────────────────
echo "3. GPU acceleration"
GPU_INFO=$(curl -sf "$OLLAMA_URL/api/ps" 2>/dev/null | jq -r '.models[0].details.family // empty' 2>/dev/null || echo "")
if [ -n "$GPU_INFO" ]; then
    echo "   Metal: active (model loaded on GPU)"
else
    echo "   Metal: idle (no model currently loaded — loads on first request)"
fi
echo ""

# ── 4. Model availability ───────────────────────────────────
echo "4. Model availability"
INSTALLED_MODELS=$(curl -sf "$OLLAMA_URL/api/tags" 2>/dev/null | jq -r '.models[].name' 2>/dev/null || echo "")

for model in "${MODELS[@]}"; do
    if echo "$INSTALLED_MODELS" | grep -qF "$model"; then
        SIZE=$(curl -sf "$OLLAMA_URL/api/show" -d "{\"name\": \"$model\"}" 2>/dev/null \
            | jq -r '.details.parameter_size // "?"' 2>/dev/null)
        QUANT=$(curl -sf "$OLLAMA_URL/api/show" -d "{\"name\": \"$model\"}" 2>/dev/null \
            | jq -r '.details.quantization_level // "?"' 2>/dev/null)
        echo "   [installed] $model ($SIZE, $QUANT)"
    else
        BASE_NAME="${model%%:*}"
        MATCH=$(echo "$INSTALLED_MODELS" | grep "^${BASE_NAME}:" | head -1 || true)
        if [ -n "$MATCH" ]; then
            echo "   [installed] $model (resolved as $MATCH)"
        else
            echo "   [missing]   $model"
            ISSUES=$((ISSUES + 1))
        fi
    fi
done
echo ""

# ── 5. Currently loaded models ──────────────────────────────
echo "5. Currently loaded (GPU memory)"
LOADED=$(curl -sf "$OLLAMA_URL/api/ps" 2>/dev/null)
LOADED_COUNT=$(echo "$LOADED" | jq -r '.models | length' 2>/dev/null || echo "0")

if [ "$LOADED_COUNT" -gt 0 ]; then
    echo "$LOADED" | jq -r '.models[] | "   [loaded] \(.name) — \(.size / 1073741824 | floor) GB, expires \(.expires_at)"' 2>/dev/null
else
    echo "   (none — models load on first request)"
fi
echo ""

# ── 6. Model storage ────────────────────────────────────────
echo "6. Model storage"
MODELS_DIR="${OLLAMA_MODELS:-$HOME/.ollama}"
if [ -d "$MODELS_DIR" ]; then
    DISK_USAGE=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1)
    echo "   Path: $MODELS_DIR"
    echo "   Disk: $DISK_USAGE"
else
    echo "   Path: $MODELS_DIR (does not exist yet)"
fi
echo ""

# ── Result ───────────────────────────────────────────────────
echo "==========================================="
if [ $ISSUES -eq 0 ]; then
    echo "  All checks passed."
else
    echo "  $ISSUES issue(s) found."
fi
echo "==========================================="

exit $ISSUES
