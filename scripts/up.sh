#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
PID_FILE="$PROJECT_DIR/.ollama.pid"
LOG_FILE="$PROJECT_DIR/.ollama.log"

# ── Pre-flight ───────────────────────────────────────────────
if ! command -v ollama &>/dev/null; then
    echo "ERROR: ollama is not installed."
    echo "       Run: ./scripts/install.sh"
    exit 1
fi

# Already running?
if curl -sf "http://127.0.0.1:11434/" >/dev/null 2>&1; then
    echo "==> Ollama is already running at http://127.0.0.1:11434"
    echo "    To restart: ./scripts/down.sh && ./scripts/up.sh"
    exit 0
fi

# ── Source environment ───────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# ── Start server ─────────────────────────────────────────────
echo "==> Starting Ollama server (Metal GPU)..."
ollama serve > "$LOG_FILE" 2>&1 &
OLLAMA_PID=$!
echo "$OLLAMA_PID" > "$PID_FILE"

# ── Wait for healthy ────────────────────────────────────────
MAX_WAIT=30
for i in $(seq 1 "$MAX_WAIT"); do
    if curl -sf "http://127.0.0.1:11434/" >/dev/null 2>&1; then
        echo "==> Ollama is ready (PID $OLLAMA_PID, ${i}s)."
        echo ""
        echo "    API:    http://127.0.0.1:11434"
        echo "    Log:    $LOG_FILE"
        echo "    PID:    $PID_FILE"
        echo ""
        echo "    Next:   ./scripts/pull-models.sh"
        exit 0
    fi

    # Make sure process didn't crash
    if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
        echo "ERROR: Ollama process exited unexpectedly."
        echo "       Check log: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi

    printf "\r    waiting... %ds" "$i"
    sleep 1
done

echo ""
echo "ERROR: Ollama did not become healthy within ${MAX_WAIT}s."
echo "       Check log: $LOG_FILE"
echo "       PID: $OLLAMA_PID"
exit 1
